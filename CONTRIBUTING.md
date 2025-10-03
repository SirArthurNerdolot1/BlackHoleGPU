# Contributing to Black Hole GPU

Thank you for your interest in contributing to Black Hole GPU! This document provides guidelines for contributing to the project.

## Code of Conduct

- Be respectful and constructive
- Focus on scientific accuracy and code quality
- Help others learn and grow

## Getting Started

1. **Fork the repository**
   ```bash
   git https://github.com/SirArthurNerdolot1/BlackHoleGPU.git
   cd BlackHoleGPU
   ```

2. **Set up your development environment**
   - macOS 11.0+ (Big Sur or later)
   - Xcode with Command Line Tools
   - CMake 3.15+
   - See [README.md](README.md) for detailed setup instructions

3. **Build and test**
   ```bash
   mkdir build && cd build
   cmake ..
   cmake --build . --config Debug
   ```

## Development Workflow

### Branch Naming
- `feature/description` - New features
- `bugfix/description` - Bug fixes
- `docs/description` - Documentation updates
- `perf/description` - Performance improvements

### Making Changes

1. **Create a new branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**
   - Write clear, well-documented code
   - Follow existing code style
   - Add comments for complex physics or algorithms
   - Update documentation as needed

3. **Test thoroughly**
   - Build in both Debug and Release configurations
   - Test all interactive sliders and controls
   - Verify visual output matches scientific expectations
   - Check for memory leaks with Instruments

4. **Commit with clear messages**
   ```bash
   git commit -m "Add feature: description of what you added"
   ```

## Code Style Guidelines

### C++/Objective-C++
- Follow existing naming conventions
- Use meaningful variable names (physics variables can use standard notation like `r`, `theta`, `phi`)
- Add header comments to all source files
- Document all public methods and complex functions
- Use C++17 features appropriately

### Metal Shaders
- Organize code into logical sections with comment headers
- Document all major functions with purpose and parameters
- Explain physics equations with references when applicable
- Use descriptive function and variable names
- Comment any non-obvious optimizations

### Comments
- **Good**: Explain *why*, not *what*
  ```cpp
  // Use RK4 for better accuracy near event horizon where curvature is extreme
  if (uniforms.integration_method == 1) {
      rk4(pos, vel, h2, time, uniforms);
  }
  ```
- **Bad**: Obvious statements
  ```cpp
  // Increment i by 1
  i++;
  ```

## Areas for Contribution

### High Priority
- **Performance Optimizations**: GPU compute shader optimizations, parallel processing
- **Kerr Black Holes**: Add support for rotating black holes with frame dragging
- **Unit Tests**: Add automated testing for physics calculations
- **Cross-platform Support**: Port to other platforms (Linux/Vulkan, Windows/DX12)

### Medium Priority
- **Advanced Physics**: 
  - Multiple black holes (binary systems)
  - Time dilation visualization
  - Gravitational wave effects
- **Rendering Enhancements**:
  - Better accretion disk models
  - Volume rendering for gas clouds
  - Bloom and HDR rendering
- **User Experience**:
  - Camera path animation
  - Preset configurations
  - Save/load settings
  - Export video frames

### Documentation
- Improve physics explanations
- Add tutorials for new contributors
- Create example configurations
- Write technical blog posts about implementation

## Physics Contributions

When contributing physics-related changes:

1. **Provide references**
   - Cite peer-reviewed papers
   - Link to textbooks or authoritative sources
   - Explain the physical basis

2. **Validate scientifically**
   - Compare with known analytical solutions where possible
   - Test limiting cases (e.g., Newtonian limit at large distances)
   - Verify units and dimensional analysis

3. **Document thoroughly**
   - Explain equations in comments
   - Provide intuitive descriptions
   - Note any approximations or assumptions

## Pull Request Process

1. **Before submitting**
   - Ensure code builds without warnings
   - Test all affected features
   - Update documentation
   - Add yourself to CONTRIBUTORS.md

2. **PR Description should include**
   - Clear description of changes
   - Motivation and context
   - Screenshots/videos for visual changes
   - References for physics changes
   - Breaking changes (if any)

3. **Review process**
   - Address reviewer feedback promptly
   - Keep discussions focused and constructive
   - Be patient - thorough review takes time

4. **After merge**
   - Delete your feature branch
   - Celebrate!

## Reporting Bugs

### Before Reporting
- Check existing issues
- Verify it's reproducible
- Test with latest version

### Bug Report Should Include
- macOS version and hardware (GPU model)
- Steps to reproduce
- Expected vs actual behavior
- Screenshots or recordings
- Console output if applicable
- Parameter values that trigger the bug

### Example Bug Report
```markdown
**Bug**: Accretion disk disappears at certain camera distances

**Environment**:
- macOS 14.2 Sonoma
- MacBook Pro M4 Pro
- Build: Debug configuration

**Steps to Reproduce**:
1. Launch app
2. Set Camera Distance slider to 15.0
3. Set Disk Radius to 20.0

**Expected**: Disk should be visible
**Actual**: Disk is not rendered

**Screenshots**: [attach image]
```

## Feature Requests

Feature requests are welcome! Please include:
- Clear description of desired feature
- Use case and motivation
- Optional: Implementation ideas
- Optional: Willingness to contribute code

## Questions?

- Open an issue with the `question` label
- Be specific about what you're trying to understand
- Share relevant code snippets or context

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

## Recognition

Contributors will be acknowledged in:
- CONTRIBUTORS.md file
- Project README
- Release notes for significant contributions

Thank you for making Black Hole GPU better! 
