import json
import os
import logging
from PySide6.QtCore import QStandardPaths

logger = logging.getLogger(__name__)

def _get_templates_path():
    config_dir = QStandardPaths.writableLocation(QStandardPaths.AppConfigLocation)
    if not config_dir:
        config_dir = os.path.expanduser("~/.config/TagQt")
    else:
        config_dir = os.path.join(config_dir, "TagQt")
    return os.path.join(config_dir, "rename_templates.json")

TEMPLATES_FILE = _get_templates_path()


def ensure_config_dir():
    config_dir = os.path.dirname(TEMPLATES_FILE)
    if not os.path.exists(config_dir):
        os.makedirs(config_dir)


def save_template(name, pattern):
    ensure_config_dir()
    templates = load_templates()
    templates[name] = pattern
    with open(TEMPLATES_FILE, 'w') as f:
        json.dump(templates, f, indent=2)


def load_templates():
    if os.path.exists(TEMPLATES_FILE):
        try:
            with open(TEMPLATES_FILE, 'r') as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError) as e:
            logger.warning(f"Warning: Could not load templates file: {e}")
    return {
        "Artist - Title": "%artist% - %title%",
        "Track Title": "%track% %title%",
        "Album - Track Title": "%album% - %track% %title%"
    }


def delete_template(name):
    templates = load_templates()
    if name in templates:
        del templates[name]
        ensure_config_dir()
        with open(TEMPLATES_FILE, 'w') as f:
            json.dump(templates, f, indent=2)
