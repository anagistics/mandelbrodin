# Blender 3D Heightmap Guide

This guide explains how to create a 3D height-mapped scene from `mandelbrot2d.png` in Blender.

## Quick Start

### Method 1: Run from Command Line (Automated)

```bash
blender --python create_3d_from_heightmap.py
```

This will:
- Clear the default scene
- Load `mandelbrot2d.png`
- Create a subdivided plane
- Apply displacement based on image brightness
- Set up camera, lighting, and materials
- Configure render settings

### Method 2: Run from Blender's Scripting Tab (Interactive)

1. Open Blender
2. Switch to the **Scripting** workspace (top menu bar)
3. Click **Open** and select `create_3d_from_heightmap.py`
4. Click **Run Script** (play button) or press `Alt+P`

## Configuration Options

Edit the top of `create_3d_from_heightmap.py` to adjust:

```python
SUBDIVISION_LEVEL = 8        # Detail level (6-10 recommended)
                             # 6 = 16,384 vertices (fast)
                             # 8 = 262,144 vertices (detailed)
                             # 10 = 4,194,304 vertices (very slow!)

DISPLACEMENT_STRENGTH = 2.0  # Height multiplier (1.0-5.0)
                             # Higher = more dramatic peaks

PLANE_SIZE = 10.0            # Base plane dimensions in Blender units
```

## Viewing the Result

After running the script:

1. **Switch to Shading workspace** (top menu bar)
2. **Change viewport shading** (press `Z` key, select "Material Preview" or "Rendered")
3. **Navigate the 3D view**:
   - Middle mouse drag: Rotate view
   - Shift + middle mouse drag: Pan
   - Scroll wheel: Zoom
4. **Render final image**: Press `F12`

## Understanding the Setup

### Displacement Modifier
- Reads brightness from `mandelbrot2d.png`
- Bright areas → High peaks
- Dark areas → Low/flat areas
- Black (interior of Mandelbrot set) → No displacement

### Material
- Uses the original PNG colors for the surface
- Slightly metallic appearance for better definition
- Roughness set for realistic lighting

### Lighting
- Three-point lighting setup (key, fill, rim)
- Sun lamps for consistent directional lighting
- Creates depth and dimension

### Camera
- Positioned at angle (15, -15, 10)
- Pointed at center of heightmap
- 50mm lens for natural perspective

## Customization Tips

### Increase Detail
```python
SUBDIVISION_LEVEL = 9  # Warning: 1+ million vertices!
```

### More Dramatic Heights
```python
DISPLACEMENT_STRENGTH = 5.0
```

### Use EEVEE for Faster Preview
In the script, change:
```python
scene.render.engine = 'BLENDER_EEVEE'
scene.eevee.taa_render_samples = 64
```

### Adjust Camera Position
After running script, select camera object and move it:
- Press `G` to grab/move
- `R` to rotate
- Or modify the script's `setup_camera()` function

## Exporting the 3D Model

Once satisfied with the result:

1. **Select the heightmap mesh**
2. **File → Export → Choose format**:
   - **Wavefront (.obj)**: Universal, good for other software
   - **STL (.stl)**: For 3D printing
   - **glTF 2.0 (.glb/.gltf)**: Modern format with materials
   - **FBX (.fbx)**: For game engines (Unity, Unreal)

3. **Export settings**:
   - Check "Apply Modifiers" to bake the displacement
   - Check "Include Normals" for proper lighting
   - For OBJ: Check "Write Materials" to include colors

## Troubleshooting

### Script doesn't run
- Make sure you're in the correct directory with `mandelbrot2d.png`
- Or edit `IMAGE_FILENAME` in the script to use absolute path

### Viewport is black/nothing visible
- Press `Z` and select "Material Preview" or "Rendered"
- Check that lighting exists (sun icons in outliner)

### Too slow / Blender freezes
- Reduce `SUBDIVISION_LEVEL` to 6 or 7
- Use EEVEE instead of Cycles renderer

### Displacement looks wrong
- Adjust `DISPLACEMENT_STRENGTH` (try 1.0 to 5.0)
- Check that image loaded correctly (Shader Editor → Image Texture node)
- Verify displacement modifier is using UV coordinates

### Want sharper, pixelated look
In `create_heightmap_mesh()` function, comment out the subdivision surface modifier:
```python
# subsurf = plane.modifiers.new(name="Subdivision", type='SUBSURF')
```

## Performance Recommendations

| Subdivision Level | Vertices | Performance | Use Case |
|-------------------|----------|-------------|----------|
| 6 | 16,384 | Fast | Quick preview |
| 7 | 65,536 | Good | Standard detail |
| 8 | 262,144 | Moderate | High detail |
| 9 | 1,048,576 | Slow | Very high detail |
| 10 | 4,194,304 | Very slow | Final render only |

## Advanced: Manual Setup (No Script)

If you prefer to do it manually in Blender:

1. **Add plane**: Shift+A → Mesh → Plane
2. **Subdivide**: Edit Mode → Select all → Subdivide (repeat 8 times)
3. **UV unwrap**: Select all → U → Unwrap
4. **Add material**: Shading tab → New material
5. **Add Image Texture**: Add → Texture → Image Texture → Open `mandelbrot2d.png`
6. **Connect to Base Color**: Connect Image Texture → Base Color
7. **Add Displacement Modifier**: Modifiers → Add → Displace
8. **Create Texture**: Texture Properties → New → Type: Image → Open `mandelbrot2d.png`
9. **Assign to Modifier**: In modifier, select the texture
10. **Adjust strength**: Set Strength to 2.0, Mid Level to 0.0

## Tips for Beautiful Renders

1. **Add Ambient Occlusion**: Shader Editor → Add Color → Mix → Use AO for subtle shadows
2. **Use Compositor**: Add glow, bloom, or depth of field effects
3. **Increase samples**: For final render, set Cycles samples to 512+
4. **Enable denoising**: Render Properties → Denoising → Check all options
5. **Adjust camera angle**: Find the most interesting features and frame them

## Next Steps

- Experiment with different Mandelbrot exports (different zoom levels, palettes)
- Try exporting with adaptive coloring for more interesting height variations
- Combine multiple heightmaps at different scales
- Animate the camera for a flythrough video
- Use displacement painting to manually enhance specific features

## Questions?

The script is heavily commented. Read through it to understand each step and customize further!
