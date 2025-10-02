# Black Hole GPU Ray Tracer

A real-time, scientifically accurate black hole visualization using GPU-accelerated ray tracing on macOS with Metal.

![Black Hole Rendering](screenshot.png)

## Features

### Scientific Accuracy
- **Schwarzschild Metric**: Proper general relativistic geodesic integration
- **RK4 Integration**: 4th-order Runge-Kutta for accurate light path calculation
- **Gravitational Lensing**: Einstein ring and photon sphere effects
- **Relativistic Effects**:
  - Gravitational redshift
  - Doppler shift
  - Relativistic beaming
  - Frame dragging visualization

### Visual Features
- **Accretion Disk**: Physically-based temperature gradients and opacity
- **Blackbody Radiation**: Accurate color rendering from 1000K to 40000K
- **Procedural Noise**: Multi-octave simplex noise for disk turbulence
- **Background Stars**: Procedural starfield with gravitational lensing effects
- **Orbiting Star**: Dynamically placed star with proper orbital mechanics

### Interactive Controls
- **Real-time Parameters**:
  - Gravity strength (lensing intensity)
  - Accretion disk size and thickness
  - Schwarzschild radius (event horizon size)
  - Camera position and distance
- **Observer Controls**:
  - 3D position adjustment
  - Velocity vector (for motion-based Doppler)
- **Orbiting Star**:
  - Toggle visibility
  - Orbit radius and speed
  - Brightness control
- **Relativistic Effects**:
  - Background star redshift toggle
  - Doppler effect visualization

## Requirements

- **macOS**: 10.15 (Catalina) or later
- **Hardware**: Any Mac with Metal support
  - Intel Macs with discrete GPU recommended
  - Apple Silicon (M1/M2/M3) fully supported
- **Development**:
  - Xcode 12+ with Metal support
  - CMake 3.15+

## Building

### Using CMake (Recommended)

```bash
# Clone the repository
git clone https://github.com/yourusername/BlackHoleGPU.git
cd BlackHoleGPU

# Create build directory
mkdir build && cd build

# Configure and build
cmake ..
cmake --build . --config Debug

# Run
open Debug/BlackHole.app
```

### Using Xcode

```bash
# Generate Xcode project
cmake -B build -G Xcode

# Open in Xcode
open build/BlackHoleGPU.xcodeproj
```

Then build and run from Xcode (⌘R).

## Usage

### Basic Controls

1. **Camera Distance**: Adjust how far you are from the black hole
2. **Gravity Strength**: Control the intensity of gravitational lensing (1.0 = standard, 4.0 = extreme)
3. **Disk Properties**: Modify the accretion disk radius and thickness
4. **Observer Position**: Move the camera anywhere in 3D space (X, Y, Z sliders)
5. **Orbiting Star**: Toggle and control a star orbiting the black hole

### Tips for Best Results

- Start with default settings for a "Gargantua" (Interstellar movie) style black hole
- Increase gravity to 3.5-4.0 for more dramatic lensing
- Adjust observer position to see different angles (try Y = 2.0 for tilted view)
- Enable "Show Orbiting Star" to see orbital mechanics in action
- Watch the star change color as it moves through gravitational potential

## Physics Implementation

### Geodesic Integration

The black hole simulation uses the Schwarzschild metric in natural units (G = M = c = 1). Light rays are integrated using the RK4 method:

```
d²xᵘ/dλ² + Γᵘᵥᵨ (dxᵥ/dλ)(dxᵨ/dλ) = 0
```

Where Γᵘᵥᵨ are the Christoffel symbols for the Schwarzschild metric.

### Relativistic Effects

1. **Gravitational Redshift**:
   ```
   z = √(1 - rₛ/r) - 1
   ```

2. **Doppler Shift**:
   ```
   f_observed = f_emitted × γ(1 + β·n̂)
   ```

3. **Relativistic Beaming**:
   ```
   I_observed = I_emitted × D³
   ```
   where D is the Doppler factor.

### Accretion Disk Model

The accretion disk uses a multi-scale noise function for turbulence and a temperature profile:

```
T(r) = T₀ × r⁻⁰·⁷⁵
```

Colors are computed from blackbody radiation with Wien's displacement law.

## Performance

- **Apple Silicon**: 30-60 FPS at 1280x720
- **Intel Mac (discrete GPU)**: 15-30 FPS at 1280x720
- **Intel Mac (integrated GPU)**: 8-15 FPS at 1280x720

Performance depends on:
- Ray marching iteration count (currently 512)
- Disk noise LOD (currently 4 octaves)
- Screen resolution

## Project Structure

```
BlackHoleGPU/
├── CMakeLists.txt          # Build configuration
├── README.md               # This file
├── src/
│   ├── main.cpp           # Application entry point
│   ├── Renderer.hpp       # Renderer interface
│   ├── Renderer.mm        # Metal renderer implementation
│   └── ShaderTypes.h      # Shared CPU/GPU data structures
├── shaders/
│   └── BlackHole.metal    # Metal compute shader (main physics)
└── vendor/
    ├── glfw/              # Windowing library
    ├── glm/               # Math library
    ├── imgui/             # Immediate mode GUI
    └── metal-cpp/         # Metal C++ wrapper
```

## Credits

### Physics & Algorithm
- Based on [BlackHoleRayTracer](https://github.com/hydrogendeuteride/BlackHoleRayTracer) by hydrogendeuteride
- Schwarzschild metric implementation
- Geodesic integration techniques

### Libraries
- **GLFW**: Window management
- **ImGui**: Immediate mode GUI
- **GLM**: Mathematics library
- **Metal**: Apple's GPU framework

### References
- [Interstellar's Black Hole](https://arxiv.org/abs/1502.03808) - Scientific visualization paper
- [General Relativity](https://en.wikipedia.org/wiki/Schwarzschild_metric) - Schwarzschild metric
- [Accretion Disk Physics](https://en.wikipedia.org/wiki/Accretion_disk) - Astrophysical background

## License

MIT License - See LICENSE file for details.

Original physics implementation by hydrogendeuteride.
Metal port and macOS adaptation by contributors.

## Contributing

Contributions are welcome! Areas for improvement:

- [ ] Kerr metric (rotating black holes)
- [ ] Photon sphere visualization
- [ ] Multiple black holes
- [ ] VR support
- [ ] Video recording
- [ ] More accretion disk models
- [ ] Neutron star support

## Contact

For questions, issues, or contributions, please open an issue on GitHub.

---

*"The black hole teaches us that space can be crumpled like a piece of paper into an infinitesimal dot, that time can be extinguished like a blown-out flame, and that the laws of physics that we regard as 'sacred,' as immutable, are anything but."* - John Wheeler
