# 3D Visualization Mode - Implementation Plan

**Date**: December 8, 2025
**Goal**: Add 3D visualization mode with columns representing iteration depth/magnitude

## Executive Summary

Transform the Mandelbrot explorer from 2D colored pixels to 3D sculptural columns, where each (x,y) coordinate has a vertical column with height representing the iteration count or escape magnitude. Add realistic lighting, shadows, camera controls, and 3D model export.

## Vision

**Current (2D Mode)**:
- Flat colored pixels
- Top-down view only
- Color represents iteration count

**New (3D Mode)**:
- Vertical columns at each pixel location
- Height represents iteration count/magnitude
- Realistic lighting and shadows
- Free camera rotation in 3D space
- Shadows reveal hidden structure
- Export to 3D modeling formats

## Visual Concept

```
Top View (2D Mode):           Side View (3D Mode):

████████████                  ║║║║║║║║║║║║
████░░░░████                  ║║║░░░░║║║║
██░░░░░░░░██                  ║║░░░░░░░║║
██░░▓▓▓▓░░██                  ║░░▓▓▓▓░░░║
██░░░░░░░░██                  ║░░░░░░░░░║
████████████                  ║░░░░░░░░░║
                              ╚═════════╝
```

Each colored pixel becomes a 3D column with:
- **X position**: Horizontal coordinate
- **Y position**: Depth coordinate
- **Z (height)**: Iteration count or magnitude
- **Color**: Same palette as 2D mode
- **Lighting**: Phong shading with shadows

## Design Decisions

### 1. Rendering Approach

**Option A: Instanced Rendering** ⭐ **RECOMMENDED**
- **Approach**: Draw millions of cube instances using OpenGL instancing
- **Pros**:
  - Very fast (single draw call for all columns)
  - Simple to implement
  - GPU-friendly (hardware instancing)
  - Easy to add per-column colors
- **Cons**:
  - Memory usage for instance data
  - Fixed geometry (cubes)
- **Performance**: Excellent (millions of instances at 60 FPS)

**Option B: Geometry Shader**
- **Approach**: Send points, expand to cubes in geometry shader
- **Pros**:
  - Minimal CPU→GPU data transfer
  - Dynamic column generation
- **Cons**:
  - Geometry shaders are slow on some GPUs
  - More complex shader code
- **Performance**: Good but variable

**Option C: Heightfield Mesh**
- **Approach**: Single mesh with displacement mapping
- **Pros**:
  - Very efficient (one mesh)
  - Continuous surface
  - Easy to export
- **Cons**:
  - Loses "column" aesthetic
  - More complex UV mapping
- **Performance**: Excellent

**Option D: Raymarching/Voxels**
- **Approach**: Volumetric rendering in compute shader
- **Pros**:
  - Highest quality
  - True volumetric effects
- **Cons**:
  - Very complex
  - Slower performance
- **Performance**: Moderate

**Decision**: **Option A (Instanced Rendering)** for Phase 1
- Best balance of simplicity, performance, and visual quality
- Can upgrade to heightfield in Phase 2 if desired

### 2. Column Height Mapping

**Option A: Iteration Count (Discrete)**
- `height = iteration_count / max_iterations`
- Simple, but causes "stepping" artifacts

**Option B: Smooth Iteration Count** ⭐ **RECOMMENDED**
- `height = smooth_iteration / max_iterations`
- Smooth transitions, professional quality
- Already implemented for 2D coloring

**Option C: Logarithmic Mapping**
- `height = log(iteration_count + 1) / log(max_iterations)`
- Compresses high values, emphasizes low values

**Option D: Escape Magnitude**
- `height = magnitude_at_escape`
- Different visual from iteration count
- Shows escape "velocity"

**Decision**: **Option B (Smooth Iteration)** with Option D as alternative mode

### 3. Column Geometry

**Option A: Cubes** ⭐ **RECOMMENDED**
- 8 vertices, 12 triangles per column
- Simple, classic look
- Easy normals for lighting

**Option B: Cylinders**
- More vertices, rounder look
- Heavier on GPU
- Better for export quality

**Option C: Hexagonal Prisms**
- Honeycomb pattern
- Interesting aesthetic
- Good vertex/quality balance

**Option D: Adaptive Detail**
- LOD based on camera distance
- Cubes far away, cylinders up close

**Decision**: **Option A (Cubes)** for simplicity, with Option D as future enhancement

### 4. Lighting Model

**Option A: Phong Shading** ⭐ **RECOMMENDED**
- Ambient + Diffuse + Specular
- Simple, fast, classic
- Good for real-time

**Option B: Physically-Based Rendering (PBR)**
- More realistic
- Metallic/roughness workflow
- Heavier computation

**Option C: Flat Shading**
- No lighting calculations
- Very fast
- Less visual interest

**Decision**: **Option A (Phong)** for Phase 1, Option B for Phase 2

### 5. Shadow Technique

**Option A: Shadow Mapping** ⭐ **RECOMMENDED**
- Render depth map from light's perspective
- Sample during main render
- Good quality, standard technique
- 1024×1024 or 2048×2048 shadow map

**Option B: No Shadows**
- Simpler, faster
- Less realistic
- Good for prototyping

**Option C: Ray Traced Shadows**
- Highest quality
- Very slow without RT hardware
- Overkill for this application

**Decision**: **Option A (Shadow Mapping)** with Option B for initial prototype

### 6. Camera Control

**Option A: Orbital Camera** ⭐ **RECOMMENDED**
- Rotate around Mandelbrot center
- Zoom in/out with distance
- Intuitive for exploration
- Always keeps set in view

**Option B: Free Camera (FPS)**
- Full 6DOF movement
- Can get lost/disoriented
- More flexible but harder to use

**Option C: Turntable**
- Rotate around vertical axis only
- Simple but limited

**Decision**: **Option A (Orbital)** with smooth interpolation

### 7. Export Formats

**Format Options**:

| Format | Pros | Cons | Use Case |
|--------|------|------|----------|
| **OBJ** ⭐ | Universal support, simple | No materials | General 3D modeling |
| **PLY** | Supports vertex colors | Less common | Point clouds, colored meshes |
| **STL** | 3D printing standard | No colors | Physical models |
| **glTF** | Modern, PBR materials | Complex format | Game engines, web |
| **FBX** | Industry standard | Complex, proprietary | Professional tools |

**Decision**: Support multiple formats
- **OBJ** (required): Universal compatibility
- **PLY** (recommended): Preserves colors
- **STL** (optional): 3D printing
- **glTF** (future): Modern workflows

## Implementation Phases

### Phase 1: Basic 3D Rendering (Core Functionality)

**Goal**: Working 3D visualization with instanced cubes

**Tasks**:
1. **3D Renderer Infrastructure** (2-3 days)
   - Create `renderer/renderer_3d.odin`
   - Vertex buffer for cube geometry (8 vertices, 12 triangles)
   - Instance buffer for column data (position, height, color)
   - MVP matrix management (Model-View-Projection)
   - Basic camera system (orbital)

2. **3D Shaders** (1-2 days)
   - `shaders/mandelbrot_3d.vert` - Vertex shader with instancing
   - `shaders/mandelbrot_3d.frag` - Fragment shader with Phong lighting
   - Uniform management (camera, light direction)

3. **Data Preparation** (1 day)
   - Compute Mandelbrot iteration data (reuse existing)
   - Convert to instance buffer format
   - Height mapping (smooth iteration → column height)
   - Color from palette (same as 2D)

4. **Camera Controls** (1-2 days)
   - Orbital camera (azimuth, elevation, distance)
   - Mouse drag to rotate
   - Mouse wheel to zoom
   - Keyboard controls (arrow keys, +/-)
   - Smooth interpolation

5. **UI Integration** (1 day)
   - Toggle 2D/3D mode button
   - 3D-specific controls (lighting direction, height scale)
   - Camera position display
   - Reset view button

6. **Testing** (1 day)
   - Visual verification
   - Performance profiling
   - Memory usage check
   - Different resolutions

**Deliverables**:
- Working 3D view with cubes
- Basic Phong lighting (no shadows yet)
- Orbital camera controls
- 2D↔3D mode switching

**Estimated Time**: 1-1.5 weeks

### Phase 2: Lighting and Shadows (Visual Enhancement)

**Goal**: Realistic lighting with shadows

**Tasks**:
1. **Shadow Mapping** (2-3 days)
   - Create shadow map framebuffer (2048×2048)
   - Shadow depth shader
   - Render scene from light's perspective
   - Sample shadow map in fragment shader
   - PCF (Percentage Closer Filtering) for soft shadows

2. **Advanced Lighting** (1-2 days)
   - Multiple light sources (directional + ambient)
   - Adjustable light position (UI controls)
   - Ambient occlusion approximation
   - Specular highlights

3. **Visual Polish** (1 day)
   - Ground plane/base
   - Skybox or gradient background
   - Fog for depth perception
   - Anti-aliasing (MSAA or FXAA)

**Deliverables**:
- Realistic shadows
- Adjustable lighting
- Professional visual quality

**Estimated Time**: 4-6 days

### Phase 3: Export Functionality (3D Model Export)

**Goal**: Export 3D models to common formats

**Tasks**:
1. **OBJ Exporter** (1-2 days)
   - Generate vertex data for all columns
   - Write OBJ format (vertices, faces)
   - Optional MTL file for materials
   - Progress indicator for large exports

2. **PLY Exporter** (1 day)
   - Binary PLY format
   - Vertex colors embedded
   - More compact than OBJ

3. **STL Exporter** (1 day)
   - Binary STL format
   - For 3D printing
   - Manifold mesh verification

4. **Export UI** (1 day)
   - Export panel in 3D mode
   - Format selection
   - Resolution/detail settings
   - Preview before export

**Deliverables**:
- OBJ export with colors
- PLY export (optional)
- STL export (optional)

**Estimated Time**: 3-5 days

### Phase 4: Optimization and Polish (Performance)

**Goal**: Smooth performance and advanced features

**Tasks**:
1. **LOD (Level of Detail)** (2-3 days)
   - Distance-based detail reduction
   - Cube instances far away
   - Higher detail (cylinders?) up close
   - Frustum culling

2. **Instancing Optimization** (1-2 days)
   - Indexed rendering
   - Geometry instancing via transform matrices
   - Minimize state changes

3. **Memory Optimization** (1 day)
   - Compact instance data format
   - Stream large datasets
   - Resolution downsampling for initial view

4. **Advanced Features** (2-3 days)
   - Height scale adjustment
   - Column width adjustment
   - Alternative height mappings (logarithmic, magnitude)
   - Wireframe mode
   - Point cloud mode

**Deliverables**:
- Smooth 60 FPS even at high resolutions
- Advanced rendering modes
- Optimized memory usage

**Estimated Time**: 6-9 days

## Technical Architecture

### Data Flow

```
Mandelbrot Computation (GPU/CPU)
    ↓
Iteration Data (per pixel)
    ↓
Height Mapping (smooth iteration → column height)
    ↓
Instance Buffer (position, height, color)
    ↓
Vertex Shader (apply transforms, instancing)
    ↓
Fragment Shader (Phong lighting, shadows)
    ↓
Framebuffer → Screen
```

### File Structure

```
mandelbrodin/
├── renderer/
│   ├── renderer.odin           # Existing 2D renderer
│   ├── renderer_3d.odin        # NEW: 3D renderer
│   ├── camera.odin             # NEW: 3D camera system
│   ├── lighting.odin           # NEW: Light management
│   └── export_3d.odin          # NEW: 3D model export
├── shaders/
│   ├── mandelbrot_3d.vert      # NEW: 3D vertex shader
│   ├── mandelbrot_3d.frag      # NEW: 3D fragment shader
│   ├── shadow_depth.vert       # NEW: Shadow map vertex
│   └── shadow_depth.frag       # NEW: Shadow map fragment
├── ui/
│   ├── view_mode_panel.odin    # NEW: 2D/3D mode toggle
│   └── camera_control_panel.odin  # NEW: 3D camera controls
└── app/
    └── app.odin                # Add 3D mode state
```

### Data Structures

```odin
// 3D rendering mode
Render_Mode :: enum {
    Mode_2D,      // Current flat pixel display
    Mode_3D,      // New 3D column display
}

// Camera for 3D mode
Camera_3D :: struct {
    // Orbital camera
    azimuth:      f32,  // Rotation around Y axis (horizontal)
    elevation:    f32,  // Rotation around X axis (vertical)
    distance:     f32,  // Distance from target
    target:       [3]f32,  // Look-at point (center of Mandelbrot)

    // Derived (computed from above)
    position:     [3]f32,
    view_matrix:  matrix[4, 4]f32,
    proj_matrix:  matrix[4, 4]f32,
}

// Instance data for GPU
Column_Instance :: struct {
    position:     [2]f32,  // X, Y world position
    height:       f32,     // Column height (Z scale)
    color:        [3]f32,  // RGB color from palette
}

// Light source
Light :: struct {
    direction:    [3]f32,  // Directional light
    color:        [3]f32,  // Light color
    intensity:    f32,     // Light strength
    ambient:      f32,     // Ambient light amount
}

// 3D renderer state
Renderer_3D :: struct {
    // Geometry
    cube_vao:         u32,  // Vertex Array Object for cube
    cube_vbo:         u32,  // Vertex Buffer Object
    instance_vbo:     u32,  // Instance data buffer

    // Shaders
    shader_program:   u32,
    shadow_program:   u32,

    // Shadow mapping
    shadow_fbo:       u32,  // Framebuffer for shadow map
    shadow_texture:   u32,  // Depth texture
    shadow_resolution: int,

    // Rendering state
    instance_count:   int,
    camera:           Camera_3D,
    light:            Light,

    // Configuration
    height_scale:     f32,  // Multiplier for column heights
    column_width:     f32,  // Base width of columns
}
```

### Shader Pseudocode

**Vertex Shader** (`mandelbrot_3d.vert`):
```glsl
#version 430 core

// Per-vertex attributes (cube geometry)
layout(location = 0) in vec3 a_position;
layout(location = 1) in vec3 a_normal;

// Per-instance attributes
layout(location = 2) in vec2 a_instance_pos;    // XY position
layout(location = 3) in float a_instance_height; // Column height
layout(location = 4) in vec3 a_instance_color;  // Color

// Uniforms
uniform mat4 u_view;
uniform mat4 u_projection;
uniform float u_height_scale;
uniform float u_column_width;

// Outputs to fragment shader
out vec3 v_position;
out vec3 v_normal;
out vec3 v_color;
out vec4 v_shadow_coord;

void main() {
    // Scale cube to column dimensions
    vec3 scaled_pos = a_position;
    scaled_pos.xy *= u_column_width;
    scaled_pos.z *= a_instance_height * u_height_scale;

    // Translate to instance position
    vec3 world_pos = vec3(a_instance_pos.x, a_instance_pos.y, scaled_pos.z / 2.0);
    world_pos += scaled_pos;

    // Transform to clip space
    gl_Position = u_projection * u_view * vec4(world_pos, 1.0);

    // Pass to fragment shader
    v_position = world_pos;
    v_normal = a_normal;  // TODO: transform by model matrix
    v_color = a_instance_color;

    // Shadow mapping (if enabled)
    v_shadow_coord = u_light_view_proj * vec4(world_pos, 1.0);
}
```

**Fragment Shader** (`mandelbrot_3d.frag`):
```glsl
#version 430 core

// Inputs from vertex shader
in vec3 v_position;
in vec3 v_normal;
in vec3 v_color;
in vec4 v_shadow_coord;

// Uniforms
uniform vec3 u_light_direction;
uniform vec3 u_light_color;
uniform float u_light_intensity;
uniform float u_ambient;
uniform vec3 u_camera_pos;

uniform sampler2D u_shadow_map;
uniform bool u_enable_shadows;

// Output
out vec4 FragColor;

float calculate_shadow() {
    if (!u_enable_shadows) return 1.0;

    // Perspective divide
    vec3 proj_coords = v_shadow_coord.xyz / v_shadow_coord.w;
    proj_coords = proj_coords * 0.5 + 0.5;  // [-1,1] to [0,1]

    // Sample shadow map
    float closest_depth = texture(u_shadow_map, proj_coords.xy).r;
    float current_depth = proj_coords.z;

    // Bias to prevent shadow acne
    float bias = 0.005;
    float shadow = current_depth - bias > closest_depth ? 0.3 : 1.0;

    return shadow;
}

void main() {
    // Normalize inputs
    vec3 normal = normalize(v_normal);
    vec3 light_dir = normalize(-u_light_direction);
    vec3 view_dir = normalize(u_camera_pos - v_position);

    // Ambient
    vec3 ambient = u_ambient * v_color;

    // Diffuse (Lambertian)
    float diff = max(dot(normal, light_dir), 0.0);
    vec3 diffuse = diff * u_light_color * u_light_intensity * v_color;

    // Specular (Blinn-Phong)
    vec3 halfway = normalize(light_dir + view_dir);
    float spec = pow(max(dot(normal, halfway), 0.0), 32.0);
    vec3 specular = spec * u_light_color * 0.3;

    // Shadow
    float shadow = calculate_shadow();

    // Combine
    vec3 result = ambient + shadow * (diffuse + specular);

    FragColor = vec4(result, 1.0);
}
```

## Camera Control Scheme

### Mouse Controls (3D Mode)

| Action | Control | Effect |
|--------|---------|--------|
| Rotate | Left Drag | Orbital rotation (azimuth + elevation) |
| Zoom | Mouse Wheel | Change camera distance |
| Pan | Right Drag | Move target point (X/Y) |

### Keyboard Controls (3D Mode)

| Key | Action |
|-----|--------|
| Arrow Keys | Rotate camera |
| +/- | Zoom in/out |
| R | Reset camera to default view |
| L | Toggle lighting |
| S | Toggle shadows |
| W | Toggle wireframe mode |

### Camera Constraints

- **Elevation**: Clamp to [-89°, 89°] (prevent gimbal lock)
- **Distance**: Clamp to [min_distance, max_distance]
- **Target**: Keep within Mandelbrot bounds

### Smooth Interpolation

- Use exponential smoothing for camera movements
- Lerp (Linear Interpolation) for position
- Slerp (Spherical Linear Interpolation) for rotation
- Makes controls feel smooth and professional

## Export Format Specifications

### OBJ Format

**Structure**:
```
# Mandelbrot 3D Export
# Resolution: 800x600
# Max Iterations: 256

mtllib mandelbrot.mtl

v -2.5 -1.5 0.0      # Vertex 1
v -2.5 -1.5 0.5      # Vertex 2
...

vn 0.0 0.0 1.0       # Normal 1
...

f 1//1 2//1 3//1     # Face 1 (vertex//normal)
...
```

**MTL File** (materials):
```
newmtl column_1
Ka 0.1 0.1 0.1       # Ambient
Kd 0.5 0.3 0.2       # Diffuse (column color)
Ks 0.3 0.3 0.3       # Specular
```

### PLY Format

**Binary PLY** (preferred for size):
```
ply
format binary_little_endian 1.0
element vertex 1000000
property float x
property float y
property float z
property uchar red
property uchar green
property uchar blue
element face 2000000
property list uchar int vertex_indices
end_header
<binary data>
```

### STL Format

**Binary STL**:
```
HEADER: Mandelbrot 3D Export
<triangle count as uint32>
<foreach triangle>
  normal: nx ny nz
  vertex 1: x y z
  vertex 2: x y z
  vertex 3: x y z
  attribute byte count: 0
</foreach>
```

## Performance Considerations

### Instance Count

| Resolution | Instances | Vertices | Triangles |
|------------|-----------|----------|-----------|
| 100×100    | 10,000    | 80,000   | 120,000   |
| 200×200    | 40,000    | 320,000  | 480,000   |
| 400×400    | 160,000   | 1,280,000| 1,920,000 |
| 800×600    | 480,000   | 3,840,000| 5,760,000 |

**Target Performance**: 60 FPS at 400×400, 30 FPS at 800×600

### Optimization Strategies

1. **Frustum Culling**: Don't render columns outside view
2. **Back-face Culling**: Eliminate invisible triangles
3. **LOD**: Reduce geometry for distant columns
4. **Instanced Rendering**: Single draw call for all columns
5. **Index Buffers**: Share vertices between triangles
6. **Compact Data**: Use `vec3` instead of `vec4` where possible

### Memory Budget

| Component | Memory (800×600) |
|-----------|------------------|
| Instance Buffer | 480K × 20 bytes = 9.6 MB |
| Shadow Map | 2048² × 4 bytes = 16 MB |
| Cube Geometry | 8 vertices × 24 bytes = 192 bytes |
| **Total** | ~26 MB |

## UI Integration

### Mode Toggle

**Control Panel Addition**:
```
┌─────────────────────────────┐
│ Rendering Mode              │
│ ○ 2D Display               │
│ ● 3D Display               │
│                             │
│ [3D Settings]               │
│  Height Scale: [===|====]   │
│  Column Width: [==|======]  │
│  Lighting: ☑ Enabled       │
│  Shadows:  ☑ Enabled       │
│                             │
│ Camera                      │
│  Azimuth:   45.0°          │
│  Elevation: 30.0°          │
│  Distance:  10.0           │
│  [Reset View]              │
└─────────────────────────────┘
```

### Export Panel (3D Mode)

```
┌─────────────────────────────┐
│ 3D Model Export             │
│                             │
│ Format: [OBJ ▼]            │
│ Resolution: [400x400 ▼]    │
│                             │
│ Options:                    │
│  ☑ Include colors          │
│  ☑ Optimize mesh           │
│  ☐ Separate by height      │
│                             │
│ [Export Model]              │
│                             │
│ Estimated:                  │
│  Vertices: ~1.2M           │
│  File Size: ~50 MB         │
└─────────────────────────────┘
```

## Testing Strategy

### Visual Testing

1. **Correctness**:
   - Compare 3D height map with 2D iteration counts
   - Verify column positions match pixel coordinates
   - Check color consistency with 2D palette

2. **Lighting**:
   - Verify shadows appear in correct direction
   - Test multiple light angles
   - Check ambient/diffuse/specular balance

3. **Camera**:
   - Test all rotation angles (gimbal lock?)
   - Verify zoom limits work
   - Check smooth interpolation

### Performance Testing

1. **FPS Benchmarks**:
   - Measure at different resolutions
   - Profile with/without shadows
   - Test LOD effectiveness

2. **Memory Profiling**:
   - Monitor VRAM usage
   - Check for memory leaks
   - Verify instance buffer updates

### Export Testing

1. **Format Validation**:
   - Import OBJ into Blender
   - Verify vertex count
   - Check material/color preservation

2. **Quality**:
   - Compare exported model with live view
   - Test different resolutions
   - Verify manifold mesh (STL)

## Future Enhancements (Beyond Initial Implementation)

### Phase 5: Advanced Features

1. **Height Mapping Modes**:
   - Iteration count (current)
   - Escape velocity magnitude
   - Distance estimation
   - Orbit trap values

2. **Alternative Geometries**:
   - Cylinders (smoother look)
   - Hexagonal prisms (honeycomb)
   - Octahedron (fewer triangles)
   - Point cloud mode (very fast)

3. **Material System**:
   - Metallic columns
   - Glass/translucent columns
   - Emissive (glowing) columns
   - Roughness variation

4. **Advanced Lighting**:
   - Multiple light sources
   - Colored lights
   - Area lights
   - Global illumination approximation

5. **Post-Processing**:
   - Bloom (glowing highlights)
   - SSAO (Ambient Occlusion)
   - Depth of field
   - Motion blur

6. **Animation**:
   - Camera path recording
   - Keyframe animation
   - Export to video
   - Mandelbrot zoom animations in 3D

### Phase 6: Raytracer Export

**Goal**: Export to raytracer formats for photorealistic rendering

**Formats**:
- **POV-Ray** (.pov): Classic raytracer
- **Mitsuba** (.xml): Research raytracer
- **Blender Cycles** (.blend): Full scene export

**Features**:
- True shadows and reflections
- Caustics (light through glass)
- Global illumination
- Physically accurate materials

## Risk Assessment

### Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Poor performance at high res | Medium | High | LOD, frustum culling, instancing optimization |
| Memory overflow | Low | High | Resolution limits, streaming, compact data |
| Gimbal lock in camera | Low | Medium | Quaternions or elevation clamping |
| Shadow artifacts | Medium | Low | Bias tuning, PCF filtering |
| Export file too large | Medium | Medium | Resolution options, mesh optimization |

### Usability Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Confusing camera controls | Medium | Medium | Smooth defaults, reset button, tutorial |
| 3D mode too slow on old GPUs | Low | Medium | Automatic fallback to 2D, lower defaults |
| Exported models too complex | Low | Low | Decimation option, LOD export |

## Success Metrics

### Performance Targets

- **60 FPS** at 400×400 resolution with shadows enabled
- **30 FPS** at 800×600 resolution with shadows enabled
- **< 100 MB** memory usage for instance data
- **< 10 seconds** for 800×600 OBJ export

### Quality Targets

- **Accurate** height mapping (matches iteration data)
- **Smooth** camera controls (no jittering)
- **Realistic** lighting (Phong shading minimum)
- **Clean** shadows (minimal artifacts)

### Usability Targets

- **< 5 seconds** to understand 3D controls (intuitive)
- **< 2 clicks** to switch between 2D/3D modes
- **< 3 clicks** to export 3D model
- **Works** in Blender, Maya, 3DS Max (OBJ import)

## Development Timeline

### Optimistic (Full-time)

- **Phase 1** (Core 3D): 1-1.5 weeks
- **Phase 2** (Lighting): 4-6 days
- **Phase 3** (Export): 3-5 days
- **Phase 4** (Polish): 6-9 days
- **Total**: 3.5-5 weeks

### Realistic (Part-time)

- **Phase 1** (Core 3D): 2-3 weeks
- **Phase 2** (Lighting): 1-2 weeks
- **Phase 3** (Export): 1 week
- **Phase 4** (Polish): 2 weeks
- **Total**: 6-8 weeks

### Phased Rollout

1. **Week 1-2**: Basic 3D with cubes, no shadows
2. **Week 3-4**: Add shadows and lighting
3. **Week 5**: OBJ export
4. **Week 6+**: Optimization and polish

## Conclusion

This 3D visualization mode will transform the Mandelbrot explorer into a unique tool for:
- **Scientific visualization**: Understanding fractal structure
- **Art creation**: Exporting sculptural 3D models
- **Education**: Visualizing iteration depth
- **3D Printing**: Physical Mandelbrot models

The implementation is technically feasible with OpenGL instancing, follows industry-standard practices, and builds upon the existing codebase without major refactoring.

**Recommended Approach**: Start with Phase 1 (basic 3D), validate with users, then proceed to lighting and export based on feedback.

## Appendix: Reference Images

**Similar Projects**:
- [Mandelbulb 3D](http://www.mandelbulb.com/) - 3D fractals
- [Fragmentarium](http://syntopia.github.io/Fragmentarium/) - Distance estimation fractals
- [3D Mandelbrot](https://github.com/HackerPoet/PySpace) - Height-mapped visualization

**Inspiration**:
- Terrain rendering techniques
- Minecraft-style voxel rendering
- Point cloud visualization
- Architectural model rendering

## Appendix: Code Snippets

### Camera Update (Orbital)

```odin
update_camera :: proc(camera: ^Camera_3D, dt: f32) {
    // Convert spherical to Cartesian
    rad_azimuth := math.to_radians(camera.azimuth)
    rad_elevation := math.to_radians(camera.elevation)

    camera.position.x = camera.target.x + camera.distance * math.cos(rad_elevation) * math.sin(rad_azimuth)
    camera.position.y = camera.target.y + camera.distance * math.sin(rad_elevation)
    camera.position.z = camera.target.z + camera.distance * math.cos(rad_elevation) * math.cos(rad_azimuth)

    // Update view matrix
    camera.view_matrix = glm.lookAt(camera.position, camera.target, {0, 1, 0})
}
```

### Instance Buffer Creation

```odin
create_instance_buffer :: proc(state: ^app.App_State, width, height: int) -> []Column_Instance {
    instances := make([]Column_Instance, width * height)

    for y in 0..<height {
        for x in 0..<width {
            idx := y * width + x

            // World position (centered at origin)
            instances[idx].position = {
                f32(x) - f32(width) / 2.0,
                f32(y) - f32(height) / 2.0,
            }

            // Height from iteration count
            pixel_idx := y * width + x
            iter := get_iteration_count(state, pixel_idx)
            smooth_iter := calculate_smooth_iteration(iter, state.max_iterations)
            instances[idx].height = f32(smooth_iter) / f32(state.max_iterations)

            // Color from palette
            color := compute_color(state, iter)
            instances[idx].color = {
                f32((color >> 16) & 0xFF) / 255.0,
                f32((color >> 8) & 0xFF) / 255.0,
                f32(color & 0xFF) / 255.0,
            }
        }
    }

    return instances
}
```

---

**Document Version**: 1.0
**Last Updated**: December 8, 2025
**Status**: Proposal - Awaiting approval
