"""Entry point for the packaged app."""

import importlib.machinery
import importlib.util
import ctypes
import os
import sys
from pathlib import Path

if getattr(sys, "frozen", False):
    # Put the bundled Qt/Shiboken directories on the DLL search path and load
    # the exact bundled core DLLs before PySide's extension modules import.
    # This prevents an older Qt6Core.dll elsewhere on PATH (or left beside an
    # older installation) from being selected by the Windows loader.
    if sys.platform == "win32":
        _bundle = Path(getattr(sys, "_MEIPASS", ""))
        _dll_dirs = (_bundle, _bundle / "PySide6", _bundle / "shiboken6")
        _dll_handles = [os.add_dll_directory(str(p)) for p in _dll_dirs if p.is_dir()]
        _winmode = 0x00000100 | 0x00001000  # DLL_LOAD_DIR | DEFAULT_DIRS
        # PyInstaller can collect an unrelated ICU 78 DLL from PATH. That
        # library exports version-suffixed names (ucnv_open_78), while QtCore
        # imports Windows' stable, unsuffixed ICU C API. Load Windows ICU first
        # so it wins by module name before QtCore resolves its dependencies.
        _system_icu = Path(os.environ.get("WINDIR", r"C:\Windows")) / "System32" / "icuuc.dll"
        if not _system_icu.is_file():
            ctypes.windll.user32.MessageBoxW(
                None,
                "This app requires Windows 10 version 1703 or newer (Windows ICU is missing).",
                "死ねアップル",
                0x10,
            )
            raise SystemExit(1)
        ctypes.WinDLL(str(_system_icu), winmode=_winmode)
        for _dll in (
            _bundle / "shiboken6" / "shiboken6.abi3.dll",
            _bundle / "PySide6" / "Qt6Core.dll",
        ):
            if _dll.is_file():
                ctypes.WinDLL(str(_dll), winmode=_winmode)

    # The download engine's compiled core ships as engine.pyd; load it under
    # the module name the engine expects.
    _native = Path(getattr(sys, "_MEIPASS", "")) / "engine.pyd"
    if _native.is_file():

        class _NativeFinder:
            @classmethod
            def find_spec(cls, name, path=None, target=None):
                if name != "gamdl._native":
                    return None
                loader = importlib.machinery.ExtensionFileLoader(name, str(_native))
                return importlib.util.spec_from_file_location(name, str(_native), loader=loader)

        sys.meta_path.insert(0, _NativeFinder)

from gamdl_gui.app import main

if __name__ == "__main__":
    sys.exit(main())
