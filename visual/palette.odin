package visual

// Palette types
Palette_Type :: enum {
	Classic,
	Fire,
	Ice,
	Ocean,
	Sunset,
	Grayscale,
	Psychedelic,
}

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

// Convert palette type to string
palette_to_string :: proc(palette: Palette_Type) -> string {
	switch palette {
	case .Classic:     return "Classic"
	case .Fire:        return "Fire"
	case .Ice:         return "Ice"
	case .Ocean:       return "Ocean"
	case .Sunset:      return "Sunset"
	case .Grayscale:   return "Grayscale"
	case .Psychedelic: return "Psychedelic"
	}
	return "Classic"
}

// Convert string to palette type
string_to_palette :: proc(s: string) -> Palette_Type {
	switch s {
	case "Classic":     return .Classic
	case "Fire":        return .Fire
	case "Ice":         return .Ice
	case "Ocean":       return .Ocean
	case "Sunset":      return .Sunset
	case "Grayscale":   return .Grayscale
	case "Psychedelic": return .Psychedelic
	}
	return .Classic
}

// Predefined gradient palettes
get_palette :: proc(palette_type: Palette_Type) -> Gradient_Palette {
	classic_stops := []Color_Stop{
		{0.0, 0, 0, 0},
		{0.16, 32, 107, 203},
		{0.42, 237, 255, 255},
		{0.6425, 255, 170, 0},
		{0.8575, 0, 2, 0},
		{1.0, 0, 0, 0},
	}

	fire_stops := []Color_Stop{
		{0.0, 0, 0, 0},
		{0.25, 128, 0, 0},
		{0.5, 255, 0, 0},
		{0.75, 255, 128, 0},
		{1.0, 255, 255, 0},
	}

	ice_stops := []Color_Stop{
		{0.0, 0, 0, 32},
		{0.3, 0, 32, 128},
		{0.6, 0, 128, 255},
		{0.85, 128, 200, 255},
		{1.0, 255, 255, 255},
	}

	ocean_stops := []Color_Stop{
		{0.0, 0, 0, 64},
		{0.25, 0, 64, 128},
		{0.5, 0, 128, 192},
		{0.75, 64, 192, 192},
		{1.0, 192, 255, 255},
	}

	sunset_stops := []Color_Stop{
		{0.0, 0, 0, 32},
		{0.2, 64, 0, 128},
		{0.4, 128, 0, 64},
		{0.6, 255, 64, 0},
		{0.8, 255, 128, 0},
		{1.0, 255, 255, 128},
	}

	grayscale_stops := []Color_Stop{
		{0.0, 0, 0, 0},
		{0.5, 128, 128, 128},
		{1.0, 255, 255, 255},
	}

	psychedelic_stops := []Color_Stop{
		{0.0, 255, 0, 255},
		{0.14, 0, 0, 255},
		{0.28, 0, 255, 255},
		{0.42, 0, 255, 0},
		{0.56, 255, 255, 0},
		{0.7, 255, 128, 0},
		{0.84, 255, 0, 0},
		{1.0, 255, 0, 255},
	}

	switch palette_type {
	case .Classic:
		return Gradient_Palette{classic_stops}
	case .Fire:
		return Gradient_Palette{fire_stops}
	case .Ice:
		return Gradient_Palette{ice_stops}
	case .Ocean:
		return Gradient_Palette{ocean_stops}
	case .Sunset:
		return Gradient_Palette{sunset_stops}
	case .Grayscale:
		return Gradient_Palette{grayscale_stops}
	case .Psychedelic:
		return Gradient_Palette{psychedelic_stops}
	}

	return Gradient_Palette{classic_stops}
}
