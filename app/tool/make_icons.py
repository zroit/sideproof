"""Draw the SideProof mark (a disc split down the middle: the filled half had the product, the
outlined half is the control) as the Android launcher icons, the web icons and the favicon.
The geometry matches SideProofMark in lib/brand.dart.

    cd app && python3 tool/make_icons.py
"""
import pathlib

from PIL import Image, ImageDraw

APP = pathlib.Path(__file__).resolve().parent.parent
PORCELAIN = (242, 244, 243, 255)
INK = (21, 35, 42, 255)
COBALT = (47, 91, 234, 255)
SS = 8  # supersampling, for smooth edges


def mark(px, mark_share, background=PORCELAIN, rounded=True):
    big = px * SS
    im = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if background:
        radius = int(big * 0.22) if rounded else 0
        d.rounded_rectangle((0, 0, big - 1, big - 1), radius=radius, fill=background)
    s = big * mark_share
    w = max(1, round(s * 0.09))
    gap = s * 0.08
    R = s / 2                     # both halves share the same outer radius
    cx = cy = big / 2
    lx = cx - gap / 2
    d.pieslice((lx - R, cy - R, lx + R, cy + R), 90, 270, fill=COBALT)
    rx = cx + gap / 2
    d.arc((rx - R, cy - R, rx + R, cy + R), 270, 90, fill=INK, width=w)   # PIL strokes inward from the box
    d.rectangle((rx, cy - R, rx + w, cy + R), fill=INK)
    return im.resize((px, px), Image.LANCZOS)


def main():
    res = APP / 'android/app/src/main/res'
    for folder, px in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)):
        mark(px, 0.62).save(res / f'mipmap-{folder}/ic_launcher.png')
    web = APP / 'web'
    mark(192, 0.62).save(web / 'icons/Icon-192.png')
    mark(512, 0.62).save(web / 'icons/Icon-512.png')
    # Maskable icons get cropped to a circle: full-bleed background, mark inside the safe zone.
    mark(192, 0.5, rounded=False).save(web / 'icons/Icon-maskable-192.png')
    mark(512, 0.5, rounded=False).save(web / 'icons/Icon-maskable-512.png')
    mark(32, 0.9, background=None).save(web / 'favicon.png')


if __name__ == '__main__':
    main()
