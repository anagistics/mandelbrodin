package app

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import visual "../visual"
import stbi "vendor:stb/image"

// View state for saving/loading
View_State :: struct {
	center_x:       f64         `json:"center_x"`,
	center_y:       f64         `json:"center_y"`,
	zoom:           f64         `json:"zoom"`,
	max_iterations: u32         `json:"max_iterations"`,
	palette:        string      `json:"palette"`,
	name:           string      `json:"name,omitempty"`,
	created_at:     string      `json:"created_at,omitempty"`,
}

// Bookmark entry for UI display
Bookmark :: struct {
	filename: string,
	view:     View_State,
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

// Save current view to JSON file
save_view :: proc(state: ^App_State, filepath: string, name: string = "") -> bool {
	view := View_State {
		center_x       = state.center_x,
		center_y       = state.center_y,
		zoom           = state.zoom,
		max_iterations = state.max_iterations,
		palette        = state.palette,
		name           = name,
		created_at     = fmt.tprintf("%v", time.now()),
	}

	data, err := json.marshal(view, {pretty = true, use_spaces = true, spaces = 2})
	if err != nil {
		fmt.eprintln("Failed to marshal JSON:", err)
		return false
	}
	defer delete(data)

	success := os.write_entire_file(filepath, data)
	if !success {
		fmt.eprintln("Failed to write file:", filepath)
		return false
	}

	return true
}

// Load view from JSON file
load_view :: proc(filepath: string) -> (View_State, bool) {
	data, ok := os.read_entire_file(filepath)
	if !ok {
		fmt.eprintln("Failed to read file:", filepath)
		return {}, false
	}
	defer delete(data)

	view: View_State
	err := json.unmarshal(data, &view)
	if err != nil {
		fmt.eprintln("Failed to unmarshal JSON:", err)
		return {}, false
	}

	return view, true
}

// Apply loaded view to app state
apply_view :: proc(state: ^App_State, view: View_State) {
	state.center_x = view.center_x
	state.center_y = view.center_y
	state.zoom = view.zoom
	state.max_iterations = view.max_iterations
	set_palette(state, view.palette)
}

// Load all bookmarks from directory
load_bookmarks :: proc(state: ^App_State) {
	// Clear existing bookmarks
	for &bookmark in state.bookmarks {
		delete(bookmark.filename)
		delete(bookmark.view.name)
		delete(bookmark.view.created_at)
		delete(bookmark.view.palette)
	}
	clear(&state.bookmarks)

	// Ensure bookmarks directory exists
	os.make_directory(state.bookmarks_dir)

	// Read directory
	dir_handle, err := os.open(state.bookmarks_dir)
	if err != 0 {
		fmt.eprintln("Failed to open bookmarks directory:", state.bookmarks_dir)
		return
	}
	defer os.close(dir_handle)

	file_infos, read_err := os.read_dir(dir_handle, -1)
	if read_err != 0 {
		fmt.eprintln("Failed to read bookmarks directory")
		return
	}
	defer os.file_info_slice_delete(file_infos)

	// Load each .json file
	for info in file_infos {
		if info.is_dir {
			continue
		}

		// Check if file ends with .json
		name := info.name
		if len(name) < 5 || name[len(name)-5:] != ".json" {
			continue
		}

		filepath := fmt.tprintf("%s/%s", state.bookmarks_dir, name)
		view, ok := load_view(filepath)
		if ok {
			bookmark := Bookmark {
				filename = fmt.aprintf("%s", name),
				view = view,
			}
			append(&state.bookmarks, bookmark)
		}
	}
}

// Save current view as bookmark
save_bookmark :: proc(state: ^App_State, filename: string, name: string = "") {
	// Ensure .json extension
	filepath: string
	if len(filename) < 5 || filename[len(filename)-5:] != ".json" {
		filepath = fmt.tprintf("%s/%s.json", state.bookmarks_dir, filename)
	} else {
		filepath = fmt.tprintf("%s/%s", state.bookmarks_dir, filename)
	}

	if save_view(state, filepath, name) {
		load_bookmarks(state) // Reload bookmarks
	}
}

// Delete a bookmark
delete_bookmark :: proc(state: ^App_State, index: int) {
	if index < 0 || index >= len(state.bookmarks) {
		return
	}

	filepath := fmt.tprintf("%s/%s", state.bookmarks_dir, state.bookmarks[index].filename)
	os.remove(filepath)
	load_bookmarks(state) // Reload bookmarks
}

// Update a bookmark's name
update_bookmark_name :: proc(state: ^App_State, index: int, new_name: string) {
	if index < 0 || index >= len(state.bookmarks) {
		return
	}

	bookmark := &state.bookmarks[index]
	filepath := fmt.tprintf("%s/%s", state.bookmarks_dir, bookmark.filename)

	// Load the existing view
	view, ok := load_view(filepath)
	if !ok {
		return
	}

	// Update the name
	view.name = new_name

	// Save back to the same file
	if save_view(state, filepath, new_name) {
		load_bookmarks(state) // Reload bookmarks to refresh the display
	}
}

// Load all palettes from directory
load_palettes_from_dir :: proc(state: ^App_State) {
	state.palettes = visual.load_palettes(state.palettes_dir)

	if len(state.palettes) == 0 {
		fmt.eprintln("Warning: No palettes loaded, using default palette")
		state.palette = "Classic"
		state.current_palette = visual.DEFAULT_PALETTE
	}
}

// Set the current palette by name
set_palette :: proc(state: ^App_State, palette_name: string) {
	// Try to find the palette
	palette, found := visual.find_palette(state.palettes[:], palette_name)
	if found {
		state.palette = palette_name
		state.current_palette = palette
		state.needs_recompute = true
	} else {
		fmt.eprintln("Warning: Palette not found:", palette_name, "- using default")
		state.palette = "Classic"
		state.current_palette = visual.DEFAULT_PALETTE
		state.needs_recompute = true
	}
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

// Export resolution presets
Export_Resolution :: struct {
	name:   string,
	width:  int,
	height: int,
}

EXPORT_RESOLUTIONS := []Export_Resolution{
	{"1920x1080 (Full HD)", 1920, 1080},
	{"2560x1440 (QHD)", 2560, 1440},
	{"3840x2160 (4K)", 3840, 2160},
	{"5120x2880 (5K)", 5120, 2880},
	{"7680x4320 (8K)", 7680, 4320},
	{"15360x8640 (16K)", 15360, 8640},
}

// Save PNG image using stb_image_write
save_png :: proc(pixels: []u32, width, height: int, filepath: string) -> bool {
	// Convert ARGB to RGB (stb_image_write expects RGB or RGBA)
	rgb_data := make([]u8, width * height * 3)
	defer delete(rgb_data)

	for i in 0 ..< width * height {
		pixel := pixels[i]
		r := u8((pixel >> 16) & 0xFF)
		g := u8((pixel >> 8) & 0xFF)
		b := u8(pixel & 0xFF)

		rgb_data[i * 3 + 0] = r
		rgb_data[i * 3 + 1] = g
		rgb_data[i * 3 + 2] = b
	}

	// Write PNG file
	filepath_cstr := strings.clone_to_cstring(filepath)
	defer delete(filepath_cstr)

	result := stbi.write_png(
		filepath_cstr,
		i32(width),
		i32(height),
		3, // RGB channels
		raw_data(rgb_data),
		i32(width * 3), // stride
	)

	if result == 0 {
		fmt.eprintln("Failed to write PNG:", filepath)
		return false
	}

	fmt.println("Exported image to:", filepath)
	return true
}

// Export current view to image file at specified resolution
// Note: Compute function must be called from outside to avoid circular import
export_image :: proc(pixels: []u32, width, height: int, filepath: string) -> bool {
	fmt.printfln("Saving %dx%d image to %s...", width, height, filepath)

	// Save to PNG
	success := save_png(pixels, width, height, filepath)

	return success
}
