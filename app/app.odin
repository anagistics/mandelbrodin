package app

// Palette types
Palette_Type :: enum {
	Classic,
	Fire,
	Ice,
	Ocean,
	Sunset,
	Grayscale,
	Psychedelic,
}

// Color stop for gradient
Color_Stop :: struct {
	position: f64, // 0.0 to 1.0
	r:        u8,
	g:        u8,
	b:        u8,
}

// Gradient palette definition
Gradient_Palette :: struct {
	stops: []Color_Stop,
}

// History entry for navigation
History_Entry :: struct {
	center_x:       f64,
	center_y:       f64,
	zoom:           f64,
	max_iterations: u32,
	palette:        Palette_Type,
}

// Convert screen coordinates to world coordinates
screen_to_world :: proc(state: ^App_State, screen_x, screen_y: i32, width, height: int) -> (f64, f64) {
	scale := 3.5 / state.zoom
	offset_x := state.center_x - (1.75 / state.zoom)
	offset_y := state.center_y - (1.0 / state.zoom)

	world_x := f64(screen_x) / f64(width) * scale + offset_x
	world_y := f64(screen_y) / f64(height) * (2.0 / state.zoom) + offset_y

	return world_x, world_y
}

// Save current state to history
history_save :: proc(state: ^App_State) {
	// Don't save if we're navigating through history
	if state.navigating_history {
		return
	}

	// If we're not at the end of history, remove everything after current position
	if state.history_index >= 0 && state.history_index < len(state.history) - 1 {
		resize(&state.history, state.history_index + 1)
	}

	// Create new history entry
	entry := History_Entry {
		center_x       = state.center_x,
		center_y       = state.center_y,
		zoom           = state.zoom,
		max_iterations = state.max_iterations,
		palette        = state.palette,
	}

	// Add to history
	append(&state.history, entry)
	state.history_index = len(state.history) - 1

	// Limit history size to 100 entries
	MAX_HISTORY :: 100
	if len(state.history) > MAX_HISTORY {
		// Remove oldest entry
		ordered_remove(&state.history, 0)
		state.history_index -= 1
	}
}

// Navigate back in history
history_back :: proc(state: ^App_State) -> bool {
	if state.history_index <= 0 {
		return false
	}

	state.history_index -= 1
	entry := state.history[state.history_index]

	state.navigating_history = true
	state.center_x = entry.center_x
	state.center_y = entry.center_y
	state.zoom = entry.zoom
	state.max_iterations = entry.max_iterations
	state.palette = entry.palette
	state.needs_recompute = true
	state.navigating_history = false

	return true
}

// Navigate forward in history
history_forward :: proc(state: ^App_State) -> bool {
	if state.history_index < 0 || state.history_index >= len(state.history) - 1 {
		return false
	}

	state.history_index += 1
	entry := state.history[state.history_index]

	state.navigating_history = true
	state.center_x = entry.center_x
	state.center_y = entry.center_y
	state.zoom = entry.zoom
	state.max_iterations = entry.max_iterations
	state.palette = entry.palette
	state.needs_recompute = true
	state.navigating_history = false

	return true
}

// Check if we can go back
can_go_back :: proc(state: ^App_State) -> bool {
	return state.history_index > 0
}

// Check if we can go forward
can_go_forward :: proc(state: ^App_State) -> bool {
	return state.history_index >= 0 && state.history_index < len(state.history) - 1
}

App_State :: struct {
	pixels:              []u32,
	computation_time_ms: f64,
	zoom:                f64,
	center_x:            f64,
	center_y:            f64,
	max_iterations:      u32,
	needs_recompute:     bool,
	use_simd:            bool, // Toggle for SIMD vs scalar computation
	use_gpu:             bool, // Toggle for GPU vs CPU rendering
	palette:             Palette_Type, // Current color palette
	// Mouse interaction state
	mouse_dragging:      bool,
	drag_start_x:        f64,
	drag_start_y:        f64,
	center_at_drag:      [2]f64,
	box_zoom_active:     bool,
	box_start_x:         i32,
	box_start_y:         i32,
	box_end_x:           i32,
	box_end_y:           i32,
	// History navigation
	history:             [dynamic]History_Entry,
	history_index:       int, // Current position in history (-1 means no history)
	navigating_history:  bool, // Flag to prevent saving during history navigation
}
