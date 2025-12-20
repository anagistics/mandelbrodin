package renderer

import app "../app"
import mb "../mandelbrot"
import camera "."
import "core:fmt"
import "core:time"
import gl "vendor:OpenGL"

// Export current view to high-resolution image
// Routes to 2D or 3D export based on current render mode
export_image :: proc(r: ^Renderer, state: ^app.App_State, width, height: int, filepath: string) -> bool {
	// Check render mode and route accordingly
	if state.render_mode == .Mode_3D && r.renderer_3d_available {
		return export_image_3d(r, state, width, height, filepath)
	} else {
		return export_image_2d(state, width, height, filepath)
	}
}

// Export 2D Mandelbrot image (compute and save)
export_image_2d :: proc(state: ^app.App_State, width, height: int, filepath: string) -> bool {
	fmt.printfln("Exporting 2D %dx%d image to %s...", width, height, filepath)

	// Update stage to Computing
	state.export_stage = .Computing
	state.export_progress = 0.0

	// Allocate temporary pixel buffer
	pixels := make([]u32, width * height)
	defer delete(pixels)

	// Create temporary state for export
	export_state := state^
	export_state.pixels = pixels

	// Compute Mandelbrot at export resolution
	fmt.printfln("Computing %dx%d image...", width, height)
	start_time := time.now()
	mb.Compute(&export_state, width, height)
	end_time := time.now()

	duration := time.diff(start_time, end_time)
	fmt.printfln("Computation took %.2f ms", time.duration_milliseconds(duration))

	// Save to file
	success := app.export_image(pixels, width, height, filepath, 1, state)

	if success {
		fmt.println("Export completed successfully!")
	} else {
		fmt.eprintln("Export failed!")
	}

	return success
}

// Export 3D view (render to framebuffer and capture)
export_image_3d :: proc(r: ^Renderer, state: ^app.App_State, width, height: int, filepath: string) -> bool {
	fmt.printfln("Exporting 3D %dx%d image to %s...", width, height, filepath)

	// Update stage to Computing
	state.export_stage = .Computing
	state.export_progress = 0.0

	start_time := time.now()

	// Create framebuffer for off-screen rendering
	fbo: u32
	gl.GenFramebuffers(1, &fbo)
	gl.BindFramebuffer(gl.FRAMEBUFFER, fbo)
	defer gl.DeleteFramebuffers(1, &fbo)

	// Create color texture
	color_texture: u32
	gl.GenTextures(1, &color_texture)
	gl.BindTexture(gl.TEXTURE_2D, color_texture)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, i32(width), i32(height), 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, color_texture, 0)
	defer gl.DeleteTextures(1, &color_texture)

	// Create depth renderbuffer
	depth_rbo: u32
	gl.GenRenderbuffers(1, &depth_rbo)
	gl.BindRenderbuffer(gl.RENDERBUFFER, depth_rbo)
	gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, i32(width), i32(height))
	gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, depth_rbo)
	defer gl.DeleteRenderbuffers(1, &depth_rbo)

	// Check framebuffer completeness
	if gl.CheckFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE {
		fmt.eprintln("Framebuffer is not complete!")
		gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
		return false
	}

	// Set viewport to export resolution
	gl.Viewport(0, 0, i32(width), i32(height))

	// Enable depth testing for 3D
	gl.Enable(gl.DEPTH_TEST)
	gl.Enable(gl.CULL_FACE)

	// Clear framebuffer
	gl.ClearColor(0.0, 0.0, 0.0, 1.0)
	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

	// Save current camera settings and adjust for export resolution
	original_aspect := r.renderer_3d.camera.aspect
	original_distance := r.renderer_3d.camera.distance
	original_target_distance := r.renderer_3d.camera.target_distance

	// Update aspect ratio for export resolution
	r.renderer_3d.camera.aspect = f32(width) / f32(height)

	// Scale camera distance based on resolution increase
	// The scene size grows proportionally with resolution, so camera must move back
	screen_width :: 800  // From appelman.odin
	screen_height :: 600
	screen_max := max(screen_width, screen_height)
	export_max := max(width, height)
	scale_factor := f32(export_max) / f32(screen_max)

	r.renderer_3d.camera.distance *= scale_factor
	r.renderer_3d.camera.target_distance *= scale_factor

	// Restore original camera settings when done
	defer {
		r.renderer_3d.camera.aspect = original_aspect
		r.renderer_3d.camera.distance = original_distance
		r.renderer_3d.camera.target_distance = original_target_distance
	}

	// Always compute Mandelbrot at export resolution for 3D
	// (We need the full resolution grid for accurate column positioning)
	temp_pixels := make([]u32, width * height)
	defer delete(temp_pixels)

	export_state := state^
	export_state.pixels = temp_pixels

	fmt.printfln("Computing Mandelbrot at %dx%d for height data...", width, height)
	mb.Compute(&export_state, width, height)

	// Update camera matrices with new aspect ratio
	camera.Update_Camera_3D(&r.renderer_3d.camera, 0)

	// Render 3D using export resolution data
	Render_3D(r, &export_state, width, height)

	// Read pixels from framebuffer
	pixels := make([]u32, width * height)
	defer delete(pixels)

	pixel_data := make([]u8, width * height * 4) // RGBA
	defer delete(pixel_data)

	gl.ReadPixels(0, 0, i32(width), i32(height), gl.RGBA, gl.UNSIGNED_BYTE, raw_data(pixel_data))

	// Convert RGBA to u32 format (flip Y coordinate)
	for y in 0 ..< height {
		for x in 0 ..< width {
			src_idx := (height - 1 - y) * width + x // Flip Y
			dst_idx := y * width + x

			r_val := pixel_data[src_idx * 4 + 0]
			g_val := pixel_data[src_idx * 4 + 1]
			b_val := pixel_data[src_idx * 4 + 2]

			pixels[dst_idx] = u32(r_val) << 16 | u32(g_val) << 8 | u32(b_val)
		}
	}

	// Restore viewport and framebuffer
	gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
	gl.Disable(gl.DEPTH_TEST)

	end_time := time.now()
	duration := time.diff(start_time, end_time)
	fmt.printfln("3D rendering took %.2f ms", time.duration_milliseconds(duration))

	// Save to file
	success := app.export_image(pixels, width, height, filepath, 1, state)

	if success {
		fmt.println("Export completed successfully!")
	} else {
		fmt.eprintln("Export failed!")
	}

	return success
}

// Set uniforms for compute shader
set_compute_uniforms :: proc(r: ^Renderer, state: ^app.App_State, width, height: int) {
	// Center (double precision)
	gl.Uniform2d(r.c_center, state.center_x, state.center_y)

	// Zoom (double precision)
	gl.Uniform1d(r.c_zoom, state.zoom)

	// Rotation (double precision)
	gl.Uniform1d(r.c_rotation, state.rotation)

	// Max iterations
	gl.Uniform1i(r.c_max_iterations, i32(state.max_iterations))

	// Smooth coloring flag
	gl.Uniform1i(r.c_use_smooth_coloring, i32(state.use_smooth_coloring ? 1 : 0))

	// Dimensions
	gl.Uniform2i(r.c_dimensions, i32(width), i32(height))

	// Palette data
	palette := state.current_palette
	num_stops := i32(len(palette.stops))
	gl.Uniform1i(r.c_num_stops, num_stops)

	// Upload color stops
	positions: [10]f32
	colors: [10][3]f32

	for stop, i in palette.stops {
		if i >= 10 {
			break
		}
		positions[i] = f32(stop.position)
		colors[i] = {f32(stop.r) / 255.0, f32(stop.g) / 255.0, f32(stop.b) / 255.0}
	}

	gl.Uniform1fv(r.c_stop_positions, num_stops, &positions[0])
	gl.Uniform3fv(r.c_stop_colors, num_stops, &colors[0][0])
}

// Export using GPU compute shader (much faster than CPU for 2D)
// compression_level: 0-9 (0=none, 1=fastest, 6=default, 9=best) or -1 for stb_image_write
// Note: For 3D mode, this delegates to export_image which renders the 3D scene
export_image_compute :: proc(r: ^Renderer, state: ^app.App_State, width, height: int, filepath: string, compression_level: int = 1) -> bool {
	// If in 3D mode, use 3D export path
	if state.render_mode == .Mode_3D && r.renderer_3d_available {
		return export_image(r, state, width, height, filepath)
	}

	// For 2D mode, use compute shader if available
	if !r.compute_available {
		fmt.println("Compute shader not available, falling back to CPU")
		return export_image(r, state, width, height, filepath)
	}

	fmt.printfln("Exporting %dx%d image using GPU compute shader...", width, height)
	start_time := time.now()

	// Update stage to Computing
	state.export_stage = .Computing
	state.export_progress = 0.0

	// Create output texture
	output_texture: u32
	gl.GenTextures(1, &output_texture)
	gl.BindTexture(gl.TEXTURE_2D, output_texture)
	gl.TexStorage2D(gl.TEXTURE_2D, 1, gl.RGBA8, i32(width), i32(height))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	defer gl.DeleteTextures(1, &output_texture)

	// Bind texture as image for compute shader writing
	gl.BindImageTexture(0, output_texture, 0, false, 0, gl.WRITE_ONLY, gl.RGBA8)

	// Use compute shader program
	gl.UseProgram(r.compute_program)

	// Set all uniforms
	set_compute_uniforms(r, state, width, height)

	// Dispatch compute shader
	// Workgroup size is 16×16, so divide dimensions by 16 (round up)
	groups_x := (u32(width) + 15) / 16
	groups_y := (u32(height) + 15) / 16

	computation_start := time.now()
	gl.DispatchCompute(groups_x, groups_y, 1)

	// Wait for computation to complete
	gl.MemoryBarrier(gl.SHADER_IMAGE_ACCESS_BARRIER_BIT)

	computation_end := time.now()
	computation_duration := time.diff(computation_start, computation_end)
	fmt.printfln("GPU computation took %.2f ms", time.duration_milliseconds(computation_duration))

	// Update progress after computation
	state.export_progress = 0.5
	state.export_stage = .Encoding

	// Read pixels from texture
	pixels := make([]u8, width * height * 4)  // RGBA format
	defer delete(pixels)

	gl.BindTexture(gl.TEXTURE_2D, output_texture)
	gl.GetTexImage(gl.TEXTURE_2D, 0, gl.RGBA, gl.UNSIGNED_BYTE, raw_data(pixels))

	// Convert RGBA bytes to u32 pixels (0xAARRGGBB format) and flip Y
	pixels_u32 := make([]u32, width * height)
	defer delete(pixels_u32)

	for y in 0 ..< height {
		for x in 0 ..< width {
			// Flip Y coordinate (OpenGL is bottom-left, PNG is top-left)
			src_idx := (height - 1 - y) * width + x
			dst_idx := y * width + x

			r := u32(pixels[src_idx * 4 + 0])
			g := u32(pixels[src_idx * 4 + 1])
			b := u32(pixels[src_idx * 4 + 2])
			a := u32(pixels[src_idx * 4 + 3])
			pixels_u32[dst_idx] = (a << 24) | (r << 16) | (g << 8) | b
		}
	}

	// Save to file
	success := app.export_image(pixels_u32, width, height, filepath, compression_level, state)

	total_duration := time.diff(start_time, time.now())
	fmt.printfln("Total export time: %.2f ms", time.duration_milliseconds(total_duration))

	if success {
		fmt.println("✓ GPU export completed successfully!")
	} else {
		fmt.eprintln("✗ GPU export failed!")
	}

	return success
}

// Export thumbnail-sized image for bookmarks (128×96)
// Routes to appropriate export path based on render mode
// Takes rawptr instead of ^Renderer to avoid cyclic imports when used as callback
export_thumbnail :: proc(
	renderer: rawptr,
	state: ^app.App_State,
	width, height: int,
	filepath: string,
) -> bool {
	r := cast(^Renderer)renderer

	// Route to appropriate export based on render mode
	if state.render_mode == .Mode_3D && r.renderer_3d_available {
		return export_image_3d(r, state, width, height, filepath)
	} else if r.compute_available {
		return export_image_compute(r, state, width, height, filepath, 6)
	} else {
		return export_image_2d(state, width, height, filepath)
	}
}
