"""Draw the SideProof mark (a woman's face with her hair in a bun, split down the middle: the
pink half had the product, the white half is the control; on the left the hair is filled, on the
right outlined) as the Android launcher icons, the web icons and the favicon. The geometry is
the SVG mark in web/components/ui.tsx and SideProofMark in lib/brand.dart: a 192 x 192 drawing
whose head fills the square from (12, 12) to (180, 180).

    cd app && python3 tool/make_icons.py
"""
import pathlib

from PIL import Image, ImageDraw

APP = pathlib.Path(__file__).resolve().parent.parent
BG = (251, 238, 228, 255)
INK = (43, 30, 37, 255)
HAIR_LIGHT = (255, 248, 241, 255)
TREATED = (242, 163, 187, 255)
CONTROL = (255, 255, 255, 255)
SS = 8


def cubic(p0, p1, p2, p3, n=40):
    return [tuple((1 - t) ** 3 * a + 3 * (1 - t) ** 2 * t * b + 3 * (1 - t) * t ** 2 * c + t ** 3 * d
                  for a, b, c, d in zip(p0, p1, p2, p3)) for t in (i / n for i in range(n + 1))]


def quad(p0, p1, p2, n=24):
    return [tuple((1 - t) ** 2 * a + 2 * (1 - t) * t * b + t ** 2 * c for a, b, c in zip(p0, p1, p2))
            for t in (i / n for i in range(n + 1))]


FACE = (cubic((96, 70), (70, 73), (47, 93), (47, 127)) + cubic((47, 127), (48, 151), (69, 175), (96, 177))
        + cubic((96, 177), (123, 175), (144, 151), (145, 127)) + cubic((145, 127), (145, 93), (122, 73), (96, 70)))
STRANDS = [cubic((101, 19), (112, 22), (118, 31), (115, 44)), cubic((99, 38), (124, 41), (144, 59), (151, 88)),
           cubic((100, 52), (121, 58), (136, 74), (141, 98))]
FEATURES = [quad((60, 100), (73, 93), (87, 98)), quad((105, 98), (119, 93), (132, 100)),       # brows
            quad((64, 113), (75, 120), (86, 113)), quad((106, 113), (117, 120), (128, 113)),     # closed eyes
            quad((90, 141), (96, 145), (102, 141)), quad((84, 154), (96, 162), (108, 154))]      # nose, mouth
LASHES = [((68.4, 115.2), (66.5, 119)), ((72.8, 116.4), (72, 120.5)), ((77.2, 116.4), (78, 120.5)), ((81.6, 115.2), (83.5, 119)),
          ((110.4, 115.2), (108.5, 119)), ((114.8, 116.4), (114, 120.5)), ((119.2, 116.4), (120, 120.5)), ((123.6, 115.2), (125.5, 119))]


def mark(px, share, background=BG, rounded=True):
    """The mark on a px square: the head takes `share` of it, on a cream rounded square or on none."""
    big = px * SS
    im = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if background:
        d.rounded_rectangle((0, 0, big - 1, big - 1), radius=int(big * 0.22) if rounded else 0, fill=background)
    s = big * share / 168
    off = (big - 168 * s) / 2
    pt = lambda p: (off + (p[0] - 12) * s, off + (p[1] - 12) * s)
    box = lambda cx, cy, rx, ry: (pt((cx - rx, cy - ry)), pt((cx + rx, cy + ry)))
    midx = pt((96, 0))[0]
    left = Image.new('L', (big, big), 0)
    ImageDraw.Draw(left).rectangle((0, 0, midx, big), fill=255)

    def half_fill(shape, colour):
        """Fill the left half of a shape drawn on a mask by `shape(draw)`."""
        m = Image.new('L', (big, big), 0)
        shape(ImageDraw.Draw(m))
        im.paste(colour, (0, 0), Image.composite(m, Image.new('L', (big, big), 0), left))

    def stroke(points, w):
        w = max(1, round(w * s))
        d.line([pt(p) for p in points], fill=INK, width=w, joint='curve')
        for p in (points[0], points[-1]):
            x, y = pt(p)
            d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=INK)

    outline = max(1, round(3.4 * s))
    # The bun, behind the head, then the hair: filled on the left, outlined with strands on the right.
    d.ellipse(box(96, 38, 22, 22), fill=HAIR_LIGHT, outline=INK, width=outline)
    half_fill(lambda m: m.ellipse(box(96, 38, 22, 22), fill=255), INK)
    stroke(STRANDS[0], 2.6)
    d.ellipse(box(96, 98, 59, 62), fill=HAIR_LIGHT, outline=INK, width=outline)
    half_fill(lambda m: m.ellipse(box(96, 98, 59, 62), fill=255), INK)
    for strand in STRANDS[1:]:
        stroke(strand, 2.6)
    # The face over the hair, its top edge the hairline; the midline from the hairline to the chin.
    d.polygon([pt(p) for p in FACE], fill=CONTROL)
    half_fill(lambda m: m.polygon([pt(p) for p in FACE], fill=255), TREATED)
    d.line([pt(p) for p in FACE], fill=INK, width=outline, joint='curve')
    d.line([pt((96, 70)), pt((96, 177))], fill=INK, width=outline)
    for f in FEATURES:
        stroke(f, 3)
    for a, b in LASHES:
        stroke((a, b), 2)
    return im.resize((px, px), Image.LANCZOS)


def main():
    res = APP / 'android/app/src/main/res'
    for folder, px in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)):
        mark(px, 0.84).save(res / f'mipmap-{folder}/ic_launcher.png')
    web = APP / 'web'
    targets = [web, APP.parent / 'web' / 'public']
    for base in targets:
        (base / 'icons').mkdir(parents=True, exist_ok=True) if base == web else None
    mark(192, 0.84).save(web / 'icons/Icon-192.png')
    mark(512, 0.84).save(web / 'icons/Icon-512.png')
    mark(192, 0.62, rounded=False).save(web / 'icons/Icon-maskable-192.png')
    mark(512, 0.62, rounded=False).save(web / 'icons/Icon-maskable-512.png')
    mark(32, 0.98, background=None).save(web / 'favicon.png')
    nxt = APP.parent / 'web' / 'public'
    mark(32, 0.98, background=None).save(nxt / 'favicon.png')
    mark(192, 0.84).save(nxt / 'icon-192.png')


if __name__ == '__main__':
    main()
