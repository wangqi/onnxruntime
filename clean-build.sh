#!/bin/bash
#
# Clean ONNX Runtime build artifacts
# Use this when you want to start fresh or when build configurations change
#
# Usage: ./clean-build.sh [options]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default options
CLEAN_ALL=false
CLEAN_IOS=false
CLEAN_MACOS=false
CLEAN_FRAMEWORKS=false
CLEAN_CONFIG=""
INTERACTIVE=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Clean ONNX Runtime build artifacts selectively or completely"
            echo ""
            echo "Options:"
            echo "  -a, --all              Clean all build artifacts"
            echo "  -i, --ios              Clean iOS builds only"
            echo "  -m, --macos            Clean macOS builds only"
            echo "  -f, --frameworks       Clean framework outputs only"
            echo "  -c, --config CONFIG    Clean specific config (Release, Debug, etc.)"
            echo "  -y, --yes              Skip confirmation prompts"
            echo "  -h, --help             Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                     # Interactive mode - choose what to clean"
            echo "  $0 --all               # Clean everything"
            echo "  $0 --ios --config Release  # Clean only iOS Release builds"
            echo "  $0 --frameworks        # Clean only framework outputs"
            exit 0
            ;;
        -a|--all)
            CLEAN_ALL=true
            shift
            ;;
        -i|--ios)
            CLEAN_IOS=true
            shift
            ;;
        -m|--macos)
            CLEAN_MACOS=true
            shift
            ;;
        -f|--frameworks)
            CLEAN_FRAMEWORKS=true
            shift
            ;;
        -c|--config)
            CLEAN_CONFIG="$2"
            shift 2
            ;;
        -y|--yes)
            INTERACTIVE=false
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Get directory this script is in
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo -e "${BLUE}ONNX Runtime Build Cleaner${NC}"
echo "Current directory: $SCRIPT_DIR"

# Interactive mode if no specific options given
if [ "$CLEAN_ALL" = false ] && [ "$CLEAN_IOS" = false ] && [ "$CLEAN_MACOS" = false ] && [ "$CLEAN_FRAMEWORKS" = false ]; then
    echo ""
    echo -e "${YELLOW}What would you like to clean?${NC}"
    echo "1) Everything (complete clean)"
    echo "2) iOS builds only"
    echo "3) macOS builds only" 
    echo "4) Framework outputs only"
    echo "5) Specific configuration"
    echo "6) Cancel"
    echo ""
    read -p "Choose an option (1-6): " choice
    
    case $choice in
        1) CLEAN_ALL=true ;;
        2) CLEAN_IOS=true ;;
        3) CLEAN_MACOS=true ;;
        4) CLEAN_FRAMEWORKS=true ;;
        5) 
            echo ""
            echo "Available configurations in build directory:"
            ls -1 build/ 2>/dev/null | grep -E "(Release|Debug|RelWithDebInfo|MinSizeRel)" || echo "No build configurations found"
            echo ""
            read -p "Enter configuration name to clean: " CLEAN_CONFIG
            ;;
        6) 
            echo "Cancelled"
            exit 0
            ;;
        *)
            echo "Invalid choice"
            exit 1
            ;;
    esac
fi

# Function to show what will be cleaned and ask for confirmation
show_cleanup_plan() {
    echo ""
    echo -e "${YELLOW}Cleanup Plan:${NC}"
    
    if [ "$CLEAN_ALL" = true ]; then
        echo "- Remove entire build/ directory"
        echo "- This will clean ALL platforms, configurations, and frameworks"
        SIZE=$(du -sh build 2>/dev/null | cut -f1 || echo "unknown")
        echo "- Current build directory size: $SIZE"
    else
        if [ "$CLEAN_IOS" = true ]; then
            echo "- Remove iOS builds"
            if [ -n "$CLEAN_CONFIG" ]; then
                echo "  - Config: $CLEAN_CONFIG"
            else
                echo "  - All configurations"
            fi
        fi
        
        if [ "$CLEAN_MACOS" = true ]; then
            echo "- Remove macOS builds"
            if [ -n "$CLEAN_CONFIG" ]; then
                echo "  - Config: $CLEAN_CONFIG"
            else
                echo "  - All configurations"
            fi
        fi
        
        if [ "$CLEAN_FRAMEWORKS" = true ]; then
            echo "- Remove framework outputs"
            if [ -n "$CLEAN_CONFIG" ]; then
                echo "  - Config: $CLEAN_CONFIG"
            else
                echo "  - All configurations"
            fi
        fi
        
        if [ -n "$CLEAN_CONFIG" ] && [ "$CLEAN_IOS" = false ] && [ "$CLEAN_MACOS" = false ] && [ "$CLEAN_FRAMEWORKS" = false ]; then
            echo "- Remove all builds for configuration: $CLEAN_CONFIG"
        fi
    fi
    
    echo ""
}

# Function to perform the actual cleanup
perform_cleanup() {
    local cleaned_something=false
    
    if [ "$CLEAN_ALL" = true ]; then
        if [ -d "build" ]; then
            echo -e "${YELLOW}Removing entire build directory...${NC}"
            rm -rf build/
            echo -e "${GREEN}✓ Removed build directory${NC}"
            cleaned_something=true
        else
            echo "No build directory found"
        fi
        return
    fi
    
    # Clean specific parts
    if [ -n "$CLEAN_CONFIG" ]; then
        # Clean specific configuration
        local patterns=(
            "build/${CLEAN_CONFIG}"
            "build/${CLEAN_CONFIG}_*"
        )
        
        for pattern in "${patterns[@]}"; do
            for dir in $pattern; do
                if [ -d "$dir" ]; then
                    echo -e "${YELLOW}Removing $dir...${NC}"
                    rm -rf "$dir"
                    echo -e "${GREEN}✓ Removed $dir${NC}"
                    cleaned_something=true
                fi
            done
        done
    else
        # Clean by platform
        if [ "$CLEAN_IOS" = true ]; then
            echo -e "${YELLOW}Cleaning iOS builds...${NC}"
            find build/ -type d -name "*ios*" -o -name "*iOS*" 2>/dev/null | while read dir; do
                if [ -d "$dir" ]; then
                    echo -e "${YELLOW}Removing $dir...${NC}"
                    rm -rf "$dir"
                    echo -e "${GREEN}✓ Removed $dir${NC}"
                    cleaned_something=true
                fi
            done
        fi
        
        if [ "$CLEAN_MACOS" = true ]; then
            echo -e "${YELLOW}Cleaning macOS builds...${NC}"
            find build/ -type d -name "*macos*" -o -name "*macOS*" 2>/dev/null | while read dir; do
                if [ -d "$dir" ]; then
                    echo -e "${YELLOW}Removing $dir...${NC}"
                    rm -rf "$dir"
                    echo -e "${GREEN}✓ Removed $dir${NC}"
                    cleaned_something=true
                fi
            done
        fi
        
        if [ "$CLEAN_FRAMEWORKS" = true ]; then
            echo -e "${YELLOW}Cleaning framework outputs...${NC}"
            find build/ -name "*.xcframework" -o -name "*frameworks*" -o -name "*xcframework_output*" 2>/dev/null | while read item; do
                if [ -e "$item" ]; then
                    echo -e "${YELLOW}Removing $item...${NC}"
                    rm -rf "$item"
                    echo -e "${GREEN}✓ Removed $item${NC}"
                    cleaned_something=true
                fi
            done
        fi
    fi
    
    if [ "$cleaned_something" = false ]; then
        echo "Nothing to clean (no matching build artifacts found)"
    fi
}

# Show plan
show_cleanup_plan

# Ask for confirmation unless --yes was used
if [ "$INTERACTIVE" = true ]; then
    echo -e "${RED}Warning: This action cannot be undone!${NC}"
    echo ""
    read -p "Do you want to proceed? (y/N): " confirm
    case $confirm in
        [Yy]*)
            echo ""
            ;;
        *)
            echo "Cancelled"
            exit 0
            ;;
    esac
fi

# Perform cleanup
echo -e "${YELLOW}Starting cleanup...${NC}"
perform_cleanup

echo ""
echo -e "${GREEN}Cleanup completed!${NC}"

# Show remaining build directory contents
if [ -d "build" ]; then
    echo ""
    echo -e "${YELLOW}Remaining in build directory:${NC}"
    ls -la build/ 2>/dev/null || echo "Build directory is empty"
    
    # Show size
    SIZE=$(du -sh build 2>/dev/null | cut -f1 || echo "0")
    echo "Build directory size: $SIZE"
else
    echo "Build directory removed completely"
fi