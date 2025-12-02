package app

import visual "../visual"
import "core:fmt"
import "core:strings"
import "core:time"
import stbi "vendor:stb/image"

// Convert screen coordinates to world coordinates
screen_to_world :: proc(
	state: ^App_State,
	screen_x, screen_y: i32,
	width, height: int,
) -> (
	f64,
	f64,
) {
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
	use_gpu:             bool, // Toggle for GPU vs CPU rendering
	palette:             string, // Current color palette name
	current_palette:     visual.Gradient_Palette, // Current palette gradient data
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
	scrolling_active:    bool, // Flag to track if mouse wheel scrolling is in progress
	last_scroll_time:    time.Time, // Timestamp of last scroll event
	// History navigation
	history:             [dynamic]History_Entry,
	history_index:       int, // Current position in history (-1 means no history)
	navigating_history:  bool, // Flag to prevent saving during history navigation
	// Bookmarks
	bookmarks:           [dynamic]Bookmark,
	bookmarks_dir:       string,
	selected_bookmark:   int, // Index of selected bookmark (-1 means none)
	editing_bookmark:    int, // Index of bookmark being edited (-1 means none)
	edit_buffer:         [256]u8, // Buffer for editing bookmark names
	// Palettes
	palettes:            [dynamic]visual.Loaded_Palette,
	palettes_dir:        string,
	// Export
	export_resolution:   int, // Index of selected export resolution
	export_filename:     string, // Export filename
	export_in_progress:  bool, // Flag indicating export is running
	export_progress:     f32, // Export progress 0.0 to 1.0
}
