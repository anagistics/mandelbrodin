package ui

import app "../app"
import "core:fmt"
import imgui "vendor:imgui"

Render_bookmarks_panel :: proc(state: ^app.App_State, mandelbrot_width: int, control_width: int, height: int) {
	panel_x := f32(mandelbrot_width + control_width)
	imgui.SetNextWindowPos(imgui.Vec2{panel_x, 0}, .Always)
	imgui.SetNextWindowSize(imgui.Vec2{300, f32(height)}, .Always)

	flags := imgui.WindowFlags{.NoCollapse, .NoMove, .NoResize}
	if imgui.Begin("Bookmarks", nil, flags) {
		// Preset locations
		imgui.Text("Interesting Locations")
		imgui.Separator()

		if imgui.Button("Default View", imgui.Vec2{-1, 0}) {
			app.history_save(state)
			state.center_x = -0.5
			state.center_y = 0.0
			state.zoom = 1.0
			state.needs_recompute = true
		}

		if imgui.Button("Seahorse Valley", imgui.Vec2{-1, 0}) {
			app.history_save(state)
			state.center_x = -0.743643887037151
			state.center_y = 0.131825904205330
			state.zoom = 50.0
			state.needs_recompute = true
		}

		if imgui.Button("Elephant Valley", imgui.Vec2{-1, 0}) {
			app.history_save(state)
			state.center_x = 0.3245046418497685
			state.center_y = 0.04855101129280834
			state.zoom = 100.0
			state.needs_recompute = true
		}

		if imgui.Button("Spiral", imgui.Vec2{-1, 0}) {
			app.history_save(state)
			state.center_x = -0.7269
			state.center_y = 0.1889
			state.zoom = 30.0
			state.needs_recompute = true
		}

		imgui.Separator()

		// Saved views
		imgui.Text("Saved Views")
		imgui.Separator()

		// Save current view button
		if imgui.Button("Save Current View", imgui.Vec2{-1, 0}) {
			// Generate filename from timestamp
			filename := fmt.aprintf("view_%d", len(state.bookmarks) + 1)
			name := fmt.aprintf("View %d", len(state.bookmarks) + 1)
			app.save_bookmark(state, filename, name)
			delete(filename)
			delete(name)
		}

		imgui.Separator()

		// Bookmarks list
		imgui.Text(fmt.ctprintf("Bookmarks: %d", len(state.bookmarks)))
		imgui.Separator()

		// Display bookmarks
		for bookmark, i in state.bookmarks {
			// Selectable item
			is_selected := state.selected_bookmark == i
			display_name := bookmark.view.name if len(bookmark.view.name) > 0 else bookmark.filename

			if imgui.Selectable(fmt.ctprintf("%s##%d", display_name, i), is_selected) {
				state.selected_bookmark = i
				app.apply_view(state, bookmark.view)
				app.history_save(state)
			}

			// Right-click context menu
			if imgui.BeginPopupContextItem(fmt.ctprintf("bookmark_ctx_%d", i)) {
				if imgui.MenuItem("Delete") {
					app.delete_bookmark(state, i)
					state.selected_bookmark = -1
				}
				imgui.EndPopup()
			}
		}

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
	imgui.End()
}
