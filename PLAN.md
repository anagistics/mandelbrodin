# Compute Shader Implementation Plan

## Executive Summary

This document outlines the plan to add compute shader support to the Mandelbrot Explorer, enabling significantly faster high-resolution exports and advanced rendering features.

## System Requirements Analysis

### Current Setup
- **OpenGL Version**: 3.3 Core Profile
- **GPU**: AMD Radeon Vega Series (Renoir)
- **Vulkan Support**: Available (Version 1.4.328)

### Compute Shader Requirements
- **Option A - OpenGL**: Requires OpenGL 4.3+ (released August 2012)
- **Option B - Vulkan**: Requires Vulkan 1.0+ (available: 1.4.328 ✓)

### Capability Verification
✅ **AMD Radeon Vega GPU supports:**
- OpenGL 4.6
- Vulkan 1.4
- Compute shaders in both APIs

**Conclusion**: Both OpenGL 4.3+ and Vulkan are available. OpenGL 4.3+ is recommended for phase 1 due to lower complexity and code reuse.

## Architecture Decision

### Recommended Approach: OpenGL 4.3+ Compute Shaders

**Rationale:**
1. **Lower complexity**: Reuse existing OpenGL context, textures, and shader infrastructure
2. **Incremental upgrade**: Minimal changes to existing codebase
3. **Proven compatibility**: AMD Vega supports OpenGL 4.6
4. **Code reuse**: Share uniform handling, texture management with existing renderer
5. **Easier debugging**: Existing OpenGL debugging tools (RenderDoc, apitrace)

**Future consideration**: Vulkan could be added later for:
- Cross-platform support (WebGPU compatibility)
- Better multi-GPU support
- Lower driver overhead
- More explicit control

### Implementation Strategy

**Three-phase approach:**

1. **Phase 1**: OpenGL 4.3+ compute shader for high-resolution export (2-3 days)
2. **Phase 2**: Advanced features using compute capabilities (2-3 days)
3. **Phase 3** (Optional): Vulkan backend for maximum performance (1-2 weeks)

## Phase 1: Compute Shader Foundation

**Goal**: Replace CPU-based high-resolution export with GPU compute shader (50-100x speedup for 16K exports)

### 1.1 Upgrade OpenGL Context

**File**: `appelman.odin`

**Changes**:
```odin
// Current (lines 95-97):
SDL.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 3)
SDL.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)

// New:
SDL.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 4)
SDL.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
```

**Backward compatibility**: Keep fragment shader for real-time display, add compute shader for exports.

**Verification**:
- Add OpenGL version logging after context creation
- Query `GL_VERSION` and `GL_COMPUTE_SHADER` support
- Graceful fallback to CPU if compute shaders unavailable

### 1.2 Create Compute Shader

**New file**: `shaders/mandelbrot_compute.glsl`

**Structure**:
```glsl
#version 430 core

// Workgroup size: 16×16 threads (256 threads per workgroup)
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// Output image (write-only)
layout(rgba8, binding = 0) uniform writeonly image2D u_output_image;

// Uniforms (reuse from fragment shader)
uniform dvec2 u_center;        // Center position (double precision)
uniform double u_zoom;         // Zoom level
uniform double u_rotation;     // Rotation angle
uniform int u_max_iterations;  // Maximum iterations
uniform int u_use_smooth;      // Smooth coloring flag
uniform ivec2 u_dimensions;    // Image dimensions

// Palette data (reuse from fragment shader)
uniform int u_palette_size;
uniform vec4 u_palette_colors[10];
uniform float u_palette_positions[10];

// Screen to world coordinate conversion
dvec2 screen_to_world(ivec2 pixel, ivec2 dimensions) {
    // Normalize to [-0.5, 0.5]
    dvec2 norm = dvec2(pixel) / dvec2(dimensions) - 0.5;

    // Apply rotation
    double cos_r = cos(u_rotation);
    double sin_r = sin(u_rotation);
    dvec2 rotated = dvec2(
        norm.x * cos_r - norm.y * sin_r,
        norm.x * sin_r + norm.y * cos_r
    );

    // Scale to world coordinates
    dvec2 scale = dvec2(3.5, 2.0) / u_zoom;
    dvec2 world = rotated * scale + u_center;

    return world;
}

// Mandelbrot iteration (reuse logic from fragment shader)
vec4 compute_mandelbrot(dvec2 c) {
    dvec2 z = dvec2(0.0);
    int iter = 0;
    double magnitude_sq = 0.0;

    for (iter = 0; iter < u_max_iterations; iter++) {
        // z = z² + c
        double z_real = z.x * z.x - z.y * z.y + c.x;
        double z_imag = 2.0 * z.x * z.y + c.y;
        z = dvec2(z_real, z_imag);

        magnitude_sq = z.x * z.x + z.y * z.y;
        if (magnitude_sq > 4.0) break;
    }

    // Compute color (smooth or discrete)
    if (u_use_smooth == 1 && magnitude_sq > 1.0) {
        double magnitude = sqrt(magnitude_sq);
        double smooth_iter = double(iter) + 1.0 - log(log(magnitude)) / log(2.0);
        smooth_iter = max(0.0, smooth_iter);
        return compute_color_smooth(float(smooth_iter), u_max_iterations);
    } else {
        return compute_color(iter, u_max_iterations);
    }
}

// Color computation (copy from fragment shader)
vec4 compute_color(int iter, int max_iter) {
    if (iter >= max_iter) {
        return vec4(0.0, 0.0, 0.0, 1.0);
    }

    float t = float(iter) / float(max_iter);

    // Interpolate palette
    for (int i = 0; i < u_palette_size - 1; i++) {
        if (t >= u_palette_positions[i] && t <= u_palette_positions[i + 1]) {
            float local_t = (t - u_palette_positions[i]) /
                           (u_palette_positions[i + 1] - u_palette_positions[i]);
            return mix(u_palette_colors[i], u_palette_colors[i + 1], local_t);
        }
    }

    return u_palette_colors[u_palette_size - 1];
}

vec4 compute_color_smooth(float smooth_iter, int max_iter) {
    float t = smooth_iter / float(max_iter);

    // Same interpolation logic as discrete
    for (int i = 0; i < u_palette_size - 1; i++) {
        if (t >= u_palette_positions[i] && t <= u_palette_positions[i + 1]) {
            float local_t = (t - u_palette_positions[i]) /
                           (u_palette_positions[i + 1] - u_palette_positions[i]);
            return mix(u_palette_colors[i], u_palette_colors[i + 1], local_t);
        }
    }

    return u_palette_colors[u_palette_size - 1];
}

void main() {
    // Get pixel coordinates
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);

    // Bounds check
    if (pixel.x >= u_dimensions.x || pixel.y >= u_dimensions.y) {
        return;
    }

    // Convert to world coordinates
    dvec2 c = screen_to_world(pixel, u_dimensions);

    // Compute Mandelbrot color
    vec4 color = compute_mandelbrot(c);

    // Write to output image
    imageStore(u_output_image, pixel, color);
}
```

**Key features**:
- Double precision for center coordinates (prevents precision loss at high zoom)
- Reuses palette interpolation logic from fragment shader
- 16×16 workgroup size (standard, good performance)
- Bounds checking for non-multiple-of-16 dimensions

### 1.3 Compute Shader Loader

**File**: `renderer/renderer.odin`

**Add**:
```odin
// Global state
compute_program: u32
compute_shader_available: bool

// Load and compile compute shader
load_compute_shader :: proc() -> (program: u32, success: bool) {
    shader_source := #load("../shaders/mandelbrot_compute.glsl", cstring)

    // Create compute shader
    shader := gl.CreateShader(gl.COMPUTE_SHADER)
    gl.ShaderSource(shader, 1, &shader_source, nil)
    gl.CompileShader(shader)

    // Check compilation
    compile_status: i32
    gl.GetShaderiv(shader, gl.COMPILE_STATUS, &compile_status)
    if compile_status == 0 {
        info_log: [512]u8
        gl.GetShaderInfoLog(shader, 512, nil, raw_data(info_log[:]))
        fmt.eprintln("Compute shader compilation failed:", cstring(raw_data(info_log[:])))
        return 0, false
    }

    // Create program
    program = gl.CreateProgram()
    gl.AttachShader(program, shader)
    gl.LinkProgram(program)

    // Check linking
    link_status: i32
    gl.GetProgramiv(program, gl.LINK_STATUS, &link_status)
    if link_status == 0 {
        info_log: [512]u8
        gl.GetProgramInfoLog(program, 512, nil, raw_data(info_log[:]))
        fmt.eprintln("Compute shader linking failed:", cstring(raw_data(info_log[:])))
        return 0, false
    }

    gl.DeleteShader(shader)
    return program, true
}

// Initialize compute shader support
init_compute_shaders :: proc() -> bool {
    // Check OpenGL version
    version := gl.GetString(gl.VERSION)
    fmt.println("OpenGL Version:", cstring(version))

    // Check compute shader support
    max_compute_work_group_count: [3]i32
    gl.GetIntegeri_v(gl.MAX_COMPUTE_WORK_GROUP_COUNT, 0, &max_compute_work_group_count[0])
    gl.GetIntegeri_v(gl.MAX_COMPUTE_WORK_GROUP_COUNT, 1, &max_compute_work_group_count[1])
    gl.GetIntegeri_v(gl.MAX_COMPUTE_WORK_GROUP_COUNT, 2, &max_compute_work_group_count[2])

    fmt.println("Max compute work group count:", max_compute_work_group_count)

    // Load compute shader
    program, success := load_compute_shader()
    if !success {
        fmt.eprintln("Failed to load compute shader, using CPU fallback")
        return false
    }

    compute_program = program
    compute_shader_available = true
    fmt.println("✓ Compute shader initialized successfully")
    return true
}
```

### 1.4 Compute Export Implementation

**File**: `renderer/export.odin`

**Add**:
```odin
// Export using compute shader (GPU path)
export_image_compute :: proc(state: ^app.App_State, width, height: int, filename: string) -> bool {
    if !compute_shader_available {
        fmt.println("Compute shader not available, falling back to CPU")
        return export_image_cpu(state, width, height, filename)
    }

    fmt.printf("Exporting %dx%d image using GPU compute shader...\n", width, height)
    start_time := time.now()

    // Create output texture
    output_texture: u32
    gl.GenTextures(1, &output_texture)
    gl.BindTexture(gl.TEXTURE_2D, output_texture)
    gl.TexStorage2D(gl.TEXTURE_2D, 1, gl.RGBA8, i32(width), i32(height))
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    defer gl.DeleteTextures(1, &output_texture)

    // Bind texture as image
    gl.BindImageTexture(0, output_texture, 0, false, 0, gl.WRITE_ONLY, gl.RGBA8)

    // Use compute shader program
    gl.UseProgram(compute_program)

    // Set uniforms (reuse existing uniform setting code)
    set_mandelbrot_uniforms_compute(state, width, height)

    // Dispatch compute shader
    // Workgroup size is 16×16, so divide dimensions by 16 (round up)
    groups_x := (u32(width) + 15) / 16
    groups_y := (u32(height) + 15) / 16
    gl.DispatchCompute(groups_x, groups_y, 1)

    // Wait for computation to complete
    gl.MemoryBarrier(gl.SHADER_IMAGE_ACCESS_BARRIER_BIT)

    elapsed := time.since(start_time)
    fmt.printf("Computation completed in %.2f ms\n", time.duration_milliseconds(elapsed))

    // Read pixels from texture
    pixels := make([]u8, width * height * 4)
    defer delete(pixels)

    gl.BindTexture(gl.TEXTURE_2D, output_texture)
    gl.GetTexImage(gl.TEXTURE_2D, 0, gl.RGBA, gl.UNSIGNED_BYTE, raw_data(pixels))

    // Convert RGBA to RGBA format expected by stb_image_write
    // (may need to flip Y axis)

    // Save to PNG
    success := save_png_from_bytes(pixels, width, height, filename)

    total_elapsed := time.since(start_time)
    fmt.printf("Total export time: %.2f ms\n", time.duration_milliseconds(total_elapsed))

    return success
}

// Set uniforms for compute shader
set_mandelbrot_uniforms_compute :: proc(state: ^app.App_State, width, height: int) {
    // Center (double precision)
    center_loc := gl.GetUniformLocation(compute_program, "u_center")
    gl.Uniform2d(center_loc, state.center_x, state.center_y)

    // Zoom (double precision)
    zoom_loc := gl.GetUniformLocation(compute_program, "u_zoom")
    gl.Uniform1d(zoom_loc, state.zoom)

    // Rotation (double precision)
    rotation_loc := gl.GetUniformLocation(compute_program, "u_rotation")
    gl.Uniform1d(rotation_loc, state.rotation)

    // Max iterations
    iter_loc := gl.GetUniformLocation(compute_program, "u_max_iterations")
    gl.Uniform1i(iter_loc, i32(state.max_iterations))

    // Smooth coloring flag
    smooth_loc := gl.GetUniformLocation(compute_program, "u_use_smooth")
    gl.Uniform1i(smooth_loc, i32(state.use_smooth_coloring ? 1 : 0))

    // Dimensions
    dim_loc := gl.GetUniformLocation(compute_program, "u_dimensions")
    gl.Uniform2i(dim_loc, i32(width), i32(height))

    // Palette data (reuse from fragment shader uniform setting)
    set_palette_uniforms_compute(state)
}

set_palette_uniforms_compute :: proc(state: ^app.App_State) {
    palette := state.current_palette

    // Palette size
    size_loc := gl.GetUniformLocation(compute_program, "u_palette_size")
    gl.Uniform1i(size_loc, i32(len(palette.stops)))

    // Palette colors and positions
    colors: [10][4]f32
    positions: [10]f32

    for stop, i in palette.stops {
        colors[i] = {
            f32(stop.r) / 255.0,
            f32(stop.g) / 255.0,
            f32(stop.b) / 255.0,
            1.0,
        }
        positions[i] = f32(stop.position)
    }

    colors_loc := gl.GetUniformLocation(compute_program, "u_palette_colors")
    gl.Uniform4fv(colors_loc, i32(len(palette.stops)), &colors[0][0])

    positions_loc := gl.GetUniformLocation(compute_program, "u_palette_positions")
    gl.Uniform1fv(positions_loc, i32(len(palette.stops)), &positions[0])
}
```

### 1.5 Integration

**File**: `app/export.odin`

**Modify**:
```odin
export_current_view :: proc(state: ^App_State) {
    resolution := EXPORT_RESOLUTIONS[state.export_resolution]
    filename := fmt.aprintf("%s.png", state.export_filename)
    defer delete(filename)

    // Try GPU compute shader first, fallback to CPU
    success := renderer.export_image_compute(state, resolution.width, resolution.height, filename)

    if success {
        fmt.printf("✓ Exported to %s\n", filename)
    } else {
        fmt.eprintln("✗ Export failed")
    }
}
```

**File**: `appelman.odin` in `main()`

**Add initialization**:
```odin
// After OpenGL context creation (around line 110)
if !renderer.init_compute_shaders() {
    fmt.println("Warning: Compute shaders not available, exports will use CPU")
}
```

### 1.6 Testing

**Test cases**:
1. ✓ Verify OpenGL 4.3+ context creation
2. ✓ Check compute shader compilation and linking
3. ✓ Export 1920×1080 image, compare with CPU version (visual)
4. ✓ Export 4K image, verify ~10x speedup over CPU
5. ✓ Export 16K image, verify completion in <1 second
6. ✓ Test with different palettes
7. ✓ Test with smooth coloring on/off
8. ✓ Test with rotation at various angles
9. ✓ Test at extreme zoom levels
10. ✓ Verify CPU fallback works when compute shader unavailable

**Performance benchmarks**:
```
Resolution  | CPU (SIMD) | GPU Compute | Speedup
------------|------------|-------------|--------
1920×1080   | ~200ms     | ~5ms        | 40x
3840×2160   | ~800ms     | ~15ms       | 53x
7680×4320   | ~3200ms    | ~50ms       | 64x
15360×8640  | ~13000ms   | ~180ms      | 72x
```

## Phase 2: Advanced Compute Features

**Goal**: Leverage compute shader capabilities for enhanced features

### 2.1 Progressive Rendering

**Benefit**: Show low-res preview instantly, refine over time

**Implementation**:
- Multi-pass rendering at 1/16 → 1/4 → full resolution
- Dispatch smaller compute workloads progressively
- Update UI with intermediate results

**File**: `renderer/progressive.odin`

### 2.2 Histogram-Based Adaptive Coloring

**Benefit**: Automatically optimize color distribution for better contrast

**Implementation**:
- Shared memory histogram accumulation in compute shader
- Two-pass approach: compute histogram, then apply equalization
- Per-region adaptive coloring

**File**: `renderer/adaptive_coloring.odin`

### 2.3 Arbitrary Precision Tile Rendering

**Benefit**: Enable deeper zoom levels beyond f64 precision

**Implementation**:
- Store center in double, compute per-tile offsets
- Tile-based rendering for extreme zoom
- Perturbation theory for zoom > 10^15

**File**: `renderer/deep_zoom.odin`

### 2.4 Real-Time Compute Mode

**Benefit**: Use compute shader for real-time display (not just export)

**Implementation**:
- Replace fragment shader with compute shader for display
- Render to texture, then blit to screen
- Potentially faster for high iteration counts

**File**: `renderer/renderer.odin` (add compute display path)

## Phase 3 (Optional): Vulkan Backend

**Goal**: Maximum performance and cross-platform support

**Estimated effort**: 1-2 weeks

**Benefits**:
- Lower driver overhead (~10-20% faster)
- Better multi-GPU support
- WebGPU compatibility (for web version)
- More explicit resource management
- Better debugging tools (Validation layers)

**Implementation approach**:
- Create Vulkan renderer alongside OpenGL
- Reuse compute shader code (GLSL → SPIR-V)
- Runtime selection: OpenGL vs Vulkan
- Fallback chain: Vulkan → OpenGL 4.3 → OpenGL 3.3 (fragment) → CPU

**Files**:
- `renderer/vulkan/` - New Vulkan backend
- `renderer/backend.odin` - Backend abstraction layer

## Testing Strategy

### Unit Tests
- Compute shader compilation
- Uniform setting
- Texture creation and binding
- Image store operations

### Integration Tests
- Export pipeline end-to-end
- Color accuracy (compare GPU vs CPU output)
- Coordinate transformation correctness
- Rotation handling

### Performance Tests
- Benchmark exports at all resolutions
- Profile GPU utilization (NVIDIA Nsight, AMD Radeon GPU Profiler)
- Memory usage analysis
- Scaling tests (1080p → 16K)

### Regression Tests
- Ensure existing CPU path still works
- Verify fragment shader path unaffected
- Check backward compatibility with old bookmarks/palettes

## Rollout Plan

### Week 1: Foundation
- Day 1-2: Upgrade OpenGL context, compute shader creation
- Day 3: Compute export implementation
- Day 4: Testing and debugging
- Day 5: Performance benchmarking

### Week 2: Refinement
- Day 1-2: Advanced features (progressive, adaptive)
- Day 3: UI improvements (progress indicators)
- Day 4-5: Documentation and polish

### Week 3 (Optional): Vulkan
- Day 1-3: Vulkan backend implementation
- Day 4: Integration and testing
- Day 5: Benchmarking and optimization

## Risk Mitigation

### Risk: Compute shader not available on user systems
**Mitigation**: Graceful fallback to CPU, runtime detection, clear messaging

### Risk: Double precision performance issues
**Mitigation**: Benchmark double vs float, use float for center if acceptable

### Risk: Memory constraints for large exports
**Mitigation**: Tile-based rendering for >16K resolutions

### Risk: Driver bugs or compatibility issues
**Mitigation**: Comprehensive testing on multiple GPUs (AMD, NVIDIA, Intel)

### Risk: Complexity increase
**Mitigation**: Keep CPU path as reference, extensive documentation

## Success Metrics

### Performance
- ✓ 16K export completes in <500ms (vs ~13s CPU)
- ✓ 4K export completes in <50ms (vs ~800ms CPU)
- ✓ 50-100x speedup over CPU for exports

### Quality
- ✓ Bit-exact output compared to CPU (or perceptually identical)
- ✓ No visual artifacts or precision issues
- ✓ Rotation and smooth coloring work correctly

### Reliability
- ✓ No crashes or memory leaks
- ✓ Graceful fallback when compute unavailable
- ✓ Works on AMD, NVIDIA, and Intel GPUs

### Usability
- ✓ No user-visible changes to UI (except speed)
- ✓ Clear indication of GPU vs CPU path
- ✓ Backward compatible with existing data

## Appendix: OpenGL 4.3+ Feature Requirements

### Required Extensions (Core in 4.3)
- `GL_ARB_compute_shader` - Compute shader support
- `GL_ARB_shader_image_load_store` - Image load/store
- `GL_ARB_shader_storage_buffer_object` - SSBO support (for future features)

### Fallback Strategy
```
1. Try OpenGL 4.3+ compute shader
   ↓ (if unavailable)
2. Try OpenGL 3.3 fragment shader (current)
   ↓ (if unavailable)
3. Use CPU rendering (SIMD/scalar)
```

### Verification Code
```odin
check_compute_support :: proc() -> bool {
    major, minor: i32
    gl.GetIntegerv(gl.MAJOR_VERSION, &major)
    gl.GetIntegerv(gl.MINOR_VERSION, &minor)

    version := major * 10 + minor
    if version < 43 {
        fmt.printf("OpenGL %d.%d < 4.3, compute shaders not available\n", major, minor)
        return false
    }

    fmt.printf("OpenGL %d.%d detected, compute shaders available\n", major, minor)
    return true
}
```

## Appendix: Vulkan Consideration

### Advantages
- Modern API with explicit control
- Better performance scaling
- Cross-platform (Desktop, Mobile, Web via WebGPU)
- Better validation and debugging
- Future-proof

### Disadvantages
- Much more verbose (5-10x code)
- Steeper learning curve
- More boilerplate (instance, device, queues, command buffers)
- Requires SPIR-V shader compilation

### When to Choose Vulkan
- Target multiple platforms (Linux, Windows, macOS via MoltenVK)
- Need maximum performance
- Building web version (WebGPU)
- Large-scale compute workloads

### When to Choose OpenGL 4.3+
- ✓ Single platform (Linux desktop)
- ✓ Existing OpenGL codebase
- ✓ Faster development
- ✓ Sufficient performance for current needs

**Recommendation for this project**: Start with OpenGL 4.3+, add Vulkan later if needed.

## References

- OpenGL 4.3 Specification: https://www.khronos.org/registry/OpenGL/specs/gl/glspec43.core.pdf
- Compute Shader Tutorial: https://antongerdelan.net/opengl/compute.html
- Vulkan Tutorial: https://vulkan-tutorial.com/
- GPU Gems - Mandelbrot Rendering: https://developer.nvidia.com/gpugems/gpugems2/part-v-image-oriented-computing
- Odin OpenGL Bindings: vendor/OpenGL package
- Odin Vulkan Bindings: vendor/vulkan package
