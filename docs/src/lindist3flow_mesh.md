# Practical inputs and meshed line networks

LinDist3Flow now offers deterministic transformer-map inference, explicit
impedance-alias normalization, and an opt-in meshed linear approximation. The
radial model remains the default. No mode opens branches automatically or uses
an incumbent solution to choose constraints.

```julia
options = L3FOptions(
    unsupported=:lower,
    topology=:meshed_linear,
    infer_terminal_maps=true,
    transformer_impedance=:from_terminal,
    s_base=1e6,
)
result = solve_l3f_opf("network.bmopf.json", Clarabel.Optimizer; options)
```

The impedance convention in this example is an **explicit caller assumption**.
Do not select it merely to make a file run. Input and returned quantities remain
SI; per-unit scaling applies to the private optimization copy.

## Transformer input normalization

For `delta_wye` and `wye_delta`, missing terminal maps can be inferred when
`terminal_conventions.phase` supplies exactly three distinct, ordered phase
identities, all are present on the bus, and there are no unknown terminals or
multiple possible neutrals. The delta map contains those phases. The wye map
also contains the declared neutral when present. Existing neutral-reduction
checks then determine whether that neutral may be eliminated.

Inference never replaces a supplied map. An ambiguous case raises
`E.L3F.TERMINAL_MAP_AMBIGUOUS`; inferred maps produce
`L.L3F.TERMINAL_MAP_INFERRED` findings carrying the chosen values. Set
`infer_terminal_maps=false` to require explicit maps, as before. The caller's
snapshot is not mutated.

The aliases `r_series` and `x_series` are recognized for single-phase and Yd/Dy
transformers only. Their interpretation must be supplied through
`transformer_impedance`:

| Value | Meaning |
|:--|:--|
| `:unspecified` (default) | Refuse aliases with `E.L3F.IMPEDANCE_CONVENTION_REQUIRED`. Canonical side-specific fields still work. |
| `:from_terminal` | Total leakage referred to the primary side, in terminal-equivalent ohms. Move to `r_series_from` / `x_series_from`. |
| `:from_coil` | Total leakage referred to a primary coil. Divide by three for a delta primary; otherwise move unchanged. |

The division by three converts a delta coil impedance to the terminal-equivalent
convention consumed by the existing Yd/Dy leakage lowering. With nominal voltage
ratio ``N``, a Dy terminal equivalent refers to the wye side as ``Z/N^2``; a delta
coil value refers as ``Z/(3N^2)``. This does not reinterpret nominal voltages,
change taps, or establish which convention a particular data producer intended.

Aliases may not coexist with any canonical side-specific leakage fields, even
if the values appear consistent: otherwise total leakage could be counted twice.
They must be finite scalars. Normalization records the original values, selected
convention, and conversion factor. Existing `unsupported=:lower` leakage handling
then applies; the strict `:reject` mode still refuses nonideal transformers.

Unrecognized top-level transformer fields with electrical prefixes (`r_`, `x_`,
`g_`, `b_`, `z_`, `v_nom`, `i_max`, `s_rating`, `tap`, `impedance`, `no_load`,
case-insensitive) now produce `E.L3F.UNCONSUMED_ELECTRICAL_FIELD`. This is a targeted
check, not a general schema validator. Arbitrary metadata remains metadata.
The guard also applies in permissive mode.

Explicitly zero line-shunt coefficients are accepted by the strict mode.
Nonzero shunts still require the existing `:lower` endpoint-shunt formulation;
no small-coefficient threshold is used for this strict-mode distinction.

## Fixed meshed approximation

`topology=:meshed_linear` retains all branches. Its first supported scope is
**line cycles with transformer bridges**: removing any transformer must separate
its endpoint buses. A transformer inside a bus-graph cycle, including a parallel
transformer bank, raises `E.L3F.MESH_TRANSFORMER_CYCLE`. Such banks can still use
the established radial mode when their conductor topology is radial.

The model reuses the existing nodal active/reactive balances, magnitude-drop
equations, shunts, component limits and transformer maps. Chords retain their
input orientation; power variables are signed. A source-rooted traversal assigns
orientations to the other branches. Propagated reference phasors must agree on
all paths. Each island still requires one fixed-voltage source, and every
retained conductor must be reachable.

Magnitude drops alone do not determine physically meaningful loop flows. The
new mode adds one angle-deviation variable ``\delta\theta_{i\phi}`` for each
terminal participating in a line and a linear angle-drop equation on **every**
line. With fixed reference voltages ``\bar V``, series power ``P+\mathrm jQ``
and

```math
c_{\phi\psi}=\frac{Z_{\phi\psi}}
 {\bar V_{i\phi}\bar V_{i\psi}^{*}},
```

the added equation is

```math
\delta\theta_{j\phi}-\delta\theta_{i\phi}
=\sum_\psi\left[-\Im(c_{\phi\psi})P_{ij\psi}
                 +\Re(c_{\phi\psi})Q_{ij\psi}\right].
```

It follows by substituting the fixed-reference current
``I_\psi=(P_\psi-\mathrm jQ_\psi)/\bar V_{i\psi}^{*}`` into
``\Delta V=-ZI`` and taking ``\Im(\Delta V_\phi/\bar V_{i\phi})``.
This complements the existing squared-magnitude equation obtained from
``2\Re(\bar V_\phi^{*}\Delta V_\phi)``. Summing angle differences around a
cycle enforces linearized cycle consistency, including mutual impedances and
unbalanced injections. It is the first-order extension of the fixed-reference
line approximation described in [the component equations](lindist3flow_components.md).

There is one zero angle gauge per line-connected terminal region. Transformer
bridges separate regions: these angle deviations are local auxiliary variables,
not a complete recovered AC angle solution. They are inspectable through
`build.variables[:angle_deviation]`; result voltage-angle semantics remain fixed
reference coefficients. Line endpoint reference phasors must coincide.

This is a fixed LP/SOCP, without nonlinear initialization, iteration, adaptive
cuts or topology selection. The result carries `A.L3F.MESH_LINEARIZED` and the
selected topology mode. It omits series losses and remains an approximation,
not an AC-feasible dispatch or a certified objective bound. Zero-impedance or
otherwise degenerate loops can still leave circulating flows indeterminate.

## Verification and Springfield

The meshed regression uses an unbalanced three-phase triangle with mutual
impedance. An independent complex nodal-admittance solve with fixed-reference
current injections predicts every branch's active/reactive flow and the
linearized squared voltages. Tests cover reversed chord orientation, SI/per-unit
equivalence, transformer-cycle rejection, map ambiguity, alias conflicts,
unchanged inputs, and equality with an explicitly encoded canonical delta bank.
This verifies the intended linear approximation; it is not an exact AC oracle.

`examples/check_springfield_l3f.jl INPUT OUTPUT` exercises the supplied Springfield
network under both explicit impedance interpretations. It preserves all 1,475
original lines, 19 transformers and three independent MV loops. Leakage lowering
can add internal lines and buses. The two interpretations are sensitivity
scenarios: the script does not establish the data producer's convention.

The 12 September 2026 run returned `OPTIMAL` in both scenarios:

| Assumed primary impedance convention | Native Clarabel s | Build s | Minimum voltage / reference |
|:--|--:|--:|--:|
| Terminal equivalent | 0.3960 | 6.9088 | 0.92692 |
| Coil | 0.1887 | 2.1030 | 0.93331 |

These are single runs, not timing distributions. The initial PowerIO read and
source-preserving emission took 50.97 s, including first-use compilation; this
is separate from the build and native solve columns. Each SOCP has 18,150 variables,
1,494 lines after adding 19 leakage equivalents, and all 19 transformer banks.
There are 38 inferred terminal maps and 19 normalized alias pairs. Source import
is 3.447445 MW in both runs, equal to the fixed active load in this lossless
model; that objective is not an accuracy check. The voltage ratios above use the
propagated no-load reference, not independently verified nominal ratings. No
nonlinear AC replay was performed for this large case.

[Raw study record](https://github.com/frederikgeth/FormulationLab.jl/blob/codex/l3f-input-and-meshed-mode/examples/results/springfield_l3f_2026-09-12.json)
includes the input hash, solver versions, timings and every normalization finding.
Reproduce with:

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=test examples/check_springfield_l3f.jl INPUT.json OUTPUT.json
```
