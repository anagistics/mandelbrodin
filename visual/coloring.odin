package visual

import "core:math"

// Compute pixel color from iteration count and magnitude
Compute_pixel_color :: proc(
	iter: u64,
	magnitude_sq: f64,
	use_smooth_coloring: bool,
	max_iterations: u64,
	palette: Gradient_Palette,
) -> u32 {
	color: u32
	if use_smooth_coloring {
		smooth_iter := calculate_smooth_iteration(iter, magnitude_sq)
		color = compute_color_smooth(
			smooth_iter,
			max_iterations,
			palette,
		)
	} else {
		color = compute_color(iter, max_iterations, palette)
	}
	return color
}

// Linear interpolation between two values
lerp :: proc(a: f64, b: f64, t: f64) -> f64 {
	return a + (b - a) * t
}

// Interpolate color from gradient
interpolate_color :: proc(palette: Gradient_Palette, t: f64) -> (u8, u8, u8) {
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

compute_color :: proc(iter: u64, max_iterations: u64, palette: Gradient_Palette) -> u32 {
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
	palette: Gradient_Palette,
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
