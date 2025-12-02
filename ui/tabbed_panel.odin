package ui

import app "../app"
import imgui "vendor:imgui"

Render_tabbed_panel :: proc(state: ^app.App_State, x_offset: int, width: int, height: int) {
	imgui.SetNextWindowPos(imgui.Vec2{f32(x_offset), 0}, .Once)
	imgui.SetNextWindowSize(imgui.Vec2{f32(width), f32(height) - 20}, .Once)

	flags := imgui.WindowFlags{.NoCollapse, .NoMove}
	if imgui.Begin("Control Panel", nil, flags) {
		// Create tab bar
		if imgui.BeginTabBar("MainTabs", {}) {
			// Controls tab
			if imgui.BeginTabItem("Controls", nil, {}) {
				Render_control_panel_content(state, width, height)
				imgui.EndTabItem()
			}

			// Bookmarks tab
			if imgui.BeginTabItem("Bookmarks", nil, {}) {
				Render_bookmarks_panel_content(state, width, height)
				imgui.EndTabItem()
			}

			// Export tab
			if imgui.BeginTabItem("Export", nil, {}) {
				Render_export_panel_content(state, width, height)
				imgui.EndTabItem()
			}

			imgui.EndTabBar()
		}
	}
	imgui.End()
}
