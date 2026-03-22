#!/bin/zsh
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: zsh tools/generate_app_icon.sh /path/to/source.png"
  exit 1
fi

SOURCE_IMAGE="$1"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCE_DIR="$ROOT_DIR/MagicTrack/Resources"
ASSET_CATALOG_DIR="$RESOURCE_DIR/Assets.xcassets"
APPICON_DIR="$ASSET_CATALOG_DIR/AppIcon.appiconset"
SWIFT_HELPER="$(mktemp /tmp/magictrack-icon.XXXXXX).swift"

cleanup() {
  rm -f "$SWIFT_HELPER"
}
trap cleanup EXIT

rm -rf "$APPICON_DIR"
mkdir -p "$APPICON_DIR"

cat > "$SWIFT_HELPER" <<'EOF'
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4 else {
    fputs("Usage: helper <source> <size> <output>\n", stderr)
    exit(1)
}

let sourceURL = URL(fileURLWithPath: args[1])
let size = CGFloat(Int(args[2]) ?? 0)
let outputURL = URL(fileURLWithPath: args[3])

guard size > 0, let sourceImage = NSImage(contentsOf: sourceURL) else {
    fputs("Failed to load source image\n", stderr)
    exit(1)
}

let canvasSize = NSSize(width: size, height: size)
let insetRatio: CGFloat = 0.0
let availableSize = size * 0.86
let verticalOffset = size * -0.08

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size),
    pixelsHigh: Int(size),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
rep.size = canvasSize

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
    fputs("Failed to create graphics context\n", stderr)
    exit(1)
}
NSGraphicsContext.current = context

NSColor.clear.setFill()
NSRect(origin: .zero, size: canvasSize).fill()

guard let tiffData = sourceImage.tiffRepresentation,
      let sourceRep = NSBitmapImageRep(data: tiffData) else {
    fputs("Failed to create bitmap for source image\n", stderr)
    exit(1)
}

let pixelWidth = sourceRep.pixelsWide
let pixelHeight = sourceRep.pixelsHigh

var minX = pixelWidth
var minY = pixelHeight
var maxX = -1
var maxY = -1

let backgroundColor = sourceRep.colorAt(x: 0, y: pixelHeight - 1) ?? .clear
let backgroundTolerance: CGFloat = 0.035

func differsFromBackground(_ color: NSColor) -> Bool {
    let lhs = color.usingColorSpace(.deviceRGB) ?? color
    let rhs = backgroundColor.usingColorSpace(.deviceRGB) ?? backgroundColor

    if lhs.alphaComponent <= 0.01 {
        return false
    }

    let redDiff = abs(lhs.redComponent - rhs.redComponent)
    let greenDiff = abs(lhs.greenComponent - rhs.greenComponent)
    let blueDiff = abs(lhs.blueComponent - rhs.blueComponent)
    let alphaDiff = abs(lhs.alphaComponent - rhs.alphaComponent)

    return redDiff > backgroundTolerance
        || greenDiff > backgroundTolerance
        || blueDiff > backgroundTolerance
        || alphaDiff > backgroundTolerance
}

for y in 0..<pixelHeight {
    for x in 0..<pixelWidth {
        guard let color = sourceRep.colorAt(x: x, y: y) else { continue }
        if differsFromBackground(color) {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }
}

let sourceRect: NSRect
if maxX >= minX && maxY >= minY {
    sourceRect = NSRect(
        x: CGFloat(minX),
        y: CGFloat(minY),
        width: CGFloat(maxX - minX + 1),
        height: CGFloat(maxY - minY + 1)
    )
} else {
    sourceRect = NSRect(origin: .zero, size: sourceImage.size)
}

let scale = min(availableSize / sourceRect.width, availableSize / sourceRect.height)
let drawSize = NSSize(width: sourceRect.width * scale, height: sourceRect.height * scale)
let drawOrigin = NSPoint(
    x: (size - drawSize.width) / 2.0,
    y: ((size - drawSize.height) / 2.0) + verticalOffset
)

sourceImage.draw(
    in: NSRect(origin: drawOrigin, size: drawSize),
    from: sourceRect,
    operation: .copy,
    fraction: 1.0
)

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard
    let data = rep.representation(using: .png, properties: [:])
else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}

try data.write(to: outputURL)
EOF

create_icon() {
  local pixel_size="$1"
  local output_name="$2"
  swift "$SWIFT_HELPER" "$SOURCE_IMAGE" "$pixel_size" "$APPICON_DIR/$output_name"
}

create_icon 16 "icon_16x16.png"
create_icon 32 "icon_16x16@2x.png"
create_icon 32 "icon_32x32.png"
create_icon 64 "icon_32x32@2x.png"
create_icon 128 "icon_128x128.png"
create_icon 256 "icon_128x128@2x.png"
create_icon 256 "icon_256x256.png"
create_icon 512 "icon_256x256@2x.png"
create_icon 512 "icon_512x512.png"
create_icon 1024 "icon_512x512@2x.png"

cat > "$APPICON_DIR/Contents.json" <<'EOF'
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

cat > "$ASSET_CATALOG_DIR/Contents.json" <<'EOF'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo "Generated: $APPICON_DIR"
