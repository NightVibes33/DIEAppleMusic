import QtQuick
import QtQuick.Layouts

Sheet {
    id: a
    RowLayout {
        spacing: 16
        Layout.topMargin: 12
        Image { source: Qt.resolvedUrl("icons/app.png"); sourceSize: Qt.size(168, 168); width: 56; height: 56; smooth: true }
        ColumnLayout {
            spacing: 2
            Text { text: Theme.appName; color: Theme.text; font.family: Theme.display; font.pixelSize: 20; font.weight: Font.DemiBold }
            Text { text: "Version " + (Store.appState.version || ""); color: Theme.text2; font.family: Theme.font; font.pixelSize: 14 }
        }
    }
    Text {
        Layout.fillWidth: true
        text: "Download and play Apple Music with your own subscription. Your settings are saved in " + (Store.appState.config_path || "") + "."
        color: Theme.text2; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: 14
    }

    // What the name means, and why the app is safe to run.
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: nameNotes.implicitHeight + 32
        radius: 8
        color: Theme.panel
        border.color: Theme.hairline
        ColumnLayout {
            id: nameNotes
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 8
            Text { text: "About the name"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.15
                text: Theme.appName + " (shine appuru) is Japanese for “Die, Apple.” It's a tongue-in-cheek jab at Apple, "
                    + "not a warning sign. The app isn't harmful to your computer."
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.15
                text: "It only downloads and plays music from your own Apple Music account. It connects to Apple's servers, "
                    + "and to LRCLIB to look up song lyrics by title and artist. It doesn't keep running after you close it, "
                    + "doesn't change system settings, and never stores your Apple ID password."
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.text3; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.15
                text: "Windows may show a SmartScreen warning the first time you open it, because the app isn't signed by a registered "
                    + "publisher. Choose More info, then Run anyway."
            }
        }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
        textFormat: Text.StyledText
        linkColor: Theme.select
        text: "Free and open source under the GNU GPL v3. Source code and license: "
            + "<a href=\"https://github.com/NightVibes33/DIEAppleMusic\">github.com/NightVibes33/DIEAppleMusic</a>"
        onLinkActivated: (url) => Store.call("open_url", [url])
        HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
    }
    Toggle { text: "Show technical details in Activity"; checked: Store.prefs.debugLog; onToggled: (c) => Store.prefs.debugLog = c }
    footer: [
        AppButton { text: "Open Settings Folder"; kind: "quiet"; onClicked: Store.call("reveal", [Store.appState.config_path]) },
        Item { Layout.fillWidth: true },
        AppButton { text: "Done"; kind: "primary"; onClicked: a.close() }
    ]
}
