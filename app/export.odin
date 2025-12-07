package app

import "core:fmt"
import "core:strings"
import "core:thread"
import "core:sync"
import stbi "vendor:stb/image"

// Export resolution presets
Export_Resolution :: struct {
	name:   string,
	width:  int,
	height: int,
}

EXPORT_RESOLUTIONS := []Export_Resolution{
	{"1920x1080 (Full HD)", 1920, 1080},
	{"2560x1440 (QHD)", 2560, 1440},
	{"3840x2160 (4K)", 3840, 2160},
	{"5120x2880 (5K)", 5120, 2880},
	{"7680x4320 (8K)", 7680, 4320},
	{"15360x8640 (16K)", 15360, 8640},
}

// Thread data for parallel conversion
Conversion_Thread_Data :: struct {
	pixels:     []u32,
	rgba_data:  []u8,
	start_idx:  int,
	end_idx:    int,
}

// Worker thread for ARGB → RGB conversion
convert_pixels_worker :: proc(t: ^thread.Thread) {
	data := cast(^Conversion_Thread_Data)t.data

	for i := data.start_idx; i < data.end_idx; i += 1 {
		pixel := data.pixels[i]
		r := u8((pixel >> 16) & 0xFF)
		g := u8((pixel >> 8) & 0xFF)
		b := u8(pixel & 0xFF)

		data.rgba_data[i * 3 + 0] = r
		data.rgba_data[i * 3 + 1] = g
		data.rgba_data[i * 3 + 2] = b
	}
}

// Save PNG image using stb_image_write with optimizations
save_png :: proc(pixels: []u32, width, height: int, filepath: string) -> bool {
	NUM_THREADS :: 8

	// Convert ARGB to RGB with multi-threaded optimization
	rgb_data := make([]u8, width * height * 3)
	defer delete(rgb_data)

	pixel_count := width * height

	// Multi-threaded conversion for better performance
	if pixel_count > 100000 { // Only use threads for larger images (above ~300x300)
		threads: [NUM_THREADS]^thread.Thread
		thread_data: [NUM_THREADS]Conversion_Thread_Data

		pixels_per_thread := pixel_count / NUM_THREADS

		// Create and start threads
		for i in 0 ..< NUM_THREADS {
			start_idx := i * pixels_per_thread
			end_idx := start_idx + pixels_per_thread
			if i == NUM_THREADS - 1 {
				end_idx = pixel_count // Last thread handles remainder
			}

			thread_data[i] = Conversion_Thread_Data{
				pixels    = pixels,
				rgba_data = rgb_data, // reusing name but it's RGB now
				start_idx = start_idx,
				end_idx   = end_idx,
			}

			threads[i] = thread.create(convert_pixels_worker)
			threads[i].data = &thread_data[i]
			thread.start(threads[i])
		}

		// Wait for all threads to complete
		for i in 0 ..< NUM_THREADS {
			thread.join(threads[i])
			thread.destroy(threads[i])
		}
	} else {
		// Single-threaded for small images
		for i in 0 ..< pixel_count {
			pixel := pixels[i]
			r := u8((pixel >> 16) & 0xFF)
			g := u8((pixel >> 8) & 0xFF)
			b := u8(pixel & 0xFF)

			rgb_data[i * 3 + 0] = r
			rgb_data[i * 3 + 1] = g
			rgb_data[i * 3 + 2] = b
		}
	}

	// Note: stb_image_write doesn't expose compression level control in Odin bindings
	// Optimization: Multi-threaded pixel format conversion for large images

	// Write PNG file
	filepath_cstr := strings.clone_to_cstring(filepath)
	defer delete(filepath_cstr)

	result := stbi.write_png(
		filepath_cstr,
		i32(width),
		i32(height),
		3, // RGB channels
		raw_data(rgb_data),
		i32(width * 3), // stride
	)

	if result == 0 {
		fmt.eprintln("Failed to write PNG:", filepath)
		return false
	}

	fmt.println("Exported image to:", filepath)
	return true
}

// Export current view to image file at specified resolution
// Note: Compute function must be called from outside to avoid circular import
export_image :: proc(pixels: []u32, width, height: int, filepath: string) -> bool {
	fmt.printfln("Saving %dx%d image to %s...", width, height, filepath)

	// Save to PNG
	success := save_png(pixels, width, height, filepath)

	return success
}
