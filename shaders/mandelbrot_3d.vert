#version 330 core

// Per-vertex attributes (cube geometry)
layout(location = 0) in vec3 a_position;
layout(location = 1) in vec3 a_normal;

// Per-instance attributes
layout(location = 2) in vec2 a_instance_pos;    // XY position in world space
layout(location = 3) in float a_instance_height; // Column height (0-1)
layout(location = 4) in vec3 a_instance_color;  // RGB color

// Uniforms
uniform mat4 u_view;
uniform mat4 u_projection;
uniform float u_height_scale;  // Multiplier for height
uniform float u_column_width;  // Base width of columns

// Outputs to fragment shader
out vec3 v_position;    // World position
out vec3 v_normal;      // World normal
out vec3 v_color;       // Vertex color

void main() {
    // Invert height for plateau effect: interior (high brightness) stays at top,
    // exterior (low brightness) extends downward
    float inverted_height = 1.0 - a_instance_height;

    // Scale cube geometry
    vec3 scaled_pos = a_position;
    scaled_pos.xy *= u_column_width;  // Scale XY to column width
    scaled_pos.z *= inverted_height * u_height_scale;  // Scale Z to inverted height

    // Translate to instance position
    // Columns grow downward from top (Z=0), so offset by -half height
    vec3 world_pos = vec3(
        a_instance_pos.x,
        a_instance_pos.y,
        -scaled_pos.z * 0.5  // Negative offset: start at top, grow downward
    );
    world_pos += scaled_pos;

    // Transform to clip space
    gl_Position = u_projection * u_view * vec4(world_pos, 1.0);

    // Pass data to fragment shader
    v_position = world_pos;
    v_normal = a_normal;  // TODO: Transform normal by model matrix if needed
    v_color = a_instance_color;
}
