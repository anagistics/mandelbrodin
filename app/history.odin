package app

// History entry for navigation
History_Entry :: struct {
	center_x:            f64,
	center_y:            f64,
	zoom:                f64,
	rotation:            f64,
	max_iterations:      u64,
	palette:             string,
	use_smooth_coloring: bool,
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
		center_x            = state.center_x,
		center_y            = state.center_y,
		zoom                = state.zoom,
		rotation            = state.rotation,
		max_iterations      = state.max_iterations,
		palette             = state.palette,
		use_smooth_coloring = state.use_smooth_coloring,
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
	state.rotation = entry.rotation
	state.max_iterations = entry.max_iterations
	state.use_smooth_coloring = entry.use_smooth_coloring
	set_palette(state, entry.palette)
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
	state.rotation = entry.rotation
	state.max_iterations = entry.max_iterations
	state.use_smooth_coloring = entry.use_smooth_coloring
	set_palette(state, entry.palette)
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

// Clear history
clear_history :: proc(state: ^App_State) {
	clear(&state.history)
	state.history_index = -1
}
