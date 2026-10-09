# Domains of reference validation

Reference agreement is evidence for a declared model and experiment. It does not
establish equivalence for every device, input convention or transformation.
This page separates fresh numerical comparisons, retained comparisons,
independent physical checks and result-reader compatibility.

## Source identity and freshness

The 9 October 2026 review used the clean BMOPFTools revision
`a8b52e069bfd4a7a57434c91bc0470ac03cfdd55`. All 93 tracked Julia files under
its `src` and `ext` directories were copied and hashed before the scalar
multiwinding refresh; their hashes and checkout status were unchanged afterwards.
The recorded reference-source hashes in the retained 6 October multiwinding
reports match this checkout.

That match establishes reference implementation identity. It does **not** make
the older native runs fresh tests of today's FormulationLab. Their original
inputs, native versions, controls, outcomes and exclusions remain part of the
evidence. The review independently recomputes acceptance from the recorded
gates, retains the excluded rows, and copies the original reports without
alteration. It does not rerun the retained optimization panels.

| Domain | Evidence and outcome | Limit of the claim |
|:---|:---|:---|
| Two-, three- and four-wire networks | The 9 October refresh passes four native/reference circuit cases and 36 assertions, including SI checks and full/reduced membership. | Small fixed-load circuits; no controllable-dispatch performance claim. |
| Single-phase transformer nameplates | The same refresh passes 12 native combinations and 108 assertions: active/absent caps, two bases, three lifting choices, dispatch and result fields. | Explicit `transformer_nameplate=:bmopftools` policy. |
| All-wye three-winding scalar caps | Fresh 9 October execution: 16 reference solves, 48 native comparisons and 1,552 assertions pass. | Lossless unequal-turn circuits, single/three-phase, forward/reverse flow, 1/100 kVA bases, absent/active winding-total caps. No vector-rating or excitation-placement parity claim. |
| Mixed three-winding connections | Retained YYY/YDY/DYY panel, both delta orientations and finite leakage: 171 of 240 native/reference comparisons admitted. | 69 comparisons remain excluded; baseline and absolute stopping treatments remain separate. |
| Fixed-Q and excitation intervention | Retained zero/excitation panels: all 300 native cases pass their native checks. Equality-treated reference admissions are 200/200; unmodified opposing-inequality controls are 144/200. | A documented private-model intervention, not the unmodified reference formulation. |
| Four-winding non-star leakage | Retained panel: 336/336 native cases admitted; reference equality treatment 112/112, unmodified controls 109/112. | Manufactured mixed-connection circuits with declared excitation, caps and pair data; three reference exclusions remain. |
| Inverters and regulators | Analytic inverter fixtures, per-bound negative witnesses, full/reduced membership, and OpenDSS regulator comparisons are in the core suite. | These are distinct evidence sources; they do not establish universal current BMOPFTools optimization parity. |

The small-network and nameplate refresh is described in
[the validation guide](ivr_validation.md). The richer retained panels are
documented in [mixed winding connections](ivr_nwinding_connections.md),
[fixed-Q equalities and excitation](ivr_nwinding_equalities.md), and
[non-star four-winding correspondence](ivr_nwinding_nonstar.md).
Counts in this table have different units: a reference case in the latter two
studies must agree with all three native lifting choices. They must not be
summed into an aggregate success rate.

## What each check establishes

The scalar-cap refresh checks native SI feasibility, analytically expected
dispatch and cost, reference objective agreement, corresponding winding-result
fields, unchanged input, and round trips through `BMOPFTools.read_result`.
The maximum observed objective difference is approximately
``7.49\times10^{-9}`` in the fixture's objective units. Current phase is undefined
at zero magnitude and is excluded from that field comparison when both currents
are below its declared threshold. This is numerical agreement at the script's
tolerances, not a proof of global optimality.

The mixed/non-star reports separately record termination status, independent SI
residuals, full/candidate membership, objective and current agreement, and
negative bound witnesses. In the excitation study, an excluded reference
endpoint passes scaled full-model membership but fails the SI audit. Keeping
both gates is therefore necessary. Reconstructed internal currents also remain
labelled as inferred quantities; reconstruction alone is not independent
measurement of those currents.

The fixed-Q hook replaces exactly coincident opposing inequalities with one
equality on a privately constructed reference model. It preserves the feasible
set while removing that particular gradient dependence. It leaves the sibling
checkout unchanged. Its better outcomes support a mechanism on this panel;
they establish neither a universal solver remedy nor a runtime advantage.

Reader compatibility proves that a serialized result is understood by the
reference reader and survives the declared round trip. It does not prove
electrical feasibility, objective equivalence or numerical optimization parity.
Those claims require their own checks. See [physical results and JSON](results.md)
for canonical fields, recovered quantities and nonfinite-value conventions.

## Reproduction and remaining limits

The optional integration environment and commands are listed in
`test/integration/README.md`. The scalar refresh is reproduced with:

```sh
julia --project=test/integration --startup-file=no \
  test/integration/ivr_nwinding_limits_reference.jl /tmp/nwinding-limits.json
```

Use separate output directories for the richer studies and inspect each reported
acceptance gate. Their successful process exit means the report was completed;
it does not mean all reference endpoints were accepted. Both packages use
declared per-unit bases. None of these correctness runs constitutes an isolated
timing campaign.

The older two-port [AC containment audit](ac_validation.md) records a different
reference revision and input route. Its discrepancies are historical findings,
not proof that the current checkout still fails those cases or that later
multiwinding results resolve them. Broad cross-engine parity remains unproven.

Likewise, independent [declared-bound reconciliation](ivr_declared_bounds.md)
and [emitted-constraint coverage](ivr_constraint_inventory.md) do not establish
complete input-schema coverage. The accepted physical scope and explicit
refusals remain governed by [the IVR contract](ivr_nlp.md).

The fresh report, source snapshot, read-only gate audit and unchanged retained
reports are archived outside Git in `REFERENCE_DOMAIN_REVIEW_20261009`.
The remaining completion audit must assess the original deliverables against
their own evidence; reference agreement alone cannot close that audit.
