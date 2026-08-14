extends Control

## Kenney side-view thumbnails used by the tactical HUD.
##
## The gameplay views are assembled from the matching GLB source parts in
## data/art_asset_manifest.json. The HUD uses the corresponding PNG part as a
## readable, lightweight thumbnail instead of drawing a second interpretation
## of each unit or building in code.

const ASSET_PATHS := {
	"collector": "res://kenney_space-kit/Side/craft_miner.png",
	"ranger": "res://kenney_space-kit/Side/craft_speederB.png",
	"raider": "res://kenney_space-kit/Side/craft_speederA.png",
	"warden": "res://kenney_space-kit/Side/rover.png",
	"bulwark": "res://kenney_space-kit/Side/craft_cargoB.png",
	"command_hub": "res://kenney_space-kit/Side/hangar_smallA.png",
	"refinery": "res://kenney_space-kit/Side/hangar_roundA.png",
	"assembly_bay": "res://kenney_space-kit/Side/hangar_largeA.png",
	"tech_centre": "res://kenney_space-kit/Side/machine_wireless.png",
	"storage_silo": "res://kenney_space-kit/Side/machine_barrel.png",
	"forward_relay": "res://kenney_space-kit/Side/satelliteDish_detailed.png",
	"relay": "res://kenney_space-kit/Side/satelliteDish_detailed.png",
	"targeting": "res://kenney_space-kit/Side/machine_wireless.png",
	"fabrication": "res://kenney_space-kit/Side/machine_generatorLarge.png",
	"refining": "res://kenney_space-kit/Side/machine_generatorLarge.png",
	"repair": "res://kenney_space-kit/Side/machine_generator.png",
	"resource": "res://kenney_space-kit/Side/rock_crystalsLargeA.png",
	"route": "res://kenney_space-kit/Side/satelliteDish.png",
	"enemy": "res://kenney_space-kit/Side/turret_double.png",
	"mixed": "res://kenney_space-kit/Side/structure.png",
	"unit": "res://kenney_space-kit/Side/craft_speederB.png",
}

static var _texture_cache: Dictionary = {}

var icon_key := "unit"
var accent_color := Color("#8cebf3")
var asset_path := ""
var icon_texture: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_texture()
	queue_redraw()


func set_icon(next_key: String, next_accent := Color("#8cebf3")) -> void:
	icon_key = next_key
	accent_color = next_accent
	_refresh_texture()
	queue_redraw()


func get_asset_path() -> String:
	return asset_path


func _refresh_texture() -> void:
	asset_path = str(ASSET_PATHS.get(icon_key, ASSET_PATHS["unit"]))
	icon_texture = _load_texture(asset_path)


func _load_texture(path: String) -> Texture2D:
	if not _texture_cache.has(path):
		_texture_cache[path] = load(path)
	return _texture_cache[path] as Texture2D


func _draw() -> void:
	if size.x < 4.0 or size.y < 4.0:
		return
	var frame_rect := Rect2(Vector2(1.0, 1.0), size - Vector2(2.0, 2.0))
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.01, 0.04, 0.05, 0.20)
	frame.border_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.48)
	frame.set_border_width_all(1)
	frame.corner_radius_top_left = 6
	frame.corner_radius_top_right = 6
	frame.corner_radius_bottom_left = 6
	frame.corner_radius_bottom_right = 6
	draw_style_box(frame, frame_rect)
	if icon_texture == null:
		return

	var inset := 4.0
	var target_rect := Rect2(frame_rect.position + Vector2(inset, inset), frame_rect.size - Vector2(inset * 2.0, inset * 2.0))
	var source_size: Vector2 = icon_texture.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return
	var fit_scale: float = min(target_rect.size.x / source_size.x, target_rect.size.y / source_size.y)
	var draw_size: Vector2 = source_size * fit_scale
	var draw_rect: Rect2 = Rect2(target_rect.get_center() - draw_size * 0.5, draw_size)
	draw_texture_rect(icon_texture, draw_rect, false)
