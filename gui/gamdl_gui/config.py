"""Read and write the app's YAML settings (in its own data folder).

The GUI shares one configuration file with the CLI, so settings made in either
place apply to both.
"""

from __future__ import annotations

from dataclasses import asdict
from pathlib import Path
from typing import Any

from gamdl.cli.config import loader
from gamdl.cli.config.models import AppConfig, config_path

# Choices for fields that accept a fixed set of values. Multi-value list fields
# are shown as checkable lists; single values as combo boxes.
SONG_CODECS = [
    "aac", "aac-he", "aac-binaural", "aac-downmix", "aac-he-binaural",
    "aac-he-downmix", "aac-web", "aac-he-web", "atmos", "ac3", "alac",
    "alac-lossless", "alac-hires",
]
VIDEO_CODECS = ["h264", "h265"]
LYRICS_FORMATS = ["lrc", "enhanced-lrc", "srt", "ttml", "text"]
try:
    from gamdl.cli.options import TAG_NAMES as _TAGS

    TAG_NAMES = list(_TAGS)
except Exception:  # noqa: BLE001
    TAG_NAMES = []
ARTIST_AUTO = ["all", "main-albums", "compilation-albums", "live-albums",
               "singles-eps", "all-albums", "top-songs", "music-videos"]
LIBRARY_AUTO = ["all", "albums", "playlists", "songs", "music-videos"]
try:
    from gamdl.media import UploadedVideoQuality

    UPLOADED_QUALITIES = [q.value for q in UploadedVideoQuality]
except Exception:  # noqa: BLE001
    UPLOADED_QUALITIES = []
try:
    from gamdl.media.constants import (
        ARTIST_AUTO_SELECT_NAMES,
        LIBRARY_AUTO_SELECT_NAMES,
    )

    ARTIST_AUTO = ["all", *ARTIST_AUTO_SELECT_NAMES]
    LIBRARY_AUTO = ["all", *LIBRARY_AUTO_SELECT_NAMES]
except Exception:  # noqa: BLE001
    pass


class Settings:
    def __init__(self, path: Path | None = None) -> None:
        if path is None:
            from .paths import config_file

            path = config_file()
        self.path = path

    def load(self) -> AppConfig:
        if not self.path.exists():
            # First run: keep the sign-in cookies and media index beside the settings.
            values = asdict(AppConfig())
            values["auth"]["cookies_path"] = str(self.path.parent / "cookies.txt")
            values["database"]["path"] = str(self.path.parent / "media.sqlite3")
            self.path.parent.mkdir(parents=True, exist_ok=True)
            loader._persist(self.path, values)
        return loader.load_config(self.path)

    def as_dict(self) -> dict[str, Any]:
        return asdict(self.load())

    def save(self, values: dict[str, Any]) -> None:
        """Validate and atomically write a full configuration mapping."""
        merged = asdict(AppConfig())
        loader._merge(merged, values)
        loader._validate(merged)
        loader._persist(self.path, merged)
