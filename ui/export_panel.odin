package ui

import app "../app"
import renderer "../renderer"
import "core:fmt"
import "core:strings"
import imgui "vendor:imgui"

// Render just the content of the export panel (for use in tabs)
Render_export_panel_content :: proc(r: ^renderer.Renderer, state: ^app.App_State, width: int, height: int) {
imgui.Text("Export High Resolution")
	imgui.Separator()

	// Resolution selection
	imgui.Text("Output Resolution")

	// Build resolution options string
	str_builder := strings.builder_make()
	defer strings.builder_destroy(&str_builder)
	for resolution in app.EXPORT_RESOLUTIONS {
		strings.write_string(&str_builder, resolution.name)
		strings.write_byte(&str_builder, 0)
	}
	resolution_options := strings.to_cstring(&str_builder)

	current_resolution := i32(state.export_resolution)
	if imgui.Combo("##resolution", &current_resolution, resolution_options, i32(len(app.EXPORT_RESOLUTIONS))) {
		state.export_resolution = int(current_resolution)
	}

	// Show selected resolution details
	selected := app.EXPORT_RESOLUTIONS[state.export_resolution]
	imgui.Text(fmt.ctprintf("  %d x %d pixels", selected.width, selected.height))
	megapixels := f32(selected.width * selected.height) / 1_000_000.0
	imgui.Text(fmt.ctprintf("  %.1f megapixels", megapixels))

	imgui.Separator()

	// Compression level selection
	imgui.Text("Compression Quality")

	// Build compression options string (null-separated)
	comp_builder := strings.builder_make()
	defer strings.builder_destroy(&comp_builder)

	compression_options := []string{
		"No compression (fastest, huge files)",
		"Level 1 - Fast (recommended)",
		"Level 2",
		"Level 3 - Fast",
		"Level 4",
		"Level 5",
		"Level 6 - Default",
		"Level 7",
		"Level 8",
		"Level 9 - Best (slowest)",
	}

	for option in compression_options {
		strings.write_string(&comp_builder, option)
		strings.write_byte(&comp_builder, 0)
	}
	compression_labels := strings.to_cstring(&comp_builder)

	current_compression := i32(state.export_compression)
	if imgui.Combo("##compression", &current_compression, compression_labels, i32(len(compression_options))) {
		state.export_compression = int(current_compression)
	}

	// Show compression info
	if state.export_compression == 0 {
		imgui.TextDisabled("  Very fast, but files are ~10-20x larger")
	} else if state.export_compression == 1 {
		imgui.TextColored({0.3, 1.0, 0.3, 1.0}, "  ⚡ Recommended: Fast with good compression")
	} else if state.export_compression <= 3 {
		imgui.TextDisabled("  Good balance of speed and size")
	} else if state.export_compression <= 6 {
		imgui.TextDisabled("  Slower but smaller files")
	} else {
		imgui.TextDisabled("  Slowest: Maximum compression")
	}

	imgui.Separator()

	// Filename input
	imgui.Text("Output Filename")

	// Create a buffer for ImGui input (needs to be mutable and null-terminated)
	input_buffer: [256]u8 = {}
	for i in 0 ..< min(len(state.export_filename), 255) {
		input_buffer[i] = state.export_filename[i]
	}

	if imgui.InputText("##filename", cstring(raw_data(input_buffer[:])), len(input_buffer), {}) {
		// Update state from buffer
		null_pos := 0
		for i in 0 ..< len(input_buffer) {
			if input_buffer[i] == 0 {
				null_pos = i
				break
			}
		}
		// Clone the string to allocate persistent memory (input_buffer is stack-allocated)
		state.export_filename = strings.clone(string(input_buffer[:null_pos]))
	}

	// Show preview of full path
	if len(state.export_filename) > 0 {
		imgui.TextDisabled(fmt.ctprintf("  -> %s", strings.clone_to_cstring(state.export_filename)))
	} else {
		imgui.TextDisabled("  (enter filename)")
	}

	imgui.Separator()

	// Current view settings
	imgui.Text("Export Settings")
	imgui.BulletText(fmt.ctprintf("Zoom: %.2f", state.zoom))
	imgui.BulletText(fmt.ctprintf("Center: (%.6f, %.6f)", state.center_x, state.center_y))
	imgui.BulletText(fmt.ctprintf("Iterations: %d", state.max_iterations))
	imgui.BulletText(fmt.ctprintf("Palette: %s", strings.clone_to_cstring(state.palette)))

	imgui.Separator()

	// Export button
	can_export := len(state.export_filename) > 0 && !state.export_in_progress

	if !can_export {
		imgui.BeginDisabled()
	}

	if imgui.Button("Export Image", imgui.Vec2{-1, 40}) {
		if len(state.export_filename) > 0 {
			// Ensure .png extension
			output_filename := state.export_filename
			if !strings.has_suffix(output_filename, ".png") {
				output_filename = fmt.tprintf("%s.png", output_filename)
			}

			// Trigger export
			resolution := app.EXPORT_RESOLUTIONS[state.export_resolution]
			state.export_in_progress = true

			// Export using GPU compute shader (falls back to CPU if unavailable)
			success := renderer.export_image_compute(r, state, resolution.width, resolution.height, output_filename, state.export_compression)

			state.export_in_progress = false
		}
	}

	if !can_export {
		imgui.EndDisabled()
	}

	if state.export_in_progress {
		imgui.Text("Exporting...")
		// Note: For now, export is synchronous. Could be made async with threading
	}

	imgui.Separator()

	// Info
	imgui.TextWrapped("Export renders the current view at high resolution and saves to PNG format. Higher resolutions take longer to compute.")

	imgui.Separator()
	imgui.TextDisabled("Note: Export uses GPU compute shader (or CPU fallback)")
}

// Render export panel with its own window (for standalone use)
Render_export_panel :: proc(r: ^renderer.Renderer, state: ^app.App_State, x_offset: int, y_offset: int, width: int, height: int) {
	imgui.SetNextWindowPos(imgui.Vec2{f32(x_offset), f32(y_offset)}, .Once)
	imgui.SetNextWindowSize(imgui.Vec2{f32(width), f32(height) - 20}, .Once)

	flags := imgui.WindowFlags{.NoCollapse, .NoMove}
	if imgui.Begin("Export Image", nil, flags) {
		Render_export_panel_content(r, state, width, height)
	}
	imgui.End()
}
