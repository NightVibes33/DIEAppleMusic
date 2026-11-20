import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import QtWebEngine

// Apple ID sign-in. Apple's own sign-in panel (email, password, two-factor
// code, "Trust this browser?") is shown inside the app's card, without the
// rest of Apple's website. Passkeys are turned off so Windows never shows its
// security prompt. When Apple signs the person in, the app keeps the session
// cookie Apple sets.
Item {
    id: si
    property bool open: false
    property string phase: "loading"   // loading | panel | finishing | offline | folder
    property bool fresh: false
    readonly property alias webView: web
    signal otherOptionsRequested()

    visible: opacity > 0.01
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    // Start loading Apple's panel early, so it's ready when someone signs in.
    function preload() {
        if (web.url.toString() === "") load()
    }
    function load() {
        phase = "loading"
        readyTimer.tries = 0
        web.url = Bridge.signinUrl
        readyTimer.start()
    }
    function show() {
        open = true
        Bridge.signinStart(fresh)
        if (fresh || web.url.toString() === "" || phase === "offline" || phase === "finishing") load()
        fresh = false
        web.forceActiveFocus()
    }
    function hide() { Bridge.signinStop(); open = false }
    function complete() {
        hide()
        Store.toast("Signed in with your Apple ID. " + Theme.appName + " will remember it.", "ok", "check")
        Store.autoConnect()
        web.url = ""
    }

    // The sign-in browser profile. It persists, so Apple remembers this computer
    // ("Trust this browser") between launches; Python watches its cookies.
    WebEngineProfilePrototype {
        id: profileProto
        storageName: "signin"
        // SigninStoragePath is a plain text value set by app.py before loading,
        // so it stays valid even while the app is shutting down.
        persistentStoragePath: SigninStoragePath
        cachePath: SigninStoragePath + "/cache"
        persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
    }
    // instance() is only ready once this screen has finished loading.
    property var signinProfile: null

    Component.onCompleted: {
        signinProfile = profileProto.instance()
        web.profile = signinProfile
        Bridge.attachSigninProfile(signinProfile)
        if (!Store.configured) preload()
    }

    Connections {
        target: Store
        function onSignedOut() { si.load() }
        function onSigninNeedsToken() {
            if (!si.open || si.phase === "folder") return
            si.phase = "finishing"
            web.url = Bridge.signinFinishUrl
        }
        function onAppleSigninFinished(ok, err) {
            if (!si.open || si.phase === "folder") return
            if (!ok) { Store.toast(Store.friendlyError(err), "bad", "alert"); si.load(); return }
            Store.sessionOk = false
            Store.refreshState()
            if (!Store.appState.directory) { folderField.text = Store.appState.default_music || ""; si.phase = "folder" }
            else si.complete()
        }
    }

    // Shows the panel once Apple's email field (or sign-in frame) is on screen.
    Timer {
        id: readyTimer
        property int tries: 0
        interval: 120
        repeat: true
        onTriggered: {
            tries++
            if (si.phase !== "loading" || tries > 120) { if (si.phase === "loading") si.phase = "panel"; stop(); return }
            web.runJavaScript("!!(document.getElementById('accountName') || document.querySelector('iframe[src*=\"idmsa\"]'))", function (ok) {
                if (ok && si.phase === "loading") { si.phase = "panel"; readyTimer.stop() }
            })
        }
    }

    // ---- backdrop: the app's own look ----
    Rectangle { anchors.fill: parent; color: Theme.page }
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        height: parent.height * 0.55
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#2a1f24" }
            GradientStop { position: 1.0; color: Theme.page }
        }
    }
    WindowDragArea {}

    Row {
        anchors.right: parent.right
        anchors.top: parent.top
        Repeater {
            model: [["min", 0], [Window.window && Window.window.visibility === Window.Maximized ? "restore" : "max", 1], ["close", 2]]
            Rectangle {
                required property var modelData
                width: 46; height: 32
                color: wm.containsMouse ? (modelData[1] === 2 ? "#c42b1c" : Qt.rgba(1, 1, 1, 0.08)) : "transparent"
                Icon { anchors.centerIn: parent; name: modelData[0]; size: 10 }
                MouseArea {
                    id: wm
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        var w = Window.window
                        if (modelData[1] === 0) w.showMinimized()
                        else if (modelData[1] === 1) { if (w.visibility === Window.Maximized) w.showNormal(); else w.showMaximized() }
                        else Store.dialogs.requestClose()
                    }
                }
            }
        }
    }

    // ---- the card ----
    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(480, parent.width - 48)
        spacing: 16

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(560, si.height - 140)

            RectangularShadow { anchors.fill: card; radius: 14; blur: 48; offset.y: 18; color: Qt.rgba(0, 0, 0, 0.5) }
            Rectangle { id: card; anchors.fill: parent; radius: 14; color: "#1e1e20"; border.color: Qt.rgba(1, 1, 1, 0.08) }

            // Apple's sign-in panel
            WebEngineView {
                id: web
                anchors.fill: parent
                anchors.margins: 6
                backgroundColor: "transparent"
                visible: si.phase === "panel"
                settings.showScrollBars: false
                settings.focusOnNavigationEnabled: true
                Component.onCompleted: {
                    var s = WebEngine.script()
                    s.name = "signin"
                    s.sourceCode = Bridge.signinScript
                    s.injectionPoint = WebEngineScript.DocumentCreation
                    s.worldId = WebEngineScript.MainWorld
                    s.runsOnSubFrames = true
                    userScripts.insert(s)
                }
                onLoadingChanged: (info) => {
                    if (info.status === 3 && si.phase !== "folder") si.phase = "offline"   // load failed
                }
                // "Create Apple Account" and "Forgot password?" open in the browser.
                onNewWindowRequested: (request) => Store.call("open_url", [request.requestedUrl.toString()])
                onContextMenuRequested: (request) => request.accepted = true
            }

            // Loading and finishing
            ColumnLayout {
                anchors.centerIn: parent
                visible: si.phase === "loading" || si.phase === "finishing"
                spacing: 14
                Image {
                    Layout.alignment: Qt.AlignHCenter
                    source: Qt.resolvedUrl("icons/app.png")
                    sourceSize: Qt.size(168, 168)
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: 56
                }
                Spinner { Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 6; size: 22 }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: si.phase === "finishing" ? "Finishing sign-in…" : "Connecting to Apple…"
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
                }
            }

            // Couldn't reach Apple
            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - 64
                visible: si.phase === "offline"
                spacing: 12
                Icon { Layout.alignment: Qt.AlignHCenter; name: "alert"; size: 28; color: Theme.text2 }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: "Couldn't reach Apple"
                    color: Theme.text; font.family: Theme.display; font.pixelSize: 20; font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: "Check your internet connection, then try again."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 14; wrapMode: Text.Wrap
                }
                AppButton { Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 6; text: "Try Again"; kind: "primary"; onClicked: si.load() }
            }

            // Music folder, after signing in
            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 32
                visible: si.phase === "folder"
                spacing: 14
                Image {
                    Layout.alignment: Qt.AlignHCenter
                    source: Qt.resolvedUrl("icons/app.png")
                    sourceSize: Qt.size(168, 168)
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: 56
                }
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    horizontalAlignment: Text.AlignHCenter
                    text: "You're signed in"
                    color: Theme.text; font.family: Theme.display; font.pixelSize: 24; font.weight: Font.Bold
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: "Where should " + Theme.appName + " save the music you download?"
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 14; wrapMode: Text.Wrap
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 10
                    spacing: 8
                    Field { id: folderField; Layout.fillWidth: true; implicitHeight: 40; placeholderText: "Choose a folder" }
                    AppButton { text: "Browse…"; kind: "quiet"; onClicked: Store.pick("folder", folderField.text, function (p) { folderField.text = p }) }
                }
                AppButton {
                    Layout.fillWidth: true
                    large: true
                    kind: "primary"
                    text: "Start Listening"
                    onClicked: {
                        if (!folderField.text.trim()) { Store.toast("Choose a folder for your music.", "bad", "alert"); return }
                        Store.call("save_settings", [{ output: { directory: folderField.text.trim() } }], function (r) {
                            if (!r.ok) { Store.toast(Store.friendlyError(r.error), "bad", "alert"); return }
                            Store.refreshState()
                            si.complete()
                        })
                    }
                }
            }
        }

        // ---- footer ----
        RowLayout {
            visible: si.phase !== "folder"
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Layout.rightMargin: 6
            spacing: 8
            Icon { name: "key"; size: 14; color: Theme.text3 }
            Text {
                Layout.fillWidth: true
                text: "This is Apple's own sign-in. Your password goes straight to Apple; " + Theme.appName + " only keeps the session Apple returns."
                color: Theme.text3; font.family: Theme.font; font.pixelSize: 12; wrapMode: Text.Wrap
            }
        }
        RowLayout {
            visible: si.phase !== "folder"
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Layout.rightMargin: 6
            Text {
                text: "Other ways to sign in"
                color: om.containsMouse ? Theme.text : Theme.text2
                font.family: Theme.font; font.pixelSize: 13
                MouseArea { id: om; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: { si.hide(); si.otherOptionsRequested() } }
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "Use a different Apple ID"
                visible: si.phase === "panel"
                color: um.containsMouse ? Theme.text : Theme.text2
                font.family: Theme.font; font.pixelSize: 13
                MouseArea { id: um; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: { Bridge.signinStart(true); si.load() } }
            }
            Text {
                Layout.leftMargin: 16
                text: "Not Now"
                color: nm.containsMouse ? Theme.text : Theme.text2
                font.family: Theme.font; font.pixelSize: 13
                MouseArea { id: nm; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: si.hide() }
            }
        }
    }
}
