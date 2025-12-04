package mandelbrot

import app "../app"

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

// Compute Mandelbrot set using CPU (scalar or SIMD)
Compute :: proc(state: ^app.App_State, width: int, height: int) {
	if state.use_simd {
		compute_simd(state, width, height)
	} else {
		compute_scalar(state, width, height)
	}
}
