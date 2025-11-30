package ui

import app "../app"
import visual "../visual"
import "core:fmt"
import "core:strings"
import imgui "vendor:imgui"

Render_control_panel :: proc(state: ^app.App_State, width: int, height: int) {
	topRightControl := imgui.Vec2{f32(width), 0}
	bottomLeftControl := imgui.Vec2{0, f32(height)}
	imgui.SetNextWindowPos(imgui.Vec2{f32(width), 0}, .Once)
	imgui.SetNextWindowSize(imgui.Vec2{300, f32(height) - 20}, .Once)

	flags := imgui.WindowFlags{.NoCollapse, .NoMove}
	if imgui.Begin("Controls", nil, flags) {
		imgui.Text("Mandelbrot Set Explorer")
		imgui.Separator()

		// Current cursor coordinates
		mousePos := imgui.GetMousePos()
		imgui.Text("Mouse X:")
		if mousePos.x >= bottomLeftControl.x && mousePos.x <= topRightControl.x {
			imgui.Text(fmt.ctprintf("%.2f", mousePos.x))
		} else {
			imgui.Text("...")
		}
		imgui.Text("Mouse Y:")
		if mousePos.y <= bottomLeftControl.y && mousePos.y >= topRightControl.y {
			imgui.Text(fmt.ctprintf("%.2f", mousePos.y))
		} else {
			imgui.Text("...")
		}

		// Performance info
		imgui.Text("Computation Time:")
		time_str := fmt.ctprintf("  %.2f ms", state.computation_time_ms)
		imgui.Text(time_str)

		// Rendering mode toggles
		if imgui.Checkbox("Use GPU", &state.use_gpu) {
			state.needs_recompute = true
		}
		if imgui.IsItemHovered() {
			imgui.SetTooltip("Toggle GPU shader vs CPU computation")
		}

		// SIMD toggle (only relevant in CPU mode)
		if !state.use_gpu {
			if imgui.Checkbox("Use SIMD", &state.use_simd) {
				state.needs_recompute = true
			}
			if imgui.IsItemHovered() {
				imgui.SetTooltip("Toggle SIMD vectorization (AVX 4-wide)")
			}
		} else {
			imgui.TextDisabled("SIMD (CPU only)")
		}

		imgui.Separator()

		// Palette selection
		imgui.Text("Color Palette")
		palette_names := [?]string {
			"Classic",
			"Fire",
			"Ice",
			"Ocean",
			"Sunset",
			"Grayscale",
			"Psychedelic",
		}
		current_palette := i32(state.palette)
		str_builder := strings.builder_make()
		defer strings.builder_destroy(&str_builder)
		for name in palette_names {
			strings.write_string(&str_builder, name)
			strings.write_byte(&str_builder, 0)
		}
		palette_options := strings.to_cstring(&str_builder)
		if imgui.Combo("##palette", &current_palette, palette_options, i32(len(palette_names))) {
			state.palette = visual.Palette_Type(current_palette)
			state.needs_recompute = true
		}

		imgui.Separator()

		// Save/Load buttons
		imgui.Text("Save/Load")
		if imgui.Button("Save View...") {
			// TODO: Open file dialog
			// For now, save to default location
			app.save_view(state, "saved_view.json", "Saved View")
		}
		imgui.SameLine(0, -1)
		if imgui.Button("Load View...") {
			// TODO: Open file dialog
			// For now, try to load from default location
			view, ok := app.load_view("saved_view.json")
			if ok {
				app.apply_view(state, view)
				app.history_save(state)
			}
		}

		imgui.Separator()

		// History navigation
		imgui.Text("Navigation History")

		// Back button
		can_back := app.can_go_back(state)
		if !can_back {
			imgui.BeginDisabled()
		}
		if imgui.Button("< Back") {
			app.history_back(state)
		}
		if !can_back {
			imgui.EndDisabled()
		}

		imgui.SameLine(0, -1)

		// Forward button
		can_forward := app.can_go_forward(state)
		if !can_forward {
			imgui.BeginDisabled()
		}
		if imgui.Button("Forward >") {
			app.history_forward(state)
		}
		if !can_forward {
			imgui.EndDisabled()
		}

		// History counter (1-based)
		imgui.SameLine(0, -1)
		history_count := len(state.history)
		has_history := history_count > 0
		if has_history {
			current_pos := state.history_index + 1 // Convert to 1-based
			counter_text := fmt.ctprintf("%d/%d", current_pos, history_count)
			imgui.Text(counter_text)
			// Clear history button
			if imgui.Button("Clear") {
				app.clear_history(state)
			}
			if imgui.IsItemHovered() {
				imgui.SetTooltip("Clear all navigation history")
			}
		} else {
			imgui.Text("0/0")
		}


		imgui.Separator()

		// Zoom controls
		imgui.Text("View Controls")
		zoom_f32 := f32(state.zoom)
		if imgui.SliderFloat("Zoom", &zoom_f32, 0.1, 100.0, "%.2f", {.Logarithmic}) {
			state.zoom = f64(zoom_f32)
			state.needs_recompute = true
		}

		if imgui.Button("Zoom In") {
			app.history_save(state)
			state.zoom *= 2.0
			state.needs_recompute = true
		}
		imgui.SameLine(0, -1)
		if imgui.Button("Zoom Out") {
			app.history_save(state)
			state.zoom *= 0.5
			state.needs_recompute = true
		}

		// Center controls
		imgui.Separator()
		center_x_f32 := f32(state.center_x)
		if imgui.SliderFloat("Center X", &center_x_f32, -2.5, 1.5, "%.6f", {}) {
			state.center_x = f64(center_x_f32)
			state.needs_recompute = true
		}

		center_y_f32 := f32(state.center_y)
		if imgui.SliderFloat("Center Y", &center_y_f32, -1.5, 1.5, "%.6f", {}) {
			state.center_y = f64(center_y_f32)
			state.needs_recompute = true
		}

		if imgui.Button("Reset View") {
			app.history_save(state)
			state.zoom = 1.0
			state.center_x = -0.5
			state.center_y = 0.0
			state.needs_recompute = true
		}

		// Iteration controls
		imgui.Separator()
		imgui.Text("Quality Settings")
		min_iter: u32 = 32
		max_iter: u32 = 2048
		if imgui.SliderScalar(
			"Max Iterations",
			.U32,
			&state.max_iterations,
			&min_iter,
			&max_iter,
		) {
			state.needs_recompute = true
		}

		// Manual recompute button
		imgui.Separator()
		if imgui.Button("Recompute", imgui.Vec2{-1, 30}) {
			state.needs_recompute = true
		}

		// Mouse controls info
		imgui.Separator()
		imgui.Text("Mouse Controls")
		imgui.BulletText("Left Click: Recenter")
		imgui.BulletText("Right Drag: Pan view")
		imgui.BulletText("Mouse Wheel: Zoom")
		imgui.BulletText("Shift+Drag: Box zoom")

		// Keyboard controls info
		imgui.Separator()
		imgui.Text("Keyboard Controls")
		imgui.BulletText("Backspace: History back")
		imgui.BulletText("Shift+Backspace: History forward")

		// Info
		imgui.Separator()
		imgui.TextWrapped(
			"Use mouse to navigate or adjust sliders below. Try preset locations for interesting areas.",
		)
	}
	imgui.End()
}
