"""Background asyncio engine that drives gamdl's library API for the GUI.

All gamdl objects live on one event loop running in a daemon thread. The GUI
talks to it through Qt signals (engine -> GUI) and ``submit`` (GUI -> engine).
Whenever gamdl needs a decision (track selection, stream choice, wrapper
sign-in), the engine emits ``prompt`` and awaits the GUI's answer.
"""

from __future__ import annotations

import asyncio
import os
import threading
import traceback
from collections import Counter
from contextlib import AsyncExitStack, aclosing
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

from gamdl.api import AppleMusicApi, GamdlApiError, ItunesApi, WrapperApi
from gamdl.api.exceptions import GamdlRateLimitError
from gamdl.download import (
    Downloader,
    DownloadFinalizationError,
    MediaDatabase,
    PathFormatter,
    TagResolver,
)
from gamdl.download.events import DownloadEvent, DownloadStage, EventState
from gamdl.drm import Drm
from gamdl.media import (
    MediaNotFoundError,
    MediaNotStreamableError,
    MediaResolver,
    MusicVideo,
    MusicVideoCodec,
    Song,
    SongCodec,
    UploadedVideo,
    UploadedVideoQuality,
)
from gamdl.media.base import Media
from gamdl.media.constants import (
    ARTIST_AUTO_SELECT_NAMES,
    DEFAULT_AUTO_SELECT,
    LIBRARY_AUTO_SELECT_NAMES,
)
from gamdl.search import create_search_caches

from .config import Settings

STAGE_LABELS = {
    DownloadStage.FETCHING_TAGS: "Fetching tags",
    DownloadStage.FETCHING_STREAMS: "Fetching streams",
    DownloadStage.FETCHING_DECRYPTION_KEYS: "Getting keys",
    DownloadStage.DOWNLOADING: "Downloading",
    DownloadStage.MUXING: "Muxing",
    DownloadStage.TAGGING: "Tagging",
    DownloadStage.PUBLISHING: "Saving",
    DownloadStage.SAVING_COVER: "Saving cover",
    DownloadStage.SAVING_LYRICS: "Saving lyrics",
    DownloadStage.UPDATING_DATABASE: "Updating database",
    DownloadStage.UPDATING_PLAYLIST: "Updating playlist",
    DownloadStage.COMPLETED: "Completed",
}


def short_error(error: BaseException) -> str:
    text = str(error).strip()
    return text or type(error).__name__


@dataclass
class SearchSource:
    """A search result chosen in the Search tab."""

    resource_type: str
    metadata: dict
    label: str


@dataclass
class LibrarySource:
    """An item from the person's own Apple Music library."""

    kind: str  # albums | playlists | songs | music-videos
    metadata: dict
    label: str


@dataclass
class Job:
    """One batch of sources (URLs, ISRCs, search picks, or the library)."""

    id: int
    sources: list[str | SearchSource | LibrarySource]
    select_tracks: bool = False
    ask_streams: bool = False
    counts: Counter = field(default_factory=Counter)


class Hook:
    """Minimal signal: listeners are called on the emitting thread."""

    def __init__(self) -> None:
        self._listeners: list[Callable[..., Any]] = []

    def connect(self, listener: Callable[..., Any]) -> None:
        self._listeners.append(listener)

    def emit(self, *args: Any) -> None:
        for listener in list(self._listeners):
            listener(*args)


def stream_cache_dir() -> Path:
    from .paths import cache_dir

    path = cache_dir() / "stream-cache"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _prune_cache(cache: Path, limit: int = 1024 * 1024 * 1024) -> None:
    """Keep the stream cache under ``limit`` bytes, dropping the oldest files."""
    files = sorted(cache.glob("*.m4a"), key=lambda f: f.stat().st_mtime, reverse=True)
    total = 0
    for f in files:
        total += f.stat().st_size
        if total > limit:
            f.unlink(missing_ok=True)


def artwork_url(attributes: dict, size: int = 300) -> str:
    url = (attributes.get("artwork") or {}).get("url") or ""
    return url.replace("{w}", str(size)).replace("{h}", str(size)).replace("{f}", "jpg")


class Session:
    """An authenticated Apple Music session reused across jobs."""

    def __init__(self) -> None:
        self.stack = AsyncExitStack()
        self.api: AppleMusicApi | None = None
        self.wrapper: WrapperApi | None = None
        self.drm: Drm | None = None
        self.itunes: ItunesApi | None = None
        self.stream_downloader: Downloader | None = None

    async def close(self) -> None:
        await self.stack.aclose()


class Engine:
    def __init__(self, settings: Settings) -> None:
        self.log = Hook()  # level, message
        self.status = Hook()  # text
        self.session_changed = Hook()  # authenticated, description
        self.profile_changed = Hook()  # display name and profile image URL
        self.job_started = Hook()  # job
        self.job_finished = Hook()  # job, summary
        self.item_added = Hook()  # job, item, info
        self.item_event = Hook()  # job, item, stage, percent, detail
        self.item_finished = Hook()  # job, item, status, message, path
        self.prompt = Hook()  # kind, payload, reply(callable)
        self.search_page = Hook()  # token, type, items, has_more
        self.settings = settings
        self.loop = asyncio.new_event_loop()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()
        self._session: Session | None = None
        self._session_lock: asyncio.Lock | None = None
        self._jobs: dict[int, asyncio.Future] = {}
        self._next_job = 1
        # Downloads running at once across every job (the "concurrent downloads"
        # setting), so several bulk downloads queue instead of piling up on Apple.
        self._gate: asyncio.Semaphore | None = None
        self._gate_size = 0
        self._search_caches: dict[str, Any] = {}

    # ---- thread plumbing -------------------------------------------------

    def _run(self) -> None:
        asyncio.set_event_loop(self.loop)
        self.loop.run_forever()

    def submit(self, coro) -> asyncio.Future:
        return asyncio.run_coroutine_threadsafe(coro, self.loop)

    def shutdown(self) -> None:
        async def stop():
            for future in list(self._jobs.values()):
                future.cancel()
            await self._drop_session()

        try:
            self.submit(stop()).result(timeout=5)
        except Exception:  # noqa: BLE001 - best effort on exit
            pass
        self.loop.call_soon_threadsafe(self.loop.stop)

    async def ask(self, kind: str, payload: Any) -> Any:
        """Ask the GUI thread a question and wait for the answer."""
        future = self.loop.create_future()

        def reply(value: Any) -> None:
            def resolve():
                if not future.done():
                    if isinstance(value, BaseException):
                        future.set_exception(value)
                    else:
                        future.set_result(value)

            self.loop.call_soon_threadsafe(resolve)

        self.prompt.emit(kind, payload, reply)
        return await future

    def _info(self, message: str) -> None:
        self.log.emit("info", message)

    def _warn(self, message: str) -> None:
        self.log.emit("warn", message)

    def _error(self, message: str) -> None:
        self.log.emit("error", message)

    # ---- authentication --------------------------------------------------

    def reset_session(self) -> None:
        """Called after settings change; the next job re-authenticates."""
        self.submit(self._drop_session())

    async def _drop_session(self) -> None:
        if self._session is not None:
            session, self._session = self._session, None
            try:
                await session.close()
            except Exception:  # noqa: BLE001
                pass
            self.profile_changed.emit({})
            self.session_changed.emit(False, "Not signed in")

    def connect_auth(self) -> asyncio.Future:
        async def run():
            await self._drop_session()
            await self._get_session()

        return self.submit(run())

    async def _get_session(self) -> Session:
        if self._session_lock is None:
            self._session_lock = asyncio.Lock()
        async with self._session_lock:
            if self._session is not None:
                return self._session
            cfg = self.settings.load()
            auth = cfg.auth
            if auth.mode is None:
                raise RuntimeError(
                    "No authentication method configured. Open Settings → "
                    "Authentication and choose Cookies, Media User Token or Wrapper."
                )
            self.status.emit("Authenticating…")
            self._info(f"Authenticating with {auth.mode}…")
            session = Session()
            try:
                stack = session.stack
                if auth.mode == "cookies":
                    path = Path(auth.cookies_path).expanduser()
                    if not path.is_file():
                        raise RuntimeError(f"Cookies file not found: {path}")
                    session.api = await stack.enter_async_context(
                        await AppleMusicApi.from_cookies(
                            str(path),
                            storefront=auth.storefront,
                            language=auth.language,
                        )
                    )
                elif auth.mode == "media-user-token":
                    if not auth.media_user_token:
                        raise RuntimeError("Media User Token is empty")
                    session.api = await stack.enter_async_context(
                        await AppleMusicApi.create(
                            media_user_token=auth.media_user_token,
                            storefront=auth.storefront,
                            language=auth.language,
                        )
                    )
                else:

                    async def credentials():
                        return await self.ask("credentials", None)

                    async def two_factor():
                        return await self.ask("two_factor", None)

                    session.wrapper = await stack.enter_async_context(
                        await WrapperApi.create(
                            base_url=auth.wrapper_url,
                            decrypt_host=auth.wrapper_decrypt_host,
                            decrypt_port=auth.wrapper_decrypt_port,
                            get_credentials=credentials,
                            get_2fa_code=two_factor,
                        )
                    )
                    session.api = await stack.enter_async_context(
                        await AppleMusicApi.from_wrapper(
                            session.wrapper,
                            storefront=auth.storefront,
                            language=auth.language,
                        )
                    )
                device = auth.device_path or None
                if auth.drm_backend == "playready":
                    if not device:
                        raise RuntimeError(
                            "PlayReady needs a .prd device file (Settings → Authentication)"
                        )
                    session.drm = Drm.from_playready(session.api, device_path=device)
                else:
                    session.drm = Drm.from_widevine(session.api, device_path=device)
            except BaseException:
                await session.close()
                self.status.emit("Authentication failed")
                raise
            api = session.api
            sub = "" if api.active_subscription else " (subscription not confirmed)"
            desc = f"Signed in · {auth.mode} · storefront {api.storefront}{sub}"
            self._info(desc)
            if not api.active_subscription:
                self._warn("An active Apple Music subscription was not confirmed.")
            self._session = session
            self.profile_changed.emit(await self._social_profile(api))
            self.session_changed.emit(True, desc)
            self.status.emit("Ready")
            return session

    @staticmethod
    async def _social_profile(api: AppleMusicApi) -> dict[str, str]:
        """Read the signed-in Apple Music social profile when it is available."""
        try:
            # Apple currently exposes this user-scoped profile through its
            # Music API service; accounts without a Music profile may return
            # no data, which is a normal fallback case for the account card.
            profile = await api._get("/v1/me/social-profile", operation="get_social_profile")
            data = profile.get("data") or []
            item = data[0] if isinstance(data, list) and data else data
            attrs = item.get("attributes", item) if isinstance(item, dict) else {}
            if not isinstance(attrs, dict):
                return {}
            name = next((attrs.get(k) for k in ("name", "displayName", "fullName", "handle", "username") if isinstance(attrs.get(k), str) and attrs.get(k).strip()), "")
            image = next((attrs.get(k) for k in ("artwork", "profileImage", "avatar", "image") if attrs.get(k)), "")
            if isinstance(image, dict):
                image = image.get("url") or image.get("template") or ""
            if isinstance(image, str):
                # Apple's image templates also carry {c} (crop) and {f} (format).
                image = image.replace("{w}", "256").replace("{h}", "256").replace("{c}", "cc").replace("{f}", "jpg")
            else:
                image = ""
            return {"name": name, "image": image if image.startswith("https://") else ""}
        except Exception:  # noqa: BLE001 - profile data is optional
            return {}

    # ---- search ----------------------------------------------------------

    def search(self, token: int, term: str, resource_type: str, api_name: str):
        async def run():
            session = await self._get_session()
            itunes = None
            if api_name == "itunes":
                itunes = await session.stack.enter_async_context(
                    await ItunesApi.create(
                        storefront=session.api.storefront, search_only=True
                    )
                )
            caches = create_search_caches(
                session.api,
                term,
                (resource_type,),
                search_api=api_name,
                itunes_api=itunes,
            )
            self._search_caches = {"token": token, "cache": caches[resource_type], "page": 0}
            await self._emit_search_page(token, resource_type)

        return self.submit(run())

    def search_more(self, token: int, resource_type: str):
        return self.submit(self._emit_search_page(token, resource_type))

    async def _emit_search_page(self, token: int, resource_type: str) -> None:
        state = self._search_caches
        if state.get("token") != token:
            return
        page = await state["cache"].get(state["page"])
        state["page"] += 1
        items = list(page.items) if page else []
        has_more = bool(page and page.next_cursor)
        self.search_page.emit(token, resource_type, items, has_more)

    # ---- downloads -------------------------------------------------------

    def start_job(
        self,
        sources: list[str | SearchSource],
        *,
        select_tracks: bool = False,
        ask_streams: bool = False,
    ) -> int:
        job = Job(self._next_job, sources, select_tracks, ask_streams)
        self._next_job += 1
        future = self.submit(self._run_job(job))
        self._jobs[job.id] = future
        future.add_done_callback(lambda _: self._jobs.pop(job.id, None))
        return job.id

    def cancel_job(self, job_id: int) -> None:
        future = self._jobs.get(job_id)
        if future is not None:
            future.cancel()

    def cancel_all(self) -> None:
        for future in list(self._jobs.values()):
            future.cancel()

    @property
    def busy(self) -> bool:
        return bool(self._jobs)

    async def _run_job(self, job: Job) -> None:
        self.job_started.emit(job.id)
        counts = job.counts
        found = 0
        try:
            found = await self._download(job)
        except asyncio.CancelledError:
            self._warn(f"Job {job.id} cancelled")
            counts["cancelled"] += 1
        except Exception as error:  # noqa: BLE001 - surface every failure
            counts["failed"] += 1
            self._error(f"Job {job.id}: {short_error(error)}")
            self.log.emit("debug", traceback.format_exc())
        finally:
            summary = dict(counts)
            summary["found"] = found
            self.job_finished.emit(job.id, summary)
            self.status.emit("Ready")

    def _download_gate(self, size: int) -> asyncio.Semaphore:
        size = max(1, int(size or 1))
        if self._gate is None or size != self._gate_size:
            self._gate, self._gate_size = asyncio.Semaphore(size), size
        return self._gate

    async def _download(self, job: Job) -> int:
        cfg = self.settings.load()
        dl, out, db = cfg.download, cfg.output, cfg.database
        gate = self._download_gate(dl.concurrent_downloads)
        if not out.directory:
            raise RuntimeError("Choose an output folder in Settings → Output first.")
        session = await self._get_session()
        api, wrapper = session.api, session.wrapper
        if wrapper is None and (
            (dl.song_codec or "").startswith("alac")
            or any(c.startswith("alac") for c in (dl.song_codec_priority or []))
        ):
            self._warn(
                "ALAC selected without Wrapper: Apple Music may refuse "
                "Widevine/PlayReady licenses for lossless streams."
            )
        output_dir = Path(out.directory).expanduser()
        output_dir.mkdir(parents=True, exist_ok=True)
        formatter = PathFormatter(
            output_dir,
            album_folder_template=out.album_folder_template,
            compilation_folder_template=out.compilation_folder_template,
            no_album_folder_template=out.no_album_folder_template,
            playlist_folder_template=out.playlist_folder_template,
            single_disc_file_template=out.single_disc_file_template,
            multi_disc_file_template=out.multi_disc_file_template,
            no_album_file_template=out.no_album_file_template,
            playlist_file_template=out.playlist_file_template,
            truncate=out.truncate,
        )

        async with AsyncExitStack() as stack:
            itunes = None
            if dl.use_album_date:
                itunes = await stack.enter_async_context(
                    await ItunesApi.create(
                        storefront=api.storefront, language=cfg.auth.language
                    )
                )
            downloader = Downloader(
                drm=session.drm,
                wrapper_api=wrapper,
                itunes_api=itunes,
                tag_resolver=TagResolver(
                    wrapper_api=wrapper, itunes_api=itunes, use_album_date=True
                )
                if dl.use_album_date
                else None,
                temp_path=out.temp_path,
                path_formatter=formatter,
                database=MediaDatabase(
                    Path(db.path).expanduser(),
                    root=formatter.output_dir,
                    save_metadata=db.save_metadata,
                    on_created=lambda p: self._info(f"Created database at {p}"),
                )
                if not db.disabled and db.path
                else None,
                concurrency=dl.segment_concurrency,
            )

            artist_values = list(dl.artist_auto_select)
            library_values = list(dl.library_auto_select)
            resolver = MediaResolver(
                api,
                auto_select=[
                    *DEFAULT_AUTO_SELECT,
                    *(
                        ARTIST_AUTO_SELECT_NAMES[n]
                        for n in artist_values
                        if n in ARTIST_AUTO_SELECT_NAMES
                    ),
                    *(
                        ARTIST_AUTO_SELECT_NAMES[n]
                        for n in ("all-albums", "music-videos")
                        if "all" in artist_values
                    ),
                    *(
                        LIBRARY_AUTO_SELECT_NAMES[n]
                        for n in library_values
                        if n in LIBRARY_AUTO_SELECT_NAMES
                    ),
                    *(
                        LIBRARY_AUTO_SELECT_NAMES.values()
                        if "all" in library_values
                        else ()
                    ),
                ],
                select=job.select_tracks,
                library_auto_select=bool(library_values),
                selector=lambda request: self.ask("media", request),
            )

            excluded = tuple(out.exclude_tags)
            pending: set[asyncio.Task] = set()
            counts = job.counts
            found = 0
            choose_lock = asyncio.Lock()

            async def process(index: int, media: Media, title: str) -> None:
                last_stage = {"value": None}

                def on_event(event: DownloadEvent) -> None:
                    pct = -1.0
                    detail = ""
                    if event.progress is not None:
                        p = event.progress
                        if p.total_bytes:
                            pct = min(100.0, 100.0 * p.emitted_bytes / p.total_bytes)
                        elif p.total_parts:
                            pct = 100.0 * p.completed_parts / p.total_parts
                        speed = p.speed
                        if speed:
                            detail = f"{speed / 1_048_576:.1f} MB/s"
                        if event.track:
                            detail = f"{event.track} {detail}".strip()
                    label = STAGE_LABELS.get(event.stage, event.stage.value)
                    if event.state == EventState.FAILED:
                        label += " failed"
                    if event.stage != last_stage["value"] or pct >= 0:
                        last_stage["value"] = event.stage
                        self.item_event.emit(job.id, index, label, pct, detail)

                async def choose_stream(request):
                    async with choose_lock:
                        return await self.ask("stream", (title, request))

                kwargs: dict[str, Any] = {
                    "overwrite": dl.overwrite,
                    "tag": not out.no_tag,
                    "exclude_tags": excluded,
                    "save_cover": out.save_cover,
                    "cover_format": out.cover_format,
                    "embedded_cover_size": out.embedded_cover_size,
                    "file_cover_size": out.file_cover_size,
                    "save_lyrics": not out.no_lyrics_file and isinstance(media, Song),
                    "lyrics_file_format": out.lyrics_file_format,
                    "embedded_lyrics_format": out.embedded_lyrics_format,
                    "date_tag_template": out.date_tag_template,
                    "save_playlist": out.save_playlist
                    and media.source is not None
                    and media.source.playlist is not None,
                    "event_callback": on_event,
                }
                ask = job.ask_streams
                if isinstance(media, Song):
                    kwargs.update(
                        codec=SongCodec(dl.song_codec)
                        if dl.song_codec and not ask
                        else None,
                        codec_priority=None
                        if dl.song_codec or ask
                        else [SongCodec(c) for c in dl.song_codec_priority] or None,
                        ask=ask,
                        selector=choose_stream if ask else None,
                    )
                elif isinstance(media, MusicVideo):
                    kwargs.update(
                        video_extension=f".{out.music_video_container}",
                        video_codec=MusicVideoCodec(dl.music_video_codec)
                        if dl.music_video_codec and not ask
                        else None,
                        codec_priority=None
                        if dl.music_video_codec or ask
                        else [MusicVideoCodec(c) for c in dl.music_video_codec_priority]
                        or None,
                        max_height=dl.max_height,
                        ask=ask,
                        selector=choose_stream if ask else None,
                    )
                elif isinstance(media, UploadedVideo):
                    kwargs.update(
                        quality=UploadedVideoQuality(dl.uploaded_video_quality)
                        if dl.uploaded_video_quality and not ask
                        else None,
                        ask=ask,
                        selector=choose_stream if ask else None,
                    )
                try:
                    # Wait for a free download slot, and if Apple keeps
                    # rate-limiting, back off for a minute or two and retry.
                    for attempt in range(3):
                        async with gate:
                            try:
                                result = await downloader.download(media, **kwargs)
                                break
                            except GamdlRateLimitError:
                                if attempt == 2:
                                    raise
                        wait = 60 * (attempt + 1)
                        self._warn(f"{title}: Apple is limiting requests; trying again in {wait} seconds")
                        self.item_event.emit(job.id, index, f"Waiting {wait}s (Apple limit)", -1, "")
                        await asyncio.sleep(wait)
                    counts[result.status.value] += 1
                    self.item_finished.emit(
                        job.id, index, result.status.value, "", str(result.path)
                    )
                except asyncio.CancelledError:
                    self.item_finished.emit(job.id, index, "cancelled", "", "")
                    raise
                except (MediaNotStreamableError, MediaNotFoundError) as error:
                    counts["skipped"] += 1
                    self.item_finished.emit(
                        job.id, index, "skipped", short_error(error), ""
                    )
                except DownloadFinalizationError as error:
                    partial = error.partial_result
                    counts["partial" if partial else "failed"] += 1
                    self._error(f"{title}: {short_error(error)}")
                    self.item_finished.emit(
                        job.id,
                        index,
                        "partial" if partial else "failed",
                        short_error(error),
                        str(partial.path) if partial else "",
                    )
                    if dl.fail_fast:
                        raise
                except Exception as error:  # noqa: BLE001
                    counts["failed"] += 1
                    self._error(f"{title}: {short_error(error)}")
                    self.log.emit("debug", traceback.format_exc())
                    self.item_finished.emit(
                        job.id, index, "failed", short_error(error), ""
                    )
                    if dl.fail_fast:
                        raise

            async def wait_one() -> None:
                nonlocal pending
                done, pending = await asyncio.wait(
                    pending, return_when=asyncio.FIRST_COMPLETED
                )
                for task in done:
                    task.result()

            def iterate(source):
                if isinstance(source, SearchSource):
                    return self._search_source(resolver, api, source)
                if isinstance(source, LibrarySource):
                    return self._library_source(resolver, api, source)
                if source.strip().lower() == "library":
                    return resolver.from_library()
                return resolver.from_url(source.strip())

            try:
                for number, source in enumerate(job.sources):
                    if number:
                        # A short pause between albums and playlists in a bulk
                        # download keeps Apple's API from seeing a burst.
                        await asyncio.sleep(1.0)
                    label = source if isinstance(source, str) else source.label
                    self.status.emit(f"Resolving {label}…")
                    self._info(f"Resolving {label}")
                    try:
                        async with aclosing(iterate(source)) as items:
                            async for media in items:
                                found += 1
                                info = {"title": f"Track {found}", "artist": "", "album": "", "artwork": ""}
                                try:
                                    meta = await media.get_metadata()
                                    attrs = meta.get("attributes", {})
                                    info.update(
                                        title=attrs.get("name") or media.id,
                                        artist=attrs.get("artistName") or "",
                                        album=attrs.get("albumName") or "",
                                        artwork=artwork_url(attrs),
                                        explicit=attrs.get("contentRating") == "explicit",
                                        duration=attrs.get("durationInMillis") or 0,
                                    )
                                except Exception:  # noqa: BLE001
                                    pass
                                title = info["title"]
                                if info["artist"]:
                                    title = f"{info['artist']} — {title}"
                                if isinstance(media, MusicVideo) and downloader.itunes_api is None:
                                    try:
                                        downloader.itunes_api = await stack.enter_async_context(
                                            await ItunesApi.create(
                                                storefront=api.storefront,
                                                language=cfg.auth.language,
                                            )
                                        )
                                        downloader.tag_resolver.itunes_api = downloader.itunes_api
                                    except GamdlApiError:
                                        pass
                                kind = (
                                    "Music video"
                                    if isinstance(media, MusicVideo)
                                    else "Video"
                                    if isinstance(media, UploadedVideo)
                                    else "Song"
                                )
                                info["kind"] = kind
                                self.item_added.emit(job.id, found, info)
                                pending.add(
                                    asyncio.create_task(process(found, media, title))
                                )
                                self.status.emit(f"Downloading ({found} found)…")
                                if len(pending) >= max(1, dl.concurrent_downloads):
                                    await wait_one()
                    except asyncio.CancelledError:
                        raise
                    except Exception as error:  # noqa: BLE001
                        if isinstance(error, (DownloadFinalizationError,)) or dl.fail_fast:
                            raise
                        counts["failed"] += 1
                        self._error(f"{label}: {short_error(error)}")
                        self.log.emit("debug", traceback.format_exc())
                while pending:
                    await wait_one()
            finally:
                for task in pending:
                    task.cancel()
                await asyncio.gather(*pending, return_exceptions=True)
        if found == 0 and not counts["failed"]:
            self._warn("No supported media found.")
        return found

    async def _library_source(self, resolver: MediaResolver, api, source: LibrarySource):
        item_id = source.metadata["id"]
        if source.kind == "albums":
            async for track in resolver.from_album(item_id, is_library=True, select_all=True):
                yield track
        elif source.kind == "playlists":
            async for track in resolver.from_playlist(item_id, is_library=True, select_all=True):
                yield track
        else:
            yield Media.from_metadata(source.metadata, api=api, cover_cache=resolver.cover_cache)

    # ---- the person's library ------------------------------------------------

    def library_pages(self, kind: str, on_page) -> asyncio.Future:
        """Fetch every page of a library category, calling on_page(items, more)."""
        endpoint = {"albums": "albums", "playlists": "playlists", "songs": "songs", "music-videos": "music_videos"}[kind]

        async def run():
            session = await self._get_session()
            fetch = getattr(session.api, f"get_library_{endpoint}")
            offset = 0
            while True:
                response = await fetch(limit=100, offset=offset)
                items = list(response.get("data") or ())
                more = bool(items and response.get("next"))
                on_page(items, more)
                if not more:
                    return offset + len(items)
                offset += len(items)

        return self.submit(run())

    async def _search_source(self, resolver: MediaResolver, api, source: SearchSource):
        metadata = source.metadata
        if source.resource_type == "albums":
            async for track in resolver.from_album(metadata["id"]):
                yield track
        elif source.resource_type in {"playlists", "user-playlists"}:
            async for track in resolver.from_playlist(metadata["id"]):
                yield track
        elif metadata.get("_search_api") == "itunes":
            yield Media.from_id(
                metadata["id"],
                media_type=metadata["type"],
                api=api,
                cover_cache=resolver.cover_cache,
            )
        else:
            yield Media.from_metadata(
                metadata, api=api, cover_cache=resolver.cover_cache
            )

    # ---- playback ----------------------------------------------------------

    def fetch_stream(self, metadata: dict) -> asyncio.Future:
        """Fetch one song as playable AAC into the stream cache."""
        return self.submit(self._fetch_stream(metadata))

    async def _fetch_stream(self, metadata: dict) -> str:
        cache = stream_cache_dir()
        path = cache / f"{metadata['id']}.m4a"
        if path.is_file():
            path.touch()
            return str(path)
        if not hasattr(self, "_stream_locks"):
            self._stream_locks: dict[str, asyncio.Lock] = {}
        lock = self._stream_locks.setdefault(metadata["id"], asyncio.Lock())
        async with lock:
            if path.is_file():
                return str(path)
            session = await self._get_session()
            if metadata.get("attributes"):
                media = Media.from_metadata(metadata, api=session.api)
            else:
                media = Media.from_id(metadata["id"], media_type=metadata.get("type", "songs"), api=session.api)
            if not isinstance(media, Song):
                raise RuntimeError("Only songs can be played in the app.")
            if session.stream_downloader is None:
                session.stream_downloader = Downloader(
                    drm=session.drm, wrapper_api=session.wrapper, concurrency=8
                )
            result = await session.stream_downloader.download(
                media,
                output=path,
                codec_priority=[SongCodec("aac"), SongCodec("aac-web")],
                # Playback reads title, artwork and lyrics from Apple directly;
                # skipping tags and the cover download saves about a second.
                tag=False,
            )
            _prune_cache(cache)
            return str(result.path)

    def fetch_lyrics(self, metadata: dict) -> asyncio.Future:
        """Timed lyric lines for a song: [{"t": ms, "end": ms, "text": str}]."""

        async def run():
            session = await self._get_session()
            if metadata.get("attributes"):
                media = Media.from_metadata(metadata, api=session.api)
            else:
                media = Media.from_id(metadata["id"], media_type=metadata.get("type", "songs"), api=session.api)
            if not isinstance(media, Song):
                return None
            lyrics = await media.get_lyrics()
            if lyrics is None:
                return None
            return [{"t": line.start, "end": line.end, "text": line.text} for line in lyrics.lines]

        return self.submit(run())

    def artist_page(self, artist_id: str) -> asyncio.Future:
        """An artist's top songs, albums and singles from the catalog."""

        async def run():
            session = await self._get_session()
            return await session.api.get_artist(
                artist_id, include="", views="top-songs,full-albums,singles", limit=40
            )

        return self.submit(run())

    def collection_tracks(self, kind: str, metadata: dict) -> asyncio.Future:
        """Resolve the songs of an album or playlist for the play queue."""

        async def run():
            session = await self._get_session()
            resolver = MediaResolver(session.api)
            is_library = kind.startswith("library-")
            base = kind.removeprefix("library-")
            source = (
                resolver.from_album(metadata["id"], is_library=is_library, select_all=True)
                if base == "albums"
                else resolver.from_playlist(metadata["id"], is_library=is_library, select_all=True)
            )
            tracks = []
            async with aclosing(source) as items:
                async for media in items:
                    if isinstance(media, Song):
                        tracks.append(await media.get_metadata())
                    if len(tracks) >= 300:
                        break
            return tracks

        return self.submit(run())

    def run_in_loop(self, coro_factory: Callable[[], Any]):
        """Run an awaitable produced by ``coro_factory`` on the engine loop."""

        async def wrapper():
            return await coro_factory()

        return self.submit(wrapper())
