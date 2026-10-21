#!/usr/bin/env bash
# make-icon.sh — render a macOS app icon (rounded gradient + music.note) and
# build an AppIcon.icns with iconutil. Requires Xcode Command Line Tools (swiftc).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT/assets"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/fticon.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

echo "▶ Rendering 1024px source icon…"
cat > "$TMP/render.swift" <<'SWIFT'
import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

// Rounded-square gradient background
let inset = NSRect(x: 0, y: 0, width: size, height: size).insetBy(dx: 48, dy: 48)
let bg = NSBezierPath(roundedRect: inset, xRadius: 220, yRadius: 220)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.99, green: 0.76, blue: 0.17, alpha: 1),
    NSColor(calibratedRed: 0.92, green: 0.42, blue: 0.16, alpha: 1),
    NSColor(calibratedRed: 0.78, green: 0.26, blue: 0.12, alpha: 1)
])!
gradient.draw(in: bg, angle: -90)

// White music-note SF Symbol, centered
if let raw = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil),
   let symbol = raw.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 460, weight: .bold)) {
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    NSColor.white.set()
    symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    tinted.unlockFocus()
    let x = (size - tinted.size.width) / 2
    let y = (size - tinted.size.height) / 2
    tinted.draw(in: NSRect(x: x, y: y, width: tinted.size.width, height: tinted.size.height),
                from: .zero, operation: .sourceOver, fraction: 1)
}

img.unlockFocus()

let tiff = img.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT

swiftc -O "$TMP/render.swift" -o "$TMP/render" 2>/dev/null
"$TMP/render" "$TMP/icon_1024.png"

echo "▶ Building iconset…"
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"; do
  set -- $spec
  sips -z "$1" "$1" "$TMP/icon_1024.png" --out "$ICONSET/icon_$2.png" >/dev/null
done

echo "▶ Assembling AppIcon.icns…"
mkdir -p "$OUT_DIR"
iconutil -c icns "$ICONSET" -o "$OUT_DIR/AppIcon.icns"
echo "✓ Wrote $OUT_DIR/AppIcon.icns"
