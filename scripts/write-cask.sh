#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
    echo "usage: $0 <tag> <asset-name> <sha256> <output-file>" >&2
    exit 64
fi

TAG="$1"
ASSET_NAME="$2"
SHA256="$3"
OUTPUT_FILE="$4"
VERSION="${TAG#v}"

if [[ ! "$TAG" =~ ^v[0-9] ]]; then
    echo "tag must start with v, for example v1.0.0" >&2
    exit 65
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

cat >"$OUTPUT_FILE" <<CASK
cask "touchy" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/gugahoi/touchy/releases/download/v#{version}/${ASSET_NAME}"
  name "Touchy"
  desc "Native macOS menu-bar app for remapping multitouch gestures"
  homepage "https://github.com/gugahoi/touchy"

  app "Touchy.app"

  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "/Applications/Touchy.app"] if OS.mac?
  end
end
CASK
