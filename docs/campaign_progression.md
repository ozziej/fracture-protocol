# Campaign progression and mission expansion

## Current campaign spine

The campaign is a linear six-mission first pass. Each mission teaches one new
strategic layer and grants a persistent reward on its first successful
completion.

| Tier | Mission | Focus | First-completion reward |
| --- | --- | --- | --- |
| 1 | Relay Divide — Foundation | Economy, basic construction, Ranger/Collector opening | Warden and Forward Relay |
| 2 | Relay Crossroads — Network Expansion | Territory, connected staging, research | Bulwark, Tech Centre, Advanced Targeting |
| 3 | Silent Recovery — Special Operations | Limited force, detection, recovery, exfiltration | Forward Base, Field Repair Station, Field Optics, Hardened Chassis |
| 4 | The Long Road — Fortified Advance | Convoy routing and forward deployment | Sensor Mast, Bastion Turret, Breach Package |
| 5 | Holdfast — Layered Defence | Economy-backed perimeter defence and escalating waves | Fire Support Battery |
| 6 | Network Sever — Counter-Offensive | Connected Central Relay capture and sustained hold | Campaign mastery; no further tier |

Mission metadata lives in `data/campaign_data.json`. Runtime maps, allowed
content, objectives, spawns, wave sets, and faction assignments live in
`data/level_data.json`.

## Persistent save contract

`src/campaign_progress.gd` owns campaign persistence. The default save is
`user://campaign_progress.json`; tests may provide an isolated absolute path.
The schema currently contains:

- `schema_version`: currently `2`.
- `completed`: mission IDs completed at least once.
- `unlocked`: mission IDs available from the deployment screen.
- `unlocked_content`: durable `units`, `buildings`, and `technologies` arrays.
- `flags`: completion flags emitted by authored missions.
- `results`: the most recent result payload per mission, including
  `rewards_granted` on the first completion.

A new save starts with only `ranger`, `collector`, `refinery`, `assembly_bay`,
and `storage_silo`. Loading an older save preserves its completed missions and
migrates missing `unlocked_content` from `initial_content`, then replays the
authored reward table once per completed mission. Rewards are deduplicated and
are not removed by replaying a completed mission.

The deployment UI reads the same reward table to show the next unlock before a
mission starts. On a successful `MatchWon`, the result receipt records the
reward payload and names the newly unlocked mission or content.

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
- Resource Processor: Collector production and income routing.

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

- `tests/campaign_progression_expansion_test.gd`: save/reload rewards, tier
  gates, faction modifiers, connected relay-chain capture, offline decay, and
  Network Sever completion.
- `tests/campaign_expansion_playtest.gd`: authored Silent Recovery, Long Road,
  and Holdfast flows.
- `tests/campaign_navigation_presentation_test.gd`: authored world corridors
  and industrial set-piece composition.
- `tests/visual_performance_smoke_test.gd`: repeated synchronization of 100
  added asset-backed unit views.

Music remains intentionally deferred until suitable tracks are supplied under
`res://audio/music`.
