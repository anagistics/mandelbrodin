package visual

import "core:math"

// Histogram structure for adaptive coloring
Histogram :: struct {
	bins:       []int, // Bin counts
	total:      int, // Total pixel count
	cdf:        []f64, // Cumulative distribution function
	max_iter:   u64, // Maximum iterations
}

// Create histogram from iteration data
Build_Histogram :: proc(iterations: []u64, max_iterations: u64) -> Histogram {
	// Create histogram with one bin per iteration value
	bin_count := int(max_iterations) + 1
	histogram := Histogram {
		bins     = make([]int, bin_count),
		total    = len(iterations),
		cdf      = make([]f64, bin_count),
		max_iter = max_iterations,
	}

	// Count iterations
	for iter in iterations {
		if int(iter) < bin_count {
			histogram.bins[iter] += 1
		}
	}

	// Compute cumulative distribution function (CDF)
	cumulative := 0
	for i in 0 ..< bin_count {
		cumulative += histogram.bins[i]
		// Normalize to [0, 1] range
		histogram.cdf[i] = f64(cumulative) / f64(histogram.total)
	}

	return histogram
}

// Destroy histogram and free memory
Destroy_Histogram :: proc(hist: ^Histogram) {
	delete(hist.bins)
	delete(hist.cdf)
}

// Map iteration to color using histogram equalization
Map_Iteration_Adaptive :: proc(iter: u64, histogram: ^Histogram) -> f64 {
	// For pixels that reached max iterations (in the set), return 1.0 (black)
	if iter >= histogram.max_iter {
		return 1.0
	}

	// Use CDF as the mapping (histogram equalization)
	if int(iter) < len(histogram.cdf) {
		return histogram.cdf[iter]
	}

	// Fallback
	return f64(iter) / f64(histogram.max_iter)
}

// Compute pixel color using adaptive histogram equalization
Compute_Color_Adaptive :: proc(
	iter: u64,
	magnitude_sq: f64,
	use_smooth_coloring: bool,
	histogram: ^Histogram,
	palette: Gradient_Palette,
) -> u32 {
	// For smooth coloring, we use the smooth iteration value
	smooth_iter: f64
	if use_smooth_coloring && magnitude_sq > 1.0 {
		smooth_iter = calculate_smooth_iteration(iter, magnitude_sq)
	} else {
		smooth_iter = f64(iter)
	}

	// Apply adaptive mapping
	t := Map_Iteration_Adaptive(u64(smooth_iter), histogram)

	// Handle max iterations (inside set) - return black
	if t >= 1.0 {
		return 0xFF000000
	}

	// Interpolate color from palette
	r, g, b := interpolate_color(palette, t)
	return 0xFF000000 | (u32(r) << 16) | (u32(g) << 8) | u32(b)
}
