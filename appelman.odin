package main

import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"
import "core:time"
import gl "vendor:OpenGL"
import imgui "vendor:imgui"
import imgui_opengl3 "vendor:imgui/imgui_impl_opengl3"
import imgui_sdl2 "vendor:imgui/imgui_impl_sdl2"
import SDL "vendor:sdl2"

import app "app"
import mb "mandelbrot"
import renderer "renderer"
import ui "ui"
import visual "visual"

WIDTH :: 800
HEIGHT :: 600
MAX_ITER :: 256
PANEL_WIDTH :: 300
WINDOW_WIDTH :: WIDTH + PANEL_WIDTH
WINDOW_HEIGHT :: HEIGHT

// Convert screen coordinates to world coordinates
screen_to_world :: proc(
	state: ^app.App_State,
	screen_x, screen_y: i32,
	width, height: int,
) -> (
	f64,
	f64,
) {
	// Convert to normalized coordinates [-0.5, 0.5] centered at origin
	norm_x := f64(screen_x) / f64(width) - 0.5
	norm_y := f64(screen_y) / f64(height) - 0.5

	// Apply rotation
	cos_r := math.cos(state.rotation)
	sin_r := math.sin(state.rotation)
	rotated_x := norm_x * cos_r - norm_y * sin_r
	rotated_y := norm_x * sin_r + norm_y * cos_r

	// Scale to world coordinates
	scale_x := 3.5 / state.zoom
	scale_y := 2.0 / state.zoom

	world_x := rotated_x * scale_x + state.center_x
	world_y := rotated_y * scale_y + state.center_y

	return world_x, world_y
}

main :: proc() {
	state := app.App_State {
		pixels              = make([]u32, WIDTH * HEIGHT),
		zoom                = 1.0,
		center_x            = -0.5,
		center_y            = 0.0,
		rotation            = 0.0,
		max_iterations      = MAX_ITER,
		needs_recompute     = true,
		computation_time_ms = 0.0,
		use_simd            = true, // Use SIMD by default
		use_gpu             = true, // Use GPU by default
		use_smooth_coloring = true, // Use smooth coloring by default
		palette             = "Classic", // Default palette name
		current_palette     = visual.DEFAULT_PALETTE, // Default palette data
		history_index       = -1, // No history yet
		bookmarks_dir       = "bookmarks",
		palettes_dir        = "palettes",
		selected_bookmark   = -1,
		editing_bookmark    = -1,
		export_resolution   = 2, // Default to 4K
		export_filename     = "mandelbrot_export", // Default export filename
		export_compression  = 1, // Default to fast compression (level 1)
		export_in_progress  = false,
		export_progress     = 0.0,
		active_tab          = 0, // Default to Controls tab
		show_help           = false, // Help overlay hidden by default
	}
	defer delete(state.pixels)
	defer delete(state.history)
	defer delete(state.bookmarks)
	defer delete(state.palettes)

	if SDL.Init(SDL.INIT_VIDEO) != 0 {
		fmt.eprintln("SDL_Init Error:", SDL.GetError())
		return
	}
	defer SDL.Quit()

	// Try to create OpenGL 4.3 context first (for compute shaders)
	// If that fails, fallback to 3.3 (fragment shaders only)
	opengl_major: i32 = 4
	opengl_minor: i32 = 3

	SDL.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, opengl_major)
	SDL.GL_SetAttribute(.CONTEXT_MINOR_VERSION, opengl_minor)
	SDL.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(SDL.GLprofile.CORE))

	window := SDL.CreateWindow(
		"Mandelbrot Set Explorer",
		SDL.WINDOWPOS_CENTERED,
		SDL.WINDOWPOS_CENTERED,
		WINDOW_WIDTH,
		HEIGHT,
		{.OPENGL, .SHOWN},
	)
	if window == nil {
		fmt.eprintln("SDL_CreateWindow Error:", SDL.GetError())
		return
	}
	defer SDL.DestroyWindow(window)

	// Raise and focus the window to ensure keyboard input works from the start
	SDL.RaiseWindow(window)

	gl_context := SDL.GL_CreateContext(window)
	if gl_context == nil {
		// OpenGL 4.3 failed, try fallback to 3.3
		fmt.println("Failed to create OpenGL 4.3 context, trying 3.3...")
		opengl_major = 3
		opengl_minor = 3

		SDL.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, opengl_major)
		SDL.GL_SetAttribute(.CONTEXT_MINOR_VERSION, opengl_minor)

		gl_context = SDL.GL_CreateContext(window)
		if gl_context == nil {
			fmt.eprintln("SDL_GL_CreateContext Error:", SDL.GetError())
			return
		}
	}
	defer SDL.GL_DeleteContext(gl_context)

	// Load OpenGL functions for the version we got
	gl.load_up_to(int(opengl_major), int(opengl_minor), SDL.gl_set_proc_address)

	// Log OpenGL version information
	gl_version := gl.GetString(gl.VERSION)
	gl_renderer := gl.GetString(gl.RENDERER)
	gl_glsl_version := gl.GetString(gl.SHADING_LANGUAGE_VERSION)
	fmt.printf("OpenGL Version: %s\n", gl_version)
	fmt.printf("Renderer: %s\n", gl_renderer)
	fmt.printf("GLSL Version: %s\n", gl_glsl_version)

	// Enable vsync
	SDL.GL_SetSwapInterval(1)

	// Initialize ImGui
	imgui.CHECKVERSION()
	imgui.CreateContext(nil)
	defer imgui.DestroyContext(nil)

	io := imgui.GetIO()
	io.ConfigFlags += {.NavEnableKeyboard}

	imgui_sdl2.InitForOpenGL(window, gl_context)
	defer imgui_sdl2.Shutdown()

	// Use appropriate GLSL version for ImGui
	glsl_version_string: cstring = "#version 330"
	if opengl_major >= 4 {
		glsl_version_string = "#version 430"
	}
	imgui_opengl3.Init(glsl_version_string)
	defer imgui_opengl3.Shutdown()

	imgui.StyleColorsDark(nil)

	// Initialize renderer
	render_context: renderer.Renderer
	if !renderer.Init(&render_context, WIDTH, HEIGHT) {
		fmt.eprintln("Failed to initialize renderer")
		return
	}
	defer renderer.Destroy(&render_context)

	// Initialize compute shader (for high-res exports)
	renderer.Init_Compute_Shader(&render_context)

	// Load palettes
	state.palettes = visual.load_palettes(state.palettes_dir)
	if len(state.palettes) == 0 {
		fmt.eprintln("Warning: No palettes loaded, using default palette")
		state.palette = "Classic"
		state.current_palette = visual.DEFAULT_PALETTE
	}

	// Set initial palette (will use loaded palette or fall back to default)
	app.set_palette(&state, "Classic")

	// Save initial state to history
	app.history_save(&state)

	// Load bookmarks
	app.load_bookmarks(&state)

	running := true
	for running {
		event: SDL.Event
		for SDL.PollEvent(&event) {
			imgui_sdl2.ProcessEvent(&event)
			io := imgui.GetIO()

			#partial switch event.type {
			case .QUIT:
				running = false
			case .KEYDOWN:
				mod_state := SDL.GetModState()
				ctrl_pressed := (mod_state & SDL.KMOD_CTRL) != SDL.Keymod{}
				shift_pressed := (mod_state & SDL.KMOD_SHIFT) != SDL.Keymod{}
				alt_pressed := (mod_state & SDL.KMOD_ALT) != SDL.Keymod{}
				key := event.key.keysym.sym

				// Handle global shortcuts regardless of ImGui keyboard capture
				// (These should work even when ImGui navigation is active)
				handled := false

				// F1 for help (global shortcut)
				if key == .F1 {
					state.show_help = !state.show_help
					handled = true
				}

				// Ctrl+1/2/3 for tab switching (global shortcuts)
				if !handled && ctrl_pressed && (key == .NUM1 || key == .KP_1) {
					state.active_tab = 0 // Controls tab
					handled = true
				}
				if !handled && ctrl_pressed && (key == .NUM2 || key == .KP_2) {
					state.active_tab = 1 // Bookmarks tab
					handled = true
				}
				if !handled && ctrl_pressed && (key == .NUM3 || key == .KP_3) {
					state.active_tab = 2 // Export tab
					handled = true
				}

				// Ctrl+S for quick export (global shortcut)
				if !handled && ctrl_pressed && key == .S {
					if len(state.export_filename) > 0 {
						output_filename := state.export_filename
						if !strings.has_suffix(output_filename, ".png") {
							output_filename = fmt.tprintf("%s.png", output_filename)
						}

						resolution := app.EXPORT_RESOLUTIONS[state.export_resolution]
						state.export_in_progress = true

						success := renderer.export_image_compute(
							&render_context,
							&state,
							resolution.width,
							resolution.height,
							output_filename,
						)

						state.export_in_progress = false
					}
					handled = true
				}

				// Alt+Left/Right for history navigation (global shortcuts)
				if !handled && alt_pressed && key == .LEFT {
					app.history_back(&state)
					handled = true
				}
				if !handled && alt_pressed && key == .RIGHT {
					app.history_forward(&state)
					handled = true
				}

				// ESC to quit (global shortcut)
				if !handled && key == .ESCAPE {
					running = false
					handled = true
				}

				// Navigation shortcuts - work unless user is typing in a text field
				// These should work even when ImGui keyboard navigation is active
				if !handled && !io.WantTextInput {
					// Arrow keys for panning
					if key == .LEFT || key == .RIGHT || key == .UP || key == .DOWN {
						app.history_save(&state)

						// Pan distance: normal or faster with Shift
						pan_distance := shift_pressed ? 0.1 : 0.05
						scale_x := 3.5 / state.zoom
						scale_y := 2.0 / state.zoom

						// Apply rotation to pan direction
						cos_r := math.cos(state.rotation)
						sin_r := math.sin(state.rotation)

						dx, dy: f64 = 0, 0
						if key == .LEFT {
							dx = -pan_distance
						} else if key == .RIGHT {
							dx = pan_distance
						} else if key == .UP {
							dy = -pan_distance
						} else if key == .DOWN {
							dy = pan_distance
						}

						// Rotate the pan direction
						rotated_dx := dx * cos_r - dy * sin_r
						rotated_dy := dx * sin_r + dy * cos_r

						state.center_x += rotated_dx * scale_x
						state.center_y += rotated_dy * scale_y
						state.needs_recompute = true
						handled = true
					}

					// PgUp and PgDown for zooming
					if key == .PAGEUP {
						app.history_save(&state)
						state.zoom *= 1.5
						state.needs_recompute = true
						handled = true
					}
					if key == .PAGEDOWN {
						app.history_save(&state)
						state.zoom /= 1.5
						state.needs_recompute = true
						handled = true
					}

					// , and . keys for rotation
					if key == .COMMA {
						app.history_save(&state)
						state.rotation += math.to_radians(f64(5.0))
						state.rotation = math.mod(state.rotation, 2.0 * math.PI)
						if state.rotation < 0 {
							state.rotation += 2.0 * math.PI
						}
						state.needs_recompute = true
						handled = true
					}
					if key == .PERIOD {
						app.history_save(&state)
						state.rotation -= math.to_radians(f64(5.0))
						state.rotation = math.mod(state.rotation, 2.0 * math.PI)
						if state.rotation < 0 {
							state.rotation += 2.0 * math.PI
						}
						state.needs_recompute = true
						handled = true
					}
				}

			case .MOUSEWHEEL:
				// Only handle mouse wheel if not over ImGui window
				if !io.WantCaptureMouse && event.wheel.x >= 0 && event.wheel.x < WIDTH {
					mouse_x, mouse_y: i32
					SDL.GetMouseState(&mouse_x, &mouse_y)

					// Only handle if mouse is over the Mandelbrot area
					if mouse_x >= 0 && mouse_x < WIDTH && mouse_y >= 0 && mouse_y < HEIGHT {
						// Check if CTRL is pressed
						mod_state := SDL.GetModState()
						ctrl_pressed := (mod_state & SDL.KMOD_CTRL) != SDL.Keymod{}

						// Save current state before changing
						app.history_save(&state)

						if ctrl_pressed {
							// CTRL + Mouse Wheel: Rotate
							rotation_increment := math.to_radians(f64(5.0)) // 5 degrees
							if event.wheel.y > 0 {
								state.rotation += rotation_increment
							} else if event.wheel.y < 0 {
								state.rotation -= rotation_increment
							}
							// Normalize rotation to [0, 2π)
							state.rotation = math.mod(state.rotation, 2.0 * math.PI)
							if state.rotation < 0 {
								state.rotation += 2.0 * math.PI
							}
						} else {
							// Normal Mouse Wheel: Zoom
							// Get world coordinates before zoom
							world_x, world_y := screen_to_world(
								&state,
								mouse_x,
								mouse_y,
								WIDTH,
								HEIGHT,
							)

							// Zoom in or out
							zoom_factor := 1.2
							if event.wheel.y > 0 {
								state.zoom *= zoom_factor
							} else if event.wheel.y < 0 {
								state.zoom /= zoom_factor
							}

							// Adjust center to keep mouse position fixed in world coordinates
							new_world_x, new_world_y := screen_to_world(
								&state,
								mouse_x,
								mouse_y,
								WIDTH,
								HEIGHT,
							)
							state.center_x += world_x - new_world_x
							state.center_y += world_y - new_world_y
						}

						state.needs_recompute = true
					}
				}

			case .MOUSEBUTTONDOWN:
				if !io.WantCaptureMouse {
					mouse_x := event.button.x
					mouse_y := event.button.y

					// Only handle if in Mandelbrot area
					if mouse_x >= 0 && mouse_x < WIDTH && mouse_y >= 0 && mouse_y < HEIGHT {
						if event.button.button == SDL.BUTTON_LEFT {
							// Check if shift is held for box zoom
							keyboard_state := SDL.GetKeyboardState(nil)
							if keyboard_state[SDL.Scancode.LSHIFT] == 1 ||
							   keyboard_state[SDL.Scancode.RSHIFT] == 1 {
								// Start box zoom
								state.box_zoom_active = true
								state.box_start_x = mouse_x
								state.box_start_y = mouse_y
								state.box_end_x = mouse_x
								state.box_end_y = mouse_y
							} else {
								// Simple click to recenter
								app.history_save(&state)
								world_x, world_y := screen_to_world(
									&state,
									mouse_x,
									mouse_y,
									WIDTH,
									HEIGHT,
								)
								state.center_x = world_x
								state.center_y = world_y
								state.needs_recompute = true
							}
						} else if event.button.button == SDL.BUTTON_RIGHT {
							// Start dragging to pan
							state.mouse_dragging = true
							state.drag_start_x = f64(mouse_x)
							state.drag_start_y = f64(mouse_y)
							state.center_at_drag = {state.center_x, state.center_y}
						}
					}
				}

			case .MOUSEBUTTONUP:
				if event.button.button == SDL.BUTTON_LEFT && state.box_zoom_active {
					// Complete box zoom
					state.box_zoom_active = false

					// Calculate box dimensions
					x1 := min(state.box_start_x, state.box_end_x)
					y1 := min(state.box_start_y, state.box_end_y)
					x2 := max(state.box_start_x, state.box_end_x)
					y2 := max(state.box_start_y, state.box_end_y)

					// Only zoom if box is large enough
					if abs(x2 - x1) > 10 && abs(y2 - y1) > 10 {
						// Save current state before changing
						app.history_save(&state)

						// Get world coordinates of box corners
						world_x1, world_y1 := screen_to_world(&state, x1, y1, WIDTH, HEIGHT)
						world_x2, world_y2 := screen_to_world(&state, x2, y2, WIDTH, HEIGHT)

						// Calculate new center
						state.center_x = (world_x1 + world_x2) / 2.0
						state.center_y = (world_y1 + world_y2) / 2.0

						// Calculate new zoom to fit box
						box_width := abs(world_x2 - world_x1)
						box_height := abs(world_y2 - world_y1)
						zoom_x := 3.5 / box_width
						zoom_y := 2.0 / box_height
						state.zoom = min(zoom_x, zoom_y)

						state.needs_recompute = true
					}
				} else if event.button.button == SDL.BUTTON_RIGHT {
					// Save history when pan is complete
					if state.mouse_dragging {
						app.history_save(&state)
					}
					state.mouse_dragging = false
				}

			case .MOUSEMOTION:
				if state.mouse_dragging {
					// Pan view based on drag
					mouse_x := f64(event.motion.x)
					mouse_y := f64(event.motion.y)

					dx := mouse_x - state.drag_start_x
					dy := mouse_y - state.drag_start_y

					// Convert pixel delta to world delta
					scale := 3.5 / state.zoom
					world_dx := -(dx / f64(WIDTH)) * scale
					world_dy := -(dy / f64(HEIGHT)) * (2.0 / state.zoom)

					state.center_x = state.center_at_drag.x + world_dx
					state.center_y = state.center_at_drag.y + world_dy
					state.needs_recompute = true
				} else if state.box_zoom_active {
					// Update box end position
					state.box_end_x = event.motion.x
					state.box_end_y = event.motion.y
				}
			}
		}

		// Recompute if needed (CPU mode only)
		if state.needs_recompute && !state.use_gpu {
			start_time := time.now()
			mb.Compute(&state, WIDTH, HEIGHT)
			end_time := time.now()
			duration := time.diff(start_time, end_time)
			state.computation_time_ms = time.duration_milliseconds(duration)
			state.needs_recompute = false
		}

		// Start ImGui frame
		imgui_opengl3.NewFrame()
		imgui_sdl2.NewFrame()
		imgui.NewFrame()

		// Render Mandelbrot
		gl.Viewport(0, 0, WIDTH, HEIGHT)
		gl.Scissor(0, 0, WIDTH, HEIGHT)
		gl.Enable(gl.SCISSOR_TEST)
		gl.ClearColor(0.0, 0.0, 0.0, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		if state.use_gpu {
			// GPU rendering - compute in shader
			start_time := time.now()
			renderer.Render_GPU(&render_context, &state, WIDTH, HEIGHT)
			end_time := time.now()
			duration := time.diff(start_time, end_time)
			state.computation_time_ms = time.duration_milliseconds(duration)
			state.needs_recompute = false
		} else {
			// CPU rendering - display precomputed texture
			renderer.Render_CPU(&render_context, state.pixels, WIDTH, HEIGHT)
		}

		gl.Disable(gl.SCISSOR_TEST)

		// Restore viewport to full window for ImGui
		gl.Viewport(0, 0, WINDOW_WIDTH, HEIGHT)

		// Draw box zoom selection if active using ImGui overlay
		if state.box_zoom_active {
			x1 := f32(min(state.box_start_x, state.box_end_x))
			y1 := f32(min(state.box_start_y, state.box_end_y))
			x2 := f32(max(state.box_start_x, state.box_end_x))
			y2 := f32(max(state.box_start_y, state.box_end_y))

			draw_list := imgui.GetBackgroundDrawList()
			imgui.DrawList_AddRectFilled(
				draw_list,
				{x1, y1},
				{x2, y2},
				imgui.ColorConvertFloat4ToU32({1, 1, 1, 0.2}),
			)
			imgui.DrawList_AddRect(
				draw_list,
				{x1, y1},
				{x2, y2},
				imgui.ColorConvertFloat4ToU32({1, 1, 1, 1}),
				0,
				{},
				2,
			)
		}

		// ImGui Tabbed Panel
		ui.Render_tabbed_panel(&render_context, &state, WIDTH, PANEL_WIDTH, HEIGHT)

		// Help overlay
		if state.show_help {
			ui.Render_help_overlay(&state)
		}

		// Render ImGui
		imgui.Render()
		imgui_opengl3.RenderDrawData(imgui.GetDrawData())

		SDL.GL_SwapWindow(window)
	}
}
