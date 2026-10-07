# Fixed-observation KKT elimination control

## Question and scope

[Fixed-input observation substitution](ivr_fixed_observations.md) removes six
scalar auxiliaries and six defining equations from each tested broad formulation.
Does removing those pairs change the accuracy of the corresponding linear solve?
This experiment compares each **retained augmented system with its exact block
elimination**, keeping its state, coefficients, regularization and right-hand side
fixed. It does not claim a matched native capture from a separately initialized
substituted NLP.

The panel contains all 13 previously retained broad-model systems at iterations
0, 22 and 24, plus the first iteration-0 system of each powers-only profile as
two identity controls. Several systems are correction solves at the same state;
these are not 15 independent networks. The selection is retrospective and follows
the [native KKT study](ivr_native_kkt.md). Structural preflight preceded the new
factorizations and identified nonzero, although small, defining-row RHS entries.

## Exact elimination, including a nonzero RHS

After permuting the retained coordinates ``r``, eliminated observation coordinates
``u`` and their equality multipliers ``y``, the admitted matrix has the form

```math
\begin{bmatrix}B&E&0\\E^\mathsf{T}&A&D\\0&D&0\end{bmatrix}
\begin{bmatrix}q_r\\q_u\\q_y\end{bmatrix}
=\begin{bmatrix}b_r\\b_u\\b_y\end{bmatrix},
```

where ``D`` is diagonal and nonsingular. The defining equality rows have no
other nonzero entries, including multiplier regularization. Therefore

```math
q_u=D^{-1}b_y,\qquad
Bq_r=b_r-ED^{-1}b_y,\qquad
q_y=D^{-1}(b_u-E^\mathsf{T}q_r-Aq_u).
```

The reduced matrix is the principal submatrix ``B``; the right-hand side is
generally **not** just ``b_r``. Discarding a tiny nonzero ``b_y`` changes the
linear system. Source-observation keys and fixed-input provenance identify the
pairs; numeric row indices are not assumed to survive formulation changes.
The helper refuses duplicate pairs, additional multiplier coupling and nonzero
multiplier regularization. It does not silently apply this formula to a more
general Schur complement.

`examples/ivr_kkt_fixed_observations.jl` forms the RHS correction and reconstructs
the removed coordinates with 256-bit accumulation, then rounds the outputs to
Float64. These operations and the canonical printed matrices retain rounding
error; algebraic equivalence does not imply bitwise equivalence of solutions.

## Calibration and reproducible example

The 27 calibration assertions cover signed non-unit ``D``, off-diagonal ``A``,
ordinary, zero and tiny defining-row RHSs, empty identity controls, malformed
pairs, prohibited regularization, dense reference solutions and MUMPS recovery.

```@example fixed_observation_kkt
using LinearAlgebra
include(joinpath(@__DIR__, "..", "..", "examples", "ivr_kkt_fixed_observations.jl"))
const Eliminate = IVRKKTFirstOrderElimination
K = [4.0 1 2 0; 1 -3 0.5 0; 2 0.5 5 2; 0 0 2 0]
b = [1.0, 2, 3, 4]
ij = [(i,j) for i in 1:4 for j in 1:i]
data = Dict("dimension"=>4, "rows"=>first.(ij), "columns"=>last.(ij),
    "values"=>[K[i,j] for (i,j) in ij], "rhs"=>b, "coordinate_map"=>ones(4))
control = Eliminate.control(data, [(3,4)])
reduced_rhs = Eliminate.reduce_rhs(control, b)
q = Eliminate.recover(control, K[1:2,1:2] \ reduced_rhs, b)
@assert reduced_rhs != b[1:2] # b_y is not zero
@assert q ≈ K \ b
@assert norm(K*q-b, Inf) < 1e-12
(original_dimension=4, reduced_dimension=length(control.keep), recovered=true)
```

Run the standalone calibration with
`julia --project=docs --startup-file=no test/ivr_kkt_fixed_observations.jl`.

## Results and interpretation

All 30 fresh automatic MUMPS factorizations succeed: full and reduced systems for
each of 15 inputs. Each factorization serves native and manufactured RHSs, with
the previously declared two external refinement steps. Manufactured RHSs use
the original full-coordinate ``q_i^*=\sin(i)``, 256-bit matrix action and Float64
rounding. Inertia loses exactly six negative eigenvalues per broad system, as
expected for six nonsingular variable/equality pairs. The two identity systems
retain their directions, permutations and factorization reports exactly.
All 30 original full-system directions reproduce the earlier automatic-factor
results exactly.

The broad augmented dimensions change from 45,492 to 45,480 with explicit
transformer currents, and from 45,300 to 45,288 with eliminated currents.
Residuals are evaluated against the **original full matrix and RHS after
recovery**, as well as against the reduced system. The original strict
componentwise criterion is ``\eta\le10^{-10}``. The additional grid is
``|r_i|\le a+10^{-10}(|K||q|+|b|)_i`` in original KKT row units, following
the [residual-magnitude study](ivr_kkt_residuals.md).

| RHS group | Directions | Strict passes: full → recovered | Passes with ``a=10^{-16}``: full → recovered |
|:---|---:|---:|---:|
| Broad, native | 13 | 3 → 6 | 13 → 13 |
| Broad, manufactured | 13 | 13 → 13 | 13 → 13 |
| Powers-only identities, both RHSs | 4 | 2 → 2 | 2 → 2 |

Across all 30 directions, pass counts for
``a=(0,10^{-16},10^{-14},10^{-12},10^{-10})`` change from
``(18,28,28,29,30)`` to ``(21,28,28,29,30)``. Original failures remain in the
archive; the reduced results do not replace their classifications.

The three new strict passes are native first calls at broad iteration 22 in
both current formulations and iteration 24 with eliminated currents. Seven
broad native directions still fail the strict criterion, with worst rows now
including other observation-stationarity and line-current slack rows. Every
broad native direction already passed the ``10^{-16}`` mixed allowance before
this intervention. Thus the change addresses particular small-denominator
failures without improving that mixed classification.

The maximum normalized full-direction change is ``1.11\times10^{-16}`` for
broad native RHSs and ``1.11\times10^{-15}`` for broad manufactured RHSs, using
``|q_i-\widetilde q_i|/\max(1,|q_i|,|\widetilde q_i|)``. For native RHSs, the
maximum change on retained coordinates is only ``8.08\times10^{-33}``.
The native RHS correction reaches ``1.14\times10^{-15}``; the manufactured
correction reaches 1.389 and cannot be discarded. The maximum manufactured
reference-direction error is ``7.20\times10^{-11}``, illustrating that backward
error and forward error are different quantities.

An independent 80-digit decimal audit checks all 30 recovered directions,
including RHS reduction, removed-coordinate recovery, full residual maxima,
all mixed-grid failure counts and the reported worst rows. Raw vectors,
provenance, hashes, protocol and planning records remain outside Git in
`FIXED_OBSERVATION_KKT_20261007`.

This is a narrow numerical result, not evidence of faster Ipopt solves or
improved conditioning. It holds the retained Newton system fixed; it does not
reproduce the substituted NLP's internal slacks, dual initialization, row
scaling, regularization decisions or trajectory. Automatic ordering can also
change when the matrix dimension changes. No new OPF solve or physical-result
export is produced. All production options and defaults remain unchanged, and
timing remains deferred. The remaining material mixed-criterion misses from
the broader, supplied-order study deserve attention before extending this tiny
structural reduction on accuracy grounds.
