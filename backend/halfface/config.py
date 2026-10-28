"""Settings from the environment. Secrets are read on use, so a rotated key needs no restart."""
import os
import pathlib
import re

HERE = pathlib.Path(__file__).resolve().parent

YOUCAM_BASE = os.environ.get('YOUCAM_BASE', 'https://yce-api-01.makeupar.com')
DB_PATH = os.environ.get('HALFFACE_DB', str(HERE.parent / 'halfface.db'))
FACE_MODEL = os.environ.get('HALFFACE_FACE_MODEL', str(HERE.parent / 'models' / 'face_landmarker.task'))
ENV_LINE = re.compile(r'(?:export\s+)?([A-Z][A-Z0-9_]*)\s*=(.*)')


def secret(name):
    """NAME from the environment, or from the file named by NAME_FILE. The file holds either
    the bare value or NAME=value lines, so one .env file can serve several keys."""
    value = os.environ.get(name)
    if value:
        return value.strip()
    path = os.environ.get(name + '_FILE')
    if not (path and pathlib.Path(path).is_file()):
        return None
    text = pathlib.Path(path).read_text().strip()
    lines = text.splitlines()
    for line in lines:
        m = ENV_LINE.match(line.strip())
        if m and m[1] == name:
            return m[2].strip().strip('"\'') or None
    if len(lines) == 1 and not ENV_LINE.match(text):
        return text
    return None
