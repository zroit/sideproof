"""Draw the SideProof mark (a face split down the middle: the filled half had the product, the
outlined half is the control, a closed eye on each) as the Android launcher icons, the web
icons and the favicon. The geometry is the 32x32 SVG mark in web/components/ui.tsx and
SideProofMark in lib/brand.dart.

    cd app && python3 tool/make_icons.py
"""
import pathlib

from PIL import Image, ImageDraw

APP = pathlib.Path(__file__).resolve().parent.parent
CREAM = (251, 246, 241, 255)
INK = (43, 30, 37, 255)
GRADIENT = ((244, 143, 177), (227, 80, 126), (180, 103, 224))   # the mark's fill, corner to corner
SS = 8


def cubic(p0, p1, p2, p3, n=40):
    return [tuple((1 - t) ** 3 * a + 3 * (1 - t) ** 2 * t * b + 3 * (1 - t) * t ** 2 * c + t ** 3 * d
                  for a, b, c, d in zip(p0, p1, p2, p3)) for t in (i / n for i in range(n + 1))]


LEFT = [(15, 2.6)] + cubic((15, 2.6), (8.6, 3), (4.8, 8.3), (4.8, 14.6)) + cubic((4.8, 14.6), (4.8, 21.6), (9.2, 27.6), (15, 29.5))
RIGHT = [(17.2, 3.9)] + cubic((17.2, 3.9), (22.6, 4.8), (25.8, 9.3), (25.8, 14.6)) + cubic((25.8, 14.6), (25.8, 20.6), (22.3, 25.6), (17.2, 27.8)) + [(17.2, 3.9)]
EYE_L = cubic((9.6, 13.4), (10.4, 14.2), (11.8, 14.2), (12.6, 13.4), 16)
EYE_R = cubic((19.6, 13.4), (20.4, 14.2), (21.8, 14.2), (22.6, 13.4), 16)


def gradient(size):
    """A diagonal three-stop gradient, top left to bottom right."""
    g = Image.new('RGB', (size, size))
    px = g.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            a, b, k = (GRADIENT[0], GRADIENT[1], t / 0.55) if t < 0.55 else (GRADIENT[1], GRADIENT[2], (t - 0.55) / 0.45)
            px[x, y] = tuple(round(a[i] + (b[i] - a[i]) * k) for i in range(3))
    return g


def mark(px, share, background=CREAM, rounded=True, white=False):
    big = px * SS
    im = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if background:
        d.rounded_rectangle((0, 0, big - 1, big - 1), radius=int(big * 0.22) if rounded else 0, fill=background)
    s = big * share / 32
    off = (big - 32 * s) / 2
    pt = lambda p: (off + p[0] * s, off + p[1] * s)
    mask = Image.new('L', (big, big), 0)
    ImageDraw.Draw(mask).polygon([pt(p) for p in LEFT], fill=255)
    fill = Image.new('RGB', (big, big), (255, 255, 255)) if white else gradient(big)
    im.paste(fill, (0, 0), mask)
    line = (255, 255, 255, 255) if white else INK
    w = max(1, round(2.4 * s))
    d.line([pt(p) for p in RIGHT], fill=line, width=w, joint='curve')
    for p in (RIGHT[0], RIGHT[-2]):
        x, y = pt(p)
        d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=line)
    ew = max(1, round(1.6 * s))
    d.line([pt(p) for p in EYE_L], fill=(227, 80, 126, 255) if white else CREAM, width=ew, joint='curve')
    d.line([pt(p) for p in EYE_R], fill=line, width=ew, joint='curve')
    return im.resize((px, px), Image.LANCZOS)


def main():
    res = APP / 'android/app/src/main/res'
    for folder, px in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)):
        mark(px, 0.7).save(res / f'mipmap-{folder}/ic_launcher.png')
    web = APP / 'web'
    targets = [web, APP.parent / 'web' / 'public']
    for base in targets:
        (base / 'icons').mkdir(parents=True, exist_ok=True) if base == web else None
    mark(192, 0.7).save(web / 'icons/Icon-192.png')
    mark(512, 0.7).save(web / 'icons/Icon-512.png')
    mark(192, 0.56, rounded=False).save(web / 'icons/Icon-maskable-192.png')
    mark(512, 0.56, rounded=False).save(web / 'icons/Icon-maskable-512.png')
    mark(32, 0.98, background=None).save(web / 'favicon.png')
    nxt = APP.parent / 'web' / 'public'
    mark(32, 0.98, background=None).save(nxt / 'favicon.png')
    mark(192, 0.7).save(nxt / 'icon-192.png')


if __name__ == '__main__':
    main()
