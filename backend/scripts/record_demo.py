"""Record the demo trial that the app opens without spending units.

A full HalfFace run on YouCam's own sample face, through the real API: real YouCam Skin
Analysis, the real agent, the real trial math. Two things are staged: the "product" is a
digital matte filter on the treated half (highlights squashed, wearing off over the day), and
the clock is moved forward between scans. Only numbers are saved, to demo/demo_trial.json.
About 55 YouCam units.

    cd backend
    YOUCAM_API_KEY_FILE=... GEMINI_API_KEY_FILE=... .venv/bin/python scripts/record_demo.py --check
    YOUCAM_API_KEY_FILE=... GEMINI_API_KEY_FILE=... .venv/bin/python scripts/record_demo.py

--check runs only the free photo checks on every photo the run would send.
"""
import io
import json
import os
import pathlib
import sys
import tempfile
import time

os.environ['HALFFACE_DB'] = str(pathlib.Path(tempfile.mkdtemp()) / 'demo.db')
os.environ.setdefault('HALFFACE_LLM', 'gemini')
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import httpx
import numpy as np
from fastapi.testclient import TestClient
from PIL import Image, ImageEnhance

from halfface import api, db, demo, face

SAMPLE = 'https://plugins-media.makeupar.com/strapi/assets/skin_analysis_01_5b5defd339.png'
PRODUCT = 'Matte Gel'
LISTING = 'Oil-free gel moisturizer. Controls shine for up to 8 hours. Light, non-greasy hydration.'
# Hours after the product went on -> how much of the shine above the knee is left.
MATTE = ((1, 0.35), (4, 0.5), (8, 0.75))
KNEE = 0.6
HEADERS = {'X-Device': 'demo-recorder-000000'}


class Clock:
    """Stands in for the time module in api and db, so hours pass between scans."""
    def __init__(self):
        self.now = time.time()

    def time(self):
        return self.now


def matte(img, region, slope):
    a = np.asarray(img, np.float32) / 255
    squashed = np.where(a > KNEE, KNEE + (a - KNEE) * slope, a)
    a = np.where(region[..., None], squashed, a)
    return Image.fromarray((a * 255).round().astype(np.uint8))


def jpeg_bytes(img):
    buf = io.BytesIO()
    img.save(buf, 'JPEG', quality=95)
    return buf.getvalue()


def photos(orig, treated):
    """(label, minutes after the previous photo, image) in run order. treated: the image half."""
    _, found = face.find(orig)
    region = getattr(found, treated)
    yield 'baseline 1', 0, orig
    yield 'baseline 2', 5, ImageEnhance.Brightness(orig).enhance(1.02)
    last = 0
    for hours, slope in MATTE:
        yield f'{hours} h', (hours * 60 - last), matte(orig, region, slope)
        last = hours * 60


def main():
    orig = face.prepare(httpx.get(SAMPLE, timeout=60).content)
    if '--check' in sys.argv:
        for treated in ('img_left', 'img_right'):
            for label, _, img in photos(orig, treated):
                _, issues, nums = face.check(face.prepare(jpeg_bytes(img)))
                print(f'{treated:9} {label:10} {issues or "ok"} {nums}')
        return

    clock = Clock()
    api.time = db.time = clock
    with TestClient(api.app) as client:
        r = client.post('/api/trials', headers=HEADERS, data={'product': PRODUCT, 'listing': LISTING})
        r.raise_for_status()
        t = r.json()
        tid, treated = t['id'], t['treated_image_side']
        print('plan:', json.dumps(t['plan'], indent=1))
        print('treated image half:', treated)
        for label, minutes, img in photos(orig, treated):
            clock.now += minutes * 60
            r = client.post(f'/api/trials/{tid}/scans', headers=HEADERS,
                            files={'photo': ('scan.jpg', jpeg_bytes(img), 'image/jpeg')})
            r.raise_for_status()
            t = r.json()
            if 'retake' in t:
                sys.exit(f'{label}: photo refused: {t["retake"]}')
            effects = {c: (s.get('state'), s.get('verdict'), s.get('effect'), s.get('noise'))
                       for c, s in t['stats']['concerns'].items()}
            print(f'{label}: {effects}')
            decision = client.get(f'/api/trials/{tid}', headers=HEADERS).json()['decision'] or {}    # after the agent ran
            print('   agent:', decision.get('action'), '-', decision.get('message') or decision.get('error'))
            if label == 'baseline 2':
                client.post(f'/api/trials/{tid}/start', headers=HEADERS).raise_for_status()
        r = client.post(f'/api/trials/{tid}/verdict', headers=HEADERS)
        r.raise_for_status()
        print('verdict:', json.dumps(r.json()['verdict'], indent=1))
    con = db.connect()
    demo.export(con, tid)
    con.close()
    print('saved', demo.DEMO_FILE)


if __name__ == '__main__':
    main()
