#!/usr/bin/env blender --python
"""
Blender script to create a 3D height-mapped scene from mandelbrot2d.png

Usage:
    blender --python create_3d_from_heightmap.py

Or run from within Blender's scripting tab.
"""

import bpy
import os
from pathlib import Path

# Configuration
IMAGE_FILENAME = "mandelbrot2d.png"
SUBDIVISION_LEVEL = 8  # Higher = more detail (6-10 recommended, 10 = very high poly)
DISPLACEMENT_STRENGTH = 2.0  # Height multiplier
PLANE_SIZE = 10.0  # Size of the base plane

def clear_scene():
    """Remove all default objects from the scene"""
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)

    # Clear orphaned data
    for mesh in bpy.data.meshes:
        bpy.data.meshes.remove(mesh)
    for material in bpy.data.materials:
        bpy.data.materials.remove(material)

def load_image(filepath):
    """Load image file into Blender"""
    if not os.path.exists(filepath):
        print(f"Error: Image file not found: {filepath}")
        return None

    # Load or reuse existing image
    image_name = os.path.basename(filepath)
    if image_name in bpy.data.images:
        image = bpy.data.images[image_name]
    else:
        image = bpy.data.images.load(filepath)

    print(f"Loaded image: {image.size[0]}x{image.size[1]} pixels")
    return image

def create_heightmap_mesh(image, subdivision_level, displacement_strength, plane_size):
    """Create a subdivided plane with displacement from image"""

    # Create plane
    bpy.ops.mesh.primitive_plane_add(size=plane_size, location=(0, 0, 0))
    plane = bpy.context.active_object
    plane.name = "Mandelbrot_Heightmap"

    # Add subdivision surface modifier for smoothness (optional, comment out for sharp pixels)
    subsurf = plane.modifiers.new(name="Subdivision", type='SUBSURF')
    subsurf.levels = 2
    subsurf.render_levels = 3

    # Subdivide the plane for displacement detail
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    for _ in range(subdivision_level):
        bpy.ops.mesh.subdivide()
    bpy.ops.object.mode_set(mode='OBJECT')

    print(f"Created plane with {len(plane.data.vertices)} vertices")

    # Create material with displacement
    material = bpy.data.materials.new(name="Mandelbrot_Material")
    material.use_nodes = True
    plane.data.materials.append(material)

    # Get node tree
    nodes = material.node_tree.nodes
    links = material.node_tree.links

    # Clear default nodes
    nodes.clear()

    # Add nodes
    node_output = nodes.new(type='ShaderNodeOutputMaterial')
    node_output.location = (400, 0)

    node_bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    node_bsdf.location = (0, 0)
    node_bsdf.inputs['Metallic'].default_value = 0.3
    node_bsdf.inputs['Roughness'].default_value = 0.4

    node_image = nodes.new(type='ShaderNodeTexImage')
    node_image.location = (-400, 0)
    node_image.image = image

    node_colorramp = nodes.new(type='ShaderNodeValToRGB')
    node_colorramp.location = (-200, -300)

    # Connect nodes - use image color for material color
    links.new(node_image.outputs['Color'], node_bsdf.inputs['Base Color'])
    links.new(node_bsdf.outputs['BSDF'], node_output.inputs['Surface'])

    # Add displacement modifier
    displace = plane.modifiers.new(name="Displace", type='DISPLACE')
    displace.strength = displacement_strength
    displace.mid_level = 0.0  # Black = no displacement

    # Create texture for displacement
    texture = bpy.data.textures.new(name="Mandelbrot_Displacement", type='IMAGE')
    texture.image = image
    displace.texture = texture

    # Set texture coordinates to UV (plane has default UVs)
    displace.texture_coords = 'UV'

    return plane

def setup_camera(target_object):
    """Create and position camera to view the heightmap"""
    bpy.ops.object.camera_add(location=(15, -15, 10))
    camera = bpy.context.active_object
    camera.name = "Camera"

    # Point camera at the center of the plane
    direction = target_object.location - camera.location
    camera.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()

    # Set as active camera
    bpy.context.scene.camera = camera

    # Camera settings
    camera.data.lens = 50
    camera.data.clip_end = 1000

    return camera

def setup_lighting():
    """Create three-point lighting setup"""

    # Key light (main light)
    bpy.ops.object.light_add(type='SUN', location=(10, -10, 15))
    key_light = bpy.context.active_object
    key_light.name = "Key_Light"
    key_light.data.energy = 3.0
    key_light.rotation_euler = (0.8, 0, 0.7)

    # Fill light (softer, from opposite side)
    bpy.ops.object.light_add(type='SUN', location=(-5, 5, 8))
    fill_light = bpy.context.active_object
    fill_light.name = "Fill_Light"
    fill_light.data.energy = 1.5
    fill_light.rotation_euler = (1.0, 0, -0.5)

    # Rim light (from behind, creates outline)
    bpy.ops.object.light_add(type='SUN', location=(-10, 10, 5))
    rim_light = bpy.context.active_object
    rim_light.name = "Rim_Light"
    rim_light.data.energy = 2.0
    rim_light.rotation_euler = (1.2, 0, -2.0)

def setup_world():
    """Configure world settings for better rendering"""
    world = bpy.context.scene.world
    world.use_nodes = True

    # Set background color
    bg_node = world.node_tree.nodes['Background']
    bg_node.inputs['Color'].default_value = (0.05, 0.05, 0.05, 1.0)  # Dark gray
    bg_node.inputs['Strength'].default_value = 0.3

def configure_render_settings():
    """Set up render settings for better output"""
    scene = bpy.context.scene

    # Use Cycles renderer for better quality (or EEVEE for faster preview)
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 128  # Increase for final render

    # Or use EEVEE for real-time preview:
    # scene.render.engine = 'BLENDER_EEVEE'
    # scene.eevee.taa_render_samples = 64

    scene.render.resolution_x = 1920
    scene.render.resolution_y = 1080
    scene.render.resolution_percentage = 100

def main():
    """Main execution function"""
    print("=" * 60)
    print("Creating 3D Mandelbrot heightmap scene")
    print("=" * 60)

    # Get the directory of this script
    script_dir = Path(__file__).parent
    image_path = script_dir / IMAGE_FILENAME

    # Clear existing scene
    print("Clearing scene...")
    clear_scene()

    # Load image
    print(f"Loading image: {image_path}")
    image = load_image(str(image_path))
    if not image:
        return

    # Create heightmap mesh
    print("Creating heightmap mesh...")
    plane = create_heightmap_mesh(
        image,
        SUBDIVISION_LEVEL,
        DISPLACEMENT_STRENGTH,
        PLANE_SIZE
    )

    # Setup camera
    print("Setting up camera...")
    camera = setup_camera(plane)

    # Setup lighting
    print("Setting up lighting...")
    setup_lighting()

    # Setup world
    print("Configuring world...")
    setup_world()

    # Configure render settings
    print("Configuring render settings...")
    configure_render_settings()

    # Save .blend file
    blend_filepath = script_dir / "mandelbrot_3d_scene.blend"
    print(f"Saving scene to: {blend_filepath}")
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_filepath))

    print("=" * 60)
    print("Scene creation complete!")
    print("=" * 60)
    print(f"Subdivision level: {SUBDIVISION_LEVEL}")
    print(f"Displacement strength: {DISPLACEMENT_STRENGTH}")
    print(f"Plane size: {PLANE_SIZE}")
    print(f"Vertices: {len(plane.data.vertices)}")
    print(f"Saved to: {blend_filepath}")
    print("")
    print("Adjust settings at the top of the script:")
    print("  - SUBDIVISION_LEVEL: Higher = more detail (6-10)")
    print("  - DISPLACEMENT_STRENGTH: Height multiplier")
    print("  - PLANE_SIZE: Base plane dimensions")
    print("")
    print("To open the scene:")
    print(f"  blender {blend_filepath}")
    print("")
    print("Switch to 'Shading' workspace to see the result")
    print("Press F12 to render, or use Viewport Shading (Z key)")
    print("=" * 60)

if __name__ == "__main__":
    main()
