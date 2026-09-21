# Static AC component models

IVRSDP supports the electrical AC component families in the inspected BMOPF 0.2
proposal: buses, lines/linecodes, sources, shunts, capacitors, switches, loads,
generators, IBRs, and all seven transformer subtypes. This is static electrical
model coverage, not unrestricted schema conformance or a general AC exactness
claim. Line geometry compilation, DC networks, time-series evaluation, and control
laws are outside this formulation. Unknown electrical fields are rejected.

Symbols and current/power signs follow the shared [notation and
conventions](notation.md). ``D_d`` always maps bus-terminal voltages into a
device's ordered coil voltages.

## Switches and capacitors

`open_switch` is a required fixed Boolean. A closed switch imposes `vf=vt`, with
one through-current entering its two buses with opposite signs. An open switch
has zero current and imposes no voltage equality. `i_max` applies in conductor
order; the dictionary extension `s_max` applies at both endpoints. Switch powers
are returned under `:switch_from` and `:switch_to`.

A capacitor is a connection-aware susceptance. With coil incidence `D`,

```math
U_d=D_dU_i,\qquad J_d=\mathrm j\,\operatorname{Diag}(q^{rated}/(v^{nom})^2)U_d,
\qquad I_d^{term}=D_d^T J_d.
```

Wye, delta, and single terminal-pair connections retain their return paths.
`q_rated` is a nonnegative per-coil array; `v_nom` may be scalar or per-coil.
The result `:capacitor` contains consumed coil powers, so an energized capacitor
has negative reactive consumption. It is not a constant-Q generator.

## Grounding

Bus `perfectly_grounded_terminals` remove zero-voltage coordinates; unrestricted
ideal earth currents supply their KCL residual. Impedance grounding can be
represented by an ordinary shunt.

Transformer `r_neutral_from/to`, `x_neutral_from/to` and multiwinding
`r_neutral`, `x_neutral` also stamp explicit internal earth branches:

```math
z_n\ne0:\quad i_n=v_n/z_n;\qquad
z_n=0:\quad v_n=0,\quad i_n\ \text{free}.
```

**Absent fields add no branch; explicitly zero fields mean solid grounding.**
The winding must identify an actual neutral. Its role comes from
`terminal_conventions.neutral`, then `bus.neutral_terminal`, then the conventional
name `n`. A delta winding cannot acquire a neutral merely by supplying grounding
fields. Ground-branch currents enter physical terminal KCL and transformer
terminal-current results.

## Bus voltage limits

All magnitude limits are affine functions of voltage moments. For a complex row
`c` selecting a voltage difference or sequence,

```math
\underline U^2\le \widehat{|cU|^2}\le\overline U^2.
```

Supported fields are `v_min/max`, `vn_max`, `vpn_min/max`, `vpp_min/max`,
`vpos_min/max`, `vneg_max`, and `vzero_max`. Per-phase arrays follow bus terminal
order with the declared neutral removed; full-terminal `v_min/max` arrays remain
accepted for compatibility. Phase-pair bounds use unordered pairs in that phase
order: for `[a,b,c]`, `[ab,ac,bc]`. Bounds are checked at source and grounded
terminals too; an incompatible engineering bound does not disappear.

Sequences use phase-to-neutral voltages when an explicit neutral exists and
phase-to-ground otherwise. Positive, negative and zero sequences use coefficients
`[1,a,a²]/3`, `[1,a²,a]/3`, `[1,1,1]/3`, where `a=exp(j2π/3)`. Their phase order is
`terminal_conventions.phase` when applicable, otherwise canonical `[a,b,c]` when
those labels exist, otherwise the bus's ordered three phases. Sequence bounds
require three phases. Neutral-only bounds require an explicit neutral.

## Sources and generators

Multiple fixed voltage sources are supported, including separate islands. All
source phasors are related linearly to one nonzero reference phasor, whose squared
magnitude is fixed. Thus supplied relative angles are retained across sources.
At least one nonzero reference is required. Source-current allocation between
multiple ideal grounding paths is not inferred: the research extension that
requests current ratings on an explicitly grounded source terminal remains
rejected. This field is not part of the inspected schema's source model.

Generators retain connection-aware coil powers and P/Q boxes. Their bounds are
optional. `s_max` limits each coil; `i_max` can cover the coils or the full terminal
map, including a wye neutral. Full terminal maps rate current sums/differences
through the shared moment matrix. `energy_cost_rate` is an alias for `cost` in
\$/kWh; conflicting aliases are rejected. No implicit dispatch limits are added.

## Inverters without control laws

`FOUR_LEG`, `THREE_LEG`, and `SINGLE_PHASE` use wye, delta, and terminal-pair
connections respectively. P/Q boxes, `s_max`, and coil/full-terminal `i_max`
provide static capability constraints. Equal P/Q bounds specify fixed dispatch;
otherwise dispatch is optimized within those bounds. Equal bounds compile as a
single equality to avoid opposing conic inequalities without a strict interior. Scalar `p_avail` caps total
active power delivered at the point of common coupling (PCC).

With filter impedance `Z=diag(r_filter+j*x_filter)` and per-coil PCC shunt
susceptance `b_filter_shunt`, define delivered PCC current `i` and voltage `u`:

```math
J_f=I+\mathrm jB U_d,\qquad E=U_d+ZJ_f.
```

The ordinary `:ibr` powers are `u*conj(i)` at PCC; `:ibr_internal` reports
`e*conj(j_f)`. These expressions retain filter copper loss and shunt power.
A shared DC-link operating budget (`dc_link_coupled=true`, `p_dc_min/max`) bounds
the sum of internal active powers; it does not create a DC network. With
`grid_forming=true`, `v_ref_internal` fixes each internal voltage magnitude.
This is a fixed algebraic setpoint, not a droop or dynamic grid-forming model.

`control_profile` and `voltage_aggregation` do not generate constraints. No
Volt-VAr, Volt-Watt, power-factor profile, or other profile law is evaluated.
Referenced profiles are listed in `build.omitted_controls`, the result, and
`solve_diagnostics(result)`. The global `control_profile` table is retained as
metadata. Availability and capability limits remain active independently of it.

## Voltage-dependent loads: additional relaxation

Constant-power loads fix their coil powers. Constant-impedance loads retain the
linear law ``J=\operatorname{Diag}(\overline{s^{nom}}/(v^{nom})^2)U_d``,
including at zero voltage. Equivalent all-Z
ZIP and exponent-2 declarations use that same law.

For constant-current, mixed ZIP and exponential loads, use normalized squared
coil voltage ``x=|U_d|^2/(v^{nom})^2`` and auxiliary factors ``t_a\approx x^a``. Constant-current uses
`a=1/2`; exponential P/Q use `gamma_p/2` and `gamma_q/2`. ZIP powers are affine
combinations of `x`, `t_(1/2)`, and 1 with independent active/reactive fractions.
Fractions must be nonnegative and sum to one.

The graph is relaxed with power cones:

```math
0<a<1:\quad 0\le t_a\le x^a;\qquad
 a>1\ \text{or}\ a<0:\quad t_a\ge x^a.
```

When physical voltage limits provide a finite interval `[l,h]`, the secant supplies
the opposite inequality. Bounds are obtained from an identical phase-ground,
phase-neutral or phase-pair row (either orientation). No arbitrary voltage box is
introduced for conditioning. Without a finite upper bound, only the global
one-sided envelope is imposed; this is valid but can be substantially weaker.
Negative exponents exclude zero voltage through their power-cone domain.

This adds a relaxation **beyond dropping moment rank**. Even rank-one voltage
moments do not establish that a recovered point satisfies the original load law.
Affected load IDs appear in `load_envelopes` on builds/results and in diagnostics.
Clarabel supports these cones. Optional Mosek is tested too.

## Input and scope boundary

The audit uses PowerIO's `bmopf-0.2.0.schema.json`, SHA-256
`74d6c6de3637d52e42a26c4cb0584f51df70d69f360b236cf5e23afaf7669462`.
This remains a proposal; the adapter retains PowerIO diagnostics and does not
claim raw dictionaries are schema validated. See the [field inventory](schema_fields.md).

`wire_data` and `line_geometry` are retained descriptive inputs when electrical
line/linecode coefficients are already supplied. This model does not infer
impedances from geometry or material data. Time-series references must be resolved
into a static snapshot upstream; DC tables are excluded from this AC pass.
Core saturation and custom zigzag connections have no supported representation
in the inspected schema. No new ad hoc component subtype is introduced for them.
