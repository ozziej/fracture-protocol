class_name UnitDefinition
extends Resource

@export var id: String = ""
@export var display_name: String = "Unit"
@export var role: String = "general"
@export var role_summary: String = "General purpose"
@export var role_tags: PackedStringArray = []
@export var cost: int = 100
@export var force_slots: int = 1
@export var build_time: float = 3.0
@export var max_health: float = 100.0
@export var speed: float = 5.0
@export var attack_range: float = 8.0
@export var minimum_attack_range: float = 0.0
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 1.0
@export var vision_range: float = 14.0
@export var body_scale: Vector3 = Vector3.ONE
@export var required_technology: String = ""
@export var armour: float = 0.0
@export var structure_damage_multiplier: float = 1.0
@export var splash_radius: float = 0.0
@export var splash_minimum_multiplier: float = 0.0
@export var splash_damage_multiplier: float = 1.0
@export var projectile_mode: String = "direct"
