# Export Progress Bar Implementation Plan

## Goal
Add a progress bar to image exports and run exports in a background thread to keep the UI responsive.

## Current State Analysis

### Export Flow (Synchronous)
1. **UI** (`ui/export_panel.odin:132-148`): User clicks "Export Image"
2. **Router** (`renderer/export.odin:export_image_compute`): Routes to 2D/3D export
3. **2D Export** (`renderer/export.odin:export_image_2d`):
   - Allocates pixel buffer
   - **CPU Computation** (`mb.Compute`) - Takes most time for CPU path
   - **PNG Encoding** (`app.export_image`) - Multi-threaded conversion + libpng
4. **3D Export** (`renderer/export.odin:export_image_3d`):
   - Creates framebuffer
   - **CPU Computation** (`mb.Compute`) - For height data
   - **3D Rendering** (GPU rendering to texture)
   - **PNG Encoding**

### GPU Compute Export Path
- Single GPU dispatch (very fast, <100ms for most resolutions)
- Hard to track detailed progress (atomic operation)
- Can track stages: "Computing..." → "Encoding..." → "Done"

### CPU Export Path
- Multi-threaded with dynamic work queue
- Row-by-row processing (8 threads grabbing rows atomically)
- Easy to track: `completed_rows / total_rows`
- PNG encoding also multi-threaded

### Current Issues
1. **Blocking**: Export runs on main thread, UI freezes
2. **No Progress**: Only shows "Exporting..." flag (line 155-158)
3. **No Cancellation**: Can't abort a long export
4. **Poor UX**: User has no idea how long export will take

## Implementation Plan

### Phase 1: Add Progress Tracking to CPU Computation

**Goal**: Track row completion during CPU Mandelbrot computation

**Files to Modify**:
- `mandelbrot/mandelbrot.odin` - Add progress tracking to work queue
- `app/app.odin` - Add export progress state

**Changes**:

1. **Extend Work_Queue** (`mandelbrot/mandelbrot.odin:11-15`):
```odin
Work_Queue :: struct {
    next_row:      int, // Atomic counter for next row to process
    total_rows:    int, // Total number of rows to process
    completed_rows: int, // NEW: Atomic counter for completed rows
    progress:      ^f32, // NEW: Optional pointer to progress (0.0-1.0)
}
```

2. **Update Worker Functions** (`mandelbrot/mandelbrot_scalar.odin`, `mandelbrot/mandelbrot_simd.odin`):
   - After completing each row, atomically increment `completed_rows`
   - If `progress` pointer is non-nil, update: `*progress = f32(completed_rows) / f32(total_rows)`

3. **Add Progress to App_State** (`app/app.odin:30-88`):
   - Already has `export_progress: f32` (line 75) ✓
   - Add `export_stage: Export_Stage` enum
   - Add `export_error: string` for error messages

4. **Export Stage Enum** (new in `app/app.odin`):
```odin
Export_Stage :: enum {
    Idle,       // Not exporting
    Computing,  // CPU/GPU computation in progress
    Encoding,   // PNG encoding in progress
    Completed,  // Export finished successfully
    Error,      // Export failed
}
```

### Phase 2: Thread the Export Operation

**Goal**: Run export in background thread so UI stays responsive

**Files to Modify**:
- `app/export.odin` - Add threaded export wrapper
- `renderer/export.odin` - Modify to accept progress callback
- `ui/export_panel.odin` - Trigger background export

**Implementation**:

1. **Export Thread Data** (new in `app/export.odin`):
```odin
import "core:thread"
import "core:sync"

Export_Thread_Data :: struct {
    // Input parameters
    state:             ^App_State,
    renderer:          ^renderer.Renderer,
    width:             int,
    height:            int,
    filepath:          string,
    compression_level: int,

    // Output/status (atomic access)
    progress:          f32,     // 0.0 to 1.0
    stage:             Export_Stage,
    success:           bool,
    error_message:     string,
}

export_thread_worker :: proc(t: ^thread.Thread) {
    data := cast(^Export_Thread_Data)t.data

    // Set stage to Computing
    sync.atomic_store(&data.stage, .Computing)

    // Allocate pixel buffer
    pixels := make([]u32, data.width * data.height)
    defer delete(pixels)

    // Create export state with progress tracking
    export_state := data.state^
    export_state.pixels = pixels
    export_state.export_progress = 0.0

    // Compute Mandelbrot (will update export_state.export_progress)
    mb.Compute(&export_state, data.width, data.height)

    // Copy final progress
    sync.atomic_store(&data.progress, export_state.export_progress)

    // Set stage to Encoding
    sync.atomic_store(&data.stage, .Encoding)
    sync.atomic_store(&data.progress, 0.5) // Encoding is ~50% of total

    // Save to file
    success := export_image(pixels, data.width, data.height, data.filepath, data.compression_level)

    // Set completion status
    sync.atomic_store(&data.success, success)
    sync.atomic_store(&data.progress, 1.0)
    sync.atomic_store(&data.stage, success ? .Completed : .Error)
}
```

2. **Start Background Export** (new in `app/export.odin`):
```odin
export_image_async :: proc(
    r: ^renderer.Renderer,
    state: ^App_State,
    width, height: int,
    filepath: string,
    compression_level: int = 1
) -> ^Export_Thread_Data {
    // Allocate thread data (caller must free after thread completes)
    data := new(Export_Thread_Data)
    data.state = state
    data.renderer = r
    data.width = width
    data.height = height
    data.filepath = filepath
    data.compression_level = compression_level
    data.progress = 0.0
    data.stage = .Idle

    // Create and start thread
    export_thread := thread.create(export_thread_worker)
    export_thread.data = data
    thread.start(export_thread)

    // Store thread handle in data for later joining
    data.thread_handle = export_thread

    return data
}
```

3. **Polling in Main Loop** (`appelman.odin` main loop):
   - If `state.export_in_progress`, poll the export thread data
   - Update `state.export_progress` and `state.export_stage`
   - When complete, join thread and cleanup

### Phase 3: Add Progress Bar UI

**Goal**: Display progress bar below Export button

**Files to Modify**:
- `ui/export_panel.odin` - Add progress bar rendering

**Implementation**:

Add after the "Export Image" button (`ui/export_panel.odin:132-158`):

```odin
// Progress bar (below export button)
if state.export_in_progress {
    imgui.Separator()

    // Stage text
    stage_text := "Idle"
    switch state.export_stage {
    case .Computing:
        stage_text = "Computing Mandelbrot..."
    case .Encoding:
        stage_text = "Encoding PNG..."
    case .Completed:
        stage_text = "✓ Export completed!"
    case .Error:
        stage_text = "✗ Export failed!"
    case .Idle:
        stage_text = "Starting..."
    }

    imgui.Text(stage_text)

    // Progress bar
    progress_text := fmt.ctprintf("%.0f%%", state.export_progress * 100.0)
    imgui.ProgressBar(state.export_progress, imgui.Vec2{-1, 0}, progress_text)

    // Show elapsed time (optional)
    elapsed := time.since(state.export_start_time)
    imgui.TextDisabled(fmt.ctprintf("Time: %.1fs", time.duration_seconds(elapsed)))

    // Cancel button (optional - Phase 4)
    if imgui.Button("Cancel Export", imgui.Vec2{-1, 0}) {
        // Set cancellation flag
        state.export_cancel_requested = true
    }
}
```

### Phase 4: Progress Tracking for GPU Compute Export

**Goal**: Show stage-based progress for GPU compute exports

**Files to Modify**:
- `renderer/export.odin:export_image_compute` - Update stage during export

**Implementation**:

GPU compute is very fast (<100ms typically), so detailed progress isn't as critical. Use stages:

```odin
export_image_compute :: proc(...) -> bool {
    state.export_stage = .Computing
    state.export_progress = 0.0

    // ... GPU setup ...

    state.export_progress = 0.25

    // Dispatch compute shader
    gl.DispatchCompute(groups_x, groups_y, 1)
    gl.MemoryBarrier(gl.SHADER_IMAGE_ACCESS_BARRIER_BIT)

    state.export_progress = 0.50
    state.export_stage = .Encoding

    // Read pixels and encode
    // ... pixel conversion ...

    state.export_progress = 0.75

    // Save PNG
    success := app.export_image(...)

    state.export_progress = 1.0
    state.export_stage = success ? .Completed : .Error

    return success
}
```

### Phase 5: PNG Encoding Progress (Optional)

**Goal**: Track progress during PNG encoding (minor improvement)

**Complexity**: Medium (requires libpng callback or chunked encoding)

**Benefit**: Small (encoding is relatively fast with level 1 compression)

**Recommendation**: Skip this phase initially, add only if needed

## Implementation Order

### Step 1: Add Progress State (30 min)
- Add `Export_Stage` enum to `app/app.odin`
- Add `export_stage` and `export_start_time` to `App_State`
- Initialize in main

### Step 2: Progress Tracking in CPU Computation (1 hour)
- Modify `Work_Queue` to track completed rows
- Update worker functions to increment completed rows
- Pass progress pointer through computation chain
- Test with synchronous exports

### Step 3: Progress Bar UI (30 min)
- Add progress bar rendering in `export_panel.odin`
- Add stage text display
- Test with synchronous exports (should see progress update)

### Step 4: Background Export Thread (2 hours)
- Create `Export_Thread_Data` structure
- Implement `export_thread_worker` function
- Implement `export_image_async` launcher
- Add polling in main loop
- Handle thread cleanup on completion
- Test with all export types

### Step 5: GPU Compute Stage Tracking (30 min)
- Add stage updates to `export_image_compute`
- Test GPU exports show stages

### Step 6: Polish & Error Handling (1 hour)
- Add error messages to UI
- Add export cancellation (optional)
- Handle edge cases (disk full, invalid filename, etc.)
- Add completion notification (optional)

## Total Estimated Time: 5-6 hours

## Testing Checklist

- [ ] 2D CPU export shows progress (row-by-row updates)
- [ ] 2D GPU compute export shows stages
- [ ] 3D export shows progress
- [ ] Progress bar updates smoothly (not jumpy)
- [ ] UI remains responsive during export
- [ ] Can navigate tabs during export
- [ ] Can adjust settings during export (but not trigger another export)
- [ ] Export completion shows success/error message
- [ ] Large exports (16K) show meaningful progress
- [ ] Small exports (1080p) complete quickly without flickering UI

## Benefits

1. **Responsive UI**: User can navigate tabs, view help, etc. during export
2. **Progress Feedback**: User knows how long export will take
3. **Professional UX**: Matches expectations of modern applications
4. **Cancellation**: (Optional) User can abort long exports
5. **Error Handling**: Clear feedback if export fails

## Risks & Mitigation

### Risk: Thread Safety
- **Mitigation**: Use atomic operations for all shared state
- Use `sync.atomic_store` and `sync.atomic_load`
- Keep shared state minimal (just progress, stage, success flag)

### Risk: OpenGL Context Thread Safety
- **Issue**: OpenGL contexts are not thread-safe
- **Mitigation**:
  - GPU compute exports must run on main thread
  - Only CPU computation can be threaded
  - Alternative: Use shared contexts (complex)

### Risk: Memory Management
- **Issue**: Thread allocations must be freed
- **Mitigation**: Clear ownership model, use defer for cleanup

## Alternative: Simpler Approach (If Time Constrained)

If full threading is too complex, implement a **simpler staged approach**:

1. Add progress tracking to CPU computation (Step 1-2)
2. Add progress bar UI (Step 3)
3. **Don't thread the export** - keep it synchronous
4. Use `imgui.GetIO().DeltaTime` to periodically yield to UI during export
5. Update progress in the Mandelbrot worker loop

**Pros**: Much simpler, fewer moving parts
**Cons**: UI still semi-responsive (can render but input may lag)

## Recommended Approach

**Start with Phase 1-3** (progress tracking + UI without threading):
- Proves the progress tracking works
- Shows value immediately
- Lower risk

**Then add Phase 4** (threading) once progress tracking is stable:
- Significantly better UX
- Worth the additional complexity
- Can be tested thoroughly

This incremental approach reduces risk and delivers value faster.
