package app

import "core:fmt"
import visual "../visual"

// Load all palettes from directory
load_palettes_from_dir :: proc(state: ^App_State) {
	state.palettes = visual.load_palettes(state.palettes_dir)

	if len(state.palettes) == 0 {
		fmt.eprintln("Warning: No palettes loaded, using default palette")
		state.palette = "Classic"
		state.current_palette = visual.DEFAULT_PALETTE
	}
}

// Set the current palette by name
set_palette :: proc(state: ^App_State, palette_name: string) {
	// Try to find the palette
	palette, found := visual.find_palette(state.palettes[:], palette_name)
	if found {
		state.palette = palette_name
		state.current_palette = palette
		state.needs_recompute = true
	} else {
		fmt.eprintln("Warning: Palette not found:", palette_name, "- using default")
		state.palette = "Classic"
		state.current_palette = visual.DEFAULT_PALETTE
		state.needs_recompute = true
	}
}
