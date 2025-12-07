#version 430 core

// Workgroup size: 16×16 threads (256 threads per workgroup)
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// Output image (write-only, RGBA8 format)
layout(rgba8, binding = 0) uniform writeonly image2D u_output_image;

// View parameters (using double precision for better accuracy)
uniform dvec2 u_center;        // Center position
uniform double u_zoom;         // Zoom level
uniform double u_rotation;     // Rotation angle in radians
uniform int u_max_iterations;  // Maximum iterations
uniform bool u_use_smooth_coloring;  // Smooth coloring flag
uniform ivec2 u_dimensions;    // Image dimensions (width, height)

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

// Screen to world coordinate conversion
dvec2 screen_to_world(ivec2 pixel) {
    // Normalize to [0, 1] range
    dvec2 normalized = dvec2(pixel) / dvec2(u_dimensions);

    // Center to [-0.5, 0.5]
    // Flip Y to match CPU coordinate system (top = -0.5, bottom = +0.5)
    double norm_x = normalized.x - 0.5;
    double norm_y = (1.0 - normalized.y) - 0.5;

    // Apply rotation (cast to float for trig functions, GLSL has no double precision trig)
    double cos_r = double(cos(float(u_rotation)));
    double sin_r = double(sin(float(u_rotation)));
    double rotated_x = norm_x * cos_r - norm_y * sin_r;
    double rotated_y = norm_x * sin_r + norm_y * cos_r;

    // Scale to world coordinates
    dvec2 scale = dvec2(3.5, 2.0) / u_zoom;
    dvec2 world = dvec2(rotated_x, rotated_y) * scale + u_center;

    return world;
}

// Mandelbrot iteration - returns iteration count and final magnitude squared
void iterate(dvec2 c, int max_iter, out int iteration, out double magnitude_sq) {
    dvec2 z = dvec2(0.0);
    iteration = 0;
    magnitude_sq = 0.0;

    for (int i = 0; i < max_iter; i++) {
        // z = z^2 + c
        double x_temp = z.x * z.x - z.y * z.y + c.x;
        z.y = 2.0 * z.x * z.y + c.y;
        z.x = x_temp;

        iteration++;

        // Calculate magnitude squared
        magnitude_sq = dot(z, z);
        if (magnitude_sq > 4.0) {
            break;
        }
    }
}

// Calculate smooth iteration count
float calculate_smooth_iteration(int iter, double magnitude_sq) {
    // Avoid log of values <= 0
    if (magnitude_sq <= 1.0) {
        return float(iter);
    }

    // Smooth iteration formula: n + 1 - log(log(|z|)) / log(2)
    // Note: GLSL has no double precision log, so cast to float
    float magnitude = float(sqrt(magnitude_sq));
    float smooth_val = float(iter) + 1.0 - log(log(magnitude)) / log(2.0);

    return max(0.0, smooth_val);
}

void main() {
    // Get pixel coordinates from global invocation ID
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);

    // Bounds check - don't process pixels outside image dimensions
    if (pixel.x >= u_dimensions.x || pixel.y >= u_dimensions.y) {
        return;
    }

    // Convert pixel to complex plane coordinates
    dvec2 c = screen_to_world(pixel);

    // Compute Mandelbrot iterations
    int iter;
    double magnitude_sq;
    iterate(c, u_max_iterations, iter, magnitude_sq);

    // Compute color
    vec4 color;
    if (iter == u_max_iterations) {
        // Point is in the set - black
        color = vec4(0.0, 0.0, 0.0, 1.0);
    } else {
        // Point escaped - apply coloring
        float t;
        if (u_use_smooth_coloring) {
            float smooth_iter = calculate_smooth_iteration(iter, magnitude_sq);
            t = smooth_iter / float(u_max_iterations);
        } else {
            t = float(iter) / float(u_max_iterations);
        }
        vec3 rgb = interpolate_color(t);
        color = vec4(rgb, 1.0);
    }

    // Write color to output image
    imageStore(u_output_image, pixel, color);
}
