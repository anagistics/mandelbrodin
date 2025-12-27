package app

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import stbi "vendor:stb/image"
import gl "vendor:OpenGL"

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

// Thumbnail data for visual bookmark preview
Bookmark_Thumbnail :: struct {
	texture_id: u32,     // OpenGL texture handle (0 if not loaded)
	width:      i32,     // Thumbnail dimensions (128)
	height:     i32,     // Thumbnail dimensions (96)
	filepath:   string,  // Path to .png file
	loaded:     bool,    // Whether texture is currently loaded on GPU
}

// Bookmark entry for UI display
Bookmark :: struct {
	filename:  string,
	view:      View_State,
	thumbnail: Bookmark_Thumbnail,  // Thumbnail preview
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

// Thumbnail export procedure type (to avoid cyclic imports)
Thumbnail_Export_Proc :: #type proc(renderer: rawptr, state: ^App_State, width, height: int, filepath: string) -> bool

// Generate thumbnail for bookmark at 128×96 resolution
// export_proc should be renderer.export_thumbnail (passed to avoid cyclic import)
generate_bookmark_thumbnail :: proc(
	state: ^App_State,
	bookmark_name: string,
	r: rawptr,  // ^renderer.Renderer
	export_proc: Thumbnail_Export_Proc,
) -> string {
	THUMBNAIL_WIDTH :: 128
	THUMBNAIL_HEIGHT :: 96

	thumbnail_path := fmt.tprintf("%s/%s.png", state.bookmarks_dir, bookmark_name)

	if r != nil && export_proc != nil {
		success := export_proc(r, state, THUMBNAIL_WIDTH, THUMBNAIL_HEIGHT, thumbnail_path)

		if success {
			return thumbnail_path
		} else {
			fmt.eprintln("Warning: Failed to generate thumbnail for:", bookmark_name)
		}
	}

	return ""
}

// Load thumbnail PNG and upload to GPU texture
load_thumbnail :: proc(thumbnail: ^Bookmark_Thumbnail) -> bool {
	if !os.exists(thumbnail.filepath) {
		return false
	}

	// Load PNG using stb_image
	width, height, channels: i32
	filepath_cstr := strings.clone_to_cstring(thumbnail.filepath)
	defer delete(filepath_cstr)

	pixels := stbi.load(filepath_cstr, &width, &height, &channels, 4) // Force RGBA
	if pixels == nil {
		return false
	}
	defer stbi.image_free(pixels)

	// Create OpenGL texture
	gl.GenTextures(1, &thumbnail.texture_id)
	gl.BindTexture(gl.TEXTURE_2D, thumbnail.texture_id)

	// Set texture parameters
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

	// Upload to GPU
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, pixels)

	// Store dimensions and mark as loaded
	thumbnail.width = width
	thumbnail.height = height
	thumbnail.loaded = true

	return true
}

// Unload thumbnail from GPU
unload_thumbnail :: proc(thumbnail: ^Bookmark_Thumbnail) {
	if thumbnail.texture_id != 0 {
		gl.DeleteTextures(1, &thumbnail.texture_id)
		thumbnail.texture_id = 0
	}
	thumbnail.loaded = false
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
// Returns true if palette was corrected (fallback to default occurred)
apply_view :: proc(state: ^App_State, view: View_State, camera: rawptr = nil) -> bool {
	// Apply 2D parameters
	state.center_x = view.center_x
	state.center_y = view.center_y
	state.zoom = view.zoom
	state.rotation = view.rotation
	state.max_iterations = view.max_iterations
	state.use_smooth_coloring = view.use_smooth_coloring
	state.use_adaptive_coloring = view.use_adaptive_coloring
	palette_corrected := set_palette(state, view.palette)

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

	return palette_corrected
}

// Correct the palette in a bookmark file to use the current palette
// This is used when a bookmark references a non-existent palette
correct_bookmark_palette :: proc(state: ^App_State, bookmark_filename: string) -> bool {
	filepath := fmt.tprintf("%s/%s", state.bookmarks_dir, bookmark_filename)

	// Load the existing view
	view, ok := load_view(filepath)
	if !ok {
		fmt.eprintln("Failed to load bookmark for correction:", bookmark_filename)
		return false
	}

	// Update the palette to the current (corrected) palette
	old_palette := view.palette
	view.palette = state.palette

	// Save the corrected view back to the file
	// Use save_view with the existing metadata
	data, err := json.marshal(view, {pretty = true, use_spaces = true, spaces = 2})
	if err != nil {
		fmt.eprintln("Failed to marshal corrected bookmark:", err)
		return false
	}
	defer delete(data)

	success := os.write_entire_file(filepath, data)
	if !success {
		fmt.eprintln("Failed to write corrected bookmark:", filepath)
		return false
	}

	fmt.printfln("Corrected bookmark '%s': palette '%s' -> '%s'", bookmark_filename, old_palette, state.palette)
	return true
}

// Load all bookmarks from directory
load_bookmarks :: proc(state: ^App_State) {
	// Clear existing bookmarks
	for &bookmark in state.bookmarks {
		delete(bookmark.filename)
		delete(bookmark.view.name)
		delete(bookmark.view.created_at)
		delete(bookmark.view.palette)
		unload_thumbnail(&bookmark.thumbnail)
		delete(bookmark.thumbnail.filepath)
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
			// Extract bookmark name (without .json extension)
			bookmark_name := name[:len(name) - 5]
			thumbnail_path := fmt.tprintf("%s/%s.png", state.bookmarks_dir, bookmark_name)

			bookmark := Bookmark {
				filename = fmt.aprintf("%s", name),
				view     = view,
				thumbnail = Bookmark_Thumbnail {
					texture_id = 0,
					width      = 128,
					height     = 96,
					filepath   = fmt.aprintf("%s", thumbnail_path),
					loaded     = false,
				},
			}

			// Try to load thumbnail (silent failure if missing)
			load_thumbnail(&bookmark.thumbnail)

			append(&state.bookmarks, bookmark)
		}
	}
}

// Save current view as bookmark
// camera parameter should be ^Camera_3D from renderer package (passed as rawptr to avoid cyclic import)
// renderer parameter should be ^renderer.Renderer (passed as rawptr to avoid cyclic import)
// export_proc should be renderer.export_thumbnail (passed to avoid cyclic import)
save_bookmark :: proc(state: ^App_State, filename: string, name: string = "", camera: rawptr = nil, renderer: rawptr = nil, export_proc: Thumbnail_Export_Proc = nil) {
	// Ensure .json extension
	filepath: string
	bookmark_name: string

	if len(filename) < 5 || filename[len(filename) - 5:] != ".json" {
		filepath = fmt.tprintf("%s/%s.json", state.bookmarks_dir, filename)
		bookmark_name = filename
	} else {
		filepath = fmt.tprintf("%s/%s", state.bookmarks_dir, filename)
		bookmark_name = filename[:len(filename) - 5]
	}

	if save_view(state, filepath, name, camera) {
		// Generate thumbnail after successful save
		if renderer != nil && export_proc != nil {
			generate_bookmark_thumbnail(state, bookmark_name, renderer, export_proc)
		}

		load_bookmarks(state) // Reload bookmarks
	}
}

// Delete a bookmark
delete_bookmark :: proc(state: ^App_State, index: int) {
	if index < 0 || index >= len(state.bookmarks) {
		return
	}

	bookmark := &state.bookmarks[index]

	// Delete JSON file
	filepath := fmt.tprintf("%s/%s", state.bookmarks_dir, bookmark.filename)
	os.remove(filepath)

	// Delete thumbnail PNG file
	if len(bookmark.thumbnail.filepath) > 0 {
		os.remove(bookmark.thumbnail.filepath)
	}

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

// Regenerate thumbnail for existing bookmark
// Loads the bookmark, renders it, and saves new thumbnail
// renderer parameter should be ^renderer.Renderer (passed as rawptr to avoid cyclic import)
// export_proc should be renderer.export_thumbnail (passed to avoid cyclic import)
regenerate_bookmark_thumbnail :: proc(
	state: ^App_State,
	index: int,
	renderer: rawptr,
	export_proc: Thumbnail_Export_Proc,
) -> bool {
	if index < 0 || index >= len(state.bookmarks) {
		return false
	}

	bookmark := &state.bookmarks[index]

	// Extract bookmark name from filename
	name := bookmark.filename
	if len(name) >= 5 && name[len(name) - 5:] == ".json" {
		name = name[:len(name) - 5]
	}

	// Generate new thumbnail
	thumbnail_path := generate_bookmark_thumbnail(state, name, renderer, export_proc)

	if len(thumbnail_path) > 0 {
		// Reload thumbnail
		unload_thumbnail(&bookmark.thumbnail)
		delete(bookmark.thumbnail.filepath)
		bookmark.thumbnail.filepath = fmt.aprintf("%s", thumbnail_path)
		load_thumbnail(&bookmark.thumbnail)
		return true
	}

	return false
}
