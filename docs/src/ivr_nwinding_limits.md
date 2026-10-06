# Multiwinding power-limit units

A scalar winding `s_max` has different meanings in the original native
FormulationLab contract and the inspected BMOPFTools implementation. The native
contract broadcasts the scalar to every coil. BMOPFTools treats it as a total
winding VA rating and divides it by the coil count. On a three-phase winding,
the per-coil caps consequently differ by a factor of three. This is a physical
feasible-set difference, not per-unit scaling or an exact reformulation.

## Explicit policy and equations

For winding ``k``, let ``u_{k,c}`` and ``j_{k,c}`` denote native coil voltage and
series-coil current, and ``m_k`` its number of coils. Exact IVR enforces

```math
|u_{k,c}\overline{j_{k,c}}|\le \overline S_{k,c},\qquad
\overline S_{k,c}=\begin{cases}
S_k/m_k,&\text{scalar }S_k\text{ and policy :bmopftools},\\
S_k,&\text{scalar }S_k\text{ and policy :ignore},\\
S_{k,c},&\text{explicit vector, either policy}.
\end{cases}
```

Select `transformer_nameplate=:bmopftools` to obtain the scalar winding-total
interpretation. The default `:ignore` preserves the original per-coil contract;
it does **not** ignore explicit winding limits. Vectors remain an explicit
per-coil dictionary extension, including unequal values. `i_max` remains a
per-coil ampere cap. Missing `s_max` adds no constraint; zero imposes zero coil
power. Negative, nonfinite and wrong-length declarations are rejected.
Transformer and winding `s_rating` remain metadata for general multiwinding
models. Ordinary-transformer `s_rating` retains its separately documented
[rated-port policy](ivr_nlp.md#Explicit-transformer-nameplate-policy).

The equal per-coil shares are not an aggregate apparent-power cap: unused
capacity on one phase does not increase another phase's allowance. Neither
nominal-voltage current proxies nor terminal currents containing excitation
replace the physical series-coil products. The applied limits enter the common
bound ledger before numerical coordinate maps and lifting, so every retained
exact-IVR representation uses the same selected physical caps.

Build diagnostics expose `:nwinding_power_limit_report`, with transformer ID,
winding index, coil count, interpretation, `:series_coil` basis and `limits_VA`.
The SI result extension copies this report. Ordinary BMOPFTools-shaped winding
records export `s=abs(u*conj(j))` and the applied **per-coil** `s_max`, independently
of formulation and assembly power base. The independent SI auditor implements
the division separately. Auditing a result uses its recorded policy; auditing
an `ACPoint` requires an explicit policy argument.

Before this correction, `:bmopftools` also broadcast scalar multiwinding limits.
To reproduce that earlier feasible set while retaining ordinary-transformer
nameplate enforcement, represent the old scalar ``S_k`` as the explicit vector
`fill(S_k, m_k)`. Record this input conversion separately from the original data.
Using `:ignore` alone would also disable ordinary-transformer nameplates, so it
is not an equivalent migration for a mixed network. New winding-total inputs
should retain their scalar representation under `:bmopftools`.

## Analytical dispatch and rejection witnesses

A lossless three-winding circuit uses unequal native coil voltages 230, 115 and
57.5 V and grounded wye neutrals. The second winding supplies independent phase
demands of 200, 160 and 120 W; local generation is limited to 0–300 W per phase
and is priced positively, while source supply is free. The third winding is
unloaded. With scalar `s_max=300 VA`, the native policy requires no generation.
The winding-total policy gives 100 VA per coil and requires
``(100,60,20)\,\mathrm W`` of generation, **180 W total**. The
[executable tutorial](tutorial_exact_ivr.md#55.-Reconcile-scalar-multiwinding-power-ratings)
constructs and solves both problems explicitly.

The native test suite checks one/three phases, forward/reverse power, both
policies, 1/100 kVA assembly bases and off/power/bounded-observation lifting.
It composes nominal transformer coordinates, conductor specialization,
passive-block reduction and the retained transformer-current elimination option
(multiwinding currents themselves remain explicit). An equivalent explicit
vector admits the same point. Exported caps, generation, coil powers and SI
JSON round trips are checked against the analytical answer. Lowering the cap
rejects each solved point in both model membership and independent physical
validation.

A separate manufactured four-winding circuit has non-star leakage coupling,
unequal fixed taps, mixed wye/delta connections and excitation on a declared
winding. Independent SI coil products determine permissive scalar limits; each
winding is then tightened separately. Both policies and all lifting choices
reject the violating point. Unequal explicit vectors are tested coil by coil;
zero/absent bounds and invalid declarations have separate checks. No
manufactured witness uses the compiler's winding-plan or limit helper to
calculate its expected power cap.

## Live BMOPFTools comparison

`test/integration/ivr_nwinding_limits_reference.jl` runs against the local
BMOPFTools checkout at revision
`a8b52e069bfd4a7a57434c91bc0470ac03cfdd55`, with the relevant source hashes
recorded in the external evidence. It is an optional integration dependency,
not a runtime dependency or fallback implementation.

The live panel has 16 reference solves and 48 FormulationLab comparisons:
one/three phases, forward/reverse flow, active/absent scalar caps, 1/100 kVA
power bases and three lifting modes. All reference solves use **per-unit mode**.
Both solvers use strict `1e-10` feasibility/optimality settings, zero acceptable
iterations and zero bound relaxation. The analytical dispatch, native per-kW
cost, matching winding export fields and physical values agree. BMOPFTools'
JSON reader round-trips each FormulationLab export.
The live suite passes **1552 assertions**; the native targeted suite passes
**974 assertions**.

This closes scalar bound-unit parity for the declared live panel. It does not
establish full multiwinding device-law equivalence. In particular, the live
cases have zero excitation and unit taps; non-star leakage, delta connections,
non-unit taps and explicit excitation placement are covered by independent
native witnesses, not by these live comparisons. BMOPFTools' inspected input
path accepts scalar winding limits; explicit vectors remain a native extension.
Shared SDP/SOC assembly retains the original per-coil contract. Compare feasible
sets only after aligning the selected limit policy or supplying explicit
per-coil vectors. Earlier French timing cases contain ordinary transformers,
so this correction changes none of their inputs or recorded timing evidence.

## Reproduction and evidence

Run the native tests through `test/runtests.jl`, or include
`test/ivr_nwinding_limit_tests.jl` in the test environment. Run the live script
with `--project=test/integration`, optionally passing a JSON report path. Reports
record reference revision, dirty state, source hashes, case factors and objective
agreement. Raw logs and reference/source snapshots are in the outside-Git
`NWINDING_LIMITS_20261006` archive. Early test-fixture syntax, phase-cost arity
and W-versus-kW oracle mistakes are retained in separate logs; no physical or
solver acceptance condition was relaxed to obtain agreement.

This is a correctness checkpoint. It makes no timing or global-optimality claim;
all transformation options and the original scalar interpretation remain
available.
