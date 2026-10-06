# Selective transformer-coil observation lifting

## Motivation

Eliminating transformer currents can reduce state dimension while making their
recovered affine expressions denser. Broad bounded-observation lifting can
reduce nonlinear coupling, but introduces auxiliaries for many other voltage
and current observations. The opt-in `observation_selection` controls which
original rows are eligible for those affine auxiliaries. It leaves power
lifting, electrical elimination, original bounds and physical outputs intact.

| Selection | Eligible original observation rows |
|:--|:--|
| `:all` | All requested observations; unchanged default |
| `:coil_voltages` | Rows matching stamped transformer coil voltages |
| `:coil_currents` | Rows matching stamped transformer coil currents |
| `:coils` | Union of coil voltage and coil current rows |

Selection applies only with `lifting=:bounded_observations`. It has no effect
for `:off` or `:powers`. The existing support threshold and observation-sharing
policies remain independent controls. No transformation option is removed.

## Provenance and exact graph extension

Eligible rows come from the electrical assembly's ordinary-transformer
`:transformer_coil_from` and `:transformer_coil_to` observations and multiwinding
`:transformer_coil` observations. Selection compares original row keys, before
coordinate composition, using their recorded coefficients and indices. It does
not identify a coil by an approximate coefficient match or a variable name.
For multiwinding devices, the stamped coil current is the series current;
terminal excitation and ground-current observations remain distinct.

Eligibility belongs to a **row**, not to a particular bound's label. A bus
voltage bound or power objective requesting the exact same original row is also
eligible. Conversely, a different original row that happens to compose to the
same affine expression is not selected merely because an auxiliary exists.
Selection occurs before affine-sharing lookup. Sharing can reuse definitions
only among requests that passed selection and the support threshold.

For an eligible requested observation ``u=aRy``, the threshold counts distinct
real native variables after composition. A count strictly greater than
`observation_support_threshold` creates a complex auxiliary ``w`` with

```math
\Re w=\Re(aRy),\qquad \Im w=\Im(aRy).
```

Otherwise the original affine expression remains direct. Identically zero
channels never acquire an auxiliary. Power lifting still defines exactly the
same complex power from its voltage and current, regardless of which factors
are explicit. Every original magnitude, current and power rating is enforced.

These equalities uniquely determine the new variables for each native state.
Projection removes them, and extension reconstructs them; neither operation
changes physical feasibility. Existing start and physical-point encoders
evaluate the auxiliary definitions in dependency order. Electrical coordinate
maps, omitted electrical rows and recovered SI variables do not change with
the selector. In particular, a coil-current auxiliary used in a nonlinear bound
does not reintroduce that current into retained KCL equations.

## Tutorial and profiling

```julia
using FormulationLab, Ipopt
options = IVRNLPOptions(
    lifting = :bounded_observations,
    observation_selection = :coils,
    observation_support_threshold = 2,
    observation_sharing = :signed,
    device_elimination = :all_transformer_currents,
    transformer_scaling = :nominal_multiwinding,
    row_scaling = :composed,
    kcl_row_max_base = 1000.0,
)
build = build_opf(network, IVRNLP(options); optimizer=Ipopt.Optimizer)
build.numerical_diagnostics[:observation_selection]
build.numerical_diagnostics[:observation_selected_row_count]
```

`observation_selected_row_count` counts distinct candidate original row keys,
including any empty key; it is `nothing` for unrestricted/inactive selection.
It is not the number of created auxiliaries. Only requested observations above
the threshold are lifted, and exact sharing can reduce the number further.

The reproducible study helper provides both support profiling and the five
experimental arms:

```julia
include("examples/benchmark_ivr_coil_observations.jl")
O = IVRCoilObservationStudy
O.supports(build)
O.run(output_directory) # Correctness/structure preflight; no timing ranking.
```

`supports` examines original coil observations in the native coordinates before
introducing affine auxiliaries. These counts can motivate a candidate, but are
not factorization fill or conditioning estimates. On the 24-unit fixture, 288
of 294 coil-current observations exceed the default threshold after full
transformer-current elimination; none do when multiwinding currents remain
explicit. Coil voltages have supports of two to four real variables, with only
30 of 294 exceeding the threshold. Some candidates have no requested bound or
objective use and therefore do not create auxiliaries.

## Controlled evidence, 7 October 2026

The 60-endpoint panel crosses 2/8/24 four-winding units, cost/tracking power
objectives, explicit/eliminated multiwinding currents and five lifting arms.
All use the same per-unit assembly, regional current and auxiliary power units,
nominal policy, KCL cap, physical start, solver settings and original bounds.
Among the four bounded-observation arms only the selector changes. The
powers-only control remains available separately.

All **60/60 endpoints** pass the unchanged physical, own/full-model,
reverse-anchor and independent winding-equation gates. The largest objective
spread is below ``2.436\times10^{-10}``. It passes the predeclared comparison
gate ``|f_1-f_2|\le\max(10^{-7},10^{-6}\max(|f_1|,|f_2|))``; the absolute
component governs the small tracking objectives. This does not establish
global optimality or identical optimizer paths. Eight archived default controls
reproduce their previous objective and iteration count exactly.

For 24 units, tracking objective and eliminated multiwinding currents:

| Lifting arm | Real variables | Unique Jacobian entries | Unique Hessian entries | Iterations |
|:--|--:|--:|--:|--:|
| Powers only | 5936 | 57368 | 16524 | 21 |
| Coil voltages | 5960 | 57464 | 16484 | 24 |
| Coil currents | 6224 | 58856 | 15084 | 21 |
| Both coil observations | 6248 | 58856 | 15044 | 21 |
| All bounded observations | 8384 | 63896 | 12032 | 20 |

Jacobian and Hessian counts are unique entries supplied through the backend
before Ipopt preprocessing. They are **not** KKT fill, factorization memory or
wall time. Selective coil lifting preserves much of the state-dimension saving
while recovering some of the Hessian sparsity lost through current elimination.
Broad lifting has more variables and Jacobian entries but the smallest Hessian
and one fewer iteration in this cell. Voltage-only lifting gives little
structural improvement and increases the iteration count here. All arms remain
available for subsequent experiments.

With explicit multiwinding currents, the current-only selector coincides with
the powers-only control on this panel: its coil currents have two-variable
support and do not exceed the threshold. This is an expected inactive control,
not independent evidence for a second formulation.

The appropriate next comparison is isolated, repeated **Ipopt optimizer-call
wall time** with matched objectives and physical gates. Compilation, model
construction, extraction and audit costs do not enter that ranking. These
single-trial structural results do not establish a fastest policy, so neither
defaults nor existing performance recommendations change.

## Verification scope

Tests verify original-row selection before affine sharing, ordinary and
multiwinding coil provenance, inactive/default behavior, exact auxiliary
definitions, starts, full-model membership and violations of selected winding
and unselected line bounds. Single-phase WYE and SINGLE_PHASE fixtures optimize
an objective expressed directly in coil power, with an independent analytical
target and full-model membership check. SI result exports retain their original
physical variables. These manufactured cases do not establish external-feeder
performance transfer.

Twenty additional four-unit solves span both objectives, both current
representations and all five arms. Their SI exports pass the FormulationLab
and BMOPFTools readers. Independent exported-state audits check 80 non-star
winding blocks and 960 coil apparent-power/current-magnitude records. Physical
leaf paths agree across all arms, including exactly recovered device channels.
These checks validate the result contract, not a speed advantage.

The preflight reports, source snapshots, initial test-development failure,
export checks and complete validation logs are retained outside Git in
`COIL_OBSERVATION_SELECTION_20261007`. The initial row-equality test incorrectly
compared different assembly power units; the corrected control aligns those
units without changing physical data or relaxing any tolerance.
