package renderer

import "core:fmt"
import "core:os"
import "core:strings"
import gl "vendor:OpenGL"
import app "../app"
import visual "../visual"

Renderer :: struct {
	vao:                    u32,
	vbo:                    u32,
	ebo:                    u32,
	mandelbrot_program:     u32,
	texture_program:        u32,
	cpu_texture:            u32,
	// Uniform locations for mandelbrot shader
	u_resolution:           i32,
	u_zoom:                 i32,
	u_center:               i32,
	u_rotation:             i32,
	u_max_iterations:       i32,
	u_use_smooth_coloring:  i32,
	u_num_stops:            i32,
	u_stop_positions:       i32,
	u_stop_colors:          i32,
	// Compute shader support
	compute_program:        u32,
	compute_available:      bool,
	// Uniform locations for compute shader
	c_center:               i32,
	c_zoom:                 i32,
	c_rotation:             i32,
	c_max_iterations:       i32,
	c_use_smooth_coloring:  i32,
	c_dimensions:           i32,
	c_num_stops:            i32,
	c_stop_positions:       i32,
	c_stop_colors:          i32,
	// 3D rendering
	renderer_3d:            Renderer_3D,
	renderer_3d_available:  bool,
}

// Load shader from file
load_shader :: proc(path: string, shader_type: u32) -> (u32, bool) {
	source_bytes, ok := os.read_entire_file(path)
	if !ok {
		fmt.eprintln("Failed to read shader file:", path)
		return 0, false
	}
	defer delete(source_bytes)

	source := string(source_bytes)

	shader := gl.CreateShader(shader_type)
	source_cstr := strings.clone_to_cstring(source)
	defer delete(source_cstr)

	gl.ShaderSource(shader, 1, &source_cstr, nil)
	gl.CompileShader(shader)

	// Check compilation
	success: i32
	gl.GetShaderiv(shader, gl.COMPILE_STATUS, &success)
	if success == 0 {
		info_log: [512]u8
		gl.GetShaderInfoLog(shader, 512, nil, raw_data(info_log[:]))
		fmt.eprintln("Shader compilation failed:", path)
		fmt.eprintln(string(info_log[:]))
		return 0, false
	}

	return shader, true
}

// Create shader program from vertex and fragment shaders
create_program :: proc(vert_path: string, frag_path: string) -> (u32, bool) {
	vert_shader, vert_ok := load_shader(vert_path, gl.VERTEX_SHADER)
	if !vert_ok {
		return 0, false
	}
	defer gl.DeleteShader(vert_shader)

	frag_shader, frag_ok := load_shader(frag_path, gl.FRAGMENT_SHADER)
	if !frag_ok {
		return 0, false
	}
	defer gl.DeleteShader(frag_shader)

	program := gl.CreateProgram()
	gl.AttachShader(program, vert_shader)
	gl.AttachShader(program, frag_shader)
	gl.LinkProgram(program)

	// Check linking
	success: i32
	gl.GetProgramiv(program, gl.LINK_STATUS, &success)
	if success == 0 {
		info_log: [512]u8
		gl.GetProgramInfoLog(program, 512, nil, raw_data(info_log[:]))
		fmt.eprintln("Program linking failed")
		fmt.eprintln(string(info_log[:]))
		return 0, false
	}

	return program, true
}

// Create compute shader program
create_compute_program :: proc(comp_path: string) -> (u32, bool) {
	comp_shader, comp_ok := load_shader(comp_path, gl.COMPUTE_SHADER)
	if !comp_ok {
		return 0, false
	}
	defer gl.DeleteShader(comp_shader)

	program := gl.CreateProgram()
	gl.AttachShader(program, comp_shader)
	gl.LinkProgram(program)

	// Check linking
	success: i32
	gl.GetProgramiv(program, gl.LINK_STATUS, &success)
	if success == 0 {
		info_log: [512]u8
		gl.GetProgramInfoLog(program, 512, nil, raw_data(info_log[:]))
		fmt.eprintln("Compute program linking failed")
		fmt.eprintln(string(info_log[:]))
		return 0, false
	}

	return program, true
}

// Initialize compute shader support
Init_Compute_Shader :: proc(r: ^Renderer) -> bool {
	// Check if compute shaders are supported (OpenGL 4.3+)
	major, minor: i32
	gl.GetIntegerv(gl.MAJOR_VERSION, &major)
	gl.GetIntegerv(gl.MINOR_VERSION, &minor)

	version := major * 10 + minor
	if version < 43 {
		fmt.printf("OpenGL %d.%d < 4.3, compute shaders not available\n", major, minor)
		r.compute_available = false
		return false
	}

	// Load compute shader
	compute_program, compute_ok := create_compute_program("shaders/mandelbrot_compute.glsl")
	if !compute_ok {
		fmt.eprintln("Failed to load compute shader, exports will use CPU")
		r.compute_available = false
		return false
	}
	r.compute_program = compute_program

	// Get uniform locations for compute shader
	gl.UseProgram(r.compute_program)
	r.c_center = gl.GetUniformLocation(r.compute_program, "u_center")
	r.c_zoom = gl.GetUniformLocation(r.compute_program, "u_zoom")
	r.c_rotation = gl.GetUniformLocation(r.compute_program, "u_rotation")
	r.c_max_iterations = gl.GetUniformLocation(r.compute_program, "u_max_iterations")
	r.c_use_smooth_coloring = gl.GetUniformLocation(r.compute_program, "u_use_smooth_coloring")
	r.c_dimensions = gl.GetUniformLocation(r.compute_program, "u_dimensions")
	r.c_num_stops = gl.GetUniformLocation(r.compute_program, "u_num_stops")
	r.c_stop_positions = gl.GetUniformLocation(r.compute_program, "u_stop_positions")
	r.c_stop_colors = gl.GetUniformLocation(r.compute_program, "u_stop_colors")

	r.compute_available = true
	fmt.println("✓ Compute shader initialized successfully")
	return true
}

// Initialize renderer
Init :: proc(r: ^Renderer, width: int, height: int) -> bool {
	// Fullscreen quad vertices (position + texcoord)
	vertices := []f32{
		// positions   // texcoords
		-1.0,  1.0,    0.0, 1.0,
		-1.0, -1.0,    0.0, 0.0,
		 1.0, -1.0,    1.0, 0.0,
		 1.0,  1.0,    1.0, 1.0,
	}

	indices := []u32{
		0, 1, 2,
		0, 2, 3,
	}

	// Create VAO, VBO, EBO
	gl.GenVertexArrays(1, &r.vao)
	gl.GenBuffers(1, &r.vbo)
	gl.GenBuffers(1, &r.ebo)

	gl.BindVertexArray(r.vao)

	gl.BindBuffer(gl.ARRAY_BUFFER, r.vbo)
	gl.BufferData(gl.ARRAY_BUFFER, len(vertices) * size_of(f32), raw_data(vertices), gl.STATIC_DRAW)

	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, r.ebo)
	gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(u32), raw_data(indices), gl.STATIC_DRAW)

	// Position attribute
	gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 4 * size_of(f32), 0)
	gl.EnableVertexAttribArray(0)

	// Texcoord attribute
	gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, 4 * size_of(f32), 2 * size_of(f32))
	gl.EnableVertexAttribArray(1)

	gl.BindVertexArray(0)

	// Load shaders
	mandelbrot_program, mb_ok := create_program("shaders/mandelbrot.vert", "shaders/mandelbrot.frag")
	if !mb_ok {
		return false
	}
	r.mandelbrot_program = mandelbrot_program

	texture_program, tex_ok := create_program("shaders/texture.vert", "shaders/texture.frag")
	if !tex_ok {
		return false
	}
	r.texture_program = texture_program

	// Get uniform locations for mandelbrot shader
	gl.UseProgram(r.mandelbrot_program)
	r.u_resolution = gl.GetUniformLocation(r.mandelbrot_program, "u_resolution")
	r.u_zoom = gl.GetUniformLocation(r.mandelbrot_program, "u_zoom")
	r.u_center = gl.GetUniformLocation(r.mandelbrot_program, "u_center")
	r.u_rotation = gl.GetUniformLocation(r.mandelbrot_program, "u_rotation")
	r.u_max_iterations = gl.GetUniformLocation(r.mandelbrot_program, "u_max_iterations")
	r.u_use_smooth_coloring = gl.GetUniformLocation(r.mandelbrot_program, "u_use_smooth_coloring")
	r.u_num_stops = gl.GetUniformLocation(r.mandelbrot_program, "u_num_stops")
	r.u_stop_positions = gl.GetUniformLocation(r.mandelbrot_program, "u_stop_positions")
	r.u_stop_colors = gl.GetUniformLocation(r.mandelbrot_program, "u_stop_colors")

	// Create texture for CPU rendering
	gl.GenTextures(1, &r.cpu_texture)
	gl.BindTexture(gl.TEXTURE_2D, r.cpu_texture)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	// Use BGRA to match CPU color packing (0xAARRGGBB in little-endian = [BB,GG,RR,AA] bytes)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, i32(width), i32(height), 0, gl.BGRA, gl.UNSIGNED_BYTE, nil)

	// Initialize 3D renderer
	aspect := f32(width) / f32(height)
	if Init_3D(&r.renderer_3d, aspect, width, height) {
		r.renderer_3d_available = true
		fmt.println("✓ 3D renderer available")
	} else {
		r.renderer_3d_available = false
		fmt.println("⚠ 3D renderer not available, 3D mode disabled")
	}

	return true
}

// Render using GPU shader
Render_GPU :: proc(r: ^Renderer, state: ^app.App_State, width: int, height: int) {
	gl.UseProgram(r.mandelbrot_program)

	// Set uniforms
	gl.Uniform2f(r.u_resolution, f32(width), f32(height))
	gl.Uniform1f(r.u_zoom, f32(state.zoom))
	gl.Uniform2f(r.u_center, f32(state.center_x), f32(state.center_y))
	gl.Uniform1f(r.u_rotation, f32(state.rotation))
	gl.Uniform1i(r.u_max_iterations, i32(state.max_iterations))
	gl.Uniform1i(r.u_use_smooth_coloring, i32(state.use_smooth_coloring ? 1 : 0))

	// Set palette uniforms
	palette := state.current_palette
	num_stops := i32(len(palette.stops))
	gl.Uniform1i(r.u_num_stops, num_stops)

	// Upload color stops
	positions: [10]f32
	colors: [10][3]f32

	for stop, i in palette.stops {
		if i >= 10 {
			break
		}
		positions[i] = f32(stop.position)
		colors[i] = {f32(stop.r) / 255.0, f32(stop.g) / 255.0, f32(stop.b) / 255.0}
	}

	gl.Uniform1fv(r.u_stop_positions, num_stops, &positions[0])
	gl.Uniform3fv(r.u_stop_colors, num_stops, &colors[0][0])

	// Draw quad
	gl.BindVertexArray(r.vao)
	gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, nil)
	gl.BindVertexArray(0)
}

// Render using CPU-computed texture
Render_CPU :: proc(r: ^Renderer, pixels: []u32, width: int, height: int) {
	// Upload texture (use BGRA to match CPU color packing)
	gl.BindTexture(gl.TEXTURE_2D, r.cpu_texture)
	gl.TexSubImage2D(gl.TEXTURE_2D, 0, 0, 0, i32(width), i32(height), gl.BGRA, gl.UNSIGNED_BYTE, raw_data(pixels))

	// Render texture
	gl.UseProgram(r.texture_program)
	gl.BindTexture(gl.TEXTURE_2D, r.cpu_texture)
	gl.BindVertexArray(r.vao)
	gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, nil)
	gl.BindVertexArray(0)
}

// Render using 3D columns
Render_3D :: proc(r: ^Renderer, state: ^app.App_State, width: int, height: int) {
	if !r.renderer_3d_available {
		return
	}

	// Create instance data from pixels
	instances := make([dynamic]Column_Instance, 0, width * height)
	defer delete(instances)

	for y in 0 ..< height {
		for x in 0 ..< width {
			idx := y * width + x

			// Get pixel color
			pixel := state.pixels[idx]

			// Extract RGB components (pixel format is 0xAARRGGBB)
			r_u8 := u8((pixel >> 16) & 0xFF)
			g_u8 := u8((pixel >> 8) & 0xFF)
			b_u8 := u8(pixel & 0xFF)

			// Convert to float colors
			color := [3]f32{f32(r_u8) / 255.0, f32(g_u8) / 255.0, f32(b_u8) / 255.0}

			// Estimate height from brightness (temporary approximation)
			// TODO: Store actual iteration count for accurate height
			brightness := (color.r + color.g + color.b) / 3.0
			height_value := brightness

			// Skip very low columns (likely in the set, black pixels)
			if height_value < 0.01 {
				height_value = 0.01
			}

			// World position (centered at origin, not scaled by column_width)
			world_x := f32(x) - f32(width) * 0.5
			world_y := f32(y) - f32(height) * 0.5

			instance := Column_Instance {
				position = {world_x, world_y},
				height   = height_value,
				color    = color,
			}

			append(&instances, instance)
		}
	}

	// Upload instance data to GPU and render
	Upload_Instance_Buffer_3D(&r.renderer_3d, instances[:])
	Draw_3D_Instances(&r.renderer_3d)
}

// Cleanup
Destroy :: proc(r: ^Renderer) {
	gl.DeleteVertexArrays(1, &r.vao)
	gl.DeleteBuffers(1, &r.vbo)
	gl.DeleteBuffers(1, &r.ebo)
	gl.DeleteProgram(r.mandelbrot_program)
	gl.DeleteProgram(r.texture_program)
	gl.DeleteTextures(1, &r.cpu_texture)

	// Cleanup 3D renderer
	if r.renderer_3d_available {
		Destroy_3D(&r.renderer_3d)
	}
}
