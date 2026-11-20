# Third-party notices

死ねアップル is licensed under the GNU General Public License v3.0 ([LICENSE](LICENSE)). It's built on, and its releases bundle, the open-source software listed below. Each component remains under its own license. Versions are the ones used for the current release.

## Download engine

| Component | Version | License | Source |
| --- | --- | --- | --- |
| gamdl (Glomatico's Apple Music Downloader) | 4.0.1 | MIT ([`LICENSES/gamdl-MIT.txt`](LICENSES/gamdl-MIT.txt)) | https://github.com/glomatico/gamdl |

The files under `src/`, `native/`, `tests/` and `docs/gamdl-*` come from gamdl, and you can use them under its MIT License.

## Runtime and interface

| Component | Version | License | Source |
| --- | --- | --- | --- |
| Python | 3.12 | PSF License 2.0 ([`LICENSES/Python-PSF.txt`](LICENSES/Python-PSF.txt)) | https://www.python.org |
| Qt 6 (including Qt Quick, Qt Multimedia and Qt WebEngine) | 6.12 | LGPL-3.0 ([`LICENSES/LGPL-3.0.txt`](LICENSES/LGPL-3.0.txt)) | https://code.qt.io, https://download.qt.io/official_releases/qt/ |
| PySide6 / Shiboken6 (Qt for Python) | 6.12.0 | LGPL-3.0 | https://code.qt.io/cgit/pyside/pyside-setup.git |
| Chromium (inside Qt WebEngine, used for the Apple sign-in panel) | — | BSD-3-Clause and others; see Qt WebEngine's licensing | https://doc.qt.io/qt-6/qtwebengine-licensing.html |
| FFmpeg (inside Qt Multimedia) | 9.0 | LGPL-2.1-or-later | https://ffmpeg.org |

**LGPL compliance.** The full text of the LGPL-3.0 is in [`LICENSES/LGPL-3.0.txt`](LICENSES/LGPL-3.0.txt); it builds on the GPL-3.0 in [`LICENSE`](LICENSE). Both ship inside the app. Qt, PySide6 and FFmpeg are included unmodified, as separate dynamic libraries (`_internal\PySide6\*.dll`). You can replace them with your own builds of the same versions. Their complete source code is available from the links above, and the source code of this app is in this repository.

## Python libraries

| Component | Version | License |
| --- | --- | --- |
| pywidevine | 1.9.0 | GPL-3.0-only |
| mutagen | 1.48.1 | GPL-2.0-or-later |
| Unidecode | 1.4.0 | GPL-2.0-or-later |
| httpx | 0.28.1 | BSD-3-Clause |
| httpcore | 1.0.9 | BSD-3-Clause |
| httpx-retries | 0.6.0 | MIT |
| h11 | 0.16.0 | MIT |
| anyio | 4.16.0 | MIT |
| idna | 3.20 | BSD-3-Clause |
| certifi | 2026.10.23 | MPL-2.0 |
| requests | 2.34.2 | Apache-2.0 |
| urllib3 | 2.8.0 | MIT |
| charset-normalizer | 3.5.2 | MIT |
| pycryptodome | 3.24.1 | BSD-2-Clause and Public Domain |
| protobuf | 6.33.6 | BSD-3-Clause |
| construct | 2.8.8 | MIT |
| pymp4 | 1.4.0 | Apache-2.0 |
| m3u8 | 6.0.0 | MIT |
| PyYAML | 6.0.3 | MIT |
| platformdirs | 4.14.5 | MIT |
| async-lru | 2.4.0 | MIT |
| structlog | 26.1.0 | MIT or Apache-2.0 |
| click | 8.5.1 | BSD-3-Clause |
| dataclass-click | 1.0.4 | BSD |
| rich | 15.0.0 | MIT |
| markdown-it-py | 4.3.0 | MIT |
| mdurl | 0.1.2 | MIT |
| Pygments | 2.21.0 | BSD-2-Clause |
| questionary | 2.1.1 | MIT |
| prompt_toolkit | 3.0.53 | BSD-3-Clause |
| wcwidth | 0.9.4 | MIT |
| cffi | 2.1.1 | MIT-0 |
| pycparser | 3.12 | BSD-3-Clause |
| typing_extensions | 4.16.0 | PSF-2.0 |
| packaging | 26.3 | Apache-2.0 or BSD-2-Clause |

Each library's full license text is in its source distribution and on [PyPI](https://pypi.org).

## Build tools

| Tool | License | Notes |
| --- | --- | --- |
| PyInstaller | GPL-2.0-or-later with a bootloader exception | The bundled bootloader (`死ねアップル.exe`) may be distributed under any license. |
| Inno Setup | Inno Setup License | Builds `死ねアップル-Setup.exe`. https://jrsoftware.org/isinfo.php |

## Services

Lyrics come from Apple Music or from [LRCLIB](https://lrclib.net), a free, open lyrics database. No LRCLIB software is bundled.

Apple Music is a trademark of Apple Inc. This project isn't affiliated with or endorsed by Apple.
