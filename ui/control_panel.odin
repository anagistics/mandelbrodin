package ui

import app "../app"
import "core:fmt"
import "core:math"
import "core:strings"
import imgui "vendor:imgui"

// Render just the content of the control panel (for use in tabs)
Render_control_panel_content :: proc(state: ^app.App_State, width: int, height: int) {
	topRightControl := imgui.Vec2{f32(width), 0}
	bottomLeftControl := imgui.Vec2{0, f32(height)}

	imgui.Text("Mandelbrot Set Explorer")
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

	// Smooth coloring toggle
	if imgui.Checkbox("Smooth Coloring", &state.use_smooth_coloring) {
		state.needs_recompute = true
	}
	if imgui.IsItemHovered() {
		imgui.SetTooltip(
			"Use continuous iteration count for smooth gradients (eliminates color banding)",
		)
	}

	// Adaptive coloring toggle (only in CPU mode)
	if !state.use_gpu {
		if imgui.Checkbox("Adaptive Coloring", &state.use_adaptive_coloring) {
			state.needs_recompute = true
		}
		if imgui.IsItemHovered() {
			imgui.SetTooltip(
				"Use histogram equalization for better color distribution and contrast (CPU only)",
			)
		}
	} else {
		imgui.TextDisabled("Adaptive (CPU only)")
	}

	imgui.Separator()

	// 2D/3D render mode toggle
	imgui.Text("Render Mode")
	mode_2d := state.render_mode == .Mode_2D
	if imgui.RadioButton("2D (Flat)", mode_2d) {
		state.render_mode = .Mode_2D
		state.needs_recompute = true
	}
	imgui.SameLine(0, -1)
	if imgui.RadioButton("3D (Columns)", !mode_2d) {
		state.render_mode = .Mode_3D
		// Force recompute to ensure pixel data is available for 3D height extraction
		state.needs_recompute = true
	}

	// 3D settings (only show when in 3D mode)
	if state.render_mode == .Mode_3D {
		imgui.Indent(16)

		// Height scale slider
		if imgui.SliderFloat("Height Scale", &state.height_scale_3d, 0.1, 10.0, "%.2f", {}) {
			// No action needed, value is updated directly
		}
		if imgui.IsItemHovered() {
			imgui.SetTooltip("Multiplier for column heights")
		}

		// Column width slider
		if imgui.SliderFloat("Column Width", &state.column_width_3d, 0.1, 1.0, "%.2f", {}) {
			// No action needed, value is updated directly
		}
		if imgui.IsItemHovered() {
			imgui.SetTooltip("Width of 3D columns (1.0 = adjacent, <1.0 = gaps)")
		}

		// Camera controls hint
		imgui.TextWrapped("Camera: Left drag = rotate, Right drag = pan, Wheel = zoom, Arrows = rotate, R = reset")

		imgui.Unindent(16)
	}

	imgui.Separator()

	// Palette selection
	imgui.Text("Color Palette")
	if len(state.palettes) > 0 {
		// Find current palette index
		current_palette: i32 = 0
		for palette, i in state.palettes {
			if palette.name == state.palette {
				current_palette = i32(i)
				break
			}
		}

		// Build palette options string
		str_builder := strings.builder_make()
		defer strings.builder_destroy(&str_builder)
		for palette in state.palettes {
			strings.write_string(&str_builder, palette.name)
			strings.write_byte(&str_builder, 0)
		}
		palette_options := strings.to_cstring(&str_builder)

		// Render combo box
		if imgui.Combo("##palette", &current_palette, palette_options, i32(len(state.palettes))) {
			selected_palette := state.palettes[current_palette]
			app.history_save(state)
			app.set_palette(state, selected_palette.name)
		}
	} else {
		imgui.TextDisabled("No palettes loaded")
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

	// Rotation controls
	rotation_deg := f32(math.to_degrees(state.rotation))
	if imgui.SliderFloat("Rotation", &rotation_deg, 0.0, 360.0, "%.1f\u00b0", {}) {
		state.rotation = math.to_radians(f64(rotation_deg))
		state.needs_recompute = true
	}

	if imgui.Button("Reset View") {
		app.history_save(state)
		state.zoom = 1.0
		state.center_x = -0.5
		state.center_y = 0.0
		state.rotation = 0.0
		state.needs_recompute = true
	}

	// Iteration controls
	imgui.Separator()
	imgui.Text("Quality Settings")
	min_iter: u32 = 32
	max_iter: u32 = 2048
	if imgui.SliderScalar("Max Iterations", .U32, &state.max_iterations, &min_iter, &max_iter) {
		state.needs_recompute = true
	}

	// Manual recompute button
	imgui.Separator()
	if imgui.Button("Recompute", imgui.Vec2{-1, 30}) {
		state.needs_recompute = true
	}

}

// Render control panel with its own window (for standalone use)
Render_control_panel :: proc(state: ^app.App_State, width: int, height: int) {
	imgui.SetNextWindowPos(imgui.Vec2{f32(width), 0}, .Once)
	imgui.SetNextWindowSize(imgui.Vec2{300, f32(height) - 20}, .Once)

	flags := imgui.WindowFlags{.NoCollapse, .NoMove}
	if imgui.Begin("Controls", nil, flags) {
		Render_control_panel_content(state, width, height)
	}
	imgui.End()
}
