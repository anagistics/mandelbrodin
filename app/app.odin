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

// Convert screen coordinates to world coordinates
screen_to_world :: proc(state: ^App_State, screen_x, screen_y: i32, width, height: int) -> (f64, f64) {
	scale := 3.5 / state.zoom
	offset_x := state.center_x - (1.75 / state.zoom)
	offset_y := state.center_y - (1.0 / state.zoom)

	world_x := f64(screen_x) / f64(width) * scale + offset_x
	world_y := f64(screen_y) / f64(height) * (2.0 / state.zoom) + offset_y

	return world_x, world_y
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
}
