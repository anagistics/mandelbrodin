# Mandelbrot Renderer - Implementation Notes

## Overview

This document describes the implementation of a high-performance Mandelbrot set renderer with dual rendering modes: GPU shader-based computation and CPU SIMD vectorization, including interactive mouse controls and performance optimizations.

## Features Implemented

### 1. Interactive Mouse Controls

Implemented in `appelman.odin` (mouse event handling and screen_to_world coordinate conversion)

**Mouse Wheel Zoom**
- Scroll to zoom in/out with 1.2x zoom factor per step
- Zoom centered on mouse cursor position
- World coordinates under cursor remain fixed during zoom
- Only active when mouse is over the Mandelbrot rendering area

**Left-Click to Recenter**
- Single click recenters the view on the clicked point
- Instant recomputation and visual feedback

**Right-Click Drag to Pan**
- Hold right mouse button and drag to pan the view
- Real-time panning with live recomputation
- Accurate coordinate transformation maintains positioning

**Box Zoom (Shift + Drag)**
- Hold Shift and drag left mouse button to create selection box
- Visual feedback with semi-transparent white overlay
- Release to zoom into selected region
- Automatic optimal zoom and center calculation
- Minimum 10x10 pixel box to avoid accidental micro-zooms

### 2. GPU Shader-Based Rendering

Implemented in `renderer/renderer.odin`, `shaders/mandelbrot.vert`, `shaders/mandelbrot.frag`

**Architecture**
- OpenGL 3.3 Core Profile with fragment shader computation
- Real-time per-pixel Mandelbrot computation on GPU
- Toggle between GPU and CPU rendering modes at runtime
- Massively parallel execution (hundreds/thousands of shader cores)

**Implementation Details**

1. **Fragment Shader Computation** (`shaders/mandelbrot.frag`)
   - Each pixel computed independently in parallel by GPU
   - Mandelbrot iteration implemented in GLSL
   - Receives uniforms: zoom, center position, max iterations, palette data
   - Converts screen coordinates to complex plane coordinates
   - Iterates until escape or max iterations reached
   - Maps iteration count to color using gradient palette

2. **Coordinate System Handling**
   - Y-coordinate flip to convert OpenGL texture coords (origin bottom-left) to screen coords (origin top-left)
   - Formula: `norm_y = (1.0 - TexCoord.y) - 0.5`
   - This ensures top of screen has norm_y = -0.5, matching CPU coordinate system
   - Critical for rotation: ensures GPU and CPU modes produce identical results
   - Without this flip, rotated images would appear mirrored between modes

3. **Palette System**
   - Gradient palettes passed as uniform arrays to shader
   - Supports up to 10 color stops per palette
   - Linear interpolation between color stops in fragment shader
   - Same palette rendering as CPU mode for consistency

4. **Rendering Pipeline** (`renderer/renderer.odin`)
   - **GPU Mode**: Fragment shader computes Mandelbrot directly
     - No CPU computation or texture upload
     - Renders fullscreen quad with computation in fragment shader
     - Updates happen instantly - no recomputation delay
   - **CPU Mode**: Traditional texture-based approach
     - CPU computes pixels (with SIMD/threading)
     - Uploads to OpenGL texture
     - Renders textured quad
     - Y-flip applied in texture shader to match coordinate systems

5. **OpenGL Setup** (`appelman.odin:42-72`)
   - Switched from SDL_Renderer to OpenGL context
   - Viewport management: (0,0,800,600) for Mandelbrot, (0,0,1100,600) for ImGui
   - Scissor test ensures rendering confined to Mandelbrot area
   - ImGui uses OpenGL backend (`imgui_opengl3`)

**Performance Characteristics**
- **Real-time rendering**: Computation happens every frame on GPU
- **No precomputation**: Zoom/pan operations are instant
- **Massive parallelism**: 100-1000+ parallel shader invocations
- **Expected speedup**: 50-100x over single-threaded CPU, 3-6x over multithreaded SIMD CPU
- **Ideal for**: Interactive exploration, smooth zooming, real-time parameter changes
- **Limitation**: Float precision limited to ~7 decimal digits (same as f32), double precision available but slower

**Runtime Toggle**
- UI checkbox "Use GPU" in control panel (`ui/ui.odin:40-45`)
- SIMD toggle only available in CPU mode (GPU doesn't use it)
- Live switching between modes for performance comparison
- Both modes produce visually identical output

### 3. Multi-Threading with Dynamic Load Balancing (8-way Task Parallelism)

Implemented in `mandelbrot/mandelbrot.odin:10-180`

**Architecture**
- Spawns 8 worker threads for parallel computation
- **Dynamic work queue** using atomic counter for row distribution
- Each thread atomically fetches rows on-demand, ensuring optimal load balancing
- No synchronization needed for pixel writes - threads write to disjoint memory regions

**Thread Management**

1. **Work Queue Structure** (lines 16-20)
   - `Work_Queue` struct with atomic counter for next row to process
   - `next_row`: Atomically incremented counter (accessed via `sync.atomic_add`)
   - `total_rows`: Total number of rows (constant, no synchronization needed)
   - Single shared work queue passed to all threads

2. **Thread Data Structure** (lines 23-31)
   - `Thread_Data` struct passes computation parameters to workers
   - Contains state pointer, dimensions, work queue pointer, and coordinate offsets
   - Each thread gets its own `Thread_Data` instance on the stack
   - Shared `work_queue` pointer enables dynamic work distribution

3. **Thread Lifecycle**
   - Main thread creates 8 worker threads with `thread.create()`
   - All threads share a single work queue (atomic counter)
   - Starts all threads simultaneously with `thread.start()`
   - Waits for completion with `thread.join()` before returning
   - Cleans up resources with `thread.destroy()`

4. **Worker Functions**
   - `compute_simd_worker` (lines 182-256): SIMD vectorized computation with work queue
   - `compute_scalar_worker` (lines 81-142): Scalar computation with work queue
   - Each worker dynamically grabs rows using atomic operations

**Memory Safety**
- No race conditions for pixel writes: each row claimed by only one thread via atomic counter
- Atomic operations ensure each row index is fetched exactly once
- Thread data arrays allocated on main thread's stack, valid until all threads complete
- Read-only access to shared state (zoom, center, max_iterations)

**Dynamic Work Distribution** (600px height, 8 threads)
Instead of static partitioning, threads dynamically claim rows:
```
Work Queue: atomic counter starting at 0

Thread A: claims row 0 (atomic_add returns 0)
Thread B: claims row 1 (atomic_add returns 1)
Thread C: claims row 2 (atomic_add returns 2)
Thread D: claims row 3 (atomic_add returns 3)
Thread E: claims row 4 (atomic_add returns 4)
Thread F: claims row 5 (atomic_add returns 5)
Thread G: claims row 6 (atomic_add returns 6)
Thread H: claims row 7 (atomic_add returns 7)

// When Thread A finishes row 0, it immediately claims the next available row
Thread A: claims row 8 (atomic_add returns 8)
// ... continues until all 600 rows are processed
```

Each thread loops, atomically fetching the next row index, processing it, and repeating until all rows are complete. This ensures optimal load balancing even when rows have varying computational complexity.

**Performance Characteristics**
- **~8x speedup** on 8-core CPUs (or more with hyperthreading)
- Scales linearly with core count (assuming sufficient workload)
- Combined with SIMD: **16-24x total speedup** over scalar single-threaded baseline
- Optimal for resolutions where `height >= NUM_THREADS` (e.g., 600px height)
- **Dynamic load balancing** eliminates thread idle time when rows have varying complexity
- Atomic counter overhead is negligible (single instruction per row)
- Particularly effective in high-contrast regions where some rows escape quickly and others require max iterations

### 4. External Palette System

Implemented in `visual/palette.odin`, `app/app.odin`, palette files in `palettes/`

**Architecture**
- Palettes stored as JSON files in `palettes/` directory
- Runtime loading and validation of palette data
- Case-sensitive palette names
- Hot-reload capability (can add palettes without rebuilding)
- Single default fallback palette (Classic)

**Palette File Format** (`palettes/*.json`)
```json
{
  "name": "Classic",
  "description": "Traditional Mandelbrot color scheme",
  "stops": [
    {"position": 0.0, "r": 0, "g": 0, "b": 0},
    {"position": 0.16, "r": 32, "g": 107, "b": 203},
    {"position": 1.0, "r": 0, "g": 0, "b": 0}
  ]
}
```

**Validation** (`visual/palette.odin:validate_palette()`)
- Minimum 2 color stops required
- Positions must be in ascending order
- Positions must be in range [0.0, 1.0]
- RGB values must be in range [0, 255]
- Invalid palettes are rejected with specific error messages

**Loading Pipeline**
1. `load_palettes()` scans `palettes/` directory for `.json` files
2. Each file is parsed and validated
3. Valid palettes stored in `state.palettes` array
4. Palette dropdown populated dynamically from loaded palettes
5. Default "Classic" palette used as fallback

**Color Interpolation**
- Linear interpolation between color stops
- Same gradient calculation for both GPU and CPU modes
- Smooth color transitions across iteration counts
- Palette data passed to GPU shader as uniform arrays

**Integration**
- Control panel shows loaded palettes in dropdown (`ui/control_panel.odin`)
- Palette changes tracked in navigation history
- Bookmarks store palette name with view
- Both GPU and CPU rendering use identical palette logic

### 5. High-Resolution Image Export

Implemented in `renderer/export.odin`, `ui/export_panel.odin`, `app/app.odin`

**Export Resolutions**
Predefined resolution presets in `app.EXPORT_RESOLUTIONS`:
- Full HD: 1920×1080 (2.1 MP)
- 2K: 2560×1440 (3.7 MP)
- 4K: 3840×2160 (8.3 MP)
- 5K: 5120×2880 (14.7 MP)
- 8K: 7680×4320 (33.2 MP)
- 16K: 15360×8640 (132.7 MP)

**Export Pipeline** (`renderer/export.odin:export_image()`)
1. Allocate temporary pixel buffer for target resolution
2. Create export state copy with export dimensions
3. Compute Mandelbrot at full resolution using CPU path
4. Encode to PNG format using stb_image_write
5. Save to user-specified filename
6. Display computation time in console

**PNG Encoding** (`app/app.odin:save_png()`)
- Uses `stb_image_write` library
- Lossless compression
- RGBA color format (32-bit per pixel)
- Automatic `.png` extension if not provided
- File saved to current working directory

**UI Features** (`ui/export_panel.odin`)
- Resolution dropdown with megapixel display
- Filename text input with preview
- Current view settings display (zoom, center, iterations, palette)
- Export button with validation (disabled during export)
- Progress indication (synchronous for now)

**Performance Characteristics**
- Uses CPU rendering path (more flexible than GPU for arbitrary sizes)
- Computation time scales with resolution (4K ~4x slower than HD)
- 16K exports can take several seconds depending on iteration count
- Memory usage: resolution × 4 bytes (e.g., 4K = 33 MB, 16K = 530 MB)

**Design Decisions**
- CPU path ensures export works regardless of GPU memory limits
- Synchronous operation (no threading yet) for simplicity
- PNG format chosen for lossless quality and wide compatibility
- No GPU path due to framebuffer size limitations

### 6. Tabbed Panel UI

Implemented in `ui/tabbed_panel.odin`, refactored panel files

**Layout Architecture**
- Single tabbed panel on right side of window (300px width)
- Three tabs: Controls, Bookmarks, Export
- Mandelbrot visualization on left (800×600px)
- Total window size: 1100×600px

**Tab Organization**
1. **Controls Tab** - Parameters and rendering settings
   - Zoom, center position, iteration count
   - GPU/CPU toggle, SIMD toggle
   - Palette selection
   - Computation time display
   - History navigation buttons

2. **Bookmarks Tab** - Saved view management
   - Save current view button
   - Bookmarks list with selection
   - Rename/delete context menu
   - Preview of selected bookmark details

3. **Export Tab** - High-resolution image export
   - Resolution preset dropdown
   - Filename input field
   - Current settings preview
   - Export button with validation

**Implementation Pattern**
Each panel split into two functions:
- `Render_*_content(state, width, height)` - Tab content only
- `Render_*(state, ...)` - Standalone window wrapper (for future use)

**Code Structure** (`ui/tabbed_panel.odin:Render_tabbed_panel()`)
```odin
if imgui.BeginTabBar("MainTabs", {}) {
    if imgui.BeginTabItem("Controls", nil, {}) {
        Render_control_panel_content(state, width, height)
        imgui.EndTabItem()
    }
    // Similar for Bookmarks and Export tabs
    imgui.EndTabBar()
}
```

**Benefits**
- Reduced window width (1100px vs 2000px previous design)
- Better organization of related functionality
- More screen space for Mandelbrot visualization
- Standard UI pattern familiar to users

### 7. Navigation History System

Implemented in `app/history.odin`, keyboard shortcuts in `appelman.odin`

**Architecture**
- Browser-style back/forward navigation through view changes
- History entries track: zoom, center, iterations, palette
- Maximum 100 entries with automatic cleanup
- Index-based navigation with forward history preservation

**History Entry Structure** (`app/history.odin`)
```odin
History_Entry :: struct {
    zoom:           f64,
    center_x:       f64,
    center_y:       f64,
    max_iterations: int,
    palette:        string,
}
```

**Operations**
- `history_save()` - Save current state (called before view changes)
- `history_back()` - Navigate to previous entry (Backspace key)
- `history_forward()` - Navigate to next entry (Shift+Backspace)
- `apply_view()` - Restore view from history entry

**Trigger Points** (when history is saved)
- Mouse wheel zoom
- Click to recenter
- Box zoom completion
- Right-drag pan completion
- Palette change
- Bookmark loading
- Manual navigation via UI buttons

**Keyboard Shortcuts** (`appelman.odin:143-154`)
- **Backspace** - Go back in history
- **Shift+Backspace** - Go forward in history
- Only active when not editing text (`!io.WantCaptureKeyboard`)

**Implementation Details**
- History stored as dynamic array in `App_State`
- Current position tracked by `history_index`
- Forward history cleared when new change made from middle of stack
- Initial view saved on startup
- Prevents duplicate consecutive entries

### 8. Bookmark System

Implemented in `app/app.odin:save_bookmark()`, UI in `ui/bookmarks_panel.odin`

**Architecture**
- Bookmarks saved as JSON files in `bookmarks/` directory
- Each bookmark stores complete view state
- User-editable names with rename/delete support
- Preset interesting locations included with distribution

**Bookmark File Format** (`bookmarks/*.json`)
```json
{
  "name": "Seahorse Valley",
  "zoom": 150.5,
  "center_x": -0.743643,
  "center_y": 0.131825,
  "max_iterations": 512,
  "palette": "Classic"
}
```

**Operations**
- **Save** - Store current view with auto-generated name
- **Load** - Apply bookmark view and add to history
- **Rename** - Double-click or context menu to edit name
- **Delete** - Context menu to remove bookmark
- **Preview** - Display bookmark details before loading

**UI Features** (`ui/bookmarks_panel.odin`)
- "Save Current View" button at top
- Scrollable bookmarks list with selection
- Double-click to rename (inline editing)
- Right-click context menu (Rename/Delete)
- Preview panel showing zoom, center, iterations, palette
- Visual feedback for selected bookmark

**Preset Bookmarks** (included in distribution)
- `default_view.json` - Initial view
- `seahorse_valley.json` - Classic Mandelbrot feature
- `elephant_valley.json` - Detailed structure
- `spiral.json` - Interesting spiral pattern

**Integration**
- Loaded on startup with `load_bookmarks()`
- Saves to disk immediately when created/modified
- Palette names stored as strings (case-sensitive)
- Loading bookmark triggers history save
- Compatible with external editing (JSON format)

### 9. SIMD Vectorization (AVX 4-wide)

Implemented in `mandelbrot/mandelbrot.odin:98-185`

**Core Algorithm**
- Processes 4 pixels simultaneously using `simd.f64x4` vectors
- Vectorized Mandelbrot iteration with parallel arithmetic operations
- Smart early exit when all lanes have escaped

**Key Optimizations**

1. **Arithmetic-based masking** (lines 97-106)
   - Uses `max`/`min` operations on `(magnitude_sq - threshold)` difference
   - Avoids complex boolean mask type conversions
   - Computes escape state: `escaped = min(1.0, max(0.0, diff))`
   - Updates active state: `active = active * (1.0 - escaped)`

2. **Active state tracking** (lines 88-89, 109)
   - Tracks which pixels are still iterating using f64 values (1.0 = active, 0.0 = done)
   - Conditionally increments iteration counter: `iter_count += active`
   - Only active lanes contribute to the count

3. **Early termination** (lines 112-114)
   - Uses `simd.reduce_add_bisect()` to sum active states
   - Exits loop when sum equals 0.0 (all lanes escaped)
   - Reduces unnecessary iterations for convergent regions

4. **Type consistency** (lines 81-89, 123-129)
   - Works entirely in f64 SIMD space during iteration
   - Converts to u32 array only at the end using `simd.to_array()`
   - Avoids expensive type conversions in hot loop

**Mathematical Correctness**
- The difference-based approach: `diff = magnitude_sq - threshold`
  - If `diff > 0`: pixel escaped (magnitude_sq > 4.0)
  - If `diff <= 0`: pixel still iterating
- Clamping `min(1, max(0, diff))` creates binary 0/1 state
- Multiplying by `(1 - escaped)` zeros out escaped lanes

### 10. Dual Implementation Architecture

**SIMD Path** (`compute_simd`, lines 101-132, `compute_simd_worker`, lines 134-174)
- Default implementation using 4-wide AVX vectorization + 8 threads
- Processes pixels in blocks of 4 across 8 parallel workers
- Each thread calls `iterate_simd` for vectorized computation on its row range
- Combined parallelism: 32 pixels computed simultaneously (4 SIMD lanes × 8 threads)

**Scalar Path** (`compute_scalar`, lines 33-72, `compute_scalar_worker`, lines 75-99)
- Fallback implementation with 8-way loop unrolling + 8 threads
- Uses `#unroll` directive for compiler optimization
- Each thread processes its assigned rows independently
- Maintains compatibility and provides performance baseline

**Runtime Toggle** (`Compute`, lines 25-31)
- Switches between implementations based on `state.use_simd` flag
- UI checkbox in control panel allows live comparison
- Tooltip indicates "AVX 4-wide vectorization"
- Both paths now benefit from multithreading

### 11. Smooth Coloring

Implemented in `visual/coloring.odin` and `mandelbrot/mandelbrot.odin`

**Overview**
- Continuous iteration count for smooth color gradients
- Eliminates color banding artifacts at escape boundaries
- Uses escape distance estimation formula
- Runtime toggle via UI checkbox
- Supported in both GPU and CPU rendering modes

**Implementation** (`visual/coloring.odin:68-80`)
```odin
calculate_smooth_iteration :: proc(iter: u64, magnitude_sq: f64) -> f64 {
    if magnitude_sq <= 1.0 {
        return f64(iter)
    }
    magnitude := math.sqrt(magnitude_sq)
    smooth := f64(iter) + 1.0 - math.ln(math.ln(magnitude)) / math.ln(f64(2.0))
    return max(0.0, smooth)
}
```

**Mathematical Formula**
- Standard formula: `smooth_iter = n + 1 - log(log(|z|)) / log(2)`
- Where `n` is discrete iteration count and `|z|` is final magnitude at escape
- Produces fractional iteration values (e.g., 42.73 instead of 43)
- Interpolates colors based on fractional position in palette

**Critical SIMD Fix** (`mandelbrot/mandelbrot.odin:202,224-225`)
- SIMD version must preserve magnitude at moment of escape
- Uses `escape_magnitude_sq` to store magnitude when pixel first escapes
- Without this fix, SIMD continues updating magnitude after escape, producing incorrect smooth coloring
- Scalar and SIMD now produce identical results

**Color Application** (`visual/coloring.odin:6-24`)
- `Compute_pixel_color()` function handles both discrete and smooth coloring
- Smooth mode: calls `calculate_smooth_iteration()` then `compute_color_smooth()`
- Discrete mode: uses integer iteration count with `compute_color()`
- Both modes use same gradient interpolation logic

**Visual Impact**
- Discrete coloring: Sharp color transitions at escape boundaries (banding effect)
- Smooth coloring: Gradual color transitions, eliminates visible bands
- Especially noticeable at lower iteration counts or in zoomed views
- Works with all palette types

### 12. View Rotation

Implemented in `appelman.odin`, `mandelbrot/mandelbrot.odin`, `shaders/mandelbrot.frag`, and `ui/control_panel.odin`

**Overview**
- Rotate the Mandelbrot view around its center point
- Full 360° rotation support
- Works with all mouse interactions (pan, zoom, box zoom)
- Supported in both GPU and CPU rendering modes
- Rotation persisted in history and bookmarks

**User Controls**
1. **CTRL + Mouse Wheel** - Rotate by 5° increments
   - Scroll up: rotate counter-clockwise
   - Scroll down: rotate clockwise
   - Angle normalized to [0°, 360°) range

2. **UI Slider** (`ui/control_panel.odin:191-195`)
   - Precise rotation control from 0° to 360°
   - Real-time visual feedback
   - Displays current angle with degree symbol (°)

3. **Reset View Button** - Resets rotation to 0° along with zoom/center

**Coordinate Transformation** (`appelman.odin:35-53`)
```odin
// 1. Convert to normalized coordinates [-0.5, 0.5]
norm_x := f64(screen_x) / f64(width) - 0.5
norm_y := f64(screen_y) / f64(height) - 0.5

// 2. Apply rotation matrix
cos_r := math.cos(state.rotation)
sin_r := math.sin(state.rotation)
rotated_x := norm_x * cos_r - norm_y * sin_r
rotated_y := norm_x * sin_r + norm_y * cos_r

// 3. Scale to world coordinates
world_x := rotated_x * scale_x + state.center_x
world_y := rotated_y * scale_y + state.center_y
```

**Implementation Consistency**
All rendering paths apply identical rotation transformation:

1. **GPU Shader** (`shaders/mandelbrot.frag:99-116`)
   - Rotation applied in fragment shader
   - `u_rotation` uniform passed from CPU
   - Same normalize → rotate → scale → translate pipeline

2. **CPU Scalar** (`mandelbrot/mandelbrot.odin:89-115`)
   - Precomputes cos/sin once per worker thread
   - Applies rotation for each pixel individually
   - 8-way loop unrolling maintained

3. **CPU SIMD** (`mandelbrot/mandelbrot.odin:177-216`)
   - Vectorized rotation using 4-wide SIMD
   - All rotation values broadcast to SIMD vectors
   - Processes 4 pixels simultaneously with rotation

**Mouse Interaction Integration**
All mouse operations work correctly in rotated views:
- **Zoom** (wheel): Zoom centered at mouse cursor works in rotated space
- **Pan** (right-drag): Dragging correctly translates in rotated view
- **Recenter** (left-click): Clicked point becomes new center
- **Box Zoom** (shift-drag): Selection box corners correctly transformed

**Data Persistence**
- **History** (`app/history.odin:8,31,65`) - Rotation tracked for undo/redo
- **Bookmarks** (`app/bookmark.odin:13,33,81`) - Rotation saved in JSON format
- **Backward Compatibility** - Old bookmarks without rotation default to 0°

**Rotation Storage**
- Internal: Stored in radians (`state.rotation: f64`)
- Display: Shown in degrees for user-friendliness
- Conversion: `math.to_radians()` / `math.to_degrees()`
- Normalization: Always kept in [0, 2π) range

**Visual Behavior**
- Rotation is around the view center point
- Zoom level and center position remain fixed during rotation
- Fractal detail preserved during rotation
- No visual artifacts or discontinuities

## Performance Characteristics

### Expected Speedup

**Multithreaded SIMD (default)**: **16-24x improvement** over original scalar single-threaded baseline
- 4x from SIMD vectorization (4-wide AVX processing)
- 6-8x from multithreading (8 cores, accounting for overhead)
- Combined effect: ~16-24x total speedup

**GPU Shader**: **50-100x improvement** over original scalar single-threaded baseline
- Massively parallel execution on hundreds/thousands of GPU cores
- Real-time computation with no precomputation delay
- Typically 3-6x faster than multithreaded SIMD CPU

**Multithreaded Scalar**: **6-8x improvement** over original scalar single-threaded baseline
- Pure multithreading benefit across 8 cores
- 8-way loop unrolling provides additional ILP (Instruction-Level Parallelism)
- Useful for systems without AVX support

### Speedup Breakdown by Optimization Layer

| Configuration | Speedup | Techniques |
|--------------|---------|------------|
| Original (scalar, single-thread) | 1x (baseline) | Basic loop |
| Scalar + unrolling | ~1.2x | 8-way loop unroll |
| SIMD only (single-thread) | ~2-3x | 4-wide AVX vectors |
| Multithreaded scalar | ~6-8x | 8 threads + unrolling |
| Multithreaded SIMD | ~16-24x | 8 threads × 4-wide SIMD |
| **GPU Shader (OpenGL)** | **~50-100x** | **Hundreds/thousands of parallel shader cores** |

### Performance Factors
- **Best speedup**: Regions with uniform escape times (threads finish simultaneously)
- **Reduced speedup**: High variance in escape times causes thread load imbalance
- **Memory bandwidth**: May become limiting factor at very high resolutions (>2K)
- **Core count**: Scales with available CPU cores (optimal at 8+ cores)
- **Hyperthreading**: May provide 10-20% additional benefit on CPUs with SMT

### Benchmarking
Toggle rendering modes in the UI to compare performance:
- **Use GPU**: Toggle between GPU shader and CPU computation
- **Use SIMD**: (CPU mode only) Compare SIMD vs scalar
- Computation time displayed in milliseconds
- Test at different zoom levels and iteration counts
- Try preset locations for varied workloads
- **CPU mode**: Monitor CPU usage (~800% utilization on 8 cores)
- **GPU mode**: Near-instant rendering, minimal CPU usage

## Code Organization

```
/~/mandelbrodin/
├── appelman.odin                  # Main application, OpenGL/SDL setup, event handling, screen_to_world
├── app/
│   ├── app.odin                  # Core app state, set_palette function
│   ├── bookmark.odin             # Bookmark management (save/load/delete views)
│   ├── export.odin               # Image export functions (PNG encoding)
│   └── history.odin              # Navigation history (back/forward)
├── mandelbrot/
│   └── mandelbrot.odin           # CPU compute: SIMD and scalar implementations
├── renderer/
│   ├── renderer.odin             # OpenGL renderer: shader loading, GPU/CPU rendering
│   └── export.odin               # High-resolution image export computation
├── visual/
│   ├── palette.odin              # Palette loading, validation, color gradients
│   └── coloring.odin             # Color computation, smooth coloring, gradient interpolation
├── ui/
│   ├── ui.odin                   # Package documentation
│   ├── tabbed_panel.odin         # Main tabbed panel wrapper
│   ├── control_panel.odin        # Controls tab content
│   ├── bookmarks_panel.odin      # Bookmarks tab content
│   └── export_panel.odin         # Export tab content
├── shaders/
│   ├── mandelbrot.vert           # Vertex shader for fullscreen quad
│   ├── mandelbrot.frag           # Fragment shader: GPU Mandelbrot computation
│   ├── texture.vert              # Vertex shader for CPU texture display
│   └── texture.frag              # Fragment shader: CPU texture sampling
├── palettes/                      # External palette definitions (JSON)
│   ├── Classic.json
│   ├── Fire.json
│   ├── Ice.json
│   ├── Ocean.json
│   ├── Sunset.json
│   ├── Grayscale.json
│   └── Psychedelic.json
└── bookmarks/                     # Saved view locations (JSON)
    ├── default_view.json
    ├── seahorse_valley.json
    ├── elephant_valley.json
    └── spiral.json
```

## Technical Details

### Threading Configuration
- `NUM_THREADS :: 8` - spawns 8 worker threads for parallel computation
- **Dynamic work queue**: threads atomically claim rows on-demand using `core:sync` atomic operations
- Thread distribution: atomic counter-based work queue ensures optimal load balancing
- Memory model: each thread writes to disjoint pixel ranges (no locks required)
- Uses Odin's `core:thread` package for cross-platform threading and `core:sync` for atomic operations

### SIMD Vector Width
- `SIMD_WIDTH :: 4` - processes 4 f64 values simultaneously
- Requires width to be divisible by 4 (current: 800px ✓)
- Uses AVX instructions on compatible CPUs
- Combined with 8 threads: 32 pixels computed in parallel (4 SIMD lanes × 8 threads)

### Coordinate Conversion
The `screen_to_world` function in `appelman.odin:26-54` converts pixel coordinates to complex plane coordinates with rotation support:
```odin
// Convert to normalized coordinates [-0.5, 0.5] centered at origin
norm_x := f64(screen_x) / f64(width) - 0.5
norm_y := f64(screen_y) / f64(height) - 0.5

// Apply rotation
cos_r := math.cos(state.rotation)
sin_r := math.sin(state.rotation)
rotated_x := norm_x * cos_r - norm_y * sin_r
rotated_y := norm_x * sin_r + norm_y * cos_r

// Scale to world coordinates
scale_x := 3.5 / state.zoom
scale_y := 2.0 / state.zoom
world_x := rotated_x * scale_x + state.center_x
world_y := rotated_y * scale_y + state.center_y
```
This transformation is applied consistently across all rendering modes (GPU shader, CPU scalar, CPU SIMD) and mouse interaction.

### Build Instructions

**Prerequisites**
- Odin compiler (nightly build recommended)
- OpenGL 3.3+ support
- SDL2 development libraries
- stb_image libraries (compile with make)

**Compile stb_image libraries** (one-time setup)
```bash
make -C ~/odin-linux-amd64-nightly+2025-10-05/vendor/stb/src
```

**Build and run**
```bash
odin build . -out:mandelbrodin
./mandelbrodin
```

**Debug build**
```bash
odin build . -debug -out:mandelbrodin
./mandelbrodin
```

## UI/UX Features

### Keyboard Shortcuts
- **Backspace** - Navigate back in history
- **Shift+Backspace** - Navigate forward in history
- **ESC** - Quit application (disabled when editing text)

### Input Protection
- Uses `io.WantCaptureKeyboard` to detect text input
- Keyboard shortcuts disabled when typing in text fields
- Prevents accidental navigation/quit while editing
- Applies to: export filename, bookmark names, all text inputs

### Mouse Controls
- **Left Click** - Recenter view
- **Right Drag** - Pan view
- **Mouse Wheel** - Zoom in/out
- **Ctrl+Wheel** - Rotate view (5° increments)
- **Shift+Drag** - Box zoom selection
- Only active over Mandelbrot area (not UI panels)
- All controls work correctly in rotated views

## Future Optimization Opportunities

1. ~~**Multi-threading**: Parallelize across CPU cores (4-8x additional speedup)~~ ✓ **IMPLEMENTED**
   - 8-way task parallelism with row-based distribution
   - Achieves 6-8x speedup on 8-core systems

2. ~~**GPU acceleration**: Port to compute shaders for massive parallelism~~ ✓ **IMPLEMENTED**
   - OpenGL fragment shader computes Mandelbrot in real-time
   - 50-100x speedup over single-threaded CPU
   - 3-6x speedup over multithreaded SIMD CPU
   - Runtime toggle between GPU and CPU modes

3. ~~**External palette system**: Load palettes from files for customization~~ ✓ **IMPLEMENTED**
   - JSON-based palette definitions in `palettes/` directory
   - Validation and hot-reload support
   - Users can add custom palettes without code changes

4. ~~**High-resolution export**: Render images larger than screen size~~ ✓ **IMPLEMENTED**
   - Export up to 16K resolution (132.7 megapixels)
   - PNG format with lossless compression
   - Uses CPU path for flexibility
   - Dedicated UI in Export tab

5. ~~**Bookmarks system**: Save and load favorite locations~~ ✓ **IMPLEMENTED**
   - JSON-based bookmark files in `bookmarks/` directory
   - Save/load/rename/delete operations
   - Preview details before loading
   - Preset interesting locations included

6. ~~**Navigation history**: Back/forward through view changes~~ ✓ **IMPLEMENTED**
   - Browser-like history navigation
   - Keyboard shortcuts (Backspace/Shift+Backspace)
   - Tracks zoom, pan, and palette changes
   - Maximum 100 entries with auto-cleanup

7. ~~**Dynamic load balancing**: Use work queue instead of static row distribution (CPU mode)~~ ✓ **IMPLEMENTED**
   - Atomic counter-based work queue for dynamic row distribution
   - Eliminates thread idle time when rows have varying complexity
   - Particularly effective in high-contrast regions (boundary between set and escape regions)

8. **AVX-512**: Use 8-wide vectors on newer CPUs (2x over AVX2)
   - Double SIMD throughput: 8 pixels per vector instead of 4
   - Requires AVX-512 capable CPU (Intel Skylake-X or newer)

9. ~~**Smooth coloring**: Continuous iteration count for better gradients~~ ✓ **IMPLEMENTED**
   - Escape distance estimation using formula: `n + 1 - log(log(|z|)) / log(2)`
   - Eliminates color banding artifacts
   - Runtime toggle in UI, works with both GPU and CPU modes
   - Critical SIMD bug fix: preserves magnitude at escape time

10. **Perturbation theory**: Enable extreme zoom levels (> 1e15)
   - Use arbitrary precision + series approximation
   - Required for deep zoom beyond f64/f32 precision limits
   - More complex to implement in GPU shaders

11. **Compute shaders**: Upgrade from fragment shaders to compute shaders
   - Better control over parallelism and memory access patterns
   - Shared memory for optimization
   - Vulkan/WebGPU for cross-platform support

## References

- Mandelbrot set algorithm: [Wikipedia](https://en.wikipedia.org/wiki/Mandelbrot_set)
- Odin SIMD documentation: [core:simd package](https://pkg.odin-lang.org/core/simd/)
- Odin threading documentation: [core:thread package](https://pkg.odin-lang.org/core/thread/)
- Odin OpenGL bindings: [vendor:OpenGL package](https://pkg.odin-lang.org/vendor/OpenGL/)
- OpenGL shader programming: [LearnOpenGL](https://learnopengl.com/)
- GLSL reference: [OpenGL Shading Language](https://www.khronos.org/opengl/wiki/OpenGL_Shading_Language)
- Task parallelism patterns: Row-based domain decomposition
- Mouse interaction patterns: Standard fractal explorer UX
