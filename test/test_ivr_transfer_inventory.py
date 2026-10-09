import copy
import hashlib
import json
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "examples"))
import ivr_transfer_inventory as I


def network():
    return dict(bus={"s": {"terminal_names": ["a", "n"]},
                     "l": {"terminal_names": ["a", "n"]}},
                line={"e": {"bus_from": "s", "bus_to": "l", "r": 1,
                              "terminal_map_from": ["a", "n"],
                              "terminal_map_to": ["a", "n"]}},
                voltage_source={"grid": {"bus": "s", "terminal_map": ["a", "n"]}},
                load={"d": {"bus": "l", "configuration": "SINGLE_PHASE",
                              "p_nom": [0, 10], "q_nom": [0, 0], "v_min": 200}})


class TransferInventory(unittest.TestCase):
    def test_features_are_not_certificates(self):
        net = network()
        original = copy.deepcopy(net)
        features = I.describe(net)
        self.assertEqual(features["zero_nominal_coils_uncertified"], 1)
        self.assertEqual(features["bus_terminal_counts"], {"2": 2})
        self.assertEqual(features["declared_limit_key_counts"], {"v_min": 1})
        self.assertEqual(net, original)

    def test_content_identity_and_topology_are_distinct(self):
        net = network()
        changed = copy.deepcopy(net)
        changed["line"]["e"]["r"] = 2
        self.assertNotEqual(I.digest(net), I.digest(changed))
        self.assertEqual(I.digest(I.topology_signal(net)), I.digest(I.topology_signal(changed)))
        changed["line"]["e"]["terminal_map_to"] = ["n", "a"]
        self.assertNotEqual(I.digest(I.topology_signal(net)), I.digest(I.topology_signal(changed)))

    def test_no_exposure_is_not_proof_of_held_out(self):
        for lineage, history in [(False, False), (True, False), (False, True)]:
            self.assertEqual(I.held_out_status([], lineage_reviewed=lineage,
                                               history_reviewed=history), "unresolved")
        self.assertEqual(I.held_out_status([], lineage_reviewed=True, history_reviewed=True),
                         "held_out")

    def test_family_exposure_cannot_be_relabelled(self):
        for exposures, expected in [(["inventory"], "held_out_with_disclosed_inventory"),
                                    (["inventory", "compiler_only"], "solve_held_out_only"),
                                    (["compiler_only", "solved"], "previously_solved_family"),
                                    (["performance_tuned"], "previously_solved_family")]:
            self.assertEqual(I.held_out_status(exposures, lineage_reviewed=True,
                                               history_reviewed=True), expected)
        for exposures, lineage, history in [(["unknown"], True, True),
                                             ([], "false", True), ([], True, 1)]:
            with self.assertRaises(ValueError):
                I.held_out_status(exposures, lineage_reviewed=lineage, history_reviewed=history)

    def test_census_does_not_claim_solves_or_successful_compilation(self):
        census = dict(inventory=[dict(file="a"), dict(file="b")],
                      sample=[dict(file="b", status="skipped_size")])
        self.assertEqual(I.census_exposures(census),
                         {"a": ["inventory"],
                          "b": ["compiler_sample_review_required", "inventory"]})

    def test_ambiguous_and_nonfinite_json_refused(self):
        for raw in ['{"bus":{},"bus":{}}', '{"x":NaN}', '{"x":Infinity}', '{"x":1e999}']:
            with self.assertRaises(ValueError):
                I.strict_json(raw)
        with self.assertRaises(ValueError):
            I.digest({"x": float("inf")})

    def test_inventory_retains_errors_aliases_and_input_bytes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "output").mkdir()
            (root / "benchmarks").mkdir()
            a, b = root / "output/a.json", root / "benchmarks/copy.json"
            a.write_text(json.dumps(network()))
            b.write_text(json.dumps(network(), indent=2, sort_keys=True))
            (root / "output/bad.json").write_text('{"bad":NaN}')
            (root / "output/report.json").write_text('{"status":"ok"}')
            before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob("*.json")}
            report = I.inventory(root, dict(inventory=[dict(file="output/a.json", sha256="old")]))
            after = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob("*.json")}
            self.assertEqual(before, after)
            self.assertEqual(report["statuses"], dict(inventoried=2, parse_or_shape_error=1,
                                                     not_network_shaped=1))
            self.assertEqual(len(report["exact_content_aliases"]), 1)
            self.assertEqual(len(report["topology_review_groups"]), 1)
            self.assertFalse(report["timing_eligible"])
            self.assertEqual(report["held_out_cases_admitted"], 0)
            self.assertTrue(all(not row["held_out"] for row in report["cases"]))
            self.assertTrue(all(row["exposure_status"] == "unresolved" for row in report["cases"]))
            row_a = next(row for row in report["cases"] if row["path"] == "output/a.json")
            self.assertFalse(row_a["census_source_bytes_match"])
            self.assertEqual(row_a["census_exposure"], ["inventory"])

    def test_cli_refuses_to_replace_existing_report(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            report = root / "report.json"
            report.write_bytes(b"preserve these bytes")
            result = subprocess.run([sys.executable, "-B", I.__file__, str(root), str(report)],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("output must be a new file", result.stderr)
            self.assertEqual(report.read_bytes(), b"preserve these bytes")

    def test_invalid_tables_do_not_become_empty_supported_tables(self):
        net = network()
        for key, value in [("load", []), ("line", {"bad": 1})]:
            broken = copy.deepcopy(net)
            broken[key] = value
            with self.assertRaises(ValueError):
                I.describe(broken)

    def test_strata_use_ports_and_devices_not_bus_width_alone(self):
        net = network()
        self.assertTrue(I.structural_strata(net)["single_phase"])
        for bus in net["bus"].values():
            bus["terminal_names"] = ["a", "b", "c", "n"]
        for side in ("from", "to"):
            net["line"]["e"]["terminal_map_" + side] = ["a", "b", "c"]
        labels = I.structural_strata(net)
        self.assertFalse(labels["single_phase"])
        self.assertFalse(labels["explicit_neutral_four_wire"])
        for side in ("from", "to"):
            net["line"]["e"]["terminal_map_" + side].append("n")
        self.assertTrue(I.structural_strata(net)["explicit_neutral_four_wire"])
        net["transformer"] = {"delta_wye": {"tx": {"v_nom_from": 11000, "v_nom_to": 415}}}
        net["shunt"] = {"ground": {}}
        labels = I.structural_strata(net)
        self.assertTrue(labels["delta"] and labels["mv_lv"])
        self.assertFalse(labels["mixed_devices"])
        net["switch"] = {"tie": {}}
        self.assertTrue(I.structural_strata(net)["mixed_devices"])
        net["transformer"] = {"n_winding": {"tx": {"windings": [{"v_nom": 11000}, {"v_nom": 230}]}}}
        labels = I.structural_strata(net)
        self.assertTrue(labels["multiwinding"] and labels["mv_lv"])

    def candidates(self, count=4):
        rows = [dict(path=f"case_{k}.json", sha256=f"bytes_{k}", content_sha256=f"content_{k}",
                     status="inventoried", features={"buses": 10},
                     strata={s: s in ("delta", "mv_lv") for s in I.STRATA}) for k in range(count)]
        return sorted(rows, key=lambda r: hashlib.sha256(r["path"].encode()).hexdigest())

    def reviews(self, rows):
        return {r["path"]: dict(family=r["path"], sha256=r["sha256"], exposures=["inventory"],
                               evidence=["reviewed/source.json"], lineage_reviewed=True,
                               history_reviewed=True) for r in rows}

    def test_selection_order_parent_separation_and_gaps(self):
        rows = self.candidates()
        a = I.select_panel(rows, self.reviews(rows))
        b = I.select_panel(list(reversed(rows)), self.reviews(rows))
        self.assertEqual(a, b)
        self.assertTrue(a["selection_complete"])
        self.assertEqual([r["path"] for r in a["selected"]], [r["path"] for r in rows])
        self.assertEqual([r["stratum"] for r in a["selected"]], ["delta", "delta", "mv_lv", "mv_lv"])
        self.assertEqual(len({r["family"] for r in a["selected"]}), 4)
        self.assertEqual({g["stratum"] for g in a["gaps"]},
                         {"single_phase", "explicit_neutral_four_wire", "mixed_devices", "multiwinding"})

    def test_unreviewed_case_cannot_be_leapfrogged(self):
        rows = self.candidates()
        reviews = self.reviews(rows[1:])
        result = I.select_panel(rows, reviews)
        self.assertFalse(result["selection_complete"])
        self.assertEqual(result["selected"], [])
        self.assertEqual({p["path"] for p in result["pending"]}, {rows[0]["path"]})

    def test_solved_sibling_taints_whole_parent(self):
        rows = self.candidates()
        reviews = self.reviews(rows)
        for r in rows[:2]:
            reviews[r["path"]]["family"] = "same_parent"
        reviews[rows[1]["path"]]["exposures"] = ["solved"]
        result = I.select_panel(rows, reviews)
        self.assertEqual([r["path"] for r in result["selected"]], [r["path"] for r in rows[2:]])
        self.assertTrue(any(r["decision"] == "previously_solved_family" for r in result["trace"]))

    def test_stale_reviews_and_duplicate_content_refused(self):
        rows = self.candidates()
        reviews = self.reviews(rows)
        reviews[rows[0]["path"]]["sha256"] = "stale"
        with self.assertRaises(ValueError):
            I.select_panel(rows, reviews)
        reviews = self.reviews(rows)
        rows[1]["content_sha256"] = rows[0]["content_sha256"]
        with self.assertRaises(ValueError):
            I.select_panel(rows, reviews)

    def test_explicit_unresolved_exclusion_is_disclosed(self):
        rows = self.candidates()
        reviews = self.reviews(rows)
        first = reviews[rows[0]["path"]]
        first["lineage_reviewed"] = False
        self.assertFalse(I.select_panel(rows, reviews)["selection_complete"])
        first["exclusion_reason"] = "upstream parent unresolved after recorded review"
        result = I.select_panel(rows, reviews)
        self.assertTrue(result["selection_complete"])
        self.assertTrue(any(r["decision"] == "unresolved" for r in result["trace"]))
        self.assertNotIn(rows[0]["path"], [r["path"] for r in result["selected"]])

    def test_selection_rejects_invalid_features_and_oversize_cases(self):
        rows = self.candidates()
        reviews = self.reviews(rows)
        for value in (True, float("nan"), 0, -1):
            bad = copy.deepcopy(rows)
            bad[0]["features"]["buses"] = value
            with self.assertRaises(ValueError):
                I.select_panel(bad, reviews)
        bad = copy.deepcopy(rows)
        bad[0]["strata"]["delta"] = "yes"
        with self.assertRaises(ValueError):
            I.select_panel(bad, reviews)
        rows[0]["features"]["buses"] = 3001
        selected = I.select_panel(rows, reviews)["selected"]
        self.assertNotIn(rows[0]["path"], [r["path"] for r in selected])


if __name__ == "__main__":
    unittest.main()
