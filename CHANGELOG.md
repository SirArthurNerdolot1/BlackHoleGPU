# Changelog

All notable changes to Black Hole GPU will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-01-XX

### Added
- Initial release of Black Hole GPU Ray Tracer
- Real-time GPU-accelerated black hole visualization using Metal compute shaders
- Scientifically accurate Schwarzschild geodesic integration
- Two integration methods: Verlet (2nd order) and Runge-Kutta 4th order
- Interactive accretion disk with procedural turbulence
- Gravitational lensing effects
- Gravitational redshift calculations
- Doppler shifting for orbital motion
- Relativistic beaming effects
- Blackbody radiation rendering (1000K-40000K temperature range)
- Orbiting star with proper gravitational redshift
- Background star redshift and Doppler effects
- Observer position and velocity controls
- ImGui-based interactive parameter controls
- macOS native Metal implementation
- GLFW cross-platform windowing
- Comprehensive documentation and code comments

### Features
- **5 Core Interactive Sliders:**
  - Gravity strength (0.1 - 10.0)
  - Accretion disk radius (1.0 - 20.0 Schwarzschild radii)
  - Disk thickness (0.01 - 2.0)
  - Black hole size (0.01 - 1.0)
  - Camera distance (3.0 - 20.0)

- **Advanced Physics Parameters:**
  - Integration method selection (Verlet/RK4)
  - Toggle disk rendering
  - Toggle Doppler shift effects
  - Toggle gravitational redshift
  - Toggle relativistic beaming
  - Realistic temperature profiles
  - Accretion temperature control (1000K - 40000K)

- **Observer Controls:**
  - 3D position adjustment
  - 3D velocity for relativistic effects

- **Orbiting Star:**
  - Toggle visibility
  - Orbit radius control (3.0 - 15.0)
  - Orbit speed control (0.1 - 2.0 rad/s)
  - Brightness adjustment

- **Background Effects:**
  - Gravitational redshift of distant stars
  - Doppler shift of distant stars

### Performance
- Typical frame rate: 9-10 FPS at 1280×720 on integrated GPU
- 512 ray marching iterations per pixel
- Compute-bound performance scales with resolution

### Technical Details
- Built with CMake 3.20+
- Requires macOS 11.0+ (Big Sur or later)
- Uses Metal API for GPU acceleration
- C++17 standard
- Objective-C++ for Metal bridge
- Dependencies: GLFW 3.x, ImGui, GLM, metal-cpp

### Credits
- Original physics implementation: [BlackHoleRayTracer](https://github.com/hydrogendeuteride/BlackHoleRayTracer)
- Based on Schwarzschild metric and general relativity
- Inspired by Interstellar's Gargantua visualization

## [Unreleased]

### Planned Features
- Kerr (rotating) black hole support
- Accretion disk emission profiles
- Time dilation visualization
- Camera path animation
- Export rendered frames
- Performance optimizations
- Multi-GPU support

---

## Version History

### Version Numbering
- **Major version**: Breaking changes or complete rewrites
- **Minor version**: New features, backward compatible
- **Patch version**: Bug fixes and minor improvements

### Release Tags
All releases are tagged in Git with the format `v1.0.0`

### Contributing
See [README.md](README.md) for contribution guidelines.
