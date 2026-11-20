"""Settings schema rendered by the web UI. Keys map 1:1 onto gamdl's config."""

from __future__ import annotations

from . import APP_NAME
from .config import (
    ARTIST_AUTO,
    LIBRARY_AUTO,
    LYRICS_FORMATS,
    SONG_CODECS,
    TAG_NAMES,
    UPLOADED_QUALITIES,
    VIDEO_CODECS,
)

COVER_SIZES = ["max", "600", "1200", "2000", "3000", "5000"]


def F(section, key, label, kind, help="", choices=None):  # noqa: N802
    return {"section": section, "key": key, "label": label, "type": kind,
            "help": help, "choices": choices or []}


SCHEMA = [
    {"id": "account", "title": "Account", "groups": [
        {"title": "Sign-in method", "fields": [
            F("auth", "mode", "Method", "choice-opt",
              "Cookies uses a cookies.txt you export from music.apple.com. Wrapper connects to a running wrapper-v2 service.",
              [["cookies", "Cookies file"], ["media-user-token", "Media User Token"], ["wrapper", "Wrapper"]]),
            F("auth", "cookies_path", "Cookies file", "file", "Netscape cookies.txt that contains media-user-token."),
            F("auth", "media_user_token", "Media User Token", "password", "Keep this private, like a password."),
            F("auth", "wrapper_url", "Wrapper URL", "text"),
            F("auth", "wrapper_decrypt_host", "Wrapper decrypt host", "text"),
            F("auth", "wrapper_decrypt_port", "Wrapper decrypt port", "int"),
        ]},
        {"title": "Region and DRM", "fields": [
            F("auth", "storefront", "Storefront", "text-opt", "Two-letter country code. Leave empty to use your account's."),
            F("auth", "language", "Metadata language", "text"),
            F("auth", "drm_backend", "DRM backend", "choice", "", [["widevine", "Widevine"], ["playready", "PlayReady"]]),
            F("auth", "device_path", "Device file", "file-opt",
              "Optional for Widevine, which has a built-in L3 device. PlayReady needs a .prd file."),
        ]},
    ]},
    {"id": "quality", "title": "Quality", "groups": [
        {"title": "Songs", "fields": [
            F("download", "song_codec_priority", "Codec priority", "order", APP_NAME + " tries checked codecs from top to bottom.", SONG_CODECS),
            F("download", "song_codec", "Exact codec", "choice-opt", "Overrides the priority list.", SONG_CODECS),
        ]},
        {"title": "Music videos", "fields": [
            F("download", "music_video_codec_priority", "Codec priority", "order", "", VIDEO_CODECS),
            F("download", "music_video_codec", "Exact codec", "choice-opt", "", VIDEO_CODECS),
            F("download", "max_height", "Maximum height", "int", "Above 1080p needs a Widevine L1 or PlayReady SL3000 device."),
            F("output", "music_video_container", "Container", "choice", "", ["m4v", "mp4"]),
            F("download", "uploaded_video_quality", "Uploaded video quality", "choice-opt", "", UPLOADED_QUALITIES),
        ]},
    ]},
    {"id": "downloads", "title": "Downloads", "groups": [
        {"title": "Location", "fields": [
            F("output", "directory", "Music folder", "folder-opt"),
            F("output", "temp_path", "Temporary folder", "folder-opt"),
        ]},
        {"title": "Behavior", "fields": [
            F("download", "concurrent_downloads", "Tracks at once", "int"),
            F("download", "segment_concurrency", "Connections per track", "int"),
            F("download", "overwrite", "Replace existing files", "check"),
            F("download", "use_album_date", "Use album release date", "check"),
            F("download", "fail_fast", "Stop at the first error", "check"),
            F("output", "save_playlist", "Write .m3u8 playlist files", "check"),
        ]},
        {"title": "Artists and library", "fields": [
            F("download", "artist_auto_select", "Artist categories", "order", "Downloaded from an artist link without asking.", ARTIST_AUTO),
            F("download", "library_auto_select", "Library categories", "order", "", LIBRARY_AUTO),
        ]},
    ]},
    {"id": "naming", "title": "File naming", "groups": [
        {"title": "Folders", "fields": [
            F("output", "album_folder_template", "Album", "text"),
            F("output", "compilation_folder_template", "Compilation", "text"),
            F("output", "no_album_folder_template", "No album", "text"),
            F("output", "playlist_folder_template", "Playlist", "text"),
        ]},
        {"title": "Files", "fields": [
            F("output", "single_disc_file_template", "Single disc", "text"),
            F("output", "multi_disc_file_template", "Multi disc", "text"),
            F("output", "no_album_file_template", "No album", "text"),
            F("output", "playlist_file_template", "Playlist", "text"),
            F("output", "truncate", "Shorten names to", "int-opt", "Characters. Leave empty for no limit."),
        ]},
    ]},
    {"id": "tags", "title": "Tags & lyrics", "groups": [
        {"title": "Tags", "fields": [
            F("output", "no_tag", "Don't write tags", "check"),
            F("output", "exclude_tags", "Skip these tags", "order", "Checked tags are left out of files.", TAG_NAMES),
            F("output", "date_tag_template", "Date format", "text"),
        ]},
        {"title": "Artwork", "fields": [
            F("output", "embedded_cover_size", "Embedded size", "cover", "", COVER_SIZES),
            F("output", "save_cover", "Save cover as a file", "check"),
            F("output", "cover_format", "Cover file format", "choice", "", ["jpg", "png"]),
            F("output", "file_cover_size", "Cover file size", "cover", "", COVER_SIZES),
        ]},
        {"title": "Lyrics", "fields": [
            F("output", "no_lyrics_file", "Don't save a lyrics file", "check"),
            F("output", "lyrics_file_format", "Lyrics file format", "choice", "", LYRICS_FORMATS),
            F("output", "embedded_lyrics_format", "Embedded lyrics format", "choice", "", LYRICS_FORMATS),
        ]},
    ]},
    {"id": "advanced", "title": "Advanced", "groups": [
        {"title": "Media database", "fields": [
            F("database", "disabled", "Turn off the database", "check"),
            F("database", "save_metadata", "Store full metadata", "check"),
            F("database", "path", "Database file", "file"),
        ]},
        {"title": "Search", "fields": [
            F("search", "api", "Search with", "choice", "", [["apple-music", "Apple Music"], ["itunes", "iTunes"]]),
        ]},
    ]},
]
