"""YouCam Skin Analysis: upload, run the task, poll, and fetch the masks."""
import io
import time

import httpx
import numpy as np
from PIL import Image

from . import config

# Units per SD call by the number of concerns (YouCam price list, 2026-10).
SD_COST = ((4, 9), (8, 12), (12, 14), (16, 16))


def unit_cost(n_concerns):
    return next(cost for most, cost in SD_COST if n_concerns <= most)


class YouCamError(RuntimeError):
    pass


class Analysis:
    def __init__(self, raw, ui, masks, overall, skin_age, file_id=None):
        self.raw = raw          # concern -> raw_score (1-100, higher is healthier)
        self.ui = ui            # concern -> ui_score (boosted for motivation; shown, never measured)
        self.masks = masks      # concern -> alpha in 0..1, same size as the input image
        self.overall = overall
        self.skin_age = skin_age
        self.file_id = file_id  # YouCam keeps the photo 30 days; reused for Fitzpatrick


class YouCam:
    def __init__(self, key=lambda: config.secret('YOUCAM_API_KEY'), base=config.YOUCAM_BASE):
        self._key = key
        self.http = httpx.Client(base_url=base, timeout=60)

    def _headers(self):
        key = self._key()
        if not key:
            raise YouCamError('no YouCam API key configured')
        return {'Authorization': 'Bearer ' + key}

    def _json(self, response, what):
        try:
            body = response.json()
        except ValueError:
            body = {}
        if response.status_code != 200:
            raise YouCamError(f'{what}: HTTP {response.status_code} {body.get("error") or body.get("error_code") or ""}'.strip())
        return body

    def credit(self):
        body = self._json(self.http.get('/s2s/v1.0/client/credit', headers=self._headers()), 'credit')
        return sum(r.get('amount', 0) for r in body.get('results', []))

    def upload(self, jpeg):
        """Send a photo to YouCam's file store; returns the file_id tasks take."""
        files = self._json(self.http.post('/s2s/v2.0/file', headers=self._headers(), json={'files': [
            {'content_type': 'image/jpeg', 'file_name': 'scan.jpg', 'file_size': len(jpeg)}]}), 'file')
        f = files['data']['files'][0]
        put = f['requests'][0]
        r = httpx.put(put['url'], content=jpeg, headers=put['headers'], timeout=60)
        if r.status_code != 200:
            raise YouCamError(f'upload: HTTP {r.status_code}')
        return f['file_id']

    def _task(self, path, body, timeout=120):
        """Start a task and poll it; units are taken only when it succeeds."""
        task_id = self._json(self.http.post(path, headers=self._headers(), json=body), 'task')['data']['task_id']
        deadline = time.monotonic() + timeout
        while True:
            time.sleep(2)
            data = self._json(self.http.get(f'{path}/{task_id}', headers=self._headers()), 'poll')['data']
            if data.get('task_status') == 'success':
                return data
            if data.get('task_status') == 'error':
                raise YouCamError('task failed: ' + str(data.get('error') or 'unknown'))
            if time.monotonic() > deadline:
                raise YouCamError('task timed out')

    def fitzpatrick(self, file_id):
        """Fitzpatrick skin type, 'I' to 'VI' (10 units)."""
        data = self._task('/s2s/v2.0/task/fitzpatrick-scale-analyzer', {'version': '1.0', 'src_file_id': file_id})
        return data['results'].get('fitzpatrick_scale')

    def analyze(self, jpeg, concerns):
        file_id = self.upload(jpeg)
        data = self._task('/s2s/v2.1/task/skin-analysis', {
            'src_file_id': file_id, 'dst_actions': list(concerns),
            'miniserver_args': {'enable_mask_overlay': False}, 'format': 'json'})
        raw, ui, masks, overall, skin_age = {}, {}, {}, None, None
        for out in data['results']['output']:
            kind = out['type']
            if kind == 'all':
                overall = out.get('score')
            elif kind == 'skin_age':
                skin_age = out.get('score')
            elif kind in concerns:
                raw[kind], ui[kind] = out.get('raw_score'), out.get('ui_score')
                if out.get('mask_urls'):
                    png = httpx.get(out['mask_urls'][0], timeout=60).content
                    masks[kind] = np.asarray(Image.open(io.BytesIO(png)).convert('RGBA'))[..., 3].astype(np.float32) / 255
        return Analysis(raw, ui, masks, overall, skin_age, file_id)
