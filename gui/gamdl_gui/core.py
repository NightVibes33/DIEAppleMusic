"""UI-neutral application core: engine wiring, prompts, history, tools.

The Qt layer calls these methods from worker threads and receives batched
events through the ``deliver`` callback.
"""

from __future__ import annotations

import itertools
import json
import os
import queue
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path
from typing import Any

from gamdl.media.enums import SelectionKind
from gamdl.media.models import (
    ArtistBrowseRequest,
    ArtistBrowseResult,
    ArtistCategorySelection,
    CollectionSelectionRequest,
    SelectionRequest,
)

from . import APP_NAME, __version__
from .config import Settings
from .engine import Engine, LibrarySource, SearchSource, artwork_url
from .schema import SCHEMA

HISTORY_LIMIT = 500
SUCCESS = {"downloaded", "overwritten"}
STREAM_NAMES = {
    "StreamSourceSelectionRequest": "Choose a source",
    "StreamSelectionRequest": "Choose an audio stream",
    "VideoSelectionRequest": "Choose a video stream",
    "AudioSelectionRequest": "Choose an audio track",
    "UploadedVideoSelectionRequest": "Choose a video quality",
}


class Cancelled(Exception):
    """The user dismissed a prompt."""


def write_netscape(path: Path, cookies: list[dict]) -> None:
    """Write cookies (name, value, domain, path, secure, expires) as cookies.txt."""
    lines = ["# Netscape HTTP Cookie File", "# Saved after Apple ID sign-in", ""]
    fallback = int(time.time()) + 180 * 24 * 3600
    for c in cookies:
        domain = c.get("domain") or "music.apple.com"
        expires = int(c.get("expires") or 0)
        lines.append("\t".join([
            domain,
            "TRUE" if domain.startswith(".") else "FALSE",
            c.get("path") or "/",
            "TRUE" if c.get("secure") else "FALSE",
            str(expires if expires > 0 else fallback),
            c["name"],
            c["value"],
        ]))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    try:
        path.chmod(0o600)
    except OSError:
        pass


def _describe_stream(option: Any) -> tuple[str, str]:
    """Return (primary, secondary) labels for any stream/quality option."""
    primary = ""
    for attr in ("origin", "codec", "quality"):
        value = getattr(option, attr, None)
        if value is not None:
            primary = str(getattr(value, "value", value))
            break
    stream = getattr(option, "stream", None)
    parts: list[str] = []
    width = getattr(option, "width", None) or getattr(stream, "width", None)
    height = getattr(option, "height", None) or getattr(stream, "height", None)
    if width and height:
        parts.append(f"{width}×{height}")
    sample_rate = getattr(stream, "sample_rate", None)
    if sample_rate:
        parts.append(f"{sample_rate / 1000:g} kHz")
    bit_depth = getattr(stream, "bit_depth", None)
    if bit_depth:
        parts.append(f"{bit_depth}-bit")
    bitrate = getattr(option, "bitrate", None) or getattr(stream, "bitrate", None)
    if bitrate:
        parts.append(f"{bitrate / 1000:.0f} kbps")
    for attr in ("name", "language", "hls_type"):
        value = getattr(option, attr, None)
        if value:
            parts.append(str(getattr(value, "value", value)))
    return primary or repr(option), " · ".join(parts)


def _result_summary(metadata: dict) -> dict:
    attrs = metadata.get("attributes", {})
    details = []
    if attrs.get("trackCount"):
        details.append(f"{attrs['trackCount']} songs")
    if attrs.get("releaseDate"):
        details.append(attrs["releaseDate"][:4])
    millis = attrs.get("durationInMillis")
    return {
        "name": attrs.get("name") or metadata.get("id", ""),
        "artist": attrs.get("artistName") or attrs.get("curatorName") or "",
        "album": attrs.get("albumName") or "",
        "artwork": artwork_url(attrs, 400),
        "explicit": attrs.get("contentRating") == "explicit",
        "duration": millis or 0,
        "details": " · ".join(details),
        "link": attrs.get("url") or "",
        "kind": metadata.get("type", ""),
        "meta": metadata,
    }


def _default_music_folder() -> str:
    """This person's own Music folder, suggested on first sign-in."""
    try:
        from platformdirs import user_music_path

        return str(user_music_path())
    except Exception:  # noqa: BLE001
        return str(Path.home() / "Music")


def _parse_lrc(text: str) -> list[dict]:
    """Parse [mm:ss.xx] line-timed LRC (word timing tags are dropped)."""
    import re

    stamp = re.compile(r"\[(\d+):(\d+(?:\.\d+)?)\]")
    lines: list[dict] = []
    for raw in text.splitlines():
        stamps = stamp.findall(raw)
        body = re.sub(r"<\d+:\d+(?:\.\d+)?>", "", stamp.sub("", raw)).strip()
        if not stamps:
            if body and not re.match(r"^\[[a-z]+:", raw, re.I):
                lines.append({"t": None, "end": None, "text": body})
            continue
        for minutes, seconds in stamps:
            lines.append({"t": int((int(minutes) * 60 + float(seconds)) * 1000), "end": None, "text": body})
    timed = sorted((l for l in lines if l["t"] is not None), key=lambda l: l["t"])
    return timed or lines


LRCLIB = "https://lrclib.net/api"
LRCLIB_AGENT = "ShineAppuru desktop app"


def _lrclib_lyrics(entry: dict, meta: dict | None) -> dict | None:
    """Look a song up on LRCLIB (free, no account). Prefer synced lyrics."""
    import httpx

    attrs = (meta or {}).get("attributes") or {}
    title = attrs.get("name") or entry.get("title") or ""
    artist = attrs.get("artistName") or entry.get("artist") or ""
    album = attrs.get("albumName") or entry.get("album") or ""
    duration = (attrs.get("durationInMillis") or entry.get("duration") or 0) / 1000
    if not title or not artist:
        return None
    try:
        with httpx.Client(timeout=12, headers={"User-Agent": LRCLIB_AGENT}) as client:
            record = None
            params = {"track_name": title, "artist_name": artist}
            if album:
                params["album_name"] = album
            if duration:
                params["duration"] = round(duration)
            response = client.get(f"{LRCLIB}/get", params=params)
            if response.status_code == 200:
                record = response.json()
            if not record or not (record.get("syncedLyrics") or record.get("plainLyrics")):
                results = client.get(f"{LRCLIB}/search", params={"track_name": title, "artist_name": artist}).json()
                if isinstance(results, list) and results:
                    # Closest length wins, synced first.
                    results.sort(key=lambda r: (not r.get("syncedLyrics"), abs((r.get("duration") or 0) - duration) if duration else 0))
                    record = results[0]
    except Exception:  # noqa: BLE001 - offline or service unavailable
        return None
    if not record:
        return None
    if record.get("syncedLyrics"):
        lines = _parse_lrc(record["syncedLyrics"])
        if lines:
            return {"lines": lines, "synced": any(l["t"] is not None for l in lines)}
    if record.get("plainLyrics"):
        return {"lines": [{"t": None, "end": None, "text": t} for t in record["plainLyrics"].splitlines()], "synced": False}
    return None


SCAN_VERSION = 3


def _art_dir() -> Path:
    import os

    from .paths import cache_dir

    path = cache_dir() / "art"
    path.mkdir(parents=True, exist_ok=True)
    return path


# Folders that never hold someone's music: this app's playback cache (also in a
# portable copy), Python environments, build output and hidden folders. Skipping
# them keeps playback-cache files out of the library and makes scans fast when
# the music folder is a busy place like Downloads.
_SKIP_DIRS = {"stream-cache", "__pycache__", "site-packages", "node_modules", "venv", "$recycle.bin"}


def _music_files(root: Path):
    import os

    from .paths import cache_dir, data_dir

    own = {str(cache_dir()).lower(), str(data_dir()).lower()}
    for folder, dirs, files in os.walk(root):
        dirs[:] = [
            d for d in dirs
            if not d.startswith(".") and d.lower() not in _SKIP_DIRS and str(Path(folder, d)).lower() not in own
        ]
        for name in files:
            if name.lower().endswith((".m4a", ".m4v", ".mp4")):
                yield Path(folder, name)


def _read_tags(path: Path) -> dict | None:
    """Title, artist, album, length and artwork of one local file.

    Returns None for anything that isn't a tagged song or music video (home
    videos, screen recordings, untagged clips), so they stay out of the library.
    """
    import hashlib
    from datetime import datetime as _dt

    entry = {
        "title": path.stem, "artist": "", "album": path.parent.name, "artwork": "",
        "path": str(path), "kind": "Music video" if path.suffix.lower() in {".m4v", ".mp4"} else "Song",
        "explicit": False, "duration": 0,
        "time": _dt.fromtimestamp(path.stat().st_mtime).isoformat(timespec="seconds"), "local": True,
    }
    try:
        from mutagen.mp4 import MP4

        audio = MP4(str(path))
        tags = audio.tags or {}

        def first(key):
            value = tags.get(key)
            return str(value[0]) if value else ""

        title, artist = first("\xa9nam"), first("\xa9ART") or first("aART")
        # Apple Music downloads carry catalog IDs; require at least real music tags.
        if not title or not artist or (not tags.get("cnID") and not first("\xa9alb")):
            return None
        entry["title"] = title
        # A catalog ID means the file came from Apple Music: count it as one of
        # our downloads, even if an earlier install (or the CLI) saved it.
        if tags.get("cnID"):
            entry["media_id"] = str(tags["cnID"][0])
            entry["local"] = False
        entry["artist"] = first("aART") or first("\xa9ART")
        if first("\xa9ART"):
            entry["artist"] = first("\xa9ART")
        entry["album"] = first("\xa9alb") or entry["album"]
        entry["explicit"] = bool(tags.get("rtng") and tags["rtng"][0] in (1, 4))
        entry["duration"] = int((audio.info.length or 0) * 1000)
        covers = tags.get("covr")
        if covers:
            folder_key = hashlib.sha1(str(path.parent).lower().encode()).hexdigest()[:16]
            art = _art_dir() / f"{folder_key}.jpg"
            if not art.exists():
                art.write_bytes(bytes(covers[0]))
            entry["artwork"] = art.as_uri()
    except Exception:  # noqa: BLE001 - unreadable or not an MP4 audio/video file
        return None
    return entry


LINK_PATHS = {"albums": "album", "songs": "song", "music-videos": "music-video", "playlists": "playlist"}


def _library_summary(item: dict, kind: str, storefront: str) -> dict:
    """Display fields, a shareable catalog link and lean metadata for one item."""
    attrs = item.get("attributes") or {}
    catalog = (((item.get("relationships") or {}).get("catalog") or {}).get("data") or [])
    cattrs = (catalog[0].get("attributes") or {}) if catalog else {}
    play = attrs.get("playParams") or {}
    link = cattrs.get("url") or attrs.get("url") or ""
    if not link:
        target = play.get("globalId") if kind == "playlists" else (play.get("catalogId") or (catalog[0]["id"] if catalog else None))
        if target:
            link = f"https://music.apple.com/{storefront}/{LINK_PATHS[kind]}/{target}"
    details = []
    if attrs.get("trackCount"):
        details.append(f"{attrs['trackCount']} songs")
    if attrs.get("releaseDate"):
        details.append(attrs["releaseDate"][:4])
    return {
        "name": attrs.get("name") or item.get("id", ""),
        "artist": attrs.get("artistName") or attrs.get("curatorName") or ("Playlist" if kind == "playlists" else ""),
        "album": attrs.get("albumName") or "",
        "artwork": artwork_url(attrs, 400) or artwork_url(cattrs, 400),
        "explicit": attrs.get("contentRating") == "explicit",
        "duration": attrs.get("durationInMillis") or 0,
        "details": " · ".join(details),
        "added": attrs.get("dateAdded") or "",
        "link": link,
        "meta": {"id": item.get("id"), "type": item.get("type"), "attributes": attrs},
    }


class Core:
    def __init__(self, deliver) -> None:
        self._deliver = deliver
        self._settings = Settings()
        self._engine = Engine(self._settings)
        self._events: queue.Queue = queue.Queue()
        self._prompts: dict[int, tuple[str, Any, Any]] = {}
        self._prompt_ids = itertools.count(1)
        self._items: dict[tuple[int, int], dict] = {}
        self._tool: subprocess.Popen | None = None
        self._history_path = self._settings.path.parent / "gui-history.json"
        self._history = self._load_history()
        self._mapped: dict[str, str] = {}
        self._wire_engine()
        threading.Thread(target=self._pump, daemon=True).start()

    # ---- plumbing ------------------------------------------------------------

    def _push(self, type_: str, **data: Any) -> None:
        self._events.put({"type": type_, **data})

    def _pump(self) -> None:
        """Batch engine events and deliver them to JS ~12 times a second."""
        while True:
            batch = [self._events.get()]
            time.sleep(0.08)
            while True:
                try:
                    batch.append(self._events.get_nowait())
                except queue.Empty:
                    break
            # Keep only the latest progress tick per item.
            latest: dict[tuple, int] = {}
            for i, event in enumerate(batch):
                if event["type"] == "item_event":
                    latest[(event["job"], event["item"])] = i
            batch = [
                e for i, e in enumerate(batch)
                if e["type"] != "item_event" or latest[(e["job"], e["item"])] == i
            ]
            try:
                self._deliver(json.dumps(batch, default=str))
            except Exception:  # noqa: BLE001 - UI shutting down
                pass

    def _wire_engine(self) -> None:
        e = self._engine
        e.log.connect(lambda level, msg: self._push("log", level=level, msg=msg))
        e.status.connect(lambda text: self._push("status", text=text))
        e.session_changed.connect(lambda ok, desc: self._push("session", ok=ok, desc=desc))
        e.profile_changed.connect(lambda profile: self._push("account_profile", profile=profile))
        e.job_started.connect(lambda job: self._push("job_started", job=job))
        e.job_finished.connect(lambda job, summary: self._push("job_finished", job=job, summary=summary))
        e.item_added.connect(self._on_item_added)
        e.item_event.connect(
            lambda job, item, stage, pct, detail: self._push(
                "item_event", job=job, item=item, stage=stage, pct=pct, detail=detail
            )
        )
        e.item_finished.connect(self._on_item_finished)
        e.prompt.connect(self._on_prompt)
        e.search_page.connect(
            lambda token, kind, items, more: self._push(
                "search", token=token, kind=kind, items=[_result_summary(m) for m in items], more=more
            )
        )

    def _on_item_added(self, job: int, item: int, info: dict) -> None:
        self._items[(job, item)] = info
        self._push("item_added", job=job, item=item, info=info)

    def _on_item_finished(self, job: int, item: int, status: str, message: str, path: str) -> None:
        self._push("item_finished", job=job, item=item, status=status, message=message, path=path)
        info = self._items.pop((job, item), None)
        if info and status in SUCCESS and path:
            entry = {**info, "path": path, "status": status, "time": datetime.now().isoformat(timespec="seconds")}
            self._history.insert(0, entry)
            del self._history[HISTORY_LIMIT:]
            self._save_history()
            self._push("history", entry=entry)

    # ---- prompts ---------------------------------------------------------------

    def _on_prompt(self, kind: str, payload: Any, reply) -> None:
        pid = next(self._prompt_ids)
        self._prompts[pid] = (kind, payload, reply)
        data: dict[str, Any] = {"id": pid}
        if kind in {"credentials", "two_factor"}:
            data["kind"] = kind
        elif kind == "media":
            request = payload
            if isinstance(request, ArtistBrowseRequest):
                data.update(
                    kind="browse",
                    title=request.artist_name or "Your library",
                    categories=[{"kind": k.value, "label": label} for k, label in request.categories],
                )
            else:
                if isinstance(request, CollectionSelectionRequest):
                    title = request.prompt
                elif isinstance(request, SelectionRequest):
                    title = {
                        "album_tracks": "Choose songs from this album",
                        "playlist_tracks": "Choose songs from this playlist",
                        "isrc": "Several matches for this ISRC",
                    }.get(request.kind.value, "Choose items")
                else:
                    title = "Choose items"
                data.update(kind="select", title=title,
                            options=[{"index": o.index, "title": o.title} for o in request.options])
        elif kind == "stream":
            media_title, request = payload
            options = []
            for pos, option in enumerate(request.options):
                primary, secondary = _describe_stream(option)
                options.append({"index": pos, "label": primary, "detail": secondary})
            data.update(kind="stream", title=STREAM_NAMES.get(type(request).__name__, "Choose a stream"),
                        subtitle=media_title, options=options)
        else:
            reply(Cancelled())
            return
        self._push("prompt", **data)

    def answer(self, pid: int, value: Any = None, cancelled: bool = False) -> None:
        entry = self._prompts.pop(int(pid), None)
        if entry is None:
            return
        kind, payload, reply = entry
        if cancelled:
            reply(Cancelled("Cancelled"))
        elif kind == "credentials":
            reply((value["user"], value["password"]))
        elif kind == "two_factor":
            reply(str(value).strip())
        elif kind == "stream":
            reply(int(value))
        elif isinstance(payload, ArtistBrowseRequest):
            selections = []
            for sel in value.get("selections", []):
                category = SelectionKind(sel["kind"])
                if sel.get("all"):
                    selections.append(ArtistCategorySelection(category, None, tuple(sel.get("excluded", []))))
                elif sel.get("indices"):
                    selections.append(ArtistCategorySelection(category, tuple(sel["indices"])))
            reply(ArtistBrowseResult(tuple(selections)))
        else:
            reply([int(v) for v in value])

    def browse_page(self, pid: int, kind: str, page: int) -> dict:
        entry = self._prompts.get(int(pid))
        if entry is None:
            return {"items": [], "more": False}
        request = entry[1]
        future = self._engine.submit(request.load_page(SelectionKind(kind), int(page)))
        result = future.result(timeout=90)
        items = [{"index": o.index, "title": o.title} for o in (result.items if result else ())]
        return {"items": items, "more": bool(result and result.next_cursor)}

    # ---- state & settings ------------------------------------------------------

    def get_state(self) -> dict:
        self._prune_history()
        try:
            cfg = self._settings.load()
            auth_mode, directory, search_api, error = cfg.auth.mode, cfg.output.directory, cfg.search.api, ""
        except Exception as exc:  # noqa: BLE001
            auth_mode, directory, search_api, error = None, None, "apple-music", str(exc)
        import gamdl

        return {
            "version": __version__,
            "auth": auth_mode,
            "directory": directory,
            "search_api": search_api,
            "config_error": error,
            "config_path": str(self._settings.path),
            "default_music": _default_music_folder(),
            "history": self._history,
        }

    def get_settings(self) -> dict:
        return {"schema": SCHEMA, "values": self._settings.as_dict(), "path": str(self._settings.path)}

    def save_settings(self, values: dict) -> dict:
        try:
            current = self._settings.as_dict()
        except Exception:  # noqa: BLE001
            current = {}
        for section, fields in values.items():
            # Sections merge; top-level values such as config_version are copied.
            if isinstance(fields, dict) and isinstance(current.get(section, {}), dict):
                current.setdefault(section, {}).update(fields)
            else:
                current[section] = fields
        for section in ("output",):
            for key in ("embedded_cover_size", "file_cover_size"):
                value = current.get(section, {}).get(key)
                if isinstance(value, str) and value.isdigit():
                    current[section][key] = int(value)
        try:
            self._settings.save(current)
        except Exception as exc:  # noqa: BLE001
            return {"ok": False, "error": str(exc)}
        self._engine.reset_session()
        self.__dict__.pop("_library", None)
        return {"ok": True}

    def connect_apple_music(self) -> dict:
        try:
            self._engine.connect_auth().result(timeout=180)
            return {"ok": True}
        except Exception as exc:  # noqa: BLE001
            return {"ok": False, "error": str(exc) or type(exc).__name__}

    # ---- downloads & search ----------------------------------------------------

    def start_job(self, sources: list, select_tracks: bool = False, ask_streams: bool = False) -> int:
        parsed: list[Any] = []
        for source in sources:
            if isinstance(source, dict) and source.get("library"):
                parsed.append(LibrarySource(source["type"], source["meta"], source.get("label", "")))
            elif isinstance(source, dict):
                parsed.append(SearchSource(source["type"], source["meta"], source.get("label", "")))
            elif str(source).strip():
                parsed.append(str(source).strip())
        return self._engine.start_job(parsed, select_tracks=select_tracks, ask_streams=ask_streams)

    def cancel_job(self, job: int) -> None:
        self._engine.cancel_job(int(job))

    def cancel_all(self) -> None:
        self._engine.cancel_all()

    def search(self, token: int, term: str, kind: str, api: str) -> dict:
        try:
            self._engine.search(int(token), term, kind, api).result(timeout=60)
            return {"ok": True}
        except Exception as exc:  # noqa: BLE001
            return {"ok": False, "error": str(exc) or type(exc).__name__}

    def search_more(self, token: int, kind: str) -> dict:
        try:
            self._engine.search_more(int(token), kind).result(timeout=60)
            return {"ok": True}
        except Exception as exc:  # noqa: BLE001
            return {"ok": False, "error": str(exc)}

    # ---- the person's Apple Music library ---------------------------------------

    def library_load(self, kind: str, refresh: bool = False) -> dict:
        """Pull an entire library category, streaming pages to the UI."""
        cache = self.__dict__.setdefault("_library", {})
        if kind in cache and not refresh:
            self._push("library_chunk", kind=kind, items=cache[kind], more=False, reset=True)
            return {"ok": True, "count": len(cache[kind])}
        collected: list[dict] = []
        first = {"value": True}

        def on_page(items: list, more: bool) -> None:
            session = self._engine._session
            storefront = getattr(session.api, "storefront", None) if session else None
            summaries = [_library_summary(i, kind, storefront or "us") for i in items]
            collected.extend(summaries)
            self._push("library_chunk", kind=kind, items=summaries, more=more, reset=first["value"])
            first["value"] = False

        try:
            self._engine.library_pages(kind, on_page).result(timeout=900)
        except Exception as exc:  # noqa: BLE001
            self._push("library_error", kind=kind, error=str(exc) or type(exc).__name__)
            return {"ok": False, "error": str(exc) or type(exc).__name__}
        cache[kind] = collected
        return {"ok": True, "count": len(collected)}

    # ---- playback -------------------------------------------------------------

    def media_url(self, path: str) -> dict:
        """URL the in-app player can stream a downloaded file from."""
        if not path or not Path(path).is_file():
            return {"ok": False, "error": "This file has moved or been deleted."}
        return {"ok": True, "url": Path(path).resolve().as_uri()}

    def stream(self, meta: dict) -> dict:
        """Full song via the stream cache, falling back to Apple's preview."""
        attrs = (meta or {}).get("attributes", {})
        previews = attrs.get("previews") or []
        preview = previews[0].get("url") if previews else None
        reason = ""
        try:
            configured = self._settings.load().auth.mode is not None
        except Exception:  # noqa: BLE001
            configured = False
        if configured:
            try:
                path = self._engine.fetch_stream(meta).result(timeout=240)
                return {"ok": True, "url": Path(path).resolve().as_uri(), "source": "full"}
            except Exception as exc:  # noqa: BLE001
                reason = str(exc) or type(exc).__name__
        else:
            reason = "Sign in to play full songs."
        if preview:
            return {"ok": True, "url": preview, "source": "preview", "note": reason}
        return {"ok": False, "error": reason or "This song can't be played."}

    def lyrics(self, entry: dict) -> dict:
        """Lyrics for the playing song: a local .lrc next to the file, else Apple."""
        path = entry.get("path")
        if path:
            sidecar = Path(path).with_suffix(".lrc")
            if sidecar.is_file():
                lines = _parse_lrc(sidecar.read_text(encoding="utf-8", errors="replace"))
                if lines:
                    return {"ok": True, "lines": lines, "synced": any(l["t"] is not None for l in lines)}
            text = Path(path).with_suffix(".txt")
            if text.is_file():
                lines = [{"t": None, "end": None, "text": t} for t in text.read_text(encoding="utf-8", errors="replace").splitlines()]
                return {"ok": True, "lines": lines, "synced": False}
        meta = entry.get("meta")
        apple_lines: list[dict] = []
        if meta:
            try:
                apple_lines = self._engine.fetch_lyrics(meta).result(timeout=60) or []
            except Exception:  # noqa: BLE001 - not signed in, preview, or no lyrics
                apple_lines = []
            if any(l["t"] is not None for l in apple_lines):
                return {"ok": True, "lines": apple_lines, "synced": True, "source": "Apple Music"}
        # Free fallback: LRCLIB's open database of synced lyrics.
        found = _lrclib_lyrics(entry, meta)
        if found and (found["synced"] or not apple_lines):
            return {"ok": True, **found, "source": "LRCLIB"}
        return {"ok": True, "lines": apple_lines, "synced": False, "source": "Apple Music" if apple_lines else ""}

    def artist(self, meta: dict) -> dict:
        """Top songs, albums and singles for an artist page."""
        try:
            data = self._engine.artist_page(meta["id"]).result(timeout=60)
        except Exception as exc:  # noqa: BLE001
            return {"ok": False, "error": str(exc) or type(exc).__name__}
        item = (data.get("data") or [{}])[0]
        attrs = item.get("attributes") or {}
        views = item.get("views") or {}

        def view(name):
            return [_result_summary(m) for m in (views.get(name) or {}).get("data") or []]

        return {
            "ok": True,
            "name": attrs.get("name", ""),
            "artwork": artwork_url(attrs, 600),
            "link": attrs.get("url", ""),
            "top": view("top-songs"),
            "albums": view("full-albums"),
            "singles": view("singles"),
        }

    # ---- music already in the music folder ----

    def scan_library(self) -> dict:
        """Index songs in the music folder (tags and artwork), with a cache."""
        try:
            directory = self._settings.load().output.directory
        except Exception:  # noqa: BLE001
            directory = None
        if not directory or not Path(directory).expanduser().is_dir():
            return {"ok": True, "items": []}
        cache_path = _art_dir().parent / "library-scan.json"
        try:
            loaded = json.loads(cache_path.read_text(encoding="utf-8"))
            # Bump SCAN_VERSION whenever the rules for what counts as music change.
            cache = loaded.get("files", {}) if loaded.get("version") == SCAN_VERSION else {}
        except Exception:  # noqa: BLE001
            cache = {}
        items, fresh = [], {}
        root = Path(directory).expanduser()
        for path in _music_files(root):
            key = str(path)
            mtime = path.stat().st_mtime
            entry = cache.get(key)
            if not entry or entry.get("mtime") != mtime:
                entry = _read_tags(path) or {"skip": True}
                entry["mtime"] = mtime
            fresh[key] = entry
            if entry.get("skip"):
                continue
            items.append(entry)
            if len(items) >= 20000:
                break
        try:
            cache_path.write_text(json.dumps({"version": SCAN_VERSION, "files": fresh}), encoding="utf-8")
        except OSError:
            pass
        self._sync_database(root, items)
        return {"ok": True, "items": items}

    def _sync_database(self, root: Path, items: list) -> None:
        """Keep the media database in step with the music folder: index Apple
        Music files it doesn't know (so a new install skips songs you already
        have) and drop entries for files that are gone."""
        try:
            from gamdl.download.database import MediaDatabase

            settings = self._settings.load()
            if settings.database.disabled:
                return
            db = MediaDatabase(Path(settings.database.path).expanduser(), root=root, save_metadata=settings.database.save_metadata)
            db.initialize()
            kinds = {".m4a": "songs", ".m4v": "music-videos"}
            for item in items:
                path = Path(item["path"])
                kind = kinds.get(path.suffix.lower())
                if kind and item.get("media_id") and db.get(path) is None:
                    db.index_file(path, kind, item["media_id"])
            from contextlib import closing

            with closing(db._read()) as conn, conn:
                gone = [row["path"] for row in conn.execute("SELECT path FROM media_files") if not db.decode_path(str(row["path"])).is_file()]
                conn.executemany("DELETE FROM media_files WHERE path=?", [(p,) for p in gone])
        except Exception:  # noqa: BLE001 - the database only helps skip duplicates
            pass

    def delete_files(self, paths: list) -> dict:
        """Move songs (and their lyrics and cover files) to the Recycle Bin."""
        from PySide6.QtCore import QFile

        moved, failed = 0, []
        for raw in paths:
            path = Path(raw)
            if not path.is_file():
                continue
            if QFile.moveToTrash(str(path)):
                moved += 1
                for sidecar in (path.with_suffix(".lrc"), path.with_suffix(".txt"), path.with_suffix(".srt"), path.with_suffix(".ttml")):
                    if sidecar.is_file():
                        QFile.moveToTrash(str(sidecar))
            else:
                failed.append(path.name)
        gone = {str(Path(p)) for p in paths}
        self._history = [h for h in self._history if str(Path(h.get("path", ""))) not in gone]
        self._save_history()
        return {"ok": not failed, "moved": moved, "error": ("Couldn't move: " + ", ".join(failed[:3])) if failed else ""}

    def collection_tracks(self, kind: str, meta: dict) -> dict:
        try:
            tracks = self._engine.collection_tracks(kind, meta).result(timeout=120)
        except Exception as exc:  # noqa: BLE001
            return {"ok": False, "error": str(exc) or type(exc).__name__}
        return {"ok": True, "tracks": [_result_summary(t) for t in tracks]}

    # ---- history -----------------------------------------------------------------

    def _prune_history(self) -> None:
        """Drop history for files deleted or moved outside the app (and repeat
        entries for the same file). Files on a drive that isn't connected right
        now (a USB stick, a network share) are kept until it's back."""
        kept, seen = [], set()
        for entry in self._history:
            path = entry.get("path") or ""
            key = os.path.normcase(path)
            if path:
                if key in seen:
                    continue
                file = Path(path)
                if not file.is_file() and Path(file.anchor or "/").exists():
                    continue
                seen.add(key)
            kept.append(entry)
        if len(kept) != len(self._history):
            self._history = kept
            self._save_history()

    def _load_history(self) -> list:
        try:
            return json.loads(self._history_path.read_text(encoding="utf-8"))[:HISTORY_LIMIT]
        except Exception:  # noqa: BLE001
            return []

    def _save_history(self) -> None:
        try:
            self._history_path.parent.mkdir(parents=True, exist_ok=True)
            self._history_path.write_text(json.dumps(self._history, ensure_ascii=False), encoding="utf-8")
        except OSError:
            pass

    def save_apple_cookies(self, cookies: list[dict]) -> dict:
        """Persist cookies captured from Apple's sign-in page for gamdl."""
        if not any(c["name"] == "media-user-token" and c["value"] for c in cookies):
            return {"ok": False, "error": "Apple didn't return a session for this account."}
        path = self._settings.path.parent / "cookies.txt"
        write_netscape(path, cookies)
        current = self._settings.as_dict()
        current["auth"].update(mode="cookies", cookies_path=str(path))
        self._settings.save(current)
        self._engine.reset_session()
        self.__dict__.pop("_library", None)
        return {"ok": True}

    def sign_out(self) -> dict:
        """Forget the saved Apple session: auth settings and Gamdl's cookies file."""
        try:
            current = self._settings.as_dict()
        except Exception:  # noqa: BLE001
            current = {}
        auth = current.setdefault("auth", {})
        cookies = Path(auth.get("cookies_path") or self._settings.path.parent / "cookies.txt")
        managed = self._settings.path.parent / "cookies.txt"
        auth.update(mode=None, media_user_token=None)
        try:
            self._settings.save(current)
        except Exception as exc:  # noqa: BLE001
            return {"ok": False, "error": str(exc)}
        # Only delete the cookies file Gamdl wrote itself, never one the
        # person exported and pointed us at.
        if cookies.resolve() == managed.resolve():
            managed.unlink(missing_ok=True)
        self._engine.reset_session()
        self.__dict__.pop("_library", None)
        return {"ok": True}

    def clear_history(self) -> None:
        self._history.clear()
        self._save_history()

    # ---- files ---------------------------------------------------------------------

    def reveal(self, path: str) -> None:
        if path and Path(path).exists():
            subprocess.Popen(["explorer", "/select,", str(Path(path))])
        elif path:
            self.open_path(str(Path(path).parent))

    def open_path(self, path: str) -> None:
        if path and Path(path).exists():
            os.startfile(path)  # noqa: S606 - user-chosen local file

    def open_output(self) -> bool:
        try:
            directory = self._settings.load().output.directory
        except Exception:  # noqa: BLE001
            directory = None
        if directory and Path(directory).expanduser().exists():
            os.startfile(str(Path(directory).expanduser()))  # noqa: S606
            return True
        return False

    def open_url(self, url: str) -> None:
        if url.startswith("https://"):
            os.startfile(url)  # noqa: S606

    # ---- library tools -------------------------------------------------------------

    def run_tool(self, args: list, directory: str = "") -> dict:
        if self._tool is not None and self._tool.poll() is None:
            return {"ok": False, "error": "Another tool is still running."}
        if self._engine.busy and args and args[0] in {"organize", "sync"}:
            return {"ok": False, "error": "Wait for downloads to finish before changing files."}
        args = [str(a) for a in args]
        if directory and args[0] in {"organize", "sync"} or (directory and args[:2] == ["database", "scan"]):
            args += ["--directory", directory]
        if getattr(sys, "frozen", False):
            # Packaged app: the exe runs gamdl's CLI itself (see app.main).
            command = [sys.executable, "--tool", "--config", str(self._settings.path), *args]
        else:
            code = "import sys; from gamdl.cli.main import main; sys.argv[0] = 'gamdl'; main()"
            command = [sys.executable, "-c", code, "--config", str(self._settings.path), *args]
        env = {**os.environ, "PYTHONIOENCODING": "utf-8", "PYTHONUTF8": "1", "NO_COLOR": "1", "COLUMNS": "120"}
        self._tool = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            env=env,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        process = self._tool
        self._push("tool_output", text=f"\u25b8 {' '.join(a for a in args if not a.startswith('--directory'))}\n")

        def read():
            assert process.stdout is not None
            import re

            for raw in iter(process.stdout.readline, b""):
                line = raw.decode("utf-8", "replace")
                if re.match(r"^\s*gamdl\s+\d+(\.\d+)*\s*$", line, re.I):
                    continue  # the engine's version banner
                self._push("tool_output", text=re.sub(r"\bgamdl\b", APP_NAME, line, flags=re.I))
            self._push("tool_done", code=process.wait())

        threading.Thread(target=read, daemon=True).start()
        return {"ok": True}

    def stop_tool(self) -> None:
        if self._tool is not None and self._tool.poll() is None:
            self._tool.kill()

    def shutdown(self) -> None:
        self.stop_tool()
        self._engine.shutdown()
