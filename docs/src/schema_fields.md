# Pinned schema field inventory

Property names below come from PowerIO’s BMOPF 0.2 proposal at revision
`8b1ad73af935fa5e15e055718cb6f5f7d6002217`, SHA-256
`74d6c6de3637d52e42a26c4cb0584f51df70d69f360b236cf5e23afaf7669462`.
This records the static AC boundary, not parser/schema conformance. The
[static equations](sdp_static.md) and [transformer contracts](sdp_transformers.md)
define arity, units, relaxation choices and fixed-setting restrictions.

This inventory describes the broad IVRSDP/IVRSOC static-AC contract.
`BranchFlowSDP` intentionally accepts only the subset listed in its
[radial prototype contract](branch_flow_sdp.md); dictionary fields appearing
below are not automatically supported by every formulation.

| Record | Accepted static fields | Excluded |
|---|---|---|
| `bus` | `terminal_names`, `perfectly_grounded_terminals`, `v_min`, `v_max`, `vn_max`, `vpn_min`, `vpn_max`, `vpp_min`, `vpp_max`, `vpos_min`, `vpos_max`, `vneg_max`, `vzero_max` | `time_series` |
| `line` | `length`, `linecode`, `terminal_map_to`, `terminal_map_from`, `bus_from`, `bus_to`, `i_max`, `s_max` | `time_series` |
| `voltage_source` | `v_magnitude`, `v_angle`, `terminal_map`, `bus`, `cost`, `p_min`, `p_max`, `energy_cost_rate` | `time_series` |
| `shunt` | `bus`, `terminal_map` | `time_series` |
| `capacitor` | `bus`, `terminal_map`, `configuration`, `q_rated`, `v_nom` | `time_series` |
| `load` | `p_nom`, `q_nom`, `bus`, `configuration`, `terminal_map`, `model`, `v_nom`, `alpha_z`, `alpha_i`, `alpha_p`, `beta_z`, `beta_i`, `beta_p`, `gamma_p`, `gamma_q` | `time_series` |
| `generator` | `p_min`, `p_max`, `q_min`, `q_max`, `s_max`, `i_max`, `cost`, `bus`, `configuration`, `terminal_map`, `energy_cost_rate` | `time_series` |
| `linecode` | `i_max`, `s_max`, `source`, `line_geometry`, `derivation` | `time_series` |
| `switch` | `bus_from`, `bus_to`, `terminal_map_to`, `terminal_map_from`, `open_switch`, `i_max` | `time_series` |
| `ibr` | `bus`, `terminal_map`, `topology`, `prime_mover`, `s_max`, `i_max`, `p_avail`, `p_min`, `p_max`, `dc_link_coupled`, `p_dc_min`, `p_dc_max`, `q_min`, `q_max`, `r_filter`, `x_filter`, `b_filter_shunt`, `grid_forming`, `v_ref_internal`, `cost`, `control_profile`, `voltage_aggregation`, `energy_cost_rate` | `dc_bus`, `dc_terminal_map`, `dc_control`, `dc_v_set`, `dc_p_ref`, `dc_droop`, `dc_deadband`, `time_series` |
| `single_phase_or_center_tap_transformer` | `s_rating`, `r_series_from`, `x_series_from`, `r_series_to`, `x_series_to`, `bus_from`, `bus_to`, `terminal_map_to`, `terminal_map_from`, `v_nom_to`, `v_nom_from`, `i_max_from`, `i_max_to`, `tap_ratio`, `tap_ratio_min`, `tap_ratio_max`, `r_neutral_from`, `x_neutral_from`, `r_neutral_to`, `x_neutral_to`, `g_no_load`, `b_no_load`, `no_load_shunt` | `time_series` |
| `three_phase_transformer` | `s_rating`, `r_series`, `x_series`, `i_max_from`, `i_max_to`, `bus_from`, `bus_to`, `terminal_map_to`, `terminal_map_from`, `v_nom_to`, `v_nom_from`, `tap_ratio`, `tap_ratio_min`, `tap_ratio_max`, `r_neutral_from`, `x_neutral_from`, `r_neutral_to`, `x_neutral_to`, `g_no_load`, `b_no_load`, `no_load_shunt` | `time_series` |
| `single_phase_autotransformer` | `s_rating`, `r_series_from`, `x_series_from`, `r_series_to`, `x_series_to`, `g_no_load`, `b_no_load`, `bus_from`, `bus_to`, `terminal_map_to`, `terminal_map_from`, `tap_ratio`, `tap_ratio_min`, `tap_ratio_max`, `regulator_type`, `i_max_from`, `i_max_to`, `no_load_shunt` | `time_series` |
| `open_delta_regulator` | `s_rating`, `r_series_from`, `x_series_from`, `r_series_to`, `x_series_to`, `g_no_load`, `b_no_load`, `bus_from`, `bus_to`, `terminal_map_to`, `terminal_map_from`, `connection`, `tap_ratio`, `tap_ratio_min`, `tap_ratio_max`, `regulator_type`, `i_max_from`, `i_max_to`, `no_load_shunt` | `time_series` |
| `n_winding_transformer` | `windings`, `x_sc`, `s_rating`, `g_no_load`, `b_no_load`, `no_load_shunt` | `time_series` |
| `transformer_winding` | `bus`, `terminal_map`, `v_nom`, `configuration`, `r_winding`, `delta_roll`, `i_max`, `s_rating`, `tap_ratio`, `tap_ratio_min`, `tap_ratio_max`, `r_neutral`, `x_neutral` | — |
| `transformer_no_load_shunt` | `winding`, `g`, `b` | — |

Matrix-pattern fields are also supported: line/linecode `R_series_i_j`,
`X_series_i_j`, `G_from_i_j`, `B_from_i_j`, `G_to_i_j`, `B_to_i_j`, and shunt
`G_i_j`, `B_i_j`. Referenced linecodes must supply electrical coefficients.

## Metadata and interpretation

- `name`, `meta`, `extras` and adapter `_meta` are descriptive metadata.
- `terminal_conventions.phase/neutral` determine sequence/neutral maps; `earth`
  is descriptive. Explicit bus grounding determines ideal earth connections.
- Linecode `source`, `line_geometry`, `derivation` and root `wire_data` /
  `line_geometry` are retained provenance; no geometry compiler is run.
- IBR `prime_mover` is descriptive. `control_profile` and `voltage_aggregation`
  generate no control constraints; referenced profiles appear in `omitted_controls`.
  No root control-profile fields execute Volt-VAr, Volt-Watt or power-factor laws.
- `dc_link_coupled` with `p_dc_min/max` is an internal active-power budget.
- Taps are fixed values or equal bounds. General multiwinding `s_rating` is base
  metadata; the six two-bus types retain their documented nameplate limits.
- Nonlinear load laws use the documented envelopes, reported in `load_envelopes`.

## Excluded tables and dictionary extensions

Nonempty `dc_bus`, `dc_branch`, `dc_grounding`, `dc_load`, `dc_source` and
`time_series` tables are rejected. Component time-series references must be
resolved upstream. External IBR DC terminals and DC control fields are rejected.

Dictionary construction also accepts compatibility fields beyond this schema:
bus `neutral_terminal` and full-terminal voltage arrays; inline line coefficients;
switch `s_max`; source Q/apparent/current bounds and connection metadata;
transformer `tap*` aliases and split Yd/Dy leakage; and multiwinding single-phase
connections and coil `s_max`. These are implementation extensions, not a claim
that PowerIO validates or round-trips them. Unknown electrical fields are refused.
