# Campaign progression, doctrine, and mission expansion

## Current campaign spine

The campaign is a 20-mission linear arc. Missions 1–8 build and defend the
Coalition network. Network Sever grants one doctrine package. Missions 9–20
turn that network into a sustained push against the Frontier command grid.

| Missions | Story beat | Gameplay focus |
| --- | --- | --- |
| 1–2 | Establish the network | Economy, territory, relays, research |
| 3–5 | Move and hold the line | Recovery, convoy deployment, perimeter defence |
| 6–8 | Open the counter-offensive | Central Relay, doctrine choice, breakthrough |
| 9–11 | Restore and blind the grid | Relay recovery, supply pressure, signal raids |
| 12–15 | Build the forward line | Carrier deployment, artillery, linked crossings, convoy defence |
| 16–18 | Break the eastern command | Relay blackout, armoured gate, deep strike |
| 19–20 | Finish the war | Final relay hold, command-grid capture, Frontier HQ destruction |

Mission metadata lives in `data/campaign_data.json`. Runtime maps, allowed
content, objectives, spawns, wave sets, and faction assignments live in
`data/level_data.json`. Briefings and phase instructions use short sentences;
the deployment screen shows the current mission's brief and available units.

## Persistent save contract

`src/campaign_progress.gd` owns campaign persistence. The default save is
`user://campaign_progress.json`; tests may provide an isolated absolute path.
The schema currently contains:

- `schema_version`: currently `3`.
- `completed`: mission IDs completed at least once.
- `unlocked`: mission IDs available from the deployment screen.
- `unlocked_content`: durable `units`, `buildings`, and `technologies` arrays.
- `flags`: completion flags emitted by authored missions.
- `results`: the most recent result payload per mission, including
  `rewards_granted` on the first completion.
- `doctrine_unlocked`: whether Network Sever has awarded the doctrine choice.
- `doctrine_id`: the selected persistent package (`logistics`, `armoured`, or
  `recon`).
- `doctrine_history` and `doctrine_choices`: durable selection receipts.

A new save starts with only `ranger`, `collector`, `refinery`, `assembly_bay`,
and `storage_silo`. Loading an older save preserves its completed missions and
migrates missing `unlocked_content` from `initial_content`, then replays the
authored reward table once per completed mission. Rewards are deduplicated and
are not removed by replaying a completed mission.

The deployment UI reads the same reward table to show the next unlock before a
mission starts. After Network Sever, the player selects one package from the
deployment screen; the choice cannot be changed later in that campaign. On a
successful `MatchWon`, the result receipt records the reward payload and names
the newly unlocked mission or content.

## Doctrine packages

Doctrine effects are concrete opening advantages rather than an unbounded stack
of percentage bonuses:

- **Logistics Corps:** +250 opening credits, an additional Storage Silo, and a
  second Collector route.
- **Armoured Spearhead:** +100 opening credits and an additional Warden.
- **Recon Network:** an additional Sensor Mast and longer intervals between
  scripted assault waves.

The package is authored into the Counterstroke and Iron Front opening variants.
The selected package remains in the campaign record for later mission receipts;
later missions currently use their own authored forces and objectives.
The simulation applies the starting assets before campaign phases activate and
the campaign mission system applies the selected phase overrides. This keeps
the choice visible in the brief and authoritative in the fixed-step runtime.

Schema-2 saves migrate in place: completed missions keep their history,
follow-on unlocks are reconstructed, and a completed Network Sever grants the
new doctrine choice without requiring replay.

## Level gates and structure roles

Mission rules are authoritative for the current match. A persistent unlock
does not silently add every later structure to an earlier battlefield:
`allowed_player_units`, `allowed_player_buildings`, `allowed_technologies`, and
the corresponding enemy lists remain level-specific.

The production split is deliberate:

- Assembly Bay: combat-unit production and its fabrication upgrade.
- Command Hub / Forward Base: relays, sensors, Bastion Turrets, and other
  perimeter construction cards allowed by the mission.
- Tech Centre: research and artillery-support access where authored.
- Resource Processor: Collector production, income routing, and 2,000 storage capacity.
- Storage Silo: adds another 2,000 resources to the team storage network when complete.

This keeps the Assembly Bay visually and mechanically associated with vehicles
and other mobile forces instead of duplicating static defences from the main
base.

## Faction identity

`src/simulation/rts_faction_catalog.gd` is a small explicit profile layer, not
a second hidden balance system. The authored campaign assignments are:

- Coalition: `Fortified network`; Sensor Mast vision, Bastion durability/damage,
  and Fire Support range are modestly improved. Specialist forces remain
  expensive and deliberate.
- Frontier: `Mobile pressure`; Raiders gain speed/vision and Collectors gain
  mobility. Static defences are lighter, so the faction is expressed through
  movement and contesting rather than free income.

Faction IDs, profile summaries, and effective entity stats are included in the
simulation snapshot so the HUD, tests, and future replay consumers can explain
the difference.

## Network Sever objective

`network_hold` is a campaign-only phase type owned by
`RtsCampaignMissionSystem`:

1. The mission starts with an authored western relay chain, so the player can
   immediately contest the objective instead of spending the opening on a
   mandatory relay-construction chain.
2. The player captures every `target_ids` control point.
3. If `require_connected` is true, each target must also be an active connected
   staging point in the player's supply graph.
4. Each fixed simulation tick that the target is online adds one tick to
   `progress`.
5. Each offline tick subtracts `offline_decay_ticks`, clamped at zero.
6. Scripted counter-offensive waves are spawned on the authored delay and
   interval and attack the target point.
7. Reaching `duration_ticks` completes the mission through the normal
   `MatchWon` event path. The objective does not depend on destroying the enemy
   HQ because `ignore_hq_victory` is authored for this mission.

The HUD exposes `network_online`, `progress`, `target`, and the required point
IDs. World markers use the same snapshot, changing between `NETWORK ONLINE`
and `NETWORK CONTESTED` rather than relying on a presentation-only timer.

## Verification

Focused regression coverage includes:

- `tests/campaign_20_mission_catalog_test.gd`: exact 20-mission order, unlock
  chain, concise mission copy, authored phase types, and target resolution for
  every later operation.
- `tests/campaign_20_mission_runtime_test.gd`: forced phase transitions across
  all 18 authored campaign operations, including recovery, network hold,
  convoy, deployment, defence, and final command-hub objectives.
- `tests/campaign_progression_expansion_test.gd`: save/reload rewards, tier
  gates, faction modifiers, connected relay-chain capture, offline decay, and
  Network Sever completion.
- `tests/campaign_doctrine_progression_test.gd`: schema migration, one-time
  doctrine selection, persistent receipts, doctrine-specific opening assets,
  authored phase changes, and a forced Counterstroke completion path.
- `tests/campaign_expansion_playtest.gd`: authored Silent Recovery, Long Road,
  and Holdfast flows.
- `tests/campaign_navigation_presentation_test.gd`: authored world corridors
  and industrial set-piece composition.
- `tests/visual_performance_smoke_test.gd`: repeated synchronization of 100
  added asset-backed unit views.
- `tests/storage_capacity_test.gd`: Processor/Silo capacity, Collector stop and
  resume behavior, resource-cap enforcement, and AI Silo construction.

Music remains intentionally deferred until suitable tracks are supplied under
`res://audio/music`.
