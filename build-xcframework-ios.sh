#!/bin/bash
#
# Clean ONNX Runtime xcframework build script
# Based on the proven official build.sh approach with CoreML
#
# Builds for:
# - iOS device (arm64) with CoreML
# - macOS (arm64) with CoreML
# (iOS simulator dropped for simplicity and to avoid CoreML issues)
#
# Usage: ./build-xcframework-ios.sh [Release|Debug|RelWithDebInfo|MinSizeRel]
#        Default: Release

set -e

# Options
IOS_MIN_OS_VERSION=16.4
MACOS_MIN_OS_VERSION=13.3

# Parse command line arguments
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "Usage: $0 [Release|Debug|RelWithDebInfo|MinSizeRel]"
    echo ""
    echo "Build ONNX Runtime XCFramework with CoreML for iOS device and macOS"
    echo ""
    echo "Options:"
    echo "  Release         Optimized build (default)"
    echo "  Debug           Debug build"  
    echo "  RelWithDebInfo  Release with debug info"
    echo "  MinSizeRel      Minimal size build"
    echo ""
    echo "Features:"
    echo "- iOS device with CoreML hardware acceleration" 
    echo "- macOS with CoreML (or CPU fallback if CoreML fails)"
    echo "- Preserves previous builds to save time"
    echo ""
    echo "To clean previous builds:"
    echo "  ./clean-build.sh --help    # See cleaning options"
    echo "  ./clean-build.sh --all     # Clean everything"
    echo "  ./clean-build.sh --ios     # Clean iOS builds only"
    echo ""
    echo "Note: iOS simulator is not included to ensure CoreML works properly"
    exit 0
fi

BUILD_CONFIG="${1:-Release}"

case "$BUILD_CONFIG" in
    Release|Debug|RelWithDebInfo|MinSizeRel)
        ;;
    *)
        echo "Error: Invalid build configuration '$BUILD_CONFIG'"
        exit 1
        ;;
esac

# Get directory this script is in
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Building ONNX Runtime XCFramework with CoreML${NC}"
echo "Build configuration: $BUILD_CONFIG"
echo "iOS minimum version: $IOS_MIN_OS_VERSION" 
echo "macOS minimum version: $MACOS_MIN_OS_VERSION"
echo "Platforms: iOS device + iOS simulator + macOS"

# Note: Not cleaning previous builds automatically to save time
# Use ./clean-build.sh if you need to clean specific platforms or configurations
echo -e "${YELLOW}Building (use ./clean-build.sh to clean if needed)...${NC}"

# Build for iOS Device (arm64) with CoreML (static libraries)
echo -e "\n${GREEN}Building for iOS Device (arm64) with CoreML...${NC}"
./build.sh \
    --config "$BUILD_CONFIG" \
    --use_xcode \
    --ios \
    --apple_sysroot iphoneos \
    --osx_arch arm64 \
    --apple_deploy_target "$IOS_MIN_OS_VERSION" \
    --use_coreml \
    --skip_tests \
    --build_dir "build/${BUILD_CONFIG}/ios_device"

if [ $? -ne 0 ]; then
    echo -e "${RED}iOS device build failed${NC}"
    exit 1
fi

# Build for iOS Simulator arm64 without CoreML (static libraries)
echo -e "\n${GREEN}Building for iOS Simulator arm64 without CoreML...${NC}"
./build.sh \
    --config "$BUILD_CONFIG" \
    --use_xcode \
    --ios \
    --apple_sysroot iphonesimulator \
    --osx_arch arm64 \
    --apple_deploy_target "$IOS_MIN_OS_VERSION" \
    --skip_tests \
    --build_dir "build/${BUILD_CONFIG}/ios_simulator"

if [ $? -ne 0 ]; then
    echo -e "${RED}iOS simulator build failed${NC}"
    exit 1
fi

# Build for macOS (arm64) with CoreML  
echo -e "\n${GREEN}Building for macOS (arm64) with CoreML...${NC}"

# First try with CoreML
echo -e "${YELLOW}Attempting macOS build with CoreML...${NC}"
if ./build.sh \
    --config "$BUILD_CONFIG" \
    --build_shared_lib \
    --parallel \
    --compile_no_warning_as_error \
    --skip_submodule_sync \
    --cmake_extra_defines CMAKE_OSX_ARCHITECTURES=arm64 \
    --use_coreml \
    --skip_tests \
    --build_dir "build/${BUILD_CONFIG}/macos_coreml"; then
    
    echo -e "${GREEN}macOS build with CoreML successful${NC}"
    MACOS_BUILD_DIR="build/${BUILD_CONFIG}/macos_coreml"
    MACOS_HAS_COREML=true
    
else
    echo -e "${YELLOW}macOS build with CoreML failed, trying without CoreML...${NC}"
    
    # Clean and try without CoreML
    rm -rf "build/${BUILD_CONFIG}/macos_cpu"
    
    if ./build.sh \
        --config "$BUILD_CONFIG" \
        --build_shared_lib \
        --parallel \
        --compile_no_warning_as_error \
        --skip_submodule_sync \
        --cmake_extra_defines CMAKE_OSX_ARCHITECTURES=arm64 \
        --skip_tests \
        --build_dir "build/${BUILD_CONFIG}/macos_cpu"; then
        
        echo -e "${YELLOW}macOS build without CoreML successful${NC}"
        MACOS_BUILD_DIR="build/${BUILD_CONFIG}/macos_cpu"
        MACOS_HAS_COREML=false
        
    else
        echo -e "${RED}macOS build failed even without CoreML${NC}"
        exit 1
    fi
fi

# Create output directory
OUTPUT_DIR="$SCRIPT_DIR/build/${BUILD_CONFIG}/frameworks"
mkdir -p "$OUTPUT_DIR"

# Function to find the built library
find_library() {
    local build_dir=$1
    local platform_name=$2
    
    echo -e "${YELLOW}Finding library in $build_dir...${NC}"
    
    # Look for the library in common locations
    local lib_path=""
    for search_path in "$build_dir/$BUILD_CONFIG" "$build_dir/$BUILD_CONFIG-iphoneos" "$build_dir" "$build_dir/Release" "$build_dir/Release-iphoneos"; do
        if [ -d "$search_path" ]; then
            # Look for both static and dynamic libraries (including versioned ones)
            lib_path=$(find "$search_path" \( -name "libonnxruntime.a" -o -name "libonnxruntime.dylib" -o -name "libonnxruntime.*.dylib" \) 2>/dev/null | grep -v "\.dSYM" | grep -v "\.tbd" | head -1)
            if [ -n "$lib_path" ]; then
                echo -e "${GREEN}Found $platform_name library: $lib_path${NC}"
                echo "$lib_path"
                return 0
            fi
        fi
    done
    
    echo -e "${RED}Could not find libonnxruntime library for $platform_name${NC}"
    echo "Searched in: $build_dir"
    exit 1
}

# Function to combine static libraries into a dynamic library
combine_static_libraries() {
    local build_dir=$1
    local platform=$2
    local min_version=$3
    local output_lib=$4
    
    echo -e "${YELLOW}Combining static libraries for $platform...${NC}"
    
    # Create temporary directory
    local temp_dir="$build_dir/temp"
    mkdir -p "$temp_dir"
    
    # iOS simulator now only builds arm64 (x86_64 is obsolete)
    if [ "$platform" = "ios-simulator" ]; then
        echo "Creating combined libraries for iOS simulator (arm64 only)..."
        
        # Find all static libraries
        local libs=()
        while IFS= read -r lib; do
            libs+=("$lib")
        done < <(find "$build_dir" -name "libonnxruntime*.a" -o -name "libabsl*.a" -o -name "libre2*.a" -o -name "libprotobuf*.a" | grep -v test | grep -v protoc | sort)
        
        if [ ${#libs[@]} -eq 0 ]; then
            echo -e "${RED}No static libraries found in $build_dir${NC}"
            return 1
        fi
        
        echo "Found ${#libs[@]} static libraries to combine"
        
        # Combine static libraries
        echo "Creating combined static library..."
        libtool -static -o "$temp_dir/combined.a" "${libs[@]}" 2>/dev/null
        
    else
        # For single architecture platforms (iOS device, macOS)
        # Find all static libraries
        local libs=()
        while IFS= read -r lib; do
            libs+=("$lib")
        done < <(find "$build_dir" -name "libonnxruntime*.a" -o -name "libabsl*.a" -o -name "libre2*.a" -o -name "libprotobuf*.a" -o -name "libcoreml_proto.a" | grep -v test | grep -v protoc | sort)
        
        if [ ${#libs[@]} -eq 0 ]; then
            echo -e "${RED}No static libraries found in $build_dir${NC}"
            return 1
        fi
        
        echo "Found ${#libs[@]} static libraries to combine"
        
        # Combine static libraries
        echo "Creating combined static library..."
        libtool -static -o "$temp_dir/combined.a" "${libs[@]}" 2>/dev/null
    fi
    
    if [ ! -f "$temp_dir/combined.a" ]; then
        echo -e "${RED}Failed to create combined static library${NC}"
        return 1
    fi
    
    # Determine SDK and flags based on platform
    local sdk=""
    local arch_flags=""
    local min_version_flag=""
    local install_name=""
    
    case "$platform" in
        "ios")
            sdk="iphoneos"
            arch_flags="-arch arm64"
            min_version_flag="-mios-version-min=$min_version"
            install_name="@rpath/onnxruntime.framework/onnxruntime"
            ;;
        "ios-simulator")
            sdk="iphonesimulator"
            arch_flags="-arch arm64"
            min_version_flag="-mios-simulator-version-min=$min_version"
            install_name="@rpath/onnxruntime.framework/onnxruntime"
            ;;
        "macos")
            sdk="macosx"
            arch_flags="-arch arm64"
            min_version_flag="-mmacosx-version-min=$min_version"
            install_name="@rpath/onnxruntime.framework/onnxruntime"
            ;;
    esac
    
    # Find additional libraries needed
    local additional_libs=""
    local search_dirs=("$build_dir")
    
    # For iOS simulator, search in both architecture directories
    if [ "$platform" = "ios-simulator" ]; then
        search_dirs=("build/${BUILD_CONFIG}/ios_simulator_arm64" "build/${BUILD_CONFIG}/ios_simulator_x86_64")
    fi
    
    # Check if re2 library exists
    for search_dir in "${search_dirs[@]}"; do
        local re2_lib=$(find "$search_dir" -name "libre2.a" -o -name "libonnxruntime_re2.a" 2>/dev/null | head -1)
        if [ -n "$re2_lib" ]; then
            additional_libs="$additional_libs -Wl,-force_load,$re2_lib"
            break
        fi
    done
    
    # Check if protobuf library exists
    for search_dir in "${search_dirs[@]}"; do
        local protobuf_lib=$(find "$search_dir" -name "libprotobuf*.a" 2>/dev/null | grep -v "protoc" | head -1)
        if [ -n "$protobuf_lib" ]; then
            additional_libs="$additional_libs -Wl,-force_load,$protobuf_lib"
            break
        fi
    done
    
    # Check if coreml_proto library exists (only for platforms with CoreML)
    if [ "$platform" != "ios-simulator" ]; then
        for search_dir in "${search_dirs[@]}"; do
            local coreml_proto_lib=$(find "$search_dir" -name "libcoreml_proto.a" 2>/dev/null | head -1)
            if [ -n "$coreml_proto_lib" ]; then
                additional_libs="$additional_libs -Wl,-force_load,$coreml_proto_lib"
                break
            fi
        done
    fi
    
    # Create dynamic library from combined static library
    echo "Creating dynamic library for $platform..."
    
    # Base frameworks
    local framework_flags="-framework Accelerate -framework Foundation"
    
    # Add CoreML only for platforms that support it
    if [ "$platform" != "ios-simulator" ]; then
        framework_flags="$framework_flags -framework CoreML"
    fi
    
    xcrun -sdk $sdk clang++ -dynamiclib \
        -isysroot $(xcrun --sdk $sdk --show-sdk-path) \
        $arch_flags \
        $min_version_flag \
        -Wl,-force_load,"$temp_dir/combined.a" \
        $additional_libs \
        $framework_flags \
        -lc++ \
        -install_name "$install_name" \
        -o "$output_lib"
    
    if [ ! -f "$output_lib" ]; then
        echo -e "${RED}Failed to create dynamic library${NC}"
        return 1
    fi
    
    # Clean up
    rm -rf "$temp_dir"
    
    echo -e "${GREEN}Successfully created dynamic library: $output_lib${NC}"
    return 0
}

# Function to create framework structure
create_framework() {
    local lib_path=$1
    local platform=$2
    local min_version=$3
    local platform_name=$4
    local has_coreml=${5:-true}
    
    local framework_dir="$OUTPUT_DIR/${platform}/onnxruntime.framework"
    
    echo -e "${YELLOW}Creating framework structure for $platform (CoreML: $has_coreml)...${NC}"
    
    mkdir -p "$framework_dir/Headers"
    mkdir -p "$framework_dir/Modules"
    
    # Copy library
    echo -e "${YELLOW}Copying library from: $lib_path${NC}"
    cp "$lib_path" "$framework_dir/onnxruntime"
    
    if [ ! -f "$framework_dir/onnxruntime" ]; then
        echo -e "${RED}Failed to copy library to framework${NC}"
        exit 1
    fi
    
    # Update the install name (our combined libraries are always dynamic)
    echo -e "${YELLOW}Updating install name for dynamic library${NC}"
    install_name_tool -id "@rpath/onnxruntime.framework/onnxruntime" "$framework_dir/onnxruntime"
    
    # Copy standard headers
    local header_base="$SCRIPT_DIR/include/onnxruntime/core/session"
    if [ ! -f "$header_base/onnxruntime_c_api.h" ]; then
        echo -e "${RED}Headers not found in $header_base${NC}"
        exit 1
    fi
    
    cp "$header_base/onnxruntime_c_api.h" "$framework_dir/Headers/"
    cp "$header_base/onnxruntime_cxx_api.h" "$framework_dir/Headers/"
    cp "$header_base/onnxruntime_cxx_inline.h" "$framework_dir/Headers/"
    
    # Copy CoreML header only if CoreML is enabled
    if [ "$has_coreml" = true ]; then
        cp "$SCRIPT_DIR/include/onnxruntime/core/providers/coreml/coreml_provider_factory.h" "$framework_dir/Headers/"
    fi
    
    # Create module map
    if [ "$has_coreml" = true ]; then
        cat > "$framework_dir/Modules/module.modulemap" << EOF
framework module onnxruntime {
    header "onnxruntime_c_api.h"
    header "onnxruntime_cxx_api.h" 
    header "onnxruntime_cxx_inline.h"
    header "coreml_provider_factory.h"
    
    link "c++"
    link framework "Accelerate"
    link framework "CoreML"
    link framework "Foundation"
    
    export *
}
EOF
    else
        cat > "$framework_dir/Modules/module.modulemap" << EOF
framework module onnxruntime {
    header "onnxruntime_c_api.h"
    header "onnxruntime_cxx_api.h" 
    header "onnxruntime_cxx_inline.h"
    
    link "c++"
    link framework "Accelerate"
    link framework "Foundation"
    
    export *
}
EOF
    fi

    # Create Info.plist
    cat > "$framework_dir/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>onnxruntime</string>
    <key>CFBundleIdentifier</key>
    <string>com.microsoft.onnxruntime</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>onnxruntime</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>$min_version</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>$platform_name</string>
    </array>
</dict>
</plist>
EOF
    
    echo -e "${GREEN}Framework created: $framework_dir${NC}"
}

# Create frameworks with combined libraries
echo -e "\n${GREEN}Creating frameworks for XCFramework...${NC}"

# Create iOS Device Framework
echo -e "\n${YELLOW}Creating iOS Device framework...${NC}"
IOS_BUILD_DIR="build/${BUILD_CONFIG}/ios_device"
if [ -d "$IOS_BUILD_DIR" ]; then
    TEMP_IOS_LIB="$IOS_BUILD_DIR/libonnxruntime_combined.dylib"
    if combine_static_libraries "$IOS_BUILD_DIR" "ios" "$IOS_MIN_OS_VERSION" "$TEMP_IOS_LIB"; then
        create_framework "$TEMP_IOS_LIB" "ios-arm64" "$IOS_MIN_OS_VERSION" "iPhoneOS" true
    else
        echo -e "${RED}Failed to create iOS device dynamic library${NC}"
        exit 1
    fi
else
    echo -e "${RED}iOS device build directory not found${NC}"
    exit 1
fi

# Create iOS Simulator Framework  
echo -e "\n${YELLOW}Creating iOS Simulator framework...${NC}"
IOS_SIM_BUILD_DIR="build/${BUILD_CONFIG}/ios_simulator"
if [ -d "$IOS_SIM_BUILD_DIR" ]; then
    TEMP_IOS_SIM_LIB="$IOS_SIM_BUILD_DIR/libonnxruntime_combined.dylib"
    if combine_static_libraries "$IOS_SIM_BUILD_DIR" "ios-simulator" "$IOS_MIN_OS_VERSION" "$TEMP_IOS_SIM_LIB"; then
        create_framework "$TEMP_IOS_SIM_LIB" "ios-arm64-simulator" "$IOS_MIN_OS_VERSION" "iPhoneSimulator" false
    else
        echo -e "${RED}Failed to create iOS simulator dynamic library${NC}"
        exit 1
    fi
else
    echo -e "${RED}iOS simulator build directory not found${NC}"
    exit 1
fi

# Create macOS Framework
echo -e "\n${YELLOW}Creating macOS framework...${NC}"
MACOS_BUILD_DIR_ACTUAL="$MACOS_BUILD_DIR"
if [ -d "$MACOS_BUILD_DIR_ACTUAL" ]; then
    TEMP_MACOS_LIB="$MACOS_BUILD_DIR_ACTUAL/libonnxruntime_combined.dylib"
    if combine_static_libraries "$MACOS_BUILD_DIR_ACTUAL" "macos" "$MACOS_MIN_OS_VERSION" "$TEMP_MACOS_LIB"; then
        if [ "$MACOS_HAS_COREML" = true ]; then
            create_framework "$TEMP_MACOS_LIB" "macos-arm64" "$MACOS_MIN_OS_VERSION" "MacOSX" true
        else
            create_framework "$TEMP_MACOS_LIB" "macos-arm64" "$MACOS_MIN_OS_VERSION" "MacOSX" false
        fi
    else
        echo -e "${RED}Failed to create macOS dynamic library${NC}"
        exit 1
    fi
else
    echo -e "${RED}macOS build directory not found${NC}"
    exit 1
fi

# Verify frameworks before creating XCFramework
echo -e "\n${YELLOW}Verifying frameworks...${NC}"
if [ ! -f "$OUTPUT_DIR/ios-arm64/onnxruntime.framework/onnxruntime" ]; then
    echo -e "${RED}iOS device framework binary not found${NC}"
    exit 1
fi
if [ ! -f "$OUTPUT_DIR/ios-arm64-simulator/onnxruntime.framework/onnxruntime" ]; then
    echo -e "${RED}iOS simulator framework binary not found${NC}"
    exit 1
fi
if [ ! -f "$OUTPUT_DIR/macos-arm64/onnxruntime.framework/onnxruntime" ]; then
    echo -e "${RED}macOS framework binary not found${NC}"
    exit 1
fi

# Create XCFramework
echo -e "\n${GREEN}Creating XCFramework...${NC}"
XCFRAMEWORK_PATH="$OUTPUT_DIR/onnxruntime.xcframework"

# Remove existing xcframework if it exists
rm -rf "$XCFRAMEWORK_PATH"

xcodebuild -create-xcframework \
    -framework "$OUTPUT_DIR/ios-arm64/onnxruntime.framework" \
    -framework "$OUTPUT_DIR/ios-arm64-simulator/onnxruntime.framework" \
    -framework "$OUTPUT_DIR/macos-arm64/onnxruntime.framework" \
    -output "$XCFRAMEWORK_PATH"

if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}SUCCESS: XCFramework created!${NC}"
    echo -e "${GREEN}Location: $XCFRAMEWORK_PATH${NC}"
    
    echo -e "${GREEN}XCFramework location: $XCFRAMEWORK_PATH${NC}"
    
    # Show info
    echo -e "\n${YELLOW}Framework info:${NC}"
    ls -la "$XCFRAMEWORK_PATH"
    
    echo -e "\n${YELLOW}Binary sizes:${NC}"
    find "$XCFRAMEWORK_PATH" -name "onnxruntime" -exec ls -lh {} \;
    
    echo -e "\n${GREEN}Integration:${NC}"
    echo "1. Drag onnxruntime.xcframework to your Xcode project"
    echo "2. Add to 'Frameworks, Libraries, and Embedded Content'"
    # Check if libraries are static or dynamic
    if [[ "$IOS_LIB" == *.a ]] || [[ "$MACOS_LIB" == *.a ]]; then
        echo "3. Set to 'Do Not Embed' (static library)"
    else
        echo "3. Set to 'Embed & Sign' (dynamic library)"
    fi
    echo ""
    echo "Usage in code:"
    echo "  #include <onnxruntime/onnxruntime_cxx_api.h>"
    
    if [ "$MACOS_HAS_COREML" = true ]; then
        echo "  #include <onnxruntime/coreml_provider_factory.h>  // Available on both iOS and macOS"
        echo ""
        echo "CoreML setup (both iOS device and macOS):"
        echo "  OrtSessionOptionsAppendExecutionProvider_CoreML(session_options, 0);"
    else
        echo "  #include <onnxruntime/coreml_provider_factory.h>  // Available on iOS device only"
        echo ""
        echo "CoreML setup:"
        echo "  // iOS device only"
        echo "  OrtSessionOptionsAppendExecutionProvider_CoreML(session_options, 0);"
        echo ""
        echo "Note: macOS build uses CPU only due to CoreML build issues"
    fi
    
else
    echo -e "${RED}XCFramework creation failed${NC}"
    exit 1
fi