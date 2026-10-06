# Inherited shunt-loaded current boundaries on an MV feeder

This study transfers the [manufactured endpoint witnesses](ivr_shunt_boundaries.md)
to a separately selected original feeder. All **24 comparisons pass** with the
selected cable near its inherited 428 A limit at one end. Reversing the reactive
request reverses that end. Original matrices, ratings, demand, voltage bounds
and source phasors are preserved; two ideal dispatch devices are research
additions. This is correctness evidence, not a timing or global-optimality claim.

## Input selection and exclusions

The read-only inventory covers 3,136 JSON files under `BMOPFDraftData/output`
and `BMOPFDraftData/benchmarks`. It records file paths and SHA-256 digests before
solves. Of these, 23 lack the network table structure and 302 lack nonempty
input-line records. Among the remaining files, 2,582 have no structurally
identified shunted line with finite positive conductor ratings, and 229 do.
These are file counts, not counts of independent networks or certified models.
Standalone shunt devices do not qualify as line-end shunts.

There are 189 candidates in `original` directories: 150 French, 32 LV, six
DSuite and one combined input. Reduced and augmented inputs remain in the
inventory but are excluded from this selection. Sort original candidates
without DER by bus count and then path. Electrical screening of the 32
candidates with at most 70 buses rejects 19 LV inputs with undeclared ground
terminals. The remaining eleven French and two DSuite inputs pass the raw
declaration, electrical-assembly and start checks. Global specialization reports
`line_shunt` for two and `transformer_boundary` for eleven; these are
specialization refusals, not failures of the full IVR model. No ground tags or
electrical fields are repaired.
Passing these checks alone does not establish OPF feasibility.

The first eligible input is `FrenchPowerGrids/original/44_MVFeeder2707.bmopf.json`:
five buses, four lines, three conductors and delta loads. Its SHA-256 is
`8f404bdc5215e7c58c83693870c339557dfbd082cb0ce54e7c940eaed52384af`.
The source phase magnitude is approximately 11.778 kV, corresponding to
20.4 kV line-to-line; all buses inherit a 19–21 kV line-to-line band.
The input declares the Etalab 2.0 licence and upstream conversion provenance.
It is not bundled with FormulationLab, and this study does not independently
validate that upstream conversion against its source simulator.

Within this feeder, select the line with the largest sum of absolute shunt
matrix entries after applying length. This rule precedes optimization and
selects `44_96573`, from `44_MVLV24227` to `44_MVLV47838`, with length
4,552.160098827711 m. Its `U_AL_240` linecode has diagonal per-metre parameters

```math
R=1.25\times10^{-4}\ \Omega/\mathrm{m},\quad
X=8.99296465\times10^{-5}\ \Omega/\mathrm{m},\quad
B_f=B_t=1.84687\times10^{-8}\ \mathrm{S}/\mathrm{m}.
```

Off-diagonal entries and conductances are zero. Both the line and linecode
declare 428 A per conductor; the explicit line rating takes precedence.

## Dispatch and acceptance protocol

Use `scenario` and `profiles` from `examples/benchmark_ivr_line_transfer.jl`.
Add a delta generator at each selected endpoint, with fixed zero active power,
20 Mvar reactive capability and 20 MVA apparent-power capability per coil.
The total reactive target is +30 Mvar at the from device and −30 Mvar at the to
device, then reverse both signs. Each target is divided across three coils.
The objective remains the sum of per-coil squared reactive errors divided by
``(1000\ \mathrm{var})^2``. Targets are soft; the source can supply or absorb
the mismatch. This is not a constrained zero-net transfer.

Cross both directions, `none`/`gradient-based` Ipopt scaling and the six retained
profiles: full powers, reduced powers, reduced reuse, signed blocks, signed
blocks with reuse, and cap-four signed reuse. Models use per-unit coordinates:
10 kVA assembly/dispatch units, 1 kVA lifted-power units, composed circuit rows,
nominal transformer scaling and voltage ground scaling. The feeder contains
no transformer, so this panel provides no additional transformer evidence.

Every case uses a complete common physical start, strict Ipopt tolerances
(`tol=constr_viol_tol=1e-10`, `acceptable_iter=0`, `bound_relax_factor=0`),
own/full/reverse point membership, physical residual checks, independently
evaluated power objective and SI JSON round trip. The same gates admit all
24 initial cases and all 24 final cases with the additional certificates below.
Initial and intermediate admissions are archived separately; the certificates
were added after observing the initial endpoints, not prespecified as outcomes.

## Endpoint observations and counterexamples

| From-device target (Mvar) | From current (A) | To current (A) | Series current (A) | Near-boundary end | Minimum voltage margin (V) |
|--:|--:|--:|--:|:--|--:|
| +30 | 426.049588 | 428.000000 | 427.032127 | to | 597.104 |
| −30 | 428.000000 | 426.020871 | 427.017768 | from | 351.385 |

The table summarizes all three selected conductors and all twelve comparisons
per direction. The largest selected end-shunt current is approximately 0.990 A
for the positive request and 1.002 A for the negative request. All voltage
bounds remain strictly inactive. In the positive direction, the source-side
end of upstream line `44_129096` also reaches its inherited 428 A rating.
The selected cable is therefore not the only restricting equipment in that
direction. Source reactive power is approximately −15.004 and +14.997 Mvar,
respectively; the actual to-device totals are −14.309 and +15.628 Mvar.

For each recovered point, make two separate copies of the admitted input.
First set each selected conductor rating halfway between its two endpoint
magnitudes. Then use a second rating

```math
\widehat i_k=\tfrac12\left[
 \max(|i_{f,k}|,|i_{t,k}|)
 +\max\{\min(|i_{f,k}|,|i_{t,k}|),|j_k|\}\right].
```

The second construction requires its second term to be strictly smaller than
the first, which is verified here. The lower-current endpoint and series current
remain below this rating while the higher-current endpoint exceeds it. All
**48 certificates** are rejected by both the compiled model and the independent
physical auditor, with only the intended selected-line endpoint current-bound
family violating physical tolerances. These witnesses show concretely why a
series-only rating is insufficient for this inherited π line. They are tests of
a fixed recovered point against separate tightened inputs, not new optimized
operating points or a proof of global non-redundancy.

Signed slacks are retained. Julia reports two slightly negative selected-port
slacks; independent Python reconstruction reports eight, with minimum
``-5.69\times10^{-14}`` A. Six sign differences come from complex-magnitude
roundoff. Each report classifies its own negative slack as a violation, never
as strict activity. Agreement is asserted within numerical tolerance; the
shared claim is boundary proximity, not identical signs at machine precision.

## Independent result audit and reproduction

The Python audit reads all 24 final SI JSON exports and the unchanged input.
It verifies 576 line-port margins, 360 bus/conductor KCL balances and 360
line-to-line voltage intervals. It reconstructs the π-line equations, complex
losses, original delta load powers, generator powers, source phasors and
objective; it also checks both counterexample constructions, exact addition
manifest replay and identical physical/native-device output structures across
formulations. Maximum discrepancies are ``3.44\times10^{-12}`` V for KVL,
``2.39\times10^{-13}`` A for KCL and ``3.49\times10^{-9}`` VA for the loss
identity. Objective disagreement is below ``8.95\times10^{-8}`` on values of
order ``10^8``.

With the external dataset available, construct the declared scenario as follows:

```julia
include("examples/benchmark_ivr_line_transfer.jl")
L = IVRLineTransferStudy
original, detached = L.P.compiler_feeder_input(input_path;
    detach_legacy_provenance=true)
net, manifest = L.scenario(original; line_id="44_96573",
    terminal_indices=1:3, q_capacity_VAR=60e6)
profiles = L.profiles(net, manifest; target_VAR=30e6,
    nlp_scaling_method="none")
```

Use the build/solve/export pattern in the [exact-IVR tutorial](tutorial_exact_ivr.md)
and `L.current_activity(net, point)` for SI endpoint margins. Source-byte hashes,
the complete inventory, exclusions, protocol, all admission stages, JSON exports,
certificate results and independent audit scripts are retained outside Git in
`EXTERNAL_SHUNT_20261006`. The handover and roadmap also remain outside Git.
No package equations, defaults, transformation options or speed recommendations
change. Broader live transformer parity and isolated Ipopt wall-time comparisons
remain separate next steps.
