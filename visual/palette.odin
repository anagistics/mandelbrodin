package visual

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

// Color stop for gradient
Color_Stop :: struct {
	position: f64, // 0.0 to 1.0
	r:        u8,
	g:        u8,
	b:        u8,
}

// Gradient palette definition
Gradient_Palette :: struct {
	stops: []Color_Stop,
}

// Palette file format for JSON deserialization
Palette_File :: struct {
	name:        string `json:"name"`,
	description: string `json:"description,omitempty"`,
	stops:       []Color_Stop `json:"stops"`,
}

// Loaded palette with metadata
Loaded_Palette :: struct {
	filename: string,
	name:     string,
	palette:  Gradient_Palette,
}

// Default fallback palette (Classic)
DEFAULT_PALETTE :: Gradient_Palette {
	stops = {
		{0.0, 0, 0, 0},
		{0.16, 32, 107, 203},
		{0.42, 237, 255, 255},
		{0.6425, 255, 170, 0},
		{0.8575, 0, 2, 0},
		{1.0, 0, 0, 0},
	},
}

// Validation errors
Palette_Validation_Error :: enum {
	None,
	Empty_Stops,
	Invalid_Position_Range,
	Unsorted_Positions,
	Missing_Start_Stop,
	Missing_End_Stop,
}

// Validate a palette file
validate_palette :: proc(pf: Palette_File) -> (bool, Palette_Validation_Error) {
	// Must have at least 2 stops
	if len(pf.stops) < 2 {
		return false, .Empty_Stops
	}

	// First stop must be at position 0.0
	if pf.stops[0].position != 0.0 {
		return false, .Missing_Start_Stop
	}

	// Last stop must be at position 1.0
	if pf.stops[len(pf.stops) - 1].position != 1.0 {
		return false, .Missing_End_Stop
	}

	// Check that positions are sorted and in valid range [0.0, 1.0]
	for i in 0 ..< len(pf.stops) {
		stop := pf.stops[i]

		// Position must be in range [0.0, 1.0]
		if stop.position < 0.0 || stop.position > 1.0 {
			return false, .Invalid_Position_Range
		}

		// Check sorting (each position must be >= previous)
		if i > 0 && stop.position < pf.stops[i - 1].position {
			return false, .Unsorted_Positions
		}
	}

	return true, .None
}

// Load a single palette from file
load_palette_from_file :: proc(filepath: string) -> (Loaded_Palette, bool) {
	data, ok := os.read_entire_file(filepath)
	if !ok {
		fmt.eprintln("Failed to read palette file:", filepath)
		return {}, false
	}
	defer delete(data)

	palette_file: Palette_File
	err := json.unmarshal(data, &palette_file)
	if err != nil {
		fmt.eprintln("Failed to parse palette JSON:", filepath, err)
		return {}, false
	}

	// Validate the palette
	valid, validation_err := validate_palette(palette_file)
	if !valid {
		fmt.eprintln("Palette validation failed:", filepath, validation_err)
		return {}, false
	}

	// Create loaded palette
	loaded := Loaded_Palette {
		filename = filepath,
		name = palette_file.name,
		palette = Gradient_Palette{stops = palette_file.stops},
	}

	return loaded, true
}

// Load all palettes from a directory
load_palettes :: proc(palettes_dir: string) -> [dynamic]Loaded_Palette {
	palettes := make([dynamic]Loaded_Palette)

	// Create directory if it doesn't exist
	os.make_directory(palettes_dir)

	// Read directory contents
	dir_handle, err := os.open(palettes_dir)
	if err != 0 {
		fmt.eprintln("Failed to open palettes directory:", palettes_dir)
		return palettes
	}
	defer os.close(dir_handle)

	file_infos, read_err := os.read_dir(dir_handle, -1)
	if read_err != 0 {
		fmt.eprintln("Failed to read palettes directory:", palettes_dir)
		return palettes
	}
	defer os.file_info_slice_delete(file_infos)

	// Load each .json file
	for info in file_infos {
		if info.is_dir {
			continue
		}

		if strings.has_suffix(info.name, ".json") {
			filepath := fmt.tprintf("%s/%s", palettes_dir, info.name)
			palette, ok := load_palette_from_file(filepath)
			if ok {
				append(&palettes, palette)
			}
		}
	}

	// Sort palettes by name for consistent ordering
	slice.sort_by(palettes[:], proc(i, j: Loaded_Palette) -> bool {
		return i.name < j.name
	})

	return palettes
}

// Find a palette by name (case-sensitive)
find_palette :: proc(palettes: []Loaded_Palette, name: string) -> (Gradient_Palette, bool) {
	for palette in palettes {
		if palette.name == name {
			return palette.palette, true
		}
	}
	return {}, false
}
