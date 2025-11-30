package app

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:time"

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

// Convert palette type to string
palette_to_string :: proc(palette: Palette_Type) -> string {
	switch palette {
	case .Classic:     return "Classic"
	case .Fire:        return "Fire"
	case .Ice:         return "Ice"
	case .Ocean:       return "Ocean"
	case .Sunset:      return "Sunset"
	case .Grayscale:   return "Grayscale"
	case .Psychedelic: return "Psychedelic"
	}
	return "Classic"
}

// Convert string to palette type
string_to_palette :: proc(s: string) -> Palette_Type {
	switch s {
	case "Classic":     return .Classic
	case "Fire":        return .Fire
	case "Ice":         return .Ice
	case "Ocean":       return .Ocean
	case "Sunset":      return .Sunset
	case "Grayscale":   return .Grayscale
	case "Psychedelic": return .Psychedelic
	}
	return .Classic
}

// Save current view to JSON file
save_view :: proc(state: ^App_State, filepath: string, name: string = "") -> bool {
	view := View_State {
		center_x       = state.center_x,
		center_y       = state.center_y,
		zoom           = state.zoom,
		max_iterations = state.max_iterations,
		palette        = palette_to_string(state.palette),
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
	state.palette = string_to_palette(view.palette)
	state.needs_recompute = true
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
	// Bookmarks
	bookmarks:           [dynamic]Bookmark,
	bookmarks_dir:       string,
	selected_bookmark:   int, // Index of selected bookmark (-1 means none)
	editing_bookmark:    int, // Index of bookmark being edited (-1 means none)
	edit_buffer:         [256]u8, // Buffer for editing bookmark names
}
