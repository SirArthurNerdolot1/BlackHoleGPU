# Quick Start Guide

Welcome to **Black Hole GPU** - a real-time black hole ray tracer with scientifically accurate physics!

## 🚀 Getting Started in 5 Minutes

### Prerequisites
- macOS 11.0 (Big Sur) or later
- Xcode or Xcode Command Line Tools
- CMake 3.15+ (install via Homebrew: `brew install cmake`)

### Build & Run
```bash
# 1. Clone the repository
git clone <your-repo-url>
cd BlackHoleGPU

# 2. Build with CMake
mkdir build && cd build
cmake ..
cmake --build . --config Debug

# 3. Launch the app
open Debug/BlackHole.app
```

That's it! You should see a black hole with an accretion disk rendering in real-time.

## Controls Overview

### Main Sliders (Left Panel)
These control the core physics of the simulation:

| Slider | Range | Effect |
|--------|-------|--------|
| **Gravity** | 0.1 - 10.0 | Strength of gravitational field (affects light bending) |
| **Disk Radius** | 1.0 - 20.0 | Size of the accretion disk in Schwarzschild radii |
| **Disk Thickness** | 0.01 - 2.0 | Vertical thickness of the disk |
| **Black Hole Size** | 0.01 - 1.0 | Size of the event horizon |
| **Camera Distance** | 3.0 - 20.0 | How far the camera orbits from the black hole |

### Quick Presets

**Classic Gargantua (like Interstellar)**
- Gravity: 2.5
- Disk Radius: 5.0
- Disk Thickness: 0.2
- Black Hole Size: 0.12
- Camera Distance: 8.0

**Extreme Gravity**
- Gravity: 8.0
- Disk Radius: 15.0
- Disk Thickness: 0.5
- Black Hole Size: 0.5
- Camera Distance: 12.0

**Thin Disk**
- Gravity: 3.0
- Disk Radius: 10.0
- Disk Thickness: 0.05
- Black Hole Size: 0.2
- Camera Distance: 10.0

##  Advanced Features

### Scientific Parameters
Toggle these for different physics effects:

- **Disk Enabled**: Show/hide the accretion disk
- **Doppler Effect**: Color shift from orbital motion
- **Gravitational Redshift**: Frequency shift from gravity
- **Relativistic Beaming**: Intensity enhancement for moving matter
- **Realistic Temperature**: Use physical blackbody temperatures

### Integration Methods
- **Verlet**: Faster, good for most cases (2nd order accuracy)
- **RK4**: More accurate, slightly slower (4th order accuracy)

### Observer Controls
Set your position and velocity in 3D space:
- **Position**: X, Y, Z coordinates
- **Velocity**: X, Y, Z velocity components for Doppler effects

### Orbiting Star
Add a star orbiting the black hole:
- **Show Star**: Toggle visibility
- **Orbit Radius**: Distance from black hole (3.0-15.0)
- **Orbit Speed**: Angular velocity (0.1-2.0 rad/s)
- **Brightness**: Star luminosity

### Background Effects
- **Background Redshift**: Apply gravitational redshift to distant stars
- **Background Doppler**: Apply Doppler shift to background

##  Tips & Tricks

### Best Visual Results
1. Start with the Gargantua preset
2. Enable all relativistic effects
3. Set realistic temperature to ON
4. Adjust camera distance to 6-10 for dramatic lensing

### Performance
- Runs at 9-10 FPS on integrated GPU
- Lower resolution → higher frame rate
- Disable background effects for slight speedup

### Understanding the Physics
- **Einstein Ring**: When camera, black hole, and disk align
- **Gravitational Lensing**: Light bends around the black hole
- **Photon Sphere**: At r=3M, light can orbit the black hole
- **Event Horizon**: At r=2M, nothing can escape

### Experimentation
- Try Gravity = 10.0 and Camera Distance = 3.5 for extreme lensing
- Set Disk Thickness = 0.01 for a razor-thin disk
- Enable orbiting star and watch gravitational redshift effects
- Adjust accretion temperature (1000K-40000K) for different colors

##  Learn More

### Documentation
- **README.md**: Full feature list and build instructions
- **CONTRIBUTING.md**: How to contribute code or bug reports
- **CHANGELOG.md**: Version history and planned features

### Physics Background
The simulation implements:
- **Schwarzschild Metric**: For non-rotating black holes
- **Geodesic Integration**: Ray tracing in curved spacetime
- **Accretion Disk Model**: Geometrically thin, optically thick

### References
- Schwarzschild, K. (1916). *On the Gravitational Field of a Mass Point*
- James et al. (2015). *Gravitational lensing by spinning black holes in astrophysics, and in the movie Interstellar*
- Chandrasekhar, S. (1983). *The Mathematical Theory of Black Holes*

##  Troubleshooting

### App won't launch
- Ensure macOS 11.0+
- Check that all dependencies are installed
- Try rebuilding: `cmake --build . --config Debug --clean-first`

### Low frame rate
- Normal: 9-10 FPS at 1280×720 is expected
- For faster performance: Close other GPU-intensive apps
- Consider a Mac with discrete GPU for better performance

### Sliders not responding
- Make sure the app window is focused
- Try clicking the slider before dragging
- Restart the app if controls become unresponsive

### Disk not visible
- Check that "Disk Enabled" is checked
- Ensure Disk Radius > Black Hole Size
- Try increasing Disk Radius slider
- Adjust Camera Distance for better viewing angle

##  What to Try First

1. **Launch the app** - See the default Gargantua-style black hole
2. **Move Gravity slider** - Watch the light bending change
3. **Adjust Camera Distance** - Move closer to see more lensing
4. **Enable Orbiting Star** - Watch a star orbit with gravitational redshift
5. **Toggle Doppler Effect** - See color shifts from orbital motion
6. **Try RK4 Integration** - Compare accuracy with Verlet method

##  Enjoy!

Black Hole GPU is both a scientific visualization tool and an educational experience. Experiment with the controls, learn about general relativity, and enjoy seeing Einstein's equations come to life in real-time!

For questions, bug reports, or contributions, see [CONTRIBUTING.md](CONTRIBUTING.md).

---

**Happy exploring the universe!**
