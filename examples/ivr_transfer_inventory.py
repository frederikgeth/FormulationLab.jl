"""Read-only input inventory for prospective exact-IVR transfer studies.

No optimizer is imported or invoked. Structural fingerprints are alias-review
signals, not isomorphism certificates. Absence of an exposure record never proves
that a network is held out. Input validation remains the compiler's responsibility.
"""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
                                    allow_nan=False).encode()).hexdigest()


def strict_json(raw):
    def constant(value):
        raise ValueError("non-finite JSON constant: " + value)

    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError("duplicate JSON key: " + key)
            result[key] = value
        return result

    def finite_float(value):
        result = float(value)
        if not math.isfinite(result):
            raise ValueError("non-finite JSON number: " + value)
        return result

    return json.loads(raw, parse_constant=constant, parse_float=finite_float,
                      object_pairs_hook=pairs)


def records(network, table):
    value = network.get(table, {})
    if not isinstance(value, dict):
        raise ValueError("component table is not an object: " + table)
    if any(not isinstance(record, dict) for record in value.values()):
        raise ValueError("component record is not an object: " + table)
    return value


def describe(network):
    """Describe raw features without inferring electrical certificates or phases."""
    buses = records(network, "bus")
    tables = ("line", "load", "generator", "ibr", "switch", "capacitor", "shunt",
              "voltage_source")
    counts = {name: len(records(network, name)) for name in tables}
    transformers = records(network, "transformer")
    transformer_counts = {kind: len(rows) for kind, rows in transformers.items()}
    configs = Counter(str(d.get("configuration", "unspecified"))
                      for d in records(network, "load").values())
    widths = Counter(str(len(b["terminal_names"])) for b in buses.values()
                     if isinstance(b.get("terminal_names"), list))
    zero_coils = 0
    for load in records(network, "load").values():
        p, q = load.get("p_nom"), load.get("q_nom")
        if isinstance(p, list) and isinstance(q, list) and len(p) == len(q):
            zero_coils += sum(type(a) in (int, float) and type(b) in (int, float)
                              and a == b == 0 for a, b in zip(p, q))
    # Do not call these active constraints or a complete schema inventory.
    limits = Counter()

    def walk(value):
        if isinstance(value, dict):
            for key, child in value.items():
                if key.endswith(("_min", "_max", "_rating")):
                    limits[key] += 1
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)
    walk(network)
    ratios = []
    for rows in transformers.values():
        for record in rows.values():
            if not isinstance(record, dict):
                raise ValueError("transformer record is not an object")
            a, b = record.get("v_nom_from"), record.get("v_nom_to")
            if type(a) in (int, float) and type(b) in (int, float) and a > 0 and b > 0:
                ratio = a / b
                if not math.isfinite(ratio):
                    raise ValueError("non-finite computed transformer voltage ratio")
                ratios.append(ratio)
    return dict(buses=len(buses), components=counts, transformer_types=transformer_counts,
                bus_terminal_counts=dict(widths), load_configurations=dict(configs),
                zero_nominal_coils_uncertified=zero_coils,
                transformer_voltage_ratios=sorted(ratios),
                declared_limit_key_counts=dict(limits))


def topology_signal(network):
    """ID-preserving topology only; equal hashes require lineage review.

    Retains named buses/ports and transformer kind. Deliberately ignores
    impedances and operating scenarios; shared topology is not equal physics.
    Renamed, reduced, or expanded copies may not match and require manual review.
    """
    keys = {"bus", "bus_from", "bus_to", "buses", "terminal_names",
            "terminal_map", "terminal_map_from", "terminal_map_to",
            "configuration", "windings"}

    def ports(value):
        if isinstance(value, dict):
            return {k: v for k, v in value.items() if k in keys}
        raise ValueError("invalid topology record")

    result = {t: {k: ports(v) for k, v in records(network, t).items()}
              for t in ("bus", "line", "switch", "voltage_source")}
    result["transformer"] = {kind: {k: ports(v) for k, v in rows.items()}
                             for kind, rows in records(network, "transformer").items()}
    return result


def inspect_file(path, root):
    raw = path.read_bytes()
    row = dict(path=path.relative_to(root).as_posix(), bytes=len(raw),
               sha256=hashlib.sha256(raw).hexdigest(), held_out=False,
               exposure_status="unresolved")
    try:
        network = strict_json(raw)
        if not isinstance(network, dict) or not isinstance(network.get("bus"), dict):
            row["status"] = "not_network_shaped"
        elif not network["bus"] or not any(isinstance(b, dict) and "terminal_names" in b
                                           for b in network["bus"].values()):
            row["status"] = "not_input_bus_shape"
        else:
            row.update(status="inventoried", features=describe(network),
                       content_sha256=digest(network),
                       topology_review_sha256=digest(topology_signal(network)))
    except (ValueError, TypeError, UnicodeError, OverflowError) as error:
        row.update(status="parse_or_shape_error", error=str(error))
    return row


def alias_groups(rows, key):
    groups = defaultdict(list)
    for row in rows:
        if key in row:
            groups[row[key]].append(row["path"])
    return [dict(sha256=k, paths=sorted(v)) for k, v in sorted(groups.items()) if len(v) > 1]


def census_exposures(census):
    """Import the historical dataset census without mistaking it for solves."""
    result = defaultdict(set)
    for row in census.get("inventory", []):
        result[row["file"]].add("inventory")
    for row in census.get("sample", []):
        # Some samples were skipped by size: flag review rather than assert
        # successful compilation, and never assert an optimizer was called.
        result[row["file"]].add("compiler_sample_review_required")
    return {path: sorted(levels) for path, levels in result.items()}


def held_out_status(exposures, *, lineage_reviewed, history_reviewed):
    """Fail closed; callers must supply reviewed exposures for the whole family."""
    allowed = {"inventory", "compiler_only", "solved", "performance_tuned"}
    if not isinstance(lineage_reviewed, bool) or not isinstance(history_reviewed, bool):
        raise ValueError("review decisions must be booleans")
    if set(exposures) - allowed:
        raise ValueError("unknown or unresolved exposure category")
    if not lineage_reviewed or not history_reviewed:
        return "unresolved"
    if set(exposures) & {"solved", "performance_tuned"}:
        return "previously_solved_family"
    if "compiler_only" in exposures:
        return "solve_held_out_only"
    return "held_out_with_disclosed_inventory" if "inventory" in exposures else "held_out"


def inventory(root, census=None):
    paths = sorted(p for folder in ("output", "benchmarks")
                   for p in (root / folder).rglob("*.json") if p.is_file())
    rows = [inspect_file(path, root) for path in paths]
    exposure = census_exposures(census) if census is not None else {}
    census_hashes = {row["file"]: row.get("sha256") for row in census.get("inventory", [])} if census else {}
    for row in rows:
        row["census_exposure"] = exposure.get(row["path"], [])
        previous = census_hashes.get(row["path"])
        row["census_source_sha256"] = previous
        row["census_source_bytes_match"] = row["sha256"] == previous if previous else None
    return dict(schema="FormulationLab.transfer_inventory.v1", root=str(root.resolve()),
                no_optimizer_invoked=True, timing_eligible=False,
                held_out_cases_admitted=0, history_review_complete=False,
                statuses=dict(Counter(row["status"] for row in rows)), cases=rows,
                exact_content_aliases=alias_groups(rows, "content_sha256"),
                topology_review_groups=alias_groups(rows, "topology_review_sha256"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--census", type=Path)
    args = parser.parse_args()
    if not args.root.is_dir():
        parser.error("root must be an existing dataset directory")
    if args.output.exists():
        parser.error("output must be a new file")
    # Opening only after inventory succeeds avoids partial valid-looking reports.
    census_raw = args.census.read_bytes() if args.census else None
    report = inventory(args.root, strict_json(census_raw) if args.census else None)
    if args.census:
        report["census_source"] = dict(path=str(args.census.resolve()),
                                      sha256=hashlib.sha256(census_raw).hexdigest())
    with args.output.open("x") as stream:
        json.dump(report, stream, indent=2, sort_keys=True, allow_nan=False)
        stream.write("\n")
    print(json.dumps(dict(statuses=report["statuses"], held_out_cases_admitted=0)))


if __name__ == "__main__":
    main()
