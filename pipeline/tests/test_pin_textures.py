"""tools/make-pin-textures.py writes the map pin and bookmark TGA textures."""
import struct
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "make-pin-textures.py"
MEDIA = ROOT / "LevelingAdvisor" / "Media"
TEXTURES = ("PinShield.tga", "PinShieldGlow.tga", "BookmarkTab.tga", "ChainLink.tga")


@pytest.fixture(scope="module")
def out(tmp_path_factory):
    """One render for the whole module (pure Python with 4x4 supersampling: seconds per run)."""
    outdir = tmp_path_factory.mktemp("textures")
    subprocess.run([sys.executable, str(SCRIPT), str(outdir)], check=True, capture_output=True)
    return outdir


def load(path):
    data = Path(path).read_bytes()
    (idlen, cmap, itype, _c1, _c2, _c3, _x, _y, w, h, bpp, desc) = struct.unpack(
        "<BBBHHBHHHHBB", data[:18])
    return dict(idlen=idlen, cmap=cmap, itype=itype, w=w, h=h, bpp=bpp, desc=desc,
                pix=data[18 + idlen:], size=len(data))


def px(img, x, y):
    i = (y * img["w"] + x) * 4
    b, g, r, a = img["pix"][i:i + 4]
    return r, g, b, a


def test_shield_header(out):
    img = load(out / "PinShield.tga")
    assert img["itype"] == 2 and img["cmap"] == 0
    assert (img["w"], img["h"], img["bpp"]) == (64, 64, 32)
    assert img["desc"] & 0x20          # top-left origin
    assert img["desc"] & 0x0F == 8     # 8 alpha bits
    assert len(img["pix"]) == 64 * 64 * 4


def test_shield_pixels(out):
    img = load(out / "PinShield.tga")
    assert px(img, 0, 0)[3] == 0
    r, g, b, a = px(img, 32, 34)
    assert a >= 230 and r < 90 and g < 70 and b < 40
    rim = [px(img, 32, y) for y in range(2, 5)]
    assert any(r > 200 and g > 160 and b < 60 for r, g, b, a in rim), rim


def test_glow(out):
    img = load(out / "PinShieldGlow.tga")
    assert (img["w"], img["h"], img["bpp"], img["itype"]) == (64, 64, 32, 2)
    assert img["desc"] & 0x20
    r, g, b, a = px(img, 32, 34)
    assert (r, g, b) == (255, 209, 0) and abs(a - round(0.55 * 255)) <= 1
    assert px(img, 0, 0)[3] == 0
    # alpha decreases moving outward from the shield edge (left of x~5 at y 20)
    alphas = [px(img, x, 20)[3] for x in range(0, 33)]
    assert max(alphas) > 0
    assert alphas[0] <= alphas[5] <= alphas[10]


def gold(c):
    r, g, b, a = c
    return r > 200 and g > 160 and b < 80 and a >= 250


def test_bookmark_pixels(out):
    img = load(out / "BookmarkTab.tga")
    assert (img["w"], img["h"], img["bpp"]) == (64, 64, 32) and img["desc"] & 0x20
    assert img["itype"] == 2 and len(img["pix"]) == 64 * 64 * 4
    # dark near black-brown body, alpha 0.9
    r, g, b, a = px(img, 20, 32)
    assert r < 60 and g < 50 and b < 40 and abs(a - round(0.9 * 255)) <= 2
    # gold border on the right, top and bottom
    assert gold(px(img, 61, 32)) and gold(px(img, 20, 2)) and gold(px(img, 20, 62))
    # the left edge is open: filled but not bordered
    left = px(img, 0, 32)
    assert not gold(left) and left[0] < 60 and left[3] >= 200
    assert not gold(px(img, 1, 32))
    # rounded right corners: the corner pixels are empty, outside the body is clear
    assert px(img, 61, 1)[3] < 128 and px(img, 61, 62)[3] < 128
    assert px(img, 63, 32)[3] == 0 and px(img, 20, 0)[3] < 128 and px(img, 20, 63)[3] < 128


def test_chain_link(out):
    img = load(out / "ChainLink.tga")
    assert (img["w"], img["h"], img["bpp"], img["itype"]) == (32, 32, 32, 2)
    assert img["desc"] & 0x20 and img["desc"] & 0x0F == 8
    assert len(img["pix"]) == 32 * 32 * 4
    for x, y in ((0, 0), (31, 0), (0, 31), (31, 31)):
        assert px(img, x, y)[3] == 0
    # an opaque white pixel on the ring of each link; the holes stay clear
    for x in (3, 27):
        r, g, b, a = px(img, x, 16)
        assert a == 255 and r > 240 and g > 240 and b > 240, (x, px(img, x, 16))
    assert px(img, 8, 16)[3] == 0 and px(img, 22, 16)[3] == 0
    # the links are tilted: the top of the left link sits right of its bottom
    top = [x for x in range(32) if px(img, x, 8)[3] == 255 and px(img, x, 8)[0] > 240]
    bottom = [x for x in range(32) if px(img, x, 23)[3] == 255 and px(img, x, 23)[0] > 240]
    assert top and bottom and min(top) >= min(bottom) + 2
    # a dark outline exists
    assert any(a == 255 and r < 80 for r, g, b, a in (px(img, x, 16) for x in range(0, 32)))


def test_deterministic_and_the_committed_textures_are_current(out):
    """A render is byte for byte the textures the addon ships (rendered by an earlier run): the
    script is deterministic, and a changed script without re-rendered textures fails here."""
    assert sorted(p.name for p in out.iterdir()) == sorted(TEXTURES)
    for name in TEXTURES:
        assert (out / name).read_bytes() == (MEDIA / name).read_bytes(), name
