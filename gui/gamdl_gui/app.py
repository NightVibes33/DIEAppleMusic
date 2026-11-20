"""Native Gamdl desktop app: Qt Quick UI over the gamdl engine."""

from __future__ import annotations

import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PySide6.QtCore import Property, QCoreApplication, QObject, Qt, QTimer, QUrl, Signal, Slot
from PySide6.QtGui import QIcon
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtWidgets import QApplication

from .core import Core


QML_DIR = (
    Path(getattr(sys, "_MEIPASS", "")) / "ui"
    if getattr(sys, "frozen", False) and (Path(getattr(sys, "_MEIPASS", "")) / "ui").is_dir()
    else Path(__file__).parent / "qml"
)


def _style_native_window(win_id: int) -> None:
    """Rounded corners and a dark frame on Windows 11."""
    if sys.platform != "win32":
        return
    try:
        import ctypes

        dwm = ctypes.windll.dwmapi
        for attribute, value in ((33, 2), (20, 1)):  # corner preference, dark mode
            v = ctypes.c_int(value)
            dwm.DwmSetWindowAttribute(int(win_id), attribute, ctypes.byref(v), 4)
    except Exception:  # noqa: BLE001 - cosmetic only
        pass


def signin_storage() -> Path:
    from .paths import cache_dir

    return cache_dir() / "signin"


def _storefront() -> tuple[str, str]:
    """Country and language for Apple's sign-in panel, from the system locale."""
    from PySide6.QtCore import QLocale

    name = QLocale.system().name()  # e.g. en_US
    lang, _, country = name.partition("_")
    country = (country or "US").lower()
    return country, f"{lang or 'en'}-{country.upper()}"


def signin_url() -> str:
    """Apple's own sign-in panel on its own, without the Apple Music web player
    around it. It loads in a few seconds and stores the Apple Music session
    cookie itself when sign-in finishes."""
    country, locale = _storefront()
    return f"https://music.apple.com/includes/commerce/authenticate?iso2code={country}&locale={locale}"


# Loaded only if Apple signs the person in without leaving the Apple Music
# cookie: the web player picks the session up and sets it.
FINISH_URL = "https://music.apple.com/login"

# Runs in every frame of the sign-in panel.
SIGNIN_SCRIPT = r"""(function () {
  // Passkeys open the Windows Security dialog; report that there are none so
  // Apple uses the email, password and code flow.
  try {
    var deny = function () { return Promise.reject(new DOMException('Passkeys are turned off here.', 'NotAllowedError')); };
    if (window.PublicKeyCredential) {
      window.PublicKeyCredential.isConditionalMediationAvailable = function () { return Promise.resolve(false); };
      window.PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable = function () { return Promise.resolve(false); };
    }
    if (navigator.credentials) {
      Object.defineProperty(navigator.credentials, 'get', { value: deny, configurable: true });
      Object.defineProperty(navigator.credentials, 'create', { value: deny, configurable: true });
    }
    try { Object.defineProperty(window, 'PublicKeyCredential', { value: undefined, configurable: true }); } catch (e) {}
  } catch (e) {}

  // Let the app's card show through and drop the page scrollbars.
  var style = function () {
    if (!document.documentElement || document.getElementById('__app_style')) return;
    var s = document.createElement('style');
    s.id = '__app_style';
    s.textContent = 'html, body { background: transparent !important; } ::-webkit-scrollbar { display: none; }';
    (document.head || document.documentElement).appendChild(s);
  };
  style();

  // "Sign in with iPhone" is a passkey (a Windows prompt); go straight to the password.
  var tidy = function () {
    style();
    var buttons = Array.from(document.querySelectorAll('button'));
    var phone = buttons.find(function (b) { return /sign in with iphone/i.test(b.innerText || ''); });
    var pass = buttons.find(function (b) { return /continue with password/i.test(b.innerText || ''); });
    if (phone && pass && pass.offsetParent && !pass.__clicked) { pass.__clicked = true; pass.click(); }
  };
  new MutationObserver(tidy).observe(document, { childList: true, subtree: true });
})();"""

class SignInWatcher(QObject):
    """Reads the cookies Apple sets in the embedded sign-in panel.

    The person signs in on Apple's own panel inside the sign-in screen; we
    only collect the session cookies Apple returns (media-user-token and
    friends) and hand them to gamdl. The browser profile persists, so a session
    that is still valid finishes immediately.
    """

    finished = Signal(bool, str)  # ok, error
    needs_token = Signal()  # signed in to Apple, but no Apple Music cookie yet

    def __init__(self, core: Core) -> None:
        super().__init__()
        self._core = core
        self._store = None
        self._cookies: dict[tuple[str, str, str], dict] = {}
        self._armed = False
        self._done = False
        self._token = False

    def attach(self, store) -> None:
        if self._store is store:
            return
        self._store = store
        store.cookieAdded.connect(self._on_cookie)
        store.cookieRemoved.connect(self._on_removed)
        store.loadAllCookies()

    def arm(self, on: bool) -> None:
        self._armed = on
        self._done = False
        if on and self._token:
            QTimer.singleShot(300, self._finish)

    def forget(self) -> None:
        self._cookies.clear()
        self._token = False
        if self._store is not None:
            self._store.deleteAllCookies()

    def _on_cookie(self, cookie) -> None:
        domain = cookie.domain()
        if "apple.com" not in domain:
            return
        name = bytes(cookie.name()).decode("utf-8", "replace")
        value = bytes(cookie.value()).decode("utf-8", "replace")
        expires = cookie.expirationDate()
        self._cookies[(domain, cookie.path(), name)] = {
            "name": name,
            "value": value,
            "domain": domain,
            "path": cookie.path(),
            "secure": cookie.isSecure(),
            "expires": expires.toSecsSinceEpoch() if expires.isValid() else 0,
        }
        if name == "media-user-token" and value:
            self._token = True
            if self._armed and not self._done:
                # A brief pause lets Apple finish setting the session cookies.
                QTimer.singleShot(300, self._finish)
        elif name == "myacinfo" and value and self._armed and not self._token:
            # Apple has signed the person in; the Apple Music cookie normally
            # follows right away.
            QTimer.singleShot(5000, self._check_token)

    def _check_token(self) -> None:
        if self._armed and not self._done and not self._token:
            self.needs_token.emit()

    def _on_removed(self, cookie) -> None:
        name = bytes(cookie.name()).decode("utf-8", "replace")
        self._cookies.pop((cookie.domain(), cookie.path(), name), None)
        if name == "media-user-token":
            self._token = False

    def _finish(self) -> None:
        if self._done or not self._armed:
            return
        self._done = True
        result = self._core.save_apple_cookies(list(self._cookies.values()))
        self.finished.emit(bool(result.get("ok")), result.get("error", ""))


class Backend(QObject):
    """Object exposed to QML as ``Bridge``."""

    events = Signal(str)  # JSON list of engine events
    result = Signal(int, str)  # call id, JSON result

    def __init__(self) -> None:
        super().__init__()
        self._core = Core(self.events.emit)
        self._pool = ThreadPoolExecutor(max_workers=6, thread_name_prefix="gamdl-call")
        self._next = 0
        self._signin = SignInWatcher(self._core)
        self._signin.finished.connect(self._signin_finished)
        self._signin.needs_token.connect(lambda: self.events.emit(json.dumps([{"type": "signin_finish"}])))
        self._profile = None  # created in QML (SignInScreen) and handed over below
        # The app's volume is the system's master volume. Poll it so changes
        # made with keyboard keys or the taskbar show up in the app at once.
        from .sysvolume import SystemVolume

        self._sysvol = SystemVolume()
        self._volume, self._muted = 1.0, False
        self._vol_timer = QTimer(self)
        self._vol_timer.setInterval(250)
        self._vol_timer.timeout.connect(self._read_volume)
        if self._sysvol.available:
            self._read_volume()
            self._vol_timer.start()
        # Media keys and taskbar buttons work while the app is in the background.
        from .mediacontrols import MediaControls

        self._media = MediaControls(QML_DIR / "icons")
        self._media.action.connect(self.mediaAction)

    volumeChanged = Signal()
    mediaAction = Signal(str)  # "toggle", "next", "prev", "stop" from media keys / taskbar

    def _read_volume(self) -> None:
        state = self._sysvol.get()
        if state is None:
            return
        level, muted = state
        if abs(level - self._volume) > 0.004 or muted != self._muted:
            self._volume, self._muted = level, muted
            self.volumeChanged.emit()

    @Property(bool, constant=True)
    def systemVolumeAvailable(self) -> bool:  # noqa: N802
        return self._sysvol.available

    @Property(float, notify=volumeChanged)
    def systemVolume(self) -> float:  # noqa: N802
        return self._volume

    @Property(bool, notify=volumeChanged)
    def systemMuted(self) -> bool:  # noqa: N802
        return self._muted

    @Slot(float)
    def setSystemVolume(self, level: float) -> None:  # noqa: N802
        self._sysvol.set_level(level)
        self._volume, self._muted = max(0.0, min(1.0, level)), self._muted and level <= 0
        self.volumeChanged.emit()

    @Slot(bool)
    def setSystemMuted(self, muted: bool) -> None:  # noqa: N802
        self._sysvol.set_muted(muted)
        self._muted = muted
        self.volumeChanged.emit()

    @Slot(str, str, result=int)
    def call(self, name: str, args_json: str) -> int:
        """Run a core method off the UI thread; the answer arrives via ``result``."""
        self._next += 1
        call_id = self._next
        args = json.loads(args_json or "[]")

        def run():
            try:
                value = getattr(self._core, name)(*args)
            except Exception as exc:  # noqa: BLE001
                value = {"ok": False, "error": str(exc) or type(exc).__name__}
            self.result.emit(call_id, json.dumps(value, default=str))

        self._pool.submit(run)
        return call_id

    @Slot(str, str, result=str)
    def callSync(self, name: str, args_json: str) -> str:  # noqa: N802
        value = getattr(self._core, name)(*json.loads(args_json or "[]"))
        return json.dumps(value, default=str)

    # ---- Apple sign-in (Apple's own panel, shown in the sign-in screen) ----

    @Slot(QObject)
    def attachSigninProfile(self, profile) -> None:  # noqa: N802
        """Watch the cookies of the profile the sign-in screen created."""
        import shiboken6
        from PySide6.QtWebEngineQuick import QQuickWebEngineProfile

        self._profile = shiboken6.wrapInstance(shiboken6.getCppPointer(profile)[0], QQuickWebEngineProfile)
        self._signin.attach(self._profile.cookieStore())

    @Property(str, constant=True)
    def signinUrl(self) -> str:  # noqa: N802
        return signin_url()

    @Property(str, constant=True)
    def signinFinishUrl(self) -> str:  # noqa: N802
        return FINISH_URL

    @Property(str, constant=True)
    def signinScript(self) -> str:  # noqa: N802
        return SIGNIN_SCRIPT

    @Slot(bool)
    def signinStart(self, fresh: bool) -> None:  # noqa: N802
        """Watch for Apple's session cookie; ``fresh`` forgets the last Apple ID."""
        if fresh:
            self._signin.forget()
        self._signin.arm(True)

    @Slot()
    def signinStop(self) -> None:  # noqa: N802
        self._signin.arm(False)

    @Slot(result=str)
    def signOut(self) -> str:  # noqa: N802
        """Sign out: forget the saved session and the sign-in panel's cookies."""
        result = self._core.sign_out()
        self._signin.arm(False)
        self._signin.forget()
        return json.dumps(result)

    def _signin_finished(self, ok: bool, error: str) -> None:
        self.events.emit(json.dumps([{"type": "apple_signin", "ok": ok, "error": error}]))

    @Slot(str, result=str)
    def fileUrl(self, path: str) -> str:  # noqa: N802
        return QUrl.fromLocalFile(path).toString()

    @Slot(str, result=str)
    def localPath(self, url: str) -> str:  # noqa: N802
        return QUrl(url).toLocalFile()

    @Slot(str)
    def copyText(self, text: str) -> None:  # noqa: N802
        QApplication.clipboard().setText(text)

    @Slot(result=str)
    def clipboardText(self) -> str:  # noqa: N802
        return QApplication.clipboard().text()

    @Slot(QObject)
    def styleWindow(self, window) -> None:  # noqa: N802
        _style_native_window(int(window.winId()))
        self._media.attach(window)

    @Slot(bool)
    def setPlaying(self, playing: bool) -> None:  # noqa: N802
        self._media.set_playing(playing)

    def shutdown(self) -> None:
        self._media.detach()
        self._core.shutdown()
        self._pool.shutdown(wait=False, cancel_futures=True)


def _use_ini_preferences(name: str, folder: Path) -> None:
    """Keep UI preferences in an INI file in the app's data folder (not the
    registry), carrying over anything saved under the old registry key."""
    from PySide6.QtCore import QSettings

    QSettings.setDefaultFormat(QSettings.Format.IniFormat)
    QSettings.setPath(QSettings.Format.IniFormat, QSettings.Scope.UserScope, str(folder))
    app = QCoreApplication.instance()
    app.setOrganizationName("Preferences")
    app.setApplicationName(name)
    current = QSettings()
    old = QSettings(QSettings.Format.NativeFormat, QSettings.Scope.UserScope, "Gamdl", "Gamdl")
    keys = old.allKeys()
    if keys and not current.allKeys():
        for key in keys:
            current.setValue(key, old.value(key))
        current.sync()
    if keys:
        old.clear()
        old.sync()


def run_cli(args: list[str]) -> int:
    """Run gamdl's command line (used by Library Tools in the packaged app)."""
    import io

    for name in ("stdout", "stderr"):
        if getattr(sys, name) is None:
            setattr(sys, name, io.TextIOWrapper(io.FileIO(1 if name == "stdout" else 2, "w"), encoding="utf-8", line_buffering=True))
    from gamdl.cli.main import main as gamdl_main

    sys.argv = ["gamdl", *args]
    try:
        gamdl_main()
    except SystemExit as exc:
        return int(exc.code or 0) if not isinstance(exc.code, str) else 1
    return 0


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--tool":
        return run_cli(sys.argv[2:])
    if sys.platform == "win32":
        try:
            import ctypes

            ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("ShineAppuru.Desktop")
        except Exception:  # noqa: BLE001
            pass
    # Windows Media Foundation: native decoding and clean output. Qt's FFmpeg
    # engine nudges resampling speed to keep sync, which can sound warbly.
    # Windows "N" editions ship without Media Foundation; use the bundled engine there.
    has_mf = sys.platform == "win32" and (Path(os.environ.get("WINDIR", r"C:\Windows")) / "System32" / "mfplat.dll").is_file()
    os.environ.setdefault("QT_MEDIA_BACKEND", "windows" if has_mf else "ffmpeg")
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    from PySide6.QtCore import qInstallMessageHandler

    def log_qt(mode, context, message):
        # QtWarningMsg=1, QtCriticalMsg=2, QtFatalMsg=3 (QtInfoMsg=4 is chatter).
        if "--debug" in sys.argv or mode.value in (1, 2, 3):
            print(f"[qt] {message}", file=sys.stderr, flush=True)

    qInstallMessageHandler(log_qt)
    QCoreApplication.setAttribute(Qt.ApplicationAttribute.AA_ShareOpenGLContexts)
    # Chromium stops painting when it thinks the window is covered; keep the
    # embedded Apple sign-in drawing reliably.
    os.environ.setdefault(
        "QTWEBENGINE_CHROMIUM_FLAGS",
        "--disable-features=CalculateNativeWinOcclusion --disable-backgrounding-occluded-windows "
        "--disable-renderer-backgrounding --blink-settings=preferredColorScheme=0",
    )
    from PySide6.QtWebEngineQuick import QtWebEngineQuick

    QtWebEngineQuick.initialize()
    app = QApplication(sys.argv)
    from . import APP_NAME
    from .paths import data_dir, migrate_old_data

    migrate_old_data()
    _use_ini_preferences(APP_NAME, data_dir())
    app.setApplicationDisplayName(APP_NAME)
    # The multi-size icon, so the title bar, taskbar and Alt+Tab each get a crisp size.
    ico = Path(sys.executable).with_name("app.ico") if getattr(sys, "frozen", False) else Path(__file__).parent.parent / "app.ico"
    app.setWindowIcon(QIcon(str(ico)) if ico.is_file() else QIcon(str(QML_DIR / "icons" / "app.png")))
    backend = Backend()
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("Bridge", backend)
    engine.rootContext().setContextProperty("SigninStoragePath", signin_storage().as_posix())
    engine.addImportPath(str(QML_DIR))
    engine.load(QUrl.fromLocalFile(str(QML_DIR / "Main.qml")))
    if not engine.rootObjects():
        return 1
    app.aboutToQuit.connect(backend.shutdown)
    code = app.exec()
    # Tear the UI down before the backend it binds to, so no binding sees a
    # half-destroyed Bridge on the way out.
    del engine
    return code
