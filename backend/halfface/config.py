"""Settings from the environment. Secrets are read on use, so a rotated key needs no restart."""
import os
import pathlib

HERE = pathlib.Path(__file__).resolve().parent

YOUCAM_BASE = os.environ.get('YOUCAM_BASE', 'https://yce-api-01.makeupar.com')
DB_PATH = os.environ.get('HALFFACE_DB', str(HERE.parent / 'halfface.db'))
FACE_MODEL = os.environ.get('HALFFACE_FACE_MODEL', str(HERE.parent / 'models' / 'face_landmarker.task'))


def secret(name):
    """NAME from the environment, or the contents of the file named by NAME_FILE."""
    value = os.environ.get(name)
    if value:
        return value.strip()
    path = os.environ.get(name + '_FILE')
    if path and pathlib.Path(path).is_file():
        return pathlib.Path(path).read_text().strip() or None
    return None
