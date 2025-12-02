package renderer

import app "../app"
import mb "../mandelbrot"
import "core:fmt"
import "core:time"

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
