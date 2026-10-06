# Four-winding non-star leakage and exact recovery

The [three-winding comparison](ivr_nwinding_connections.md) and
[fixed-Q intervention](ivr_nwinding_equalities.md) established correspondence
for mixed connections and explicit excitation. Four windings introduce an
additional test: a general pairwise leakage model need not admit an ordinary
star representation. This study exercises that distinction with all secondary
windings loaded. It adds fixtures, regression tests and a live reference runner;
the production transformer equations and formulation defaults are unchanged.

## A certificate against a star fit

The declared short-circuit reactances, in ohms referred to winding 1, are

```math
(x_{12},x_{13},x_{14},x_{23},x_{24},x_{34})
=(0.04,0.07,0.10,0.07,0.11,0.12).
```

An ordinary star would require ``x_{ij}=x_i+x_j`` and therefore
``x_{12}+x_{34}=x_{13}+x_{24}=x_{14}+x_{23}``. Here these sums are respectively
0.16, 0.18 and 0.17 Ω. No choice of four star reactances, even allowing negative
branches, preserves all six pair values. The coupled reduced reactance matrix is

```math
X_B=\begin{bmatrix}
0.04&0.02&0.015\\
0.02&0.07&0.025\\
0.015&0.025&0.10
\end{bmatrix}\ \Omega.
```

It is symmetric with positive diagonal and strict diagonal dominance, hence
positive definite. The fixture is a valid passive leakage example, rather than
a failure induced by inconsistent pair data. Positive winding resistances add a
positive resistive part. Both implementations retain the coupled matrix without
fitting a star or requiring its inverse.

For nominal turns ``N_k=V_{\mathrm{nom},k}/V_{\mathrm{nom},1}``, coil voltages
``u_k=D_kv_k`` and currents ``j_k`` entering each winding, the independently
checked SI equations are

```math
\sum_{k=1}^4 N_kj_k=0,\qquad
u_1-\frac{u_i}{N_i}+\sum_{k=2}^4 Z_{B,i-1,k-1}N_kj_k=0,
\quad i=2,3,4.
```

Each equation holds separately for all three coil channels. Define
``\widehat j=(N_2j_2,N_3j_3,N_4j_4)`` for one channel. Bare transformer complex
loss satisfies
``\sum_k u_k\overline{j_k}=\sum_i(Z_B\widehat j)_i\overline{\widehat j_i}``.
Excitation is accounted for separately at its physical terminals.

## Physical scenarios and objective

The seven connection/orientation cases are YYYY and YDYY/YYYD/DYYY with each
delta roll ``\pm1``. Wye coil nominal voltages are ``230/2^{k-1}`` V; delta
nominals additionally include ``\sqrt3``. Winding resistances are
``0.02/4^{k-1}`` Ω on their local coil bases. A fixed balanced source supplies
winding 1. Wye neutrals are grounded; secondary delta common mode is fixed by
grounding terminal c. All coil and circulation channels remain represented.

Each secondary carries three single-phase loads. Forward active demands are
``(200,160,120)`` W on winding 2, ``(60,50,40)`` W on winding 3, and
``(100,80,60)`` W on winding 4. Reverse flow negates demand. Generators on
windings 2 and 4 have ``0\le P_g\le300`` W forward, or
``-300\le P_g\le0`` W reverse, fixed ``Q_g=0`` and a 300 VA capability per
device. Single-phase dispatch connections keep transformer delta conventions
separate from generator-delta dispatch conventions.

The linear power-cost objective is ``\sum_g \sigma P_g/1000``, with
``\sigma=1`` forward and ``-1`` reverse and powers in W. It minimizes the
magnitude of local support; the ideal source is unpriced. This is a declared
diagnostic objective, not a general tariff model. The bounded treatment adds
scalar winding caps 300 VA and 180 VA on windings 2 and 4. Under the aligned
BMOPFTools policy these are 100 VA and 60 VA per coil. Both caps are active;
the uncapped treatment leaves them absent.

The excitation treatment adds an explicit per-coil admittance
``y_4=(2-\mathrm{i}3)/V_{\mathrm{nom},4}^2`` S on winding 4. At nominal voltage
each branch consumes 2 W and 3 var. Terminal current is
``D_4^{\mathsf T}(j_4+y_4u_4)``; exported bare coil current remains ``j_4``.
The reference materializes a bus shunt, while native recovery includes it in
winding terminal current. The independent audit counts it once. Ambiguous legacy
excitation fields and reference-unsupported tap fields are absent.

## Comparison design and retained exclusions

Seven connection/orientation cases, two flow directions, absent/present caps,
absent/present excitation and 1/100 kVA assembly bases give **112 physical/base
cases**. All models use per-unit coordinates. Native comparisons use three
lifting choices: off, power lifting and bounded-observation lifting, giving
**336 solves**. They retain regional coordinates, passive blocks, nominal
transformer coordinates, composed rows and the ordinary-transformer-current
option, with 500 VA auxiliary power units. This does not enable elimination of
general multiwinding currents.

Each case also receives two reference solves: original opposing fixed-Q
inequalities and the existing diagnostic equality hook, replacing six exact
pairs on the privately built reference model. The external BMOPFTools checkout
is unchanged. The **224 reference solves** use the same baseline settings:
`tol=constr_viol_tol=1e-10`, `acceptable_iter=0`, `bound_relax_factor=0`,
`max_iter=500` and gradient-based NLP scaling.

Native admission requires strict termination, physical residuals, own/full and
reverse point membership, independent leakage/ampere-turn/loss equations,
objective agreement, reader round trip and the restriction tests below.
Reference admission additionally requires agreement with **all three** native
models: objective `atol=1e-7, rtol=1e-6` and coil-current
`atol=2e-5` A, `rtol=1e-6`. A completed report retains failures and does not
imply universal admission or global optimality.

| Treatment | Strict solves | Fully admitted |
|:--|--:|--:|
| Native lifting variants | 336/336 | 336/336 |
| Reference fixed-Q pairs | 111/112 | 109/112 |
| Reference fixed-Q equality | 112/112 | 112/112 |

The original paired-Q controls have two `LOCALLY_SOLVED` endpoints that miss
objective/current agreement: uncapped forward YYYY with excitation at 1 kVA,
and uncapped forward YYYD with roll −1, no excitation, at 100 kVA. Their cost
gaps are approximately ``1.107\times10^{-5}`` and ``1.149\times10^{-5}``.
Both pass the standard physical and membership checks. A reverse, capped DYYY
case with roll −1, excitation and 100 kVA returns `OTHER_ERROR` despite close
cost/current agreement. Its status remains an exclusion.

All equality-treated reference cases pass, with maximum cost gap
``4.659\times10^{-11}``. This extends the earlier redundant fixed-Q mechanism
evidence to non-star leakage. It is not a universal constraint-regularity proof
and makes no timing claim: correctness jobs may overlap other workloads.

## Restriction witnesses and independent export audit

Every native endpoint is rejected by both the physical auditor and candidate
model after reducing ``x_{34}`` from 0.12 to 0.10 Ω. This modified matrix remains
positive definite; rejection detects a changed constitutive law rather than
invalid input. Each bounded endpoint is also rejected when either winding cap
is reduced by 10%, with the other cap untouched. The runner records **336
pair-change certificates and 336 individual bound-tightening certificates**.
All coil channels of all four windings carry nonzero power, so an unloaded
fourth winding cannot hide an omitted coupling term.

An independent Python reader audits **all 560 saved endpoints**, including the
three excluded reference controls. It checks 6,400 ungrounded KCL balances,
1,680 coil-cap observations and 840 excitation contributions. Native metadata
is independently reconstructed for 5,088 terminal-current/power channels and
4,032 coil-power channels. All 336 native exports also pass a separate on-disk
BMOPFTools reader comparison. Physical result structures agree across lifting,
flow direction and assembly base for each connection/bound/excitation treatment.

The SI audit retains a stricter ``10^{-5}`` var fixed-Q threshold. The
`OTHER_ERROR` reference endpoint violates it with a residual of
``1.843\times10^{-4}`` var; it had already failed strict-status admission.
**All 557 admitted endpoints pass the independent audit**, as do the two
economically excluded but strictly solved controls. The remaining endpoint and
its residual are retained without changing the runner flags or audit tolerance.
Maximum leakage error across all 560 files is ``1.508\times10^{-9}`` V,
ampere-turn error ``6.769\times10^{-14}`` A, loss-identity error
``6.677\times10^{-11}`` VA and objective reconstruction error
``8.327\times10^{-17}``. The audit independently verifies 560 pair-perturbation
rejections and 560 tightened-cap rejections over its larger endpoint set.
Its other thresholds are ``10^{-6}`` A/V for circuit equations and KCL,
``10^{-3}`` VA for loss and cap checks, ``10^{-5}`` VA for load/native power
reconstruction, and ``10^{-8}`` for cost reconstruction.

The new regression file passes **15,461 assertions**, including the non-star
certificate and 336 native solves. The fixture, preflight, optional live runner,
all failed outcomes, audit scripts and reference source hashes are preserved
outside Git in `NONSTAR_FOUR_WINDING_20261006`.

## Reproduction and implications

```sh
julia --project=test test/ivr_nwinding_nonstar_tests.jl
julia --project=test/integration test/integration/ivr_nwinding_nonstar_reference.jl /tmp/nonstar/report.json
```

The integration environment requires the local BMOPFTools dependency specified
in its project. The runner records the reference revision, dirty status and
relevant file hashes. No source checkout is modified by the fixed-Q hook.

This closes a specific correspondence gap: four windings, finite non-star
leakage, all secondary ports loaded, mixed delta orientations, explicit fourth-
winding excitation and active caps. It does not establish arbitrary-winding
coverage, movable-tap equivalence or a faster formulation. The next exact
reduction, now available in the [optional elimination study](ivr_nwinding_elimination.md),
removes multiwinding coil currents while
preserving their affine recovery, winding caps, excitation and delta circulation.
Singular leakage must retain a valid fallback; invertibility in this fixture
does not justify assuming it for every supported input.
