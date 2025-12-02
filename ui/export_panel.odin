package ui

import app "../app"
import mb "../mandelbrot"
import "core:fmt"
import "core:strings"
import "core:time"
import imgui "vendor:imgui"

Render_export_panel :: proc(state: ^app.App_State, x_offset: int, y_offset: int, width: int, height: int) {
	imgui.SetNextWindowPos(imgui.Vec2{f32(x_offset), f32(y_offset)}, .Once)
	imgui.SetNextWindowSize(imgui.Vec2{f32(width), f32(height) - 20}, .Once)

	flags := imgui.WindowFlags{.NoCollapse, .NoMove}
	if imgui.Begin("Export Image", nil, flags) {
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
			state.export_filename = string(input_buffer[:null_pos])
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

				// Allocate temporary pixel buffer
				pixels := make([]u32, resolution.width * resolution.height)
				defer delete(pixels)

				// Create temporary state for export
				export_state := state^
				export_state.pixels = pixels

				// Compute Mandelbrot at export resolution
				fmt.printfln("Computing %dx%d image...", resolution.width, resolution.height)
				start_time := time.now()
				mb.Compute(&export_state, resolution.width, resolution.height)
				end_time := time.now()

				duration := time.diff(start_time, end_time)
				fmt.printfln("Computation took %.2f ms", time.duration_milliseconds(duration))

				// Save to file
				success := app.export_image(pixels, resolution.width, resolution.height, output_filename)

				state.export_in_progress = false

				if success {
					fmt.println("Export completed successfully!")
				} else {
					fmt.eprintln("Export failed!")
				}
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
		imgui.TextDisabled("Note: Export uses CPU rendering")
	}
	imgui.End()
}
