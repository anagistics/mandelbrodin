package app

import visual "../visual"
import "core:fmt"
import "core:strings"
import "core:time"
import stbi "vendor:stb/image"

// Render mode (2D or 3D display)
Render_Mode :: enum {
	Mode_2D, // Flat pixel display (current)
	Mode_3D, // 3D column display (new)
}

// Export stage for progress tracking
Export_Stage :: enum {
	Idle,      // Not exporting
	Computing, // CPU/GPU computation in progress
	Encoding,  // PNG encoding in progress
	Completed, // Export finished successfully
	Error,     // Export failed
}

// Set the current palette by name, falling back to default if not found
// Returns true if fallback to default occurred
set_palette :: proc(state: ^App_State, palette_name: string) -> bool {
	palette, found := visual.find_palette(state.palettes[:], palette_name)
	if found {
		// Clone the palette name to ensure it persists
		if state.palette != palette_name {
			delete(state.palette) // Free old string if it was allocated
			state.palette = strings.clone(palette_name)
		}
		state.current_palette = palette
		state.needs_recompute = true
		return false // No fallback needed
	} else {
		fmt.eprintln("Warning: Palette not found:", palette_name, "- using default")
		delete(state.palette) // Free old string
		state.palette = strings.clone("Classic")
		state.current_palette = visual.DEFAULT_PALETTE
		state.needs_recompute = true
		return true // Fallback occurred
	}
}

App_State :: struct {
	pixels:              []u32,
	computation_time_ms: f64,
	zoom:                f64,
	center_x:            f64,
	center_y:            f64,
	rotation:            f64, // Rotation angle in radians
	max_iterations:      u64,
	needs_recompute:     bool,
	use_simd:            bool, // Toggle for SIMD vs scalar computation
	use_gpu:             bool, // Toggle for GPU vs CPU rendering
	use_smooth_coloring: bool, // Toggle for smooth coloring (continuous iteration)
	use_adaptive_coloring: bool, // Toggle for histogram-based adaptive coloring
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
	export_compression:  int, // PNG compression level (0-9, default 1)
	export_in_progress:  bool, // Flag indicating export is running
	export_progress:     f32, // Export progress 0.0 to 1.0
	export_stage:        Export_Stage, // Current export stage
	export_start_time:   time.Time, // When export started (for elapsed time display)
	export_error:        string, // Error message if export failed
	export_thread:       rawptr, // Background export thread data (nil if not running)
	// UI state
	active_tab:          int, // Currently active tab (0=Controls, 1=Bookmarks, 2=Export)
	show_help:           bool, // Toggle help overlay display
	// 3D Rendering
	render_mode:         Render_Mode, // 2D or 3D display mode
	height_scale_3d:     f32, // Height multiplier for 3D columns
	column_width_3d:     f32, // Width of 3D columns
	camera_3d_dragging:  bool, // Flag for 3D camera rotation drag (left button)
	camera_3d_panning:   bool, // Flag for 3D camera panning (right button)
	camera_drag_start_x: i32, // Mouse X at drag start
	camera_drag_start_y: i32, // Mouse Y at drag start
}
