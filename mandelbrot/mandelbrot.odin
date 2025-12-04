package mandelbrot

import app "../app"
import visual "../visual"
import "core:math"
import "core:simd"
import "core:sync"
import "core:thread"

// SIMD vector width - process 4 pixels at once with AVX
SIMD_WIDTH :: 4

// Number of threads for parallel computation
NUM_THREADS :: 8

// Work queue for dynamic load balancing
Work_Queue :: struct {
	next_row:   int, // Atomic counter for next row to process
	total_rows: int, // Total number of rows to process
}

// Thread data for passing parameters to worker threads
Thread_Data :: struct {
	state:      ^app.App_State,
	width:      int,
	height:     int,
	work_queue: ^Work_Queue, // Pointer to shared work queue
	scale:      f64,
	offset_x:   f64,
	offset_y:   f64,
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

	// Initialize work queue for dynamic load balancing
	work_queue := Work_Queue{next_row = 0, total_rows = height}

	// Create threads and thread data
	threads: [NUM_THREADS]^thread.Thread
	thread_data: [NUM_THREADS]Thread_Data

	// Spawn threads
	for i in 0 ..< NUM_THREADS {
		thread_data[i] = Thread_Data {
			state      = state,
			width      = width,
			height     = height,
			work_queue = &work_queue,
			scale      = scale,
			offset_x   = offset_x,
			offset_y   = offset_y,
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

// Worker function for scalar computation using dynamic work queue
compute_scalar_worker :: proc(t: ^thread.Thread) {
	N :: 8
	data := (^Thread_Data)(t.data)
	state := data.state
	width := data.width
	height := data.height
	work_queue := data.work_queue

	blocks := width / N
	px: [N]int
	x0: [N]f64
	y0: [N]f64

	// Precompute rotation values
	cos_r := math.cos(state.rotation)
	sin_r := math.sin(state.rotation)
	scale_x := 3.5 / state.zoom
	scale_y := 2.0 / state.zoom

	// Dynamically grab rows from the work queue
	for {
		// Atomically fetch the next row to process
		py := sync.atomic_add(&work_queue.next_row, 1)

		// Check if we've processed all rows
		if py >= work_queue.total_rows {
			break
		}

		// Convert to normalized coordinates
		norm_y := f64(py) / f64(height) - 0.5

		for blck in 0 ..< blocks {
			base := blck * N
			#unroll for i in 0 ..< N {
				px[i] = base + i

				// Convert to normalized coordinates
				norm_x := f64(px[i]) / f64(width) - 0.5

				// Apply rotation
				rotated_x := norm_x * cos_r - norm_y * sin_r
				rotated_y := norm_x * sin_r + norm_y * cos_r

				// Scale to world coordinates
				x0[i] = rotated_x * scale_x + state.center_x
				y0[i] = rotated_y * scale_y + state.center_y

				iterations, magnitude_sq := iterate(x0[i], y0[i], state.max_iterations)
				color := visual.Compute_pixel_color(
					iterations,
					magnitude_sq,
					state.use_smooth_coloring,
					state.max_iterations,
					state.current_palette,
				)
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

	// Initialize work queue for dynamic load balancing
	work_queue := Work_Queue{next_row = 0, total_rows = height}

	// Create threads and thread data
	threads: [NUM_THREADS]^thread.Thread
	thread_data: [NUM_THREADS]Thread_Data

	// Spawn threads
	for i in 0 ..< NUM_THREADS {
		thread_data[i] = Thread_Data {
			state      = state,
			width      = width,
			height     = height,
			work_queue = &work_queue,
			scale      = scale,
			offset_x   = offset_x,
			offset_y   = offset_y,
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

// Worker function for SIMD computation using dynamic work queue
compute_simd_worker :: proc(t: ^thread.Thread) {
	data := (^Thread_Data)(t.data)
	state := data.state
	width := data.width
	height := data.height
	work_queue := data.work_queue

	blocks := width / SIMD_WIDTH

	// Precompute rotation values
	cos_r := math.cos(state.rotation)
	sin_r := math.sin(state.rotation)
	scale_x := 3.5 / state.zoom
	scale_y := 2.0 / state.zoom

	// SIMD vectors for rotation and scaling
	width_vec := simd.f64x4{f64(width), f64(width), f64(width), f64(width)}
	height_vec := simd.f64x4{f64(height), f64(height), f64(height), f64(height)}
	half := simd.f64x4{0.5, 0.5, 0.5, 0.5}
	cos_r_vec := simd.f64x4{cos_r, cos_r, cos_r, cos_r}
	sin_r_vec := simd.f64x4{sin_r, sin_r, sin_r, sin_r}
	scale_x_vec := simd.f64x4{scale_x, scale_x, scale_x, scale_x}
	scale_y_vec := simd.f64x4{scale_y, scale_y, scale_y, scale_y}
	center_x_vec := simd.f64x4{state.center_x, state.center_x, state.center_x, state.center_x}
	center_y_vec := simd.f64x4{state.center_y, state.center_y, state.center_y, state.center_y}
	pixel_offsets := simd.f64x4{0, 1, 2, 3}

	// Dynamically grab rows from the work queue
	for {
		// Atomically fetch the next row to process
		py := sync.atomic_add(&work_queue.next_row, 1)

		// Check if we've processed all rows
		if py >= work_queue.total_rows {
			break
		}

		// Convert y to normalized coordinates
		py_vec := simd.f64x4{f64(py), f64(py), f64(py), f64(py)}
		norm_y_vec := py_vec / height_vec - half

		for blck in 0 ..< blocks {
			base := blck * SIMD_WIDTH

			// Convert x to normalized coordinates for 4 pixels
			base_vec := simd.f64x4{f64(base), f64(base), f64(base), f64(base)} + pixel_offsets
			norm_x_vec := base_vec / width_vec - half

			// Apply rotation
			rotated_x_vec := norm_x_vec * cos_r_vec - norm_y_vec * sin_r_vec
			rotated_y_vec := norm_x_vec * sin_r_vec + norm_y_vec * cos_r_vec

			// Scale to world coordinates
			x0_vec := rotated_x_vec * scale_x_vec + center_x_vec
			y0_vec := rotated_y_vec * scale_y_vec + center_y_vec

			// Compute iterations for 4 pixels simultaneously
			iterations, magnitudes := iterate_simd(x0_vec, y0_vec, state.max_iterations)

			// Convert to colors and store
			for i in 0 ..< SIMD_WIDTH {
				px := base + i
				color := visual.Compute_pixel_color(
					iterations[i],
					magnitudes[i],
					state.use_smooth_coloring,
					state.max_iterations,
					state.current_palette,
				)
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
