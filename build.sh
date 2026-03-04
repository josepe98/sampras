#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="$HOME/Applications"

echo "Building Sampras..."
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
    -project "$PROJECT_DIR/Sampras.xcodeproj" \
    -scheme Sampras \
    -configuration Debug \
    build 2>&1 | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED|\.swift:[0-9]+:[0-9]+: (error|warning))"

BUILT=$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
    -project "$PROJECT_DIR/Sampras.xcodeproj" \
    -scheme Sampras \
    -configuration Debug \
    -showBuildSettings 2>/dev/null | grep "BUILT_PRODUCTS_DIR" | head -1 | awk '{print $3}')

echo "Deploying to $DEPLOY_DIR..."
mkdir -p "$DEPLOY_DIR"
cp -R "$BUILT/Sampras.app" "$DEPLOY_DIR/"

echo "Restarting..."
pkill -x Sampras 2>/dev/null || true
sleep 1
open "$DEPLOY_DIR/Sampras.app"

echo "Done."
