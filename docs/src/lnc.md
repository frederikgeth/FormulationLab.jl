# Lifted nonlinear cuts

LNCs are optional linear inequalities intersected with `IVRSDP` or `IVRSOC`.
They add no variables or cone types. The generic `add_lnc!` primitive accepts
affine products supplied by either formulation. No PowerModels dependency is introduced.

The equations follow Coffrin, Hijazi and Van Hentenryck,
[Strengthening the SDP Relaxation of AC Power Flows](https://arxiv.org/abs/1512.04644),
and the [PowerModels implementation](https://github.com/lanl-ansi/PowerModels.jl/blob/master/src/core/relaxation_scheme.jl).
The generalization here applies those scalar complex-product inequalities to
physical linear voltage maps, including unbalanced terminal differences.

## Phasor maps and equations

For any two maps `u=az`, `v=bz`, the existing global electrical lift gives

```math
w_u=(aN)H(aN)^H,\quad w_v=(bN)H(bN)^H,\quad c_{uv}=(aN)H(bN)^H.
```

`VoltagePhasor` specifies a complex linear combination of terminal voltages.
Phase-to-neutral, delta coil and sequence voltages use the same interface.
`phasor_products(build,u,v)` returns SI voltage-squared expressions `wu`, `wv`,
and `cross`; it does not create independent copies of the products.

Let magnitude bounds be `[lu,hu]`, `[lv,hv]`, with positive lower bounds and finite
upper bounds. Let the unwrapped relative-angle interval be `[phi-delta,phi+delta]`,
with `0 ≤ delta < π/2`. Set `su=lu+hu`, `sv=lv+hv`, `k=cos(delta)` and
`C=Re(exp(-j*phi)*c_uv)`. The two inequalities are

```math
s_us_v C-h_vk s_vw_u-h_uk s_uw_v
\ge h_uh_vk(l_ul_v-h_uh_v),
```

```math
s_us_v C-l_vk s_vw_u-l_uk s_uw_v
\ge l_ul_vk(h_uh_v-l_ul_v).
```

They are valid for every rank-one point in that domain, including correlated or
overlapping voltage maps. Neither balance nor independence is assumed. A phase
sector centered at 120 degrees or crossing the principal-angle branch cut is
handled by rotation. Give an ordered *unwrapped* interval, e.g. `[170°,190°]`,
not `[170°,-170°]`. Reversing a coil requires reversing its map and shifting its
relative-angle sector by π.

The implementation scales `wu` by `hu²`, `wv` by `hv²`, and `cross` by `hu*hv`
before forming coefficients. By default the generic primitive also imposes the
squared-magnitude bounds and the rotated angle wedge. The wedge uses sine/cosine
coefficients, without tangent singularities; zero width uses an equality.
`include_domain=false` adds only the two LNCs and requires the caller to enforce
the domain separately.

## Explicit domains

```@example lnc_map
using FormulationLab
u = VoltagePhasor("from", "a"; return_terminal="n")
v = VoltagePhasor("to", "a"; return_terminal="n")
bounds = LNCBounds((210.0, 250.0), (210.0, 250.0), (-0.1, 0.1))
cut = VoltageLNC("line-a", u, v, bounds;
    provenance="Specified phase-neutral operating angle limit")
formulation = IVRSDP(voltage_lncs=[cut])
println("Explicit phase-neutral domain and LNC pair configured.")
```

Pass the formulation to `build_opf` / `solve_opf` with the corresponding network.
Alternatively, call `add_voltage_lnc!(build, cut)` before optimizing a built model.
A dictionary map such as `VoltagePhasor(Dict(("bus","a")=>1, ("bus","b")=>-1))`
selects a delta winding voltage. Fixed turns can be represented by multiplying
its coefficients; magnitude bounds must then use the same referred voltage base.

The default `origin=:operating_limit` explicitly **restricts the OPF problem**.
It must not be described as improving the bound for the original unrestricted
problem. `origin=:derived` records the caller's assertion that a domain follows
from that problem; the library does not prove external assertions. Both require
a provenance description. Observed power-flow angles are not validity evidence.

The generic primitive can also act on internal EMF/current products if a caller
supplies their consistent lifted expressions and valid bounds. The initial
high-level map API covers terminal-voltage combinations; automatic transformer
leakage/EMF bound generation is not implemented in this version. Exact ideal-core
proportionalities often make corresponding EMF cuts redundant.

## Automatic line bounds

Use `IVRSDP(lnc=:lines)`. The default `:off` leaves the baseline SDP unchanged;
explicit `voltage_lncs` are applied independently of that switch.

Candidates are corresponding phase-neutral voltages when a shared neutral
conductor is mapped at both endpoints, otherwise corresponding phase-ground
voltages, plus corresponding phase-pair voltages. Positive lower and finite upper
bounds must match those physical voltage maps. Source phasors supply exact bounds.
A phase-ground bound is never substituted for a floating phase-neutral bound.
Missing bounds cause a recorded skip, without invented voltage/angle assumptions.

For a line with `vf-vt=Z*i_series`, endpoint currents satisfy

```math
i_f=i_{series}+Y_fv_f,\qquad i_t=-i_{series}+Y_tv_t.
```

With conductor endpoint ratings `Imax`, derive

```math
\bar I_{series,k}=\min\left(
 I_{max,k}+\sum_j |Y_{f,kj}|\bar V_{f,j},
 I_{max,k}+\sum_j |Y_{t,kj}|\bar V_{t,j}\right).
```

Zero admittance coefficients require no voltage bound. For voltage selection row
`d` (including the negative neutral coefficient),

```math
|u-v|\le\epsilon=\sum_k |(dZ)_k|\bar I_{series,k}.
```

This retains mutual coupling and neutral return. It does not treat terminal
ratings as series-current ratings when pi shunts are present. Line-level rating
overrides and linecode length scaling follow the electrical compiler.

For positive `lu,lv`, the identity

```math
|u-v|^2=(|u|-|v|)^2+2|u||v|(1-\cos\theta)
```

implies the angle bound

```math
|\theta|\le 2\arcsin\left(\frac{\epsilon}{2\sqrt{l_ul_v}}\right).
```

Only sectors narrower than π are used. Zero-drop pairs are skipped because the
linear electrical equations already impose identical phasors. Missing current
ratings, unbounded shunt corrections and overly wide sectors are reported.
The initial generator uses `i_max`, not apparent-power ratings or optimized bound
tightening. Small outward Float64 padding protects ordinary roundoff; this is
not an interval-arithmetic or rigorous numerical certificate.

## Diagnostics and verification

`build.lnc_diagnostics`, `result.lnc_diagnostics`, and `solve_diagnostics(result)`
report each pair's ID, applied/skipped status, origin, provenance, bounds and
skip reason. IDs must be unique. Explicit unsupported domains fail rather than
being silently skipped. Diagnostics remain available for unsuccessful solves.

Tests compare normalized coefficients with the original formulas; check rank-one
points over unequal magnitude ranges, phase rotations, zero-width sectors and
SI/per-unit scales; demonstrate separation of a SOC-feasible point; and verify
transformer winding orientation, automatic bounds, pi-shunt corrections and
neutral/mutual coupling. Clarabel and optional Mosek run the same cut tests.
An exact two-bus baseline remains exact with automatic cuts. These checks do not
establish a typical unbalanced OPF gap improvement or a faster solver profile.
Cuts can increase numerical cost; benchmark against the same problem domain.

`examples/compare_lncs.jl` provides a warmed comparison of `:off` and `:lines`,
reporting build/solve times, statuses, numerical objective bounds, maximum scaled
JuMP constraint violation and model size. Call `compare_lncs(input; optimizer=...)`
for a different solver. Its residual is not an AC-feasibility residual, and its
solver objective bound is not a rigorous certificate. An independently feasible
AC upper bound is still required to report an OPF optimality gap.

```@docs
LNCBounds
VoltagePhasor
VoltageLNC
add_lnc!
phasor_products
add_voltage_lnc!
LNCDiagnostic
```
