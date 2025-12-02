#version 330 core

in vec2 TexCoord;
out vec4 FragColor;

uniform vec2 u_resolution;
uniform float u_zoom;
uniform vec2 u_center;
uniform int u_max_iterations;
uniform bool u_use_smooth_coloring;

// Palette uniforms
const int MAX_STOPS = 10;
uniform int u_num_stops;
uniform float u_stop_positions[MAX_STOPS];
uniform vec3 u_stop_colors[MAX_STOPS];

// Linear interpolation
float lerp(float a, float b, float t) {
    return a + (b - a) * t;
}

// Interpolate color from gradient
vec3 interpolate_color(float t) {
    if (u_num_stops == 0) {
        return vec3(0.0);
    }

    if (t <= u_stop_positions[0]) {
        return u_stop_colors[0];
    }

    if (t >= u_stop_positions[u_num_stops - 1]) {
        return u_stop_colors[u_num_stops - 1];
    }

    // Find the two stops to interpolate between
    for (int i = 0; i < u_num_stops - 1; i++) {
        float pos1 = u_stop_positions[i];
        float pos2 = u_stop_positions[i + 1];

        if (t >= pos1 && t <= pos2) {
            // Calculate interpolation factor
            float local_t = (t - pos1) / (pos2 - pos1);

            vec3 color1 = u_stop_colors[i];
            vec3 color2 = u_stop_colors[i + 1];

            return vec3(
                lerp(color1.r, color2.r, local_t),
                lerp(color1.g, color2.g, local_t),
                lerp(color1.b, color2.b, local_t)
            );
        }
    }

    return vec3(0.0);
}

// Mandelbrot iteration - returns iteration count and final magnitude squared
void iterate(vec2 c, int max_iter, out int iteration, out float magnitude_sq) {
    vec2 z = vec2(0.0);
    iteration = 0;
    magnitude_sq = 0.0;

    for (int i = 0; i < max_iter; i++) {
        magnitude_sq = dot(z, z);
        if (magnitude_sq > 4.0) {
            break;
        }

        // z = z^2 + c
        float x_temp = z.x * z.x - z.y * z.y + c.x;
        z.y = 2.0 * z.x * z.y + c.y;
        z.x = x_temp;

        iteration++;
    }

    // Update magnitude_sq one last time
    magnitude_sq = dot(z, z);
}

// Calculate smooth iteration count
float calculate_smooth_iteration(int iter, float magnitude_sq) {
    // Avoid log of values <= 0
    if (magnitude_sq <= 1.0) {
        return float(iter);
    }

    // Smooth iteration formula: n + 1 - log(log(|z|)) / log(2)
    float magnitude = sqrt(magnitude_sq);
    float smooth_val = float(iter) + 1.0 - log(log(magnitude)) / log(2.0);

    return max(0.0, smooth_val);
}

void main()
{
    // Convert screen coordinates to world coordinates
    float scale = 3.5 / u_zoom;
    float offset_x = u_center.x - (1.75 / u_zoom);
    float offset_y = u_center.y - (1.0 / u_zoom);

    float x0 = TexCoord.x * scale + offset_x;
    // Flip Y coordinate to match CPU version (Y=0 at top)
    float y0 = (1.0 - TexCoord.y) * (2.0 / u_zoom) + offset_y;

    vec2 c = vec2(x0, y0);

    // Compute iterations
    int iter;
    float magnitude_sq;
    iterate(c, u_max_iterations, iter, magnitude_sq);

    // Compute color
    if (iter == u_max_iterations) {
        FragColor = vec4(0.0, 0.0, 0.0, 1.0);
    } else {
        float t;
        if (u_use_smooth_coloring) {
            float smooth_iter = calculate_smooth_iteration(iter, magnitude_sq);
            t = smooth_iter / float(u_max_iterations);
        } else {
            t = float(iter) / float(u_max_iterations);
        }
        vec3 color = interpolate_color(t);
        FragColor = vec4(color, 1.0);
    }
}
