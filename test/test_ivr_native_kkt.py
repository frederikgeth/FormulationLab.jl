import sys
from pathlib import Path
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'examples'))
import ivr_native_kkt as K


def dense(name,values,homogeneous=False):
    s=f'DenseVector "{name}" with {len(values)} elements:\n'
    if homogeneous:return s+f'Homogeneous vector, all elements have value {values[0] if values else 0}\n'
    return s+''.join(f'{name}[ {i}]= {v}\n' for i,v in enumerate(values,1))


def fixture():
    blocks={
        (0,0):'SumSymMatrix "KKT[0][0]" of dimension 1 with 2 terms:\n'
        'Term 0 with factor 1 and the following matrix:\n'
        'SymTMatrix "Term: 0" of dimension 1 with 2 nonzero elements:\n'
        'Term: 0[ 1, 1]= 1 (0)\nTerm: 0[ 1, 1]= 3 (1)\n'
        'Term 1 with factor 1 and the following matrix:\n'+dense('Term: 1',[1]),
        (1,1):dense('KKT[1][1]',[2]),
        (2,0):'GenTMatrix "KKT[2][0]" of dimension 1 by 1 with 1 nonzero elements:\nKKT[2][0][ 1, 1]= 2 (0)\n',
        (2,2):dense('KKT[2][2]',[-.1],True),
        (3,0):'GenTMatrix "KKT[3][0]" of dimension 1 by 1 with 1 nonzero elements:\nKKT[3][0][ 1, 1]= 3 (0)\n',
        (3,1):'IdentityMatrix "KKT[3][1]" with 1 rows and columns and the factor -1.\n',
        (3,3):dense('KKT[3][3]',[-.2])}
    return 'CompoundSymMatrix "KKT" with 4 rows and columns components:\n'+''.join(
        f'Component for row {i} and column {j}:\n'+blocks.get((i,j),'This component has not been set.\n')
        for i in range(4) for j in range(i+1))


class NativeKKTTests(unittest.TestCase):
    def test_known_matrix_and_duplicates(self):
        k=K.matrix(fixture())
        self.assertEqual(k['dimensions'],[1,1,1,1])
        actual=K.multiply(k,[1,2,3,4])
        for a,b in zip(actual,[23,0,1.7,.2]):self.assertAlmostEqual(a,b)
        self.assertEqual(k['W']['values'],[1,3])

    def test_native_system(self):
        rhs='CompoundVector "RHS[ 0]" with 4 components:\n'+''.join(dense(f'RHS[ 0][{i}]',[v]) for i,v in enumerate([23,0,1.7,.2]))
        sol='CompoundVector "SOL[ 0]" with 4 components:\n'+''.join(dense(f'SOL[ 0][{i}]',[v]) for i,v in enumerate([1,2,3,4]))
        text=rhs+fixture()+'Right hand side 0 in TSymLinearSolver:\n'+sol
        self.assertLess(K.calls(text)[0]['residual_max'],1e-14)
        with self.assertRaises(ValueError):K.calls(text.replace(sol,''))
        failed=K.calls(text.replace(sol,'Factorization failed with retval = 2\n'))
        self.assertIsNone(failed[0]['solution'])
        level10=text.replace('Right hand side 0 in TSymLinearSolver:','Calling MUMPS-3 for solve.')
        level10='Solving system with delta_x=0 delta_s=0\n delta_c=0 delta_d=0\n'+level10
        self.assertEqual(K.calls(level10)[0]['regularization'],[0,0,0,0])

    def test_vectors(self):
        self.assertEqual(K.vector(dense('x',[1,1],True),'x'),[1,1])
        self.assertEqual(K.vector(dense('x',[]),'x'),[])
        self.assertEqual(K.vector(dense('x',[],True),'x'),[])
        for s in [dense('x',[1,2]).replace('x[ 2]= 2\n',''),dense('x',[1])+dense('x',[1]),dense('x',[1]).replace('1 elements','2 elements')]:
            with self.assertRaises(ValueError):K.vector(s,'x')

    def test_fail_closed(self):
        for text in [fixture().replace('Term: 0[ 1, 1]= 3 (1)\n',''),
                     fixture().replace('Term: 0[ 1, 1]= 3 (1)','Term: 0[ 2, 1]= 3 (1)'),
                     fixture().replace('factor -1.','factor 1.'),
                     fixture().replace('Component for row 3 and column 3:','Component for row 3 and column 2:'),
                     fixture().replace('This component has not been set.','unknown block',1)]:
            with self.subTest(text=text),self.assertRaises(ValueError):K.matrix(text)
        with self.assertRaises(ValueError):K.multiply(K.matrix(fixture()),[1])

    def test_stream_coverage(self):
        text='*** Beginning Iteration 2 from the following point:\nabc\n*** Finding Acceptable Trial Point for Iteration 2:\n'
        self.assertEqual(list(K.iteration_blocks(text.splitlines(True),{2})),[(2,text)])
        for lines,selection in [(text.splitlines(True),{2,3}),(text.splitlines(True)[:-1],{2}),((text+text).splitlines(True),{2})]:
            with self.assertRaises(ValueError):list(K.iteration_blocks(lines,selection))

    def test_bound_diagonal_requires_multiplier_and_index_map(self):
        self.assertEqual(K.bound_diagonal([2,4],[6,8],[2,0],3),[2,0,3])
        for args in [([0],[1],[0],1),([1],[-1],[0],1),([1],[1],[1],1),
                     ([1,1],[1,1],[0,0],2),([1],[1,2],[0],1)]:
            with self.assertRaises(ValueError):K.bound_diagonal(*args)

    def test_layout_fixed_variables_and_bound_positions(self):
        layout=dict(variables=[dict(column=1,fixed=True,lower=2,upper=2),dict(column=2,fixed=False,lower=None,upper=3)],
            constraints=[dict(row=1,lower=0,upper=0),dict(row=2,lower=-1,upper=None),dict(row=3,lower=None,upper=2)])
        m=K.layout_maps(layout)
        self.assertEqual(m,dict(free=[1],equality=[0],inequality=[1,2],x_L=[],x_U=[0],s_L=[0],s_U=[1]))
        layout['variables'][1]['upper']=1e20
        with self.assertRaises(ValueError):K.layout_maps(layout)

    def test_sparse_entries_refuse_nonfinite_or_truncation(self):
        for a in [dict(shape=[1,1],rows=[1],columns=[],values=[1]),
                  dict(shape=[1,1],rows=[1],columns=[1],values=[float('nan')])]:
            with self.assertRaises(ValueError):K.entries(a)

    def test_explicit_positive_row_scaling(self):
        name='KKT[3][0]'
        text=f'ScaledMatrix "{name}" of dimension 1 x 1:\n'+dense(name+'_row_scaling',[.25])
        text+=f'GenTMatrix "{name}_unscaled_matrix" of dimension 1 by 1 with 1 nonzero elements:\n{name}_unscaled_matrix[ 1, 1]= 8 (0)\n'
        a=K.jacobian_block(text,name)
        self.assertEqual(a['values'],[2.])
        self.assertEqual(a['row_scaling'],[.25])
        with self.assertRaises(ValueError):K.jacobian_block(text+'\n_column_scaling',name)
        with self.assertRaises(ValueError):K.jacobian_block(text.replace('= 0.25','= -0.25'),name)

    def test_complete_scaled_reconstruction_and_wrong_dual(self):
        import copy
        pre=''.join(dense(name,values) for name,values in [
            ('curr_x',[1]),('curr_s',[1]),('curr_y_c',[.3]),('curr_y_d',[.4]),
            ('curr_slack_x_L',[1]),('curr_z_L',[1]),('curr_slack_x_U',[]),('curr_z_U',[]),
            ('curr_slack_s_L',[]),('curr_v_L',[]),('curr_slack_s_U',[1]),('curr_v_U',[2])])
        name='KKT[3][0]'
        plain=f'GenTMatrix "{name}" of dimension 1 by 1 with 1 nonzero elements:\n{name}[ 1, 1]= 3 (0)\n'
        scaled=f'ScaledMatrix "{name}" of dimension 1 x 1:\n'+dense(name+'_row_scaling',[.25])
        scaled+=f'GenTMatrix "{name}_unscaled_matrix" of dimension 1 by 1 with 1 nonzero elements:\n{name}_unscaled_matrix[ 1, 1]= 12 (0)\n'
        rhs='CompoundVector "RHS[ 0]" with 4 components:\n'+''.join(dense(f'RHS[ 0][{i}]',[v]) for i,v in enumerate([23,0,1.7,.2]))
        sol='CompoundVector "SOL[ 0]" with 4 components:\n'+''.join(dense(f'SOL[ 0][{i}]',[v]) for i,v in enumerate([1,2,3,4]))
        text=pre+'Solving system with delta_x=0 delta_s=0\n delta_c=.1 delta_d=.2\n'+rhs+fixture().replace(plain,scaled)+'Calling MUMPS-3 for solve.\n'+sol
        layout=dict(variables=[dict(column=1,fixed=False,lower=0,upper=None)],
            constraints=[dict(row=1,lower=0,upper=0),dict(row=2,lower=None,upper=8)])
        record=dict(iteration=0,scaled=dict(x=[1],z_L=[1],z_U=[0],g=[0,1.25],**{'lambda':[.3,.4]}),
            unscaled=dict(x=[1],z_L=[2],z_U=[0],g=[0,5],**{'lambda':[.6,.2]}))
        d=dict(hessian=dict(shape=[1,1],rows=[1],columns=[1],values=[8]),
            jacobian=dict(shape=[2,1],rows=[1,2],columns=[1,1],values=[2,12]))
        self.assertTrue(K.audit_state(text,record,d,layout)['passed'])
        self.assertTrue(K.audit_state(text,record,d,layout,initial_row_scaling=dict(c=[1.],d=[.25]))['passed'])
        with self.assertRaises(ValueError):K.audit_state(text,record,d,layout,initial_row_scaling=dict(c=[1.],d=[1.]))
        wrong=copy.deepcopy(record);wrong['unscaled']['lambda'][1]=.8
        with self.assertRaises(ValueError):K.audit_state(text,wrong,d,layout)
        bad=copy.deepcopy(d);bad['hessian']['values'][0]=9
        with self.assertRaises(ValueError):K.audit_state(text,record,bad,layout)

if __name__=='__main__':unittest.main()
