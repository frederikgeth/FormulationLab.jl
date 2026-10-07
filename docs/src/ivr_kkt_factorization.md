# Fresh factorizations after an exact row-unit change

The [row-unit control](ivr_kkt_row_units.md) verified an algebraic congruence of
retained KKT systems. This follow-up independently factors both matrices and
solves their right-hand sides. It examines numerical accuracy and preprocessing;
no whole-Ipopt timing or formulation ranking is inferred.

## Experimental distinction

The matrix pair is ``\widehat K=TKT`` and the RHS pair is
``\widehat b=Tb``, with ``T`` defined in the row-unit study. A freshly computed
``\widehat q`` is mapped back as ``q_{\mathrm{mapped}}=T\widehat q``.
Unlike the previous control, neither solution is obtained by simply transforming
an existing native direction.

The retained inputs are printed Float64 coefficients. Repeated lower-triangular
contributions are summed, explicit zeros are retained, and both members use the
same sparsity pattern. This canonicalization is checked against the native block
operator before export. The transformed coefficients and RHS are rounded to
Float64. Thus paired direction differences can include these small data
perturbations as well as numerical factorization/solve error; they do not identify
pivoting as the sole cause. Native directions are comparison values, not exact
solutions of the rounded matrices.

All 58 calls at the same 13 states are retained. The 45 powers-only calls have
``T=I`` and act as exact duplicate controls. The 13 broad-lifting calls remove the
897 additional NLP scales on LV lower-voltage bounds. The physical state,
objective scale and existing regularization are fixed. Calls include correction
RHSs from iterative refinement and are not 58 independent physical states.

## Solver controls and calibration

`examples/ivr_mumps_bridge.c` uses the installed MUMPS 5.9.1 C headers, while
`examples/ivr_kkt_factor.jl` obtains the library from the installed Ipopt package.
The bridge uses 32-bit integer indices and real symmetric indefinite mode. It
owns only the solver handle; Julia preserves the input arrays until cleanup.
No installed solver source or production model implementation is changed.

Each call has four independent numerical factorizations:

| Regime | Original units | Unit row scales | Comparison control |
|:---|:---|:---|:---|
| Automatic | Fresh analysis and factorization | Fresh analysis and factorization | Same preprocessing settings; effective orders may differ |
| Given order, no scaling | Fresh factorization from supplied order | Fresh factorization from the same supplied order | Effective output permutations must match; effective scaling must be zero |

The automatic regime requests MUMPS `ICNTL(6,7,8)=(7,7,77)`. The controlled regime
uses `(0,1,0)` and supplies the original automatic permutation. MUMPS may
reorganize a supplied order; the test therefore compares the **effective output
orders of the pair**. The first reader incorrectly required output order to equal
input order and rejected the large cases. Those results are preserved; the
corrected replay keeps the same selection and settings. This behavior is specified
in §5.6.2 of the [MUMPS 5.9.1 guide](https://mumps-solver.org/doc/userguide_5.9.1.pdf).

Both regimes use one BLAS thread, pivot threshold ``10^{-6}``, no internal
iterative refinement, no singular-pivot substitution, no BLR compression, and a
sequential root. The [Ipopt 3.14.19 MUMPS interface](https://github.com/coin-or/Ipopt/blob/releases/3.14.19/src/Algorithm/LinearSolvers/IpMumpsSolverInterface.cpp)
provides the corresponding baseline controls. This is not a replay of Ipopt's
adaptive pivot thresholds, symbolic-factor reuse or complete refinement logic.

The calibration independently assembles a seven-dimensional indefinite matrix
with nonzero regularization and checks against a dense solve. A larger sparse
matrix checks the paired ordering contract. Malformed inputs are rejected before
entering C; a singular matrix checks failure reporting and cleanup. Factorization
inertia is checked against dense eigenvalues on the small matrix.

## Right-hand sides, refinement and accuracy

Each factorization is used for two RHSs: the retained native RHS and a
manufactured RHS. The manufactured reference is the Float64 vector
``q_i^*=\sin(i)``. Its RHS is accumulated at 256-bit precision from the original
Float64 matrix, then rounded to Float64. The transformed manufactured RHS is
``T b^*``; it is not independently regenerated from the transformed matrix.
Consequently forward differences from ``q^*`` include RHS rounding and do not
constitute a condition-number estimate.

For both RHSs, the initial solution and exactly two external refinement stages
are retained. At each stage, the residual is evaluated with 256-bit accumulation,
rounded to Float64, and solved using the existing factorization. Worsening stages
are retained. This is a declared diagnostic refinement algorithm, not Ipopt's
full primal-dual refinement procedure.

The componentwise backward error is

```math
\eta(q;b,K)=\max_i
\frac{|(b-Kq)_i|}{(|K||q|+|b|)_i}.
```

A zero numerator/denominator contributes zero; nonfinite metrics are refused.
This metric and the residual norm use 256-bit accumulation on the actual Float64
matrix, RHS and computed direction. Paired solutions are also checked in the
original coordinates. The declared quality gate requires final backward error
at most ``10^{-10}``; experiment completion and solution quality are separate.

## Results and interpretation

All **232 fresh factorizations and 1,392 RHS/refinement solves completed**.
The powers-only pairs reproduce identical solutions and factor reports. All
controlled pairs have identical effective orderings and zero solver scaling;
paired inertia agrees in both regimes. These checks establish the comparison
contract, not universal solution accuracy.

The following counts retain the declared final componentwise threshold
``\eta\le10^{-10}`` after two corrections:

| Regime | Lifting | Native RHS: original | Native RHS: unit rows | Manufactured RHS: original | Manufactured RHS: unit rows |
|:---|:---|---:|---:|---:|---:|
| Automatic | Powers | 30/45 | 30/45 | 45/45 | 45/45 |
| Automatic | Broad | 3/13 | 3/13 | 13/13 | 13/13 |
| Given order, no scaling | Powers | 34/45 | 34/45 | 45/45 | 45/45 |
| Given order, no scaling | Broad | 0/13 | 0/13 | 13/13 | 11/13 |

Only 29 of the 58 calls pass every declared quality gate across both regimes,
units and RHSs. The other outcomes are retained. With automatic preprocessing,
broad paired native directions differ by at most ``9.10\times10^{-15}`` after
mapping to the original coordinates; the corresponding maximum manufactured
direction difference is ``8.44\times10^{-12}``. Under the given-order/unscaled
control these maxima rise to ``5.60\times10^{-8}`` and ``2.19\times10^{-7}``.
These are componentwise discrepancies normalized by ``\max(1,|a|,|b|)``.

Removing the broad NLP scales changes automatic effective ordering in **4/13**
calls, factor-entry counts in **13/13** calls (at most 69 entries), and delayed
pivot counts in **11/13**. In the controlled regime, factor-entry and delayed-pivot
counts change in **2/13** calls, with at most 18 factor entries. Thus the row
units can influence numerical decisions even with the same symbolic ordering,
but the retained comparison supplies no consistent accuracy benefit from their
removal and no speed result. Differences between the two preprocessing regimes
cannot be attributed solely to solver scaling: matching and effective ordering
also differ between regimes.

A post-replay independent audit recomputes 52 final native-RHS vectors using
80-digit decimal arithmetic: the first call at each selected state, both regimes
and both units. It confirms the reported residuals and backward errors. Their
normwise backward errors,

```math
\frac{\lVert b-Kq\rVert_\infty}
{\lVert K\rVert_\infty\lVert q\rVert_\infty+\lVert b\rVert_\infty},
```

are all below ``3.68\times10^{-15}``. Some componentwise errors equal one
because both the row residual and its denominator are extremely small. For
example, an equality row in explicit broad lifting at iteration 22 has both
quantities about ``5.09\times10^{-36}``, while the whole-system normwise error
is ``1.79\times10^{-20}``. The strict failures therefore require row-level
interpretation; they are not evidence of physical infeasibility or uniformly
large absolute error. The original gate remains unchanged. Future diagnostics
should predeclare both absolute and relative criteria rather than silently
replace this metric after observing failures. The [rowwise follow-up](ivr_kkt_residuals.md)
retains all strict results and reports a fixed absolute-allowance grid on all
464 final vectors, with model provenance and independent decimal checks.

The [nonlinear follow-up](ivr_nonlinear_row_scaling.md) preserves the objective
scale and verifies initial internal states. Its native initializer changes 897
lower-slack bound multipliers relative to the equivalent coordinate map.
Automatic MUMPS preprocessing remains the baseline;
retain the given-order/unscaled regime as a diagnostic. No production scaling
change is justified by these results.

## Reproduction and limits

Use the docs environment, which includes Ipopt, and a C compiler:

```sh
julia --project=docs --startup-file=no test/ivr_kkt_factor.jl
python3 -m unittest discover -s test -p 'test_ivr_kkt_export.py'
```

For a parsed native call, `ivr_kkt_export.canonical(call)` produces a diagnostic
JSON input with canonical triplets, the RHS, the native direction, the coordinate
map and the action check. These diagnostic arrays are separate from the canonical
BMOPFTools-compatible physical solution export.

```julia
include("examples/ivr_kkt_factor.jl")
using JSON3
F = IVRKKTOfflineFactor
bridge = F.bridge(mktempdir())
data = JSON3.read(read("canonical_kkt.json", String), Dict{String,Any})
report = F.experiment(bridge, data)
```

This helper is deliberately version-restricted to the calibrated MUMPS library.
Full frozen drivers, input/output JSON, input hashes, factor reports and planning
documents live outside Git in `KKT_FACTORIZATION_20261007`. No timing from this
instrumented work is eligible for a speed ranking. All transformation choices
remain available. A nonlinear row-only intervention must additionally preserve
objective scaling and verify internal initialization; these offline results alone
do not establish its effect on the optimizer's trajectory.
