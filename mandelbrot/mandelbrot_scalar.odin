package mandelbrot

import app "../app"
import visual "../visual"
import "core:math"
import "core:sync"
import "core:thread"

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
