# Quick Start Guide

Welcome to **Black Hole GPU** - a real-time black hole ray tracer with scientifically accurate physics and modern performance optimization!

## Getting Started in 5 Minutes

### Prerequisites
- macOS 11.0 (Big Sur) or later
- Xcode or Xcode Command Line Tools
- CMake 3.15+ (install via Homebrew: `brew install cmake`)

### Build & Run
```bash
# 1. Clone the repository
git clone https://github.com/SirArthurNerdolot1/BlackHoleGPU.git
cd BlackHoleGPU

# 2. Build with CMake
mkdir build && cd build
cmake ..
cmake --build . --config Debug

# 3. Launch the app
open Debug/BlackHole.app
```

**Or use the automated installer:**
```bash
./install.sh
```

That's it! You should see a black hole with an accretion disk rendering in real-time.

## Modern Interface Overview

The app now features a clean, tabbed interface with organized controls:

### Performance Display (Top)
- **FPS Counter**: Real-time frames per second (green text)
- **Frame Time**: Milliseconds per frame
- **Quality Preset Dropdown**: Quick performance/quality selection

### Tab Organization

#### Physics Tab
Core physical parameters and preset configurations:

| Parameter | Range | Default | Effect |
|-----------|-------|---------|--------|
| **Gravity Strength** | 0.1 - 10.0 | 2.5 | Gravitational field strength (light bending intensity) |
| **Disk Radius** | 1.0 - 20.0 Rs | 5.0 | Accretion disk outer edge (Schwarzschild radii) |
| **Disk Thickness** | 0.01 - 2.0 | 0.2 | Vertical extent of the disk |
| **Event Horizon Size** | 0.01 - 1.0 | 0.12 | Schwarzschild radius (point of no return) |

**Quick Preset Buttons:**
- **Gargantua (Interstellar)**: Movie-accurate black hole
- **Extreme Gravity**: Maximum light bending (gravity=8.0)
- **Thin Disk**: Minimal thickness for clean visuals

#### Visual Tab
Rendering quality and relativistic effects:

| Parameter | Type | Effect |
|-----------|------|--------|
| **Background Redshift** | Toggle | Gravitational frequency shift of stars |
| **Background Doppler** | Toggle | Motion-based color shifts |
| **Show Orbiting Star** | Toggle | Display orbiting point source |
| **Star Orbit Radius** | 3.0 - 15.0 | Distance from black hole |
| **Star Orbit Speed** | 0.1 - 2.0 | Angular velocity (rad/s) |
| **Star Brightness** | 0.1 - 3.0 | Luminosity multiplier |
| **Max Iterations** | 64 - 1024 | Ray marching steps (quality vs speed) |
| **Step Size** | 0.05 - 0.2 | Integration precision |
| **Adaptive Stepping** | Toggle | Auto-adjust near event horizon |

#### Camera Tab
Observer position and viewing angle:

| Parameter | Range | Default | Effect |
|-----------|-------|---------|--------|
| **Distance from Black Hole** | 3.0 - 20.0 | 8.0 | Orbital radius |
| **Observer Position X** | -10.0 - 10.0 | 0.0 | Horizontal offset |
| **Observer Position Y** | -10.0 - 10.0 | 0.0 | Vertical offset (viewing angle!) |
| **Observer Position Z** | -10.0 - 10.0 | 8.0 | Distance along view axis |
| **Observer Velocity** | -0.5 - 0.5 | (0,0,0) | For Doppler calculations |

**Reset Button**: Instantly restore default camera position

#### Recording Tab
Screen capture and video recording:

- **macOS Screen Recording**: Cmd+Shift+5 instructions
- **QuickTime Recording**: Built-in screen capture guide
- **Screenshot Shortcuts**: Cmd+Shift+4 quick reference
- **Built-in Recording**: Coming soon (Metal texture capture)

## Quality Presets Explained

Choose the right preset for your hardware and use case:

| Preset | Iterations | Step Size | Adaptive | FPS (M1) | FPS (Intel) | Best For |
|--------|-----------|-----------|----------|----------|-------------|----------|
| **Low** | 128 | 0.15 | No | 30-60 | 15-25 | Real-time interaction, older hardware |
| **Medium** | 192 | 0.12 | Yes | 20-30 | 12-18 | Balanced quality/performance |
| **High** | 256 | 0.10 | Yes | 12-20 | 8-12 | **Recommended default** |
| **Ultra** | 512 | 0.08 | Yes | 8-15 | 4-8 | Screenshots, videos, maximum quality |

### Hardware Recommendations

**Apple Silicon (M1/M2/M3/M4)**:
- Daily use: **High** preset
- Screenshots: **Ultra** preset
- Experimenting: **Medium** preset

**Intel Mac (Discrete GPU)**:
- Daily use: **Medium** preset
- Screenshots: **High** preset
- Real-time: **Low** preset

**Intel Mac (Integrated GPU)**:
- Daily use: **Low** preset
- Screenshots: **Medium** preset (be patient!)

## Advanced Features

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

## Tips & Tricks

### Best Visual Results
1. Start with the Gargantua preset
2. Enable all relativistic effects
3. Set realistic temperature to ON
4. Adjust camera distance to 6-10 for dramatic lensing

### Performance Optimization
- Use quality presets appropriate for your hardware
- Lower iterations for real-time interaction
- Enable adaptive stepping for better performance near event horizon
- Monitor FPS counter to maintain smooth experience

### Understanding the Physics
- **Einstein Ring**: When camera, black hole, and disk align
- **Gravitational Lensing**: Light bends around the black hole
- **Photon Sphere**: At r=1.5Rs, light can orbit the black hole
- **Event Horizon**: At r=1.0Rs (Schwarzschild radius), nothing can escape

### Experimentation
- Try Gravity = 10.0 and Camera Distance = 3.5 for extreme lensing
- Set Disk Thickness = 0.01 for a razor-thin disk
- Enable orbiting star and watch gravitational redshift effects
- Adjust observer position Y for different viewing angles

## Learn More

### Documentation
- **README.md**: Full feature list and build instructions
- **CONTRIBUTING.md**: How to contribute code or bug reports
- **CHANGELOG.md**: Version history and planned features
- **FEATURES_V2.md**: Detailed feature documentation

### Physics Background
The simulation implements:
- **Schwarzschild Metric**: For non-rotating black holes
- **Geodesic Integration**: Ray tracing in curved spacetime
- **Accretion Disk Model**: Geometrically thin, optically thick
- **RK4 Integration**: 4th-order Runge-Kutta for accuracy

### References
- Schwarzschild, K. (1916). *On the Gravitational Field of a Mass Point*
- James et al. (2015). *Gravitational lensing by spinning black holes in astrophysics, and in the movie Interstellar*
- Chandrasekhar, S. (1983). *The Mathematical Theory of Black Holes*

## Troubleshooting

### App won't launch
- Ensure macOS 11.0+
- Check that all dependencies are installed
- Try rebuilding: `cmake --build build --config Debug --clean-first`

### Low frame rate
- Use a lower quality preset (Low or Medium)
- Reduce max iterations in Visual tab
- Disable adaptive stepping for slight performance boost
- Consider using a Mac with discrete GPU

### Sliders not responding
- Make sure the app window is focused
- Try clicking the slider before dragging
- Restart the app if controls become unresponsive

### Disk not visible
- Check that Disk Radius > Event Horizon Size
- Try increasing Disk Radius slider
- Adjust Camera Distance for better viewing angle
- Ensure disk thickness is not too small (<0.01)

## What to Try First

1. **Launch the app** - See the default Gargantua-style black hole
2. **Adjust Quality Preset** - Find the right balance for your hardware
3. **Move Gravity slider** - Watch the light bending change
4. **Adjust Camera Distance** - Move closer to see more lensing
5. **Enable Orbiting Star** - Watch a star orbit with gravitational redshift
6. **Toggle Doppler Effect** - See color shifts from orbital motion
7. **Try Different Presets** - Explore Gargantua, Extreme Gravity, and Thin Disk

## Conclusion

Black Hole GPU is both a scientific visualization tool and an educational experience. Experiment with the controls, learn about general relativity, and enjoy seeing Einstein's equations come to life in real-time!

For questions, bug reports, or contributions, see [CONTRIBUTING.md](CONTRIBUTING.md).

---

**Happy exploring the universe!**
