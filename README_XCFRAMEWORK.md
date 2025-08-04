# ONNX Runtime XCFramework Build - Quick Start

## ✅ Production Ready Solution

### Build XCFramework with CoreML (Recommended)
```bash
./build-xcframework-ios.sh
```

**What this creates:**
- `build/Release_clean/onnxruntime.xcframework` - Ready for production use
- iOS device (arm64) with CoreML hardware acceleration
- macOS (arm64) with CoreML hardware acceleration
- All necessary headers and module maps included
- Fixed C++ compilation with proper module.modulemap headers

### Clean Build Artifacts (When Needed)
```bash
# Interactive cleaning
./clean-build.sh

# Clean everything
./clean-build.sh --all

# Clean specific platforms
./clean-build.sh --ios
./clean-build.sh --macos
```

## Key Features

- ✅ **Tested and Working** - Successfully builds with CoreML acceleration
- ✅ **Production Ready** - Used in real applications
- ✅ **Time Efficient** - Preserves successful builds, only rebuilds what's needed
- ✅ **Hardware Acceleration** - CoreML on both iOS device and macOS
- ✅ **Clean Architecture** - arm64 only, no legacy x86_64 complexity
- ✅ **Modular Design** - Refactored for better maintainability and code reuse
- ✅ **C++ Header Fix** - Resolved 'cmath' file not found compilation errors

## File Structure

```
├── build-xcframework-ios.sh              # ✅ Main build script (RECOMMENDED)
├── create-xcframework-from-existing-builds.sh # ✅ XCFramework packaging utility
├── clean-build.sh                        # ✅ Selective cleaning utility
├── build-xcframework-ios-original.sh     # 📋 Original script backup
├── BUILD_XCFRAMEWORK_README.md           # 📖 Complete documentation
├── legacy_scripts/                       # 🗂️ Historical scripts (reference only)
└── build/                                # 📁 Build outputs (created during build)
```

## Quick Integration

1. **Build the framework:**
   ```bash
   ./build-xcframework-ios.sh
   ```

2. **Integration options:**
   
   **Option A: Swift Package (Recommended)**
   - XCFramework automatically used by `onnxruntime_swift` package
   - Run sync script to update headers: `cd ../onnxruntime_swift && ./sync_objc_files.sh`
   
   **Option B: Direct Xcode integration**
   - Drag `build/Release_clean/onnxruntime.xcframework` to your project
   - Add to "Frameworks, Libraries, and Embedded Content"
   - Set to "Do Not Embed" (static library)

3. **Use in code:**
   ```swift
   // Swift (via onnxruntime_swift package)
   import onnxruntime_swift
   
   let session = try ORTSession.create(
       env: env,
       modelPath: modelPath,
       useCoreML: true  // Automatic CoreML acceleration
   )
   ```
   
   ```cpp
   // C++ (direct integration)
   #include <onnxruntime/onnxruntime_cxx_api.h>
   #include <onnxruntime/coreml_provider_factory.h>
   
   // Enable CoreML acceleration
   OrtSessionOptionsAppendExecutionProvider_CoreML(session_options, 0);
   ```

## Need More Details?

See [BUILD_XCFRAMEWORK_README.md](BUILD_XCFRAMEWORK_README.md) for complete documentation including:
- Prerequisites and installation
- Advanced configuration options
- Troubleshooting guide
- Custom operators configuration
- Integration examples

---

**🎉 Congratulations!** You now have a production-ready ONNX Runtime XCFramework with CoreML acceleration for iOS and macOS.