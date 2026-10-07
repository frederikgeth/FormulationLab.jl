import copy,sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'examples'))
import ivr_initial_state as I

class InitialState(unittest.TestCase):
    def pair(self):
        maps=dict(free=[0,1],equality=[0],inequality=[1,2],x_L=[0],x_U=[1],s_L=[0],s_U=[1])
        a=dict(maps=maps,scales=dict(c=[1.],d=[.5,.25]),state=dict(
            curr_x=[2.,3.],curr_s=[1.,2.],curr_y_c=[.3],curr_y_d=[-3.,4.],
            curr_slack_x_L=[2.],curr_slack_x_U=[4.],curr_z_L=[.2],curr_z_U=[.4],
            curr_slack_s_L=[.5],curr_slack_s_U=[1.],curr_v_L=[3.],curr_v_U=[4.]))
        b=copy.deepcopy(a);b['scales']['d']=[1.,1.]
        # Independently supplied target: A=diag(2,4).
        b['state'].update(curr_s=[2.,8.],curr_y_d=[-1.5,1.],
            curr_slack_s_L=[1.],curr_slack_s_U=[4.],curr_v_L=[1.5],curr_v_U=[1.])
        return a,b
    def test_complete_mapping_and_inverse(self):
        a,b=self.pair()
        for left,right in [(a,b),(b,a),(a,a)]:
            d=I.compare(left,right);self.assertTrue(d['coordinate_equivalent'])
            self.assertEqual(max(d['state_gaps'].values()),0.)
    def test_multiplier_reset_is_detected(self):
        a,b=self.pair();b['state']['curr_v_L']=[3.]
        d=I.compare(a,b)
        self.assertFalse(d['coordinate_equivalent'])
        self.assertGreater(d['complementarity_gaps']['L'],0.)
        self.assertGreater(d['barrier_curvature_gaps']['L'],0.)
    def test_invalid_or_missing_state_is_refused(self):
        for mutation in [lambda b:b['scales']['d'].__setitem__(0,0.),
                         lambda b:b['state']['curr_x'].pop(),
                         lambda b:b['state']['curr_slack_s_U'].__setitem__(0,-1.),
                         lambda b:b['state']['curr_y_d'].__setitem__(0,float('nan'))]:
            a,b=self.pair();mutation(b)
            with self.assertRaises(ValueError):I.compare(a,b)
    def test_layout_change_is_refused(self):
        a,b=self.pair();b['maps']['free']=[1,0]
        with self.assertRaises(ValueError):I.compare(a,b)

if __name__=='__main__':unittest.main()
