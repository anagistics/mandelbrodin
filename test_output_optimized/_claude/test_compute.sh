#!/bin/bash
# Test script for GPU compute shader benchmarking

echo "=== Mandelbrot GPU Compute Shader Test ==="
echo ""
echo "This script will test GPU compute shader exports at various resolutions"
echo "and compare with CPU rendering performance."
echo ""

# Create test output directory
mkdir -p test_output

# Test resolutions (index into EXPORT_RESOLUTIONS array)
# 0: 1920x1080 (Full HD)
# 1: 2560x1440 (2K)
# 2: 3840x2160 (4K)
# 3: 5120x2880 (5K)
# 4: 7680x4320 (8K)

echo "Test 1: Export at 1920x1080 (Full HD) using GPU"
echo "------------------------------------------------"

# Create a simple Odin test program that exports at specific resolution
cat > test_export.odin << 'EOF'
package main

import "core:fmt"
import "core:os"
import "core:time"
import gl "vendor:OpenGL"
import SDL "vendor:sdl2"
import app "app"
import renderer "renderer"
import visual "visual"
import mb "mandelbrot"

main :: proc() {
	// Initialize SDL
	if SDL.Init(SDL.INIT_VIDEO) != 0 {
		fmt.eprintln("SDL_Init Error:", SDL.GetError())
		return
	}
	defer SDL.Quit()

	// Set OpenGL attributes for 4.3
	SDL.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 4)
	SDL.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
	SDL.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(SDL.GLprofile.CORE))

	// Create hidden window for OpenGL context
	window := SDL.CreateWindow(
		"Test",
		SDL.WINDOWPOS_UNDEFINED,
		SDL.WINDOWPOS_UNDEFINED,
		800,
		600,
		{.OPENGL, .HIDDEN},
	)
	if window == nil {
		fmt.eprintln("SDL_CreateWindow Error:", SDL.GetError())
		return
	}
	defer SDL.DestroyWindow(window)

	// Create OpenGL context
	gl_context := SDL.GL_CreateContext(window)
	if gl_context == nil {
		fmt.eprintln("SDL_GL_CreateContext Error:", SDL.GetError())
		return
	}
	defer SDL.GL_DeleteContext(gl_context)

	// Load OpenGL functions
	gl.load_up_to(4, 3, SDL.gl_set_proc_address)

	// Print OpenGL version
	version := gl.GetString(gl.VERSION)
	fmt.printf("OpenGL Version: %s\n", version)

	// Initialize renderer
	render_context: renderer.Renderer
	if !renderer.Init(&render_context, 800, 600) {
		fmt.eprintln("Failed to initialize renderer")
		return
	}
	defer renderer.Destroy(&render_context)

	// Initialize compute shader
	compute_available := renderer.Init_Compute_Shader(&render_context)

	if !compute_available {
		fmt.eprintln("Compute shader not available!")
		return
	}

	// Create test state
	state := app.App_State{
		pixels              = make([]u32, 800 * 600),
		zoom                = 1.0,
		center_x            = -0.5,
		center_y            = 0.0,
		rotation            = 0.0,
		max_iterations      = 256,
		use_smooth_coloring = true,
		palette             = "Classic",
		current_palette     = visual.DEFAULT_PALETTE,
	}
	defer delete(state.pixels)

	// Test resolutions
	resolutions := []struct {
		name: string,
		width: int,
		height: int,
	}{
		{"1080p", 1920, 1080},
		{"4K", 3840, 2160},
		{"8K", 7680, 4320},
	}

	fmt.println("\n=== GPU Compute Shader Performance Test ===\n")

	// Test GPU exports
	for res in resolutions {
		filename := fmt.tprintf("test_output/gpu_%s.png", res.name)
		fmt.printf("Testing %s (%dx%d) GPU export...\n", res.name, res.width, res.height)

		start := time.now()
		success := renderer.export_image_compute(&render_context, &state, res.width, res.height, filename)
		duration := time.since(start)

		if success {
			fmt.printf("  ✓ Success: %.2f ms\n\n", time.duration_milliseconds(duration))
		} else {
			fmt.printf("  ✗ Failed\n\n")
		}
	}

	fmt.println("=== CPU Rendering Performance Test ===\n")

	// Test CPU exports for comparison
	for res in resolutions {
		filename := fmt.tprintf("test_output/cpu_%s.png", res.name)
		fmt.printf("Testing %s (%dx%d) CPU export...\n", res.name, res.width, res.height)

		success := renderer.export_image(&state, res.width, res.height, filename)

		if !success {
			fmt.printf("  ✗ Failed\n\n")
		}
	}

	fmt.println("\n=== Test Complete ===")
	fmt.println("Check test_output/ directory for exported images")
}
EOF

echo "Compiling test program..."
odin build test_export.odin -file -out:test_export

if [ $? -eq 0 ]; then
	echo "Running tests..."
	echo ""
	./test_export

	echo ""
	echo "=== Test Results ==="
	echo ""
	echo "Exported files:"
	ls -lh test_output/*.png 2>/dev/null || echo "No files created"

	echo ""
	echo "Cleaning up test program..."
	rm -f test_export.odin test_export
else
	echo "Failed to compile test program"
	exit 1
fi
