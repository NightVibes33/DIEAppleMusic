<p align="center">
  <img src="gui/gamdl_gui/qml/icons/app.png" alt="死ねアップル icon" width="160">
</p>

<h1 align="center">死ねアップル</h1>
<p align="center"><b>DIE! Apple Music</b> — a native Windows app to download and play music from your own Apple Music account.</p>

<p align="center">
  <a href="https://github.com/NightVibes33/DIEAppleMusic/releases/latest">Download</a> ·
  <a href="#build-from-source">Build from source</a> ·
  <a href="THIRD_PARTY_NOTICES.md">Third-party notices</a> ·
  <a href="LICENSE">License (GPL-3.0)</a>
</p>

---

## What's the name?

**死ねアップル** (*shine appuru*) is Japanese for "Die, Apple." It's a tongue-in-cheek jab at Apple, not a warning sign. The app isn't malware: it only downloads and plays music from your own Apple Music account, it never stores your Apple ID password, and its full source code is right here.

Windows may show a SmartScreen warning the first time you run it, because the app isn't signed by a registered publisher. Choose **More info**, then **Run anyway**.

## Features

- **Looks like Apple Music for Windows.** A native Qt Quick interface with an artwork-tinted top bar, a now-playing display and a sidebar library. It's not a web page.
- **Sign in with your Apple ID** on Apple's own sign-in panel inside the app. Two-factor codes work, and the session is remembered between launches. Your password goes straight to Apple.
- **Your whole Apple Music library.** Browse your playlists, albums, songs and music videos, and sort them by recently added, title, artist or release date. Select items one at a time or all at once to download them.
- **Download** songs, albums, playlists, artists and music videos by pasting a link or searching the catalog. Big batches run at a steady pace, so Apple doesn't rate-limit your account.
- **Play** downloaded songs from disk, or stream catalog songs through your account. Songs start fetching when you hover over them, so they play right away. Shuffle, repeat and a queue are all there, and the next track is fetched ahead of time.
- **Now Playing** with breathing artwork colours and synced lyrics (from Apple, or the free [LRCLIB](https://lrclib.net) database).
- **Works in the background.** Media keys and the taskbar's play, pause, next and previous buttons work while the window is minimized. The volume slider is the real Windows volume.
- **Your music folder stays in sync.** Songs you already have are found on a new install. Songs deleted in File Explorer disappear from the app.
- **Simple settings** for most people, with every advanced option (codecs, file naming, tags, DRM devices) one switch away.
- **Installer and portable version.** The installer offers to update, repair or uninstall when you run it again, and closes the app first if it's open. The portable version keeps everything in a `Data` folder next to it.

## Requirements

- 64-bit Windows 10 version 1703 or newer, or Windows 11
- An Apple Music subscription. Without one you can search and play 30-second previews.

Everything the app needs is bundled. Nothing else needs to be installed or downloaded.

## Install

Get the latest release from the [Releases page](https://github.com/NightVibes33/DIEAppleMusic/releases/latest):

| File | What it is |
| --- | --- |
| `DIEAppleMusic-<version>-Setup.exe` | Installer. Installs for your user account without admin rights, adds Start menu and desktop shortcuts, and offers update, repair or uninstall when you run it again. |
| `DIEAppleMusic-<version>-Portable.zip` | Travel version. Unzip it anywhere, such as a USB stick, and run `死ねアップル.exe`. Settings, sign-in and caches stay in the `Data` folder beside it. |

Then open the app, click **Sign In**, sign in with your Apple ID and choose where to save your music.

### Where your data lives

| What | Installed | Portable |
| --- | --- | --- |
| Settings, sign-in cookies, download history, media database | `%APPDATA%\死ねアップル\` | `Data\` |
| Sign-in browser data, playback cache (capped at 1 GB), artwork cache | `%LOCALAPPDATA%\死ねアップル\` | `Data\Cache\` |

Uninstalling asks whether to keep these. Your downloaded music is never touched.

## Build from source

You'll need [Python 3.12](https://www.python.org/downloads/) (64-bit) and, for the installer, [Inno Setup 6](https://jrsoftware.org/isinfo.php).

```bat
py -3.12 -m venv .venv
.venv\Scripts\pip install "gamdl[widevine]==4.0.1" pyinstaller
.venv\Scripts\pip install -e gui
```

Run from source (add `--debug` for Qt logs):

```bat
.venv\Scripts\python -m gamdl_gui
```

Build the app folder, the portable zip and the installer into `release\`:

```powershell
powershell -ExecutionPolicy Bypass -File packaging\build.ps1
```

The version number lives in `gui/gamdl_gui/__init__.py`. The build stamps it into the exe, the installer and the About screen.

To regenerate the icons (`gui/app.ico`, the in-app PNGs and the installer images) from `packaging/icon-source.png`, run this with a Python that has Pillow, numpy and scipy:

```bat
python packaging\make_icon.py
```

### Project layout

| Path | What's there |
| --- | --- |
| `gui/gamdl_gui/app.py` | Qt bridge to the interface, Apple sign-in, system volume and media controls |
| `gui/gamdl_gui/engine.py` | Drives the download engine: downloads, streaming, library, lyrics and search |
| `gui/gamdl_gui/core.py` | Settings, history, library scan, lyrics lookup and library tools |
| `gui/gamdl_gui/qml/` | The interface (Qt Quick) |
| `packaging/` | Build script, installer script, icon generator and installer images |
| `src/gamdl/` | The download engine, from [gamdl](https://github.com/glomatico/gamdl) |

## Credits

The download engine is [**gamdl**](https://github.com/glomatico/gamdl) by Glomatico, used under the MIT License (see [`LICENSES/gamdl-MIT.txt`](LICENSES/gamdl-MIT.txt)). Its command-line documentation is kept in [`docs/gamdl-engine.md`](docs/gamdl-engine.md). The app also uses Qt/PySide6, pywidevine, mutagen and many other open-source libraries; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Disclaimer

This project isn't affiliated with, endorsed by or connected to Apple Inc. Apple Music is a trademark of Apple Inc. Use it only with your own subscription, for your own personal use, and respect copyright law and Apple's terms where you live.

## License

死ねアップル is free software, released under the **GNU General Public License v3.0**; see [LICENSE](LICENSE). The app is GPL-3.0 because it's built on and distributed with [pywidevine](https://github.com/devine-dl/pywidevine), which is GPL-3.0-only. Files that come from gamdl remain available under their original MIT License.
