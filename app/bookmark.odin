package app

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:time"

// View state for saving/loading
View_State :: struct {
	// 2D view parameters
	center_x:            f64 `json:"center_x"`,
	center_y:            f64 `json:"center_y"`,
	zoom:                f64 `json:"zoom"`,
	rotation:            f64 `json:"rotation"`,
	max_iterations:      u64 `json:"max_iterations"`,
	palette:             string `json:"palette"`,
	use_smooth_coloring: bool `json:"use_smooth_coloring"`,
	use_adaptive_coloring: bool `json:"use_adaptive_coloring,omitempty"`,

	// 3D view parameters
	render_mode:         string `json:"render_mode,omitempty"`, // "2D" or "3D"
	camera_azimuth:      f32 `json:"camera_azimuth,omitempty"`,
	camera_elevation:    f32 `json:"camera_elevation,omitempty"`,
	camera_distance:     f32 `json:"camera_distance,omitempty"`,
	camera_target_x:     f32 `json:"camera_target_x,omitempty"`,
	camera_target_y:     f32 `json:"camera_target_y,omitempty"`,
	camera_target_z:     f32 `json:"camera_target_z,omitempty"`,
	height_scale_3d:     f32 `json:"height_scale_3d,omitempty"`,
	column_width_3d:     f32 `json:"column_width_3d,omitempty"`,

	// Metadata
	name:                string `json:"name,omitempty"`,
	created_at:          string `json:"created_at,omitempty"`,
}

// Bookmark entry for UI display
Bookmark :: struct {
	filename: string,
	view:     View_State,
}

// Save current view to JSON file
// camera parameter should be ^Camera_3D from renderer package (passed as rawptr to avoid cyclic import)
save_view :: proc(state: ^App_State, filepath: string, name: string = "", camera: rawptr = nil) -> bool {
	// Determine render mode string
	mode_string := "2D"
	if state.render_mode == .Mode_3D {
		mode_string = "3D"
	}

	view := View_State {
		// 2D parameters
		center_x            = state.center_x,
		center_y            = state.center_y,
		zoom                = state.zoom,
		rotation            = state.rotation,
		max_iterations      = state.max_iterations,
		palette             = state.palette,
		use_smooth_coloring = state.use_smooth_coloring,
		use_adaptive_coloring = state.use_adaptive_coloring,

		// 3D parameters
		render_mode         = mode_string,
		height_scale_3d     = state.height_scale_3d,
		column_width_3d     = state.column_width_3d,

		// Metadata
		name                = name,
		created_at          = fmt.tprintf("%v", time.now()),
	}

	// Add camera parameters if provided
	// Note: This is a bit hacky - we receive rawptr to avoid cyclic import,
	// but we know it's ^Camera_3D from the renderer package
	if camera != nil {
		// We need to access Camera_3D fields, so we define a local struct matching its layout
		Camera_3D_Temp :: struct {
			position: [3]f32,
			azimuth: f32,
			elevation: f32,
			distance: f32,
			target: [3]f32,
			// ... other fields we don't need
		}
		cam := cast(^Camera_3D_Temp)camera
		view.camera_azimuth = cam.azimuth
		view.camera_elevation = cam.elevation
		view.camera_distance = cam.distance
		view.camera_target_x = cam.target.x
		view.camera_target_y = cam.target.y
		view.camera_target_z = cam.target.z
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
// camera parameter should be ^Camera_3D from renderer package (passed as rawptr to avoid cyclic import)
apply_view :: proc(state: ^App_State, view: View_State, camera: rawptr = nil) {
	// Apply 2D parameters
	state.center_x = view.center_x
	state.center_y = view.center_y
	state.zoom = view.zoom
	state.rotation = view.rotation
	state.max_iterations = view.max_iterations
	state.use_smooth_coloring = view.use_smooth_coloring
	state.use_adaptive_coloring = view.use_adaptive_coloring
	set_palette(state, view.palette)

	// Apply render mode
	if view.render_mode == "3D" {
		state.render_mode = .Mode_3D
	} else {
		state.render_mode = .Mode_2D
	}

	// Apply 3D parameters
	if view.height_scale_3d != 0 {
		state.height_scale_3d = view.height_scale_3d
	}
	if view.column_width_3d != 0 {
		state.column_width_3d = view.column_width_3d
	}

	// Apply camera parameters if provided
	if camera != nil && view.camera_distance != 0 {
		// We need to access Camera_3D fields, so we define a local struct matching its layout
		Camera_3D_Temp :: struct {
			position: [3]f32,
			azimuth: f32,
			elevation: f32,
			distance: f32,
			target: [3]f32,
			fov: f32,
			aspect: f32,
			near_plane: f32,
			far_plane: f32,
			view_matrix: matrix[4, 4]f32,
			projection_matrix: matrix[4, 4]f32,
			target_azimuth: f32,
			target_elevation: f32,
			target_distance: f32,
		}
		cam := cast(^Camera_3D_Temp)camera
		cam.azimuth = view.camera_azimuth
		cam.elevation = view.camera_elevation
		cam.distance = view.camera_distance
		cam.target = {view.camera_target_x, view.camera_target_y, view.camera_target_z}

		// Update target values for smooth interpolation
		cam.target_azimuth = view.camera_azimuth
		cam.target_elevation = view.camera_elevation
		cam.target_distance = view.camera_distance
	}
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
// camera parameter should be ^Camera_3D from renderer package (passed as rawptr to avoid cyclic import)
save_bookmark :: proc(state: ^App_State, filename: string, name: string = "", camera: rawptr = nil) {
	// Ensure .json extension
	filepath: string
	if len(filename) < 5 || filename[len(filename) - 5:] != ".json" {
		filepath = fmt.tprintf("%s/%s.json", state.bookmarks_dir, filename)
	} else {
		filepath = fmt.tprintf("%s/%s", state.bookmarks_dir, filename)
	}

	if save_view(state, filepath, name, camera) {
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
// camera parameter should be ^Camera_3D from renderer package (passed as rawptr to avoid cyclic import)
update_bookmark_name :: proc(state: ^App_State, index: int, new_name: string, camera: rawptr = nil) {
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

	// Save back to the same file (preserve camera data)
	if save_view(state, filepath, new_name, camera) {
		load_bookmarks(state) // Reload bookmarks to refresh the display
	}
}
