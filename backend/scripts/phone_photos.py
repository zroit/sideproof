"""Photos for a staged trial on a phone, picked from the gallery instead of taken.

YouCam's own sample face, as in the demo trial. The "product" is the same digital matte filter
as record_demo.py, on one half of the photo; baseline 2 is the same photo 2% brighter, so the
noise is not zero. The server picks the treated half at random, so there is one set per half:
use the set named after the half the app shades. A side-lit copy shows the light check refusing
a photo, which costs no units.

    cd backend
    .venv/bin/python scripts/phone_photos.py OUT_DIR

Every photo goes through the app's own free photo checks first; nothing is sent to YouCam.
"""
import io
import os
import pathlib
import sys
import time

import httpx
import numpy as np
from PIL import Image, ImageEnhance

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from sideproof import face

SAMPLE = 'https://plugins-media.makeupar.com/strapi/assets/skin_analysis_01_5b5defd339.png'
# As in record_demo.py: hours after the product went on -> how much of the shine above the knee is left.
MATTE = ((1, 0.35), (4, 0.5), (8, 0.75))
KNEE = 0.6
SETS = {'img_left': 'shaded-left', 'img_right': 'shaded-right'}

README = """SideProof: photos for a staged trial, picked from the phone's gallery

The face is YouCam's own sample face (skin_analysis_01, from the YouCam API docs). The
"product" is a digital matte filter on one half of the photo, made by a script
(backend/scripts/phone_photos.py in the repo). Baseline 2 is the same photo 2% brighter.

1. Start a trial and send 1-baseline and 2-baseline (from either folder).
2. The app shades one half of the photo. Use the folder named after that half:
   shaded-left or shaded-right.
3. Start the trial, then send 3, 4 and 5 from that folder, then Finish.

0-side-light.jpg is lit from one side: the app refuses it before anything is sent to YouCam,
so it costs no units.
"""


def matte(img, region, slope):
    a = np.asarray(img, np.float32) / 255
    squashed = np.where(a > KNEE, KNEE + (a - KNEE) * slope, a)
    a = np.where(region[..., None], squashed, a)
    return Image.fromarray((a * 255).round().astype(np.uint8))


def side_lit(img):
    """The left of the photo darker, as with a window to one side."""
    a = np.asarray(img, np.float32) * np.linspace(0.3, 1.0, img.width)[None, :, None]
    return Image.fromarray(a.clip(0, 255).astype(np.uint8))


def jpeg_bytes(img):
    buf = io.BytesIO()
    img.save(buf, 'JPEG', quality=95)
    return buf.getvalue()


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    out = pathlib.Path(sys.argv[1])
    orig = face.prepare(httpx.get(SAMPLE, timeout=60).content)
    _, found = face.find(orig)
    files = [(out / '0-side-light.jpg', side_lit(orig))]
    for treated, folder in SETS.items():
        region = getattr(found, treated)
        shots = [('1-baseline', orig), ('2-baseline', ImageEnhance.Brightness(orig).enhance(1.02))]
        shots += [(f'{i + 3}-scan-{hours}h', matte(orig, region, slope)) for i, (hours, slope) in enumerate(MATTE)]
        files += [(out / folder / f'{label}.jpg', img) for label, img in shots]

    stamp = time.time() - len(files) * 60     # a minute apart, so a gallery sorted by date keeps the order
    for i, (path, img) in enumerate(files):
        data = jpeg_bytes(img)
        _, issues, _ = face.check(face.prepare(data))
        print(f'{path.relative_to(out)}: {", ".join(issues) or "ok"}')
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        os.utime(path, (stamp + i * 60, stamp + i * 60))
    (out / 'README.txt').write_text(README)


if __name__ == '__main__':
    main()
