"""tools/make-pin-textures.py writes the map pin and bookmark TGA textures."""
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "make-pin-textures.py"


def run(outdir):
    subprocess.run([sys.executable, str(SCRIPT), str(outdir)], check=True)


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


def test_shield_header(tmp_path):
    run(tmp_path)
    img = load(tmp_path / "PinShield.tga")
    assert img["itype"] == 2 and img["cmap"] == 0
    assert (img["w"], img["h"], img["bpp"]) == (64, 64, 32)
    assert img["desc"] & 0x20          # top-left origin
    assert img["desc"] & 0x0F == 8     # 8 alpha bits
    assert len(img["pix"]) == 64 * 64 * 4


def test_shield_pixels(tmp_path):
    run(tmp_path)
    img = load(tmp_path / "PinShield.tga")
    assert px(img, 0, 0)[3] == 0
    r, g, b, a = px(img, 32, 34)
    assert a >= 230 and r < 90 and g < 70 and b < 40
    rim = [px(img, 32, y) for y in range(2, 5)]
    assert any(r > 200 and g > 160 and b < 60 for r, g, b, a in rim), rim


def test_glow(tmp_path):
    run(tmp_path)
    img = load(tmp_path / "PinShieldGlow.tga")
    assert (img["w"], img["h"], img["bpp"], img["itype"]) == (64, 64, 32, 2)
    assert img["desc"] & 0x20
    r, g, b, a = px(img, 32, 34)
    assert (r, g, b) == (255, 209, 0) and abs(a - round(0.55 * 255)) <= 1
    assert px(img, 0, 0)[3] == 0
    # alpha decreases moving outward from the shield edge (left of x~5 at y 20)
    alphas = [px(img, x, 20)[3] for x in range(0, 33)]
    assert max(alphas) > 0
    assert alphas[0] <= alphas[5] <= alphas[10]


def test_bookmark_pixels(tmp_path):
    run(tmp_path)
    img = load(tmp_path / "BookmarkTab.tga")
    assert (img["w"], img["h"], img["bpp"]) == (64, 64, 32) and img["desc"] & 0x20
    assert img["itype"] == 2 and len(img["pix"]) == 64 * 64 * 4
    assert px(img, 0, 0)[3] == 0 and px(img, 63, 32)[3] == 0
    r, g, b, a = px(img, 10, 32)
    assert a >= 240 and 50 <= r <= 100 and b <= 40
    r, g, b, a = px(img, 55, 32)
    assert r > 200 and g > 160 and b < 60      # right rim
    r, g, b, a = px(img, 20, 5)
    assert r > 200 and g > 160 and b < 60      # top rim
    r, g, b, a = px(img, 20, 59)
    assert r > 200 and g > 160 and b < 60      # bottom rim
    assert px(img, 0, 32)[0] < 120             # no left rim
    assert px(img, 0, 32)[3] >= 240            # the left edge is straight and filled
    assert px(img, 63, 2)[3] == 0 and px(img, 20, 62)[3] == 0
    # the fill darkens downward
    assert px(img, 10, 12)[0] > px(img, 10, 52)[0]
    # rounded right corners: the corner pixel itself is empty
    assert px(img, 55, 4)[3] < 128 and px(img, 55, 59)[3] < 128
    # the highlight line at y 7 is lighter than the fill under it
    assert px(img, 20, 7)[0] > px(img, 20, 9)[0]


def test_deterministic(tmp_path):
    a, b = tmp_path / "a", tmp_path / "b"
    a.mkdir(); b.mkdir()
    run(a); run(b)
    for name in ("PinShield.tga", "PinShieldGlow.tga", "BookmarkTab.tga"):
        assert (a / name).read_bytes() == (b / name).read_bytes()
