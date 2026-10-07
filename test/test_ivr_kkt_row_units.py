import copy
import math
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'examples'))
import ivr_kkt_row_units as U
import ivr_native_kkt as K


def sparse(shape, positions, scaling=None):
    result = dict(shape=shape, rows=[p[0] for p in positions],
                  columns=[p[1] for p in positions], values=[p[2] for p in positions])
    if scaling is not None:
        result['row_scaling'] = scaling
    return result


def fixture():
    k = dict(dimensions=[2, 2, 1, 2], W_factor=1.,
             W=sparse([2, 2], [(1, 1, 4.), (2, 1, 1.), (2, 2, 6.)]),
             x_diagonal=[.5, .2], s_diagonal=[2., 3.], c_diagonal=[-.1], d_diagonal=[-.2, -.3],
             J_c=sparse([1, 2], [(1, 1, 1.), (1, 2, 2.)], [.5]),
             J_d=sparse([2, 2], [(1, 1, 3.), (1, 2, 4.), (2, 1, 5.), (2, 2, 6.)], [.25, 2.]))
    dense = [[4.5, 1., 0., 0., 1., 3., 5.],
             [1., 6.2, 0., 0., 2., 4., 6.],
             [0., 0., 2., 0., 0., -1., 0.],
             [0., 0., 0., 3., 0., 0., -1.],
             [1., 2., 0., 0., -.1, 0., 0.],
             [3., 4., -1., 0., 0., -.2, 0.],
             [5., 6., 0., -1., 0., 0., -.3]]
    return k, dense


def action(a, x):
    return [sum(v*w for v, w in zip(row, x)) for row in a]


def solve(a, b):
    """Independent small dense Gaussian elimination with partial pivoting."""
    a = [list(row)+[v] for row, v in zip(a, b)]
    n = len(b)
    for i in range(n):
        pivot = max(range(i, n), key=lambda j: abs(a[j][i]))
        a[i], a[pivot] = a[pivot], a[i]
        if abs(a[i][i]) < 1e-14:
            raise ValueError('singular calibration')
        for j in range(i+1, n):
            ratio = a[j][i]/a[i][i]
            for c in range(i, n+1):
                a[j][c] -= ratio*a[i][c]
    x = [0.]*n
    for i in reversed(range(n)):
        x[i] = (a[i][-1]-sum(a[i][j]*x[j] for j in range(i+1, n)))/a[i][i]
    return x


class RowUnitTests(unittest.TestCase):
    def test_independent_dense_matrix_and_solves(self):
        k, dense = fixture()
        saved = copy.deepcopy(k)
        # Independently derived from old scales [.5], [.25,2] and new [2], [1,.5].
        t = [1., 1., .25, 4., 4., 4., .25]
        changed = U.change_units(k, [2.], [1., .5])
        self.assertEqual(U.coordinate_map(k, [2.], [1., .5]), t)
        explicit = [[t[i]*dense[i][j]*t[j] for j in range(7)] for i in range(7)]
        for j in range(7):
            basis = [float(i == j) for i in range(7)]
            self.assertLess(K.relative_gap(K.multiply(changed, basis), action(explicit, basis)), 1e-14)
        b = [1., -2., 3., 4., -5., 6., 7.]
        old_q = solve(dense, b)
        new_q = solve(explicit, [a*v for a, v in zip(t, b)])
        self.assertLess(K.relative_gap(old_q, [a*v for a, v in zip(t, new_q)]), 1e-13)
        self.assertLess(K.relative_gap(action(dense, old_q), b), 1e-13)
        self.assertEqual(k, saved)
        self.assertEqual(U.change_units(changed, [.5], [.25, 2.]), k)

    def test_residual_and_backward_error_covariance(self):
        k, dense = fixture()
        # Deliberately inexact solution: the residual is nonzero and observable.
        q = [1., 2., -1., 3., 4., -2., 5.]
        b = [v + .001*(i+1) for i, v in enumerate(action(dense, q))]
        call = dict(matrix=k, rhs=b, solution=q)
        report = U.audit_call(call, [2.], [1., .5])
        self.assertTrue(report['passed'])
        self.assertFalse(report['independently_refactorized'])
        self.assertAlmostEqual(report['original_backward_error'], report['transformed_backward_error'], places=14)
        expected = max(abs(a-v)/(sum(abs(w)*abs(z) for w,z in zip(row,q))+abs(v))
                       for a,v,row in zip(action(dense,q),b,dense))
        self.assertAlmostEqual(U.backward_error(k,q,b), expected, places=15)
        call['solution'] = None
        self.assertTrue(U.audit_call(call, [2.], [1., .5])['passed'])

    def test_identity_and_wrong_regularization(self):
        k, dense = fixture()
        self.assertEqual(U.change_units(k, [.5], [.25, 2.]), k)
        changed = U.change_units(k, [1.], [1., 1.])
        q = solve(dense, [1.]*7)
        t = U.coordinate_map(k, [1.], [1., 1.])
        new_q, new_b = U.map_vector(q,t,inverse=True), U.map_vector([1.]*7,t)
        self.assertLess(K.relative_gap(K.multiply(changed,new_q), new_b), 1e-13)
        # Retaining a uniform old dual regularization is a different matrix.
        wrong = copy.deepcopy(changed)
        wrong['c_diagonal'] = k['c_diagonal']
        wrong['d_diagonal'] = k['d_diagonal']
        self.assertGreater(K.relative_gap(K.multiply(wrong,new_q), new_b), .01)

    def test_bound_distance_multiplier_and_centrality(self):
        distances, multipliers, a = [2., 3.], [4., 5.], [.25, 4.]
        old = K.bound_diagonal(distances,multipliers,[0,1],2)
        new = K.bound_diagonal([v*r for v,r in zip(distances,a)],
                              [v/r for v,r in zip(multipliers,a)],[0,1],2)
        self.assertEqual(new, [v/r**2 for v,r in zip(old,a)])
        self.assertEqual([v*w for v,w in zip(distances,multipliers)],
                         [(v*r)*(w/r) for v,w,r in zip(distances,multipliers,a)])

    def test_duplicate_and_cancelled_diagonal_backward_error(self):
        k, dense = fixture()
        k['W']['rows'] += [1,1]; k['W']['columns'] += [1,1]; k['W']['values'] += [7.,-7.]
        k['x_diagonal'][0] = -4.; dense[0][0] = 0.
        q=[1.]*7; b=[v+.01 for v in action(dense,q)]
        expected=max(abs(a-v)/(sum(abs(w) for w in row)+abs(v)) for a,v,row in zip(action(dense,q),b,dense))
        self.assertAlmostEqual(U.backward_error(k,q,b),expected,places=14)

    def test_bad_units_and_vectors_fail_closed(self):
        k, _ = fixture()
        for c,d in [([], [1.,1.]), ([0.],[1.,1.]), ([1.],[math.nan,1.]),
                    ([1.],[math.inf,1.]), ([1.],[-1.,1.]), ([1e308],[1.,1.])]:
            with self.subTest(c=c,d=d), self.assertRaises(ValueError):
                U.change_units(k,c,d)
        for values,t in [([1.],[]),([math.nan],[1.]),([1.],[0.])]:
            with self.assertRaises(ValueError):U.map_vector(values,t)

if __name__ == '__main__':
    unittest.main()
