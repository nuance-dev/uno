#!/bin/bash

# Set error handling
set -e

# Configuration
PROJECT_NAME="Uno"
WORKSPACE_PATH="."
SCHEME_NAME="Uno"
CONFIGURATION="Debug"

# Colors for output formatting
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Clean build directory
echo "Cleaning build directory..."
xcodebuild clean -project "$PROJECT_NAME.xcodeproj" -scheme "$SCHEME_NAME" -configuration "$CONFIGURATION"

# Build project and format output
echo "Building project..."
# Use a temporary file to store the build output
BUILD_OUTPUT=$(mktemp)
# Use tee to capture the output while still displaying it
xcodebuild \
    -project "$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME_NAME" \
    -configuration "$CONFIGURATION" 2>&1 | tee "$BUILD_OUTPUT"

# Store the exit code
BUILD_RESULT=${PIPESTATUS[0]}

# Format the output
while IFS= read -r line; do
    # Format warnings
    if [[ $line == *": warning:"* ]]; then
        echo -e "${YELLOW}Warning:${NC} $line"
    # Format errors
    elif [[ $line == *": error:"* ]]; then
        echo -e "${RED}Error:${NC} $line"
    fi
done < "$BUILD_OUTPUT"

# Clean up
rm "$BUILD_OUTPUT"

# Check if build was successful
if [ $BUILD_RESULT -eq 0 ]; then
    echo "Build completed successfully!"
    exit 0
else
    echo "Build failed. Please check the errors above."
    exit $BUILD_RESULT
fi 