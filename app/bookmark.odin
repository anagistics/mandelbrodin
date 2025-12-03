package app

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:time"

// View state for saving/loading
View_State :: struct {
	center_x:            f64 `json:"center_x"`,
	center_y:            f64 `json:"center_y"`,
	zoom:                f64 `json:"zoom"`,
	max_iterations:      u64 `json:"max_iterations"`,
	palette:             string `json:"palette"`,
	use_smooth_coloring: bool `json:"use_smooth_coloring"`,
	name:                string `json:"name,omitempty"`,
	created_at:          string `json:"created_at,omitempty"`,
}

// Bookmark entry for UI display
Bookmark :: struct {
	filename: string,
	view:     View_State,
}

// Save current view to JSON file
save_view :: proc(state: ^App_State, filepath: string, name: string = "") -> bool {
	view := View_State {
		center_x            = state.center_x,
		center_y            = state.center_y,
		zoom                = state.zoom,
		max_iterations      = state.max_iterations,
		palette             = state.palette,
		use_smooth_coloring = state.use_smooth_coloring,
		name                = name,
		created_at          = fmt.tprintf("%v", time.now()),
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
	state.use_smooth_coloring = view.use_smooth_coloring
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
		if len(name) < 5 || name[len(name) - 5:] != ".json" {
			continue
		}

		filepath := fmt.tprintf("%s/%s", state.bookmarks_dir, name)
		view, ok := load_view(filepath)
		if ok {
			bookmark := Bookmark {
				filename = fmt.aprintf("%s", name),
				view     = view,
			}
			append(&state.bookmarks, bookmark)
		}
	}
}

// Save current view as bookmark
save_bookmark :: proc(state: ^App_State, filename: string, name: string = "") {
	// Ensure .json extension
	filepath: string
	if len(filename) < 5 || filename[len(filename) - 5:] != ".json" {
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
