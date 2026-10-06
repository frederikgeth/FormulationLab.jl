# Separating voltage-dependent load powers

The three-phase transfer panel originally admitted 74 of 96 candidates under
strict Ipopt settings. Every rejection involved voltage-dependent demand. An
exact auxiliary-power representation now admits **all 96**, including the 22
previously rejected candidates, without changing physical bounds, initial
physical states or solver tolerances. This is evidence of improved numerical
robustness on this panel; it is not a speed comparison or a universal guarantee.
The original representation remains the default and is retained for comparison.

## Exact formulation

Let ``s_k=u_k\overline{i_k}/S_b`` be a load coil's complex power in assembly units,
``x_k=|u_k|^2/V_{n,k}^2``, and ``f_P,f_Q`` its declared voltage-law factors.
The original power equations are

```math
\Re(s_k)=\frac{P_{n,k}}{S_b}f_P(x_k),\qquad
\Im(s_k)=\frac{Q_{n,k}}{S_b}f_Q(x_k).
```

With `load_power_lifting=true`, introduce a complex variable ``w_k`` measured in
lift units ``S_\ell`` and set ``\rho=S_\ell/S_b``. Replace these equations by

```math
\rho w_k=s_k,\qquad
\rho\Re(w_k)=\frac{P_{n,k}}{S_b}f_P(x_k),\qquad
\rho\Im(w_k)=\frac{Q_{n,k}}{S_b}f_Q(x_k).
```

The first equality denotes two real quadratic equations. The remaining rows
contain affine power variables and nonlinear voltage factors. Eliminating
``w_k`` recovers the original equations exactly; every original feasible point
has the unique extension ``w_k=s_k/\rho``. This also holds for signed or zero
nominal P/Q. No operating inequality, domain certificate or demand coefficient
changes. The positive engineering voltage domain remains mandatory.

Each applicable coil adds two real variables and two defining equalities. The
option is independent of `lifting=:off/:powers/:bounded_observations` and uses
`lifted_power_base`, falling back to `s_base`. It preserves the existing assembly
units of the equation rows. Constant-power and impedance loads are unchanged.
Fixed-magnitude voltage laws may use the power extension but retain their existing
constant evaluation of the voltage factor. The common auxiliary registry derives
all starts and recovered values from physical voltages/currents; the additional
variables cannot repair an inconsistent supplied physical point.

Use `IVRNLP(load_power_lifting=true)` or pass `load_power_lifting=true` to
`IVRThreePhaseTransferStudy.profiles`. Diagnostics report the selected policy
and complex auxiliary count as `:load_power_lifting` and `:load_power_lift_count`.
Physical SI result fields and the BMOPFTools-compatible export layout are
unchanged. See [tutorial section 50](tutorial_exact_ivr.md).

## Diagnostic evidence

Three representative failed cases were rerun with complete Ipopt logs: low-filter
cost with generator reuse and no automatic scaling; high-filter cost with signed
observations and gradient scaling; and low-filter tracking with signed observations
and no automatic scaling. Their original statuses reproduce. All recovered
endpoints satisfy the independent physical audit, including the endpoint labelled
locally infeasible by Ipopt. Logs show restoration/step-computation failures and
loss of optimality convergence near physical feasibility. These endpoints remain
rejected by the strict admission rule.

Starting from a separately solved full-model point recovers strict convergence
only for the first representative. Increasing MUMPS pivot tolerance to `1e-4`
also succeeds only for that case; an adaptive barrier strategy succeeds only for
the tracking representative. Limited-memory Hessians yield two iteration limits
and one acceptable-level status. None of these single solver interventions
consistently resolves all three cases. Every outcome is retained.

NLPDiagnostics evaluates Jacobians at shared unloaded and full-solution points
for full power lifting, reduced power lifting and signed observations. Evaluation
reports no failures; the 228 nonlinear rows use constructed exact AD and the
remaining rows use symbolic derivatives. Global row-norm ratios include nearly
zero inactive gradients and therefore do not establish a KKT condition number
or a causal scaling diagnosis. They are retained as diagnostics, not speed ranks.

Complete Ipopt first/second derivative checks pass on **36 manufactured cases**:
single-phase, delta and wye connections; current, ZIP and exponential laws;
full/reduced coordinates; and both power representations. The forward-difference
checker uses perturbation `1e-8`, comparison tolerance `1e-3` and no random point
perturbation. This checker tolerance is separate from solver admission. A full-
feeder second-derivative attempt was stopped after more than six minutes; its
partial log includes first-order discrepancy flags near small derivatives and
cannot be presented as a passed full-feeder derivative audit. The smaller checks
do not prove derivative correctness at every external iterate.

## Transfer validation

The inputs, exact additions, six candidate profiles, two power objectives, two
Ipopt scaling policies, common physical starts and inherited nameplate policy
are those of the [original three-phase study](ivr_threephase_transfer.md).
The new option alone is enabled. Assembly/dispatch units remain 10 kVA and lift
units 1 kVA; STRICT `1e-10`, MUMPS AMD and the original iteration limit remain.
The voltage-dependent scenarios each add 228 real power variables, one complex
auxiliary for each of 114 added load coils. Constant-power scenarios add none.

| Parallel demand | Original representation | Load-power auxiliaries |
|---|---:|---:|
| Constant power | 48/48 | 48/48 |
| Voltage dependent | 26/48 | 48/48 |
| Total | 74/96 | 96/96 |

All 96 endpoints pass physical, own/full/reverse membership and SI export round
trips. All **384 tightened-bound witnesses** reject unchanged endpoints under
stricter original voltage, line-current, nameplate or added IBR DC limits. All
48 tracking endpoints retain the inherited active transformer phase cap. No
failed original trial is relabelled or removed. Additional export-based checks
compare physical points between the old and new representations.

The full regression suite passes **97,094 assertions**, including **3916 new
checks**. Manufactured states cover positive, negative and zero demand, two bases,
all three existing lifting modes, full/reduced coordinates, auxiliary corruption,
physical recovery, JSON round trips and bound rejection. Constant-power models
retain their original variable and constraint counts.

## Interpretation and next experiment

Separating electrical power products from fractional voltage laws changes the
numerical representation enough to resolve all observed failures on this panel.
The current evidence does not isolate whether nonlinear expression evaluation,
KKT sparsity, ordering, or conditioning is the decisive mechanism. The option
adds variables, so improved admission does not imply faster solves.

Next, freeze a paired comparison of the retained original and auxiliary-power
representations. Keep rejected original runs visible and rank only strictly
admitted Ipopt wall times. Exclude build/compilation and diagnostics, and isolate
timed runs from tests and other solver work. Broader feeder transfer and more
precise derivative/KKT diagnostics remain useful before changing any default.
All logs, rejected trials, inputs, exports, source snapshots and planning documents
remain outside Git in `VD_DIAGNOSIS_20261006`.

## Follow-up: isolated paired timing

The [paired timing study](ivr_load_power_timing.md) completes two fresh-process
batches with all alternatives retained. All 1152 lifted measured trials pass;
576/1152 original trials pass. Speed effects depend on objective and profile,
including some slowdowns. The complete tables and conditional shortlist supersede
the untimed performance limitation of this initial diagnosis without changing
its original evidence.
