"""Guitar Quest - draws the app icon (img/guitarquest.ico + PNGs). Needs Pillow. Run: python tools/make_icon.py"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'img'
S = 1024  # drawing size; smaller sizes are scaled down from it


def cubic(p0, p1, p2, p3, n=48):
    pts = []
    for i in range(1, n + 1):
        t = i / n
        a = (1 - t) ** 3
        b = 3 * (1 - t) ** 2 * t
        c = 3 * (1 - t) * t ** 2
        d = t ** 3
        pts.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return pts


def pick_polygon():
    # same guitar-pick path as the logo in index.html: M32 4 C18 4 8 12 8 24 c0 14 14 30 24 36 10-6 24-22 24-36 C56 12 46 4 32 4z
    pts = [(32, 4)]
    pts += cubic((32, 4), (18, 4), (8, 12), (8, 24))
    pts += cubic((8, 24), (8, 38), (22, 54), (32, 60))
    pts += cubic((32, 60), (42, 54), (56, 38), (56, 24))
    pts += cubic((56, 24), (56, 12), (46, 4), (32, 4))
    return pts


def draw():
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.22), fill=(30, 34, 48, 255))
    scale = S * 0.74 / 56  # the pick is 56 units tall
    ox = S / 2 - 32 * scale
    oy = S / 2 - 32 * scale
    tr = lambda p: (ox + p[0] * scale, oy + p[1] * scale)
    d.polygon([tr(p) for p in pick_polygon()], fill=(224, 103, 43, 255))
    w = 3.6 * scale
    for (x0, y0), (x1, y1) in [((22, 26), (42, 26)), ((24, 34), (40, 34)), ((28, 42), (36, 42))]:
        a, b = tr((x0, y0)), tr((x1, y1))
        d.line([a, b], fill=(255, 255, 255, 235), width=int(w))
        for c in (a, b):
            d.ellipse([c[0] - w / 2, c[1] - w / 2, c[0] + w / 2, c[1] + w / 2], fill=(255, 255, 255, 235))
    return img


def main():
    OUT.mkdir(exist_ok=True)
    big = draw()
    sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    big.resize((256, 256), Image.LANCZOS).save(OUT / 'guitarquest.ico', sizes=[(s, s) for s in sizes])
    for s in (192, 512):
        big.resize((s, s), Image.LANCZOS).save(OUT / ('icon-%d.png' % s))
    print('written:', OUT / 'guitarquest.ico')


if __name__ == '__main__':
    main()
