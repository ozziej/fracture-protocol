"""Blender-side Kenney kitbash pipeline for Fracture Protocol.

Run inside Blender's Python context through the Blender MCP server:

    exec(compile(open('/Users/james/Development/Fracture Protocol/tools/blender_asset_pipeline.py').read(), 'blender_asset_pipeline.py', 'exec'))
    build_units()
    build_buildings()
    build_environment_assets()
    save_pipeline_scene()

The exported GLBs are deliberately presentation-only. Simulation IDs and
balance remain in Godot; this script owns only the art assembly and export.
"""

import bpy
from pathlib import Path
from math import pi
import re
from mathutils import Vector


PROJECT = Path('/Users/james/Development/Fracture Protocol')
SOURCE = PROJECT / 'kenney_space-kit' / 'Models'
OUTPUT = PROJECT / 'art' / 'fracture_protocol_assets'
BLEND_OUTPUT = PROJECT / 'art' / 'fracture_protocol_kitbash.blend'
COLLECTION_NAME = 'FractureProtocolAssets'


def _asset_collection():
    collection = bpy.data.collections.get(COLLECTION_NAME)
    if collection is None:
        collection = bpy.data.collections.new(COLLECTION_NAME)
        bpy.context.scene.collection.children.link(collection)
    return collection


def _make_material(name, color, metallic=0.35, roughness=0.42, emission=None):
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.use_nodes = True
    shader = material.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, 1.0)
    shader.inputs['Metallic'].default_value = metallic
    shader.inputs['Roughness'].default_value = roughness
    if emission is not None:
        shader.inputs['Emission Color'].default_value = (*emission, 1.0)
        shader.inputs['Emission Strength'].default_value = 2.0
    return material


def _materials():
    return {
        'FP_Source_default': _make_material('FP_Source_default', (0.843, 0.871, 0.91), 0.35, 0.42),
    }


def _preserve_material(source_material, materials):
    if source_material is None:
        return materials['FP_Source_default']
    source_name = re.sub(r'\.\d{3}$', '', source_material.name)
    while source_name.startswith('FP_Source_'):
        source_name = source_name.removeprefix('FP_Source_')
    material_name = f'FP_Source_{source_name}'
    source_shader = source_material.node_tree.nodes.get('Principled BSDF') if source_material.use_nodes else None
    if source_shader is None:
        return materials['FP_Source_default']
    color = tuple(source_shader.inputs['Base Color'].default_value[:3])
    metallic = float(source_shader.inputs['Metallic'].default_value)
    roughness = float(source_shader.inputs['Roughness'].default_value)
    material = _make_material(material_name, color, metallic, roughness)
    materials[material_name] = material
    return material


def _remove_asset(name):
    root = bpy.data.objects.get(name)
    if root is None:
        return
    for child in list(root.children_recursive):
        bpy.data.objects.remove(child, do_unlink=True)
    bpy.data.objects.remove(root, do_unlink=True)


def _import_component(filename, root, meshes, materials, offset=(0.0, 0.0, 0.0), scale=1.0, yaw=0.0):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE / filename))
    imported = [obj for obj in bpy.data.objects if obj not in before]
    imported_meshes = [obj for obj in imported if obj.type == 'MESH']
    collection = _asset_collection()
    for obj in imported_meshes:
        matrix = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = matrix
        for old_collection in list(obj.users_collection):
            old_collection.objects.unlink(obj)
        collection.objects.link(obj)
        obj.parent = root
        obj.matrix_world = matrix
        obj.location += Vector(offset)
        obj.scale = obj.scale * scale
        obj.rotation_euler[2] += yaw
        source_materials = list(obj.data.materials)
        if not source_materials:
            obj.data.materials.append(materials['FP_Source_default'])
        else:
            # Replace slots in place. Clearing the material array resets every
            # polygon's material index to zero and silently makes the export
            # monocolour even if multiple materials are appended afterwards.
            for material_index, source_material in enumerate(source_materials):
                obj.data.materials[material_index] = _preserve_material(source_material, materials)
        meshes.append(obj)
    for obj in imported:
        if obj.type != 'MESH' and obj.name in bpy.data.objects:
            bpy.data.objects.remove(obj, do_unlink=True)


def _new_asset(name):
    _remove_asset(name)
    root = bpy.data.objects.new(name, None)
    _asset_collection().objects.link(root)
    return root, []


def _normalize(root, meshes, target_width=None, target_depth=None, target_height=None):
    corners = []
    for obj in meshes:
        corners.extend([obj.matrix_world @ Vector(corner) for corner in obj.bound_box])
    if not corners:
        return {'width': 0.0, 'depth': 0.0, 'height': 0.0}
    min_x = min(value.x for value in corners)
    max_x = max(value.x for value in corners)
    min_y = min(value.y for value in corners)
    max_y = max(value.y for value in corners)
    min_z = min(value.z for value in corners)
    max_z = max(value.z for value in corners)
    root.location += Vector((-(min_x + max_x) * 0.5, -(min_y + max_y) * 0.5, -min_z))
    width = max_x - min_x
    depth = max_y - min_y
    height = max_z - min_z
    factors = []
    if target_width:
        factors.append(target_width / max(0.001, width))
    if target_depth:
        factors.append(target_depth / max(0.001, depth))
    if target_height:
        factors.append(target_height / max(0.001, height))
    if factors:
        root.scale *= min(factors)
    return {'width': round(width, 3), 'depth': round(depth, 3), 'height': round(height, 3)}


def _export(root, name):
    bpy.ops.object.select_all(action='DESELECT')
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
    OUTPUT.mkdir(parents=True, exist_ok=True)
    filepath = OUTPUT / f'{name}.glb'
    bpy.ops.export_scene.gltf(
        filepath=str(filepath),
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_lights=False,
        export_cameras=False,
    )
    return filepath


def _build(name, components, target_width=None, target_depth=None, target_height=None):
    root, meshes = _new_asset(name)
    materials = _materials()
    for filename, offset, scale, yaw in components:
        _import_component(filename, root, meshes, materials, offset, scale, yaw)
    dimensions = _normalize(root, meshes, target_width, target_depth, target_height)
    filepath = _export(root, name)
    print(f'{name}: {dimensions} -> {filepath}')
    return root


def build_units():
    _build('unit_collector', [
        ('craft_miner.glb', (0.0, 0.0, 0.0), 1.0, pi),
        ('machine_barrel.glb', (0.0, 0.0, 0.42), 0.42, pi),
    ], 1.35, 1.9, 0.95)
    _build('unit_ranger', [
        ('craft_speederB.glb', (0.0, 0.0, 0.0), 1.0, 0.0),
        ('turret_single.glb', (0.0, 0.0, 0.48), 0.72, 0.0),
        ('weapon_rifle.glb', (0.0, -0.34, 0.58), 0.62, 0.0),
    ], 1.45, 1.65, 0.9)
    _build('unit_raider', [
        ('craft_speederA.glb', (0.0, 0.0, 0.0), 1.0, 0.0),
        ('weapon_gun.glb', (0.0, -0.2, 0.48), 0.75, 0.0),
    ], 1.45, 1.9, 0.9)
    _build('unit_warden', [
        ('rover.glb', (0.0, 0.0, 0.0), 3.6, 0.0),
        ('turret_double.glb', (0.0, 0.0, 0.62), 2.25, 0.0),
        ('machine_generator.glb', (0.0, 0.42, 0.34), 0.55, 0.0),
    ], 1.65, 1.95, 1.2)
    _build('unit_bulwark', [
        ('craft_cargoB.glb', (0.0, 0.0, 0.0), 1.0, 0.0),
        ('turret_double.glb', (0.0, 0.0, 0.72), 2.2, 0.0),
        ('rocket_fuelB.glb', (0.0, 0.38, 0.62), 0.5, 0.0),
    ], 1.9, 2.25, 1.35)
    print('Fracture Protocol unit exports complete')


def build_buildings():
    _build('building_command_hub', [
        ('platform_large.glb', (0.0, 0.0, 0.0), 2.6, 0.0),
        ('hangar_smallA.glb', (-1.15, 0.0, 0.55), 1.65, 0.0),
        ('hangar_smallB.glb', (1.15, 0.15, 0.55), 1.55, pi),
        ('satelliteDish.glb', (1.55, 0.65, 1.75), 2.0, -0.35),
        ('pipe_ringHigh.glb', (-1.4, 0.5, 0.62), 0.68, 0.0),
    ], 5.8, 4.8, 3.4)
    _build('building_command_hub_upgraded', [
        ('platform_large.glb', (0.0, 0.0, 0.0), 2.6, 0.0),
        ('hangar_smallA.glb', (-1.15, 0.0, 0.55), 1.65, 0.0),
        ('hangar_smallB.glb', (1.15, 0.15, 0.55), 1.55, pi),
        ('satelliteDish_detailed.glb', (1.55, 0.65, 1.75), 2.0, -0.35),
        ('pipe_ringHigh.glb', (-1.4, 0.5, 0.62), 0.68, 0.0),
    ], 5.8, 4.8, 3.4)
    _build('building_resource_processor', [
        ('platform_large.glb', (0.0, 0.0, 0.0), 1.9, 0.0),
        ('hangar_roundA.glb', (0.0, 0.0, 0.55), 1.25, 0.0),
        ('machine_generatorLarge.glb', (-1.25, 0.35, 0.62), 0.82, 0.0),
        ('pipe_straight.glb', (1.15, 0.05, 0.68), 0.92, pi * 0.5),
    ], 4.4, 4.0, 2.8)
    _build('building_assembly_bay', [
        ('platform_large.glb', (0.0, 0.0, 0.0), 1.9, 0.0),
        ('hangar_largeA.glb', (0.0, 0.0, 0.58), 1.5, 0.0),
        ('gate_complex.glb', (0.0, -1.05, 0.68), 0.75, 0.0),
        ('rocket_topA.glb', (0.75, 0.45, 1.4), 0.6, 0.0),
    ], 4.8, 4.4, 3.8)
    _build('building_tech_centre', [
        ('platform_large.glb', (0.0, 0.0, 0.0), 1.6, 0.0),
        ('machine_wireless.glb', (0.0, 0.0, 0.58), 3.25, 0.0),
        ('machine_wirelessCable.glb', (0.0, 0.55, 0.55), 2.2, 0.0),
        ('pipe_ringHigh.glb', (0.0, -0.45, 0.62), 0.7, 0.0),
    ], 3.5, 3.2, 2.8)
    _build('building_storage_silo', [
        ('platform_small.glb', (0.0, 0.0, 0.0), 1.2, 0.0),
        ('machine_barrel.glb', (-0.55, -0.12, 0.48), 1.35, 0.0),
        ('machine_barrel.glb', (0.55, -0.12, 0.48), 1.35, pi),
        ('machine_barrel.glb', (0.0, 0.48, 0.48), 1.35, pi * 0.5),
    ], 2.5, 2.5, 2.2)
    _build('building_storage_silo_upgraded', [
        ('platform_small.glb', (0.0, 0.0, 0.0), 1.25, 0.0),
        ('machine_barrelLarge.glb', (-0.46, 0.0, 0.55), 1.65, 0.0),
        ('machine_barrelLarge.glb', (0.46, 0.0, 0.55), 1.65, pi),
        ('pipe_ringHighEnd.glb', (0.0, 0.0, 1.38), 0.75, 0.0),
    ], 2.5, 2.5, 2.8)
    _build('building_forward_relay', [
        ('platform_small.glb', (0.0, 0.0, 0.0), 1.25, 0.0),
        ('supports_high.glb', (0.0, 0.0, 0.4), 0.9, 0.0),
        ('satelliteDish_detailed.glb', (0.0, 0.0, 1.0), 1.0, 0.0),
        ('pipe_ring.glb', (0.0, 0.0, 0.65), 0.65, 0.0),
    ], 2.8, 2.8, 3.2)
    print('Fracture Protocol building exports complete')


def build_environment_assets():
    _build('resource_cluster_a', [
        ('rock_crystalsLargeA.glb', (0.0, 0.0, 0.0), 2.2, 0.0),
    ], 2.0, 2.0, 1.25)
    _build('resource_cluster_b', [
        ('rock_crystalsLargeB.glb', (0.0, 0.0, 0.0), 2.2, 0.0),
    ], 2.0, 2.0, 1.25)
    _build('scenery_rock_a', [
        ('rock_largeA.glb', (0.0, 0.0, 0.0), 3.0, 0.0),
    ], 2.6, 2.6, 1.5)
    _build('scenery_rock_b', [
        ('rock_largeB.glb', (0.0, 0.0, 0.0), 3.0, 0.0),
    ], 2.6, 2.6, 1.5)
    print('Fracture Protocol environment exports complete')


def save_pipeline_scene():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUTPUT))
    print(f'Blender source scene saved: {BLEND_OUTPUT}')
