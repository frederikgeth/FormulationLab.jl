"""Read reported MUMPS factor statistics from a verbose, single-process Ipopt log.

This is diagnostic text parsing, not a stable solver API or timing benchmark.
Missing/negative counters remain unavailable; estimates never replace actuals.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path


FIELDS = {
    9: ("real_storage", "Real space for factors"),
    10: ("integer_storage", "Integer space for factors"),
    11: ("maximum_front", "Maximum front size"),
    29: ("factor_entries", "Number of entries in factors"),
    12: ("negative_pivots", "Number of negative pivots"),
    13: ("delayed_pivots", "Number of delayed pivots"),
}


def parse(text):
    """Preserve each observed JOB=2, including incomplete or failed reports.

    Entry ratios divide INFOG(29) by the NNZ passed to MUMPS in that call.
    They are storage-convention-dependent ratios, not counts of new fill edges.
    Calls are not assumed to correspond one-to-one with Ipopt iterations.
    """
    headers = list(re.finditer(r"^Entering DMUMPS .*", text, re.M))
    pattern = re.compile(
        r"Entering DMUMPS (\S+) from C interface with JOB, N, NNZ\s*=\s*"
        r"(-?\d+)\s+(\d+)\s+(\d+)\s*$"
    )
    jobs = []; job_records = []; factors = []; versions = set()
    for k, header in enumerate(headers):
        m = pattern.fullmatch(header.group())
        if m is None:
            continue
        version, job, order, entries = m.groups()
        versions.add(version); job, order, entries = map(int, (job, order, entries))
        jobs.append(job)
        job_records.append(dict(job=job, input_order=order, input_entries=entries,
                                character_offset=header.start(), mumps_version=version))
        if job != 2:
            continue
        block = text[header.end():headers[k + 1].start() if k + 1 < len(headers) else len(text)]
        raw = {}
        for code, (name, label) in FIELDS.items():
            matches = re.findall(
                rf"^\s*INFOG\s*\(\s*{code}\)\s+{re.escape(label)}\s*=\s*(-?\d+)\s*$",
                block, re.M,
            )
            if len(matches) > 1:
                raise ValueError(f"duplicate INFOG({code}) in numerical call {len(factors) + 1}")
            raw[name] = int(matches[0]) if matches else None
        values = {name: x if x is not None and x >= 0 else None for name, x in raw.items()}
        complete = all(x is not None for x in values.values()) and order > 0 and entries > 0
        actual = values["factor_entries"]
        factors.append(dict(call=len(factors) + 1, input_order=order, input_entries=entries,
                            reported=raw, **values, complete=complete,
                            factor_to_input_entry_ratio=actual / entries
                            if actual is not None and entries > 0 else None))
    counts = {str(job): jobs.count(job) for job in sorted(set(jobs))}
    maxima = {name: max((r[name] for r in factors if r[name] is not None), default=None)
              for name, _ in FIELDS.values()}
    return dict(schema="FormulationLab.mumps_factor_trace.v1", mumps_versions=sorted(versions),
                available=any(r["factor_entries"] is not None for r in factors),
                complete_factor_reports=bool(factors) and all(r["complete"] for r in factors),
                observed_job_counts=counts, job_records=job_records, factors=factors, maxima=maxima,
                timing_eligible=False,
                qualification="Observed MUMPS text reports only. Negative/encoded counters are not decoded. "
                "Missing counters are not zero. NNZ is the solver input entry count, not the JuMP Jacobian. "
                "Entry ratios are not symbolic fill-edge counts. Reports do not establish conditioning, "
                "backward error, complete log capture, or performance causality. Buffered reports can "
                "cross capture boundaries; a filename alone does not identify the model of every job.")


def reconcile_captures(captures, models):
    """Attribute buffered reports using independently declared unique signatures.

    `captures` maps capture names to full text. Each `models` entry declares
    input_order, input_entries, wrapper_factorizations and wrapper_solves, plus
    an optional primary_capture. Matrix signatures must be unique across these
    models; dimensions alone are not a general model identifier. Every JOB=2/3
    must map to a declared signature, all actual factor reports must be complete,
    and counts must match independent Ipopt wrapper-call counts. Refuse partial,
    duplicated or ambiguous capture sets instead of assigning by filename.
    """
    if not captures or not models:
        raise ValueError("nonempty captures and model declarations required")
    signatures = {}
    rows = {}
    for name, model in models.items():
        required = ("input_order", "input_entries", "wrapper_factorizations", "wrapper_solves")
        if any(type(model.get(k)) is not int or model[k] <= 0 for k in required):
            raise ValueError(f"positive integer matrix sizes and wrapper counts required for {name}")
        signature = (model["input_order"], model["input_entries"])
        if signature in signatures:
            raise ValueError("matrix signatures must uniquely identify models within this capture set")
        primary = model.get("primary_capture")
        if primary is not None and primary not in captures:
            raise ValueError(f"missing primary capture for {name}")
        signatures[signature] = name
        rows[name] = dict(input_order=signature[0], input_entries=signature[1],
                          jobs=[], factors=[], displaced_jobs=[])
    hashes = {}
    for capture, text in captures.items():
        hashes[capture] = hashlib.sha256(text.encode("utf-8")).hexdigest()
        parsed = parse(text)
        for job in parsed["job_records"]:
            if job["job"] not in (2, 3):
                continue
            signature = (job["input_order"], job["input_entries"])
            if signature not in signatures:
                raise ValueError(f"undeclared matrix signature {signature} in {capture}")
            name = signatures[signature]
            record = dict(capture=capture, **job)
            rows[name]["jobs"].append(record)
            primary = models[name].get("primary_capture")
            if primary is not None and primary != capture:
                rows[name]["displaced_jobs"].append(record)
        for factor in parsed["factors"]:
            if not factor["complete"]:
                raise ValueError(f"incomplete actual factor report in {capture}")
            name = signatures[(factor["input_order"], factor["input_entries"])]
            rows[name]["factors"].append(dict(capture=capture, **factor))
    for name, row in rows.items():
        counts = {str(k): sum(j["job"] == k for j in row["jobs"]) for k in (2, 3)}
        if counts["2"] != models[name]["wrapper_factorizations"] or counts["3"] != models[name]["wrapper_solves"]:
            raise ValueError(f"MUMPS and independent wrapper counts differ for {name}")
        if len(row["factors"]) != counts["2"]:
            raise ValueError(f"factor report count differs for {name}")
        row["observed_job_counts"] = counts
        row["maxima"] = {field: max(f[field] for f in row["factors"]) for field, _ in FIELDS.values()}
    return dict(schema="FormulationLab.mumps_capture_audit.v1", passed=True,
                capture_sha256=hashes, models=rows, timing_eligible=False,
                qualification="Attribution requires unique declared matrix signatures and independently "
                "matched wrapper counts. No timing, conditioning or performance-causality conclusion.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    data = args.log.read_bytes()
    report = parse(data.decode("utf-8"))
    report["source_sha256"] = hashlib.sha256(data).hexdigest()
    args.output.write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
