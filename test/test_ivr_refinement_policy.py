"""Native norm calibration: reject corrupted evidence and wrong count claims."""
from decimal import Decimal as D
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).parents[1] / 'examples'))
from ivr_refinement_policy import audit, audit_counts, printed_interval, ratio_interval


def sample():
    call = 'Calling MUMPS-3 for solve.\nDone with MUMPS-3 for solve.\n'
    residual = 'CompoundVector "resid" with 8 components:\n'
    for i in range(8):
        residual += f'Component {i+1}:\nDenseVector "resid[{i}]" with 1 elements:\n'
        residual += f'resid[{i}][ 1]= {"2.0000000000000000e-12" if i == 7 else "0.0000000000000000e+00"}\n'
    for name in ('x', 's', 'c', 'd', 'zL', 'zU', 'vL', 'vU'):
        residual += f'max-norm resid_{name} {"2.000000e-12" if name == "vU" else "0.000000e+00"}\n'
    residual += 'nrm_rhs = 1.00e+00 nrm_sol = 3.00e+00 nrm_resid = 2.00e-12\nresidual_ratio = 5.000000e-13\n'
    return ('This is Ipopt version 3.14.19, running with linear solver MUMPS.\n'+call+
        '*** Solving the Primal Dual System for Iteration 0:\n'+(call+residual)*2+
        '*** Finding Acceptable Trial Point for Iteration 0:\nNumber of Iterations....: 1\nEXIT: Optimal Solution Found.\n')


class PolicyTests(unittest.TestCase):
    def test_counts_without_vector_dump(self):
        text = sample()
        result = audit_counts(text, 1)
        self.assertEqual(result['work']['mandatory_corrections'], 1)
        self.assertEqual(result['work']['excess_corrections'], 0)
        self.assertEqual(result['work']['episode_final_ratios_above_target'], 0)
        self.assertEqual(audit_counts(text, 0)['work']['excess_corrections'], 1)
        for target in (0, -1, float('nan'), float('inf')):
            with self.assertRaises(ValueError): audit_counts(text, 1, target)

    def test_counts_recovery_and_accepted_above_target(self):
        call = 'Calling MUMPS-3 for solve.\nDone with MUMPS-3 for solve.\n'
        solve = lambda value: call+f'residual_ratio = {value}\n'
        body = solve('1e-3')+solve('1e-4')+solve('1e-5')
        failure = 'Iterative refinement failed with residual_ratio = 1e-5\n'
        body += failure+'Increasing pivot tolerance for MUMPS from 1e-6 to 1e-3.\n'
        body += solve('1e-4')+solve('1e-5')+failure+'Just accept current solution.\n'
        text = ('This is Ipopt version 3.14.19, running with linear solver MUMPS.\n'+call+
            '*** Solving the Primal Dual System for Iteration 0:\n'+body+
            '*** Finding Acceptable Trial Point for Iteration 0:\nNumber of Iterations....: 1\nEXIT: Optimal Solution Found.\n')
        result = audit_counts(text, 1); work = result['work']
        self.assertEqual(work['mandatory_corrections'], 2)
        self.assertEqual(work['excess_corrections'], 1)
        self.assertEqual(work['recovery_restarts'], 1)
        self.assertEqual(work['refinement_failures'], 2)
        self.assertEqual(work['episode_final_ratios_above_target'], 2)
        self.assertEqual(work['direction_final_ratios_above_target'], 1)
        self.assertEqual(result['trace']['wrapper_solves'], 6)
        recovered = text.replace(solve('1e-4')+solve('1e-5')+failure+
            'Just accept current solution.\n', solve('1e-4')+solve('1e-12'))
        work = audit_counts(recovered, 1)['work']
        self.assertEqual(work['episode_final_ratios_above_target'], 1)
        self.assertEqual(work['direction_final_ratios_above_target'], 0)
        self.assertEqual(work['refinement_failures'], 1)

    def test_eighth_component_is_included(self):
        r = audit(sample(), 1)
        self.assertEqual(len(r['norm_ratio_checks']), 2)
        self.assertEqual(r['norm_ratio_checks'][0]['residual_max'], 2e-12)
        self.assertFalse(r['timing_eligible'])

    def test_rounding_intervals(self):
        self.assertEqual(printed_interval('1.00e+02'), (D('99.5'), D('100.5')))
        self.assertEqual(printed_interval('0.00e+00'), (D(0), D(0)))
        for bad in ('nan', '-1.00e+00', '1.0', 'inf'):
            with self.assertRaises(ValueError): printed_interval(bad)

    def test_cap_and_zero_branch(self):
        one = (D(1), D(1)); zero = (D(0), D(0))
        self.assertEqual(ratio_interval(one, (D('1e9'), D('1e9')), one),
                         (D(1)/D(1000001),)*2)
        self.assertEqual(ratio_interval(zero, zero, one), one)
        with self.assertRaises(ValueError): ratio_interval((D(0), D(1)), zero, one)
        with self.assertRaises(ValueError): ratio_interval((D(-1), D(1)), one, one)

    def test_underreported_minimum_and_invalid_claims(self):
        for minimum in (2, -1, 11, True, 1.0):
            with self.assertRaises(ValueError): audit(sample(), minimum)
        audit(sample(), 0)

    def test_corrupt_ratio_and_norms(self):
        for old, new in [('5.000000e-13', '9.000000e-13'),
                         ('nrm_resid = 2.00e-12', 'nrm_resid = 3.00e-12'),
                         ('max-norm resid_vU 2.000000e-12', 'max-norm resid_vU 0.000000e+00'),
                         ('nrm_rhs = 1.00e+00', 'nrm_rhs = 9.00e+00')]:
            with self.assertRaises(ValueError): audit(sample().replace(old, new, 1), 1)

    def test_incomplete_residual_and_duplicate_norms(self):
        for text in (sample().replace('with 8 components:', 'with 7 components:', 1),
                     sample().replace('resid[7][ 1]=', 'missing[7][ 1]=', 1),
                     sample().replace('max-norm resid_x 0.000000e+00',
                         'max-norm resid_x 0.000000e+00\nmax-norm resid_x 0.000000e+00', 1),
                     sample().replace('nrm_rhs =', 'missing_rhs =', 1)):
            with self.assertRaises(ValueError): audit(text, 1)


if __name__ == '__main__':
    unittest.main()
