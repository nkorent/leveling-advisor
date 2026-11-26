#!/bin/sh
# Build the addon logo assets from the owner's source artwork (kept outside the repo).
# Usage: tools/make-logo.sh <source.png>   (1254x1254, shield centred a little above middle)
# Writes: LevelingAdvisor/Media/Logo.tga  64x64, 32-bit uncompressed TGA, top-left origin,
#                                         cropped square around the shield so it reads at 20-28 px
#         docs/logo.png                   256x256, the full image (README / GitHub)
# Needs ffmpeg and python3 (standard library only).
set -eu

src=${1:?usage: tools/make-logo.sh <source.png>}
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/docs" "$root/LevelingAdvisor/Media"

ffmpeg -v error -y -i "$src" -vf "scale=256:256:flags=lanczos" -frames:v 1 "$root/docs/logo.png"

ffmpeg -v error -y -i "$src" \
  -vf "crop=1010:1010:122:32,scale=64:64:flags=lanczos,format=bgra" \
  -frames:v 1 -f rawvideo - |
python3 -c '
import struct, sys
raw = sys.stdin.buffer.read()
assert len(raw) == 64 * 64 * 4, len(raw)
# type 2 (true colour), 32 bpp, 8 alpha bits, top-left origin
header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, 64, 64, 32, 0x28)
open(sys.argv[1], "wb").write(header + raw)
' "$root/LevelingAdvisor/Media/Logo.tga"
echo "wrote $root/LevelingAdvisor/Media/Logo.tga $root/docs/logo.png"
