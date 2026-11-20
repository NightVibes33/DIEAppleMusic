"""Windows master volume (the taskbar volume) through Core Audio, using ctypes.

Talks to IAudioEndpointVolume on the default playback device directly, so no
extra packages are needed. Every call looks up the default device again, so
switching to headphones or a USB DAC is picked up automatically.
"""

from __future__ import annotations

import ctypes
import sys
from ctypes import HRESULT, POINTER, byref, c_float, c_int, c_uint, c_void_p
from ctypes import wintypes


class _GUID(ctypes.Structure):
    _fields_ = [("Data1", wintypes.DWORD), ("Data2", wintypes.WORD), ("Data3", wintypes.WORD), ("Data4", ctypes.c_ubyte * 8)]

    @classmethod
    def parse(cls, text: str) -> "_GUID":
        guid = cls()
        ctypes.oledll.ole32.CLSIDFromString(ctypes.c_wchar_p(text), byref(guid))
        return guid


_CLSID_ENUMERATOR = "{BCDE0395-E52F-467C-8E3D-C4579291692E}"
_IID_ENUMERATOR = "{A95664D2-9614-4F35-A746-DE8DB63617E6}"
_IID_ENDPOINT_VOLUME = "{5CDF2C82-841E-4546-9722-0CF74078229A}"
_CLSCTX_ALL = 23
_RENDER, _MULTIMEDIA = 0, 1


def _method(obj: c_void_p, index: int, *argtypes):
    """A COM method from the object's vtable."""
    vtable = ctypes.cast(obj, POINTER(POINTER(c_void_p))).contents
    return ctypes.WINFUNCTYPE(HRESULT, c_void_p, *argtypes)(vtable[index])


def _release(obj: c_void_p) -> None:
    if obj:
        vtable = ctypes.cast(obj, POINTER(POINTER(c_void_p))).contents
        ctypes.WINFUNCTYPE(c_uint, c_void_p)(vtable[2])(obj)


class SystemVolume:
    """Get and set the default playback device's master volume (0..1) and mute."""

    def __init__(self) -> None:
        self._enumerator = c_void_p()
        self.available = False
        if sys.platform != "win32":
            return
        try:
            ole32 = ctypes.oledll.ole32
            try:
                ole32.CoInitializeEx(None, 2)  # apartment threaded, like Qt's GUI thread
            except OSError:
                pass  # already initialized on this thread
            ole32.CoCreateInstance(
                byref(_GUID.parse(_CLSID_ENUMERATOR)), None, _CLSCTX_ALL,
                byref(_GUID.parse(_IID_ENUMERATOR)), byref(self._enumerator),
            )
            self.available = self._endpoint() is not None
        except OSError:
            self.available = False

    def _endpoint(self) -> c_void_p | None:
        """IAudioEndpointVolume of the current default output, or None."""
        device = c_void_p()
        try:
            _method(self._enumerator, 4, c_int, c_int, POINTER(c_void_p))(self._enumerator, _RENDER, _MULTIMEDIA, byref(device))
            volume = c_void_p()
            iid = _GUID.parse(_IID_ENDPOINT_VOLUME)
            _method(device, 3, POINTER(_GUID), wintypes.DWORD, c_void_p, POINTER(c_void_p))(device, byref(iid), _CLSCTX_ALL, None, byref(volume))
            return volume
        except OSError:
            return None  # no playback device right now
        finally:
            _release(device)

    def get(self) -> tuple[float, bool] | None:
        """(level 0..1, muted), or None if there is no playback device."""
        endpoint = self._endpoint()
        if endpoint is None:
            return None
        try:
            level, muted = c_float(), wintypes.BOOL()
            _method(endpoint, 9, POINTER(c_float))(endpoint, byref(level))
            _method(endpoint, 15, POINTER(wintypes.BOOL))(endpoint, byref(muted))
            return float(level.value), bool(muted.value)
        except OSError:
            return None
        finally:
            _release(endpoint)

    def set_level(self, level: float) -> None:
        endpoint = self._endpoint()
        if endpoint is None:
            return
        try:
            _method(endpoint, 7, c_float, c_void_p)(endpoint, max(0.0, min(1.0, level)), None)
            if level > 0:
                _method(endpoint, 14, wintypes.BOOL, c_void_p)(endpoint, False, None)  # dragging up unmutes
        except OSError:
            pass
        finally:
            _release(endpoint)

    def set_muted(self, muted: bool) -> None:
        endpoint = self._endpoint()
        if endpoint is None:
            return
        try:
            _method(endpoint, 14, wintypes.BOOL, c_void_p)(endpoint, bool(muted), None)
        except OSError:
            pass
        finally:
            _release(endpoint)
