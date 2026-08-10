class_name RtsAiProfile
extends RefCounted

## Resolves authored AI policy data into a small, stable runtime profile.
## Difficulty changes execution choices only; it never grants hidden credits,
## units, damage, or production discounts.

const FALLBACK_PROFILES := {
	"standard": {
		"display_name": "Standard",
		"decision_interval_seconds": 2.0,
		"opening_attack_delay_multiplier": 1.0,
		"minimum_attack_group_size_delta": 0,
		"production_queue_target": 2,
		"capture_group_size": 3,
		"repair_health_ratio": 0.45,
		"retreat_health_ratio": 0.45,
		"attack_reissue_ticks": 60,
	},
	"aggressive": {
		"display_name": "Aggressive",
		"decision_interval_seconds": 1.5,
		"opening_attack_delay_multiplier": 0.7,
		"minimum_attack_group_size_delta": -1,
		"production_queue_target": 3,
		"capture_group_size": 2,
		"repair_health_ratio": 0.3,
		"retreat_health_ratio": 0.3,
		"attack_reissue_ticks": 45,
	},
	"defensive": {
		"display_name": "Defensive",
		"decision_interval_seconds": 2.5,
		"opening_attack_delay_multiplier": 1.35,
		"minimum_attack_group_size_delta": 1,
		"production_queue_target": 2,
		"capture_group_size": 4,
		"repair_health_ratio": 0.6,
		"retreat_health_ratio": 0.6,
		"attack_reissue_ticks": 75,
	},
}


static func resolve(level_definition: Dictionary, requested_difficulty := "") -> Dictionary:
	var ai_config: Dictionary = level_definition.get("ai", {})
	var authored_profiles: Dictionary = level_definition.get("ai_profiles", {})
	var authored_default := str(ai_config.get("difficulty", "standard"))
	var difficulty_id := str(requested_difficulty) if not str(requested_difficulty).is_empty() else authored_default
	if not FALLBACK_PROFILES.has(difficulty_id) and not authored_profiles.has(difficulty_id):
		difficulty_id = "standard"

	var profile: Dictionary = FALLBACK_PROFILES.get(difficulty_id, FALLBACK_PROFILES["standard"]).duplicate(true)
	if authored_profiles.has(difficulty_id):
		var authored_profile: Dictionary = authored_profiles[difficulty_id]
		for key in authored_profile:
			profile[key] = authored_profile[key]
	profile["id"] = difficulty_id
	profile["display_name"] = str(profile.get("display_name", difficulty_id.capitalize()))

	return {
		"profile": profile,
		"difficulty": difficulty_id,
		"intent": str(ai_config.get("intent", "secure_then_assault")),
		"intent_display_name": str(ai_config.get("intent_display_name", "SECURE THEN ASSAULT")),
		"intent_message": str(ai_config.get("intent_message", "Secure the forward network, then assault the enemy command hub.")),
		"target_point_id": str(ai_config.get("staging_point_id", "")),
		"map_tactic_id": str(ai_config.get("map_tactic", "relay_first")),
		"map_tactic_display_name": str(ai_config.get("map_tactic_display_name", "RELAY FIRST")),
		"map_tactic_message": str(ai_config.get("map_tactic_message", "Secure the authored forward network before the main assault.")),
		"map_tactic_attack_delay_multiplier": float(ai_config.get("map_tactic_attack_delay_multiplier", 1.0)),
		"defensive_health_threshold": float(ai_config.get("defensive_health_threshold", 0.72)),
		"passive_delivery_threshold": int(ai_config.get("passive_delivery_threshold", 1)),
		"passive_window_ticks": int(ai_config.get("passive_window_ticks", 360)),
		"posture_change_cooldown_ticks": int(ai_config.get("posture_change_cooldown_ticks", 120)),
		"proactive_attack_delay_ticks": int(ai_config.get("proactive_attack_delay_ticks", 0)),
	}
