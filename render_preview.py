#!/usr/bin/env blender --python
"""
Quick render script to generate a preview image of the 3D heightmap scene

Usage:
    blender --background mandelbrot_3d_scene.blend --python render_preview.py
"""

import bpy
from pathlib import Path

# Configuration
OUTPUT_FILENAME = "mandelbrot_3d_preview.png"
RENDER_SAMPLES = 64  # Lower for faster preview, higher (128-512) for quality

def render_preview():
    """Render the current scene to an image file"""

    script_dir = Path(__file__).parent
    output_path = script_dir / OUTPUT_FILENAME

    scene = bpy.context.scene

    # Set output path
    scene.render.filepath = str(output_path)

    # Use EEVEE for faster rendering (or keep Cycles for quality)
    if scene.render.engine == 'CYCLES':
        scene.cycles.samples = RENDER_SAMPLES
        print(f"Rendering with Cycles at {RENDER_SAMPLES} samples...")
    else:
        print("Rendering with EEVEE...")

    # Set output format
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGB'

    print(f"Output: {output_path}")
    print(f"Resolution: {scene.render.resolution_x}x{scene.render.resolution_y}")
    print("Starting render...")

    # Render
    bpy.ops.render.render(write_still=True)

    print("=" * 60)
    print(f"Render complete! Saved to: {output_path}")
    print("=" * 60)

if __name__ == "__main__":
    render_preview()
