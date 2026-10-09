"""Expand the authenticated finite admission ledger without running an optimizer.

The output is a reviewable runner input, not an execution authorization or a full
runtime freeze. B and C retain their own archived compiler and correctness code.
"""
import argparse
import hashlib
import json
from pathlib import Path


def require(ok, message):
    if not ok:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_checked(path, expected):
    data = Path(path).read_bytes()
    require(hashlib.sha256(data).hexdigest() == expected, f"changed evidence: {path}")
    return json.loads(data)


def events(job):
    """Explicit excluded warmups followed by every predeclared sweep, unchanged."""
    require(job.get("correctness_qualified") is True, "job not correctness-qualified")
    require(job.get("timing_authorized") is False and job.get("executable") is False,
            "expected a non-executable admission job")
    n = len(job["arms"])
    require(n > 0 and len(job["solver_settings"]) == n, "incomplete arms/settings")
    names = [a["name"] for a in job["arms"]]
    require(len(set(names)) == n, "duplicate arm names")
    result = []

    def append(stage, sweep, order):
        require(all(type(i) is int for i in order) and sorted(order) == list(range(1, n + 1)),
                "sweep is not a permutation of all arms")
        for position, arm in enumerate(order, 1):
            result.append(dict(sequence=len(result) + 1, stage=stage, sweep=sweep,
                               position=position, arm_index=arm, arm=names[arm - 1]))

    # The freeze declares one excluded warmup per arm. Declare its previously
    # unspecified ordering here, prospectively and independent of any outcome.
    append("warmup", 0, list(range(1, n + 1)))
    require(len(job["sweeps"]) > 0, "empty measured schedule")
    for sweep, order in enumerate(job["sweeps"], 1):
        append("measurement", sweep, order)
    expected = dict(warmup=n, measured=n * len(job["sweeps"]), total=len(result))
    require(job["counts"] == expected, "declared counts disagree with schedule")
    return result


def archive_check(root, hashes):
    root = Path(root).resolve()
    actual = {str(p.relative_to(root)) for p in root.rglob("*") if p.is_file()}
    require(actual == set(hashes), f"archive file set changed: {root}")
    for name, expected in hashes.items():
        path = root / name
        require(path.resolve().is_relative_to(root), "archive path escapes source root")
        require(sha(path) == expected, f"archive bytes changed: {path}")


def outside_protected(output, root):
    require(not Path(output).resolve().is_relative_to(Path(root).resolve()),
            f"job output must be outside protected directory: {root}")


def prepare(ledger_path, expected_sha256, output):
    ledger_path = Path(ledger_path).resolve()
    output = Path(output).resolve()
    require(not output.exists(), "output must be a new directory")
    outside_protected(output, Path(__file__).resolve().parents[1])
    ledger = read_checked(ledger_path, expected_sha256)
    require(ledger.get("schema") == "FormulationLab.timing_admission_ledger.v1", "unknown ledger schema")
    require(all(ledger.get(k) is False for k in ("timing_authorized", "optimizer_invoked", "execution_ready")),
            "expected preparation-only ledger")
    evidence = ledger["evidence_sha256"]
    for path, digest in evidence.items():
        require(sha(path) == digest, f"ledger evidence changed: {path}")
    phase = ledger_path.parent.parent
    freezes = {k: read_checked(phase / f"FREEZE_{k}.json", evidence[str(phase / f"FREEZE_{k}.json")])
               for k in ("B", "C")}
    checked_archives = set()
    expanded = []
    identities = set()
    for index, job in enumerate(ledger["jobs"], 1):
        identity = tuple(job[k] for k in ("family", "id", "workload", "contrast", "batch"))
        require(identity not in identities, "duplicate job")
        identities.add(identity)
        require(job["freeze"] in freezes, "unknown compiler freeze")
        frozen = freezes[job["freeze"]]
        require(job["source_commit"] == frozen["source_commit"], "source commit mismatch")
        archive = str(Path(job["source_archive"]).resolve())
        outside_protected(output, archive)
        key = (job["freeze"], archive)
        if key not in checked_archives:
            archive_check(archive, frozen["repository_file_sha256"])
            checked_archives.add(key)
        preparation_path = Path(job["inputs"]["preparation"])
        outside_protected(output, preparation_path.parent)
        pre = read_checked(preparation_path, job["inputs"]["preparation_sha256"])
        require(pre["ready"] is True, "preparation not ready")
        require(set(pre["files"]) == {"COMPILER_INPUT.json", "WORKLOADS.json", "START.json"},
                "incomplete prepared input set")
        inputs = {name: read_checked(preparation_path.parent / name, digest)
                  for name, digest in pre["files"].items()}
        require(sha(pre["source"]) == pre["source_sha256"], "original input changed")
        workload = [w for w in inputs["WORKLOADS.json"] if w["kind"] == job["workload"]]
        require(len(workload) == 1, "missing or duplicated workload")
        workload = workload[0]
        if job["freeze"] == "B":
            declarations = [p for p in frozen["correctness_jobs"] if p["id"] == job["id"]]
            require(len(declarations) == 1, "ambiguous B preparation")
            declaration = declarations[0]
            require(Path(declaration["prepared"]).resolve() == preparation_path.parent.resolve() and
                    declaration["preparation_sha256"] == job["inputs"]["preparation_sha256"],
                    "B prepared case changed")
            require(job["family"] in ("B_portfolio", "B_factorial"), "unsupported B family")
            arms = workload["candidates"]
            kind = "portfolio"
            if job["family"] == "B_factorial":
                arms = [a for a in arms if a["name"] != "full_powers"]
                kind = "factorial"
            require(job["arms"] == arms and job["solver_settings"] == [pre["solver_options"]] * len(arms),
                    "B configurations changed")
            require(job["sweeps"] == pre["future_orders"][kind][job["batch"]], "B order changed")
            reference = workload["reference"]
            tolerances = pre["tolerances"]
        else:
            require(job["family"] == "C_candidates", "unsupported C family")
            plans = [p for p in frozen["correctness_jobs"] if p["id"] == job["id"]]
            require(len(plans) == 1, "ambiguous C plan")
            plan = read_checked(plans[0]["path"], plans[0]["sha256"])
            require(Path(plan["prepared"]).resolve() == preparation_path.parent.resolve() and
                    plan["preparation_sha256"] == job["inputs"]["preparation_sha256"],
                    "C prepared case changed")
            pairs = [p for p in plan["pairs"] if (p["workload"], p["name"]) == (job["workload"], job["contrast"])]
            require(len(pairs) == 1, "ambiguous candidate pair")
            pair = pairs[0]
            require(job["arms"] == [pair["control"], pair["candidate"]], "C configurations changed")
            require(job["solver_settings"] == [pair["control_solver"], pair["candidate_solver"]], "C solver controls changed")
            require(job["sweeps"] == frozen["future_timing"][job["batch"] + "_orders"], "C order changed")
            reference = pair["reference"]
            tolerances = plan["tolerances"]
        require(all(a["options"]["objective"] == "power" and
                    a["options"]["power_terms"] == reference["power_terms"] for a in job["arms"]),
                "objective semantics differ")
        expanded.append(dict(schema="FormulationLab.native_timing_job.v1", job_index=index,
                             admission=job, reference=reference, tolerances=tolerances,
                             preparation_files_sha256=pre["files"], events=events(job),
                             timing_authorized=False, execution_ready=False))
    require(sum(len(j["events"]) for j in expanded) == ledger["total_optimizer_calls_if_all_authorized"],
            "ledger total changed")
    output.mkdir(parents=True)
    files = {}
    for job in expanded:
        name = f"job_{job['job_index']:03d}.json"
        path = output / name
        path.write_text(json.dumps(job, indent=2) + "\n")
        files[name] = sha(path)
    manifest = dict(schema="FormulationLab.native_timing_jobs.v1", ledger=str(ledger_path),
                    ledger_sha256=expected_sha256, generator_sha256=sha(__file__), jobs=files,
                    job_count=len(expanded), total_calls=sum(len(j["events"]) for j in expanded),
                    warmup_order="ascending declared arm index, excluded, one per arm",
                    archives_checked=len(checked_archives), timing_authorized=False,
                    optimizer_invoked=False, execution_ready=False,
                    remaining=["runtime/source freeze and admission/isolation runner validation",
                               "explicit human authorization before native timing"])
    (output / "MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ledger", type=Path)
    parser.add_argument("expected_sha256")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    result = prepare(args.ledger, args.expected_sha256, args.output)
    print(json.dumps({k: result[k] for k in ("job_count", "total_calls", "archives_checked", "optimizer_invoked", "execution_ready")}))
