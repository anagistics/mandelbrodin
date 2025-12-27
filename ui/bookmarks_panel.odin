package ui

import app "../app"
import renderer "../renderer"
import "core:fmt"
import "core:strings"
import imgui "vendor:imgui"

// Render just the content of the bookmarks panel (for use in tabs)
Render_bookmarks_panel_content :: proc(r: ^renderer.Renderer, state: ^app.App_State, width: int, height: int) {
// Saved views
imgui.Text("Bookmarks")
	imgui.Separator()

	// Save current view button
	if imgui.Button("Save Current View", imgui.Vec2{-1, 0}) {
		// Generate filename from timestamp
		filename := fmt.aprintf("view_%d", len(state.bookmarks) + 1)
		name := fmt.aprintf("View %d", len(state.bookmarks) + 1)

		// Pass camera if in 3D mode
		camera_ptr := &r.renderer_3d.camera if r.renderer_3d_available else nil

		// Pass renderer and export procedure for thumbnail generation
		app.save_bookmark(state, filename, name, camera_ptr, r, renderer.export_thumbnail)

		delete(filename)
		delete(name)
	}

	imgui.Separator()

	// Bookmarks list
	imgui.Text(fmt.ctprintf("Bookmarks: %d", len(state.bookmarks)))
	imgui.Separator()

	// Calculate height for scrollable region
	// Reserve space for preview section if a bookmark is selected
	preview_height: f32 = 0
	if state.selected_bookmark >= 0 && state.selected_bookmark < len(state.bookmarks) {
		preview_height = 140 // Approximate height for preview section
	}

	// Get available height and reserve space for preview
	available_height := imgui.GetContentRegionAvail().y - preview_height

	// Create scrollable child window for bookmarks list
	if imgui.BeginChild("BookmarksList", imgui.Vec2{0, available_height}, {.Borders}, {}) {
		// Display bookmarks
		for bookmark, i in state.bookmarks {
			is_selected := state.selected_bookmark == i
			is_editing := state.editing_bookmark == i
			display_name := bookmark.view.name if len(bookmark.view.name) > 0 else bookmark.filename

			if is_editing {
				// Show input field for editing
				imgui.SetKeyboardFocusHere()

				flags := imgui.InputTextFlags{.EnterReturnsTrue}
				if imgui.InputText(fmt.ctprintf("##edit_%d", i), cstring(raw_data(state.edit_buffer[:])), len(state.edit_buffer), flags) {
					// Enter pressed - save the new name
					new_name := strings.clone_from_cstring(cstring(raw_data(state.edit_buffer[:])))
					camera_ptr := &r.renderer_3d.camera if r.renderer_3d_available else nil
					app.update_bookmark_name(state, i, new_name, camera_ptr)
					delete(new_name)
					state.editing_bookmark = -1
				}

				// Check if Escape was pressed to cancel
				if imgui.IsKeyPressed(.Escape) {
					state.editing_bookmark = -1
				}

				// Cancel editing if clicked outside
				if !imgui.IsItemActive() && state.editing_bookmark == i {
					// Wait one frame before canceling to allow Enter to work
					if imgui.IsMouseClicked(.Left) {
						state.editing_bookmark = -1
					}
				}
			} else {
				// Display thumbnail before name
				thumbnail_clicked := false
				if bookmark.thumbnail.loaded && bookmark.thumbnail.texture_id != 0 {
					// Use ImageButton for clickable thumbnail
					if imgui.ImageButton(
						fmt.ctprintf("##thumbnail_%d", i),
						u64(bookmark.thumbnail.texture_id),
						imgui.Vec2{128, 96},
					) {
						thumbnail_clicked = true
					}
					imgui.SameLine()
					imgui.BeginGroup()
				} else {
					// Placeholder for missing thumbnail
					imgui.Dummy(imgui.Vec2{128, 96})
					// Check if placeholder was clicked
					if imgui.IsItemClicked(.Left) {
						thumbnail_clicked = true
					}
					imgui.SameLine()
					imgui.BeginGroup()
				}

				// Normal selectable item (or thumbnail was clicked)
				if imgui.Selectable(fmt.ctprintf("%s##%d", display_name, i), is_selected) || thumbnail_clicked {
					state.selected_bookmark = i
					camera_ptr := &r.renderer_3d.camera if r.renderer_3d_available else nil
					palette_corrected := app.apply_view(state, bookmark.view, camera_ptr)

					// If palette was corrected (fallback to default), save the correction
					if palette_corrected {
						fmt.printfln("Bookmark '%s' had invalid palette, correcting to default", bookmark.filename)
						if app.correct_bookmark_palette(state, bookmark.filename) {
							// Reload bookmarks to reflect the correction
							app.load_bookmarks(state)
							// Adjust selected index if needed (list may have reordered)
							state.selected_bookmark = i
						}
					}

					app.history_save(state)
					state.needs_recompute = true  // Force recompute when loading bookmark
				}

				imgui.EndGroup()

				// Detect double-click to enter edit mode
				if imgui.IsItemHovered() && imgui.IsMouseDoubleClicked(.Left) {
					state.editing_bookmark = i
					// Copy current name to edit buffer
					name_bytes := transmute([]u8)display_name
					copy_len := min(len(name_bytes), len(state.edit_buffer) - 1)
					copy(state.edit_buffer[:], name_bytes[:copy_len])
					state.edit_buffer[copy_len] = 0 // Null terminate
				}

				// Right-click context menu
				if imgui.BeginPopupContextItem(fmt.ctprintf("bookmark_ctx_%d", i)) {
					if imgui.MenuItem("Rename") {
						state.editing_bookmark = i
						// Copy current name to edit buffer
						name_bytes := transmute([]u8)display_name
						copy_len := min(len(name_bytes), len(state.edit_buffer) - 1)
						copy(state.edit_buffer[:], name_bytes[:copy_len])
						state.edit_buffer[copy_len] = 0 // Null terminate
					}
					if imgui.MenuItem("Delete") {
						app.delete_bookmark(state, i)
						state.selected_bookmark = -1
					}
					imgui.EndPopup()
				}
			}
		}
	}
	imgui.EndChild()

	// Preview of selected bookmark
	if state.selected_bookmark >= 0 && state.selected_bookmark < len(state.bookmarks) {
		imgui.Separator()
		imgui.Text("Preview")

		bookmark := &state.bookmarks[state.selected_bookmark]
		imgui.Text(fmt.ctprintf("Name: %s", bookmark.view.name))
		imgui.Text(fmt.ctprintf("Zoom: %.2f", bookmark.view.zoom))
		imgui.Text(fmt.ctprintf("Center: (%.6f, %.6f)", bookmark.view.center_x, bookmark.view.center_y))
		imgui.Text(fmt.ctprintf("Iterations: %d", bookmark.view.max_iterations))
		imgui.Text(fmt.ctprintf("Palette: %s", bookmark.view.palette))
	}
}

// Render bookmarks panel with its own window (for standalone use)
Render_bookmarks_panel :: proc(r: ^renderer.Renderer, state: ^app.App_State, mandelbrot_width: int, control_width: int, height: int) {
	panel_x := f32(mandelbrot_width + control_width)
	imgui.SetNextWindowPos(imgui.Vec2{panel_x, 0}, .Always)
	imgui.SetNextWindowSize(imgui.Vec2{300, f32(height)}, .Always)

	flags := imgui.WindowFlags{.NoCollapse, .NoMove, .NoResize}
	if imgui.Begin("Bookmarks", nil, flags) {
		Render_bookmarks_panel_content(r, state, 300, height)
	}
	imgui.End()
}
