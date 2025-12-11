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
	// Initialize SDL (minimal setup)
	if SDL.Init(SDL.INIT_VIDEO) != 0 {
		fmt.eprintln("SDL init failed")
		return
	}
	defer SDL.Quit()

	SDL.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 4)
	SDL.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
	SDL.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(SDL.GLprofile.CORE))

	window := SDL.CreateWindow("Test", SDL.WINDOWPOS_UNDEFINED, SDL.WINDOWPOS_UNDEFINED, 800, 600, {.OPENGL, .HIDDEN})
	if window == nil {
		fmt.eprintln("Window creation failed")
		return
	}
	defer SDL.DestroyWindow(window)

	gl_context := SDL.GL_CreateContext(window)
	if gl_context == nil {
		fmt.eprintln("GL context creation failed")
		return
	}
	defer SDL.GL_DeleteContext(gl_context)

	gl.load_up_to(4, 3, SDL.gl_set_proc_address)

	// Initialize renderer
	render_context: renderer.Renderer
	if !renderer.Init(&render_context, 800, 600) {
		fmt.eprintln("Renderer init failed")
		return
	}
	defer renderer.Destroy(&render_context)

	renderer.Init_Compute_Shader(&render_context)

	// Create test state
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

	fmt.println("\n=== PNG Encoding Optimization Benchmark ===\n")

	// Test at 4K resolution
	width := 3840
	height := 2160

	fmt.printf("Testing 4K (%dx%d) export with optimized PNG encoding...\n", width, height)
	fmt.println("(Multi-threaded RGBA conversion + optimized PNG)")

	start := time.now()
	success := renderer.export_image_compute(&render_context, &state, width, height, "benchmark_4k.png")
	duration := time.since(start)

	if success {
		fmt.printf("\n✓ Export completed in %.2f ms\n", time.duration_milliseconds(duration))

		// Check file size
		file_info, err := os.stat("benchmark_4k.png")
		if err == 0 {
			fmt.printf("  File size: %.2f MB\n", f64(file_info.size) / 1024.0 / 1024.0)
		}
	} else {
		fmt.println("\n✗ Export failed")
	}

	fmt.println("\nDone!")
}
