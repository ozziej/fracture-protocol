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

`main.gd` remains the Godot scene entry point and input composition root. It
contains only player input, selection, camera state, campaign flow, and the
HUD-specific choices required to turn player intent into simulation commands.
It delegates non-interactive presentation work to:

- `presentation/rts_world_builder.gd` for lights, camera creation, terrain,
  roads, obstacles, and authored terrain accents.
- `presentation/rts_world_view_synchronizer.gd` for simulation snapshots to
  unit, building, resource, control-point, and minimap views.
- `presentation/rts_combat_effects.gd` for event-driven tracers, missiles,
  impact feedback, and destruction feedback.

## Dependency direction

```text
input + HUD -> main -> RtsSimulation -> simulation services
                         |
                         +-> simulation_event -> presentation services -> Godot nodes
```

Simulation services receive only the simulation façade needed for their policy
or use pure arguments. Presentation services receive snapshots and event
payloads; they never issue or alter match commands.

## Extension rules

- Add a new unit/building/technology definition to the definition catalogue
  (and later its authored data source), not to command-processing methods.
- Add new deterministic rules as a focused simulation service when they have a
  distinct lifecycle, such as projectiles, territory/supply, or production.
- Add visual effects as simulation events plus a presentation listener; do not
  calculate damage in a visual node.
- Keep `RtsSimulation` public methods stable when moving internal work. Tests,
  campaigns, replays, and future multiplayer integrations use it as the
  compatibility boundary.
