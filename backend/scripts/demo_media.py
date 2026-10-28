"""The pictures for the demo trial: YouCam's own sample face as the baseline, the same face at
8 h with the digital matte filter on the treated half, YouCam's masks on both, and the claims'
promise from YouCam AI Skin Simulation. Saved to demo/media/ (about 22 units). The demo
trial's numbers come from record_demo.py; this adds what it looked like.

    YOUCAM_API_KEY_FILE=... .venv/bin/python scripts/demo_media.py
"""
import io
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
import httpx
from PIL import Image

from sideproof import face
from sideproof.api import PROMISE_STRENGTH
from sideproof.youcam import YouCam
from scripts.record_demo import MATTE, SAMPLE, jpeg_bytes, matte

OUT = pathlib.Path(__file__).resolve().parent.parent / 'demo' / 'media'
TREATED = 'img_right'          # the recorded demo trial's treated half
CONCERNS = ['oiliness', 'moisture']


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    yc = YouCam()
    orig = face.prepare(httpx.get(SAMPLE, timeout=60).content)
    _, found = face.find(orig)
    late = matte(orig, getattr(found, TREATED), MATTE[-1][1])
    manifest = {'treated': TREATED, 'midline': found.midline(), 'photos': {}, 'overlays': {}, 'sides': {}}
    for name, img in (('baseline', orig), ('latest', late)):
        result = yc.analyze(jpeg_bytes(img), CONCERNS)
        manifest['sides'][name] = found.measure(result.masks)
        small = img.copy()
        small.thumbnail((900, 900))
        small.save(OUT / f'{name}.jpg', quality=88)
        manifest['photos'][name] = f'{name}.jpg'
        for concern, url in face.overlays(result.masks).items():
            import base64
            (OUT / f'{name}-{concern}.png').write_bytes(base64.b64decode(url.split(',', 1)[1]))
            manifest['overlays'].setdefault(name, {})[concern] = f'{name}-{concern}.png'
        print(name, manifest['sides'][name])
    promised = yc.simulate(jpeg_bytes(orig), {'oiliness': PROMISE_STRENGTH})
    im = Image.open(io.BytesIO(promised)).convert('RGB')
    im.thumbnail((900, 900))
    im.save(OUT / 'promise.jpg', quality=88)
    manifest['photos']['promise'] = 'promise.jpg'
    manifest['promise_concerns'] = ['oiliness']
    (OUT / 'manifest.json').write_text(json.dumps(manifest, indent=1))
    print('saved', OUT)


if __name__ == '__main__':
    main()
