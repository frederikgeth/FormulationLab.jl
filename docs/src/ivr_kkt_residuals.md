# KKT residual magnitudes and model provenance

## Question and scope

The [fresh-factorization study](ivr_kkt_factorization.md) retained strict
componentwise backward-error failures even when normwise errors were small.
This retrospective analysis distinguishes error magnitude from a small
denominator and joins the worst rows to model expressions. It evaluates all
**464 retained final solution vectors**: 58 KKT calls, two preprocessing regimes,
two row conventions and two right-hand sides, after the original two refinement
steps. No optimization or factorization is rerun.

The analysis is informed by earlier summaries. Its reporting grid was fixed
before this new rowwise evaluation; it is not independent confirmation or a
retrospective replacement of the original acceptance gate. Correction right-hand
sides from the same state are included and are not independent physical cases.

## Residual definitions and row units

For the actual stored Float64 matrix, right-hand side and computed direction,
256-bit accumulation evaluates

```math
r=b-Kq,\qquad d=|K||q|+|b|,\qquad
\eta=\max_i\frac{|r_i|}{d_i}.
```

A zero numerator and denominator contributes zero. The original strict gate
remains ``\eta\le10^{-10}``. Normwise backward error is also retained:

```math
\eta_\infty=
\frac{\lVert r\rVert_\infty}
{\lVert K\rVert_\infty\lVert q\rVert_\infty+\lVert b\rVert_\infty}.
```

The additional reporting criterion is

```math
|r_i|\le a w_i+10^{-10}d_i,\qquad
\rho_a=\max_i\frac{|r_i|}{a w_i+10^{-10}d_i},
```

for ``a\in\{0,10^{-16},10^{-14},10^{-12},10^{-10}\}``. The middle example
``a=10^{-12}`` is an illustrative reporting threshold, not a new solver tolerance.
The allowance has **reference KKT row units**, not SI feasibility units. In
particular, stationarity and constraint rows do not have the same physical
interpretation; passing this criterion does not establish physical feasibility,
forward accuracy or an acceptable nonlinear direction.

The [exact row-unit transformation](ivr_kkt_row_units.md) gives
``\widehat K=TKT``, ``\widehat b=Tb`` and ``\widehat q=T^{-1}q``. In exact
arithmetic, positive diagonal ``T`` implies ``\widehat r=Tr`` and
``\widehat d=Td``. Accordingly ``w_i=1`` in original coordinates and
``\widehat w_i=T_{ii}`` in transformed coordinates. A common untransformed
absolute allowance would inadvertently change the criterion when row units
change. Actual transformed matrices and vectors include the original Float64
rounding, which remains part of the experiment.

Manufactured right-hand sides are regenerated with the same ``q_i^*=\sin(i)``
Float64 values, accumulation order, 256-bit arithmetic and final Float64 rounding
as the factorization study. All 464 final residual maxima and strict errors must
reproduce the earlier reports. An independent 80-digit decimal implementation
checks the original 52 first-call native vectors, including all mixed-grid
maxima, failing-row counts and every reported worst-row value. Thirteen
zero-floor comparisons have tied maxima at reporting precision: binary and
decimal arithmetic can select different row indices. Those differences are
retained; the audit verifies each selected row directly and requires identical
reported maxima for a differing argmax.

## Results

All 464 earlier final strict errors and residual maxima are reproduced. The
independent decimal checks pass for all 52 declared native vectors. The absolute
grid yields:

| Absolute allowance in reference row units | Vectors satisfying the mixed criterion | Vectors failing |
|---:|---:|---:|
| 0: original strict criterion | 364/464 | 100 |
| ``10^{-16}`` | 444/464 | 20 |
| ``10^{-14}`` | 450/464 | 14 |
| ``10^{-12}`` | 457/464 | 7 |
| ``10^{-10}`` | 464/464 | 0 |

Thus 93 of the 100 strict failures satisfy the additional ``10^{-12}`` allowance.
This quantifies sensitivity to small absolute residuals without relabelling the
strict failures as passes. The complete sensitivity grid prevents the most
permissive threshold from being presented as a uniquely justified acceptance
criterion.

At ``a=10^{-12}``, the group counts are:

| Preprocessing | RHS | Original units | Unit-row coordinates |
|:---|:---|---:|---:|
| Automatic | Native | 57/58 | 57/58 |
| Automatic | Manufactured | 58/58 | 58/58 |
| Given order, no solver scaling | Native | 57/58 | 56/58 |
| Given order, no solver scaling | Manufactured | 58/58 | 56/58 |

Seven failures remain explicit. The automatic native pair at powers-only
iteration 0 misses the criterion by a factor of 1.007 on
`line/32_127757/drop/2`, real component; its residual is
``1.039\times10^{-12}``. The given-order/unscaled broad native pair at iteration
22 fails on stationarity rows, with mixed ratios 8.53 and 7.84. Its two
transformed manufactured-RHS calls fail on the same stationarity variable
`state_real[2050]`, with residual ``2.850\times10^{-10}`` and ratio 1.247.
The final failure is eliminated-current broad iteration 0 in the transformed,
given-order/unscaled regime: `line/32_LVBranch709377/drop/3`, real component,
with residual ``9.883\times10^{-12}`` and ratio 3.26. These seven vectors include
identity duplicates and repeated calls, not seven independent cases.

The largest normwise backward error across all 464 vectors is
``7.62\times10^{-14}``; for native RHSs it is ``3.68\times10^{-15}``.
Small normwise errors do not negate the row-level failures or certify forward
accuracy. Removing NLP row scales supplies no consistent accuracy advantage
in this panel. Automatic preprocessing remains the baseline.

## Provenance and interpretation

Models are rebuilt without optimization. Original TNLP row and variable layouts
are checked against the retained native captures, including scalar set, function
type, variable name and local index. The emitted-constraint inventory joins
recorded declarations to every solver row. Full expressions, variable support,
lifting source keys and incident constraints are retained outside Git.

The augmented KKT blocks have different meanings:

| Block | Provenance interpretation |
|:---|:---|
| Primal ``x`` | Stationarity associated with an original free variable; generally involves several model constraints |
| Slack ``s`` | Slack stationarity associated with an inequality row |
| Equality | Linearized original equality, including retained regularization |
| Inequality | Linearized inequality/slack relation, including retained regularization |

An ``x`` row must not be labelled as a single physical equation. Associated
constraint labels provide context, not a proof that any one constraint caused
an inaccurate direction. Input-schema completeness remains unclaimed.

For example, the previously reported relative error of one at explicit broad
iteration 22 maps to `lifting/4278/observation`, real component. Its scalar
expression is

```math
-x_{1296}+x_{1297}+u_{4278}=0.
```

The two source coordinates are fixed at 1 and approximately -0.5. The lifted
observation supplies the source bus `32_V.BEL` line-to-line lower and upper
voltage limits, channel 1. Its row residual and denominator are both about
``5.086\times10^{-36}``. This is a concrete small-denominator example, not evidence
that the source-voltage limit is violated by a material amount.

A different strict failure, original powers-only iteration 0 under the
supplied-order/unscaled regime, belongs to stationarity for
`lift_power_420_real`. Its incident declarations include the power definition and
`generator/threephase_32_LVBus271857_consumption/s_max/2`. Its residual is about
``1.54\times10^{-29}`` and denominator ``1.31\times10^{-27}``. This illustrates why
stationarity provenance must retain multiple associated declarations.

## A specific exact-transformation candidate

Each broad model contains **six scalar lifted observations** whose definition
inputs are all fixed source coordinates: real and imaginary parts of the three
source-bus line-to-line voltages. Powers-only has no such lifted candidates.
The associated lower and upper voltage bounds are retained in the provenance
catalogue. This is a structural candidate count, not an implemented reduction.

An opt-in constant-propagation rule could replace these auxiliaries by their
exact defining values and remove six variables and six defining equations per
broad model. It must evaluate the resulting constant bounds and refuse an
inconsistent bound, preserve bound provenance and recover the same physical
outputs. Fixed values and dependencies must be part of the rebuild/update
contract. The unreduced observation option should remain available.

This candidate is small relative to the complete model. It may remove trivial
KKT rows such as the source-observation example, but neither a conditioning gain
nor an Ipopt wall-time benefit has been demonstrated. The next implementation
should first establish exactness and constant-bound behavior on small cases,
then use the retained physical/export controls on the external panel. Timing
remains deferred.

## Reproduction and limitations

```sh
julia --project=docs --startup-file=no test/ivr_kkt_residuals.jl
```

`examples/ivr_kkt_residuals.jl` accepts a canonical KKT export, a retained solution
and its original-coordinate RHS. Set `transformed=true` for a solution of the
transformed matrix; the helper reconstructs the factorization study's rounded
matrix and RHS internally. Supply the four block dimensions. It reports the
complete tolerance grid, block failure counts and the five worst rows under
strict, absolute and each mixed criterion.

The 16 calibration assertions include a tiny-row strict failure, a material
residual that must remain a mixed failure, exact diagonal row transformations,
symmetric off-diagonal accumulation, zero equations and malformed inputs.
Source matrices, solution files, hashes, all row reports, provenance catalogues,
independent checks, protocol and planning documents are retained outside Git in
`KKT_RESIDUALS_20261007`. No production tolerance, export schema, formulation
option or timing recommendation changes.
