package ui

import app "../app"
import renderer "../renderer"
import mb "../mandelbrot"
import "core:fmt"
import "core:strings"
import "core:time"
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
		if len(state.export_filename) > 0 && !state.export_in_progress {
			// Double-check: prevent multiple exports (safety against race conditions)
			// Ensure .png extension
			output_filename := state.export_filename
			if !strings.has_suffix(output_filename, ".png") {
				output_filename = fmt.tprintf("%s.png", output_filename)
			}

			// Trigger export
			resolution := app.EXPORT_RESOLUTIONS[state.export_resolution]
			state.export_in_progress = true
			state.export_progress = 0.0
			state.export_stage = .Computing
			state.export_start_time = time.now()
			state.export_error = ""

			// Determine export mode:
			// - For 2D mode with CPU rendering: use async (background thread)
			// - For 2D mode with GPU compute: use sync (OpenGL context not thread-safe)
			// - For 3D mode: use sync (OpenGL rendering required)
			use_async := (state.render_mode == .Mode_2D && !r.compute_available)

			if use_async {
				// Safety check: ensure no existing thread (should not happen due to button disable)
				if state.export_thread != nil {
					fmt.eprintln("WARNING: Export already in progress! Ignoring new export request.")
					state.export_in_progress = false
					state.export_stage = .Error
					state.export_error = "Export already in progress"
				} else {
					// Start background export thread (CPU only)
					state.export_thread = rawptr(app.export_image_async(
						state,
						resolution.width,
						resolution.height,
						output_filename,
						state.export_compression,
						mb.Compute, // Pass compute function
					))
					// Thread will update state.export_in_progress when done
				}
			} else {
				// Synchronous export (GPU compute or 3D)
				success := renderer.export_image_compute(r, state, resolution.width, resolution.height, output_filename, state.export_compression)

				// Update final status
				if success {
					state.export_stage = .Completed
					state.export_progress = 1.0
				} else {
					state.export_stage = .Error
					state.export_error = "Export failed (check console for details)"
				}
				state.export_in_progress = false
			}
		}
	}

	if !can_export {
		imgui.EndDisabled()
	}

	// Progress bar and status (shown during export)
	if state.export_in_progress {
		imgui.Separator()

		// Stage text
		stage_text := "Starting..."
		#partial switch state.export_stage {
		case .Computing:
			stage_text = "Computing Mandelbrot..."
		case .Encoding:
			stage_text = "Encoding PNG..."
		case .Completed:
			stage_text = "✓ Export completed!"
		case .Error:
			stage_text = "✗ Export failed!"
		}

		imgui.Text(strings.clone_to_cstring(stage_text))

		// Progress bar
		progress_text := fmt.ctprintf("%.0f%%", state.export_progress * 100.0)
		imgui.ProgressBar(state.export_progress, imgui.Vec2{-1, 0}, progress_text)

		// Show elapsed time
		if state.export_stage == .Computing || state.export_stage == .Encoding {
			elapsed := time.since(state.export_start_time)
			elapsed_sec := time.duration_seconds(elapsed)
			imgui.TextDisabled(fmt.ctprintf("Elapsed: %.1fs", elapsed_sec))
		}

		// Show error message if failed
		if state.export_stage == .Error && len(state.export_error) > 0 {
			imgui.TextColored({1.0, 0.3, 0.3, 1.0}, fmt.ctprintf("Error: %s", strings.clone_to_cstring(state.export_error)))
		}
	}

	imgui.Separator()

	// Info
	imgui.TextWrapped("Export renders the current view at high resolution and saves to PNG format. Higher resolutions take longer to compute.")

	imgui.Separator()
	imgui.TextDisabled("Note: Export uses GPU compute shader (or CPU fallback)")

	// 3D Model Export Section (only in 3D mode)
	if state.render_mode == .Mode_3D {
		imgui.Separator()
		imgui.Separator()

		imgui.Text("Export 3D Model (Experimental)")
		imgui.Separator()

		imgui.TextWrapped("Export the 3D visualization as an OBJ file for use with Blender, Maya, or other 3D software.")

		imgui.Separator()

		// Model resolution selection (simplified for 3D)
		imgui.Text("Model Resolution")
		model_res_options := []string {
			"200x150 (30K columns, ~5 MB)",
			"400x300 (120K columns, ~20 MB)",
			"800x600 (480K columns, ~80 MB)",
		}

		model_res_widths := []int{200, 400, 800}
		model_res_heights := []int{150, 300, 600}

		model_res_builder := strings.builder_make()
		defer strings.builder_destroy(&model_res_builder)
		for option in model_res_options {
			strings.write_string(&model_res_builder, option)
			strings.write_byte(&model_res_builder, 0)
		}
		model_res_labels := strings.to_cstring(&model_res_builder)

		// Use export_resolution as temp storage for model resolution
		@static model_resolution: i32 = 1 // Default to 400x300

		if imgui.Combo("##model_resolution", &model_resolution, model_res_labels, i32(len(model_res_options))) {
			// Selection updated
		}

		imgui.Separator()

		// 3D model filename
		imgui.Text("Model Filename")
		model_input_buffer: [256]u8 = {}
		@static model_filename: string = "mandelbrot_3d"

		for i in 0 ..< min(len(model_filename), 255) {
			model_input_buffer[i] = model_filename[i]
		}

		if imgui.InputText("##model_filename", cstring(raw_data(model_input_buffer[:])), len(model_input_buffer), {}) {
			null_pos := 0
			for i in 0 ..< len(model_input_buffer) {
				if model_input_buffer[i] == 0 {
					null_pos = i
					break
				}
			}
			model_filename = strings.clone(string(model_input_buffer[:null_pos]))
		}

		if len(model_filename) > 0 {
			imgui.TextDisabled(fmt.ctprintf("  -> %s.obj", strings.clone_to_cstring(model_filename)))
		} else {
			imgui.TextDisabled("  (enter filename)")
		}

		imgui.Separator()

		// Export 3D model button
		can_export_3d := len(model_filename) > 0 && !state.export_in_progress

		if !can_export_3d {
			imgui.BeginDisabled()
		}

		if imgui.Button("Export 3D Model (OBJ)", imgui.Vec2{-1, 40}) {
			if len(model_filename) > 0 {
				output_filename := model_filename
				if !strings.has_suffix(output_filename, ".obj") {
					output_filename = fmt.tprintf("%s.obj", output_filename)
				}

				state.export_in_progress = true

				// Get selected resolution
				width_3d := model_res_widths[model_resolution]
				height_3d := model_res_heights[model_resolution]

				// Export 3D model
				success := renderer.export_3d_model_obj(r, state, width_3d, height_3d, output_filename)

				state.export_in_progress = false
			}
		}

		if !can_export_3d {
			imgui.EndDisabled()
		}

		imgui.Separator()
		imgui.TextWrapped("Note: 3D model files can be very large. Use lower resolutions for faster exports and smaller files. OBJ files include vertex colors.")
	}
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
