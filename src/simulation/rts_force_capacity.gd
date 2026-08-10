class_name RtsForceCapacity
extends RefCounted

## Stateless force accounting. A unit definition declares its slot weight;
## this service applies that weight consistently to active units and queued jobs.

static func capacity(level_rules: Dictionary) -> int:
	return max(1, int(level_rules.get("max_units_total", 9999)))


static func slots_for_kind(unit_definitions: Dictionary, kind: String) -> int:
	if not unit_definitions.has(kind):
		return 1
	return max(1, int(unit_definitions[kind].force_slots))


static func occupied(unit_definitions: Dictionary, units: Dictionary, buildings: Dictionary, team: String, include_queued: bool = true, kind: String = "") -> int:
	var force := 0
	for entity_id in units:
		var unit: Dictionary = units[entity_id]
		if unit["team"] == team and (kind.is_empty() or unit["kind"] == kind):
			force += slots_for_kind(unit_definitions, str(unit["kind"]))
	if include_queued:
		for building_id in buildings:
			var building: Dictionary = buildings[building_id]
			if building["team"] != team:
				continue
			for job in building.get("queue", []):
				var job_kind := str(job.get("unit_type", ""))
				if kind.is_empty() or job_kind == kind:
					force += slots_for_kind(unit_definitions, job_kind)
	return force


static func queue_limit_reason(unit_definitions: Dictionary, units: Dictionary, buildings: Dictionary, level_rules: Dictionary, team: String, kind: String) -> String:
	var occupied_force: int = occupied(unit_definitions, units, buildings, team)
	var required_force: int = slots_for_kind(unit_definitions, kind)
	var force_capacity: int = capacity(level_rules)
	if occupied_force + required_force > force_capacity:
		return "Force capacity reached (%d/%d); %s requires %d force." % [occupied_force, force_capacity, unit_definitions[kind].display_name, required_force]
	return ""
