#!/bin/sh
# Builds build/ClaudePill.app from the Swift package.
set -eu
cd "$(dirname "$0")"

swift build -c release
application="build/ClaudePill.app"
rm -rf "$application"
mkdir -p "$application/Contents/MacOS"
cp .build/release/ClaudePill "$application/Contents/MacOS/"
cp Info.plist "$application/Contents/"
codesign --force --sign - "$application"
echo "Built $application"
