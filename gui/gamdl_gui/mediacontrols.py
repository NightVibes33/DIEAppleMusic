"""Playback controls that work while the window is in the background or minimized.

* Media keys (play/pause, next, previous, stop) are registered system-wide, so
  keyboard and headset buttons reach the app from anywhere.
* The taskbar thumbnail gets previous / play-pause / next buttons.

Both use Windows APIs directly through ctypes, so nothing extra is bundled.
"""

from __future__ import annotations

import ctypes
import sys
from ctypes import HRESULT, POINTER, byref, c_uint, c_void_p, c_wchar, wintypes
from pathlib import Path

from PySide6.QtCore import QAbstractNativeEventFilter, QObject, QTimer, Signal
from PySide6.QtGui import QColor, QIcon, QImage, QPainter

WM_HOTKEY, WM_COMMAND, THBN_CLICKED = 0x0312, 0x0111, 0x1800
MOD_NOREPEAT = 0x4000
# hotkey / button id -> (virtual key, action)
_KEYS = {1: (0xB3, "toggle"), 2: (0xB0, "next"), 3: (0xB1, "prev"), 4: (0xB2, "stop")}
_BUTTONS = [(11, "prev", "Previous"), (12, "toggle", "Play"), (13, "next", "Next")]


class _THUMBBUTTON(ctypes.Structure):
    _fields_ = [
        ("dwMask", wintypes.DWORD), ("iId", c_uint), ("iBitmap", c_uint),
        ("hIcon", wintypes.HICON), ("szTip", c_wchar * 260), ("dwFlags", wintypes.DWORD),
    ]


class _GUID(ctypes.Structure):
    _fields_ = [("Data1", wintypes.DWORD), ("Data2", wintypes.WORD), ("Data3", wintypes.WORD), ("Data4", ctypes.c_ubyte * 8)]

    @classmethod
    def parse(cls, text: str) -> "_GUID":
        guid = cls()
        ctypes.oledll.ole32.CLSIDFromString(ctypes.c_wchar_p(text), byref(guid))
        return guid


def _method(obj, index, *argtypes):
    vtable = ctypes.cast(obj, POINTER(POINTER(c_void_p))).contents
    return ctypes.WINFUNCTYPE(HRESULT, c_void_p, *argtypes)(vtable[index])


def _light_taskbar() -> bool:
    try:
        import winreg

        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize")
        return bool(winreg.QueryValueEx(key, "SystemUsesLightTheme")[0])
    except OSError:
        return False


def _icon(path: Path, color: QColor) -> int:
    """An HICON for a toolbar button, tinted to suit the taskbar."""
    image = QIcon(str(path)).pixmap(32, 32).toImage().convertToFormat(QImage.Format.Format_ARGB32_Premultiplied)
    painter = QPainter(image)
    painter.setCompositionMode(QPainter.CompositionMode.CompositionMode_SourceIn)
    painter.fillRect(image.rect(), color)
    painter.end()
    return int(image.toHICON())


class _Filter(QAbstractNativeEventFilter):
    def __init__(self, owner: "MediaControls") -> None:
        super().__init__()
        self._owner = owner

    def nativeEventFilter(self, event_type, message):  # noqa: N802
        if event_type != b"windows_generic_MSG":
            return False, 0
        msg = wintypes.MSG.from_address(int(message))
        return self._owner._handle(msg), 0


class MediaControls(QObject):
    """Emits ``action`` ("toggle", "next", "prev", "stop") from media keys and
    taskbar buttons. Call ``attach`` once the window exists."""

    action = Signal(str)

    def __init__(self, icons_dir: Path) -> None:
        super().__init__()
        self._icons_dir = icons_dir
        self._hwnd = 0
        self._taskbar = c_void_p()
        self._playing = False
        self._icons: dict[str, int] = {}
        self._buttons_added = False
        self._filter = _Filter(self)
        self._taskbar_created = 0
        self.keys_registered: list[str] = []

    def attach(self, window) -> None:
        if sys.platform != "win32" or self._hwnd:
            return
        from PySide6.QtCore import QCoreApplication

        self._hwnd = int(window.winId())
        QCoreApplication.instance().installNativeEventFilter(self._filter)
        user32 = ctypes.windll.user32
        for ident, (vk, name) in _KEYS.items():
            # Fails quietly if another app already owns the key; the in-window
            # shortcut still works then.
            if user32.RegisterHotKey(wintypes.HWND(self._hwnd), ident, MOD_NOREPEAT, vk):
                self.keys_registered.append(name)
        self._taskbar_created = user32.RegisterWindowMessageW("TaskbarButtonCreated")
        # The taskbar button exists once the window is shown.
        QTimer.singleShot(800, self._add_buttons)

    def detach(self) -> None:
        if self._hwnd:
            for ident in _KEYS:
                ctypes.windll.user32.UnregisterHotKey(wintypes.HWND(self._hwnd), ident)

    def set_playing(self, playing: bool) -> None:
        if playing != self._playing:
            self._playing = playing
            self._update_buttons()

    # ---- taskbar thumbnail buttons ----
    def _ensure_icons(self) -> None:
        color = QColor("#1c1c1c") if _light_taskbar() else QColor("#ffffff")
        for name, file in (("prev", "prev"), ("next", "next"), ("play", "play-f"), ("pause", "pause-f")):
            self._icons[name] = _icon(self._icons_dir / f"{file}.svg", color)

    def _make_buttons(self):
        buttons = (_THUMBBUTTON * len(_BUTTONS))()
        for i, (ident, name, tip) in enumerate(_BUTTONS):
            icon = ("pause" if self._playing else "play") if name == "toggle" else name
            buttons[i].dwMask = 0x2 | 0x4 | 0x8  # icon, tooltip, flags
            buttons[i].iId = ident
            buttons[i].hIcon = self._icons[icon]
            buttons[i].szTip = ("Pause" if self._playing else "Play") if name == "toggle" else tip
            buttons[i].dwFlags = 0  # enabled
        return buttons

    def _add_buttons(self) -> None:
        try:
            if not self._taskbar:
                ole32 = ctypes.oledll.ole32
                try:
                    ole32.CoInitializeEx(None, 2)
                except OSError:
                    pass
                ole32.CoCreateInstance(
                    byref(_GUID.parse("{56FDF344-FD6D-11d0-958A-006097C9A090}")), None, 1,
                    byref(_GUID.parse("{EA1AFB91-9E28-4B86-90E9-9E9F8A5EEFAF}")), byref(self._taskbar),
                )
                _method(self._taskbar, 3)(self._taskbar)  # HrInit
            self._ensure_icons()
            buttons = self._make_buttons()
            _method(self._taskbar, 15, wintypes.HWND, c_uint, POINTER(_THUMBBUTTON))(
                self._taskbar, wintypes.HWND(self._hwnd), len(buttons), buttons
            )
            self._buttons_added = True
        except OSError:
            self._buttons_added = False

    def _update_buttons(self) -> None:
        if not self._buttons_added:
            return
        try:
            buttons = self._make_buttons()
            _method(self._taskbar, 16, wintypes.HWND, c_uint, POINTER(_THUMBBUTTON))(
                self._taskbar, wintypes.HWND(self._hwnd), len(buttons), buttons
            )
        except OSError:
            pass

    # ---- messages ----
    def _handle(self, msg) -> bool:
        if msg.message == WM_HOTKEY and msg.wParam in _KEYS:
            self.action.emit(_KEYS[msg.wParam][1])
            return True
        if msg.message == WM_COMMAND and (msg.wParam >> 16) & 0xFFFF == THBN_CLICKED and msg.hWnd == self._hwnd:
            ident = msg.wParam & 0xFFFF
            for button_id, name, _tip in _BUTTONS:
                if ident == button_id:
                    self.action.emit(name)
                    return True
        if self._taskbar_created and msg.message == self._taskbar_created:
            # Explorer restarted; the taskbar forgot the buttons.
            self._buttons_added = False
            QTimer.singleShot(500, self._add_buttons)
        return False
