package app

import "core:fmt"
import "core:strings"
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

// Save PNG image using stb_image_write
save_png :: proc(pixels: []u32, width, height: int, filepath: string) -> bool {
	// Convert ARGB to RGB (stb_image_write expects RGB or RGBA)
	rgb_data := make([]u8, width * height * 3)
	defer delete(rgb_data)

	for i in 0 ..< width * height {
		pixel := pixels[i]
		r := u8((pixel >> 16) & 0xFF)
		g := u8((pixel >> 8) & 0xFF)
		b := u8(pixel & 0xFF)

		rgb_data[i * 3 + 0] = r
		rgb_data[i * 3 + 1] = g
		rgb_data[i * 3 + 2] = b
	}

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
