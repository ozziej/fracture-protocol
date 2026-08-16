class_name RtsFactionCatalog
extends RefCounted

## Small, explicit faction profiles. Faction identity is deliberately visible
## in mission data and the HUD; these modifiers are bounded presentation of the
## authored doctrine, not hidden difficulty bonuses or extra income.

const PROFILES := {
	"coalition": {
		"id": "coalition",
		"display_name": "Coalition",
		"doctrine": "Fortified network",
		"summary": "Sensors, durable defensive infrastructure, and deliberate combined-arms pushes.",
		"strengths": ["sensor coverage", "fortified turrets", "armoured line vehicles"],
		"weaknesses": ["expensive specialist units", "slower recovery when links are cut"],
		"modifiers": {
			"sensor_mast": {"vision_range": 1.10},
			"bastion_turret": {"max_health": 1.10, "attack_damage": 1.05},
			"fire_support_battery": {"attack_range": 1.05}
		}
	},
	"frontier": {
		"id": "frontier",
		"display_name": "Frontier",
		"doctrine": "Mobile pressure",
		"summary": "Fast raiders and resilient field logistics turn captured ground into momentum.",
		"strengths": ["raider mobility", "collector recovery", "rapid pressure"],
		"weaknesses": ["lighter static defenses", "lower individual unit durability"],
		"modifiers": {
			"raider": {"speed": 1.08, "vision_range": 1.05},
			"collector": {"speed": 1.08},
			"relay": {"vision_range": 1.05}
		}
	}
}


static func profile(faction_id: String) -> Dictionary:
	var resolved_id := faction_id if PROFILES.has(faction_id) else "coalition"
	return PROFILES[resolved_id].duplicate(true)


static func modifier(faction_id: String, entity_kind: String, stat: String, fallback := 1.0) -> float:
	var faction := profile(faction_id)
	var modifiers: Dictionary = faction.get("modifiers", {})
	var entity_modifiers: Dictionary = modifiers.get(entity_kind, {})
	return float(entity_modifiers.get(stat, fallback))
