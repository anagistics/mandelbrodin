package ui

import app "../app"
import renderer "../renderer"
import imgui "vendor:imgui"

Render_tabbed_panel :: proc(r: ^renderer.Renderer, state: ^app.App_State, x_offset: int, width: int, height: int) {
	imgui.SetNextWindowPos(imgui.Vec2{f32(x_offset), 0}, .Once)
	imgui.SetNextWindowSize(imgui.Vec2{f32(width), f32(height) - 20}, .Once)

	flags := imgui.WindowFlags{.NoCollapse, .NoMove}
	if imgui.Begin("Control Panel", nil, flags) {
		// Create tab bar
		if imgui.BeginTabBar("MainTabs", {}) {
			// Controls tab
			tab_flags: imgui.TabItemFlags = state.active_tab == 0 ? {.SetSelected} : {}
			if imgui.BeginTabItem("Controls", nil, tab_flags) {
				if state.active_tab == 0 {
					state.active_tab = -1 // Clear the flag after it's been used
				}
				Render_control_panel_content(state, width, height)
				imgui.EndTabItem()
			}

			// Bookmarks tab
			tab_flags = state.active_tab == 1 ? {.SetSelected} : {}
			if imgui.BeginTabItem("Bookmarks", nil, tab_flags) {
				if state.active_tab == 1 {
					state.active_tab = -1 // Clear the flag after it's been used
				}
				Render_bookmarks_panel_content(r, state, width, height)
				imgui.EndTabItem()
			}

			// Export tab
			tab_flags = state.active_tab == 2 ? {.SetSelected} : {}
			if imgui.BeginTabItem("Export", nil, tab_flags) {
				if state.active_tab == 2 {
					state.active_tab = -1 // Clear the flag after it's been used
				}
				Render_export_panel_content(r, state, width, height)
				imgui.EndTabItem()
			}

			imgui.EndTabBar()
		}
	}
	imgui.End()
}
