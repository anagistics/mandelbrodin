package app

import png "../vendor_libpng"
import "core:c"
import "core:fmt"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import stbi "vendor:stb/image"

foreign import libc "system:c"

@(default_calling_convention = "c")
foreign libc {
	fopen :: proc(filename: cstring, mode: cstring) -> rawptr ---
	fclose :: proc(stream: rawptr) -> c.int ---
}

// Export resolution presets
Export_Resolution :: struct {
	name:   string,
	width:  int,
	height: int,
}

EXPORT_RESOLUTIONS := []Export_Resolution {
	{"1920x1080 (Full HD)", 1920, 1080},
	{"2560x1440 (QHD)", 2560, 1440},
	{"3840x2160 (4K)", 3840, 2160},
	{"5120x2880 (5K)", 5120, 2880},
	{"7680x4320 (8K)", 7680, 4320},
	{"15360x8640 (16K)", 15360, 8640},
}

// Thread data for parallel conversion
Conversion_Thread_Data :: struct {
	pixels:    []u32,
	rgba_data: []u8,
	start_idx: int,
	end_idx:   int,
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
save_png :: proc(
	pixels: []u32,
	width, height: int,
	filepath: string,
	state: ^App_State = nil,
) -> bool {
	NUM_THREADS :: 8

	// Convert ARGB to RGB with multi-threaded optimization
	rgb_data := make([]u8, width * height * 3)
	defer delete(rgb_data)

	pixel_count := width * height

	// Multi-threaded conversion for better performance
	if pixel_count > 100000 { 	// Only use threads for larger images (above ~300x300)
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

			thread_data[i] = Conversion_Thread_Data {
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

// Save PNG image using libpng with compression level control
save_png_libpng :: proc(
	pixels: []u32,
	width, height: int,
	filepath: string,
	compression_level: u8 = 6,
	state: ^App_State = nil,
) -> bool {
	NUM_THREADS :: 8

	// Convert ARGB to RGB with multi-threaded optimization (same as stb version)
	rgb_data := make([]u8, width * height * 3)
	defer delete(rgb_data)

	pixel_count := width * height

	// Multi-threaded conversion for better performance
	if pixel_count > 100000 {
		threads: [NUM_THREADS]^thread.Thread
		thread_data: [NUM_THREADS]Conversion_Thread_Data

		pixels_per_thread := pixel_count / NUM_THREADS

		for i in 0 ..< NUM_THREADS {
			start_idx := i * pixels_per_thread
			end_idx := start_idx + pixels_per_thread
			if i == NUM_THREADS - 1 {
				end_idx = pixel_count
			}

			thread_data[i] = Conversion_Thread_Data {
				pixels    = pixels,
				rgba_data = rgb_data,
				start_idx = start_idx,
				end_idx   = end_idx,
			}

			threads[i] = thread.create(convert_pixels_worker)
			threads[i].data = &thread_data[i]
			thread.start(threads[i])
		}

		for i in 0 ..< NUM_THREADS {
			thread.join(threads[i])
			thread.destroy(threads[i])
		}

		// Update progress after pixel conversion
		if state != nil {
			state.export_progress = 0.7
		}
	} else {
		for i in 0 ..< pixel_count {
			pixel := pixels[i]
			r := u8((pixel >> 16) & 0xFF)
			g := u8((pixel >> 8) & 0xFF)
			b := u8(pixel & 0xFF)

			rgb_data[i * 3 + 0] = r
			rgb_data[i * 3 + 1] = g
			rgb_data[i * 3 + 2] = b
		}

		// Update progress after pixel conversion
		if state != nil {
			state.export_progress = 0.7
		}
	}

	// Open file for writing
	filepath_cstr := strings.clone_to_cstring(filepath)
	defer delete(filepath_cstr)

	fp := fopen(filepath_cstr, "wb")
	if fp == nil {
		fmt.eprintln("Failed to open file for writing:", filepath)
		return false
	}
	defer fclose(fp)

	// Create PNG write structure
	png_ptr := png.create_write_struct(png.PNG_LIBPNG_VER_STRING, nil, nil, nil)
	if png_ptr == nil {
		fmt.eprintln("Failed to create PNG write struct")
		return false
	}

	// Create PNG info structure
	info_ptr := png.create_info_struct(png_ptr)
	if info_ptr == nil {
		png.destroy_write_struct(&png_ptr, nil)
		fmt.eprintln("Failed to create PNG info struct")
		return false
	}

	// Set up error handling (simplified - using defaults)
	// Note: libpng uses setjmp/longjmp for error handling, which is complex in Odin
	// For now, we'll rely on the default error handlers

	// Initialize I/O
	png.init_io(png_ptr, rawptr(fp))

	// Set image information
	png.set_IHDR(
		png_ptr,
		info_ptr,
		png.png_uint_32(width),
		png.png_uint_32(height),
		8, // bit depth
		png.PNG_COLOR_TYPE_RGB,
		png.PNG_INTERLACE_NONE,
		png.PNG_COMPRESSION_TYPE_DEFAULT,
		png.PNG_FILTER_TYPE_DEFAULT,
	)

	// Set compression level (0-9, default is 6)
	// 0 = no compression, 1 = fastest, 9 = best compression
	png.set_compression_level(png_ptr, c.int(compression_level))

	// Write header
	png.write_info(png_ptr, info_ptr)

	// Prepare row pointers
	row_pointers := make([]png.png_bytep, height)
	defer delete(row_pointers)

	for i in 0 ..< height {
		row_pointers[i] = png.png_bytep(&rgb_data[i * width * 3])
	}

	// Write image data
	png.write_image(png_ptr, raw_data(row_pointers))

	// Finish writing
	png.write_end(png_ptr, info_ptr)

	// Clean up
	png.destroy_write_struct(&png_ptr, &info_ptr)

	// Update progress to complete
	if state != nil {
		state.export_progress = 1.0
	}

	fmt.println("Exported image to:", filepath)
	return true
}

// Export current view to image file at specified resolution
// Note: Compute function must be called from outside to avoid circular import
// compression_level: 0-9 (0=none, 1=fastest, 6=default, 9=best compression)
//                    or -1 to use stb_image_write fallback
// state: optional pointer to App_State for progress tracking
export_image :: proc(
	pixels: []u32,
	width, height: int,
	filepath: string,
	compression_level: u8 = 1,
	state: ^App_State = nil,
) -> bool {
	fmt.printfln("Saving %dx%d image to %s...", width, height, filepath)

	// Update stage to Encoding if we have state
	if state != nil {
		state.export_stage = .Encoding
		state.export_progress = 0.5
	}

	// Use libpng with configurable compression level for better performance
	success: bool
	if compression_level >= 0 && compression_level <= 9 {
		success = save_png_libpng(pixels, width, height, filepath, compression_level, state)
	} else {
		// Fallback to stb_image_write (slower, but no compression control)
		success = save_png(pixels, width, height, filepath, state)
	}

	return success
}

// Compute function signature for export threading
// Takes (state, width, height) and computes pixels into state.pixels
Compute_Func :: #type proc(state: ^App_State, width, height: int)

// Thread data for background export
Export_Thread_Data :: struct {
	// Input parameters
	state:             ^App_State,
	width:             int,
	height:            int,
	filepath:          string,
	compression_level: u8,
	compute_func:      Compute_Func, // Function to compute pixels

	// Thread handle
	thread_handle:     ^thread.Thread,

	// Status (accessed atomically from main thread)
	is_complete:       bool,
	success:           bool,
}

// Worker function for background CPU export
export_cpu_worker :: proc(t: ^thread.Thread) {
	data := cast(^Export_Thread_Data)t.data
	state := data.state

	// Allocate pixel buffer
	pixels := make([]u32, data.width * data.height)
	defer delete(pixels)

	// Create temporary export state
	export_state := state^
	export_state.pixels = pixels

	// Compute Mandelbrot at export resolution (this updates state.export_progress)
	fmt.printfln("Computing %dx%d image...", data.width, data.height)
	start_time := time.now()
	data.compute_func(&export_state, data.width, data.height)
	end_time := time.now()

	duration := time.diff(start_time, end_time)
	fmt.printfln("Computation took %.2f ms", time.duration_milliseconds(duration))

	// Save to file (this also updates state.export_progress)
	success := export_image(
		pixels,
		data.width,
		data.height,
		data.filepath,
		data.compression_level,
		state,
	)

	// Update completion status
	sync.atomic_store(&data.success, success)
	sync.atomic_store(&data.is_complete, true)

	if success {
		fmt.println("✓ Background export completed successfully!")
	} else {
		fmt.eprintln("✗ Background export failed!")
	}
}

// Start a background export thread (for CPU exports only)
// Returns thread data that must be polled and freed by caller
// compute_func: function to compute pixels (e.g., mb.Compute)
export_image_async :: proc(
	state: ^App_State,
	width, height: int,
	filepath: string,
	compression_level: u8,
	compute_func: Compute_Func,
) -> ^Export_Thread_Data {
	// Allocate thread data (caller must free after thread completes)
	data := new(Export_Thread_Data)
	data.state = state
	data.width = width
	data.height = height
	data.filepath = strings.clone(filepath) // Clone string for thread safety
	data.compression_level = compression_level
	data.compute_func = compute_func
	data.is_complete = false
	data.success = false

	// Create and start thread
	data.thread_handle = thread.create(export_cpu_worker)
	data.thread_handle.data = data
	thread.start(data.thread_handle)

	fmt.println("Started background export thread...")
	return data
}

// Check if export thread is complete and clean up if done
// Returns true if export is still running, false if complete
poll_export_thread :: proc(data: ^Export_Thread_Data) -> (still_running: bool) {
	if data == nil {
		return false
	}

	// Check if complete
	is_complete := sync.atomic_load(&data.is_complete)
	if !is_complete {
		return true // Still running
	}

	// Thread is complete, join and cleanup
	thread.join(data.thread_handle)
	thread.destroy(data.thread_handle)

	// Free cloned filepath
	delete(data.filepath)

	// Get final success status
	success := sync.atomic_load(&data.success)

	// Update app state
	if success {
		data.state.export_stage = .Completed
		data.state.export_progress = 1.0
	} else {
		data.state.export_stage = .Error
		data.state.export_error = "Export failed (check console for details)"
	}

	data.state.export_in_progress = false

	// Free thread data
	free(data)

	return false // Complete
}
