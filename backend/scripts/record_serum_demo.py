"""Record the second demo trial: a young face (one of YouCam's own sample images) testing a
made-up brightening serum. (Spot and redness simulations barely change this flawless sample
face; radiance shows.)

It runs through the real API: the agent plans, the photos pass the checks, YouCam AI Skin
Analysis measures every scan and returns its maps, and YouCam AI Skin Simulation draws the
claims' promise. Two things are staged and said so in the app: the clock moves forward between
scans, and the "product effect" on the treated half is YouCam AI Skin Simulation at rising
strength at each scan, blended in along the midline. About 70 units.

    SIDEPROOF_LLM=claude-cli YOUCAM_API_KEY_FILE=... .venv/bin/python scripts/record_serum_demo.py
"""
import base64
import io
import json
import os
import pathlib
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent.parent
RECORDING_DB = HERE / 'demo-recording-serum.db'
RECORDING_DB.unlink(missing_ok=True)
os.environ['SIDEPROOF_DB'] = str(RECORDING_DB)
os.environ.setdefault('SIDEPROOF_LLM', 'claude-cli')
sys.path.insert(0, str(HERE))

import httpx
from fastapi.testclient import TestClient
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

from sideproof import api, db, demo, face

SAMPLE = 'https://plugins-media.makeupar.com/strapi/assets/sample_Image_1_202b6bf6e6.jpg'
PRODUCT = 'Glow Serum'
LISTING = ('Brightening serum for dull, tired-looking skin. Visibly brighter, more radiant skin in 7 days. '
           'Evens out dullness. With niacinamide and licorice root.')
EFFECT = ((0.15, 0.3), (0.5, 0.6), (1.0, 0.85))  # share of the planned trial -> simulation strength on the treated half
CACHE = HERE / 'demo-recording-cache'           # simulations kept between runs, so a retry costs nothing
HEADERS = {'X-Device': 'demo-recorder-serum-01'}


class Clock:
    def __init__(self):
        self.now = time.time()

    def time(self):
        return self.now


def jpeg(img):
    buf = io.BytesIO()
    img.save(buf, 'JPEG', quality=95)
    return buf.getvalue()


def blend_half(orig, sim, midline, treated):
    """The treated half from `sim`, the control half from `orig`, feathered along the midline."""
    w, h = orig.size
    (x0, _), (x1, _) = midline
    mask = Image.new('L', (w, h), 0)
    poly = [(x0 * w, 0), (w, 0), (w, h), (x1 * w, h)] if treated == 'img_right' else [(0, 0), (x0 * w, 0), (x1 * w, h), (0, h)]
    ImageDraw.Draw(mask).polygon(poly, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(6))
    return Image.composite(sim.resize(orig.size), orig, mask)


def data_bytes(url):
    return base64.b64decode(url.split(',', 1)[1])


def effect_images(orig, concerns):
    """The simulated faces for each scan day, from the cache when a run already made them."""
    CACHE.mkdir(exist_ok=True)
    out = []
    for _, strength in EFFECT:
        path = CACHE / f'sim-{"-".join(sorted(concerns))}-{strength}.jpg'
        if not path.exists():
            path.write_bytes(api.youcam.simulate(jpeg(orig), {api.SIMULATE[c]: strength for c in concerns}))
        out.append(Image.open(path).convert('RGB'))
    return out


def main():
    orig = face.prepare(httpx.get(SAMPLE, timeout=60).content)
    sims = effect_images(orig, ['radiance'])
    clock = Clock()
    api.time = db.time = clock
    with TestClient(api.app) as client:
        r = client.post('/api/trials', headers=HEADERS, data={'product': PRODUCT, 'listing': LISTING})
        r.raise_for_status()
        t = r.json()
        tid, treated = t['id'], t['treated_image_side']
        print('plan:', t['plan']['concerns'], t['plan']['days'], 'days;', t['plan']['summary'])
        concerns = [c for c in t['plan']['concerns'] if c in api.SIMULATE]
        media = {}
        for i, img in enumerate((orig, ImageEnhance.Brightness(orig).enhance(1.02))):
            clock.now += 300 if i else 0
            r = client.post(f'/api/trials/{tid}/scans', headers=HEADERS, files={'photo': ('b.jpg', jpeg(img), 'image/jpeg')})
            r.raise_for_status()
            if 'retake' in r.json():
                sys.exit(f'baseline refused: {r.json()["retake"]}')
            media.setdefault('baseline', r.json()['media'])
        midline = media['baseline']['midline']
        p = client.post(f'/api/trials/{tid}/promise', headers=HEADERS, files={'photo': ('b.jpg', jpeg(orig), 'image/jpeg')})
        p.raise_for_status()
        promise = p.json()
        client.post(f'/api/trials/{tid}/start', headers=HEADERS).raise_for_status()
        start = clock.now
        latest = None
        for (share, _), sim in zip(EFFECT, sims):
            day = round(t['plan']['days'] * share, 2)
            img = blend_half(orig, sim, midline, treated)
            _, issues, _ = face.check(img)
            if issues:
                sys.exit(f'day {day} photo would be refused: {issues}')
            clock.now = start + day * 86400
            r = client.post(f'/api/trials/{tid}/scans', headers=HEADERS, files={'photo': ('s.jpg', jpeg(img), 'image/jpeg')})
            r.raise_for_status()
            media['latest'], latest = r.json()['media'], img
            stats = r.json()['stats']['concerns']
            print(f'day {day}:', {c: (s.get('verdict'), s.get('effect'), s.get('threshold')) for c, s in stats.items()})
            print('   agent:', (client.get(f'/api/trials/{tid}', headers=HEADERS).json()['decision'] or {}).get('message'))
        r = client.post(f'/api/trials/{tid}/verdict', headers=HEADERS)
        r.raise_for_status()
        print('verdict:', json.dumps(r.json()['verdict'])[:600])
    con = db.connect()
    demo.export(con, tid, demo.DEMO_DIR / 'serum_trial.json')
    con.close()

    out = demo.DEMO_DIR / 'media' / tid
    out.mkdir(parents=True, exist_ok=True)
    manifest = {'treated': treated, 'midline': midline, 'span': media['baseline'].get('span'), 'photos': {}, 'overlays': {}, 'promise_concerns': promise['concerns']}
    for name, img in (('baseline', orig), ('latest', latest)):
        small = img.copy()
        small.thumbnail((900, 900))
        small.save(out / f'{name}.jpg', quality=88)
        manifest['photos'][name] = f'{name}.jpg'
        for concern, url in media[name]['overlays'].items():
            (out / f'{name}-{concern}.png').write_bytes(data_bytes(url))
            manifest['overlays'].setdefault(name, {})[concern] = f'{name}-{concern}.png'
    Image.open(io.BytesIO(data_bytes(promise['image']))).convert('RGB').save(out / 'promise.jpg', quality=88)
    manifest['photos']['promise'] = 'promise.jpg'
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=1))
    RECORDING_DB.unlink(missing_ok=True)
    print('saved', tid, '(the simulation cache in demo-recording-cache/ can go)')


if __name__ == '__main__':
    main()
