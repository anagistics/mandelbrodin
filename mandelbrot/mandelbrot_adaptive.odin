package mandelbrot

import app "../app"
import visual "../visual"
import "core:math"
import "core:sync"
import "core:thread"

// Thread data for adaptive coloring first pass
Thread_Data_Adaptive_Pass1 :: struct {
	state:       ^app.App_State,
	iterations:  []u64, // Shared iteration buffer
	magnitudes:  []f64, // Shared magnitude buffer
	width:       int,
	height:      int,
	work_queue:  ^Work_Queue,
	scale:       f64,
	offset_x:    f64,
	offset_y:    f64,
}

// Thread data for adaptive coloring second pass
Thread_Data_Adaptive_Pass2 :: struct {
	state:       ^app.App_State,
	iterations:  []u64,
	magnitudes:  []f64,
	histogram:   ^visual.Histogram,
	width:       int,
	height:      int,
	work_queue:  ^Work_Queue,
}

// Compute Mandelbrot with adaptive coloring (two-pass algorithm)
compute_adaptive :: proc(state: ^app.App_State, width: int, height: int) {
	pixel_count := width * height

	// Allocate temporary buffers for iteration data
	iterations := make([]u64, pixel_count)
	defer delete(iterations)

	magnitudes := make([]f64, pixel_count)
	defer delete(magnitudes)

	// Pass 1: Compute iterations
	{
		scale := 3.5 / state.zoom
		offset_x := state.center_x - (1.75 / state.zoom)
		offset_y := state.center_y - (1.0 / state.zoom)

		work_queue := Work_Queue{next_row = 0, total_rows = height, completed_rows = 0}
		threads: [NUM_THREADS]^thread.Thread
		thread_data: [NUM_THREADS]Thread_Data_Adaptive_Pass1

		for i in 0 ..< NUM_THREADS {
			thread_data[i] = Thread_Data_Adaptive_Pass1 {
				state      = state,
				iterations = iterations,
				magnitudes = magnitudes,
				width      = width,
				height     = height,
				work_queue = &work_queue,
				scale      = scale,
				offset_x   = offset_x,
				offset_y   = offset_y,
			}

			threads[i] = thread.create(compute_adaptive_pass1_worker)
			threads[i].data = &thread_data[i]
			thread.start(threads[i])
		}

		for i in 0 ..< NUM_THREADS {
			thread.join(threads[i])
			thread.destroy(threads[i])
		}
	}

	// Pass 2: Build histogram
	histogram := visual.Build_Histogram(iterations, state.max_iterations)
	defer visual.Destroy_Histogram(&histogram)

	// Pass 3: Apply adaptive coloring
	{
		work_queue := Work_Queue{next_row = 0, total_rows = height, completed_rows = 0}
		threads: [NUM_THREADS]^thread.Thread
		thread_data: [NUM_THREADS]Thread_Data_Adaptive_Pass2

		for i in 0 ..< NUM_THREADS {
			thread_data[i] = Thread_Data_Adaptive_Pass2 {
				state      = state,
				iterations = iterations,
				magnitudes = magnitudes,
				histogram  = &histogram,
				width      = width,
				height     = height,
				work_queue = &work_queue,
			}

			threads[i] = thread.create(compute_adaptive_pass2_worker)
			threads[i].data = &thread_data[i]
			thread.start(threads[i])
		}

		for i in 0 ..< NUM_THREADS {
			thread.join(threads[i])
			thread.destroy(threads[i])
		}
	}
}

// Worker for pass 1: compute iterations only
compute_adaptive_pass1_worker :: proc(t: ^thread.Thread) {
	N :: 8
	data := (^Thread_Data_Adaptive_Pass1)(t.data)
	state := data.state
	width := data.width
	height := data.height
	work_queue := data.work_queue
	iterations := data.iterations
	magnitudes := data.magnitudes

	blocks := width / N
	px: [N]int
	x0: [N]f64
	y0: [N]f64

	// Precompute rotation values
	cos_r := math.cos(state.rotation)
	sin_r := math.sin(state.rotation)
	scale_x := 3.5 / state.zoom
	scale_y := 2.0 / state.zoom

	for {
		py := sync.atomic_add(&work_queue.next_row, 1)
		if py >= work_queue.total_rows {
			break
		}

		norm_y := f64(py) / f64(height) - 0.5

		for blck in 0 ..< blocks {
			base := blck * N
			#unroll for i in 0 ..< N {
				px[i] = base + i

				norm_x := f64(px[i]) / f64(width) - 0.5

				// Apply rotation
				rotated_x := norm_x * cos_r - norm_y * sin_r
				rotated_y := norm_x * sin_r + norm_y * cos_r

				// Scale to world coordinates
				x0[i] = rotated_x * scale_x + state.center_x
				y0[i] = rotated_y * scale_y + state.center_y

				// Compute iteration count
				iter, mag_sq := iterate(x0[i], y0[i], state.max_iterations)

				idx := py * width + px[i]
				iterations[idx] = iter
				magnitudes[idx] = mag_sq
			}
		}

		// Update progress tracking (Pass 1: 0-33%)
		completed := sync.atomic_add(&work_queue.completed_rows, 1)
		if state.export_in_progress {
			state.export_progress = f32(completed) / f32(work_queue.total_rows) * 0.33
		}
	}
}

// Worker for pass 2: apply adaptive coloring
compute_adaptive_pass2_worker :: proc(t: ^thread.Thread) {
	data := (^Thread_Data_Adaptive_Pass2)(t.data)
	state := data.state
	width := data.width
	height := data.height
	work_queue := data.work_queue
	iterations := data.iterations
	magnitudes := data.magnitudes
	histogram := data.histogram

	for {
		py := sync.atomic_add(&work_queue.next_row, 1)
		if py >= work_queue.total_rows {
			break
		}

		for px in 0 ..< width {
			idx := py * width + px
			iter := iterations[idx]
			mag_sq := magnitudes[idx]

			// Apply adaptive coloring
			color := visual.Compute_Color_Adaptive(
				iter,
				mag_sq,
				state.use_smooth_coloring,
				histogram,
				state.current_palette,
			)
			state.pixels[idx] = color
		}

		// Update progress tracking (Pass 2: 33-50%)
		completed := sync.atomic_add(&work_queue.completed_rows, 1)
		if state.export_in_progress {
			state.export_progress = 0.33 + f32(completed) / f32(work_queue.total_rows) * 0.17
		}
	}
}
