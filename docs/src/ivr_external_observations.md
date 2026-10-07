# Observation lifting on external MV/LV feeders

The [manufactured multiwinding panel](ivr_coil_observations.md) favoured broad
bounded observations over powers-only lifting. This experiment asks whether
that result transfers to external networks with ordinary transformers. It
separates physical and export admission from optimizer timing. No transformation
option or package default is removed or changed.

## Inputs and declared intervention

Three FrenchPowerGrids original files from the local BMOPFDraftData collection
span different network sizes and numbers of ordinary delta–wye transformers.
Selection preceded solver results. These networks retain explicit LV neutrals,
coupled conductor matrices and the source converter's electrical semantics.

| Source stem | Buses | Transformers | Added generators | Added IBRs |
|---|---:|---:|---:|---:|
| `24_MVFeeder1514` | 17 | 1 | 1 | 0 |
| `84_MVFeeder2024` | 110 | 7 | 18 | 18 |
| `32_MVFeeder3323` | 333 | 16 | 73 | 72 |

Original files have no dispatchable devices. The existing
[three-phase scenario](ivr_threephase_transfer.md) adds DERs at positive
three-channel load sites and 10% parallel demand, with low finite filter
impedance and voltage-dependent load laws. Zero-demand records remain present
but are not selected as DER sites. The smallest scenario has one constant-current
addition; the larger scenarios cycle constant-current, ZIP and exponential laws.
These are declared operating scenarios, not observations of installed DERs.
Every original record and limit is checked for exact preservation. The experiment
uses the explicit `transformer_nameplate=:bmopftools` policy in every arm.

A refreshed recursive census found **3,136 plain JSON files** in the supplied
`output` and `benchmarks` directories and no literal `"n_winding"` records.
Ignored files were included; compressed files were excluded. This panel therefore
does **not** establish external transfer of multiwinding-current elimination.
Source paths, hashes, complete scenario additions and the census remain outside
Git in `EXTERNAL_OBSERVATION_TRANSFER_20261007`. The external dataset is supplied
under the Etalab Open Licence 2.0; no network data are bundled here.

## Four formulations, two power objectives

The four arms cross powers-only versus broad bounded-observation lifting with
ordinary transformer currents retained versus eliminated. All retain conductor
regions, passive-block elimination, signed observation sharing and load-power
lifting. The reference used for endpoint membership has the full electrical
model and the same power objective and nameplate limits.

All numerical settings are fixed across arms: assembly power base 100 kVA,
source-region current power base 100 kVA, transformer-secondary region current
power base 1 kVA, generator P/Q base 1 kVA, lifted-power base 500 VA, nominal
transformer coordinates, composed row normalization, voltage-ground scaling
and KCL row-unit cap 1,000 A. These are numerical units, not changed device ratings.
Conflicting regional seeds are refused. This protocol supports step-down
delta–wye transformers; it is deliberately narrower than library coverage.

The mixed-device quadratic-cost objective prices source P, static-generator P
and internal IBR P, with dispatch P/Q penalties. Internal IBR pricing includes
filter losses. Exchange tracking targets source P at **35% of the scenario's
summed nominal load P**, source Q at zero and each dispatch P at its box midpoint,
with the established regularization coefficients. The exact terms and SI targets
are saved for every case. No legacy prices are inferred.

Ipopt uses MUMPS ordering request 7, gradient scaling, `tol=constr_viol_tol=1e-10`,
zero bound relaxation, no acceptable-iteration exit, 500 iterations and 30 CPU
seconds maximum. Julia and BLAS each use one thread. All arms encode the same
unloaded physical start; a converged solution is not used as their starting point.

## Correctness and result contract

All **24 preflight solves** pass physical SI audits, own-model and full-model
endpoint membership, reverse membership of the accepted anchor and an objective
evaluation from recovered physical powers. Objective values agree across all
four arms at absolute/relative tolerances `1e-6`/`1e-8`.

All emitted JuMP constraints have recorded inventory provenance in every build.
This checks emitted-constraint coverage; it does not establish that every possible
input bound expression was emitted. Schema auditing and independent physical
tests remain necessary for that stronger claim.

All 24 canonical SI exports are equal after reading through either FormulationLab
or BMOPFTools. The physical leaf paths, including native powers and exactly
reconstructed devices, agree across formulations. A separate exported-state
calculation verifies **30,048 coil-power identities** and **576 transformer
rated-port powers and limits**. The largest power reconciliation gap is
`1.46e-11` VA. These checks concern the variables and their physical definitions;
they do not require nonconvex solvers to return identical state vectors.

## Isolated wall-time confirmation — 7 October 2026

Two fresh-process batches use eight four-arm Williams sweeps per case: two
four-period blocks balance positions and immediate within-sweep predecessors.
Confirmation reverses both case and sweep order. One warmup per arm and case
precedes measurement. All **384 measured solves and 48 warmups** pass physical,
own/full-model, reverse-anchor and objective gates. Frozen sources and inputs
are unchanged. The two-second isolation guard records **268 snapshots** without
observed competing Julia; it cannot exclude other system load or shorter jobs.
No failed runs or outliers are discarded within the admitted campaign.

The table gives confirmation medians in milliseconds of Ipopt optimizer-call
wall time. Compilation, construction, extraction and audits are excluded.

| Buses | Objective | Explicit powers | Explicit broad | Eliminated powers | Eliminated broad |
|---:|---|---:|---:|---:|---:|
| 17 | Cost | 6.233 | 7.296 | 6.083 | 7.264 |
| 17 | Tracking | 5.810 | 6.894 | 5.762 | 6.697 |
| 110 | Cost | 164.512 | 181.242 | 165.553 | 182.548 |
| 110 | Tracking | 187.003 | 196.955 | 181.100 | 231.452 |
| 333 | Cost | 770.691 | 851.009 | 786.652 | 840.494 |
| 333 | Tracking | 956.141 | 995.662 | 909.060 | 973.925 |

Here explicit/eliminated refers only to ordinary transformer currents; all arms
retain the same other reductions. **Powers-only wins every cell in both batches**,
and the complete winning arm repeats in all six cells. With explicit currents,
the geometric mean broad/powers ratio is 1.117 in exploration and **1.108** in
confirmation. With eliminated currents it is 1.147 and **1.144**, respectively.
Each of the six case/objective cells has equal weight in these averages.

Transformer-current elimination wins four cells and retained currents win the
110- and 333-bus cost cells. Its powers-only geometric mean ratio is 0.989 in
exploration and **0.985** in confirmation. That roughly 1.5% average benefit is
small and reverses by workload; it is weaker evidence than the repeated lifting
comparison and does not support unconditional elimination.

On the 333-bus tracking case, broad observations add 6,890 variables and increase
iterations from 32 to 36 in both current representations. Eliminating ordinary
transformer currents removes only 96 variables and leaves iterations unchanged.
These counts describe the numerical trade-off; they do not isolate its causal
cost. In the smallest case every arm takes the same iteration count, yet broad
observations remain slower. Iteration count alone is insufficient.

The manufactured multiwinding benefit therefore **does not transfer to this
ordinary-transformer panel**. Powers-only lifting is the stronger candidate here
at the declared units and solver settings. Broad and selective observations remain
available for other cases. This finite three-feeder scenario panel is not a global
optimality result, a scaling sweep or proof of a universal fastest formulation.
Raw trials, protocol, source hashes, isolation snapshots and admission audit are
retained in the archive's `TIMING` directory outside Git.

## Reproduce the admission screen

Use a new empty output directory for each run:

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=test \
  --startup-file=no examples/benchmark_ivr_external_observations.jl \
  /path/to/24_MVFeeder1514.bmopf.json /path/to/new-evidence-folder
```

`INPUT.json` and `SCENARIO.json` describe the exact scenario. `REPORT.json` retains
every completed trial and the pending trial identifier. Each build has an emitted
constraint inventory; each optimal endpoint has a canonical `.result.json`.
Rejected trials retain their error or solver status. The runner refuses to
overwrite an existing evidence directory. Its timing fields are diagnostics:
`timing_eligible=false` and `ranking=null` prevent a preflight speed claim.

The targeted harness test exercises successful admission, objective agreement,
unchanged sources, failed-build retention, unsupported protocol scope and
protection against overwriting evidence:

```sh
julia --project=test --startup-file=no test/ivr_external_observation_tests.jl
```

All 11 harness assertions pass. The initial manufactured test fixture omitted
the positive voltage domain required by its added voltage-dependent load law;
that refusal and the original test source are preserved in the evidence archive.
The repaired fixture declares a positive voltage lower bound. No external input,
solver tolerance or admission threshold was changed to obtain the external passes.

## A structural hypothesis for the next experiment

The three scenario inputs contain 39/45, 458/660 and 1,471/2,235 load channels
with exactly zero nominal P and Q, respectively. They are retained in this
experiment. For a load law whose requested complex power is identically zero,
the equation ``S=U\overline I=0`` implies ``I=0`` only on a domain with
``|U|>0``. A declared positive coil-voltage lower bound can certify that domain;
an observed nonzero voltage at one solved point cannot.

An optional reduction could therefore remove certified zero-power coil currents
and their law equations, substitute zero into every observation, preserve any
associated bounds and recover the original result fields exactly. Uncertified
channels must remain explicit. The census alone neither proves eligibility nor
predicts a speed gain. A useful follow-up would compare this reduction with
selective observation lifting under the same power objectives and admission
gates, retaining every present control.

The subsequent [certified zero-load implementation](ivr_zero_loads.md) makes
this reduction opt-in, with a zero-voltage counterexample, atomic update guards
and original-channel export checks. Its numerical evidence is kept separate
from the unmodified scenarios and timings on this page.
