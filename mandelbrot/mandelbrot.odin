package mandelbrot

import app "../app"
import visual "../visual"
import "core:math"
import "core:simd"
import "core:thread"

// SIMD vector width - process 4 pixels at once with AVX
SIMD_WIDTH :: 4

// Number of threads for parallel computation
NUM_THREADS :: 8

// Thread data for passing parameters to worker threads
Thread_Data :: struct {
	state:     ^app.App_State,
	width:     int,
	height:    int,
	row_start: int,
	row_end:   int,
	scale:     f64,
	offset_x:  f64,
	offset_y:  f64,
}

Compute :: proc(state: ^app.App_State, width: int, height: int) {
	if state.use_simd {
		compute_simd(state, width, height)
	} else {
		compute_scalar(state, width, height)
	}
}

// Scalar fallback version (for comparison/debugging)
compute_scalar :: proc(state: ^app.App_State, width: int, height: int) {
	N :: 8
	assert(width % N == 0)

	scale := 3.5 / state.zoom
	offset_x := state.center_x - (1.75 / state.zoom)
	offset_y := state.center_y - (1.0 / state.zoom)

	// Calculate rows per thread
	rows_per_thread := height / NUM_THREADS

	// Create threads and thread data
	threads: [NUM_THREADS]^thread.Thread
	thread_data: [NUM_THREADS]Thread_Data

	// Spawn threads
	for i in 0 ..< NUM_THREADS {
		thread_data[i] = Thread_Data {
			state     = state,
			width     = width,
			height    = height,
			row_start = i * rows_per_thread,
			row_end   = (i + 1) * rows_per_thread,
			scale     = scale,
			offset_x  = offset_x,
			offset_y  = offset_y,
		}

		threads[i] = thread.create(compute_scalar_worker)
		threads[i].data = &thread_data[i]
		thread.start(threads[i])
	}

	// Wait for all threads to complete
	for i in 0 ..< NUM_THREADS {
		thread.join(threads[i])
		thread.destroy(threads[i])
	}
}

// Worker function for scalar computation on a range of rows
compute_scalar_worker :: proc(t: ^thread.Thread) {
	N :: 8
	data := (^Thread_Data)(t.data)
	state := data.state
	width := data.width
	height := data.height

	blocks := width / N
	px: [N]int
	x0: [N]f64

	for py in data.row_start ..< data.row_end {
		y0 := f64(py) / f64(height) * (2.0 / state.zoom) + data.offset_y
		for blck in 0 ..< blocks {
			base := blck * N
			#unroll for i in 0 ..< N {
				px[i] = base + i
				x0[i] = f64(px[i]) / f64(width) * data.scale + data.offset_x
				iterations, magnitude_sq := iterate(x0[i], y0, state.max_iterations)
				color := compute_pixel_color(iterations, magnitude_sq, state)
				state.pixels[py * width + px[i]] = color
			}
		}
	}
}

compute_simd :: proc(state: ^app.App_State, width: int, height: int) {
	assert(width % SIMD_WIDTH == 0)

	scale := 3.5 / state.zoom
	offset_x := state.center_x - (1.75 / state.zoom)
	offset_y := state.center_y - (1.0 / state.zoom)

	// Calculate rows per thread
	rows_per_thread := height / NUM_THREADS

	// Create threads and thread data
	threads: [NUM_THREADS]^thread.Thread
	thread_data: [NUM_THREADS]Thread_Data

	// Spawn threads
	for i in 0 ..< NUM_THREADS {
		thread_data[i] = Thread_Data {
			state     = state,
			width     = width,
			height    = height,
			row_start = i * rows_per_thread,
			row_end   = (i + 1) * rows_per_thread,
			scale     = scale,
			offset_x  = offset_x,
			offset_y  = offset_y,
		}

		threads[i] = thread.create(compute_simd_worker)
		threads[i].data = &thread_data[i]
		thread.start(threads[i])
	}

	// Wait for all threads to complete
	for i in 0 ..< NUM_THREADS {
		thread.join(threads[i])
		thread.destroy(threads[i])
	}
}

// Worker function for SIMD computation on a range of rows
compute_simd_worker :: proc(t: ^thread.Thread) {
	data := (^Thread_Data)(t.data)
	state := data.state
	width := data.width
	height := data.height

	blocks := width / SIMD_WIDTH

	// Precompute constant SIMD vectors for x-coordinate calculation
	width_vec := simd.f64x4{f64(width), f64(width), f64(width), f64(width)}
	scale_vec := simd.f64x4{data.scale, data.scale, data.scale, data.scale}
	offset_vec := simd.f64x4{data.offset_x, data.offset_x, data.offset_x, data.offset_x}
	pixel_offsets := simd.f64x4{0, 1, 2, 3}

	for py in data.row_start ..< data.row_end {
		y0 := f64(py) / f64(height) * (2.0 / state.zoom) + data.offset_y
		y0_vec := simd.f64x4(y0)

		for blck in 0 ..< blocks {
			base := blck * SIMD_WIDTH

			// Build x0 vector for 4 pixels using SIMD operations
			base_vec := simd.f64x4{f64(base), f64(base), f64(base), f64(base)} + pixel_offsets
			x0_vec := (base_vec / width_vec) * scale_vec + offset_vec

			// Compute iterations for 4 pixels simultaneously
			iterations, magnitudes := iterate_simd(x0_vec, y0_vec, state.max_iterations)

			// Convert to colors and store
			for i in 0 ..< SIMD_WIDTH {
				px := base + i
				color := compute_pixel_color(iterations[i], magnitudes[i], state)
				state.pixels[py * width + px] = color
			}
		}
	}
}

// SIMD iteration - processes 4 pixels at once
iterate_simd :: proc(
	x0_vec: simd.f64x4,
	y0_vec: simd.f64x4,
	max_iterations: u64,
) -> (
	[4]u64,
	[4]f64,
) {
	x := simd.f64x4{0, 0, 0, 0}
	y := simd.f64x4{0, 0, 0, 0}
	threshold := simd.f64x4{4.0, 4.0, 4.0, 4.0}
	zero := simd.f64x4{0, 0, 0, 0}
	zero_uint := simd.u64x4{0, 0, 0, 0}
	one_uint := simd.u64x4{1, 1, 1, 1}

	// Track iteration count and active state as f64
	iter_count := zero_uint
	active := one_uint

	magnitude_sq := simd.f64x4{0, 0, 0, 0}
	escape_magnitude_sq := simd.f64x4{0, 0, 0, 0}

	for iter: u64 = 0; iter < max_iterations; iter += 1 {
		// Mandelbrot iteration: z = z^2 + c
		xx := x * x
		yy := y * y
		xtemp := xx - yy + x0_vec
		y = 2.0 * x * y + y0_vec
		x = xtemp

		// Increment counter for active lanes
		iter_count = iter_count + active

		// Calculate magnitude squared (after updating z)
		magnitude_sq = x * x + y * y

		// Check if escaped: magnitude_sq > 4.0
		not_escaped := simd.lanes_le(magnitude_sq, threshold)

		// Preserve magnitude at escape time for smooth coloring
		// Only update escape_magnitude_sq for lanes that just became inactive
		active_mask := simd.lanes_ne(active, zero_uint)
		escape_magnitude_sq = simd.select(active_mask, magnitude_sq, escape_magnitude_sq)

		active = simd.select(not_escaped, active, zero_uint)

		// Early exit if all lanes have escaped
		if simd.reduce_or(active) == 0 {
			break
		}
	}

	// Convert to arrays
	iterations := simd.to_array(iter_count)
	magnitudes := simd.to_array(escape_magnitude_sq)

	return iterations, magnitudes
}

// Scalar fallback iteration (kept for reference/debugging)
iterate :: proc(x0: f64, y0: f64, max_iterations: u64) -> (u64, f64) {
	x := 0.0
	y := 0.0
	iteration: u64 = 0
	magnitude_sq := 0.0
	for magnitude_sq <= 4.0 && iteration < max_iterations {
		xtemp := x * x - y * y + x0
		y = 2.0 * x * y + y0
		x = xtemp
		iteration += 1
		magnitude_sq = x * x + y * y
	}
	return iteration, magnitude_sq
}

// Compute pixel color from iteration count and magnitude
compute_pixel_color :: proc(
	iter: u64,
	magnitude_sq: f64,
	state: ^app.App_State,
) -> u32 {
	color: u32
	if state.use_smooth_coloring {
		smooth_iter := calculate_smooth_iteration(iter, magnitude_sq)
		color = compute_color_smooth(
			smooth_iter,
			state.max_iterations,
			state.current_palette,
		)
	} else {
		color = compute_color(iter, state.max_iterations, state.current_palette)
	}
	return color
}

// Linear interpolation between two values
lerp :: proc(a: f64, b: f64, t: f64) -> f64 {
	return a + (b - a) * t
}

// Interpolate color from gradient
interpolate_color :: proc(palette: visual.Gradient_Palette, t: f64) -> (u8, u8, u8) {
	if len(palette.stops) == 0 {
		return 0, 0, 0
	}

	if t <= palette.stops[0].position {
		return palette.stops[0].r, palette.stops[0].g, palette.stops[0].b
	}

	if t >= palette.stops[len(palette.stops) - 1].position {
		last := palette.stops[len(palette.stops) - 1]
		return last.r, last.g, last.b
	}

	// Find the two stops to interpolate between
	for i in 0 ..< len(palette.stops) - 1 {
		stop1 := palette.stops[i]
		stop2 := palette.stops[i + 1]

		if t >= stop1.position && t <= stop2.position {
			// Calculate interpolation factor
			local_t := (t - stop1.position) / (stop2.position - stop1.position)

			r := u8(lerp(f64(stop1.r), f64(stop2.r), local_t))
			g := u8(lerp(f64(stop1.g), f64(stop2.g), local_t))
			b := u8(lerp(f64(stop1.b), f64(stop2.b), local_t))

			return r, g, b
		}
	}

	return 0, 0, 0
}

// Calculate smooth iteration count from discrete iteration and final magnitude
calculate_smooth_iteration :: proc(iter: u64, magnitude_sq: f64) -> f64 {
	// Avoid log of values <= 0
	if magnitude_sq <= 1.0 {
		return f64(iter)
	}

	// Smooth iteration formula: n + 1 - log(log(|z|)) / log(2)
	// Where |z| = sqrt(magnitude_sq)
	magnitude := math.sqrt(magnitude_sq)
	smooth := f64(iter) + 1.0 - math.ln(math.ln(magnitude)) / math.ln(f64(2.0))

	return max(0.0, smooth)
}

compute_color :: proc(iter: u64, max_iterations: u64, palette: visual.Gradient_Palette) -> u32 {
	color: u32
	if iter == max_iterations {
		color = 0xFF000000
	} else {
		t := f64(iter) / f64(max_iterations)
		r, g, b := interpolate_color(palette, t)
		color = 0xFF000000 | (u32(r) << 16) | (u32(g) << 8) | u32(b)
	}
	return color
}

// Compute color with smooth (fractional) iteration count
compute_color_smooth :: proc(
	smooth_iter: f64,
	max_iterations: u64,
	palette: visual.Gradient_Palette,
) -> u32 {
	color: u32
	if smooth_iter >= f64(max_iterations) {
		color = 0xFF000000
	} else {
		t := smooth_iter / f64(max_iterations)
		r, g, b := interpolate_color(palette, t)
		color = 0xFF000000 | (u32(r) << 16) | (u32(g) << 8) | u32(b)
	}
	return color
}
