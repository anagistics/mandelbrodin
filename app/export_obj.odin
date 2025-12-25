package app

import "core:fmt"
import "core:os"
import "core:math"
import "core:strings"

// OBJ Export Configuration
OBJ_Export_Options :: struct {
    width:              int,
    height:             int,
    column_width:       f32,      // Width of each column (0.0-1.0)
    height_scale:       f32,      // Multiplier for column heights
    min_height:         f32,      // Minimum height to export (skip shorter columns)
    include_normals:    bool,     // Include normal vectors for better lighting
    center_geometry:    bool,     // Center the geometry at origin
}

DEFAULT_OBJ_OPTIONS :: OBJ_Export_Options{
    column_width     = 0.9,
    height_scale     = 2.0,
    min_height       = 0.01,
    include_normals  = true,
    center_geometry  = true,
}

// Export 3D column geometry to OBJ file
export_obj :: proc(
    pixels: []u32,
    width, height: int,
    filepath: string,
    options: OBJ_Export_Options = DEFAULT_OBJ_OPTIONS,
) -> bool {
    // Cube geometry data
    cube_vertices := [8][3]f32{
        {-0.5, -0.5, 0.0},  // 0: Bottom-front-left
        { 0.5, -0.5, 0.0},  // 1: Bottom-front-right
        { 0.5,  0.5, 0.0},  // 2: Bottom-back-right
        {-0.5,  0.5, 0.0},  // 3: Bottom-back-left
        {-0.5, -0.5, 1.0},  // 4: Top-front-left
        { 0.5, -0.5, 1.0},  // 5: Top-front-right
        { 0.5,  0.5, 1.0},  // 6: Top-back-right
        {-0.5,  0.5, 1.0},  // 7: Top-back-left
    }

    cube_faces := [12][3]int{
        // Bottom face (z=0)
        {0, 2, 1}, {0, 3, 2},
        // Top face (z=1)
        {4, 5, 6}, {4, 6, 7},
        // Front face (y=-0.5)
        {0, 1, 5}, {0, 5, 4},
        // Back face (y=0.5)
        {2, 3, 7}, {2, 7, 6},
        // Left face (x=-0.5)
        {0, 4, 7}, {0, 7, 3},
        // Right face (x=0.5)
        {1, 2, 6}, {1, 6, 5},
    }

    face_normals := [6][3]f32{
        { 0,  0, -1},  // Bottom
        { 0,  0,  1},  // Top
        { 0, -1,  0},  // Front
        { 0,  1,  0},  // Back
        {-1,  0,  0},  // Left
        { 1,  0,  0},  // Right
    }

    fmt.printf("Exporting OBJ file: %s\n", filepath)
    fmt.printf("Resolution: %dx%d (%d columns)\n", width, height, width * height)
    fmt.printf("Options: column_width=%.2f, height_scale=%.2f, min_height=%.3f\n",
        options.column_width, options.height_scale, options.min_height)

    // Open file for writing
    file, err := os.open(filepath, os.O_CREATE | os.O_WRONLY | os.O_TRUNC, 0o644)
    if err != os.ERROR_NONE {
        fmt.printf("Error: Failed to create OBJ file: %v\n", err)
        return false
    }
    defer os.close(file)

    // Write OBJ header
    write_obj_header(file, width, height, options)

    // Calculate geometry offset for centering
    offset_x := options.center_geometry ? -f32(width) / 2.0 : 0.0
    offset_y := options.center_geometry ? -f32(height) / 2.0 : 0.0

    vertex_count := 0
    normal_count := 0
    column_count := 0
    skipped_count := 0

    // First pass: Write all vertices and normals
    fmt.println("Writing vertices...")

    for y in 0..<height {
        for x in 0..<width {
            idx := y * width + x
            pixel := pixels[idx]

            // Extract color and calculate height
            r := f32((pixel >> 16) & 0xFF) / 255.0
            g := f32((pixel >> 8) & 0xFF) / 255.0
            b := f32(pixel & 0xFF) / 255.0

            // Use brightness as height (can be customized to use iteration count)
            brightness := (r + g + b) / 3.0
            column_height := brightness * options.height_scale

            // Skip columns below minimum height
            if column_height < options.min_height {
                skipped_count += 1
                continue
            }

            // Write 8 vertices for this column
            pos_x := f32(x) + offset_x
            pos_y := f32(y) + offset_y

            for vertex in cube_vertices {
                vx := pos_x + vertex.x * options.column_width
                vy := pos_y + vertex.y * options.column_width
                vz := vertex.z * column_height

                fmt.fprintf(file, "v %.6f %.6f %.6f\n", vx, vy, vz)
                vertex_count += 1
            }

            column_count += 1
        }

        // Progress indicator
        if (y + 1) % 100 == 0 || y == height - 1 {
            fmt.printf("\rProgress: %d/%d rows (%.1f%%)", y + 1, height, f32(y + 1) / f32(height) * 100)
        }
    }
    fmt.println()

    // Write normals if requested
    if options.include_normals {
        fmt.println("Writing normals...")
        for i in 0..<column_count {
            for normal in face_normals {
                fmt.fprintf(file, "vn %.6f %.6f %.6f\n", normal.x, normal.y, normal.z)
                normal_count += 1
            }
        }
    }

    // Second pass: Write faces
    fmt.println("Writing faces...")

    column_idx := 0
    for y in 0..<height {
        for x in 0..<width {
            idx := y * width + x
            pixel := pixels[idx]

            // Recalculate height to determine if we should skip
            r := f32((pixel >> 16) & 0xFF) / 255.0
            g := f32((pixel >> 8) & 0xFF) / 255.0
            b := f32(pixel & 0xFF) / 255.0
            brightness := (r + g + b) / 3.0
            column_height := brightness * options.height_scale

            if column_height < options.min_height {
                continue
            }

            // Write 12 triangular faces for this column
            base_vertex := column_idx * 8 + 1  // OBJ indices start at 1

            for face_pair_idx in 0..<6 {
                face_idx1 := face_pair_idx * 2
                face_idx2 := face_pair_idx * 2 + 1

                if options.include_normals {
                    base_normal := column_idx * 6 + 1
                    normal_idx := base_normal + face_pair_idx

                    // First triangle
                    face1 := cube_faces[face_idx1]
                    fmt.fprintf(file, "f %d//%d %d//%d %d//%d\n",
                        base_vertex + face1.x, normal_idx,
                        base_vertex + face1.y, normal_idx,
                        base_vertex + face1.z, normal_idx)

                    // Second triangle
                    face2 := cube_faces[face_idx2]
                    fmt.fprintf(file, "f %d//%d %d//%d %d//%d\n",
                        base_vertex + face2.x, normal_idx,
                        base_vertex + face2.y, normal_idx,
                        base_vertex + face2.z, normal_idx)
                } else {
                    // Without normals
                    face1 := cube_faces[face_idx1]
                    fmt.fprintf(file, "f %d %d %d\n",
                        base_vertex + face1.x,
                        base_vertex + face1.y,
                        base_vertex + face1.z)

                    face2 := cube_faces[face_idx2]
                    fmt.fprintf(file, "f %d %d %d\n",
                        base_vertex + face2.x,
                        base_vertex + face2.y,
                        base_vertex + face2.z)
                }
            }

            column_idx += 1
        }

        // Progress indicator
        if (y + 1) % 100 == 0 || y == height - 1 {
            fmt.printf("\rProgress: %d/%d rows (%.1f%%)", y + 1, height, f32(y + 1) / f32(height) * 100)
        }
    }
    fmt.println()

    fmt.println("============================================================")
    fmt.printf("Export complete!\n")
    fmt.printf("Columns exported: %d\n", column_count)
    fmt.printf("Columns skipped: %d (below min height)\n", skipped_count)
    fmt.printf("Vertices: %d\n", vertex_count)
    if options.include_normals {
        fmt.printf("Normals: %d\n", normal_count)
    }
    fmt.printf("Faces: %d triangles\n", column_count * 12)
    fmt.printf("File: %s\n", filepath)
    fmt.println("============================================================")

    return true
}

// Write OBJ file header with metadata
write_obj_header :: proc(file: os.Handle, width, height: int, options: OBJ_Export_Options) {
    fmt.fprintf(file, "# Mandelbrot Set 3D Column Visualization\n")
    fmt.fprintf(file, "# Generated by Mandelbrodin\n")
    fmt.fprintf(file, "# Resolution: %dx%d\n", width, height)
    fmt.fprintf(file, "# Column width: %.2f\n", options.column_width)
    fmt.fprintf(file, "# Height scale: %.2f\n", options.height_scale)
    fmt.fprintf(file, "# Min height threshold: %.3f\n", options.min_height)
    fmt.fprintf(file, "#\n")
    fmt.fprintf(file, "# Format: Wavefront OBJ\n")
    fmt.fprintf(file, "# Vertices: v x y z\n")
    if options.include_normals {
        fmt.fprintf(file, "# Normals: vn x y z\n")
        fmt.fprintf(file, "# Faces: f v1//n1 v2//n2 v3//n3\n")
    } else {
        fmt.fprintf(file, "# Faces: f v1 v2 v3\n")
    }
    fmt.fprintf(file, "#\n\n")
}

// Helper to estimate file size before export
estimate_obj_file_size :: proc(width, height: int, options: OBJ_Export_Options) -> int {
    // Rough estimate in bytes
    columns := width * height
    vertices_per_column := 8
    normals_per_column := options.include_normals ? 6 : 0
    faces_per_column := 12

    bytes_per_vertex := 30  // "v 123.456789 123.456789 123.456789\n"
    bytes_per_normal := 25  // "vn 1.000000 0.000000 0.000000\n"
    bytes_per_face := options.include_normals ? 40 : 20

    total := columns * (
        vertices_per_column * bytes_per_vertex +
        normals_per_column * bytes_per_normal +
        faces_per_column * bytes_per_face
    )

    return total + 1024  // Add some header overhead
}
