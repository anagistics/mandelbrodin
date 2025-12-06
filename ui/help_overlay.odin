package ui

import app "../app"
import imgui "vendor:imgui"

// Render the help overlay showing all keyboard shortcuts
Render_help_overlay :: proc(state: ^app.App_State) {
	// Center the window on screen
	display_size := imgui.GetIO().DisplaySize
	window_width: f32 = 600
	window_height: f32 = 500
	window_pos := imgui.Vec2 {
		(display_size.x - window_width) * 0.5,
		(display_size.y - window_height) * 0.5,
	}

	imgui.SetNextWindowPos(window_pos, .Always)
	imgui.SetNextWindowSize(imgui.Vec2{window_width, window_height}, .Always)

	flags := imgui.WindowFlags{.NoCollapse, .NoResize, .NoMove}
	if imgui.Begin("Keyboard Shortcuts (Press F1 to close)", nil, flags) {
		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, "Navigation")
		imgui.Separator()
		imgui.Columns(2, "nav_cols", false)
		imgui.SetColumnWidth(0, 200)

		imgui.Text("Arrow Keys")
		imgui.NextColumn()
		imgui.TextDisabled("Pan view")
		imgui.NextColumn()

		imgui.Text("Shift + Arrow Keys")
		imgui.NextColumn()
		imgui.TextDisabled("Pan faster")
		imgui.NextColumn()

		imgui.Text("Page Up")
		imgui.NextColumn()
		imgui.TextDisabled("Zoom in")
		imgui.NextColumn()

		imgui.Text("Page Down")
		imgui.NextColumn()
		imgui.TextDisabled("Zoom out")
		imgui.NextColumn()

		imgui.Text(",")
		imgui.NextColumn()
		imgui.TextDisabled("Rotate counter-clockwise")
		imgui.NextColumn()

		imgui.Text(".")
		imgui.NextColumn()
		imgui.TextDisabled("Rotate clockwise")
		imgui.NextColumn()

		imgui.Columns(1)
		imgui.Spacing()

		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, "History")
		imgui.Separator()
		imgui.Columns(2, "history_cols", false)
		imgui.SetColumnWidth(0, 200)

		imgui.Text("Alt + Left")
		imgui.NextColumn()
		imgui.TextDisabled("Go back in history")
		imgui.NextColumn()

		imgui.Text("Alt + Right")
		imgui.NextColumn()
		imgui.TextDisabled("Go forward in history")
		imgui.NextColumn()

		imgui.Columns(1)
		imgui.Spacing()

		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, "Tabs")
		imgui.Separator()
		imgui.Columns(2, "tabs_cols", false)
		imgui.SetColumnWidth(0, 200)

		imgui.Text("Ctrl + 1")
		imgui.NextColumn()
		imgui.TextDisabled("Jump to Controls tab")
		imgui.NextColumn()

		imgui.Text("Ctrl + 2")
		imgui.NextColumn()
		imgui.TextDisabled("Jump to Bookmarks tab")
		imgui.NextColumn()

		imgui.Text("Ctrl + 3")
		imgui.NextColumn()
		imgui.TextDisabled("Jump to Export tab")
		imgui.NextColumn()

		imgui.Columns(1)
		imgui.Spacing()

		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, "Actions")
		imgui.Separator()
		imgui.Columns(2, "actions_cols", false)
		imgui.SetColumnWidth(0, 200)

		imgui.Text("Ctrl + S")
		imgui.NextColumn()
		imgui.TextDisabled("Export image")
		imgui.NextColumn()

		imgui.Text("F1")
		imgui.NextColumn()
		imgui.TextDisabled("Toggle this help")
		imgui.NextColumn()

		imgui.Text("ESC")
		imgui.NextColumn()
		imgui.TextDisabled("Quit application")
		imgui.NextColumn()

		imgui.Columns(1)
		imgui.Spacing()
		imgui.Separator()

		imgui.TextColored({0.4, 0.8, 1.0, 1.0}, "Mouse Controls")
		imgui.Separator()
		imgui.BulletText("Left Click: Recenter view")
		imgui.BulletText("Right Drag: Pan view")
		imgui.BulletText("Mouse Wheel: Zoom in/out")
		imgui.BulletText("Ctrl + Wheel: Rotate view")
		imgui.BulletText("Shift + Drag: Box zoom")

		imgui.Spacing()
		imgui.Separator()

		if imgui.Button("Close (F1)", imgui.Vec2{-1, 30}) {
			state.show_help = false
		}
	}
	imgui.End()
}
