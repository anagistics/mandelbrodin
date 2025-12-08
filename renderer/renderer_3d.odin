package renderer

import "core:fmt"
import "core:math"
import "core:math/linalg"
import gl "vendor:OpenGL"
import app "../app"

// Instance data for GPU (per-column data)
Column_Instance :: struct {
	position: [2]f32, // X, Y world position
	height:   f32, // Column height (Z scale)
	color:    [3]f32, // RGB color from palette
}

// 3D renderer state
Renderer_3D :: struct {
	// Geometry
	cube_vao:     u32, // Vertex Array Object for cube
	cube_vbo:     u32, // Vertex Buffer Object (vertices + normals)
	instance_vbo: u32, // Instance data buffer

	// Shaders
	shader_program: u32,

	// Uniforms
	u_view:         i32,
	u_projection:   i32,
	u_height_scale: i32,
	u_column_width: i32,
	u_light_dir:    i32,
	u_light_color:  i32,
	u_ambient:      i32,
	u_camera_pos:   i32,

	// Rendering state
	instance_count: int,
	camera:         Camera_3D,

	// Configuration
	height_scale:   f32, // Multiplier for column heights
	column_width:   f32, // Base width of columns
	light_dir:      [3]f32, // Directional light direction
	light_color:    [3]f32, // Light color
	light_ambient:  f32, // Ambient light amount
}

// Cube vertex data (position + normal)
// Format: [x, y, z, nx, ny, nz]
CUBE_VERTICES := [?]f32 {
	// Front face (normal: 0, 0, 1)
	-0.5,
	-0.5,
	0.5,
	0.0,
	0.0,
	1.0,
	0.5,
	-0.5,
	0.5,
	0.0,
	0.0,
	1.0,
	0.5,
	0.5,
	0.5,
	0.0,
	0.0,
	1.0,
	0.5,
	0.5,
	0.5,
	0.0,
	0.0,
	1.0,
	-0.5,
	0.5,
	0.5,
	0.0,
	0.0,
	1.0,
	-0.5,
	-0.5,
	0.5,
	0.0,
	0.0,
	1.0,
	// Back face (normal: 0, 0, -1)
	-0.5,
	-0.5,
	-0.5,
	0.0,
	0.0,
	-1.0,
	-0.5,
	0.5,
	-0.5,
	0.0,
	0.0,
	-1.0,
	0.5,
	0.5,
	-0.5,
	0.0,
	0.0,
	-1.0,
	0.5,
	0.5,
	-0.5,
	0.0,
	0.0,
	-1.0,
	0.5,
	-0.5,
	-0.5,
	0.0,
	0.0,
	-1.0,
	-0.5,
	-0.5,
	-0.5,
	0.0,
	0.0,
	-1.0,
	// Top face (normal: 0, 1, 0)
	-0.5,
	0.5,
	-0.5,
	0.0,
	1.0,
	0.0,
	-0.5,
	0.5,
	0.5,
	0.0,
	1.0,
	0.0,
	0.5,
	0.5,
	0.5,
	0.0,
	1.0,
	0.0,
	0.5,
	0.5,
	0.5,
	0.0,
	1.0,
	0.0,
	0.5,
	0.5,
	-0.5,
	0.0,
	1.0,
	0.0,
	-0.5,
	0.5,
	-0.5,
	0.0,
	1.0,
	0.0,
	// Bottom face (normal: 0, -1, 0)
	-0.5,
	-0.5,
	-0.5,
	0.0,
	-1.0,
	0.0,
	0.5,
	-0.5,
	-0.5,
	0.0,
	-1.0,
	0.0,
	0.5,
	-0.5,
	0.5,
	0.0,
	-1.0,
	0.0,
	0.5,
	-0.5,
	0.5,
	0.0,
	-1.0,
	0.0,
	-0.5,
	-0.5,
	0.5,
	0.0,
	-1.0,
	0.0,
	-0.5,
	-0.5,
	-0.5,
	0.0,
	-1.0,
	0.0,
	// Right face (normal: 1, 0, 0)
	0.5,
	-0.5,
	-0.5,
	1.0,
	0.0,
	0.0,
	0.5,
	0.5,
	-0.5,
	1.0,
	0.0,
	0.0,
	0.5,
	0.5,
	0.5,
	1.0,
	0.0,
	0.0,
	0.5,
	0.5,
	0.5,
	1.0,
	0.0,
	0.0,
	0.5,
	-0.5,
	0.5,
	1.0,
	0.0,
	0.0,
	0.5,
	-0.5,
	-0.5,
	1.0,
	0.0,
	0.0,
	// Left face (normal: -1, 0, 0)
	-0.5,
	-0.5,
	-0.5,
	-1.0,
	0.0,
	0.0,
	-0.5,
	-0.5,
	0.5,
	-1.0,
	0.0,
	0.0,
	-0.5,
	0.5,
	0.5,
	-1.0,
	0.0,
	0.0,
	-0.5,
	0.5,
	0.5,
	-1.0,
	0.0,
	0.0,
	-0.5,
	0.5,
	-0.5,
	-1.0,
	0.0,
	0.0,
	-0.5,
	-0.5,
	-0.5,
	-1.0,
	0.0,
	0.0,
}

// Initialize 3D renderer
Init_3D :: proc(r3d: ^Renderer_3D, aspect: f32, width: int, height: int) -> bool {
	fmt.println("Initializing 3D renderer...")

	// Initialize camera with scene dimensions
	Init_Camera_3D(&r3d.camera, aspect, f32(width), f32(height))

	// Set default configuration
	r3d.height_scale = 2.0
	r3d.column_width = 0.9 // 0.9 = adjacent columns with small gap, 1.0 = no gap
	r3d.light_dir = linalg.normalize([3]f32{-0.5, -1.0, -0.3})
	r3d.light_color = {1.0, 1.0, 1.0}
	r3d.light_ambient = 0.2

	// Create cube geometry VAO/VBO
	gl.GenVertexArrays(1, &r3d.cube_vao)
	gl.GenBuffers(1, &r3d.cube_vbo)

	gl.BindVertexArray(r3d.cube_vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, r3d.cube_vbo)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		size_of(CUBE_VERTICES),
		raw_data(&CUBE_VERTICES),
		gl.STATIC_DRAW,
	)

	// Vertex attributes: position (location 0) and normal (location 1)
	stride := 6 * size_of(f32)

	// Position attribute
	gl.EnableVertexAttribArray(0)
	gl.VertexAttribPointer(0, 3, gl.FLOAT, false, i32(stride), 0)

	// Normal attribute
	gl.EnableVertexAttribArray(1)
	gl.VertexAttribPointer(1, 3, gl.FLOAT, false, i32(stride), 3 * size_of(f32))

	// Create instance buffer (will be filled later)
	gl.GenBuffers(1, &r3d.instance_vbo)

	// Load shaders
	if !Load_3D_Shaders(r3d) {
		fmt.eprintln("Failed to load 3D shaders")
		return false
	}

	// Get uniform locations
	r3d.u_view = gl.GetUniformLocation(r3d.shader_program, "u_view")
	r3d.u_projection = gl.GetUniformLocation(r3d.shader_program, "u_projection")
	r3d.u_height_scale = gl.GetUniformLocation(r3d.shader_program, "u_height_scale")
	r3d.u_column_width = gl.GetUniformLocation(r3d.shader_program, "u_column_width")
	r3d.u_light_dir = gl.GetUniformLocation(r3d.shader_program, "u_light_dir")
	r3d.u_light_color = gl.GetUniformLocation(r3d.shader_program, "u_light_color")
	r3d.u_ambient = gl.GetUniformLocation(r3d.shader_program, "u_ambient")
	r3d.u_camera_pos = gl.GetUniformLocation(r3d.shader_program, "u_camera_pos")

	fmt.println("✓ 3D renderer initialized successfully")
	return true
}

// Clean up 3D renderer resources
Destroy_3D :: proc(r3d: ^Renderer_3D) {
	gl.DeleteVertexArrays(1, &r3d.cube_vao)
	gl.DeleteBuffers(1, &r3d.cube_vbo)
	gl.DeleteBuffers(1, &r3d.instance_vbo)
	gl.DeleteProgram(r3d.shader_program)
}

// Update instance buffer with prepared instance data
Upload_Instance_Buffer_3D :: proc(r3d: ^Renderer_3D, instances: []Column_Instance) {
	r3d.instance_count = len(instances)

	// Upload to GPU
	gl.BindBuffer(gl.ARRAY_BUFFER, r3d.instance_vbo)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		size_of(Column_Instance) * r3d.instance_count,
		raw_data(instances),
		gl.DYNAMIC_DRAW,
	)

	// Set up instance attributes (location 2, 3, 4)
	gl.BindVertexArray(r3d.cube_vao)

	// Position (vec2)
	gl.EnableVertexAttribArray(2)
	gl.VertexAttribPointer(
		2,
		2,
		gl.FLOAT,
		false,
		i32(size_of(Column_Instance)),
		offset_of(Column_Instance, position),
	)
	gl.VertexAttribDivisor(2, 1) // Advance per instance

	// Height (float)
	gl.EnableVertexAttribArray(3)
	gl.VertexAttribPointer(
		3,
		1,
		gl.FLOAT,
		false,
		i32(size_of(Column_Instance)),
		offset_of(Column_Instance, height),
	)
	gl.VertexAttribDivisor(3, 1)

	// Color (vec3)
	gl.EnableVertexAttribArray(4)
	gl.VertexAttribPointer(
		4,
		3,
		gl.FLOAT,
		false,
		i32(size_of(Column_Instance)),
		offset_of(Column_Instance, color),
	)
	gl.VertexAttribDivisor(4, 1)
}

// Helper: Extract iteration count from colored pixel
// This is a rough approximation - ideally we'd store iteration data separately
get_iteration_from_pixel :: proc(pixel: u32) -> u64 {
	// For now, use brightness as proxy for iteration
	// TODO: Store actual iteration data separately
	r := f32((pixel >> 16) & 0xFF)
	g := f32((pixel >> 8) & 0xFF)
	b := f32(pixel & 0xFF)

	brightness := (r + g + b) / (3.0 * 255.0)

	// Map brightness to iteration (very rough approximation)
	return u64(brightness * 256.0)
}

// Render 3D view (draws the prepared instances)
Draw_3D_Instances :: proc(r3d: ^Renderer_3D) {

	// Use 3D shader
	gl.UseProgram(r3d.shader_program)

	// Set uniforms
	gl.UniformMatrix4fv(r3d.u_view, 1, false, &r3d.camera.view_matrix[0, 0])
	gl.UniformMatrix4fv(r3d.u_projection, 1, false, &r3d.camera.proj_matrix[0, 0])
	gl.Uniform1f(r3d.u_height_scale, r3d.height_scale)
	gl.Uniform1f(r3d.u_column_width, r3d.column_width)
	gl.Uniform3f(r3d.u_light_dir, r3d.light_dir.x, r3d.light_dir.y, r3d.light_dir.z)
	gl.Uniform3f(
		r3d.u_light_color,
		r3d.light_color.x,
		r3d.light_color.y,
		r3d.light_color.z,
	)
	gl.Uniform1f(r3d.u_ambient, r3d.light_ambient)
	gl.Uniform3f(
		r3d.u_camera_pos,
		r3d.camera.position.x,
		r3d.camera.position.y,
		r3d.camera.position.z,
	)

	// Enable depth testing
	gl.Enable(gl.DEPTH_TEST)
	gl.DepthFunc(gl.LESS)

	// Enable back-face culling
	gl.Enable(gl.CULL_FACE)
	gl.CullFace(gl.BACK)

	// Draw instanced cubes
	gl.BindVertexArray(r3d.cube_vao)
	gl.DrawArraysInstanced(gl.TRIANGLES, 0, 36, i32(r3d.instance_count)) // 36 vertices = 6 faces × 2 triangles × 3 vertices

	// Disable depth test for 2D UI
	gl.Disable(gl.DEPTH_TEST)
	gl.Disable(gl.CULL_FACE)
}

// Load 3D shaders
Load_3D_Shaders :: proc(r3d: ^Renderer_3D) -> bool {
	// Note: Shader files will be created next
	// For now, return false to signal they need to be created
	fmt.println("Loading 3D shaders...")

	vert_source := #load("../shaders/mandelbrot_3d.vert", cstring)
	frag_source := #load("../shaders/mandelbrot_3d.frag", cstring)

	// Compile vertex shader
	vert_shader := gl.CreateShader(gl.VERTEX_SHADER)
	gl.ShaderSource(vert_shader, 1, &vert_source, nil)
	gl.CompileShader(vert_shader)

	// Check vertex shader compilation
	success: i32
	gl.GetShaderiv(vert_shader, gl.COMPILE_STATUS, &success)
	if success == 0 {
		info_log: [512]u8
		gl.GetShaderInfoLog(vert_shader, 512, nil, raw_data(info_log[:]))
		fmt.eprintln("Vertex shader compilation failed:", cstring(raw_data(info_log[:])))
		return false
	}

	// Compile fragment shader
	frag_shader := gl.CreateShader(gl.FRAGMENT_SHADER)
	gl.ShaderSource(frag_shader, 1, &frag_source, nil)
	gl.CompileShader(frag_shader)

	// Check fragment shader compilation
	gl.GetShaderiv(frag_shader, gl.COMPILE_STATUS, &success)
	if success == 0 {
		info_log: [512]u8
		gl.GetShaderInfoLog(frag_shader, 512, nil, raw_data(info_log[:]))
		fmt.eprintln("Fragment shader compilation failed:", cstring(raw_data(info_log[:])))
		return false
	}

	// Link shader program
	r3d.shader_program = gl.CreateProgram()
	gl.AttachShader(r3d.shader_program, vert_shader)
	gl.AttachShader(r3d.shader_program, frag_shader)
	gl.LinkProgram(r3d.shader_program)

	// Check linking
	gl.GetProgramiv(r3d.shader_program, gl.LINK_STATUS, &success)
	if success == 0 {
		info_log: [512]u8
		gl.GetProgramInfoLog(r3d.shader_program, 512, nil, raw_data(info_log[:]))
		fmt.eprintln("Shader linking failed:", cstring(raw_data(info_log[:])))
		return false
	}

	// Clean up shaders (no longer needed after linking)
	gl.DeleteShader(vert_shader)
	gl.DeleteShader(frag_shader)

	fmt.println("✓ 3D shaders loaded successfully")
	return true
}
