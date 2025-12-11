# Mandelbrot Explorer

A high-performance, interactive Mandelbrot set renderer with real-time GPU acceleration, multi-threaded CPU rendering, **3D visualization**, and an intuitive user interface.

Additionally, this is an exercise in _vibe_ coding using Anthropic's Claude Code. I wanted to see how this works and how to improve the outcomes. Besides this, it's an interesting way to learn several new technologies, like Odin itself, shader programming, and ImGui. Definitely worth the trial.

## Features

### 🎬 Dual Visualization Modes
- **2D Mode**: Classic flat fractal rendering with color mapping
- **3D Mode**: Revolutionary column-based visualization where iteration depth becomes physical height
  - Instanced rendering with millions of 3D columns
  - Orbital camera with full 6-DOF control (rotate, pan, zoom)
  - Real-time Phong lighting with adjustable parameters
  - Explore the Mandelbrot set as a three-dimensional landscape

### 🚀 Triple Rendering Engines
- **GPU Fragment Shader**: Real-time interactive display using OpenGL 3.3+ (50-100x faster than single-threaded CPU)
- **GPU Compute Shader**: High-resolution exports using OpenGL 4.3+ compute shaders (100-1000x faster for exports)
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
- **Ultra-Fast GPU Export**: Export up to 16K resolution (132 megapixels) in under 3 seconds
- **Background Export**: CPU exports run in separate thread - UI stays responsive during export
- **Real-Time Progress**: Live progress bar with stage tracking (Computing → Encoding → Complete)
- **Configurable Compression**: Choose speed vs file size with 10 compression levels
- **PNG Format**: Lossless compression with libpng (3.6× faster than original implementation)
- Preset interesting locations included

### 🖥️ Modern UI
- Clean tabbed interface (Controls, Bookmarks, Export)
- Real-time computation time display
- Export progress bar with stage indicators and elapsed time
- Adjustable iteration counts
- Help overlay (Press F1)

## Controls

### 2D Mode Controls

**Mouse**
| Action | Control |
|--------|---------|
| Zoom In/Out | Mouse Wheel |
| Rotate View | Ctrl + Mouse Wheel |
| Recenter | Left Click |
| Pan View | Right Click + Drag |
| Box Zoom | Shift + Left Click + Drag |

**Keyboard**
| Key | Action |
|-----|--------|
| Page Up / Down | Zoom in / out |
| Arrow Keys | Pan view |
| Shift + Arrows | Pan faster |
| `,` (comma) | Rotate counter-clockwise |
| `.` (period) | Rotate clockwise |

### 3D Mode Controls

**Mouse**
| Action | Control |
|--------|---------|
| Rotate Camera | Left Click + Drag |
| Pan Camera Target | Right Click + Drag |
| Zoom In/Out | Mouse Wheel |

**Keyboard**
| Key | Action |
|-----|--------|
| Arrow Keys | Rotate camera (2° per press) |
| Shift + Arrows | Rotate faster (5° per press) |
| Page Up / Down | Move closer / farther |
| Shift + PgUp/PgDn | Zoom faster |
| R | Reset camera to default view |

### General Controls

| Key | Action |
|-----|--------|
| Alt + Left | Go back in history |
| Alt + Right | Go forward in history |
| Ctrl + 1 / 2 / 3 | Jump to Controls / Bookmarks / Export tab |
| Ctrl + S | Export image |
| F1 | Toggle help overlay (tabbed: 2D/3D/General) |
| ESC | Quit application |

## Installation

### Prerequisites
- [Odin compiler](https://odin-lang.org/) (nightly build recommended)
- OpenGL 3.3+ support (OpenGL 4.3+ recommended for compute shaders)
- SDL2 development libraries
- libpng development libraries (for optimized PNG export)
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

### Real-Time Display Performance

| Configuration | Speedup vs Baseline | Techniques |
|--------------|---------------------|------------|
| Single-threaded scalar | 1x (baseline) | Basic loop |
| Multi-threaded scalar | ~6-8x | 8 threads + loop unrolling |
| Multi-threaded SIMD | ~16-24x | 8 threads × 4-wide AVX vectors |
| **GPU Fragment Shader** | **~50-100x** | **Hundreds/thousands of parallel cores** |

### Export Performance (4K Resolution)

| Phase | Export Time | Improvement | Technology |
|-------|-------------|-------------|------------|
| Original | 1959 ms | Baseline | Single-threaded + stb_image_write |
| Phase 1 | 1691 ms | 14% faster | Multi-threaded conversion (8 threads) |
| **Phase 2** | **551 ms** | **72% faster (3.6×)** | **GPU compute + libpng compression** |

**8K Export**: 7711 ms → 2170 ms (72% faster, 3.6× speedup)

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
│   ├── renderer.odin     # 2D rendering and exports
│   ├── renderer_3d.odin  # 3D instanced rendering
│   └── camera.odin       # 3D orbital camera system
├── visual/                # Palette and coloring systems
├── ui/                    # User interface components
│   ├── control_panel.odin # Main controls and mode switching
│   ├── help_overlay.odin # Tabbed help screen (F1)
│   └── ...               # Other UI components
├── shaders/               # GLSL shaders (fragment + compute)
│   ├── mandelbrot.frag   # 2D fragment shader (real-time display)
│   ├── mandelbrot_compute.glsl  # Compute shader (GPU exports)
│   ├── mandelbrot_3d.vert # 3D vertex shader (instancing)
│   ├── mandelbrot_3d.frag # 3D fragment shader (Phong lighting)
│   └── texture.*         # Texture display shaders
├── vendor_libpng/         # libpng bindings for optimized PNG export
├── palettes/              # Color palette definitions (JSON)
└── bookmarks/             # Saved view locations (JSON)
```

## Technical Details

**2D Rendering Modes:**
- **GPU Display Mode**: Fragment shader (OpenGL 3.3+) computes Mandelbrot in real-time for interactive exploration
- **GPU Export Mode**: Compute shader (OpenGL 4.3+) renders high-resolution exports at 100-1000× speed
- **CPU Mode**: 8-way task parallelism with dynamic work queues and 4-wide AVX SIMD vectorization

**3D Visualization (OpenGL 3.3+):**
- **Instanced Rendering**: Single draw call renders millions of cube instances efficiently
- **Height Mapping**: Iteration count/brightness extracted from 2D computation → column height
- **Phong Lighting**: Ambient + Diffuse + Specular components for realistic appearance
- **Orbital Camera**: Spherical coordinates (azimuth, elevation, distance) with smooth interpolation
- **Smart Input Routing**: Mouse position determines whether keyboard controls viewport or UI
- **Performance**: Handles 800×600 = 480,000 columns at 60+ FPS on modern GPUs

**Export Optimization:**
- Multi-threaded ARGB→RGB pixel conversion (8 threads)
- libpng with configurable compression levels (0-9)
- Level 1 compression: 42-44% faster than stb_image_write with similar file sizes
- Combined optimizations: 3.6× faster exports than original implementation

**Coordinate System:**
- Proper rotation support with consistent transformations across GPU and CPU paths
- Screen-to-world coordinate conversion handles zoom, pan, and rotation

**Smooth Coloring:**
- Uses escape distance estimation: `smooth_iter = n + 1 - log(log(|z|)) / log(2)`
- Eliminates color banding for professional-quality visualization

## Contributing

Contributions are welcome! Areas for potential improvement:
- **3D Enhancements**: Shadow mapping, 3D model export (OBJ/PLY/STL), LOD optimization
- **AVX-512 Support**: 8-wide vectorization for newer CPUs
- **Vulkan Backend**: Cross-platform GPU acceleration (Phase 3 of PLAN.md)
- **Progressive Rendering**: Adaptive coloring (Phase 2 of PLAN.md)
- **Deep Zoom**: Perturbation theory for extreme zoom levels (>10^15)
- **Animation**: Video export capabilities, camera path recording

## License

This project is under the MIT license. 
(c) 2025 Andreas Cardeneo

## Credits

Built with:
- [Odin Programming Language](https://odin-lang.org/)
- [SDL2](https://www.libsdl.org/) for windowing and input
- [Dear ImGui](https://github.com/ocornut/imgui) for user interface
- [libpng](http://www.libpng.org/pub/png/libpng.html) for optimized PNG export
- [OpenGL](https://www.opengl.org/) 3.3+ (fragment shaders) and 4.3+ (compute shaders)

## Screenshots

The following image is just one example of an exported image in 4K resolution. 
![4K Mandelbrot set image](images/example.png)

3D export of a "landscape" using adaptive coloring:
![4K Adaptive Coloring 3D Mandelbrot landscape](images/3d_ex_ac.png)

Nice spiral in 5K resolution:
![5K Spiral](images/spiral_5K.png)
