package main

import "core:fmt"
import "core:mem"
import "core:time"
import imgui "vendor:imgui"
import imgui_sdl2 "vendor:imgui/imgui_impl_sdl2"
import imgui_sdlrenderer2 "vendor:imgui/imgui_impl_sdlrenderer2"
import SDL "vendor:sdl2"

import app "app"
import mb "mandelbrot"
import ui "ui"

WIDTH :: 800
HEIGHT :: 600
MAX_ITER :: 256

main :: proc() {
	state := app.App_State {
		pixels              = make([]u32, WIDTH * HEIGHT),
		zoom                = 1.0,
		center_x            = -0.5,
		center_y            = 0.0,
		max_iterations      = MAX_ITER,
		needs_recompute     = true,
		computation_time_ms = 0.0,
		use_simd            = true, // Use SIMD by default
	}
	defer delete(state.pixels)

	if SDL.Init(SDL.INIT_VIDEO) != 0 {
		fmt.eprintln("SDL_Init Error:", SDL.GetError())
		return
	}
	defer SDL.Quit()

	window := SDL.CreateWindow(
		"Mandelbrot Set - ImGui",
		SDL.WINDOWPOS_CENTERED,
		SDL.WINDOWPOS_CENTERED,
		WIDTH + 300,
		HEIGHT,
		SDL.WINDOW_SHOWN,
	)
	if window == nil {
		fmt.eprintln("SDL_CreateWindow Error:", SDL.GetError())
		return
	}
	defer SDL.DestroyWindow(window)

	renderer := SDL.CreateRenderer(window, -1, SDL.RENDERER_ACCELERATED)
	if renderer == nil {
		fmt.eprintln("SDL_CreateRenderer Error:", SDL.GetError())
		return
	}
	defer SDL.DestroyRenderer(renderer)

	// Initialize ImGui
	imgui.CHECKVERSION()
	imgui.CreateContext(nil)
	defer imgui.DestroyContext(nil)

	io := imgui.GetIO()
	io.ConfigFlags += {.NavEnableKeyboard}

	imgui_sdl2.InitForSDLRenderer(window, renderer)
	defer imgui_sdl2.Shutdown()

	imgui_sdlrenderer2.Init(renderer)
	defer imgui_sdlrenderer2.Shutdown()

	imgui.StyleColorsDark(nil)

	texture := SDL.CreateTexture(renderer, SDL.PixelFormatEnum.ARGB8888, .STATIC, WIDTH, HEIGHT)
	if texture == nil {
		fmt.eprintln("SDL_CreateTexture Error:", SDL.GetError())
		return
	}
	defer SDL.DestroyTexture(texture)

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
				if event.key.keysym.sym == .ESCAPE {
					running = false
				}

			case .MOUSEWHEEL:
				// Only handle mouse wheel if not over ImGui window
				if !io.WantCaptureMouse && event.wheel.x >= 0 && event.wheel.x < WIDTH {
					mouse_x, mouse_y: i32
					SDL.GetMouseState(&mouse_x, &mouse_y)

					// Only zoom if mouse is over the Mandelbrot area
					if mouse_x >= 0 && mouse_x < WIDTH && mouse_y >= 0 && mouse_y < HEIGHT {
						// Get world coordinates before zoom
						world_x, world_y := app.screen_to_world(&state, mouse_x, mouse_y, WIDTH, HEIGHT)

						// Zoom in or out
						zoom_factor := 1.2
						if event.wheel.y > 0 {
							state.zoom *= zoom_factor
						} else if event.wheel.y < 0 {
							state.zoom /= zoom_factor
						}

						// Adjust center to keep mouse position fixed in world coordinates
						new_world_x, new_world_y := app.screen_to_world(&state, mouse_x, mouse_y, WIDTH, HEIGHT)
						state.center_x += world_x - new_world_x
						state.center_y += world_y - new_world_y

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
							if keyboard_state[SDL.Scancode.LSHIFT] == 1 || keyboard_state[SDL.Scancode.RSHIFT] == 1 {
								// Start box zoom
								state.box_zoom_active = true
								state.box_start_x = mouse_x
								state.box_start_y = mouse_y
								state.box_end_x = mouse_x
								state.box_end_y = mouse_y
							} else {
								// Simple click to recenter
								world_x, world_y := app.screen_to_world(&state, mouse_x, mouse_y, WIDTH, HEIGHT)
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
						// Get world coordinates of box corners
						world_x1, world_y1 := app.screen_to_world(&state, x1, y1, WIDTH, HEIGHT)
						world_x2, world_y2 := app.screen_to_world(&state, x2, y2, WIDTH, HEIGHT)

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

		// Recompute if needed
		if state.needs_recompute {
			start_time := time.now()
			mb.Compute(&state, WIDTH, HEIGHT)
			end_time := time.now()
			duration := time.diff(start_time, end_time)
			state.computation_time_ms = time.duration_milliseconds(duration)

			SDL.UpdateTexture(texture, nil, raw_data(state.pixels), WIDTH * size_of(u32))
			state.needs_recompute = false
		}

		// Start ImGui frame
		imgui_sdlrenderer2.NewFrame()
		imgui_sdl2.NewFrame()
		imgui.NewFrame()

		// Render Mandelbrot texture
		SDL.SetRenderDrawColor(renderer, 0, 0, 0, 255)
		SDL.RenderClear(renderer)

		mandelbrot_rect := SDL.Rect{0, 0, WIDTH, HEIGHT}
		SDL.RenderCopy(renderer, texture, nil, &mandelbrot_rect)

		// Draw box zoom selection if active
		if state.box_zoom_active {
			x1 := min(state.box_start_x, state.box_end_x)
			y1 := min(state.box_start_y, state.box_end_y)
			x2 := max(state.box_start_x, state.box_end_x)
			y2 := max(state.box_start_y, state.box_end_y)

			box_rect := SDL.Rect{x1, y1, x2 - x1, y2 - y1}

			// Draw semi-transparent fill
			SDL.SetRenderDrawBlendMode(renderer, .BLEND)
			SDL.SetRenderDrawColor(renderer, 255, 255, 255, 50)
			SDL.RenderFillRect(renderer, &box_rect)

			// Draw border
			SDL.SetRenderDrawColor(renderer, 255, 255, 255, 255)
			SDL.RenderDrawRect(renderer, &box_rect)
		}

		// ImGui Control Panel
		ui.Render_control_panel(&state, WIDTH, HEIGHT)

		// Render ImGui
		imgui.Render()
		imgui_sdlrenderer2.RenderDrawData(imgui.GetDrawData(), renderer)

		SDL.RenderPresent(renderer)
		SDL.Delay(16)
	}
}
