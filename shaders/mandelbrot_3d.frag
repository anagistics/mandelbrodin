#version 330 core

// Inputs from vertex shader
in vec3 v_position;
in vec3 v_normal;
in vec3 v_color;

// Uniforms
uniform vec3 u_light_dir;      // Directional light direction (normalized)
uniform vec3 u_light_color;    // Light color
uniform float u_ambient;       // Ambient light amount
uniform vec3 u_camera_pos;     // Camera position (for specular)

// Output
out vec4 FragColor;

void main() {
    // Normalize normal (in case of interpolation issues)
    vec3 normal = normalize(v_normal);

    // Light direction (pointing from surface to light)
    vec3 light_dir = normalize(-u_light_dir);

    // View direction (pointing from surface to camera)
    vec3 view_dir = normalize(u_camera_pos - v_position);

    // === Ambient Component ===
    vec3 ambient = u_ambient * v_color;

    // === Diffuse Component (Lambertian) ===
    float diff = max(dot(normal, light_dir), 0.0);
    vec3 diffuse = diff * u_light_color * v_color;

    // === Specular Component (Blinn-Phong) ===
    vec3 halfway = normalize(light_dir + view_dir);
    float spec = pow(max(dot(normal, halfway), 0.0), 32.0);  // 32 = shininess
    vec3 specular = spec * u_light_color * 0.3;  // 0.3 = specular strength

    // === Combine All Components ===
    vec3 result = ambient + diffuse + specular;

    FragColor = vec4(result, 1.0);
}
