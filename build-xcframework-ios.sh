#!/bin/bash
#
# Clean ONNX Runtime xcframework build script (Refactored)
# Based on the proven official build.sh approach with CoreML
#
# Builds for:
# - iOS device (arm64) with CoreML
# - iOS simulator (arm64) with CPU fallback
# - macOS (arm64) with CoreML
#
# Then delegates XCFramework creation to create-xcframework-from-existing-builds.sh
#
# Usage: ./build-xcframework-ios-refactored.sh [Release|Debug|RelWithDebInfo|MinSizeRel]
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
    echo "- iOS simulator with CPU fallback"
    echo "- macOS with CoreML (or CPU fallback if CoreML fails)"
    echo "- Delegates XCFramework creation to create-xcframework-from-existing-builds.sh"
    echo ""
    echo "To clean previous builds:"
    echo "  ./clean-build.sh --help    # See cleaning options"
    echo "  ./clean-build.sh --all     # Clean everything"
    echo "  ./clean-build.sh --ios     # Clean iOS builds only"
    echo ""
    exit 0
fi

BUILD_CONFIG="${1:-Release}"

case "$BUILD_CONFIG" in
    Release|Debug|RelWithDebInfo|MinSizeRel)
        ;;
    *)
        echo "Error: Invalid build configuration '$BUILD_CONFIG'"
        echo "Valid options: Release, Debug, RelWithDebInfo, MinSizeRel"
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
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}Building ONNX Runtime XCFramework (Refactored)${NC}"
echo "Build configuration: $BUILD_CONFIG"

# Build directories based on configuration
OUTPUT_DIR="$SCRIPT_DIR/build/$BUILD_CONFIG/frameworks"
IOS_DEVICE_BUILD_DIR="$SCRIPT_DIR/build/$BUILD_CONFIG/ios_device"
IOS_SIM_BUILD_DIR="$SCRIPT_DIR/build/$BUILD_CONFIG/ios_simulator"
MACOS_BUILD_DIR="$SCRIPT_DIR/build/$BUILD_CONFIG/macos_coreml"

# ============================================================================
# Build iOS Device
# ============================================================================
echo -e "\n${BLUE}=== Building iOS Device (arm64) ===${NC}"

if [ ! -d "$IOS_DEVICE_BUILD_DIR" ]; then
    echo -e "${YELLOW}Creating iOS device build directory...${NC}"
    mkdir -p "$IOS_DEVICE_BUILD_DIR"
    
    echo -e "${YELLOW}Configuring iOS device build...${NC}"
    cmake \
        -S "$SCRIPT_DIR" \
        -B "$IOS_DEVICE_BUILD_DIR" \
        -DCMAKE_BUILD_TYPE=$BUILD_CONFIG \
        -DCMAKE_TOOLCHAIN_FILE="$SCRIPT_DIR/cmake/onnxruntime_ios.toolchain.cmake" \
        -DPLATFORM=OS64 \
        -DDEPLOYMENT_TARGET=$IOS_MIN_OS_VERSION \
        -Donnxruntime_USE_COREML=ON \
        -Donnxruntime_BUILD_SHARED_LIB=OFF \
        -Donnxruntime_BUILD_APPLE_FRAMEWORK=OFF \
        -Donnxruntime_USE_XNNPACK=OFF
        
    if [ $? -ne 0 ]; then
        echo -e "${RED}iOS device CMake configuration failed${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}iOS device build directory exists, skipping configuration${NC}"
fi

echo -e "${YELLOW}Building iOS device...${NC}"
cmake --build "$IOS_DEVICE_BUILD_DIR" --config $BUILD_CONFIG -j$(sysctl -n hw.ncpu)

if [ $? -ne 0 ]; then
    echo -e "${RED}iOS device build failed${NC}"
    exit 1
fi

# ============================================================================
# Build iOS Simulator
# ============================================================================
echo -e "\n${BLUE}=== Building iOS Simulator (arm64) ===${NC}"

if [ ! -d "$IOS_SIM_BUILD_DIR" ]; then
    echo -e "${YELLOW}Creating iOS simulator build directory...${NC}"
    mkdir -p "$IOS_SIM_BUILD_DIR"
    
    echo -e "${YELLOW}Configuring iOS simulator build...${NC}"
    cmake \
        -S "$SCRIPT_DIR" \
        -B "$IOS_SIM_BUILD_DIR" \
        -DCMAKE_BUILD_TYPE=$BUILD_CONFIG \
        -DCMAKE_TOOLCHAIN_FILE="$SCRIPT_DIR/cmake/onnxruntime_ios.toolchain.cmake" \
        -DPLATFORM=SIMULATORARM64 \
        -DDEPLOYMENT_TARGET=$IOS_MIN_OS_VERSION \
        -Donnxruntime_USE_COREML=OFF \
        -Donnxruntime_BUILD_SHARED_LIB=OFF \
        -Donnxruntime_BUILD_APPLE_FRAMEWORK=OFF \
        -Donnxruntime_USE_XNNPACK=OFF
        
    if [ $? -ne 0 ]; then
        echo -e "${RED}iOS simulator CMake configuration failed${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}iOS simulator build directory exists, skipping configuration${NC}"
fi

echo -e "${YELLOW}Building iOS simulator...${NC}"
cmake --build "$IOS_SIM_BUILD_DIR" --config $BUILD_CONFIG -j$(sysctl -n hw.ncpu)

if [ $? -ne 0 ]; then
    echo -e "${RED}iOS simulator build failed${NC}"
    exit 1
fi

# ============================================================================
# Build macOS
# ============================================================================
echo -e "\n${BLUE}=== Building macOS (arm64) ===${NC}"

if [ ! -d "$MACOS_BUILD_DIR" ]; then
    echo -e "${YELLOW}Creating macOS build directory...${NC}"
    mkdir -p "$MACOS_BUILD_DIR"
    
    echo -e "${YELLOW}Configuring macOS build...${NC}"
    cmake \
        -S "$SCRIPT_DIR" \
        -B "$MACOS_BUILD_DIR" \
        -DCMAKE_BUILD_TYPE=$BUILD_CONFIG \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOS_MIN_OS_VERSION \
        -Donnxruntime_USE_COREML=ON \
        -Donnxruntime_BUILD_SHARED_LIB=OFF \
        -Donnxruntime_BUILD_APPLE_FRAMEWORK=OFF \
        -Donnxruntime_USE_XNNPACK=OFF
        
    if [ $? -ne 0 ]; then
        echo -e "${RED}macOS CMake configuration failed${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}macOS build directory exists, skipping configuration${NC}"
fi

echo -e "${YELLOW}Building macOS...${NC}"
cmake --build "$MACOS_BUILD_DIR" --config $BUILD_CONFIG -j$(sysctl -n hw.ncpu)

if [ $? -ne 0 ]; then
    echo -e "${RED}macOS build failed${NC}"
    exit 1
fi

# ============================================================================
# Delegate XCFramework Creation
# ============================================================================
echo -e "\n${GREEN}=== Delegating XCFramework Creation ===${NC}"

# Check if the dedicated script exists
XCFRAMEWORK_SCRIPT="$SCRIPT_DIR/create-xcframework-from-existing-builds.sh"
if [ ! -f "$XCFRAMEWORK_SCRIPT" ]; then
    echo -e "${RED}Error: XCFramework creation script not found: $XCFRAMEWORK_SCRIPT${NC}"
    exit 1
fi

# Make sure the script is executable
chmod +x "$XCFRAMEWORK_SCRIPT"

# Call the dedicated XCFramework creation script
echo -e "${YELLOW}Calling: $XCFRAMEWORK_SCRIPT $BUILD_CONFIG${NC}"
"$XCFRAMEWORK_SCRIPT" "$BUILD_CONFIG"

# Check the result
if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}SUCCESS: Complete build and XCFramework creation finished!${NC}"
    echo -e "${GREEN}XCFramework was created by: create-xcframework-from-existing-builds.sh${NC}"
    echo -e "${BLUE}This refactored script eliminates duplicate XCFramework creation logic${NC}"
else
    echo -e "${RED}XCFramework creation failed${NC}"
    echo -e "${RED}Error occurred in: create-xcframework-from-existing-builds.sh${NC}"
    exit 1
fi