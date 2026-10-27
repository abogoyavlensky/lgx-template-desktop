#!/usr/bin/env bash
# Build the app natively for Apple Silicon and assemble dist/<APP_NAME>.app
# around it. The bundle is unsigned: for a signed, notarized release, see
# the README's "Releases" section.
#
#   lgx package-macos
set -euo pipefail

# Edit these for your app.
# The name shown in the Dock and the Finder, e.g. "My App".
APP_NAME="projectname"
# Change to your reverse-DNS ID before you sign the app.
BUNDLE_ID="com.example.projectname"
# The binary inside the bundle, and the icon's file name.
EXECUTABLE="projectname"
# One value for the compiler and linker flags and Info.plist.
MACOS_MIN="15.0"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

die() { echo "${0##*/}: $1" >&2; exit 1; }

# The version: VERSION with surrounding whitespace trimmed, MAJOR.MINOR.PATCH.
read_version() {
    local v
    [[ -f "$ROOT/VERSION" ]] || die "VERSION is missing"
    v="$(tr -d '[:space:]' <"$ROOT/VERSION")"
    [[ "$v" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
        die "VERSION must be MAJOR.MINOR.PATCH, got '$v'"
    echo "$v"
}

require_apple_silicon() {
    [[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] ||
        die "needs an Apple Silicon Mac (this is $(uname -s) $(uname -m))"
}

# Escape a value for the replacement side of a sed s/// command.
sed_escape() { printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'; }

require_apple_silicon
version="$(read_version)"
cd "$ROOT"

# The shipped app is the desktop build: a window over cgo, not Wails' server
# mode, with the production tag lgx.edn sets for the binary.
[[ "${CGO_ENABLED:-1}" == "1" ]] || die "CGO_ENABLED=$CGO_ENABLED: the desktop build needs cgo"
[[ "${GOFLAGS:-}" != *server* ]] || die "GOFLAGS has the server tag ($GOFLAGS): unset it"

export GOOS=darwin GOARCH=arm64 CGO_ENABLED=1
export MACOSX_DEPLOYMENT_TARGET="$MACOS_MIN"
export CGO_CFLAGS="${CGO_CFLAGS:+$CGO_CFLAGS }-mmacosx-version-min=$MACOS_MIN"
export CGO_LDFLAGS="${CGO_LDFLAGS:+$CGO_LDFLAGS }-mmacosx-version-min=$MACOS_MIN"

mkdir -p "$DIST"
log="$DIST/build.log"
echo "==> Building $APP_NAME $version (frontend, then the native binary)"
lgx build 2>&1 | tee "$log"
# ld warns when an object targets a newer macOS than the binary claims: the
# deployment flags did not reach part of the build.
if grep -q "built for newer" "$log"; then
    die "the linker saw objects for a newer macOS than $MACOS_MIN (see $log)"
fi

echo "==> Icon"
iconset="$DIST/$EXECUTABLE.iconset"
rm -rf "$iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" build/macos/icon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" build/macos/icon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$DIST/$EXECUTABLE.icns"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# bin/projectname is :out in lgx.edn.
cp bin/projectname "$APP/Contents/MacOS/$EXECUTABLE"
cp "$DIST/$EXECUTABLE.icns" "$APP/Contents/Resources/$EXECUTABLE.icns"
sed -e "s/@APP_NAME@/$(sed_escape "$APP_NAME")/g" \
    -e "s/@BUNDLE_ID@/$(sed_escape "$BUNDLE_ID")/g" \
    -e "s/@EXECUTABLE@/$(sed_escape "$EXECUTABLE")/g" \
    -e "s/@VERSION@/$version/g" \
    -e "s/@MACOS_MIN@/$MACOS_MIN/g" \
    build/macos/Info.plist >"$APP/Contents/Info.plist"
plutil -lint -s "$APP/Contents/Info.plist"

echo "Built $APP ($version, unsigned). Open it with: open \"dist/$APP_NAME.app\""
echo "To sign and notarize it for distribution, follow Quel's docs/RELEASE.md:"
echo "https://github.com/abogoyavlensky/quel"
