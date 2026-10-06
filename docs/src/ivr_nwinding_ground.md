# Finite-ground units across multiwinding transformers

## Motivation and independent controls

A ground admittance can be stiff in one voltage base and modest in another.
The existing `ground_scaling=:regional_voltage` selects its multiplier from
ordinary-transformer voltage regions. It deliberately skips multiwinding
transitions, even when `transformer_scaling=:nominal_multiwinding` is enabled.
The opt-in `ground_scaling=:regional_multiwinding_voltage` extends only this
multiplier selection to the [multiwinding nominal-base graph](ivr_nwinding_coordinates.md).
All previous policies and the default `:off` remain available.

The policies answer separate questions. Transformer scaling selects voltage
and current coordinate units; ground scaling selects an additional multiplier
for eligible free voltage coordinates attached to one-terminal finite shunts.
Neither changes a physical admittance, creates a reference, removes a degree of
freedom or replaces a finite ground by an ideal ground. Selection of regional
current-power bases does not change the ground multiplier's power denominator.

## Definition and equivalence

For an eligible bus-terminal voltage and its one-terminal shunts ``Y_j``, let
``V_r`` be the assigned nominal characteristic voltage and ``S_b`` the common
assembly power base. The multiplier is

```math
Z_r=V_r^2/S_b,\qquad
s=\max\left(1,\max_j |Y_j|Z_r\right).
```

With transformer voltage scaling disabled, ``w=sV/V_b``; reconstruction uses
``V=V_b w/s``. With nominal transformer voltage scaling applied successfully to
the coordinate, ``w=sV/V_r`` and ``V=V_r w/s``. Each original current, power,
voltage expression and bound uses the same reconstruction. Thus the change is
an invertible diagonal coordinate transformation, subject to finite nonzero
representability of the stored coefficients. It introduces no constraint or
variable, and consumes no equation.

As in the existing regional policy, eligibility requires a retained singleton
physical voltage coordinate, unfixed by a source or ideal ground. Multi-terminal
shunts and voltages already reconstructed from other physical coordinates are
not selected. Multiple shunts at a terminal use the largest eligible multiplier;
their original admittances remain separate. Multipliers at most one leave the
coordinate unchanged. Nonfinite scales or coefficient overflow/underflow are
refused, without dropping nonzero terms.

The base graph uses WYE/SINGLE_PHASE coil nominals and DELTA coil nominals
divided by ``\sqrt{3}``. The latter is a characteristic unit, not a neutral or
an assumed phase-to-earth voltage. Inconsistent nominal cycles, inconsistent
source bases and unanchored regions keep the established global-base fallback
with diagnostic reasons. A floating delta still requires a declared physical
reference; the existing initializer refusal is unchanged.

Both regional-ground policies use **assembly** ``S_b``. They do not substitute
the independently declared `current_power_bases`, generator dispatch bases or
auxiliary power bases. If scaling changes any coordinate, legacy ground-dependent
row normalization responds as before; explicit `row_scaling=:composed` remains
available independently. The KCL row cap is another independent option.

## A numerical example

Consider an assembly with ``V_b=2300`` V and ``S_b=100000`` VA, behind a
multiwinding secondary whose characteristic unit is 115 V. For a 0.5 S shunt,
the global multiplier is 26.45, whereas the regional raw multiplier is 0.066125;
the new policy therefore leaves that coordinate unscaled. For a ``10^8`` S
shunt, the multipliers are ``5.29\times10^9`` and ``1.3225\times10^7`` respectively.
The factor of 400 follows from the squared voltage-base ratio. Smaller
multipliers alone do not establish better conditioning or faster optimization.

## Tutorial and diagnostics

```julia
options = IVRNLPOptions(
    ground_scaling = :regional_multiwinding_voltage,
    transformer_scaling = :nominal_multiwinding,
    row_scaling = :composed,
    kcl_row_max_base = 1000.0,
)
build = build_opf(network, IVRNLP(options); optimizer=Ipopt.Optimizer)
report = build.numerical_diagnostics[:ground_scaling_report]
report.scaled_terminals
report.retained_shunts
report.region_assignment
```

The first field gives each selected terminal, coordinate and multiplier; the
others explain retained declarations and voltage-base fallbacks. The two scaling
policies need not be enabled together. After solving, use `physical_residuals`
and full-model membership to check original SI feasibility. The recovered
BMOPFTools-compatible JSON retains the same physical variables. A tiny finite
ground voltage must still be exported: its product with a large admittance can
represent a substantial physical current.

The reproducible preflight helper is:

```julia
include("examples/benchmark_ivr_nwinding_ground.jl")
G = IVRNWindingGroundStudy
G.run(output_directory; earth_return_S=1e-3)
```

This is a correctness study, with no speed ranking. It varies only
`ground_scaling` across `:off`, `:voltage`, `:regional_voltage` and
`:regional_multiwinding_voltage`, holding the multiwinding transformer policy,
regional current units, power objective, row cap and physical start fixed.
Raw errors and rejected endpoints are retained. Performance assessment requires
a separate isolated, repeated comparison of **Ipopt optimizer-call wall time**;
compilation, construction, extraction and diagnostic costs do not enter it.

## Manufactured fixtures and verification limits

`G.network` starts from the shared-supply multiwinding feeder family and explicitly
replaces each declared secondary ideal reference with a finite shunt. This
defines a new physical test network; the scaling option never performs that
replacement. Delta references remain attached to their declared conductor.

The default fixture has no added phase-to-earth return. Its 128-endpoint panel
crosses 2/8 units, 0.5/``10^8`` S reference shunts, cost/tracking power objectives,
four current/lifting representations and four ground policies. All 128 endpoints
pass the unchanged physical, own/full-model, reverse-anchor and independent
winding-equation gates. All 32 matched iteration comparisons between the two
regional policies are equal. Maximum objective spread is below
``2.636\times10^{-13}``; maximum finite-ground current is below
``2.132\times10^{-7}`` A. This is a weak live-ground stress case, and it supplies
no evidence of a performance benefit. The negative control is retained.

Setting `earth_return_S=1e-3` additionally places a declared phase-to-earth shunt
at every secondary feeder endpoint. The reference shunt then carries a live
return current. This is a separate physical panel, compared only across scaling
policies applied to that same panel. It must not be treated as an equivalent
reformulation of the default fixture.

Regression tests cover single-phase analytical optima, WYE and delta references,
complex stiff admittances, conservative fallbacks, coefficient representability,
map round trips, unchanged equations and dimensions, full/reduced membership,
SI JSON recovery, and detection of a deliberately perturbed finite-ground
current. Both nominal-unit policies and all prior transformation options remain
available. These manufactured families do not establish transfer to external
multiwinding feeders or a universally fastest formulation.


## Live return-current evidence, 7 October 2026

The separate 128-endpoint live-return panel uses the same factorial design,
with the additional 0.001 S phase-to-earth shunts. All 128 endpoints pass.
Maximum reference-shunt current is below ``0.199152`` A, and maximum
reference-shunt voltage is below ``0.397509`` V. Maximum objective spread across
policies is below ``3.691\times10^{-13}``. Tiny voltages in the stiff-ground
cases remain physical reconstructed values, not fixed zeros.

| Panel | Accepted endpoints | Matched cells with fewer/equal/more iterations, new versus ordinary regional policy |
|:--|--:|:--|
| References without added earth-return shunts | 128/128 | 0 / 32 / 0 |
| Explicit phase-to-earth return paths | 128/128 | 0 / 32 / 0 |

Indeed, all four policies have equal iteration counts within each cell in both
panels. Counts across cells range from 18–25 in the first panel and 19–29 in the
second. For these fixtures the global and ordinary regional policies select
identical multipliers. At 0.5 S, the new policy selects no multiplier above one
and matches `:off`; these coincident controls are not independent interventions.
At ``10^8`` S its secondary reference multipliers differ by factors of
400, 1600 and 6400 from the ordinary-only fallback. This difference still
produces no observed iteration reduction. Optimizer wall-time benefits remain
untested in an isolated repeated campaign; no default or recommendation changes.

A separate four-unit export panel solves both physical fixtures, both shunt
strengths, both objectives and all four policies: **32 exports** pass both the
FormulationLab and BMOPFTools readers. All physical leaf paths agree across
policies within each fixture, including recovered device observations. There
are 8216 paths per export without added earth returns and 8300 with them.
Independent checks reproduce all **576** shunt-current and shunt-power records
from exported SI voltages and original admittances, within ``10^{-10}`` A/VA.
This preserves the original result schema rather than exposing native scaled
coordinates as physical results.

The **834 targeted assertions** pass. Full regression and documentation logs,
source snapshots, both unranked preflight panels, exports and analysis scripts
are archived outside Git in `NWINDING_GROUND_UNITS_20261007`. The initial weak
return-current panel and its exact source are retained separately; it was not
replaced by the stronger fixture. These are correctness and diagnostic results,
not speed evidence.
