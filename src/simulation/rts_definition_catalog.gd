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
	targeting.description = "Unlocks Bulwark production, extends weapon range by 18%, and vision by 15%."
	targeting.cost = 300
	targeting.research_time = 8.0
	targeting.effect_id = "advanced_targeting"
	targeting.affected_units = PackedStringArray(["ranger", "warden", "bulwark", "raider"])
	technology_definitions[targeting.id] = targeting

	var hardened = TechnologyDefinitionScript.new()
	hardened.id = "hardened_chassis"
	hardened.display_name = "Hardened Chassis"
	hardened.description = "Reinforces Wardens and Bulwarks for prolonged route fights."
	hardened.cost = 260
	hardened.research_time = 7.0
	hardened.effect_id = "hardened_chassis"
	hardened.affected_units = PackedStringArray(["warden", "bulwark"])
	technology_definitions[hardened.id] = hardened

	var optics = TechnologyDefinitionScript.new()
	optics.id = "field_optics"
	optics.display_name = "Field Optics"
	optics.description = "Extends Ranger and Raider vision for scouting and detection."
	optics.cost = 220
	optics.research_time = 6.0
	optics.effect_id = "field_optics"
	optics.affected_units = PackedStringArray(["ranger", "raider"])
	technology_definitions[optics.id] = optics

	var breach = TechnologyDefinitionScript.new()
	breach.id = "breach_package"
	breach.display_name = "Breach Package"
	breach.description = "Improves Bulwark structure and relay damage for offensive operations."
	breach.cost = 280
	breach.research_time = 7.5
	breach.effect_id = "breach_package"
	breach.affected_units = PackedStringArray(["bulwark"])
	technology_definitions[breach.id] = breach

	var ranger = UnitDefinitionScript.new()
	ranger.id = "ranger"
	ranger.display_name = "Ranger"
	ranger.role = "general infantry"
	ranger.role_summary = "Light / fast-fire skirmisher"
	ranger.role_tags = PackedStringArray(["LIGHT ARMOUR", "FAST FIRE", "ANTI-UNIT"])
	ranger.cost = 80
	ranger.force_slots = 1
	ranger.build_time = 2.2
	ranger.max_health = 120.0
	ranger.speed = 5.8
	ranger.attack_range = 8.5
	ranger.attack_damage = 15.0
	ranger.attack_cooldown = 0.75
	ranger.armour = 1.0
	ranger.vision_range = 24.0
	ranger.body_scale = Vector3(0.72, 1.05, 0.72)
	unit_definitions[ranger.id] = ranger

	var warden = UnitDefinitionScript.new()
	warden.id = "warden"
	warden.display_name = "Warden"
	warden.role = "armoured line vehicle"
	warden.role_summary = "Armoured line breaker"
	warden.role_tags = PackedStringArray(["HEAVY ARMOUR", "SLOW FIRE", "DIRECT HIT"])
	warden.cost = 145
	warden.force_slots = 2
	warden.build_time = 4.2
	warden.max_health = 250.0
	warden.speed = 3.7
	warden.attack_range = 9.5
	warden.attack_damage = 36.0
	warden.attack_cooldown = 1.8
	warden.armour = 8.0
	warden.vision_range = 16.0
	warden.body_scale = Vector3(1.05, 0.75, 1.05)
	unit_definitions[warden.id] = warden

	var raider = UnitDefinitionScript.new()
	raider.id = "raider"
	raider.display_name = "Raider"
	raider.role = "fast attack vehicle"
	raider.role_summary = "Fast pressure vehicle"
	raider.role_tags = PackedStringArray(["FAST", "LIGHT ARMOUR", "RAID"])
	raider.cost = 105
	raider.force_slots = 1
	raider.build_time = 3.0
	raider.max_health = 120.0
	raider.speed = 6.4
	raider.attack_range = 8.5
	raider.attack_damage = 15.0
	raider.attack_cooldown = 0.75
	raider.armour = 1.0
	raider.vision_range = 17.0
	raider.body_scale = Vector3(1.25, 0.65, 0.9)
	unit_definitions[raider.id] = raider

	var bulwark = UnitDefinitionScript.new()
	bulwark.id = "bulwark"
	bulwark.display_name = "Bulwark"
	bulwark.role = "siege vehicle"
	bulwark.role_summary = "Heavy siege / structure breaker"
	bulwark.role_tags = PackedStringArray(["SIEGE", "ARC MISSILE", "BLAST / STRUCTURES"])
	bulwark.cost = 210
	bulwark.force_slots = 2
	bulwark.build_time = 6.5
	bulwark.max_health = 165.0
	bulwark.speed = 2.6
	bulwark.attack_range = 20.0
	bulwark.minimum_attack_range = 8.0
	bulwark.attack_damage = 58.0
	bulwark.attack_cooldown = 3.6
	bulwark.armour = 2.0
	bulwark.structure_damage_multiplier = 1.8
	bulwark.splash_radius = 2.4
	bulwark.splash_minimum_multiplier = 0.18
	bulwark.splash_damage_multiplier = 0.38
	bulwark.projectile_mode = "arc_missile"
	bulwark.vision_range = 18.0
	bulwark.body_scale = Vector3(1.4, 0.8, 1.15)
	bulwark.required_technology = "advanced_targeting"
	unit_definitions[bulwark.id] = bulwark

	var collector = UnitDefinitionScript.new()
	collector.id = "collector"
	collector.display_name = "Collector"
	collector.role = "resource hauler"
	collector.role_summary = "Economy unit with self-defence"
	collector.role_tags = PackedStringArray(["ECONOMY", "RETREAT", "SELF-DEFENCE"])
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

	var command_carrier = UnitDefinitionScript.new()
	command_carrier.id = "command_carrier"
	command_carrier.display_name = "Mobile Command Unit"
	command_carrier.role = "deployable base carrier"
	command_carrier.role_summary = "Slow convoy core / forward-base deployer"
	command_carrier.role_tags = PackedStringArray(["CONVOY", "DEPLOY", "NO WEAPON"])
	command_carrier.cost = 0
	command_carrier.force_slots = 3
	command_carrier.build_time = 0.0
	command_carrier.max_health = 520.0
	command_carrier.speed = 2.4
	command_carrier.attack_range = 0.0
	command_carrier.attack_damage = 0.0
	command_carrier.vision_range = 12.0
	command_carrier.body_scale = Vector3(1.55, 0.85, 1.2)
	unit_definitions[command_carrier.id] = command_carrier

	var command_hub = BuildingDefinitionScript.new()
	command_hub.id = "command_hub"
	command_hub.display_name = "Command Hub"
	command_hub.role = "headquarters"
	command_hub.cost = 0
	command_hub.build_time = 0.0
	command_hub.max_health = 2400.0
	command_hub.vision_range = 22.0
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
	refinery.upgrade_effect = "transfer_speed"
	refinery.role = "economy"
	refinery.cost = 250
	refinery.build_time = 4.5
	refinery.max_health = 900.0
	refinery.vision_range = 15.0
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
	assembly_bay.max_health = 1000.0
	assembly_bay.vision_range = 14.0
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
	tech_centre.max_health = 850.0
	tech_centre.vision_range = 16.0
	tech_centre.footprint = Vector2(3.2, 3.2)
	tech_centre.prerequisite_building = "assembly_bay"
	tech_centre.can_research = "advanced_targeting,hardened_chassis,field_optics,breach_package"
	tech_centre.body_height = 2.4
	building_definitions[tech_centre.id] = tech_centre

	var silo = BuildingDefinitionScript.new()
	silo.id = "storage_silo"
	silo.display_name = "Storage Silo"
	silo.role = "logistics storage"
	silo.cost = 150
	silo.build_time = 3.5
	silo.max_health = 600.0
	silo.vision_range = 10.0
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
	relay.max_health = 700.0
	relay.vision_range = 18.0
	relay.footprint = Vector2(2.6, 2.6)
	relay.body_height = 2.5
	building_definitions[relay.id] = relay

	var forward_base = BuildingDefinitionScript.new()
	forward_base.id = "forward_base"
	forward_base.display_name = "Forward Base"
	forward_base.role = "deployable logistics"
	forward_base.cost = 0
	forward_base.build_time = 8.0
	forward_base.max_health = 1500.0
	forward_base.vision_range = 20.0
	forward_base.footprint = Vector2(4.8, 4.8)
	forward_base.repair_radius = 7.5
	forward_base.body_height = 2.6
	building_definitions[forward_base.id] = forward_base

	var sensor_mast = BuildingDefinitionScript.new()
	sensor_mast.id = "sensor_mast"
	sensor_mast.display_name = "Sensor Mast"
	sensor_mast.role = "recon / detection"
	sensor_mast.cost = 190
	sensor_mast.build_time = 4.0
	sensor_mast.max_health = 520.0
	sensor_mast.vision_range = 30.0
	sensor_mast.footprint = Vector2(2.0, 2.0)
	sensor_mast.build_source_kind = "assembly_bay"
	sensor_mast.body_height = 3.4
	building_definitions[sensor_mast.id] = sensor_mast

	var field_repair = BuildingDefinitionScript.new()
	field_repair.id = "field_repair_station"
	field_repair.display_name = "Field Repair Station"
	field_repair.role = "forward repair"
	field_repair.cost = 210
	field_repair.build_time = 4.5
	field_repair.max_health = 650.0
	field_repair.vision_range = 12.0
	field_repair.footprint = Vector2(2.8, 2.8)
	field_repair.prerequisite_building = "forward_base"
	field_repair.build_source_kind = "forward_base"
	field_repair.repair_radius = 7.5
	field_repair.body_height = 1.7
	building_definitions[field_repair.id] = field_repair

	var bastion = BuildingDefinitionScript.new()
	bastion.id = "bastion_turret"
	bastion.display_name = "Bastion Turret"
	bastion.role = "defensive anti-unit"
	bastion.cost = 260
	bastion.build_time = 4.5
	bastion.max_health = 820.0
	bastion.vision_range = 20.0
	bastion.footprint = Vector2(2.8, 2.8)
	bastion.build_source_kind = "assembly_bay"
	bastion.attack_range = 15.0
	bastion.attack_damage = 26.0
	bastion.attack_cooldown = 1.0
	bastion.structure_damage_multiplier = 0.55
	bastion.body_height = 2.0
	building_definitions[bastion.id] = bastion

	var battery = BuildingDefinitionScript.new()
	battery.id = "fire_support_battery"
	battery.display_name = "Fire Support Battery"
	battery.role = "offensive artillery"
	battery.cost = 420
	battery.build_time = 6.5
	battery.max_health = 720.0
	battery.vision_range = 16.0
	battery.footprint = Vector2(3.4, 3.4)
	battery.build_source_kind = "tech_centre"
	battery.attack_range = 28.0
	battery.minimum_attack_range = 7.0
	battery.attack_damage = 72.0
	battery.attack_cooldown = 4.2
	battery.projectile_mode = "arc_missile"
	battery.structure_damage_multiplier = 1.65
	battery.splash_radius = 2.1
	battery.splash_damage_multiplier = 0.35
	battery.body_height = 2.1
	building_definitions[battery.id] = battery
