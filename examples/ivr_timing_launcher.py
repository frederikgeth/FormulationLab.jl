"""Authorization-bound launcher for the finite, source-pinned timing campaign.

inspect launches a waiting Julia process to capture/verify its runtime, without
building or solving a network. run requires a frozen scope plus a separate
explicit human authorization record. This tool never grants that authorization.
"""
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import secrets
import subprocess
import sys
import time

sys.dont_write_bytecode = True
import ivr_timing_isolation as isolation


def require(ok, message):
    if not ok:
        raise ValueError(message)


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def load_checked(path, expected):
    data = Path(path).read_bytes()
    require(hashlib.sha256(data).hexdigest() == expected, f'changed file: {path}')
    return json.loads(data)


def save(path, data):
    path = Path(path)
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_text(json.dumps(data, indent=2, allow_nan=False) + '\n')
    temporary.replace(path)


def check_files(files):
    for path, digest in files.items():
        require(sha(path) == digest, f'changed frozen bytes: {path}')


def verify_runtime(runtime, expected=None):
    require(runtime.get('schema') == 'FormulationLab.timing_runtime.v1', 'unknown runtime schema')
    require(runtime['julia_threads'] == runtime['blas_threads'] == 1, 'runtime thread settings')
    check_files(runtime['files_sha256'])
    for path, target in runtime['path_aliases'].items():
        require(str(Path(path).resolve()) == target, f'runtime path alias changed: {path}')
    for root, names in runtime['trees'].items():
        actual = []
        for directory, dirs, files in os.walk(root, followlinks=False):
            dirs[:] = [d for d in dirs if d not in ('.git', '__pycache__')]
            require(not any((Path(directory)/d).is_symlink() for d in dirs), 'runtime directory symlink changed')
            actual += [str((Path(directory)/name).relative_to(root)) for name in files]
        require(sorted(actual) == names, f'runtime tree membership changed: {root}')
    if expected is not None:
        # Full equality includes loaded caches/images, platform, selected artifact
        # identities and effective environment; no silent runtime migration.
        require(runtime == expected, 'loaded runtime differs from execution freeze')


def worker_environment():
    env = os.environ.copy()
    env.update(JULIA_LOAD_PATH='@:@stdlib', JULIA_NUM_THREADS='1', JULIA_PKG_OFFLINE='true',
               OPENBLAS_NUM_THREADS='1', OMP_NUM_THREADS='1', VECLIB_MAXIMUM_THREADS='1',
               PYTHONDONTWRITEBYTECODE='1')
    return env


def python_identity():
    return dict(executable=str(Path(sys.executable).resolve()), version=sys.version,
                platform=platform.platform())


def authorize(record, freeze_digest, jobs, output):
    require(record.get('schema') == 'FormulationLab.timing_authorization.v1' and
            record.get('authorized') is True, 'explicit human timing authorization is required')
    require(record.get('freeze_sha256') == freeze_digest, 'authorization is for a different freeze')
    require(isinstance(record.get('human_instruction_reference'), str) and
            record['human_instruction_reference'].strip(), 'human authorization reference required')
    require(Path(record['output']).resolve() == Path(output).resolve(), 'authorization output differs')
    selected = record.get('jobs')
    require(isinstance(selected, list) and selected and len(set(selected)) == len(selected) and
            set(selected).issubset(jobs), 'authorization job scope is invalid')
    require(selected == [key for key in jobs if key in set(selected)], 'authorization must preserve frozen job order')
    # Both prospectively declared batches must remain together for each contrast.
    identities = {}
    for key in selected:
        j = jobs[key]['admission']
        identity = tuple(j[k] for k in ('family', 'id', 'workload', 'contrast'))
        identities.setdefault(identity, set()).add(j['batch'])
    require(all(b == {'exploration', 'confirmation'} for b in identities.values()),
            'authorization must include both batches of each selected comparison')
    return selected


def bootstrap(command):
    # Same PID survives exec. No Julia process starts before the initial monitor
    # query, avoiding the race between Popen returning and registering its PID.
    require(sys.stdin.readline().strip() == 'exec', 'bootstrap was not released')
    require(isinstance(command, list) and command and all(isinstance(x, str) for x in command), 'invalid command')
    os.execvpe(command[0], command, os.environ)


def launch_one(job_path, job_digest, environment, julia, folder, *, mode='inspect', expected_runtime=None,
               authorization=None, freeze_digest=None, authorization_digest=None,
               interval_s=0.2, max_gap_s=1.0, ready_timeout_s=900, worker_timeout_s=21600,
               pre_release=None):
    require(mode in ('inspect', 'native'), 'unknown launch mode')
    require(mode != 'native' or (authorization is not None and expected_runtime is not None and
            freeze_digest is not None and authorization_digest is not None), 'native launcher requires frozen authorization')
    job = load_checked(job_path, job_digest)
    folder = Path(folder).resolve()
    if mode == 'native':
        require(authorization.get('schema') == 'FormulationLab.timing_authorization.v1' and
                authorization.get('authorized') is True and authorization.get('freeze_sha256') == freeze_digest and
                isinstance(authorization.get('human_instruction_reference'), str) and
                authorization['human_instruction_reference'].strip() and
                Path(authorization['output']).resolve() == folder.parent and
                folder.name in authorization.get('jobs', []), 'native job is outside explicit authorization')
    protected = [Path(__file__).resolve().parents[1], Path(job['admission']['source_archive']),
                 Path(job['admission']['inputs']['preparation']).parent]
    require(not folder.exists() and all(not folder.is_relative_to(p.resolve()) for p in protected),
            'launcher output must be new and outside protected directories')
    folder.mkdir(parents=True)
    ready_path, permit_path = folder/'READY.json', folder/'PERMIT.json'
    worker = Path(__file__).with_name('ivr_timing_worker.jl').resolve()
    command = [str(julia), f'--project={Path(environment).resolve()}', '--startup-file=no', '--threads=1',
               str(worker), str(Path(job_path).resolve()), job_digest, str(folder/'result'), str(ready_path), mode, str(permit_path)]
    process = monitor = None
    failure = None
    try:
        with (folder/'WORKER.log').open('w') as log:
            process = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), '_bootstrap', json.dumps(command)],
                stdin=subprocess.PIPE, stdout=log, stderr=subprocess.STDOUT, text=True, env=worker_environment())
            monitor = isolation.Monitor(dict(pid=process.pid, parent_pid=os.getpid()), interval_s=interval_s, max_gap_s=max_gap_s)
            monitor.start()
            initial = monitor.observations[0]
            require(initial['error'] is None and not initial['julia_processes'], 'initial process isolation failed')
            process.stdin.write('exec\n'); process.stdin.flush()
            deadline = time.monotonic() + ready_timeout_s
            while not ready_path.exists():
                require(process.poll() is None, 'worker exited before readiness; inspect WORKER.log')
                require(time.monotonic() < deadline, 'worker readiness timed out')
                time.sleep(0.05)
            ready = json.loads(ready_path.read_text())
            require(ready['schema'] == 'FormulationLab.waiting_timing_worker.v1' and ready['pid'] == process.pid and
                    ready['parent_pid'] == os.getpid() and ready['job_sha256'] == job_digest and
                    ready['mode'] == mode and ready['optimizer_invoked'] is False, 'invalid worker readiness packet')
            verify_runtime(ready['runtime'], expected_runtime)
            # A closed-prefix audit is used only as a release guard. The actual
            # monitor stays open and continues through worker termination.
            monitor_prefix = isolation.audit(list(monitor.observations), monitor.expected_worker, monitor.max_gap_ns, closed=True)
            require(monitor_prefix['admitted'], 'isolation failed before worker release')
            if pre_release is not None:
                pre_release()
            nonce = secrets.token_hex(24)
            if mode == 'native':
                save(permit_path, dict(schema='FormulationLab.native_launch_permit.v1', authorized=True,
                    worker_pid=process.pid, launcher_pid=os.getpid(), job_sha256=job_digest,
                    freeze_sha256=freeze_digest, authorization_sha256=authorization_digest, nonce=nonce))
            process.stdin.write(json.dumps(dict(command='run', nonce=nonce)) + '\n');process.stdin.flush()
            process.stdin.close()
            require(process.wait(timeout=worker_timeout_s) == 0, 'worker failed; retain its complete log and partial report')
    except BaseException as exc:
        failure = f'{type(exc).__name__}: {exc}'
        # Terminate only this confirmed child, never any unrelated Julia job.
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill();process.wait()
        raise
    finally:
        if monitor is not None and monitor._thread is not None and not monitor.closed:
            result = monitor.stop()
            save(folder/'ISOLATION.json', dict(observations=monitor.observations,
                expected_worker=monitor.expected_worker, max_gap_ns=monitor.max_gap_ns, closed=monitor.closed, audit=result))
        save(folder/'EXIT.json', dict(mode=mode, worker_pid=None if process is None else process.pid,
            exit_code=None if process is None else process.poll(), failure=failure))
    ready = json.loads(ready_path.read_text())
    if mode == 'native':
        verify_runtime(json.loads((folder/'result/RUNTIME_AFTER.json').read_text()), expected_runtime)
    return ready


def run_campaign(freeze_path, freeze_digest, authorization_path, output):
    freeze = load_checked(freeze_path, freeze_digest)
    require(freeze.get('schema') == 'FormulationLab.native_execution_freeze.v1' and
            freeze.get('execution_ready') is True, 'execution freeze is not ready')
    jobs = {key: load_checked(item['path'], item['sha256']) for key, item in freeze['jobs'].items()}
    auth_digest = sha(authorization_path)
    authorization = load_checked(authorization_path, auth_digest)
    selected = authorize(authorization, freeze_digest, jobs, output)
    require(not Path(output).exists(), 'campaign output already exists; authorization is not reusable there')
    require(python_identity() == freeze['python_identity'], 'launcher Python/platform identity changed')
    check_files(freeze['protected_files_sha256'])
    runtimes = {key: load_checked(item['path'], item['sha256']) for key, item in freeze['runtimes'].items()}
    for runtime in runtimes.values():
        verify_runtime(runtime)
    output = Path(output).resolve();output.mkdir(parents=True)
    reports, traces = {}, {}
    summary = dict(schema='FormulationLab.native_campaign_run.v1', freeze_sha256=freeze_digest,
        authorization_sha256=auth_digest, selected_jobs=selected, admitted=False, pending_job=None, error=None)
    save(output/'STATE.json', summary)
    try:
        for key in selected:
            summary['pending_job'] = key;save(output/'STATE.json', summary)
            item = freeze['jobs'][key];role = jobs[key]['admission']['freeze']
            launch_one(item['path'], item['sha256'], freeze['environments'][role], runtimes[role]['executable'], output/key,
                mode='native', expected_runtime=runtimes[role], authorization=authorization,
                freeze_digest=freeze_digest, authorization_digest=auth_digest,
                pre_release=lambda: check_files(freeze['protected_files_sha256']), **freeze['monitor_settings'])
            reports[key] = json.loads((output/key/'result/REPORT.json').read_text())
            traces[key] = json.loads((output/key/'ISOLATION.json').read_text())
            # Once contamination occurs, stop launching more jobs and retain all
            # prior outcomes as an incomplete, excluded campaign, never a subset.
            require(traces[key]['audit']['admitted'], 'campaign isolation failed')
            summary['pending_job'] = None;save(output/'STATE.json', summary)
        check_files(freeze['protected_files_sha256'])
        admission = isolation.audit_campaign(reports, traces, {key: jobs[key] for key in selected})
        save(output/'ADMISSION.json', admission)
        summary['admitted'] = admission['admitted']
    except BaseException as exc:
        summary['error'] = f'{type(exc).__name__}: {exc}'
        raise
    finally:
        save(output/'STATE.json', summary)
    return summary


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '_bootstrap':
        bootstrap(json.loads(sys.argv[2]))
    else:
        parser = argparse.ArgumentParser(description=__doc__)
        commands = parser.add_subparsers(dest='command', required=True)
        inspect = commands.add_parser('inspect')
        for name in ('job', 'job_sha256', 'environment', 'julia', 'output'):
            inspect.add_argument(name)
        run = commands.add_parser('run')
        for name in ('freeze', 'freeze_sha256', 'authorization', 'output'):
            run.add_argument(name)
        args = parser.parse_args()
        if args.command == 'inspect':
            result = launch_one(args.job, args.job_sha256, args.environment, args.julia, args.output)
            print(json.dumps(dict(mode='inspect', optimizer_invoked=False, worker_pid=result['pid'])))
        else:
            print(json.dumps(run_campaign(args.freeze, args.freeze_sha256, args.authorization, args.output)))
