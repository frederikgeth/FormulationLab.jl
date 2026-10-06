# Separate current limits at shunt-loaded line ends

The [local reactive-transfer study](ivr_line_boundaries.md) established active
inherited current bounds on a real line with zero shunts. Its endpoint current
magnitudes were equal. This extension tests unequal terminal currents explicitly,
using manufactured active-bound witnesses and a separate reconstruction audit
of inherited shunts in the archived real-feeder results.

## Physical equations and the potential error

Let ``v_f,v_t`` be conductor voltages in the line's ordered endpoint maps,
``j`` the series current directed from ``f`` to ``t``, and ``i_f,i_t`` the
terminal currents entering the branch. A coupled π model satisfies

```math
v_f-v_t=Zj,\qquad i_f=j+Y_fv_f,\qquad i_t=-j+Y_tv_t.
```

Consequently ``i_f+i_t=Y_fv_f+Y_tv_t``, rather than zero. A conductor rating
``\bar i_k`` imposes both ``|i_{f,k}|\leq\bar i_k`` and
``|i_{t,k}|\leq\bar i_k``. Applying that rating only to ``j`` can admit a
terminal-current violation. Copying one endpoint magnitude to the other can
misidentify which bound is active.

The independent audit also checks complex losses:

```math
\sum_k v_{f,k}\overline{i_{f,k}}+v_{t,k}\overline{i_{t,k}}
=\sum_k (Zj)_k\overline{j_k}
 +\sum_k v_{f,k}\overline{(Y_fv_f)_k}
 +\sum_k v_{t,k}\overline{(Y_tv_t)_k}.
```

All these identities use recovered SI values. Ratings follow conductor
positions; receiving-end terminal names need not match sending-end names.

## Manufactured protocol

`shunt_fixture` in `examples/benchmark_ivr_line_transfer.jl` declares a two-bus,
zero-demand network with 230 V source phase magnitude and a 200 A line rating.
The linecode has a 250 A rating; the line-level 200 A value must take precedence.
For length ``\ell=0.5``, the per-length series matrix has diagonal
``0.004+\mathrm{j}0.002`` and off-diagonal ``0.001+\mathrm{j}0.0003``.
The physical shunts are

```math
Y_f=\ell(0.001+\mathrm{j}0.02)C,\qquad
Y_t=\ell(0.002+\mathrm{j}0.08)C,
```

where ``C=\begin{bmatrix}1&-1\\-1&1\end{bmatrix}`` for two conductors and
``C=I-\mathbf{1}\mathbf{1}^{\mathsf T}/3`` for three. Conductance matrices
are positive semidefinite. This is a deliberately manufactured research input,
not altered shunt data from an external feeder.

Declare two equivalent representations: linecode matrices with length 0.5,
and inline physical matrices with the multiplier already applied. Inline data
has no linecode or length field. For the three-wire case, use receiving map
`["b","c","a"]` against sending map `["a","b","c"]`. Preserve these inputs
when adding the same two ideal reactive devices and ±600 kvar total soft
targets as in the preceding study; per-device capability is 1.2 Mvar. Two
conductors give single-phase devices and three give delta devices.

Cross two conductor counts, two representations, two target directions, both
Ipopt scaling policies and all six retained formulation arms: **96 cells**.
Use per-unit coordinates, unchanged strict solver tolerances, complete common
physical starts, own/full/reverse membership, physical residuals, objective
agreement and SI JSON round trips. No timing is ranked. The protocol declares
the expected active end before solves: receiving for positive targets, sending
for negative targets.

## Endpoint activity and rejection witnesses

All **96/96 admissions pass**. `current_activity` reports each finite bound in
SI with its endpoint, positional channel, actual terminal name, rating origin,
signed slack and geometric activity. Negative slack is a violation and is
never labelled active. The activity threshold is ``10^{-5}`` A; no multiplier
or sensitivity claim is made.

| Conductors | Target (kvar per device) | Sending current (A) | Receiving current (A) | Series current (A) | Active end |
|:--|--:|--:|--:|--:|:--|
| 2 | +600 | 188.514 | 200.000 | 190.813 | receiving |
| 2 | −600 | 200.000 | 188.486 | 197.700 | sending |
| 3 | +600 | 188.507 | 200.000 | 190.807 | receiving |
| 3 | −600 | 200.000 | 188.493 | 197.700 | sending |

Each row summarizes both representations, both policies and all six arms;
conductor magnitudes agree to the displayed precision. Every conductor at the
declared active end is active, while every conductor at the opposite end is
strictly below its rating. The endpoints differ by more than 11.48 A.

For each accepted point, create a separate input copy with the rating halfway
between the two endpoint maxima. Every conductor at the formerly active end
then violates the cap; every conductor at the opposite end remains below it.
Both physical and model auditors reject all **96 witnesses**. For positive
targets, the series current also remains below this tightened cap. Thus these
witnesses specifically exclude substituting a series-current bound for the
terminal-current bound. No admitted input is changed by this rejection test.

## Independent SI exports and external transfer

A separate Python audit decodes the original matrices, applies length exactly
once, and reconstructs series and shunt currents from exported endpoint
voltages and currents. It verifies voltage drop, current balance, complex
losses, native-power objective, rating precedence, manifest replay and equal
physical/native-device output structures. It checks 480 manufactured port
margins and all 96 exports.

The same audit reads the 24 archived real-feeder exports from
`LINE_BOUNDARY_20261006`, verifies their saved hashes, and checks all 1,632 line
records and 9,792 port margins. The six original DSuite feeders inspected have
nonzero shunts only on `sourcez`; the archived solved feeder is still the one
previously selected rural input. Its maximum endpoint shunt-current magnitude
is approximately 4.11–4.12 mA, with endpoint magnitude differences approximately
7.98 mA. These inherited source-branch ratings remain inactive. This is
reconstruction evidence, not a new active-shunt feeder experiment or six new
solved feeders.

Across both audits, voltage-drop residual is at most ``5.63\times10^{-12}`` V,
series-current balance residual at most ``3.02\times10^{-14}`` A, and the
complex-loss identity error at most ``1.01\times10^{-10}`` VA. Exported series
currents match the independently calculated values; shunt-current discrepancies
are below ``1.78\times10^{-15}`` A. Objective error is below
``5.83\times10^{-11}``. These numerical checks do not establish global optima.

The [tutorial](tutorial_exact_ivr.md#59.-Distinguish-series-and-terminal-current-limits)
shows the single-phase witness. Tests additionally cover invalid observations,
rating precedence, receiving-terminal names and unchanged original records.
Raw protocols, manufactured inputs, 96 exports, source screening, independent
audits and validation logs remain outside Git in `SHUNT_BOUNDARY_20261006`.
Package equations, options and fastest-profile recommendations are unchanged.
The next coverage gaps are simultaneous current/voltage activity and active
inherited shunt-loaded limits on independently selected valid feeders.
