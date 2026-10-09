"""Freeze reviewed jobs, held-worker runtime captures and launcher sources.

This prepares reproducible execution; it neither authorizes nor launches native
timing. The generated authorization template is deliberately false and unbound to
any output until a human explicitly authorizes a concrete scope.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
import ivr_timing_launcher as L
import ivr_timing_isolation as I

HELPERS = ('ivr_timing_launcher.py', 'ivr_timing_isolation.py', 'ivr_timing_worker.jl',
           'ivr_timing_runtime.jl', 'ivr_timing_controller.jl', 'ivr_timing_adapter.jl',
           'ivr_native_timer.jl', 'prepare_ivr_execution_freeze.py')


def prepare(job_manifest_path, job_manifest_digest, inspections, output):
    output = Path(output).resolve()
    L.require(not output.exists(), 'new freeze output directory required')
    L.require(not output.is_relative_to(Path(__file__).resolve().parents[1]), 'freeze evidence must be outside Git repository')
    manifest = L.load_checked(job_manifest_path, job_manifest_digest)
    L.require(manifest['schema'] == 'FormulationLab.native_timing_jobs.v1' and
              manifest['timing_authorized'] is False and manifest['optimizer_invoked'] is False,
              'authenticated preparation-only job manifest required')
    ledger = L.load_checked(manifest['ledger'], manifest['ledger_sha256'])
    protected = {str(Path(job_manifest_path).resolve()): job_manifest_digest,
                 manifest['ledger']: manifest['ledger_sha256'], **ledger['evidence_sha256']}
    jobs = {}
    for key, digest in manifest['jobs'].items():
        L.require(Path(key).name == key, 'unsafe job identifier')
        path = Path(job_manifest_path).parent/key
        job = L.load_checked(path, digest)
        L.require(job['admission'] == ledger['jobs'][job['job_index']-1], 'job admission differs from ledger')
        for root in (job['admission']['source_archive'], Path(job['admission']['inputs']['preparation']).parent):
            L.require(not output.is_relative_to(Path(root).resolve()), 'freeze output inside protected input/source')
        jobs[key] = dict(path=str(path.resolve()), sha256=digest)
        protected[str(path.resolve())] = digest
    runtime_data, environments, summaries = {}, {}, {}
    for role in ('B', 'C'):
        folder = Path(inspections[role]).resolve()
        ready = json.loads((folder/'READY.json').read_text())
        result = json.loads((folder/'result/REPORT.json').read_text())
        trace = json.loads((folder/'ISOLATION.json').read_text())
        exit_record = json.loads((folder/'EXIT.json').read_text())
        L.require(ready['mode'] == 'inspect' and ready['optimizer_invoked'] is False and
                  result['schema'] == 'FormulationLab.timing_worker_inspection.v1' and
                  result['optimizer_invoked'] is False and result['runtime'] == ready['runtime'] and
                  result['worker_pid'] == ready['pid'] and exit_record['exit_code'] == 0 and
                  exit_record['failure'] is None, 'inspection did not complete without optimization')
        audit = I.audit(trace['observations'], trace['expected_worker'], trace['max_gap_ns'], closed=trace['closed'])
        L.require(audit['admitted'] and trace['expected_worker']['pid'] == ready['pid'], 'inspection isolation incomplete')
        runtime = ready['runtime'];L.verify_runtime(runtime)
        L.require(not runtime['uninstalled_host_artifacts'], 'host artifact coverage is incomplete')
        source = next(p['source'] for p in runtime['packages'] if p['name'] == 'FormulationLab')
        original_freeze = Path(manifest['ledger']).parent.parent/f'FREEZE_{role}.json'
        original = L.load_checked(original_freeze, ledger['evidence_sha256'][str(original_freeze)])
        L.require(set(runtime['trees'][source]) == set(original['repository_file_sha256']),
                  'archived compiler file membership differs from original freeze')
        for relative, digest in original['repository_file_sha256'].items():
            L.require(L.sha(Path(source)/relative) == digest, 'archived compiler differs from original correctness source')
        role_jobs = [L.load_checked(j['path'], j['sha256']) for j in jobs.values()
                     if L.load_checked(j['path'], j['sha256'])['admission']['freeze'] == role]
        L.require(role_jobs and all(Path(j['admission']['source_archive']).resolve() == Path(source) for j in role_jobs),
                  'inspection loaded the wrong compiler source')
        runtime_data[role] = runtime
        environments[role] = str(Path(runtime['project']).parent)
        summaries[role] = dict(files=len(runtime['files_sha256']), trees=len(runtime['trees']),
                               artifacts=len(runtime['artifacts']), loaded_caches=len(runtime['loaded_caches']))
        for name in ('READY.json', 'result/REPORT.json', 'ISOLATION.json', 'EXIT.json'):
            protected[str(folder/name)] = L.sha(folder/name)
    for name in HELPERS:
        path = Path(__file__).with_name(name).resolve();protected[str(path)] = L.sha(path)
    # Python's readable loaded modules and caches accompany executable/build ID.
    # Numerical runtime provenance is in the much fuller Julia inventory.
    python_files = {str(Path(sys.executable).resolve()): L.sha(sys.executable)}
    for module in tuple(sys.modules.values()):
        for field in ('__file__', '__cached__'):
            path = getattr(module, field, None)
            if path and Path(path).is_file():
                path = str(Path(path).resolve());python_files[path] = L.sha(path)
    protected.update(python_files)
    L.check_files(protected)
    output.mkdir(parents=True)
    runtimes = {}
    for role, runtime in runtime_data.items():
        path = output/f'RUNTIME_{role}.json';L.save(path, runtime)
        runtimes[role] = dict(path=str(path), sha256=L.sha(path))
        protected[str(path)] = L.sha(path)
    freeze = dict(schema='FormulationLab.native_execution_freeze.v1',
        prepared_utc=datetime.now(timezone.utc).isoformat(), execution_ready=True, timing_authorized=False,
        optimizer_invoked=False, jobs=jobs, runtimes=runtimes, environments=environments,
        python_identity=L.python_identity(), protected_files_sha256=protected,
        monitor_settings=dict(interval_s=0.2, max_gap_s=1.0, ready_timeout_s=900, worker_timeout_s=21600),
        scope=dict(job_count=len(jobs), planned_calls=manifest['total_calls'],
                   parents='one previously studied training parent; no held-out runtime claim'),
        runtime_summary=summaries,
        limitations=['Process polling is sampled isolation, not a continuous-isolation proof.',
                     'Apple system shared-cache libraries are identified by OS build and names, not individual byte hashes.',
                     'This file is execution preparation, not human authorization.'],
        job_manifest=dict(path=str(Path(job_manifest_path).resolve()), sha256=job_manifest_digest))
    path = output/'FREEZE.json';L.save(path, freeze)
    L.save(output/'AUTHORIZATION_TEMPLATE.json', dict(schema='FormulationLab.timing_authorization.v1',
        authorized=False, freeze_sha256=L.sha(path), human_instruction_reference='',
        output=None, jobs=list(jobs)))
    return freeze


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('job_manifest', 'job_manifest_sha256', 'inspection_B', 'inspection_C', 'output'):
        parser.add_argument(name)
    args = parser.parse_args()
    result = prepare(args.job_manifest, args.job_manifest_sha256, {'B': args.inspection_B, 'C': args.inspection_C}, args.output)
    print(json.dumps({k: result[k] for k in ('execution_ready', 'timing_authorized', 'scope', 'runtime_summary')}))
