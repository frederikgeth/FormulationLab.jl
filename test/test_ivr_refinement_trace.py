"""Restricted log classifier tests; no solver installation or benchmark required."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('refinement', Path(__file__).parents[1] / 'examples/ivr_refinement_trace.py')
trace = importlib.util.module_from_spec(spec); spec.loader.exec_module(trace)
CALL = 'Calling MUMPS-3 for solve.\nDone with MUMPS-3 for solve.\n'
START = '*** Solving the Primal Dual System for Iteration 0:\n'
STOP = '*** Finding Acceptable Trial Point for Iteration 0:\n'


def run(body, initial=CALL):
    return ('This is Ipopt version 3.14.19, running with linear solver MUMPS.\n' + initial + START + body + STOP +
            'Number of Iterations....: 1\nEXIT: Optimal Solution Found.\n')


def solve(ratio):
    return CALL + f'residual_ratio = {ratio}\n'


class RefinementTraceTests(unittest.TestCase):
    def test_required_correction_below_threshold_is_still_a_correction(self):
        d = trace.parse(run(solve('1e-12') + solve('1e-16')))
        self.assertEqual(d['counts']['initial'], 1)
        self.assertEqual(d['counts']['refinement'], 1)
        self.assertEqual(d['counts']['before_iterations'], 1)
        self.assertEqual(d['corrections_beyond_first'], 0)
        self.assertFalse(d['timing_eligible'])

    def test_extra_corrections_and_buffered_fortran_noise(self):
        noise = 'Entering DMUMPS 5.9.1 from C interface with JOB, N, NNZ = 3 999 999\n'
        d = trace.parse(run(solve('1e-4') + noise + solve('1e-7') + solve('1e-11')))
        self.assertEqual(d['wrapper_solves'], 4)
        self.assertEqual(d['corrections_beyond_first'], 1)
        self.assertEqual(d['episodes'][0]['corrections'], [1e-7, 1e-11])

    def test_quality_and_singularity_restarts_are_not_corrections(self):
        body = solve('1e-3') + solve('1e-2')
        body += ('Iterative refinement failed with residual_ratio = 1e-2\n'
                 'Asking augmented system solver to improve quality of its solutions.\n'
                 'Increasing pivot tolerance for MUMPS from 1.00e-06 to 1.00e-03.\n'
                 'Calling MUMPS-2 for numerical factorization.\n')
        body += solve('1e-2') + solve('1e-1')
        body += ('Iterative refinement failed with residual_ratio = 1e-1\n'
                 'Pretend that the current system (including modifications) is singular.\n'
                 'Calling MUMPS-2 for numerical factorization.\n')
        body += solve('1e-11') + solve('1e-14')
        d = trace.parse(run(body))
        self.assertEqual(d['wrapper_factorizations'], 2)
        self.assertEqual(d['counts'], dict(before_iterations=1, initial=1, refinement=3, quality_restart=1, singularity_restart=1))
        self.assertEqual(len(d['episodes']), 3)

    def test_acceptance_after_failure_does_not_create_a_restart(self):
        d = trace.parse(run(solve('1e-3') + solve('1e-4') +
                            'Iterative refinement failed with residual_ratio = 1e-4\nJust accept current solution.\n'))
        self.assertEqual(d['wrapper_solves'], 3)
        self.assertEqual(len(d['episodes']), 1)

    def test_missing_and_duplicate_residuals_refuse(self):
        for body in (CALL, CALL + CALL, solve('1e-9') + 'residual_ratio = 1e-10\n'):
            with self.assertRaises(ValueError): trace.parse(run(body))

    def test_invalid_numeric_residuals_refuse(self):
        for value in ('nan', 'inf', '-1e-8', '1e999', 'junk'):
            with self.assertRaises(ValueError): trace.parse(run(solve(value)))

    def test_nested_missing_and_unmatched_completions_refuse(self):
        for body in ('Calling MUMPS-3 for solve.\n', 'Done with MUMPS-3 for solve.\n',
                     'Calling MUMPS-3 for solve.\n' + CALL):
            with self.assertRaises(ValueError): trace.parse(run(body))

    def test_unsupported_post_block_solve_refuses(self):
        text = run(solve('1e-11') + solve('1e-12')).replace(STOP, STOP + CALL)
        with self.assertRaises(ValueError): trace.parse(text)

    def test_missing_version_iteration_and_exit_refuse(self):
        good = run(solve('1e-11') + solve('1e-12'))
        for text in (good.replace('3.14.19', '3.14.18'), good.replace('EXIT:', 'unfinished:'),
                     good.replace('Iterations....: 1', 'Iterations....: 2'), good + good, good.replace(STOP, '')):
            with self.assertRaises(ValueError): trace.parse(text)

    def test_unclassified_refactorization_and_unfinished_restart_refuse(self):
        for tail in ('Calling MUMPS-2 for numerical factorization.\n',
                     'Increasing pivot tolerance for MUMPS from 1e-6 to 1e-3.\n'):
            with self.assertRaises(ValueError): trace.parse(run(solve('1e-9') + tail))

    def test_multiple_iterations_reset_episode(self):
        text = run(solve('1e-11') + solve('1e-12'))
        second = (START + solve('1e-8') + solve('1e-11') + STOP).replace('Iteration 0:', 'Iteration 1:')
        text = text.replace('Number of Iterations', second + 'Number of Iterations').replace('Iterations....: 1', 'Iterations....: 2')
        d = trace.parse(text)
        self.assertEqual(d['counts']['initial'], 2)
        self.assertEqual([e['iteration'] for e in d['episodes']], [0, 1])


if __name__ == '__main__':
    unittest.main()
