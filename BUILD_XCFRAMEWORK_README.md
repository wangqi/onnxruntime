# Building ONNX Runtime XCFramework for iOS and macOS

This directory contains scripts to build ONNX Runtime as an XCFramework for Apple platforms.

## Prerequisites

- macOS with Xcode installed
- Xcode Command Line Tools (`xcode-select --install`)
- CMake 3.28.0 or later (`brew install cmake`)
- Python 3 (`brew install python3`)
- jq (for custom build script) (`brew install jq`)

### Installing/Updating CMake

ONNX Runtime requires CMake 3.28.0 or later. To check your version:
```bash
cmake --version
```

If you need to update:
```bash
# Using Homebrew (recommended)
brew update
brew upgrade cmake

# Or download directly from cmake.org
# https://cmake.org/download/
```

## Build Scripts

### 1. build-xcframework-ios.sh (Recommended - Production Ready)

**✅ TESTED AND WORKING** - This script successfully builds ONNX Runtime with CoreML acceleration:

```bash
# Build with default Release configuration
./build-xcframework-ios.sh

# Build with specific configuration
./build-xcframework-ios.sh Debug
```

**Features:**
- ✅ **iOS device with CoreML** - Full hardware acceleration on real devices
- ✅ **macOS with CoreML** - Hardware acceleration on Mac (with CPU fallback if needed)
- ✅ **Production ready** - Tested and proven to work
- ✅ **Time efficient** - Preserves successful builds, only rebuilds what's needed
- ✅ **Official approach** - Uses the same methods as ONNX Runtime documentation
- ✅ **Modular design** - Delegates XCFramework creation to `create-xcframework-from-existing-builds.sh`
- ✅ **Fixed headers** - Includes all required headers (`onnxruntime_float16.h`, `onnxruntime_ep_c_api.h`) in module.modulemap

**Output:** Creates `build/{CONFIG}_clean/onnxruntime.xcframework` ready for production use.

**This is the recommended script for all production applications.**

**Note:** This script has been refactored to use `create-xcframework-from-existing-builds.sh` for XCFramework creation, eliminating code duplication and ensuring consistent framework packaging. The original script is preserved as `build-xcframework-ios-original.sh`.

### 2. create-xcframework-from-existing-builds.sh (XCFramework Packaging)

**✅ CORE UTILITY** - This script packages existing builds into an XCFramework:

```bash
# Create XCFramework from Release builds
./create-xcframework-from-existing-builds.sh Release

# Create XCFramework from Debug builds  
./create-xcframework-from-existing-builds.sh Debug
```

**Features:**
- ✅ **Dedicated packaging** - Focuses solely on XCFramework creation from existing binaries
- ✅ **Proper module.modulemap** - Includes all required headers for C++ compilation
- ✅ **Header verification** - Ensures `onnxruntime_float16.h` and `onnxruntime_ep_c_api.h` are included
- ✅ **Platform support** - Handles iOS device, iOS simulator, and macOS frameworks
- ✅ **Reusable** - Can be called independently or from other build scripts

**This script is automatically called by `build-xcframework-ios.sh` but can also be used standalone to repackage existing builds.**

**Swift Package Integration:** The created XCFramework is automatically used by the `onnxruntime_swift` package. After building, run the sync script to update package headers:
```bash
cd ../onnxruntime_swift && ./sync_objc_files.sh
```

### 3. clean-build.sh (Cleaning Utility)

**✅ ESSENTIAL UTILITY** - Use this to selectively clean build artifacts:

```bash
# Interactive mode
./clean-build.sh

# Clean everything  
./clean-build.sh --all

# Clean specific platforms
./clean-build.sh --ios
./clean-build.sh --macos
```

See the [Cleaning Build Artifacts](#cleaning-build-artifacts) section for full details.

## Cleaning Build Artifacts

### clean-build.sh

Since builds take a long time (10-30 minutes), the build scripts no longer automatically clean previous builds. Use this dedicated script to clean selectively:

```bash
# Interactive mode - choose what to clean
./clean-build.sh

# Clean everything
./clean-build.sh --all

# Clean only iOS builds  
./clean-build.sh --ios

# Clean only macOS builds
./clean-build.sh --macos

# Clean only framework outputs
./clean-build.sh --frameworks  

# Clean specific configuration
./clean-build.sh --config Release

# Combine options
./clean-build.sh --ios --config Debug

# Skip confirmation prompts
./clean-build.sh --all --yes
```

**Benefits:**
- **Selective cleaning** - Only clean what you need to rebuild
- **Time savings** - Keep successful builds, only rebuild what failed
- **Interactive mode** - Easy to use with menu-driven selection
- **Safe defaults** - Always asks for confirmation unless `--yes` is used

## Build Output

After a successful build with `build-xcframework-ios.sh`, you'll find:

- **✅ Ready-to-use XCFramework**: `build/{BUILD_CONFIG}_clean/onnxruntime.xcframework`
  - Example: `build/Release_clean/onnxruntime.xcframework`
- **Intermediate files**: `build/{BUILD_CONFIG}_clean/frameworks/`
- **Individual platform builds**: 
  - `build/{BUILD_CONFIG}_clean/ios_device/` - iOS device build
  - `build/{BUILD_CONFIG}_clean/macos_coreml/` or `build/{BUILD_CONFIG}_clean/macos_cpu/` - macOS build

The XCFramework contains:
- **iOS device (arm64)** - With CoreML hardware acceleration
- **macOS (arm64)** - With CoreML hardware acceleration (or CPU fallback)
- **Headers** - All necessary ONNX Runtime headers including CoreML provider
- **Module maps** - For Swift interoperability

## Using the Framework

1. **Swift Package Integration (Recommended)**:
   ```swift
   // Import the Swift package
   import onnxruntime_swift
   
   // Create environment and session with CoreML
   let env = try ORTEnv.create(logLevel: .warning)
   let session = try ORTSession.create(
       env: env,
       modelPath: modelPath,
       useCoreML: true  // Automatic CoreML on device, CPU on simulator
   )
   
   // Run inference with Swift-native error handling
   let results = try session.run(inputs: inputs)
   ```

2. **Direct Xcode Integration**:
   - Drag `onnxruntime.xcframework` into your Xcode project
   - Add to "Frameworks, Libraries, and Embedded Content"
   - For static framework: Set "Do Not Embed"
   - For dynamic framework: Set "Embed & Sign"

3. **C++ Usage**:
   ```cpp
   #include <onnxruntime/onnxruntime_cxx_api.h>
   
   // CoreML provider - only available on iOS device and macOS, not iOS simulator
   #if !TARGET_OS_SIMULATOR
   #include <onnxruntime/coreml_provider_factory.h>
   #endif
   ```

4. **Objective-C Usage**:
   ```objc
   @import onnxruntime;
   ```

5. **CoreML Provider Usage**:
   ```cpp
   // Only use CoreML on actual devices and macOS
   #if !TARGET_OS_SIMULATOR
   Ort::SessionOptions session_options;
   OrtSessionOptionsAppendExecutionProvider_CoreML(session_options, 0);
   #endif
   ```

## Custom Operators Configuration

The current recommended script (`build-xcframework-ios.sh`) uses a minimal build with extended operators, which provides a good balance between functionality and binary size.

If you need to further customize which operators are included:

1. Generate ops config from your specific model:
   ```bash
   python3 tools/python/create_reduced_build_config.py your_model.onnx ops.config
   ```

2. Modify the `build-xcframework-ios.sh` script to add:
   ```bash
   --include_ops_by_config ops.config
   ```
   to the build.sh commands for further size optimization.

## Troubleshooting

### Common Issues with the Recommended Script

- **Build fails with CMake error**: 
  - Ensure CMake version is 3.28.0 or later (`cmake --version`)
  - Update with `brew update && brew upgrade cmake`

- **C++ compilation errors like "'cmath' file not found"**:
  - ✅ **This is now fixed** - The scripts include all required headers in module.modulemap
  - Headers `onnxruntime_float16.h` and `onnxruntime_ep_c_api.h` are automatically included
  - If you encounter this with older builds, rebuild using the updated scripts

- **macOS build fails with CoreML**: 
  - ✅ **This is handled automatically** - The script will fall back to CPU-only macOS build
  - No action needed, the build will still succeed

- **"Can't find libonnxruntime.a" error**:
  - Check if the build actually completed successfully
  - Look for error messages in the build output
  - Try cleaning with `./clean-build.sh --all` and rebuilding

- **Xcode integration issues**:
  - Ensure you set the framework to "Do Not Embed" (static library)
  - Make sure the framework is added to both "Link Binary With Libraries" and "Frameworks, Libraries, and Embedded Content"

- **Runtime errors about missing CoreML**:
  - This is normal on iOS simulator - CoreML only works on real devices
  - Use conditional compilation: `#if !TARGET_OS_SIMULATOR`

### Build Time Issues

- **Builds take too long**:
  - Use `./clean-build.sh` to selectively clean only what needs rebuilding
  - The script preserves successful builds automatically

- **Out of disk space**:
  - Use `./clean-build.sh --frameworks` to clean old framework outputs
  - Use `./clean-build.sh --config OldConfig` to clean specific configurations

## Notes

- ✅ **Production Ready**: `build-xcframework-ios.sh` is tested and works reliably
- **Build time**: 10-30 minutes depending on machine and configuration
- **Architecture**: arm64 only (modern Apple devices)
- **Platforms**: iOS device + macOS (no iOS simulator to avoid CoreML issues)
- **CoreML**: Hardware acceleration on both iOS device and macOS
- **Time efficient**: Preserves successful builds, only rebuilds what's needed
- **Official approach**: Based on ONNX Runtime's official build documentation