#!/bin/bash
#
# Create ONNX Runtime xcframework from existing builds
# This script searches for already-built libraries and creates an xcframework
#
# Usage: ./create-xcframework-from-existing-builds.sh [Release|Debug|RelWithDebInfo|MinSizeRel]
#

set -e

# Options
IOS_MIN_OS_VERSION=16.4
MACOS_MIN_OS_VERSION=13.3

# Parse command line arguments
BUILD_CONFIG="${1:-Release}"

# Get directory this script is in
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Creating ONNX Runtime XCFramework from existing builds${NC}"
echo "Build configuration: $BUILD_CONFIG"

# Function to find the built library with multiple search paths
find_library_flexible() {
    local platform_name=$1
    shift
    local search_paths=("$@")
    
    echo -e "${YELLOW}Finding $platform_name library...${NC}" >&2
    
    for search_dir in "${search_paths[@]}"; do
        if [ -d "$search_dir" ]; then
            echo "Searching in: $search_dir" >&2
            # Look for both .a and .dylib files
            local lib_path=$(find "$search_dir" -name "libonnxruntime.a" -o -name "libonnxruntime.dylib" 2>/dev/null | grep -v "\.dSYM" | head -1)
            if [ -n "$lib_path" ]; then
                echo -e "${GREEN}Found $platform_name library: $lib_path${NC}" >&2
                echo "$lib_path"
                return 0
            fi
        fi
    done
    
    echo -e "${RED}Could not find libonnxruntime for $platform_name${NC}" >&2
    echo "Searched in: ${search_paths[@]}" >&2
    return 1
}

# Search for iOS device library in multiple possible locations
IOS_DEVICE_SEARCH_PATHS=(
    "$SCRIPT_DIR/build/iOS/$BUILD_CONFIG/Release-iphoneos"
    "$SCRIPT_DIR/build/iOS/$BUILD_CONFIG"
    "$SCRIPT_DIR/build/$BUILD_CONFIG/ios_device/Release/Release-iphoneos"
    "$SCRIPT_DIR/build/$BUILD_CONFIG/ios_device/Release"
    "$SCRIPT_DIR/build/$BUILD_CONFIG/ios_device"
    "$SCRIPT_DIR/build/${BUILD_CONFIG}_clean/ios_device/$BUILD_CONFIG"
    "$SCRIPT_DIR/build/${BUILD_CONFIG}_clean/ios_device/$BUILD_CONFIG-iphoneos"
    "$SCRIPT_DIR/build/${BUILD_CONFIG}_clean/ios_device"
)

# Search for iOS simulator library
IOS_SIM_SEARCH_PATHS=(
    "$SCRIPT_DIR/build/$BUILD_CONFIG/ios_simulator/Release/Release-iphonesimulator"
    "$SCRIPT_DIR/build/$BUILD_CONFIG/ios_simulator/Release"
    "$SCRIPT_DIR/build/$BUILD_CONFIG/ios_simulator"
    "$SCRIPT_DIR/build/${BUILD_CONFIG}/ios_simulator_arm64/Release/Release-iphonesimulator"
    "$SCRIPT_DIR/build/${BUILD_CONFIG}/ios_simulator_arm64/Release"
    "$SCRIPT_DIR/build/${BUILD_CONFIG}/ios_simulator_arm64"
)

# Search for macOS library in multiple possible locations
MACOS_SEARCH_PATHS=(
    "$SCRIPT_DIR/build/MacOS/RelWithDebInfo"
    "$SCRIPT_DIR/build/MacOS/$BUILD_CONFIG"
    "$SCRIPT_DIR/build/$BUILD_CONFIG/macos_coreml/$BUILD_CONFIG"
    "$SCRIPT_DIR/build/$BUILD_CONFIG/macos_coreml"
    "$SCRIPT_DIR/build/$BUILD_CONFIG/macos_cpu/$BUILD_CONFIG"
    "$SCRIPT_DIR/build/$BUILD_CONFIG/macos_cpu"
    "$SCRIPT_DIR/build/${BUILD_CONFIG}_clean/macos_coreml/$BUILD_CONFIG"
    "$SCRIPT_DIR/build/${BUILD_CONFIG}_clean/macos_coreml"
    "$SCRIPT_DIR/build/${BUILD_CONFIG}_clean/macos_cpu/$BUILD_CONFIG"
    "$SCRIPT_DIR/build/${BUILD_CONFIG}_clean/macos_cpu"
)

# Find libraries
if ! IOS_DEVICE_LIB=$(find_library_flexible "iOS Device" "${IOS_DEVICE_SEARCH_PATHS[@]}"); then
    exit 1
fi

if ! IOS_SIM_LIB=$(find_library_flexible "iOS Simulator" "${IOS_SIM_SEARCH_PATHS[@]}"); then
    echo -e "${YELLOW}Warning: iOS Simulator library not found, continuing without it${NC}" >&2
    IOS_SIM_LIB=""
fi

if ! MACOS_LIB=$(find_library_flexible "macOS" "${MACOS_SEARCH_PATHS[@]}"); then
    exit 1
fi

# Determine if libraries are static or dynamic
IOS_DEVICE_IS_STATIC=false
IOS_SIM_IS_STATIC=false
MACOS_IS_STATIC=false

if [[ "$IOS_DEVICE_LIB" == *.a ]]; then
    IOS_DEVICE_IS_STATIC=true
fi

if [[ -n "$IOS_SIM_LIB" ]] && [[ "$IOS_SIM_LIB" == *.a ]]; then
    IOS_SIM_IS_STATIC=true
fi

if [[ "$MACOS_LIB" == *.a ]]; then
    MACOS_IS_STATIC=true
fi

echo -e "${YELLOW}iOS device library is static: $IOS_DEVICE_IS_STATIC${NC}"
echo -e "${YELLOW}iOS simulator library is static: $IOS_SIM_IS_STATIC${NC}"
echo -e "${YELLOW}macOS library is static: $MACOS_IS_STATIC${NC}"

# Create output directory
OUTPUT_DIR="$SCRIPT_DIR/build/$BUILD_CONFIG/frameworks"
mkdir -p "$OUTPUT_DIR"

# Function to create framework structure
create_framework() {
    local lib_path=$1
    local platform=$2
    local min_version=$3
    local platform_name=$4
    local is_static=$5
    
    local framework_dir="$OUTPUT_DIR/${platform}/onnxruntime.framework"
    
    echo -e "${YELLOW}Creating framework for $platform...${NC}"
    
    mkdir -p "$framework_dir/Headers"
    mkdir -p "$framework_dir/Modules"
    
    # Copy library
    if [ "$is_static" = true ]; then
        cp "$lib_path" "$framework_dir/onnxruntime"
    else
        # For dynamic library, we need to update the install name
        cp "$lib_path" "$framework_dir/onnxruntime"
        install_name_tool -id "@rpath/onnxruntime.framework/onnxruntime" "$framework_dir/onnxruntime"
    fi
    
    # Copy standard headers
    if [ -f "$SCRIPT_DIR/include/onnxruntime/core/session/onnxruntime_c_api.h" ]; then
        cp "$SCRIPT_DIR/include/onnxruntime/core/session/onnxruntime_c_api.h" "$framework_dir/Headers/"
        cp "$SCRIPT_DIR/include/onnxruntime/core/session/onnxruntime_cxx_api.h" "$framework_dir/Headers/"
        cp "$SCRIPT_DIR/include/onnxruntime/core/session/onnxruntime_cxx_inline.h" "$framework_dir/Headers/"
        
        # Copy additional headers needed for C++ compilation
        if [ -f "$SCRIPT_DIR/include/onnxruntime/core/session/onnxruntime_float16.h" ]; then
            cp "$SCRIPT_DIR/include/onnxruntime/core/session/onnxruntime_float16.h" "$framework_dir/Headers/"
            echo -e "${GREEN}onnxruntime_float16.h included${NC}"
        else
            echo -e "${YELLOW}Warning: onnxruntime_float16.h not found${NC}"
        fi
        
        if [ -f "$SCRIPT_DIR/include/onnxruntime/core/session/onnxruntime_ep_c_api.h" ]; then
            cp "$SCRIPT_DIR/include/onnxruntime/core/session/onnxruntime_ep_c_api.h" "$framework_dir/Headers/"
            echo -e "${GREEN}onnxruntime_ep_c_api.h included${NC}"
        else
            echo -e "${YELLOW}Warning: onnxruntime_ep_c_api.h not found${NC}"
        fi
    else
        echo -e "${RED}Warning: Headers not found in expected location${NC}"
    fi
    
    # Check if CoreML provider header exists
    COREML_HEADER="$SCRIPT_DIR/include/onnxruntime/core/providers/coreml/coreml_provider_factory.h"
    HAS_COREML=false
    if [ -f "$COREML_HEADER" ]; then
        cp "$COREML_HEADER" "$framework_dir/Headers/"
        HAS_COREML=true
        echo -e "${GREEN}CoreML support included${NC}"
    else
        echo -e "${YELLOW}CoreML header not found - building without CoreML support${NC}"
    fi
    
    # Create module map
    if [ "$HAS_COREML" = true ]; then
        cat > "$framework_dir/Modules/module.modulemap" << EOF
framework module onnxruntime {
    header "onnxruntime_c_api.h"
    header "onnxruntime_cxx_api.h" 
    header "onnxruntime_cxx_inline.h"
    header "onnxruntime_float16.h"
    header "onnxruntime_ep_c_api.h"
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
    header "onnxruntime_float16.h"
    header "onnxruntime_ep_c_api.h"
    
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

# Create frameworks
create_framework "$IOS_DEVICE_LIB" "ios-arm64" "$IOS_MIN_OS_VERSION" "iPhoneOS" "$IOS_DEVICE_IS_STATIC"

# Create iOS simulator framework if library exists
if [ -n "$IOS_SIM_LIB" ]; then
    create_framework "$IOS_SIM_LIB" "ios-arm64-simulator" "$IOS_MIN_OS_VERSION" "iPhoneSimulator" "$IOS_SIM_IS_STATIC"
fi

create_framework "$MACOS_LIB" "macos-arm64" "$MACOS_MIN_OS_VERSION" "MacOSX" "$MACOS_IS_STATIC"

# Create XCFramework
echo -e "\n${GREEN}Creating XCFramework...${NC}"
XCFRAMEWORK_PATH="$OUTPUT_DIR/onnxruntime.xcframework"

# Remove existing xcframework if it exists
rm -rf "$XCFRAMEWORK_PATH"

# Build xcodebuild command dynamically
xcframework_args=("-create-xcframework")
xcframework_args+=("-framework" "$OUTPUT_DIR/ios-arm64/onnxruntime.framework")

# Add iOS simulator if it exists
if [ -n "$IOS_SIM_LIB" ] && [ -d "$OUTPUT_DIR/ios-arm64-simulator/onnxruntime.framework" ]; then
    xcframework_args+=("-framework" "$OUTPUT_DIR/ios-arm64-simulator/onnxruntime.framework")
fi

xcframework_args+=("-framework" "$OUTPUT_DIR/macos-arm64/onnxruntime.framework")
xcframework_args+=("-output" "$XCFRAMEWORK_PATH")

xcodebuild "${xcframework_args[@]}"

if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}SUCCESS: XCFramework created!${NC}"
    echo -e "${GREEN}Location: $XCFRAMEWORK_PATH${NC}"
    
    echo -e "${GREEN}XCFramework location: $XCFRAMEWORK_PATH${NC}"
    
    # Show info
    echo -e "\n${YELLOW}Framework info:${NC}"
    ls -la "$XCFRAMEWORK_PATH"
    
    echo -e "\n${YELLOW}Binary sizes:${NC}"
    find "$XCFRAMEWORK_PATH" -name "onnxruntime" -exec ls -lh {} \;
    
    echo -e "\n${GREEN}Integration instructions:${NC}"
    echo "1. Drag onnxruntime.xcframework to your Xcode project"
    echo "2. Add to 'Frameworks, Libraries, and Embedded Content'"
    if [ "$IOS_DEVICE_IS_STATIC" = true ] || [ "$MACOS_IS_STATIC" = true ]; then
        echo "3. Set to 'Do Not Embed' (static library)"
    else
        echo "3. Set to 'Embed & Sign' (dynamic library)"
    fi
    echo ""
    echo "Usage in code:"
    echo "  #include <onnxruntime/onnxruntime_cxx_api.h>"
    
    if [ -f "$COREML_HEADER" ]; then
        echo "  #include <onnxruntime/coreml_provider_factory.h>"
        echo ""
        echo "CoreML setup:"
        echo "  OrtSessionOptionsAppendExecutionProvider_CoreML(session_options, 0);"
    fi
else
    echo -e "${RED}XCFramework creation failed${NC}"
    exit 1
fi