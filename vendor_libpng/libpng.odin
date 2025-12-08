package vendor_libpng

import "core:c"

when ODIN_OS == .Windows {
	foreign import libpng "libpng16.lib"
} else when ODIN_OS == .Linux {
	foreign import libpng "system:png16"
} else when ODIN_OS == .Darwin {
	foreign import libpng "system:png16"
} else {
	foreign import libpng "system:png16"
}

// PNG version info
PNG_LIBPNG_VER_STRING :: "1.6.43"

// Color types
PNG_COLOR_TYPE_GRAY       :: 0
PNG_COLOR_TYPE_PALETTE    :: 3
PNG_COLOR_TYPE_RGB        :: 2
PNG_COLOR_TYPE_RGB_ALPHA  :: 6
PNG_COLOR_TYPE_GRAY_ALPHA :: 4

// Interlace types
PNG_INTERLACE_NONE  :: 0
PNG_INTERLACE_ADAM7 :: 1

// Compression types
PNG_COMPRESSION_TYPE_BASE    :: 0
PNG_COMPRESSION_TYPE_DEFAULT :: 0

// Filter types
PNG_FILTER_TYPE_BASE    :: 0
PNG_FILTER_TYPE_DEFAULT :: 0

// Compression levels (0-9)
PNG_COMPRESSION_LEVEL_DEFAULT :: -1
PNG_COMPRESSION_LEVEL_NONE    :: 0
PNG_COMPRESSION_LEVEL_FAST    :: 1
PNG_COMPRESSION_LEVEL_BEST    :: 9

// Transform flags
PNG_TRANSFORM_IDENTITY :: 0x0000

// Opaque structure types
png_struct  :: struct {}
png_info    :: struct {}
png_structp :: ^png_struct
png_infop   :: ^png_info

// Row pointer type
png_bytep   :: [^]u8
png_bytepp  :: [^]png_bytep

// Size types
png_size_t  :: c.size_t
png_uint_32 :: u32
png_int_32  :: i32
png_byte    :: u8

// Write callback type
png_rw_ptr :: proc "c" (png_ptr: png_structp, data: png_bytep, length: png_size_t)
png_flush_ptr :: proc "c" (png_ptr: png_structp)

// Error handling
png_error_ptr :: proc "c" (png_ptr: png_structp, msg: cstring)
png_error_ptr_null :: proc "c" (png_ptr: png_structp, msg: cstring)

@(default_calling_convention = "c", link_prefix = "png_")
foreign libpng {
	// Create/destroy write structs
	create_write_struct :: proc(
		user_png_ver: cstring,
		error_ptr: rawptr,
		error_fn: png_error_ptr,
		warn_fn: png_error_ptr,
	) -> png_structp ---

	create_info_struct :: proc(png_ptr: png_structp) -> png_infop ---

	destroy_write_struct :: proc(
		png_ptr_ptr: ^png_structp,
		info_ptr_ptr: ^png_infop,
	) ---

	// I/O functions
	init_io :: proc(png_ptr: png_structp, fp: rawptr) ---

	set_write_fn :: proc(
		png_ptr: png_structp,
		io_ptr: rawptr,
		write_data_fn: png_rw_ptr,
		output_flush_fn: png_flush_ptr,
	) ---

	// Write functions
	set_IHDR :: proc(
		png_ptr: png_structp,
		info_ptr: png_infop,
		width: png_uint_32,
		height: png_uint_32,
		bit_depth: c.int,
		color_type: c.int,
		interlace_method: c.int,
		compression_method: c.int,
		filter_method: c.int,
	) ---

	set_compression_level :: proc(png_ptr: png_structp, level: c.int) ---

	write_info :: proc(png_ptr: png_structp, info_ptr: png_infop) ---

	write_image :: proc(png_ptr: png_structp, image: png_bytepp) ---

	write_row :: proc(png_ptr: png_structp, row: png_bytep) ---

	write_end :: proc(png_ptr: png_structp, info_ptr: png_infop) ---

	// Error handling
	set_error_fn :: proc(
		png_ptr: png_structp,
		error_ptr: rawptr,
		error_fn: png_error_ptr,
		warning_fn: png_error_ptr,
	) -> rawptr ---

	// Get functions for error checking
	get_error_ptr :: proc(png_ptr: png_structp) -> rawptr ---
}
