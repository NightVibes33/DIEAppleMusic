import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Sheet {
    id: ob
    wide: true
    title: "Other ways to sign in"
    subtitle: Theme.appName + " uses your own Apple Music account. An active subscription is needed to download and play full songs."

    property string mode: "cookies"
    property string busy: ""     // "", "apple", "connecting"
    property string error: ""
    property bool fresh: false

    readonly property var methods: [
        ["cookies", "key", "Cookies file", "Use a cookies.txt exported from music.apple.com."],
        ["media-user-token", "link", "Media User Token", "Paste the media-user-token from your browser."],
        ["wrapper", "server", "Wrapper", "Use a wrapper-v2 service on your network."]
    ]

    onAboutToShow: {
        error = ""; busy = ""
        var s = Store.callSync("get_settings").values
        cookies.text = s.auth.cookies_path || ""
        token.text = s.auth.media_user_token || ""
        wrapper.text = s.auth.wrapper_url || "http://127.0.0.1"
        folder.text = s.output.directory || Store.appState.default_music || ""
        var a = Store.appState.auth
        mode = a === "media-user-token" || a === "wrapper" ? a : "cookies"
    }

    Connections {
        target: Store
        function onAppleSigninFinished(ok, err) {
            if (ob.busy !== "apple") return
            if (!ok) { ob.busy = ""; ob.error = err; return }
            // Apple handed over a session: close now, verify in the background.
            ob.busy = ""
            Store.sessionOk = false
            Store.refreshState()
            ob.close()
            Store.toast("Signed in with your Apple ID. " + Theme.appName + " will remember it.", "ok", "check")
            Store.autoConnect()
        }
    }

    function finish() {
        busy = "connecting"
        Store.refreshState()
        Store.call("connect_apple_music", [], function (r) {
            busy = ""
            if (!r.ok) { error = Store.friendlyError(r.error); return }
            Store.refreshState()
            close()
            Store.toast("Signed in. Paste a link or search to get started.", "ok", "check")
        })
    }

    function submit() {
        error = ""
        if (!folder.text.trim()) { error = "Choose a folder for your music."; return }
        if (mode === "cookies" && !cookies.text.trim()) { error = "Choose your cookies.txt file."; return }
        if (mode === "media-user-token" && !token.text.trim()) { error = "Paste your Media User Token."; return }
        var values = { output: { directory: folder.text.trim() } }
        if (mode !== "apple") {
            values.auth = { mode: mode }
            if (mode === "cookies") values.auth.cookies_path = cookies.text.trim()
            if (mode === "media-user-token") values.auth.media_user_token = token.text.trim()
            if (mode === "wrapper") values.auth.wrapper_url = wrapper.text.trim()
        }
        busy = mode === "apple" ? "apple" : "connecting"
        Store.call("save_settings", [values], function (r) {
            if (!r.ok) { busy = ""; error = Store.friendlyError(r.error); return }
            finish()
        })
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 3
        columnSpacing: 10
        Repeater {
            model: ob.methods
            Rectangle {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 112
                radius: 10
                readonly property bool on: ob.mode === modelData[0]
                color: on ? "#2f3640" : mh.hovered ? "#383838" : "#333333"
                border.color: on ? Theme.select : "transparent"
                border.width: 2
                HoverHandler { id: mh }
                MouseArea { anchors.fill: parent; onClicked: { ob.mode = modelData[0]; ob.error = "" } }
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 6
                    Icon { name: modelData[1]; size: 22; color: Theme.brand }
                    Text { text: modelData[2]; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                    Text { Layout.fillWidth: true; Layout.fillHeight: true; text: modelData[3]; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; wrapMode: Text.Wrap }
                }
            }
        }
    }

    // Method details
    Rectangle {
        visible: ob.mode === "apple"
        Layout.fillWidth: true
        implicitHeight: appleText.implicitHeight + 28
        radius: 8
        color: Theme.panel
        border.color: Theme.hairline
        RowLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 14
            Icon { Layout.alignment: Qt.AlignTop; name: "key"; size: 20 }
            Text {
                id: appleText
                Layout.fillWidth: true
                text: "A window opens on music.apple.com. Sign in there with your Apple ID and approve the two-factor prompt. " + Theme.appName + " never sees your password. It keeps the session Apple gives the sign-in window and saves it for downloads and playback."
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; wrapMode: Text.Wrap; lineHeight: 1.15
            }
        }
    }
    Toggle { visible: ob.mode === "apple"; text: "Use a different Apple ID than last time"; checked: ob.fresh; onToggled: (c) => ob.fresh = c }

    ColumnLayout {
        visible: ob.mode === "cookies"
        Layout.fillWidth: true
        spacing: 6
        Text { text: "Cookies file"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
        RowLayout {
            Layout.fillWidth: true
            Field { id: cookies; Layout.fillWidth: true; placeholderText: "C:\\Users\\you\\Downloads\\cookies.txt" }
            AppButton { text: "Browse…"; kind: "quiet"; onClicked: Store.pick("file", cookies.text, function (p) { cookies.text = p }) }
        }
    }
    ColumnLayout {
        visible: ob.mode === "media-user-token"
        Layout.fillWidth: true
        spacing: 6
        Text { text: "Media User Token"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
        Field { id: token; Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: "Paste your token" }
    }
    ColumnLayout {
        visible: ob.mode === "wrapper"
        Layout.fillWidth: true
        spacing: 6
        Text { text: "Wrapper URL"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
        Field { id: wrapper; Layout.fillWidth: true }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6
        Text { text: "Music folder"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
        RowLayout {
            Layout.fillWidth: true
            Field { id: folder; Layout.fillWidth: true; placeholderText: "Where downloads are saved" }
            AppButton { text: "Browse…"; kind: "quiet"; onClicked: Store.pick("folder", folder.text, function (p) { folder.text = p }) }
        }
    }

    Rectangle {
        visible: ob.error !== ""
        Layout.fillWidth: true
        implicitHeight: errText.implicitHeight + 20
        radius: 8
        color: Qt.rgba(1, 0.35, 0.37, 0.12)
        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10
            Icon { Layout.alignment: Qt.AlignTop; name: "alert"; size: 18; color: Theme.bad }
            Text { id: errText; Layout.fillWidth: true; text: ob.error; color: "#ffb3b5"; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: 13 }
        }
    }

    footer: [
        AppButton { text: "Back"; kind: "quiet"; onClicked: { ob.close(); Store.onboardingRequested() } },
        Item { Layout.fillWidth: true },
        AppButton {
            kind: "primary"
            busy: ob.busy !== ""
            text: ob.busy === "apple" ? "Waiting for Apple…" : ob.busy === "connecting" ? "Connecting…" : ob.mode === "apple" ? "Sign In with Apple ID" : "Sign In"
            onClicked: ob.submit()
        }
    ]
}
