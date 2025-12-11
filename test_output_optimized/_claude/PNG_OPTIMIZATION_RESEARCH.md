# PNG Encoding Optimization Research

## Current Implementation Analysis

**Library**: stb_image_write (single-threaded, simple API)
**Bottleneck**: 
- ARGB → RGB conversion (single-threaded loop)
- PNG compression (single-threaded zlib)
- Total time: 500-7,000ms for 1080p-8K

## Optimization Strategies

### Strategy 1: Reduce Conversion Overhead
**Change**: Use RGBA instead of RGB (saves conversion step)
**Expected improvement**: ~10-20% (eliminates one copy)
**Trade-off**: Slightly larger files (~33% bigger)

### Strategy 2: Lower Compression Level  
**Change**: Reduce zlib compression level (if supported by stb)
**Expected improvement**: 2-3x faster encoding
**Trade-off**: Larger file sizes (~2-3x)

### Strategy 3: Multi-threaded Conversion
**Change**: Parallelize ARGB→RGB/RGBA conversion
**Expected improvement**: 6-8x on 8-core CPU (for conversion only)
**Trade-off**: More complex code

### Strategy 4: Alternative PNG Library
**Change**: Use libpng or fpng (faster alternatives)
**Expected improvement**: 2-10x faster
**Trade-off**: Additional dependencies

## Recommended Approach

**Phase 1 (Quick Win)**: 
1. Use RGBA format (skip packed→unpacked conversion)
2. Multi-thread the pixel format conversion
3. Add compression level control

**Phase 2 (If needed)**:
- Consider fpng (very fast PNG encoder)
- Or use libpng with threading

Let me implement Phase 1 optimizations...
