from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'examples'))
import ivr_kkt_export as E
from test_ivr_kkt_row_units import fixture,action

class ExportTests(unittest.TestCase):
    def test_complete_matrix_and_zero_pattern(self):
        k,a=fixture();q=[1.]*7
        d=E.canonical(dict(matrix=k,rhs=action(a,q),solution=q))
        restored=[[0.]*7 for _ in range(7)]
        for i,j,v in zip(d['rows'],d['columns'],d['values']):
            restored[i-1][j-1]=restored[j-1][i-1]=v
        self.assertEqual(restored,a)
        k['W']['rows'] += [1];k['W']['columns'] += [1];k['W']['values'] += [-4.5]
        out=E.canonical(dict(matrix=k,rhs=[0.]*7,solution=None))
        self.assertIn((1,1,0.),list(zip(out['rows'],out['columns'],out['values'])))
        self.assertEqual(len(set(zip(out['rows'],out['columns']))),len(out['values']))
    def test_bad_rhs(self):
        k,_=fixture()
        for rhs in [[0.], [float('nan')]*7]:
            with self.assertRaises(ValueError):E.canonical(dict(matrix=k,rhs=rhs,solution=None))

if __name__=='__main__':unittest.main()
