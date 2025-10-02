# Deployment Checklist

Use this checklist when preparing Black Hole GPU for distribution.

##  Pre-Release Checklist

### Code Quality
- [x] All source files have documentation headers
- [x] All public APIs are documented
- [x] Complex algorithms have explanatory comments
- [x] Physics equations reference scientific papers
- [x] No compiler warnings in Release build
- [x] Code follows consistent style guidelines

### Functionality
- [x] All 5 core sliders work correctly
- [x] Observer controls functional
- [x] Orbiting star renders properly
- [x] Background effects toggle correctly
- [x] Integration methods (Verlet/RK4) both work
- [x] Accretion disk renders at various parameter values
- [x] Gravitational lensing visible
- [x] App launches without errors

### Documentation
- [x] README.md is comprehensive and up-to-date
- [x] QUICKSTART.md provides easy onboarding
- [x] CONTRIBUTING.md has clear guidelines
- [x] CHANGELOG.md documents version history
- [x] LICENSE file is present and correct
- [x] CONTRIBUTORS.md acknowledges contributors
- [x] Code comments are accurate and helpful

### Build System
- [x] CMakeLists.txt builds successfully
- [x] Xcode project generation works
- [x] Info.plist has correct metadata
- [x] Version numbers are consistent
- [x] Metal shaders compile without warnings
- [x] All dependencies are included

##  Release Preparation

### Version Management
- [ ] Update version in CMakeLists.txt
- [ ] Update version in Info.plist.in
- [ ] Update CHANGELOG.md with release notes
- [ ] Tag release in git: `git tag v1.0.0`

### Testing
- [ ] Test on macOS 11.0 (minimum version)
- [ ] Test on macOS 12.0+
- [ ] Test on macOS 13.0+ (Ventura)
- [ ] Test on macOS 14.0+ (Sonoma)
- [ ] Test on Intel Mac
- [ ] Test on Apple Silicon (M1/M2/M3)
- [ ] Test with integrated GPU
- [ ] Test with discrete GPU
- [ ] Verify all sliders in full range
- [ ] Test extreme parameter combinations
- [ ] Check for memory leaks with Instruments
- [ ] Profile GPU performance

### App Bundle
- [ ] App icon created (.icns file)
  - [ ] 16×16 pixels
  - [ ] 32×32 pixels
  - [ ] 64×64 pixels
  - [ ] 128×128 pixels
  - [ ] 256×256 pixels
  - [ ] 512×512 pixels
  - [ ] 1024×1024 pixels
- [ ] Icon set in Info.plist: `CFBundleIconFile`
- [ ] Bundle identifier unique: `com.blackholegpu.raytracer`
- [ ] Display name set: "Black Hole Ray Tracer"
- [ ] Copyright notice present
- [ ] Category set: Education
- [ ] Minimum system version specified

### Code Signing (Optional for public distribution)
- [ ] Apple Developer account active
- [ ] Developer ID Application certificate obtained
- [ ] Enable hardened runtime
- [ ] Sign app bundle: `codesign --force --deep --sign "Developer ID Application: Your Name" BlackHole.app`
- [ ] Verify signature: `codesign --verify --deep --strict BlackHole.app`
- [ ] Check entitlements: `codesign -d --entitlements :- BlackHole.app`

### Notarization (Required for Gatekeeper)
- [ ] Upload for notarization: `xcrun notarytool submit BlackHole.app.zip`
- [ ] Wait for notarization approval
- [ ] Staple ticket: `xcrun stapler staple BlackHole.app`
- [ ] Verify stapling: `xcrun stapler validate BlackHole.app`

## Distribution Package

### DMG Creation
```bash
# Create a distributable disk image
hdiutil create -volname "Black Hole GPU" \
               -srcfolder BlackHole.app \
               -ov -format UDZO \
               BlackHoleGPU-1.0.0.dmg
```

- [ ] DMG created with proper volume name
- [ ] DMG opens with Applications folder symlink
- [ ] Background image designed (optional)
- [ ] Window size and position set
- [ ] Icon positions arranged
- [ ] DMG is compressed (UDZO format)
- [ ] Test DMG on clean system

### Release Package Contents
- [ ] `BlackHoleGPU-1.0.0.dmg` (app installer)
- [ ] `BlackHoleGPU-1.0.0-src.zip` (source code)
- [ ] `RELEASE_NOTES.md` (version highlights)
- [ ] `SHA256SUMS` (checksums for verification)

### GitHub Release
- [ ] Create release tag: `v1.0.0`
- [ ] Write release notes
- [ ] Upload DMG file
- [ ] Upload source ZIP
- [ ] Upload checksums
- [ ] Mark as stable release
- [ ] Set release as latest

##  Announcement

### Release Notes Template
```markdown
# Black Hole GPU v1.0.0

**Release Date**: January XX, 2025

##  Highlights
- Real-time GPU-accelerated black hole visualization
- Scientifically accurate Schwarzschild geodesics
- Interactive controls for all physical parameters
- Advanced relativistic effects

##  Features
- 5 core interactive sliders
- Observer position and velocity controls
- Orbiting star with gravitational redshift
- Background star redshift and Doppler effects
- RK4 and Verlet integration methods

##  Performance
- 9-10 FPS at 1280×720 on integrated GPU
- Optimized Metal compute shaders
- 512 ray marching iterations per pixel

##  Requirements
- macOS 11.0 (Big Sur) or later
- Metal-capable GPU

##  Download
[Download BlackHoleGPU-1.0.0.dmg](link)

##  Known Issues
- None at this time

##  Credits
Based on [BlackHoleRayTracer](https://github.com/hydrogendeuteride/BlackHoleRayTracer)
```

### Social Media
- [ ] Tweet release announcement
- [ ] Post to Reddit (r/Physics, r/Astronomy, r/programming)
- [ ] Share on Hacker News
- [ ] Post to relevant Discord servers
- [ ] Update personal website/portfolio

### Documentation Sites
- [ ] Update project website
- [ ] Submit to macOS app directories
- [ ] Add to educational resource lists
- [ ] Submit to physics simulation databases

##  Post-Release

### Monitoring
- [ ] Monitor for bug reports
- [ ] Track download statistics
- [ ] Collect user feedback
- [ ] Review performance metrics
- [ ] Check crash reports (if analytics enabled)

### Support
- [ ] Respond to GitHub issues promptly
- [ ] Update FAQ based on common questions
- [ ] Create video tutorials if requested
- [ ] Maintain discussion forum

### Maintenance
- [ ] Plan patch releases for bugs
- [ ] Roadmap for version 1.1.0
- [ ] Keep dependencies updated
- [ ] Monitor macOS version compatibility

## Version-Specific Notes

### Version 1.0.0
- Initial production release
- All core features complete
- Comprehensive documentation
- Professional packaging

---

## Quick Commands Reference

### Build Release Version
```bash
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release
```

### Create Source Distribution
```bash
git archive --format=zip --output=BlackHoleGPU-1.0.0-src.zip v1.0.0
```

### Generate Checksums
```bash
shasum -a 256 BlackHoleGPU-1.0.0.dmg > SHA256SUMS
shasum -a 256 BlackHoleGPU-1.0.0-src.zip >> SHA256SUMS
```

### Code Sign
```bash
codesign --force --deep --sign "Developer ID Application" BlackHole.app
```

### Verify App
```bash
codesign --verify --deep --strict BlackHole.app
spctl -a -v BlackHole.app
```

---

**Remember**: Quality over speed. Take time to test thoroughly before release!
