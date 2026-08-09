class_name BuildingDefinition
extends Resource

@export var id: String = ""
@export var display_name: String = "Building"
@export var role: String = "support"
@export var cost: int = 200
@export var build_time: float = 5.0
@export var max_health: float = 500.0
@export var footprint: Vector2 = Vector2(3.0, 3.0)
@export var produces_income: float = 0.0
@export var can_produce: String = ""
@export var can_research: String = ""
@export var build_source_kind: String = "command_hub"
@export var prerequisite_building: String = ""
@export var upgrade_id: String = ""
@export var upgrade_cost: int = 0
@export var upgrade_time: float = 0.0
@export var upgrade_effect: String = ""
@export var body_height: float = 1.5

