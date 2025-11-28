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
	u_max_iterations:       i32,
	u_num_stops:            i32,
	u_stop_positions:       i32,
	u_stop_colors:          i32,
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
	r.u_max_iterations = gl.GetUniformLocation(r.mandelbrot_program, "u_max_iterations")
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
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, i32(width), i32(height), 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)

	return true
}

// Render using GPU shader
Render_GPU :: proc(r: ^Renderer, state: ^app.App_State, width: int, height: int) {
	gl.UseProgram(r.mandelbrot_program)

	// Set uniforms
	gl.Uniform2f(r.u_resolution, f32(width), f32(height))
	gl.Uniform1f(r.u_zoom, f32(state.zoom))
	gl.Uniform2f(r.u_center, f32(state.center_x), f32(state.center_y))
	gl.Uniform1i(r.u_max_iterations, i32(state.max_iterations))

	// Set palette uniforms
	palette := visual.get_palette(state.palette)
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
	// Upload texture
	gl.BindTexture(gl.TEXTURE_2D, r.cpu_texture)
	gl.TexSubImage2D(gl.TEXTURE_2D, 0, 0, 0, i32(width), i32(height), gl.RGBA, gl.UNSIGNED_BYTE, raw_data(pixels))

	// Render texture
	gl.UseProgram(r.texture_program)
	gl.BindTexture(gl.TEXTURE_2D, r.cpu_texture)
	gl.BindVertexArray(r.vao)
	gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, nil)
	gl.BindVertexArray(0)
}

// Cleanup
Destroy :: proc(r: ^Renderer) {
	gl.DeleteVertexArrays(1, &r.vao)
	gl.DeleteBuffers(1, &r.vbo)
	gl.DeleteBuffers(1, &r.ebo)
	gl.DeleteProgram(r.mandelbrot_program)
	gl.DeleteProgram(r.texture_program)
	gl.DeleteTextures(1, &r.cpu_texture)
}
