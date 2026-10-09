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


if __name__ == "__main__":
    unittest.main()
