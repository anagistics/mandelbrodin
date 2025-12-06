# Mandelbrot Explorer

A high-performance, interactive Mandelbrot set renderer with real-time GPU acceleration, multi-threaded CPU rendering, and an intuitive user interface.

## Features

### 🚀 Dual Rendering Modes
- **GPU Shader Rendering**: Real-time computation using OpenGL fragment shaders (50-100x faster than single-threaded CPU)
- **CPU Rendering**: Multi-threaded SIMD vectorized computation with dynamic load balancing (16-24x speedup)
- Toggle between modes at runtime to compare performance

### 🎨 Visual Customization
- **External Palette System**: Load custom color palettes from JSON files
- **Smooth Coloring**: Continuous iteration counts for gradient color transitions without banding
- **View Rotation**: Rotate the fractal view by any angle (0-360°)
- Multiple preset palettes included: Classic, Fire, Ice, Ocean, Sunset, Grayscale, Psychedelic

### 🎯 Interactive Navigation
- **Mouse Wheel Zoom**: Smooth zooming centered on cursor position
- **Click to Recenter**: Single-click to center the view on any point
- **Pan with Drag**: Right-click and drag to pan the view
- **Box Zoom**: Shift + drag to select and zoom into a specific region
- **Keyboard Controls**: Arrow keys, Page Up/Down, rotation keys
- **History Navigation**: Browser-style back/forward through your exploration

### 💾 Save and Share
- **Bookmarks**: Save and reload your favorite locations
- **High-Resolution Export**: Export images up to 16K resolution (132 megapixels)
- **PNG Format**: Lossless compression for perfect quality
- Preset interesting locations included

### 🖥️ Modern UI
- Clean tabbed interface (Controls, Bookmarks, Export)
- Real-time computation time display
- Adjustable iteration counts
- Help overlay (Press F1)

## Controls

### Mouse Controls
| Action | Control |
|--------|---------|
| Zoom In/Out | Mouse Wheel |
| Rotate View | Ctrl + Mouse Wheel |
| Recenter | Left Click |
| Pan View | Right Click + Drag |
| Box Zoom | Shift + Left Click + Drag |

### Keyboard Shortcuts

**Navigation**
| Key | Action |
|-----|--------|
| Page Up | Zoom in |
| Page Down | Zoom out |
| Arrow Keys | Pan view |
| Shift + Arrows | Pan faster |
| `,` (comma) | Rotate counter-clockwise |
| `.` (period) | Rotate clockwise |

**History**
| Key | Action |
|-----|--------|
| Alt + Left | Go back in history |
| Alt + Right | Go forward in history |

**Tabs**
| Key | Action |
|-----|--------|
| Ctrl + 1 | Jump to Controls tab |
| Ctrl + 2 | Jump to Bookmarks tab |
| Ctrl + 3 | Jump to Export tab |

**Other**
| Key | Action |
|-----|--------|
| Ctrl + S | Export image |
| F1 | Toggle help overlay |
| ESC | Quit application |

## Installation

### Prerequisites
- [Odin compiler](https://odin-lang.org/) (nightly build recommended)
- OpenGL 3.3+ support
- SDL2 development libraries
- Linux (tested on Arch Linux, should work on other distributions)

### Building

1. Clone the repository:
```bash
git clone https://github.com/anagistics/mandelbrodin.git
cd mandelbrodin
```

2. Compile the stb_image libraries (one-time setup):
```bash
make -C ~/odin-linux-amd64-nightly+2025-10-05/vendor/stb/src
```

3. Build the project:
```bash
odin build . -out:mandelbrodin
```

4. Run:
```bash
./mandelbrodin
```

### Debug Build
For development or troubleshooting:
```bash
odin build . -debug -out:mandelbrodin
```

## System Requirements

**Minimum:**
- CPU: Multi-core processor (2+ cores)
- GPU: OpenGL 3.3 compatible graphics card
- RAM: 2 GB
- OS: Linux

**Recommended:**
- CPU: 8+ core processor with AVX support
- GPU: Modern GPU with hundreds of shader cores
- RAM: 4+ GB
- OS: Linux (Arch, Ubuntu, Fedora, etc.)

## Performance

The application features multiple optimization layers:

| Configuration | Speedup vs Baseline | Techniques |
|--------------|---------------------|------------|
| Single-threaded scalar | 1x (baseline) | Basic loop |
| Multi-threaded scalar | ~6-8x | 8 threads + loop unrolling |
| Multi-threaded SIMD | ~16-24x | 8 threads × 4-wide AVX vectors |
| **GPU Shader** | **~50-100x** | **Hundreds/thousands of parallel cores** |

## Creating Custom Palettes

Palettes are stored as JSON files in the `palettes/` directory. Create your own by following this format:

```json
{
  "name": "My Custom Palette",
  "description": "A beautiful custom color scheme",
  "stops": [
    {"position": 0.0, "r": 0, "g": 0, "b": 0},
    {"position": 0.5, "r": 255, "g": 128, "b": 0},
    {"position": 1.0, "r": 255, "g": 255, "b": 255}
  ]
}
```

- Positions must be in ascending order from 0.0 to 1.0
- RGB values range from 0 to 255
- Minimum 2 color stops required
- Place the file in `palettes/` and restart the application

## Project Structure

```
mandelbrodin/
├── appelman.odin          # Main application and event handling
├── app/                   # Core application state and logic
├── mandelbrot/            # Computation engines (scalar, SIMD)
├── renderer/              # OpenGL rendering and export
├── visual/                # Palette and coloring systems
├── ui/                    # User interface components
├── shaders/               # GLSL shaders for GPU rendering
├── palettes/              # Color palette definitions (JSON)
└── bookmarks/             # Saved view locations (JSON)
```

## Technical Details

**Rendering Modes:**
- GPU mode computes the Mandelbrot set directly in the fragment shader, enabling real-time interactive exploration
- CPU mode uses 8-way task parallelism with dynamic work queues and 4-wide AVX SIMD vectorization

**Coordinate System:**
- Proper rotation support with consistent transformations across GPU and CPU paths
- Screen-to-world coordinate conversion handles zoom, pan, and rotation

**Smooth Coloring:**
- Uses escape distance estimation: `smooth_iter = n + 1 - log(log(|z|)) / log(2)`
- Eliminates color banding for professional-quality visualization

## Contributing

Contributions are welcome! Areas for potential improvement:
- AVX-512 support for 8-wide vectorization
- Vulkan/WebGPU backend for cross-platform GPU acceleration
- Perturbation theory for extreme zoom levels (>10^15)
- Animation/video export capabilities

## License

This project is under the MIT license. 
(c) 2025 Andreas Cardeneo

## Credits

Built with:
- [Odin Programming Language](https://odin-lang.org/)
- [SDL2](https://www.libsdl.org/) for windowing and input
- [Dear ImGui](https://github.com/ocornut/imgui) for user interface
- [stb_image_write](https://github.com/nothings/stb) for PNG export

## Screenshots

The following image is just one example of an exported image in 4K resolution. 
![4K Mandelbrot set image](images/example.png)
