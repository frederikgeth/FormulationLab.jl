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
    jobs = []; factors = []; versions = set()
    for k, header in enumerate(headers):
        m = pattern.fullmatch(header.group())
        if m is None:
            continue
        version, job, order, entries = m.groups()
        versions.add(version); job, order, entries = map(int, (job, order, entries))
        jobs.append(job)
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
                observed_job_counts=counts, factors=factors, maxima=maxima,
                timing_eligible=False,
                qualification="Observed MUMPS text reports only. Negative/encoded counters are not decoded. "
                "Missing counters are not zero. NNZ is the solver input entry count, not the JuMP Jacobian. "
                "Entry ratios are not symbolic fill-edge counts. Reports do not establish conditioning, "
                "backward error, complete log capture, or performance causality.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    data = args.log.read_bytes()
    report = parse(data.decode("utf-8"))
    report["source_sha256"] = hashlib.sha256(data).hexdigest()
    args.output.write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
