package main

import "core:fmt"
import "core:time"
import "core:os"
import gl "vendor:OpenGL"
import SDL "vendor:sdl2"
import app "app"
import renderer "renderer"
import visual "visual"

main :: proc() {
	SDL.Init(SDL.INIT_VIDEO)
	defer SDL.Quit()

	SDL.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 4)
	SDL.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
	SDL.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(SDL.GLprofile.CORE))

	window := SDL.CreateWindow("Test", SDL.WINDOWPOS_UNDEFINED, SDL.WINDOWPOS_UNDEFINED, 800, 600, {.OPENGL, .HIDDEN})
	defer SDL.DestroyWindow(window)

	gl_context := SDL.GL_CreateContext(window)
	defer SDL.GL_DeleteContext(gl_context)

	gl.load_up_to(4, 3, SDL.gl_set_proc_address)

	render_context: renderer.Renderer
	renderer.Init(&render_context, 800, 600)
	defer renderer.Destroy(&render_context)

	renderer.Init_Compute_Shader(&render_context)

	state := app.App_State{
		pixels = make([]u32, 800 * 600),
		zoom = 1.0,
		center_x = -0.5,
		center_y = 0.0,
		rotation = 0.0,
		max_iterations = 256,
		use_smooth_coloring = true,
		current_palette = visual.DEFAULT_PALETTE,
	}
	defer delete(state.pixels)

	fmt.println("\n=== libpng Compression Benchmark ===\n")

	// Test resolutions
	test_cases := []struct{name: string, width: int, height: int}{
		{"4K (3840×2160)", 3840, 2160},
		{"8K (7680×4320)", 7680, 4320},
	}

	// Compression levels to test
	compression_levels := []struct{level: int, name: string}{
		{0, "No compression (level 0)"},
		{1, "Fastest (level 1)"},
		{3, "Fast (level 3)"},
		{6, "Default (level 6)"},
		{9, "Best (level 9)"},
		{-1, "stb_image_write (baseline)"},
	}

	for test_case in test_cases {
		fmt.printf("\n=== Testing %s ===\n\n", test_case.name)

		for comp_test in compression_levels {
			filename := fmt.tprintf("benchmark_%s_comp%d.png", test_case.name, comp_test.level)

			fmt.printf("Testing %s: ", comp_test.name)

			start := time.now()

			// Generate pixels using compute shader
			compute_start := time.now()
			renderer.export_image_compute(&render_context, &state, test_case.width, test_case.height, filename, comp_test.level)
			duration := time.since(start)

			fmt.printf("%.0f ms", time.duration_milliseconds(duration))

			// Get file size
			file_info, err := os.stat(filename)
			if err == 0 {
				fmt.printf(" | %.2f MB", f64(file_info.size) / 1024.0 / 1024.0)
			}

			// Clean up test file
			os.remove(filename)

			fmt.println()
		}
	}

	fmt.println("\n=== Benchmark Complete ===")
}
