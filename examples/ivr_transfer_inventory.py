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


STRATA = ("single_phase", "delta", "explicit_neutral_four_wire", "mv_lv",
          "mixed_devices", "multiwinding")


def structural_strata(network):
    """Conservative input-only sampling labels, not compiler certificates.

    Single-phase means at most one declared nonneutral terminal per bus (so
    split-phase circuits are not silently included). Four-wire requires an
    actual four-terminal line with a declared/conventional neutral at both ends.
    Ground shunts and sources alone do not count as mixed device families.
    """
    buses = records(network, "bus")
    conventions = network.get("terminal_conventions", {})
    if not isinstance(conventions, dict):
        raise ValueError("terminal conventions must be an object")
    neutral_names = conventions.get("neutral", ["n"])
    if not isinstance(neutral_names, list):
        raise ValueError("neutral convention must be a list")

    def neutrals(bus):
        declaration = buses[bus].get("neutral_terminal")
        return {declaration} if declaration is not None else set(neutral_names)

    phase_counts = []
    for bus, record in buses.items():
        terminals = record.get("terminal_names")
        if not isinstance(terminals, list):
            raise ValueError("bus terminal_names must be a list")
        phase_counts.append(len(set(terminals) - neutrals(bus)))
    four_wire = False
    for line in records(network, "line").values():
        sides = []
        for side in ("from", "to"):
            bus, terminals = line.get("bus_" + side), line.get("terminal_map_" + side)
            sides.append(bus in buses and isinstance(terminals, list) and
                         len(set(terminals)) == 4 and bool(set(terminals) & neutrals(bus)))
        four_wire |= all(sides)
    transformers = records(network, "transformer")
    delta = any("delta" in kind.lower() and bool(rows) for kind, rows in transformers.items())
    for family in ("load", "generator", "ibr"):
        delta |= any(str(d.get("configuration", d.get("topology", ""))).upper() == "DELTA"
                     for d in records(network, family).values())
    mv_lv = False
    for rows in transformers.values():
        for record in rows.values():
            values = [record.get("v_nom_from"), record.get("v_nom_to")]
            windings = record.get("windings", [])
            if not isinstance(windings, list) or any(not isinstance(w, dict) for w in windings):
                raise ValueError("transformer windings must be a list of objects")
            values += [w.get("v_nom") for w in windings]
            values = [v for v in values if type(v) in (int, float) and math.isfinite(v) and v > 0]
            mv_lv |= bool(values) and min(values) <= 1000 < max(values)
    families = [family for family in ("generator", "ibr", "switch", "capacitor")
                if records(network, family)]
    if any(transformers.values()):
        families.append("transformer")
    return dict(single_phase=bool(phase_counts) and max(phase_counts) == 1,
                delta=delta, explicit_neutral_four_wire=four_wire, mv_lv=mv_lv,
                mixed_devices=len(families) >= 2,
                multiwinding=any("winding" in kind.lower() and bool(rows)
                                for kind, rows in transformers.items()))


def select_panel(candidates, reviews, *, per_stratum=2, max_buses=3000):
    """Select in frozen stratum/hash order with explicit reviewed family identity.

    Unreviewed eligible candidates stop their stratum, so a later convenient
    case cannot leapfrog unresolved history. Explicit exclusions need a reason
    and evidence. Family-wide solved/tuned exposure dominates individual reviews.
    Missing strata remain gaps. No numerical outcomes are accepted as features.
    """
    if type(per_stratum) is not int or per_stratum < 1 or type(max_buses) is not int or max_buses < 1:
        raise ValueError("positive integer selection limits required")
    paths = [row["path"] for row in candidates]
    if len(paths) != len(set(paths)):
        raise ValueError("duplicate input paths")
    families = defaultdict(set)
    by_path = {row["path"]: row for row in candidates}
    for row in candidates:
        if row.get("status") == "inventoried":
            count = row.get("features", {}).get("buses")
            if type(count) is not int or count <= 0:
                raise ValueError("positive integer bus count required: " + row["path"])
    identities = {}
    for path, review in reviews.items():
        if not review.get("family") or not review.get("evidence"):
            raise ValueError("family and review evidence required: " + path)
        if path not in by_path or not review.get("sha256") or review["sha256"] != by_path[path].get("sha256"):
            raise ValueError("review input bytes are absent or changed: " + path)
        content = by_path[path].get("content_sha256")
        if content:
            if content in identities and identities[content] != review["family"]:
                raise ValueError("identical content assigned different parents")
            identities[content] = review["family"]
        families[review["family"]].update(review.get("exposures", []))
    selected, trace, gaps, pending = [], [], [], []
    used = set()
    ordered = sorted(candidates, key=lambda row: hashlib.sha256(row["path"].encode()).hexdigest())
    for stratum in STRATA:
        count = 0
        for row in ordered:
            if row.get("status") != "inventoried" or row["features"]["buses"] > max_buses:
                continue
            labels = row.get("strata", {})
            if set(labels) != set(STRATA) or any(type(v) is not bool for v in labels.values()):
                raise ValueError("complete boolean structural strata required: " + row["path"])
            if not labels[stratum]:
                continue
            path = row["path"]
            review = reviews.get(path)
            if review is None:
                pending.append(dict(stratum=stratum, path=path, reason="unreviewed_candidate"))
                break
            family = review["family"]
            if family in used:
                trace.append(dict(stratum=stratum, path=path, decision="parent_already_selected", family=family))
                continue
            status = held_out_status(families[family], lineage_reviewed=review.get("lineage_reviewed", False),
                                     history_reviewed=review.get("history_reviewed", False))
            if status in ("held_out", "held_out_with_disclosed_inventory"):
                selected.append(dict(stratum=stratum, path=path, family=family, exposure=status,
                                     selection_key=hashlib.sha256(path.encode()).hexdigest()))
                used.add(family); count += 1
                if count == per_stratum:
                    break
            elif status == "unresolved" and not review.get("exclusion_reason"):
                pending.append(dict(stratum=stratum, path=path, reason="unresolved_review"))
                break
            else:
                trace.append(dict(stratum=stratum, path=path, family=family, decision=status,
                                  reason=review.get("exclusion_reason", status)))
        if count < per_stratum:
            gaps.append(dict(stratum=stratum, selected=count, target=per_stratum))
    return dict(selected=selected, trace=trace, gaps=gaps, pending=pending,
                selection_complete=not pending, timing_eligible=False)


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
                       strata=structural_strata(network),
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
