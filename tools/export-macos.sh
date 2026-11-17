#!/bin/bash
# Create a native Apple Silicon bundle from the matching official universal template.
set -euo pipefail
cd "$(dirname "$0")/.."
project_dir="$PWD"
editor="${GODOT:-$project_dir/.tools/Godot.app/Contents/MacOS/Godot}"
template="${1:-$HOME/Library/Application Support/Godot/export_templates/4.4.1.stable/macos.zip}"
mkdir -p .tools dist
work=$(mktemp -d "$project_dir/.tools/export.XXXXXX")
trap 'rm -rf "$work"' EXIT
unzip -q "$template" -d "$work"
for mode in debug release; do
    binary="$work/macos_template.app/Contents/MacOS/godot_macos_${mode}"
    lipo "$binary.universal" -thin arm64 -output "$binary.arm64"
    rm "$binary.universal"
done
(cd "$work" && zip -qr "$work/arm64.zip" macos_template.app)
mv "$work/arm64.zip" .tools/macos-arm64.zip
"$editor" --headless --path game --import
"$editor" --headless --path game --export-release macOS "$project_dir/dist/EMERGENCE.app"
codesign --verify --deep --strict dist/EMERGENCE.app
