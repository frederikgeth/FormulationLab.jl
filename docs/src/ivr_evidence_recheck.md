# Rechecking retained timing evidence

The formulation recommendations rely on conditional numerical evidence, not a
claim of a universally fastest model. On 9 October 2026, four retained campaigns
were rechecked against their frozen source bytes and raw records. **The audit
runs no optimizer and makes no new timing measurements.** It reproduced the historical admission
calculations and independently recomputed their trial counts and medians.

This complements the [current preflight gate](ivr_joint_reductions.md#Read-only-preflight-validation).
A historical result must be evaluated under its original source and protocol;
a preflight that lacks current required evidence cannot simply be relabelled as
current. Neither operation supplies a new runtime measurement.

## Source and artifact identity

The four manifests contain 1,185 entries in total, including repeated source
files across campaigns. Every entry resolved to bytes with the recorded SHA-256
digest, using retained source snapshots or unchanged original files. Resolution
required a content-hash match; a matching filename was insufficient.

The original audit scripts refer to live checkout paths and write their
admission files in place. The replay retained their calculations and assertions
while making two explicit adaptations: resolve frozen paths to verified snapshot
bytes, and direct outputs to a new audit folder. The adapted scripts and both
source hashes are retained. Nine audit outputs reproduce the original JSON
records exactly; the original records and frozen bytes remain unchanged.

| Campaign | Frozen entries | Measured solves | Excluded warmups | Evidence domain |
|:---|---:|---:|---:|:---|
| External observation lifting | 155 | 384 | 48 | Three ordinary-transformer feeders, cost and tracking, two current representations. |
| Certified zero-load elimination | 298 | 384 | 48 | Same feeder/objective panel, powers-only lifting, retained versus eliminated zero-load currents. |
| Observation selection after zero reduction | 316 | 1,200 | 120 | Five observation choices within each feeder/objective/current cell. |
| Manufactured multiwinding observations | 416 | 1,200 | 120 | 2/8/24-unit networks, cost and tracking, explicit/eliminated multiwinding currents. |
| **Total** | **1,185** | **3,168** | **336** | Separate campaigns; no pooling into a universal ranking. |

The nine replays comprise four timing admissions, three physical-export audits
and two zero-load inventory audits. The export audits recheck 132 canonical
preflight exports: physical leaf paths, recovered coil power products, IBR
internal power products, delta–wye rated-port limits and exact zero-load recovery
where applicable. Existing BMOPFTools reader records are retained; this review
uses those historical reader records and does not claim a fresh reference-package
execution. The manufactured timing trials additionally retain their independent
non-star winding-equation checks.

## Independent raw-record checks

A separate calculation reads all measured trials and warmups. It checks complete
trial counts, accepted SI/own/full-model gates, reverse-anchor membership,
physical-objective reconciliation, common-start encoding, declared power bases,
solver controls, paired orders and positive finite Ipopt wall times. Its medians
agree exactly with the historical admission records.

All four campaigns declare a 100 kVA assembly power base. This is **not** a claim
that every variable uses that base: regional current, dispatch and auxiliary
power bases remain explicitly recorded in the profiles. Complete physical-start
encoding is checked independently of start feasibility. The maximum recorded
binding/reconstruction discrepancy is approximately ``1.26\times10^{-15}`` per
unit on the external panels and ``9.29\times10^{-13}`` on the manufactured panel.

Each batch has excluded warmups and a complete balanced schedule. Within-sweep
positions and ordered predecessors occur twice. Confirmation reverses the
planned order in a fresh process. Between-sweep transitions are not balanced.
The isolation records cover the recorded campaign interval, subject to the
whole-second precision of shell start/end stamps. Maximum observed sampling
gaps are approximately 2.11–2.24 seconds. No competing Julia process is recorded.
Sampling cannot rule out short jobs or unrelated system load; the recheck does
not strengthen that original isolation claim.

For arm ``a`` in batch ``b``, the primary estimate remains

```math
\widetilde T_{a,b}=\operatorname{median}_{r\in\mathcal R_b}
T^{\mathrm{Ipopt}}_{a,b,r},
```

where ``\mathcal R_b`` contains the declared measured repetitions only. Ratios
compare these medians within the planned cell. Compilation, model construction,
result extraction and audits do not enter the estimate. Geometric means across
cells are descriptive summaries, not population estimates or confidence bounds.

## Conclusions retained

| Comparison | Rechecked confirmation result | Interpretation |
|:---|:---|:---|
| Broad versus powers-only on the unreduced external panel | Geometric mean time ratios 1.108 with explicit ordinary currents and 1.144 with eliminated currents. | Powers-only remains the economical general starting candidate within this domain. |
| Certified zero-load elimination versus retention | Ratios 0.846 and 0.852 for the two ordinary-current representations. All twelve matched comparisons improve in both batches. | Exploit exact zero-power channels only when the required nonzero-voltage certificate holds. |
| Broad versus powers-only on the zero-reduced 333-bus tracking case | Confirmation ratios 0.891 and 0.862. | Keep the workload-specific broad-lifting exception; the corresponding cost ratios are approximately one. |
| Broad observations on the manufactured multiwinding panel | Confirmation ratios to powers-only range from 0.507 to 0.864; broad wins all twelve cells in both batches. | Strong evidence for this finite panel, not a universal transformer policy. |

The [external observation](ivr_external_observations.md),
[zero-load](ivr_zero_loads.md),
[zero-reduced observation](ivr_zero_load_observations.md) and
[multiwinding observation](ivr_coil_observations.md) pages retain the detailed
scope and tables. Selective-observation current representations were scheduled
in separate cells; their cross-cell ratios do not inherit the balanced
within-cell design. Previously excluded attempts remain excluded. Recent
refinement/pivot diagnostics remain unranked by wall time.

The replay source, resolved-path manifest, independent calculations and unchanged
artifact hashes are retained outside Git in
`HISTORICAL_ADMISSION_RECHECK_20261009`. This closes a provenance and reproducibility
check on these numerical claims. It does not prove global optimality, full
input-schema coverage, equivalence of every untested option combination, or
performance on unseen networks.
