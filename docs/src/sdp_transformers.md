# Fixed transformers and regulators

The dense IVRSDP represents transformer electrical equations before lifting.
All coefficients, including taps, are fixed. It neither linearizes complex power
nor turns delta winding power into a nominal terminal-power allocation.

## Winding representation

Let `Df` and `Dt` map terminal voltages into oriented coil voltages. Their rows
contain +1 and −1 at the two coil terminals; a missing return is ideal ground.
With every coil current directed into the transformer,

```math
u_f=D_f v_f,\quad u_t=D_t v_t,\qquad
j_f+R^Hj_t=0,\qquad
e_t=R e_f,
```

where

```math
e_f=u_f-Z_fj_f,\qquad e_t=u_t-Z_tj_t.
```

`R` maps from-side EMFs to to-side EMFs. The ampere-turn equation is its
conjugate-transpose counterpart, so the ideal core conserves complex power,
including for rectangular center-tap coupling. No impedance inversion is needed:
zero leakage arms and ideal units use the same equations.

External exciting admittances produce terminal currents

```math
i_f=D_f^T(j_f+Y_fu_f),\qquad i_t=D_t^T(j_t+Y_tu_t).
```

These currents enter full terminal KCL. For regulators, an additional galvanic
bond contributes equal-and-opposite current at its endpoints and enforces equal
endpoint voltage. The bond current is retained even when its voltage is zero.

Every equation is a row of the global homogeneous system `A*z = 0`. Substitution
`z=N*y`, followed by `H ≽ 0` in place of `y*yᴴ`, preserves all winding and current
cross-products. The formulation does not split coupled winding current Grams or
invert a singular delta incidence matrix.

## Supported connection contracts

The supported tables live under `transformer.<subtype>`. Map order is significant.
An explicit return must appear in the documented position; terminal names have
no special role in selecting winding polarity.

| Subtype | From / to map order | EMF coupling |
|---|---|---|
| `single_phase` | `[p,n]` / `[p,n]`, or one ground-referenced terminal per side | `R = 1/(N₀ τ)` |
| `center_tap` | `[p,n]` / `[x1,n,x2]`; ground-referenced maps `[p]` / `[x1,x2]` also accepted | `R = [1;1]/(N₀ τ)` with to coils `x1−n` and `n−x2` |
| `wye_delta` | `[a,b,c,n]` / `[a,b,c]`; wye return may be implicit | To coils `a−b,b−c,c−a`; `R = √3/(N₀ τ) I` |
| `delta_wye` | `[a,b,c]` / `[a,b,c,n]`; wye return may be implicit | From coils `a−c,b−a,c−b`; `R = 1/(√3 N₀ τ) I` |
| `single_phase_autotransformer` | `[p,q]` / `[p,q]`, or one ground-referenced terminal per side | `R = 1/n_eff`, plus through-bond at `q` |
| `open_delta_regulator` | Three ordered phase terminals, optionally followed by bonded neutral | Two regulating coils plus a through-bond on their shared phase |

Here `N₀ = v_nom_from/v_nom_to`. Yd/Dy nominal voltages are bus phase-to-neutral
reference magnitudes, so delta coil ratios contain √3. The opposite delta rolls
are intentional. Wye-to-delta operation does not impose a common-mode voltage
gauge: grounding or other connected devices must establish any physical reference.
A free common-mode voltage remains free in the relaxation.

Open-delta `connection` selects coil pairs `ABBC = (a−b,b−c)`,
`BCAC = (b−c,a−c)`, or `CABA = (c−a,b−a)`. The shared conductor is bonded from
input to output. `tap_ratio` has two entries, one per regulator. For either
regulator subtype, type A uses `n_eff = tap_ratio` and type B uses its reciprocal.
The default is type B and unity tap.

## Leakage, excitation, and taps

Leakage and exciting fields use SI Ω and S. For isolating transformers,
`r/x_series_from` are multiplied by `τ²` on the tapped winding; to-side values
remain unchanged. Delta-side input leakage uses the bus phase-to-neutral base
and is multiplied by three to obtain coil impedance. Thus single-phase
short-circuit impedance referred to the input is

```math
Z_{sc,f}=\tau^2 Z_{f,0}+(N_0\tau)^2 Z_{t,0}.
```

For a center tap, the primary arm is shared: `jf + (jt1+jt2)/(N₀τ) = 0`.
Each secondary has its own leakage arm, retaining load-imbalance coupling.
Regulator leakage uses the declared through-winding impedances without an extra
`tap_ratio²` input factor; its referral follows the fixed coupling equation.

Canonical BMOPF legacy `g_no_load + im*b_no_load` is split across the from-side
coils, including for center-tap units. This corrects the previous implementation
that followed an older BMOPFTools winding-2 convention. Use `no_load_shunt` for
an explicit physical location: `{winding, g, b}` specifies admittance per coil
at that winding, and is mutually exclusive with legacy excitation fields.
Center-tap indices are 1=primary, 2=first secondary, 3=second secondary. Regulator excitation is across each from-side regulating coil (the
open-delta value is per regulator). Negative winding resistance or core conductance
is rejected. Linear excitation is supported; core saturation is not.

Ordinary transformers accept `tap`, including the PowerIO boundary's normalized
`tap_ratio` spelling. Regulators use `tap_ratio`. An explicit value fixes the
setting, and is checked against supplied bounds. Without a value, equal lower
and upper bounds fix it; unequal bounds are rejected. Supplying one bound,
nonpositive/nonfinite ratios, or conflicting aliases is rejected. This is a
fixed operating point, not tap optimization or regulator control simulation.

## Limits and results

`i_max_from` and `i_max_to` follow the schema winding/conductor convention in map order,
including exciting and galvanic-bond currents, except that schema delta-side
limits rate the individual series **coil currents**, not their differences at
bus terminals. Each vector must cover the declared map, including any explicit
return. This corrects the earlier delta terminal-current interpretation. These
limits use affine squared-current moments.

`s_rating`, if supplied, must be positive. Its SOC limit applies to series-coil
power: the from coil for single-phase and center-tap units, each wye coil at
one-third nameplate for Yd/Dy, and from-side through-power per regulator. The
center-tap rating is the shared primary nameplate, not an independent rating for
each secondary. No-load current is included in terminal-current limits but not
these series-coil power limits. Omitted ratings do not create implicit limits.

`relaxed_powers` exposes keys `(:transformer_from, "subtype/id")` and
`(:transformer_to, "subtype/id")` in terminal order, including excitation.
`(:transformer_coil_from, "subtype/id")` and `(:transformer_coil_to, "subtype/id")`
contain oriented series-coil powers. All are W+jvar, positive into the device.
Subtype-qualified IDs avoid collisions between component tables.

## Evidence and remaining scope

The connection and PSD-consistency design follows the revised DeltaLoadsSDP
manuscript's incidence interface. That work excludes transformers from its
validated scope; it does not establish transformer SDP exactness. Its split-leg
PSD equivalence assumes current-Gram use only through diagonal entries, which
must not be assumed for coupled transformer constraints.

The input conventions were checked against BMOPFTools source at commit
`72e6cec22a66cf376c37ec4d64aef350b9f1100d`; it is not a package or test dependency.
Independent OpenDSS comparisons cover single-phase, center-tap, Yd and Dy
leakage at unity and 1.04 taps, including complex input power.
Analytical tests cover impedance-load solutions, center-tap shared-arm coupling,
Yd/Dy phase shifts, asymmetric loads, regulator bonds, tap validation, and rating
infeasibility. The optional Mosek runner executes the analytical SDP suite.

General `n_winding` and internal neutral grounding are now supported as described
below. Zigzag/custom banks, saturation, time-series evaluation, and optimized
taps remain outside the input/model scope. Controller profiles are not executed.
Explicit ideal grounding and separately declared fixed shunts remain available.
Multi-voltage-base equilibration and scalable sparse SDP representations remain
future work; this implementation uses the reference model's single voltage base.
An optimal solver status or voltage candidate is not an AC feasibility certificate.

## Build a fixed operating point

This example uses explicit grounded returns and a tap selected by the caller.
The builder works without installing a solver.

```@example fixed_transformer
using FormulationLab
network = Dict(
    "bus" => Dict(
        "hv" => Dict("terminal_names" => ["p", "n"],
                     "perfectly_grounded_terminals" => ["n"]),
        "lv" => Dict("terminal_names" => ["p", "n"],
                     "perfectly_grounded_terminals" => ["n"])),
    "voltage_source" => Dict("s" => Dict(
        "bus" => "hv", "terminal_map" => ["p", "n"],
        "v_magnitude" => [230.0, 0.0], "v_angle" => [0.0, 0.0])),
    "transformer" => Dict("single_phase" => Dict("t" => Dict(
        "bus_from" => "hv", "bus_to" => "lv",
        "terminal_map_from" => ["p", "n"], "terminal_map_to" => ["p", "n"],
        "v_nom_from" => 230.0, "v_nom_to" => 115.0, "tap" => 1.02,
        "r_series_from" => 0.1, "x_series_from" => 0.05,
        "s_rating" => 5000.0))),
    "load" => Dict("l" => Dict(
        "bus" => "lv", "terminal_map" => ["p", "n"],
        "configuration" => "SINGLE_PHASE", "model" => "constant_power",
        "p_nom" => [1000.0], "q_nom" => [200.0])))
build = build_opf(network, IVRSDP(objective=:source_import); optimizer=nothing)
println("Built a fixed-tap transformer SDP without attaching a solver.")
```

With Clarabel loaded, call `solve_opf(network, IVRSDP(objective=:source_import))`
to solve the same model. Interpret its lifted powers and voltage candidate
according to the [SDP result contract](sdp.md).

## General multiwinding transformers

`transformer.n_winding` accepts any number of ports ≥2, each with `bus`,
`terminal_map`, coil-voltage `v_nom`, `configuration` (WYE, DELTA, or a
single-phase dictionary extension), and optional `r_winding`, fixed
`tap_ratio`, neutral impedance and current limits. Delta `v_nom` is a **coil
line-to-line voltage**, unlike the two-bus Yd/Dy bus-voltage convention;
`delta_roll=±1` sets coil orientation. All ports must have the same coil count.

Let `n_k=v_nom[k]/v_nom[1]` and `T_k=n_k*tap_ratio[k]`. Per-coil referred currents
are `J_k=T_k*j_k`. Resistances are referred with nominal `n_k²`; pairwise `x_sc`
already uses winding 1's nominal coil-voltage base. Every key `i_j`, `i<j`, must
be supplied exactly once. Construct

```math
Z_{ij}=r_i/n_i^2+r_j/n_j^2+jx_{ij},
Z_B[a,a]=Z_{1,a+1},\qquad
Z_B[a,b]=(Z_{1,a+1}+Z_{1,b+1}-Z_{a+1,b+1})/2.
```

The exact linear equations (currents into the transformer) are

```math
\sum_k J_k=0,\qquad
u_1/T_1-u_i/T_i+\sum_{k=2}^n Z_B[i-1,k-1]J_k=0,\quad i\ge2.
```

The full matrix is retained, including non-star four-or-more-winding couplings.
No matrix inversion or independent star fit is used. Negative resistances and
materially indefinite leakage-reactance matrices are rejected. Singular/zero
leakage is permitted. The transformer and winding `s_rating` values are power-base
metadata; explicit per-winding `i_max` (and dictionary extension `s_max`) impose
per-coil operating limits. Scalar limits are broadcast across that winding's coils.

Legacy multiwinding excitation is on winding 1, following the inspected schema.
`no_load_shunt` chooses another physical winding explicitly. Independent OpenDSS
comparisons use both all-wye and mixed wye/delta three-winding circuits and fixed
non-unity taps. A separate four-winding analytical case exercises non-star leakage.

Results expose `(:transformer_winding,"n_winding/id/k")` for terminal powers and
`(:transformer_coil,"n_winding/id/k")` for series-coil powers. Internal grounding
branches are included in terminal powers; excitation location and fixed taps are
not silently reinterpreted as control variables.
