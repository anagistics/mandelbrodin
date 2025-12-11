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

	fmt.println("\n=== 8K Export Benchmark ===\n")

	width := 7680
	height := 4320

	fmt.printf("Testing 8K (%dx%d) export...\n", width, height)

	start := time.now()
	success := renderer.export_image_compute(&render_context, &state, width, height, "benchmark_8k.png")
	duration := time.since(start)

	if success {
		fmt.printf("\n✓ Completed in %.2f ms\n", time.duration_milliseconds(duration))
		file_info, err := os.stat("benchmark_8k.png")
		if err == 0 {
			fmt.printf("  File size: %.2f MB\n", f64(file_info.size) / 1024.0 / 1024.0)
		}
	}
}
