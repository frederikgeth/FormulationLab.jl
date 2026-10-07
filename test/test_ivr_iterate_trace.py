import copy
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'examples'))
from ivr_iterate_trace import associate

CALL='Calling MUMPS-3 for solve.\nDone with MUMPS-3 for solve.\n'
TEXT=('This is Ipopt version 3.14.19, running with linear solver MUMPS.\n'+CALL+
    '*** Beginning Iteration 0 from the following point:\n'
    'Current barrier parameter mu = 1e-1\nBarrier Parameter: 1e-3\n'
    '*** Solving the Primal Dual System for Iteration 0:\n'
    'Solving system with delta_x=1e-4 delta_s=1e-4\n delta_c=0 delta_d=0\n'
    'Calling MUMPS-2 for numerical factorization.\n'+CALL+'residual_ratio = 1e-11\n'+
    CALL+'residual_ratio = 1e-16\n'
    '*** Finding Acceptable Trial Point for Iteration 0:\n'
    'Number of Iterations....: 1\nEXIT: Optimal Solution Found.\n')
CAPTURE=dict(schema='FormulationLab.ipopt_iterates.v1',timing_eligible=False,
    records=[dict(iteration=i,mode=0,mu=.1,regularization=0.) for i in range(2)])

class IterateAssociationTests(unittest.TestCase):
    def test_distinct_callback_and_direction(self):
        r=associate(TEXT,CAPTURE);b=r['iterations'][0]
        self.assertTrue(b['barrier_updated'])
        self.assertEqual((b['callback_mu'],b['direction_mu_printed']),(.1,.001))
        self.assertEqual(b['callback_regularization'],0.)
        self.assertEqual(b['direction_regularization_attempts'][0]['x'],.0001)
        self.assertEqual((b['factorizations'],b['corrections']),(1,1))
        self.assertFalse(r['timing_eligible'])

    def test_reject_incomplete_or_ambiguous(self):
        for text in (TEXT.replace('Barrier Parameter: 1e-3\n',''),
                     TEXT.replace('delta_c=0 delta_d=0','delta_c=0'),
                     TEXT.replace('Current barrier parameter mu = 1e-1','Current barrier parameter mu = 2e-1'),
                     TEXT.replace('delta_x=1e-4','delta_x=-1e-4'),
                     TEXT.replace('Barrier Parameter: 1e-3','Barrier Parameter: 1e-3\nBarrier Parameter: 1e-3')):
            with self.subTest(text=text),self.assertRaises(ValueError): associate(text,CAPTURE)

    def test_reject_wrong_capture(self):
        for key,value in [('schema','unknown'),('timing_eligible',True),('records',CAPTURE['records'][:1])]:
            c=copy.deepcopy(CAPTURE);c[key]=value
            with self.subTest(key=key),self.assertRaises(ValueError): associate(TEXT,c)
        c=copy.deepcopy(CAPTURE);c['records'][0]['mode']=1
        with self.assertRaises(ValueError): associate(TEXT,c)

if __name__=='__main__':unittest.main()
