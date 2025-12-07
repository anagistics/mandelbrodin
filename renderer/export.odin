package renderer

import app "../app"
import mb "../mandelbrot"
import "core:fmt"
import "core:time"
import gl "vendor:OpenGL"

// Export current view to high-resolution image
// Computes the Mandelbrot set at the specified resolution and saves to PNG
export_image :: proc(state: ^app.App_State, width, height: int, filepath: string) -> bool {
	fmt.printfln("Exporting %dx%d image to %s...", width, height, filepath)

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
	success := app.export_image(pixels, width, height, filepath)

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

// Export using GPU compute shader (much faster than CPU)
export_image_compute :: proc(r: ^Renderer, state: ^app.App_State, width, height: int, filepath: string) -> bool {
	if !r.compute_available {
		fmt.println("Compute shader not available, falling back to CPU")
		return export_image(state, width, height, filepath)
	}

	fmt.printfln("Exporting %dx%d image using GPU compute shader...", width, height)
	start_time := time.now()

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

	// Read pixels from texture
	pixels := make([]u8, width * height * 4)  // RGBA format
	defer delete(pixels)

	gl.BindTexture(gl.TEXTURE_2D, output_texture)
	gl.GetTexImage(gl.TEXTURE_2D, 0, gl.RGBA, gl.UNSIGNED_BYTE, raw_data(pixels))

	// Convert RGBA bytes to u32 pixels (0xAARRGGBB format)
	pixels_u32 := make([]u32, width * height)
	defer delete(pixels_u32)

	for i := 0; i < width * height; i += 1 {
		r := u32(pixels[i * 4 + 0])
		g := u32(pixels[i * 4 + 1])
		b := u32(pixels[i * 4 + 2])
		a := u32(pixels[i * 4 + 3])
		pixels_u32[i] = (a << 24) | (r << 16) | (g << 8) | b
	}

	// Save to file
	success := app.export_image(pixels_u32, width, height, filepath)

	total_duration := time.diff(start_time, time.now())
	fmt.printfln("Total export time: %.2f ms", time.duration_milliseconds(total_duration))

	if success {
		fmt.println("✓ GPU export completed successfully!")
	} else {
		fmt.eprintln("✗ GPU export failed!")
	}

	return success
}
