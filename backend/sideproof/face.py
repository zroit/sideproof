"""Face geometry from MediaPipe landmarks: the midline, the two halves, the photo checks,
and each skin mask measured per half.

Image sides: photos are taken unmirrored, so the image's left is the person's right.
"""
import io
import threading

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps

from . import config

# Landmarks on the face's vertical midline, forehead to chin.
MIDLINE = [10, 151, 9, 8, 168, 6, 197, 195, 5, 4, 1, 19, 94, 2, 164, 0, 11, 12, 13, 14, 15, 16, 17, 18, 200, 199, 175, 152]
EDGE_L, EDGE_R, NOSE_TIP, EYE_L, EYE_R = 234, 454, 1, 33, 263

MAX_SIDE = 2048       # YouCam takes up to 2560; smaller is faster to send
MIN_SHORT = 480       # YouCam SD minimum

# What a person is told when a photo can't be measured fairly. No units are spent on these.
ISSUES = {
    'no_face': 'No face found. Face the camera, hair off your face.',
    'many_faces': 'Only one face in the photo, please.',
    'too_far': 'Come closer: your face should fill most of the frame.',
    'turned': 'Look straight at the camera; your head is turned.',
    'tilted': 'Keep your head level.',
    'uneven_light': 'One side of your face is lit more than the other. Face the light.',
    'too_dark': 'Too dark. Face a window or a bright light.',
    'too_bright': 'Too bright: move out of direct light.',
    'blurry': 'The photo is blurry. Hold still.',
}

_lock = threading.Lock()
_detector = None


def _landmarker():
    global _detector
    if _detector is None:
        from mediapipe.tasks.python import BaseOptions, vision
        opts = vision.FaceLandmarkerOptions(base_options=BaseOptions(model_asset_path=config.FACE_MODEL), num_faces=2)
        _detector = vision.FaceLandmarker.create_from_options(opts)
    return _detector


def prepare(data):
    """Phone photo bytes -> upright RGB image within YouCam's size limits."""
    img = ImageOps.exif_transpose(Image.open(io.BytesIO(data))).convert('RGB')
    scale = MAX_SIDE / max(img.size)
    if scale < 1:
        img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    if min(img.size) < MIN_SHORT:
        raise ValueError(f'photo too small: the short side must be at least {MIN_SHORT} px')
    return img


def jpeg(img):
    buf = io.BytesIO()
    img.save(buf, 'JPEG', quality=92)
    return buf.getvalue()


def _hull(points):
    pts = sorted(map(tuple, points))

    def chain(seq):
        out = []
        for p in seq:
            while len(out) >= 2 and (out[-1][0] - out[-2][0]) * (p[1] - out[-2][1]) - (out[-1][1] - out[-2][1]) * (p[0] - out[-2][0]) <= 0:
                out.pop()
            out.append(p)
        return out

    lower, upper = chain(pts), chain(reversed(pts))
    return lower[:-1] + upper[:-1]


class Face:
    def __init__(self, points, size):
        self.pts = points
        self.w, self.h = size
        self.a, self.b = np.polyfit(points[MIDLINE, 1], points[MIDLINE, 0], 1)    # midline: x = a*y + b

        # The landmarks stop mid-forehead; the masks go higher, so stretch the hull upward.
        hull = np.array(_hull(points), float)
        cy = points[:, 1].mean()
        up = hull[:, 1] < cy
        hull[up, 1] = cy + (hull[up, 1] - cy) * 1.25
        region = Image.new('L', size, 0)
        ImageDraw.Draw(region).polygon([tuple(p) for p in hull], fill=1)
        region = np.asarray(region, bool)
        yy, xx = np.mgrid[0:self.h, 0:self.w]
        left = xx < self.a * yy + self.b
        self.img_left = region & left
        self.img_right = region & ~left

    def side(self, values):
        """Mean of a per-pixel array over each half: {'img_left': x, 'img_right': y}."""
        return {'img_left': float(values[self.img_left].mean()), 'img_right': float(values[self.img_right].mean())}

    def midline(self):
        """The midline's ends, top and bottom of the photo, as fractions of width and height."""
        return [[round(self.b / self.w, 4), 0.0], [round((self.a * self.h + self.b) / self.w, 4), 1.0]]

    def measure(self, masks):
        """Each concern's mask as percent coverage per half."""
        out = {}
        for concern, alpha in masks.items():
            if alpha.shape != (self.h, self.w):
                alpha = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8)).resize((self.w, self.h)), np.float32) / 255
            out[concern] = {k: round(v * 100, 3) for k, v in self.side(alpha).items()}
        return out


def find(img):
    """(face count, Face or None)."""
    import mediapipe as mp
    arr = np.ascontiguousarray(np.asarray(img))
    with _lock:
        res = _landmarker().detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=arr))
    faces = res.face_landmarks or []
    if len(faces) != 1:
        return len(faces), None
    pts = np.array([(p.x * img.width, p.y * img.height) for p in faces[0]])
    return 1, Face(pts, img.size)


def check(img):
    """Measure the photo before spending units. Returns (Face or None, issues, numbers)."""
    count, face = find(img)
    if count == 0:
        return None, ['no_face'], {}
    if count > 1:
        return None, ['many_faces'], {}
    p = face.pts
    width = float(np.linalg.norm(p[EDGE_R] - p[EDGE_L]))
    yaw = float((p[NOSE_TIP, 0] - p[EDGE_L, 0]) / (p[EDGE_R, 0] - p[EDGE_L, 0]))
    roll = float(np.degrees(np.arctan2(p[EYE_R, 1] - p[EYE_L, 1], p[EYE_R, 0] - p[EYE_L, 0])))
    luma = np.asarray(img.convert('L'), np.float32)
    lit = {k: float(np.median(luma[m])) for k, m in (('img_left', face.img_left), ('img_right', face.img_right))}
    # Sharpness on the inner face only (eyes to mouth), so hair and background edges don't count.
    x0, x1 = p[:, 0].min(), p[:, 0].max()
    y0, y1 = p[:, 1].min(), p[:, 1].max()
    fw, fh = x1 - x0, y1 - y0
    crop = img.convert('L').crop((int(x0 + 0.2 * fw), int(y0 + 0.25 * fh), int(x1 - 0.2 * fw), int(y1 - 0.2 * fh)))
    crop = crop.resize((256, max(1, round(256 * crop.height / crop.width))))
    edges = np.asarray(crop.filter(ImageFilter.Kernel((3, 3), (0, 1, 0, 1, -4, 1, 0, 1, 0), 1, 128)), np.float32)
    sharp = float(edges.var())
    nums = {'face_width': round(width / img.width, 3), 'yaw': round(yaw, 3), 'roll': round(roll, 1),
            'light_left': round(lit['img_left'], 1), 'light_right': round(lit['img_right'], 1), 'sharpness': round(sharp, 1)}

    issues = []
    if width < 0.30 * img.width:
        issues.append('too_far')
    if abs(yaw - 0.5) > 0.08:
        issues.append('turned')
    if abs(roll) > 7:
        issues.append('tilted')
    lo, hi = sorted(lit.values())
    if hi > 1.15 * max(lo, 1):
        issues.append('uneven_light')
    if hi < 70:
        issues.append('too_dark')
    if lo > 215:
        issues.append('too_bright')
    if sharp < 45:      # sample face 172, Gaussian blur r2 35; recheck on real phone photos
        issues.append('blurry')
    return face, issues, nums


# One colour per concern for the overlays the app draws on the person's own photo.
OVERLAY_COLOURS = {'oiliness': (255, 196, 0), 'moisture': (0, 168, 232), 'radiance': (255, 140, 60), 'redness': (232, 48, 72),
                   'acne': (214, 40, 120), 'pore': (140, 90, 220), 'texture': (120, 120, 120), 'age_spot': (150, 90, 40),
                   'wrinkle': (40, 160, 120), 'dark_circle_v2': (70, 70, 160), 'eye_bag': (90, 120, 180)}


def overlays(masks, width=480):
    """Each concern's mask as a small transparent PNG (data URL) in its colour, for the app to lay
    over the photo it already has. Sent once with the scan's answer and never stored."""
    import base64
    out = {}
    for concern, alpha in masks.items():
        h, w = alpha.shape
        size = (width, max(1, round(h * width / w)))
        a = Image.fromarray((np.clip(alpha, 0, 1) * 115).astype(np.uint8)).resize(size, Image.BILINEAR)
        rgb = Image.new('RGB', size, OVERLAY_COLOURS.get(concern, (47, 91, 234)))
        rgb.putalpha(a)
        buf = io.BytesIO()
        rgb.save(buf, 'PNG', optimize=True)
        out[concern] = 'data:image/png;base64,' + base64.b64encode(buf.getvalue()).decode()
    return out


def data_url(jpeg_bytes, longest=1080):
    """A JPEG as a data URL, scaled down so its long side is at most `longest`."""
    import base64
    im = Image.open(io.BytesIO(jpeg_bytes)).convert('RGB')
    im.thumbnail((longest, longest))
    buf = io.BytesIO()
    im.save(buf, 'JPEG', quality=86)
    return 'data:image/jpeg;base64,' + base64.b64encode(buf.getvalue()).decode()
