# Literature and formulation lineage

This page maps published ideas to FormulationLab's implementations. It is not a
claim that the package reproduces every assumption or exactness theorem in the
cited work. Component coverage, explicit neutrals, finite bounds, topology,
objective choice and optional strengthening can all change the mathematical
problem.

## Unbalanced power flow and common notation

Geth and Ergun,
[*Real-Value Power-Voltage Formulations of, and Bounds for, Three-Wire
Unbalanced Optimal Power Flow*](https://arxiv.org/abs/2106.06186), give a
tutorial derivation of nonlinear and lifted BIM/BFM models with full pi-section
matrices and explicit voltage, current, power and angle bounds. The shared
[notation](notation.md) follows that paper's ``U/I/S/W/L`` vocabulary while
extending it to arbitrary terminal sets, neutrals, connection maps, parallel
branches and implementation result contracts.

The paper is a conceptual reference rather than the package specification. In
particular, FormulationLab's `IVRSDP` lifts an eliminated current--voltage state,
and `BranchFlowSDP` adds matrix KCL, device-local connection moments and
conditional voltage closure beyond the paper's three-wire radial BFM summary.

## SDP formulations of multiphase OPF

- Lavaei and Low,
  [*Zero Duality Gap in Optimal Power Flow
  Problem*](https://doi.org/10.1109/TPWRS.2011.2160974), is a foundational
  transmission-level OPF SDP reference. Its recovery and exactness conditions
  are not general guarantees for the unbalanced component models here.
- Dall'Anese, Giannakis and Wollenberg,
  [*Optimization of Unbalanced Power Distribution Networks via Semidefinite
  Relaxation*](https://doi.org/10.1109/NAPS.2012.6336350), is an early
  unbalanced bus-injection SDP reference.
- Gan and Low,
  [*Convex Relaxations and Linear Approximation for Optimal Power Flow in
  Multiphase Radial Networks*](https://arxiv.org/abs/1406.3054), place
  multiphase BIM and BFM SDP relaxations in a common radial-network framework.
- Farivar and Low,
  [*Branch Flow Model: Relaxations and Convexification*](https://doi.org/10.1109/CDC.2012.6425870),
  develop the balanced branch-flow angle and conic-relaxation viewpoint. Its
  exactness statements have specific assumptions and do not automatically
  transfer to unbalanced networks with full mutual coupling, finite bounds and
  general devices.
- Geth and Ergun's tutorial above derives real embeddings and bound semantics
  for both unbalanced BIM and BFM lifted variables. It is the nearest notation
  reference for the side-by-side presentation in these docs.
- Geth, Claeys and Deconinck,
  [*Nonconvex Lifted Unbalanced Branch Flow Model: Derivation, Implementation
  and Experiments*](https://doi.org/10.1016/j.epsr.2020.106558), derives the
  rank-constrained unbalanced BFM relationships underlying the line equations.
- Vanin, Ergun, D'hulst and Van Hertem,
  [*Comparison of Linear and Conic Power Flow Formulations for Unbalanced Low
  Voltage Network Optimization*](https://doi.org/10.1016/j.epsr.2020.106699),
  provide empirical context for comparing nonlinear, conic and linear models;
  those results are evidence for their data and implementations, not package
  benchmarks.

`IVRSDP` should not be labeled a direct implementation of any one of these BIM
or BFM models. It retains component currents, eliminates the homogeneous
electrical equations, and lifts the reduced state. `BranchFlowSDP` is closer to
the classic multiphase BFM line block, but its connection and topology closure
machinery is implementation-specific.

## Connections, transformers and nonlinear loads

- Zhao, Dall'Anese and Low,
  [*Convex Relaxation of OPF in Multiphase Radial Networks with Wye and Delta
  Connections*](https://www.nrel.gov/docs/fy17osti/68859.pdf), motivate explicit
  delta connection variables in multiphase SDP models. FormulationLab likewise
  keeps coil currents and never replaces a delta device by a nominal wye
  allocation.
- Claeys, Deconinck and Geth,
  [*Decomposition of n-Winding Transformers for Unbalanced Optimal Power
  Flow*](https://doi.org/10.1049/iet-gtd.2020.0776), provide the component
  decomposition and winding conventions behind the general fixed transformer
  support. The package retains the coupled winding equations directly in its
  IVR and component-local moment states.
- Bazrafshan, Gatsis and Zhu,
  [*Optimal Power Flow with Step-Voltage Regulators in Multi-Phase
  Distribution Networks*](https://arxiv.org/abs/1901.04566), provide regulator
  connection-matrix context. FormulationLab currently fixes taps; it does not
  reproduce their discrete tap-selection problem.
- Claeys, Deconinck and Geth,
  [*Voltage-Dependent Load Models in Unbalanced Optimal Power Flow Using Power
  Cones*](https://doi.org/10.1109/TSG.2021.3052576), is the basis for the
  connection-aware ZIP and exponential load envelopes. These power-cone
  envelopes are an additional relaxation beyond moment-rank relaxation.
- Claeys, Geth and Deconinck,
  [*Optimal Power Flow in Four-Wire Distribution Networks: Formulation and
  Benchmarking*](https://arxiv.org/abs/2204.08126), gives the relevant
  explicit-neutral IVR modeling background.

## Bounds and physical limit semantics

Bounds must be attached to a physical voltage, current or power map. Geth and
Liu,
[*Notes on BIM and BFM Optimal Power Flow With Parallel Lines and Total Current
Limits*](https://doi.org/10.1109/PESGM48719.2022.9917005), show why parallel
branches and total endpoint currents require care, especially when a BIM has
eliminated branch-current variables. FormulationLab preserves a branch identity
``\ell`` and distinguishes series current from endpoint current including
shunts. `BranchFlowSDP` carries these products directly; `IVRSDP` evaluates the
same physical maps in its reduced moment matrix.

Jabr,
[*A Conic Quadratic Format for the Load Flow Equations of Meshed
Networks*](https://doi.org/10.1109/TPWRS.2007.907590), is the standard reference
for tangent-style voltage-angle constraints in lifted voltage products. The
package applies angle and magnitude bounds only when the corresponding physical
voltage maps and finite domains are available.

## Sparsity and conic representations

- Grone, Johnson, Sá and Wolkowicz,
  [*Positive Definite Completions of Partial Hermitian
  Matrices*](https://doi.org/10.1016/0024-3795(84)90207-6), provide the chordal
  PSD-completion foundation. Chordal splitting is equivalent only when the
  required clique overlaps are consistent.
- Liu, Li, Wu and Ortmeyer,
  [*Chordal Relaxation Based ACOPF for Unbalanced Distribution Systems with
  DERs and Voltage Regulation Devices*](https://doi.org/10.1109/TPWRS.2017.2707564),
  and Gan and Low,
  [*Chordal Relaxation of OPF for Multiphase Radial
  Networks*](https://doi.org/10.1109/ISCAS.2014.6865509), apply sparse PSD ideas
  to unbalanced/multiphase OPF.
- Kim, Kojima and Yamashita,
  [*Second Order Cone Programming Relaxation of a Positive Semidefinite
  Constraint*](https://doi.org/10.1080/1055678031000148696), provide the basic
  finite SOC relaxation of PSD constraints.
- Geth and Foster,
  [*Improving Optimal Power Flow Relaxations Using 3-Cycle Second-Order Cone
  Constraints*](https://arxiv.org/abs/2104.06695), motivate the optional fixed
  complex three-map projections in `IVRSOC`.
- Fawzi,
  [*On Representing the Positive Semidefinite Cone Using the Second-Order
  Cone*](https://arxiv.org/abs/1610.04901), explains why a finite general SOC
  representation should not be described as full SDP equivalence.

## Strengthening and recovery

Coffrin, Hijazi and Van Hentenryck,
[*Strengthening the SDP Relaxation of AC Power Flows with Convex Envelopes,
Bound Tightening, and Lifted Nonlinear Cuts*](https://arxiv.org/abs/1512.04644),
is the main reference for the optional voltage-product LNCs. FormulationLab
applies their scalar geometry to declared physical voltage maps; it does not
infer domains from an incumbent solution.

Geth and Coffrin,
[*Direct Method to Recover Current and Voltage in Multi-Conductor Optimal Power
Flow Models*](https://ieeexplore.ieee.org/document/8973923), motivate direct
phasor recovery from multiconductor product matrices. Recovery in this package
is deliberately reported as a candidate plus residual diagnostics, never as an
automatic AC-feasibility certificate.

## Linear approximation and software context

Sankur, Dobbe, Stewart, Callaway and Arnold,
[*A Linearized Power Flow Model for Optimization in Unbalanced Distribution
Systems*](https://arxiv.org/abs/1606.04492), provide the fixed voltage-ratio
multiphase linearization lineage for `LinDist3Flow`. The implementation and
regression fixtures were migrated from PowerOptLab and have a broader
component-lowering contract documented separately.

PowerModelsDistribution.jl is described by Fobes, Coffrin, Geth and Claeys,
[*PowerModelsDistribution.jl: An Open-Source Framework for Exploring
Distribution Power Flow Formulations*](https://doi.org/10.1016/j.epsr.2020.106664).
It is a useful formulation and implementation reference; FormulationLab does
not depend on it at runtime. JuMP's complex-variable and conic modeling context
is described by Lubin *et al.*,
[*JuMP 1.0: Recent Improvements to a Modeling Language for Mathematical
Optimization*](https://doi.org/10.1007/s12532-023-00239-3).

The default open-source conic backend is described by Goulart and Chen,
[*Clarabel: An Interior-Point Solver for Conic Programs with Quadratic
Objectives*](https://arxiv.org/abs/2405.12762). Formulation-specific scaling,
regularization and stopping tolerances remain package choices rather than
properties inherited from the solver paper.

## How to cite implementation-specific claims

Published papers establish the cited mathematical ideas under their own
assumptions. Package-specific claims—component coverage, terminal ordering,
diagnostics, benchmark outcomes and solver profiles—should instead cite the
relevant FormulationLab version or commit and its test/benchmark artifacts.
See [verification](verification.md), [AC containment](ac_validation.md), and
[migration provenance](migration.md).
