package ui

import app "../app"
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
			state.palette = app.Palette_Type(current_palette)
			state.needs_recompute = true
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
			state.zoom *= 2.0
			state.needs_recompute = true
		}
		imgui.SameLine(0, -1)
		if imgui.Button("Zoom Out") {
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

		// Preset locations
		imgui.Separator()
		imgui.Text("Interesting Locations")

		if imgui.Button("Default View") {
			state.center_x = -0.5
			state.center_y = 0.0
			state.zoom = 1.0
			state.needs_recompute = true
		}

		if imgui.Button("Seahorse Valley") {
			state.center_x = -0.743643887037151
			state.center_y = 0.131825904205330
			state.zoom = 50.0
			state.needs_recompute = true
		}

		if imgui.Button("Elephant Valley") {
			state.center_x = 0.3245046418497685
			state.center_y = 0.04855101129280834
			state.zoom = 100.0
			state.needs_recompute = true
		}

		if imgui.Button("Spiral") {
			state.center_x = -0.7269
			state.center_y = 0.1889
			state.zoom = 30.0
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

		// Info
		imgui.Separator()
		imgui.TextWrapped(
			"Use mouse to navigate or adjust sliders below. Try preset locations for interesting areas.",
		)
	}
	imgui.End()
}
