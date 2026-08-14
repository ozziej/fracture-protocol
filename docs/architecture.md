# Fracture Protocol architecture

## Runtime boundaries

`RtsSimulation` is the deterministic match façade. It owns serialisable match
state, the fixed simulation tick, commands, validation, combat resolution,
economy, supply, and event emission. Presentation code must never mutate that
state directly.

The simulation delegates isolated responsibilities to collaborators:

- `simulation/rts_definition_catalog.gd` creates runtime unit, building, and
  technology definitions.
- `simulation/rts_navigation_service.gd` is a stateless geometry service for
  obstacle-aware routes.
- `simulation/rts_ai_controller.gd` is an enemy policy that can only use the
  same public commands as the player; it has no hidden resource or combat path.
- `simulation/rts_ai_profile.gd` resolves authored difficulty profiles and
  mission intents into a small policy contract. Difficulty changes timing,
  force thresholds, queue reservations, and risk tolerance; it never changes
  the shared economy or combat definitions.
- `simulation/rts_force_capacity.gd` is a stateless force-accounting service;
  unit slot weights and queued reservations are evaluated consistently.
- `simulation/rts_formation_layout.gd` owns deterministic group and persistent
  rally-slot geometry, so player and AI production use the same serialisable
  spread instead of presentation-only offsets.
- Queue and patrol orders remain serialisable unit state, with direct Move, Attack, Stop, and Collector commands explicitly clearing stale route plans.
- Mission changes reload the selected simulation definition and rebuild the presentation world shell and minimap bounds from authored level data, keeping map geometry aligned with simulation state.
- Control-point roles, income, capture resistance, and supply-link bonuses are
  authored in `data/level_data.json`. The logistics service applies those roles
  to territory, supply, and forward rally behavior. Unit repair is instead
  owned by completed player Command Hubs and Assembly Bays, each of which
  exposes a visible repair influence radius; the HUD renders that state from
  the simulation snapshot.
- Resource reserves, depletion state, and map-specific AI tactics are authored
  in `data/level_data.json`. The simulation owns depletion and adaptive posture
  transitions; the presentation layer only renders field inspection, player
  intel, and the start-menu deployment flow.
- `simulation/rts_scenario_system.gd` owns optional data-driven skirmish
  objectives. Scenario definitions live in `data/skirmish_data.json`; the
  service reads simulation-owned control-point staging state, advances fixed
  tick progress, and emits progress/result events. It does not decide the
  authoritative `match_over` transition, so HQ destruction and scenario
  completion still pass through `RtsSimulation`.

`main.gd` remains the Godot scene entry point and input composition root. It
contains only player input, selection, camera state, campaign flow, and the
HUD-specific choices required to turn player intent into simulation commands.
It delegates non-interactive presentation work to:

- `presentation/rts_world_builder.gd` for lights, camera creation, terrain,
  roads, obstacles, and authored terrain accents.
- presentation/rts_terrain_decorator.gd composes a small number of readable
  Space Kit mesas, outposts, debris fields, and deterministic vegetation zones.
  Modular terrain pieces are repeated at near-uniform scale rather than
  stretched to obstacle footprints. It changes presentation only; simulation
  obstacle rectangles remain the pathing authority.
- `presentation/rts_world_view_synchronizer.gd` for simulation snapshots to
  unit, building, resource, control-point, and minimap views.
- `presentation/rts_resource_view.gd` for depletion-aware crystal clusters,
  resource labels, and resource selection feedback.
- `presentation/rts_combat_effects.gd` for event-driven tracers, missiles,
  impact feedback, and destruction feedback.
- `presentation/rts_asset_library.gd` for the presentation-only mapping from
  simulation kinds to the Kenney-based GLB exports. Unit and building views
  retain their procedural geometry as a fallback, so an art import failure
  cannot remove gameplay UI or simulation state.
- `presentation/rts_billboard_helper.gd` for camera-aligned world-space status
  UI shared by units and buildings, preventing parent rotation or mirrored
  back faces from affecting health, cargo, and name readability.

## Art pipeline

The current visual slice uses only the imported Kenney Space Kit. Blender
kitbashes the supplied pieces into role-readable units, buildings, resource
clusters, and scenery, applies the Fracture Protocol material palette, and exports runtime GLBs under
`art/fracture_protocol_assets/`. The source scene and the exact component
choices are recorded in `data/art_asset_manifest.json`; the source pack is
CC0 and may be replaced or extended without changing simulation definitions.

The Blender pipeline preserves the original Kenney face-to-material indices
and its white, orange, grey, stone, and crystal colours. Team colour is
deliberately reserved for a small presentation marker, world-space labels, and
thin selection/staging rings. Authored scenery is tagged by the world builder
and hidden while its visibility-grid cell remains undiscovered. Movement facing comes from measured
simulation displacement in `rts_unit_view.gd`, so pursuit, retreat, harvesting,
and explicit movement all use the same presentation rule. Health, cargo, and
name UI live in top-level camera-facing roots, independent of chassis rotation.
Legacy navigation rectangles are now presented as fog-aware authored mesa
prefabs, outpost, debris, and industrial clusters. Map floors use the Kenney
terrain tile rather than a stretched procedural box, while authored roads use
the matching straight, cross, end, and corner road GLBs. The mesa prefabs are
assembled in Blender from aligned Space Kit cliff/corner/ramp modules and
reused for sparse map-boundary landforms and authored walkable platforms.
Walkable platforms retain their authored height, vary only their X/Z footprint,
and raise unit presentation views while simulation movement remains 2D. Rocks,
obstacles, and border mesas receive matching presentation collision bodies;
blocking authored rocks are also included in simulation navigation footprints.
Both maps use selective infrastructure and deterministic vegetation from the
imported Kenney nature set. The asset library keeps the full kit available, but
a map uses only the pieces needed for a coherent composition; it is not an asset
showcase.

New art should follow this boundary:

1. assemble or modify a source asset in Blender;
2. export a self-contained GLB into the runtime asset directory;
3. register its simulation-kind mapping in `rts_asset_library.gd` and its
   source parts in the manifest;
4. keep selection, health, cargo, construction, and faction tint overlays in
   Godot presentation views rather than baking gameplay state into the model.

## Dependency direction

```text
input + HUD -> main -> RtsSimulation -> simulation services
                         |
                         +-> simulation_event -> presentation services -> Godot nodes
```

Simulation services receive only the simulation façade needed for their policy
or use pure arguments. Presentation services receive snapshots and event
payloads; they never issue or alter match commands.

## Deployment and skirmish flow

`RtsSimulation.start_match()` retains its existing two-argument contract and
accepts an optional third `match_settings` dictionary for new deployment
types. Empty or legacy calls create campaign matches; explicit skirmish
settings select the authored map, scenario, AI difficulty, and AI intent.
`restart_match()` reuses the selected settings so Rematch is deterministic.

`main.gd` presents Campaign and Skirmish deployment tabs. Campaign buttons
continue to use `CampaignProgress`, while skirmish deployment is deliberately
stateless with respect to campaign saves. Map and scenario choices come from
the simulation catalog, and AI difficulty/intent are passed into the existing
AI profile/controller boundary rather than being special-cased in the UI.

The skirmish catalog includes `network_hold` and `network_sever`. `network_hold`
requires each side to own and maintain its authored connected relay chain for
900 fixed ticks (90 seconds); losing a required point resets that side's hold
progress. `network_sever` is asymmetric: the player builds a connected Central
Relay + East Network chain, accumulates 900 online ticks without losing prior
progress, and must recover within 150 continuous offline ticks after the chain
has first armed. Its AI intent targets Central Relay using the normal staging,
capture, production, and combat rules. The normal Command Hub victory
condition remains active in parallel, so either skirmish can still end
immediately through HQ destruction.

Scenario state is included in the simulation snapshot for HUD and replay/test
consumers. Objective markers are represented as an array of point IDs so the
world view and minimap can highlight every required site. The tactical HUD
uses high-contrast objective rings, proximity markers, and a blocking mission
briefing modal at deployment so the player receives the objective before the
simulation starts. Combat readability follows the same presentation boundary:
launcher volleys emit source/target threat events, damage events carry attacker
and splash metadata, and selected combat units render their effective range
(including the Bulwark minimum-range dead zone). Units and structures retain a
short-lived under-fire state so the world view and HUD can tell the player when
to spread out, flank, retreat to repair, or reinforce from production. Match
result UI is event-driven and offers Rematch or Return to Deployment; neither
action grants or removes campaign progress.

## Extension rules

- Add a new unit/building/technology definition to the definition catalogue
  (and later its authored data source), not to command-processing methods.
- Add new deterministic rules as a focused simulation service when they have a
  distinct lifecycle, such as projectiles, territory/supply, or production.
- Add visual effects as simulation events plus a presentation listener; do not
  calculate damage in a visual node.
- Keep placement previews and build acceptance on the same simulation query so
  a red invalid preview cannot become an accepted or silently discarded build.
- Keep `RtsSimulation` public methods stable when moving internal work. Tests,
  campaigns, replays, and future multiplayer integrations use it as the
  compatibility boundary.
- Keep scenario definitions data-driven. A new skirmish objective should add a
  catalog entry plus a focused scenario-system rule, then expose only stable
  snapshot state and events to presentation.
- Keep campaign persistence scoped to campaign `MatchWon` events. Local
  skirmishes may reuse maps, units, and AI policies, but must not unlock or
  complete campaign missions.
