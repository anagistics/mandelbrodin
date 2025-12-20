# Windows Porting Guide

This document outlines the code changes and setup required to compile and run Mandelbrot Explorer on Windows using the Windows Odin implementation.

## Summary

The codebase is **largely platform-agnostic** thanks to Odin's cross-platform standard library and vendor packages. Most platform-specific code is already handled via `when ODIN_OS` conditionals. However, several build configuration and dependency setup changes are required for Windows.

## Current Platform-Specific Code

### ✅ Already Cross-Platform Compatible

The following components already have proper Windows support:

1. **libpng bindings** (`vendor_libpng/libpng.odin:5-13`)
   ```odin
   when ODIN_OS == .Windows {
       foreign import libpng "libpng16.lib"
   } else when ODIN_OS == .Linux {
       foreign import libpng "system:png16"
   }
   ```
   ✅ **No changes needed** - Already conditionally imports Windows library

2. **File I/O operations**
   - Uses `core:os` functions: `read_entire_file()`, `write_entire_file()`, `open()`, `read_dir()`, `remove()`
   - ✅ **No changes needed** - These are cross-platform

3. **Threading**
   - Uses `core:thread` and `core:sync` packages
   - ✅ **No changes needed** - Cross-platform threading

4. **SDL2, OpenGL, ImGui**
   - All use Odin vendor packages
   - ✅ **No changes needed** - Vendor packages handle platform differences

5. **C library functions** (`app/export.odin:12-18`)
   ```odin
   foreign import libc "system:c"
   fopen  :: proc(filename: cstring, mode: cstring) -> rawptr
   fclose :: proc(stream: rawptr) -> c.int
   ```
   ✅ **No changes needed** - Uses `system:c` which works on Windows

### ⚠️ Areas Requiring Attention

## 1. Path Separator Handling

**Current State:**
- Code uses hardcoded forward slashes (`/`) for path construction
- Examples:
  ```odin
  // visual/palette.odin:155
  filepath := fmt.tprintf("%s/%s", palettes_dir, info.name)

  // app/bookmark.odin:230
  filepath := fmt.tprintf("%s/%s", state.bookmarks_dir, name)
  ```

**Issue:**
- Forward slashes work on modern Windows in most contexts
- However, this is not formally guaranteed and may cause issues with some Windows APIs

**Recommended Fix:**
Use `core:path` package for proper cross-platform path handling:

```odin
import "core:path/filepath"

// Instead of:
filepath := fmt.tprintf("%s/%s", dir, filename)

// Use:
filepath := filepath.join({dir, filename}, context.temp_allocator)
```

**Files to Update:**
- `visual/palette.odin:155` - Palette loading
- `app/bookmark.odin:230, 248, 250, 264, 277` - Bookmark path construction

**Priority:** ⭐⭐⭐ Medium (current code may work, but not guaranteed)

## 2. Build Instructions

**Current Linux Build:**
```bash
# From README.md
odin build . -out:mandelbrodin
```

**Windows Build:**
```cmd
REM Basic build
odin build . -out:mandelbrodin.exe

REM Debug build
odin build . -debug -out:mandelbrodin.exe

REM Optimized release build
odin build . -o:speed -out:mandelbrodin.exe
```

**Note:** Windows automatically appends `.exe` extension, so `-out:mandelbrodin` works too.

## 3. Dependency Installation

### Prerequisites for Windows

1. **Odin Compiler**
   - Download from [odin-lang.org](https://odin-lang.org/download/)
   - Extract to a location (e.g., `C:\odin`)
   - Add to PATH: `C:\odin`

2. **Visual C++ Build Tools**
   - Required for C library linking
   - Install Visual Studio 2022 Community Edition OR
   - Install Build Tools for Visual Studio 2022 (lighter option)
   - Ensure "Desktop development with C++" workload is selected

3. **SDL2**
   - Download development libraries: [SDL2-devel-2.x.x-VC.zip](https://www.libsdl.org/download-2.0.php)
   - Extract to a location (e.g., `C:\SDL2`)
   - Copy `SDL2.dll` from `lib\x64\` to your project directory or `C:\Windows\System32`
   - Odin will find SDL2 via vendor package

4. **OpenGL**
   - Included with graphics drivers
   - Ensure graphics drivers are up-to-date
   - OpenGL 3.3+ required (4.3+ recommended for compute shaders)

5. **libpng**
   - Download pre-built binaries from [libpng.org](http://www.libpng.org/pub/png/libpng.html) or use vcpkg:
     ```cmd
     vcpkg install libpng:x64-windows
     ```
   - Required files:
     - `libpng16.lib` - Link-time library
     - `libpng16.dll` - Runtime library
     - `zlib1.dll` - Dependency (compression)

   **Library Setup:**
   - Copy `libpng16.lib` to a library directory (e.g., `C:\libs\`)
   - Add library path to Odin build:
     ```cmd
     odin build . -extra-linker-flags:"/LIBPATH:C:\libs" -out:mandelbrodin.exe
     ```
   - OR place `libpng16.lib` in the project directory
   - Copy `libpng16.dll` and `zlib1.dll` to project directory (next to `.exe`)

### Alternative: Using vcpkg

vcpkg simplifies Windows dependency management:

```cmd
# Install vcpkg
git clone https://github.com/microsoft/vcpkg
cd vcpkg
bootstrap-vcpkg.bat

# Install dependencies
vcpkg install sdl2:x64-windows
vcpkg install libpng:x64-windows

# Integrate with Visual Studio
vcpkg integrate install
```

Then build with:
```cmd
odin build . -extra-linker-flags:"/LIBPATH:C:\vcpkg\installed\x64-windows\lib" -out:mandelbrodin.exe
```

## 4. stb_image Library Compilation

**Current Linux Instructions (README.md:122-124):**
```bash
make -C ~/odin-linux-amd64-nightly+2025-10-05/vendor/stb/src
```

**Windows Equivalent:**

The Odin Windows distribution includes pre-compiled stb libraries. **No manual compilation needed.**

If rebuilding is required:
```cmd
REM Navigate to Odin vendor directory
cd %ODIN_ROOT%\vendor\stb\src

REM Compile with MSVC (if make is unavailable)
cl /c /O2 stb_image.c
cl /c /O2 stb_image_write.c
lib /OUT:stb_image.lib stb_image.obj stb_image_write.obj
```

**Recommended:** Just use the pre-built libraries included with Odin.

## 5. Running the Application

### Windows-Specific Runtime Requirements

1. **DLL Files** must be in the same directory as `mandelbrodin.exe`:
   - `SDL2.dll`
   - `libpng16.dll`
   - `zlib1.dll`

2. **Working Directory** must be the project root:
   ```cmd
   REM From project root
   mandelbrodin.exe
   ```

   This ensures the application finds:
   - `shaders/` directory
   - `palettes/` directory
   - `bookmarks/` directory

3. **Directory Creation:**
   - `palettes/` and `bookmarks/` directories are auto-created if missing
   - Shaders must exist before running

### Troubleshooting

**"Cannot find SDL2.dll":**
- Ensure `SDL2.dll` is in the same directory as `mandelbrodin.exe`
- Or add SDL2 bin directory to PATH

**"Cannot find libpng16.dll":**
- Copy `libpng16.dll` and `zlib1.dll` to project directory

**"Failed to initialize renderer":**
- Check OpenGL version: Run `dxdiag` → Display → Check driver version
- Update graphics drivers

**"Failed to read shader file":**
- Ensure working directory is project root
- Verify `shaders/` directory exists with all `.vert`, `.frag`, `.glsl` files

## 6. Shader Path Handling

**Current Code:**
```odin
// renderer/renderer.odin:151
compute_program, ok := create_compute_program("shaders/mandelbrot_compute.glsl")

// renderer/renderer_3d.odin:461-462
vert_source := #load("../shaders/mandelbrot_3d.vert", cstring)
frag_source := #load("../shaders/mandelbrot_3d.frag", cstring)
```

**Status:**
✅ **No changes needed** - Forward slashes work in Windows file paths for Odin's `#load` directive and `os.read_entire_file()`

**Note:** `#load` is a compile-time directive, so paths are resolved during compilation.

## 7. File Extensions

No changes needed - JSON files (`.json`) and shader files (`.vert`, `.frag`, `.glsl`) work identically on Windows.

## Complete Windows Setup Checklist

- [ ] Install Odin compiler (Windows distribution)
- [ ] Install Visual Studio 2022 Build Tools
- [ ] Install SDL2 development libraries
- [ ] Install libpng + zlib (via vcpkg or manual download)
- [ ] Copy DLLs to project directory:
  - [ ] `SDL2.dll`
  - [ ] `libpng16.dll`
  - [ ] `zlib1.dll`
- [ ] (Optional) Update path construction to use `core:path/filepath`
- [ ] Build project: `odin build . -out:mandelbrodin.exe`
- [ ] Run from project root: `mandelbrodin.exe`

## Tested Configurations

### Recommended Setup
- **OS:** Windows 10/11 (64-bit)
- **Odin:** Latest nightly build (Windows)
- **Compiler:** Visual Studio 2022 Build Tools
- **Dependencies:** vcpkg-installed (SDL2, libpng)
- **GPU:** NVIDIA/AMD with OpenGL 4.3+ support

### Minimum Setup
- **OS:** Windows 10 (64-bit)
- **Odin:** Stable release
- **Compiler:** Visual Studio 2019 Build Tools
- **OpenGL:** 3.3+ (fragment shaders only, no compute shader exports)

## Performance Notes

- **SIMD (AVX):** Odin's `core:simd` works on Windows x64 with AVX support
- **Multi-threading:** Windows thread scheduling may differ slightly from Linux
- **GPU Performance:** Identical to Linux (OpenGL is cross-platform)
- **Export Performance:** libpng compression performance is equivalent

## Known Limitations

1. **Console Window:** Windows GUI applications show a console by default
   - Can be hidden with linker flag: `-subsystem:windows` (but loses debug output)
   - Recommended: Keep console for development

2. **Path Length:** Windows MAX_PATH (260 chars) may limit deep directory nesting
   - Not an issue for this project's structure

3. **Case Sensitivity:** Windows filesystem is case-insensitive
   - Palette/bookmark names are case-sensitive in code
   - "Classic.json" and "classic.json" are the same file on Windows but different in code

## Code Changes Required: Summary

### Mandatory Changes
**None** - The code should compile and run on Windows without modifications.

### Recommended Changes (for robustness)

1. **Path Construction** (6 locations):
   - `visual/palette.odin:155`
   - `app/bookmark.odin:230, 248, 250, 264, 277`

   Replace:
   ```odin
   filepath := fmt.tprintf("%s/%s", dir, filename)
   ```

   With:
   ```odin
   import "core:path/filepath"
   filepath := filepath.join({dir, filename}, context.temp_allocator)
   ```

2. **README.md Updates**:
   - Add Windows build instructions
   - Update dependency installation section
   - Remove Linux-specific stb compilation step
   - Add Windows DLL requirements

### Optional Enhancements

1. **Platform-Specific Defaults**:
   ```odin
   when ODIN_OS == .Windows {
       DEFAULT_PALETTE_DIR :: "palettes"
       DEFAULT_BOOKMARK_DIR :: "bookmarks"
   } else {
       DEFAULT_PALETTE_DIR :: "palettes"
       DEFAULT_BOOKMARK_DIR :: "bookmarks"
   }
   ```
   (Currently identical, but allows future customization)

2. **Case-Insensitive Palette Lookup** (Windows consideration):
   ```odin
   // visual/palette.odin:172
   find_palette :: proc(palettes: []Loaded_Palette, name: string) -> (Gradient_Palette, bool) {
       for palette in palettes {
           when ODIN_OS == .Windows {
               if strings.to_lower(palette.name) == strings.to_lower(name) {
                   return palette.palette, true
               }
           } else {
               if palette.name == name {
                   return palette.palette, true
               }
           }
       }
       return {}, false
   }
   ```

## Conclusion

**Porting Effort:** ⭐⭐ Low

The Mandelbrot Explorer codebase is **well-designed for cross-platform compatibility**. The use of Odin's standard library (`core:os`, `core:thread`) and vendor packages (`vendor:OpenGL`, `vendor:sdl2`, `vendor:imgui`) means the code is inherently portable.

**Required Code Changes:** 0 mandatory, 6 lines recommended (path construction)

**Required Setup Changes:** Standard Windows dependency installation

The application should compile and run on Windows with **zero code changes**, requiring only proper dependency setup and build configuration.
