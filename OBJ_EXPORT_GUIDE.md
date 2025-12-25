# 3D OBJ Export Guide

## Overview

Mandelbrodin now supports exporting 3D column geometry directly to OBJ format! This creates proper 3D geometry with full cube meshes (not just vertices) that can be imported into Blender, Maya, or any other 3D software.

## Features

✅ **Full Cube Geometry**: Each column is a complete cube with 8 vertices and 12 triangular faces
✅ **Proper Normals**: Includes face normals for correct lighting in 3D software
✅ **Vertex Colors**: OBJ file includes RGB color data from the Mandelbrot palette
✅ **Height Mapping**: Iteration count/brightness determines column height
✅ **Centered Geometry**: Model is centered at origin for easy manipulation
✅ **Optimized Export**: Skips columns below minimum height threshold

## How to Use

### Method 1: From the Application UI

1. **Run Mandelbrodin**:
   ```bash
   ./mandelbrodin
   ```

2. **Switch to 3D Mode**:
   - In the Controls tab, select "3D (Columns)" under Visualization Mode

3. **Navigate to Export Tab**:
   - Click on the "Export" tab in the right panel
   - Scroll down to the "Export 3D Model (Experimental)" section

4. **Configure Export**:
   - **Model Resolution**: Choose from three presets
     - 200×150 (30K columns, ~5 MB) - Quick test
     - 400×300 (120K columns, ~20 MB) - Good detail
     - 800×600 (480K columns, ~80 MB) - High detail

   - **Filename**: Enter desired filename (e.g., "mandelbrot_3d")
     - `.obj` extension will be added automatically

5. **Click "Export 3D Model (OBJ)"**:
   - Progress will be shown in console
   - File will be saved in current directory

### Method 2: Programmatic Export

The OBJ export is also available as a function in `app/export_obj.odin`:

```odin
import app "../app"

// Configure export options
options := app.OBJ_Export_Options{
    width           = 800,
    height          = 600,
    column_width    = 0.9,   // 0.0-1.0 (1.0 = adjacent, <1.0 = gaps)
    height_scale    = 2.0,   // Height multiplier
    min_height      = 0.01,  // Skip columns shorter than this
    include_normals = true,  // Include normal vectors
    center_geometry = true,  // Center at origin
}

// Export to OBJ
success := app.export_obj(pixels, width, height, "output.obj", options)
```

## OBJ File Structure

The exported OBJ file contains:

```
# Header with metadata
v x y z r g b      # Vertices with position and color
vn x y z           # Normal vectors (6 per column, one per face)
f v1//n1 v2//n2... # Faces with vertex and normal indices
```

### Geometry Details

- **8 vertices per column**: Bottom 4 corners + Top 4 corners
- **6 normals per column**: One for each cube face (±X, ±Y, ±Z)
- **12 triangular faces per column**: 6 quad faces, each split into 2 triangles
- **Vertex colors**: RGB values embedded in vertex data (non-standard OBJ extension)

## Importing into Blender

### Quick Import

1. Open Blender
2. **File → Import → Wavefront (.obj)**
3. Select your exported `.obj` file
4. Click "Import OBJ"

### Import Settings

- **Forward Axis**: Y Forward (default)
- **Up Axis**: Z Up (default)
- **Split by Object**: Off
- **Split by Group**: Off

### After Import

The model will appear centered at the origin with:
- Proper scale (1 Blender unit = 1 column width)
- Correct normals for smooth/flat shading
- Z-up orientation (columns grow upward)

### Viewing in Blender

1. **Switch to Shading workspace** (top menu bar)
2. **Change viewport shading**:
   - Press `Z` → Select "Solid" or "Material Preview"
3. **Navigate the view**:
   - Middle mouse drag: Rotate
   - Shift + middle mouse: Pan
   - Scroll wheel: Zoom

### Applying Colors in Blender

The OBJ file includes vertex colors, but you may need to enable them:

1. Select the imported mesh
2. Switch to **Shading** workspace
3. In the Shader Editor:
   - Add **Attribute** node
   - Set Name to "Col" (vertex color attribute)
   - Connect to **Base Color** of Principled BSDF

Or use a Python script to apply colors programmatically.

## Performance Considerations

| Resolution | Columns | Vertices | Faces | File Size | Export Time |
|------------|---------|----------|-------|-----------|-------------|
| 200×150 | 30,000 | 240K | 360K | ~5 MB | ~1 sec |
| 400×300 | 120,000 | 960K | 1.4M | ~20 MB | ~3 sec |
| 800×600 | 480,000 | 3.8M | 5.7M | ~80 MB | ~10 sec |

### Tips for Large Exports

1. **Start Small**: Test with 200×150 before exporting higher resolutions
2. **Adjust Min Height**: Increase `min_height` to skip more columns and reduce file size
3. **Reduce Column Width**: Use smaller values (e.g., 0.7) for gaps between columns
4. **Subsample**: Export at lower resolution than display resolution

## Export Options Explained

### column_width (default: 0.9)
- **Range**: 0.0 to 1.0
- **Effect**: Width of each cube column
- **1.0**: Cubes are adjacent (touching)
- **0.9**: Small gaps between cubes (recommended)
- **0.5**: Large gaps, lattice appearance

### height_scale (default: 2.0)
- **Range**: 0.1 to 10.0
- **Effect**: Multiplier for column heights
- **1.0**: Natural height based on brightness
- **2.0**: Exaggerated peaks (more dramatic)
- **5.0**: Very tall spikes

### min_height (default: 0.01)
- **Range**: 0.0 to 1.0
- **Effect**: Minimum height to export (skip shorter columns)
- **0.01**: Export almost everything
- **0.1**: Skip short columns (smaller file)
- **0.5**: Only tall peaks (very small file)

### include_normals (default: true)
- **true**: Include normal vectors for proper lighting
- **false**: Smaller file, but may look flat in some renderers

### center_geometry (default: true)
- **true**: Model centered at origin (0, 0, 0)
- **false**: Model positioned at corner

## Troubleshooting

### "Export failed" message
- Check disk space (OBJ files can be large)
- Ensure you have write permissions in current directory
- Try smaller resolution first

### Blender import is slow
- Large OBJ files take time to parse
- 800×600 resolution may take 1-2 minutes to import
- Consider using lower resolution

### Model appears flat or has no detail
- Check that you're in 3D mode before exporting
- Verify height_scale is > 0
- Try increasing height_scale for more dramatic relief

### Colors don't show in Blender
- OBJ vertex colors are non-standard
- You may need to set up materials manually
- Use the height map approach (see BLENDER_HEIGHTMAP_GUIDE.md) for automatic colors

## Comparison: OBJ Export vs Height Map

### OBJ Export (This Feature)
- ✅ Direct 3D geometry
- ✅ Immediate use in 3D software
- ✅ Includes normals and topology
- ❌ Large file sizes
- ❌ Fixed resolution

### Height Map (PNG → Displacement)
- ✅ Tiny file size (few MB)
- ✅ Adjustable in Blender
- ✅ Non-destructive workflow
- ❌ Requires setup in Blender
- ❌ Extra step to create geometry

**Recommendation**: Use OBJ export for direct 3D use, height map for flexibility

## Examples

### Export at Different Settings

**High Detail Export**:
```odin
options := app.OBJ_Export_Options{
    column_width    = 0.95,  // Nearly touching
    height_scale    = 3.0,   // Tall columns
    min_height      = 0.0,   // Export everything
    include_normals = true,
}
```

**Optimized Export (Smaller File)**:
```odin
options := app.OBJ_Export_Options{
    column_width    = 0.8,   // Gaps between columns
    height_scale    = 2.0,   // Moderate height
    min_height      = 0.1,   // Skip short columns
    include_normals = true,
}
```

**Artistic Effect (Sparse)**:
```odin
options := app.OBJ_Export_Options{
    column_width    = 0.5,   // Wide gaps
    height_scale    = 5.0,   // Very tall
    min_height      = 0.3,   // Only tall columns
    include_normals = true,
}
```

## Technical Notes

### Coordinate System
- **X, Y**: Horizontal plane (fractal coordinates)
- **Z**: Vertical (column height)
- **Origin**: Center of the fractal region
- **Units**: 1 unit = 1 column spacing

### Height Calculation
```
brightness = (R + G + B) / 3.0
column_height = brightness × height_scale
```

Future enhancement: Use actual iteration count instead of brightness

### Face Winding
- Counter-clockwise winding (standard)
- Outward-facing normals
- Compatible with Blender's default settings

## Future Enhancements

Planned improvements:
- [ ] MTL material file export (for proper colors)
- [ ] PLY format support (better color support)
- [ ] STL format for 3D printing
- [ ] Mesh decimation options
- [ ] Use iteration count directly instead of brightness
- [ ] Progressive LOD (Level of Detail)
- [ ] Batch export at multiple resolutions

## Questions?

The OBJ exporter is implemented in:
- `app/export_obj.odin` - Core export logic
- `renderer/export_3d_model.odin` - Integration with renderer
- `ui/export_panel.odin` - User interface

Check the source code for detailed implementation!
