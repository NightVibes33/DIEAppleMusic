"""Where the app keeps its files.

Installed: settings in %APPDATA%\\<app>, caches in %LOCALAPPDATA%\\<app>.
Portable (a "portable.ini" file next to the exe): everything in .\\Data, so the
whole app can live on a USB stick and leave nothing behind on the PC.
"""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

from . import APP_NAME


def exe_dir() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent.parent


def is_portable() -> bool:
    return (exe_dir() / "portable.ini").is_file()


def data_dir() -> Path:
    if is_portable():
        path = exe_dir() / "Data"
    else:
        path = Path(os.environ.get("APPDATA") or Path.home()) / APP_NAME
    path.mkdir(parents=True, exist_ok=True)
    return path


def cache_dir() -> Path:
    if is_portable():
        path = exe_dir() / "Data" / "Cache"
    else:
        path = Path(os.environ.get("LOCALAPPDATA") or Path.home()) / APP_NAME
    path.mkdir(parents=True, exist_ok=True)
    return path


def config_file() -> Path:
    return data_dir() / "config.yml"


def migrate_old_data() -> None:
    """Copy settings, sign-in and history from the old .gamdl folder once.

    The old folder is left untouched (the command-line tool may still use it).
    """
    if is_portable() or config_file().exists():
        return
    old = Path.home() / ".gamdl"
    if not (old / "config.yml").is_file():
        return
    for name in ("config.yml", "cookies.txt", "gui-history.json", "media.sqlite3"):
        if (old / name).is_file():
            shutil.copy2(old / name, data_dir() / name)
    # Point copied paths at the new folder.
    try:
        import yaml

        cfg_path = config_file()
        cfg = yaml.safe_load(cfg_path.read_text(encoding="utf-8")) or {}
        auth, database = cfg.setdefault("auth", {}), cfg.setdefault("database", {})
        if Path(str(auth.get("cookies_path") or "")).resolve() == (old / "cookies.txt").resolve():
            auth["cookies_path"] = str(data_dir() / "cookies.txt")
        if Path(str(database.get("path") or "")).resolve() == (old / "media.sqlite3").resolve():
            database["path"] = str(data_dir() / "media.sqlite3")
        cfg_path.write_text(yaml.safe_dump(cfg, sort_keys=False, allow_unicode=True), encoding="utf-8")
    except Exception:  # noqa: BLE001 - a plain copy is still usable
        pass
