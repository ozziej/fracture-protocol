class_name RtsDefinitionCatalog
extends RefCounted

const UnitDefinitionScript = preload("res://src/unit_definition.gd")
const BuildingDefinitionScript = preload("res://src/building_definition.gd")
const TechnologyDefinitionScript = preload("res://src/technology_definition.gd")

## Authored runtime definitions belong in one catalogue instead of the match loop.
## This keeps simulation code focused on rules and makes a future data import
## replaceable without changing command or combat code.
static func populate(unit_definitions: Dictionary, building_definitions: Dictionary, technology_definitions: Dictionary) -> void:
	if not unit_definitions.is_empty() and not building_definitions.is_empty() and not technology_definitions.is_empty():
		return
	unit_definitions.clear()
	building_definitions.clear()
	technology_definitions.clear()

	var targeting = TechnologyDefinitionScript.new()
	targeting.id = "advanced_targeting"
	targeting.display_name = "Advanced Targeting"
	targeting.description = "Unlocks Bulwark production at the Assembly Bay."
	targeting.cost = 300
	targeting.research_time = 8.0
	technology_definitions[targeting.id] = targeting

	var ranger = UnitDefinitionScript.new()
	ranger.id = "ranger"
	ranger.display_name = "Ranger"
	ranger.role = "general infantry"
	ranger.cost = 80
	ranger.force_slots = 1
	ranger.build_time = 2.2
	ranger.max_health = 75.0
	ranger.speed = 6.0
	ranger.attack_range = 7.5
	ranger.attack_damage = 8.0
	ranger.attack_cooldown = 0.65
	ranger.armour = 0.0
	ranger.vision_range = 15.0
	ranger.body_scale = Vector3(0.72, 1.05, 0.72)
	unit_definitions[ranger.id] = ranger

	var warden = UnitDefinitionScript.new()
	warden.id = "warden"
	warden.display_name = "Warden"
	warden.role = "armoured line vehicle"
	warden.cost = 145
	warden.force_slots = 2
	warden.build_time = 4.2
	warden.max_health = 190.0
	warden.speed = 3.7
	warden.attack_range = 9.5
	warden.attack_damage = 36.0
	warden.attack_cooldown = 1.8
	warden.armour = 5.0
	warden.vision_range = 16.0
	warden.body_scale = Vector3(1.05, 0.75, 1.05)
	unit_definitions[warden.id] = warden

	var raider = UnitDefinitionScript.new()
	raider.id = "raider"
	raider.display_name = "Raider"
	raider.role = "fast attack vehicle"
	raider.cost = 105
	raider.force_slots = 1
	raider.build_time = 3.0
	raider.max_health = 125.0
	raider.speed = 6.4
	raider.attack_range = 8.5
	raider.attack_damage = 16.0
	raider.attack_cooldown = 0.75
	raider.vision_range = 17.0
	raider.body_scale = Vector3(1.25, 0.65, 0.9)
	unit_definitions[raider.id] = raider

	var bulwark = UnitDefinitionScript.new()
	bulwark.id = "bulwark"
	bulwark.display_name = "Bulwark"
	bulwark.role = "siege vehicle"
	bulwark.cost = 210
	bulwark.force_slots = 2
	bulwark.build_time = 6.5
	bulwark.max_health = 210.0
	bulwark.speed = 2.6
	bulwark.attack_range = 14.0
	bulwark.attack_damage = 70.0
	bulwark.attack_cooldown = 3.6
	bulwark.armour = 3.0
	bulwark.structure_damage_multiplier = 1.65
	bulwark.splash_radius = 2.8
	bulwark.splash_minimum_multiplier = 0.4
	bulwark.projectile_mode = "arc_missile"
	bulwark.vision_range = 14.0
	bulwark.body_scale = Vector3(1.4, 0.8, 1.15)
	bulwark.required_technology = "advanced_targeting"
	unit_definitions[bulwark.id] = bulwark

	var collector = UnitDefinitionScript.new()
	collector.id = "collector"
	collector.display_name = "Collector"
	collector.role = "resource hauler"
	collector.cost = 115
	collector.force_slots = 1
	collector.build_time = 3.5
	collector.max_health = 150.0
	collector.speed = 4.8
	collector.attack_range = 7.2
	collector.attack_damage = 9.0
	collector.attack_cooldown = 1.1
	collector.vision_range = 10.0
	collector.body_scale = Vector3(1.2, 0.7, 1.0)
	unit_definitions[collector.id] = collector

	var command_hub = BuildingDefinitionScript.new()
	command_hub.id = "command_hub"
	command_hub.display_name = "Command Hub"
	command_hub.role = "headquarters"
	command_hub.cost = 0
	command_hub.build_time = 0.0
	command_hub.max_health = 900.0
	command_hub.footprint = Vector2(4.5, 4.5)
	command_hub.body_height = 2.8
	building_definitions[command_hub.id] = command_hub

	var refinery = BuildingDefinitionScript.new()
	refinery.id = "refinery"
	refinery.display_name = "Resource Processor"
	refinery.can_produce = "collector"
	refinery.upgrade_id = "refining_efficiency"
	refinery.upgrade_cost = 200
	refinery.upgrade_time = 6.0
	refinery.upgrade_effect = "delivery_value"
	refinery.role = "economy"
	refinery.cost = 250
	refinery.build_time = 4.5
	refinery.max_health = 420.0
	refinery.footprint = Vector2(3.5, 3.5)
	refinery.produces_income = 0.0
	refinery.body_height = 1.8
	building_definitions[refinery.id] = refinery

	var assembly_bay = BuildingDefinitionScript.new()
	assembly_bay.id = "assembly_bay"
	assembly_bay.display_name = "Assembly Bay"
	assembly_bay.role = "production"
	assembly_bay.cost = 220
	assembly_bay.build_time = 4.0
	assembly_bay.max_health = 450.0
	assembly_bay.footprint = Vector2(3.5, 3.5)
	assembly_bay.prerequisite_building = "refinery"
	assembly_bay.can_produce = "ranger,warden,bulwark,raider"
	assembly_bay.upgrade_id = "fabrication_systems"
	assembly_bay.upgrade_cost = 225
	assembly_bay.upgrade_time = 7.0
	assembly_bay.upgrade_effect = "production_speed"
	assembly_bay.body_height = 2.0
	building_definitions[assembly_bay.id] = assembly_bay

	var tech_centre = BuildingDefinitionScript.new()
	tech_centre.id = "tech_centre"
	tech_centre.display_name = "Tech Centre"
	tech_centre.role = "technology"
	tech_centre.cost = 320
	tech_centre.build_time = 5.5
	tech_centre.max_health = 380.0
	tech_centre.footprint = Vector2(3.2, 3.2)
	tech_centre.prerequisite_building = "assembly_bay"
	tech_centre.can_research = "advanced_targeting"
	tech_centre.body_height = 2.4
	building_definitions[tech_centre.id] = tech_centre

	var silo = BuildingDefinitionScript.new()
	silo.id = "storage_silo"
	silo.display_name = "Storage Silo"
	silo.role = "logistics storage"
	silo.cost = 150
	silo.build_time = 3.5
	silo.max_health = 260.0
	silo.footprint = Vector2(2.4, 2.4)
	silo.build_source_kind = "refinery"
	silo.prerequisite_building = "refinery"
	silo.body_height = 2.8
	building_definitions[silo.id] = silo

	var relay = BuildingDefinitionScript.new()
	relay.id = "relay"
	relay.display_name = "Forward Relay"
	relay.role = "logistics"
	relay.cost = 180
	relay.build_time = 4.0
	relay.max_health = 300.0
	relay.footprint = Vector2(2.6, 2.6)
	relay.body_height = 2.5
	building_definitions[relay.id] = relay
