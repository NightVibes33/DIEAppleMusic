import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

PageScroll {
    id: page
    property string tool: "organize"
    spacing: 16
    readonly property var tools: ({
        organize: { title: "Organize Files", icon: "organize",
            text: "Move files so their folders and names match your naming settings. " + Theme.appName + " never overwrites an existing file. Preview first to see what will move.",
            actions: [["Preview", ["organize", "--dry-run"], ""], ["Repair Playlists Only", ["organize", "--playlists-only"], "Rewrite paths inside your .m3u8 playlists?"], ["Organize", ["organize"], "Move files in your library to match your naming settings?"]] },
        database: { title: "Media Database", icon: "db",
            text: Theme.appName + " keeps an index of downloaded files so it can skip duplicates. Pruning removes index entries for missing files and never deletes music.",
            actions: [["Show Info", ["database", "info"], ""], ["Preview Scan", ["database", "scan", "--dry-run"], ""], ["Scan Library", ["database", "scan"], ""], ["Preview Prune", ["database", "prune", "--dry-run"], ""], ["Prune Missing", ["database", "prune", "--yes"], "Remove database entries for files that no longer exist?"]] },
        sync: { title: "Sync Playlists", icon: "sync",
            text: "Update your saved .m3u8 playlists to match Apple Music: add new songs, remove dropped ones, and download anything missing. Local music is never deleted.",
            actions: [["Preview", ["sync", "playlists", "--dry-run", "--verbose"], ""], ["Sync Without Downloading", ["sync", "playlists", "--no-download"], "Update playlist files without downloading new songs?"], ["Sync and Download", ["sync", "playlists"], "Update playlists and download missing songs?"]] }
    })
    readonly property var t: tools[tool] || tools.organize

    function run(a) {
        var go = function () {
            Store.call("run_tool", [a[1], Store.prefs.toolDir], function (r) {
                if (!r.ok) Store.toast(r.error, "bad", "alert")
                else Store.toolRunning = true
            })
        }
        if (a[2]) Store.dialogs.confirm(a[0], a[2], a[0], go)
        else go()
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: card.implicitHeight + 36
        radius: 8
        color: Theme.panel
        border.color: Theme.hairline
        ColumnLayout {
            id: card
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12
            RowLayout {
                spacing: 10
                Rectangle { width: 30; height: 30; radius: 8; color: Theme.fill; Icon { anchors.centerIn: parent; name: page.t.icon; size: 18 } }
                Text { text: page.t.title; color: Theme.text; font.family: Theme.display; font.pixelSize: 16; font.weight: Font.DemiBold }
            }
            Text { Layout.fillWidth: true; text: page.t.text; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; wrapMode: Text.Wrap }
            Text { text: "Library folder"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; Layout.topMargin: 4 }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Field {
                    Layout.fillWidth: true
                    text: Store.prefs.toolDir
                    placeholderText: "Your music folder from Settings"
                    onTextEdited: Store.prefs.toolDir = text
                }
                AppButton { text: "Browse…"; onClicked: Store.pick("folder", Store.prefs.toolDir, function (p) { Store.prefs.toolDir = p }) }
            }
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 8
                Repeater {
                    model: page.t.actions
                    AppButton {
                        required property var modelData
                        required property int index
                        text: modelData[0]
                        kind: index === page.t.actions.length - 1 ? "primary" : "default"
                        enabled: !Store.toolRunning
                        onClicked: page.run(modelData)
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 8
        Text { text: "Output"; color: Theme.text; font.family: Theme.display; font.pixelSize: 20; font.weight: Font.Bold; Layout.fillWidth: true }
        AppButton { visible: Store.toolRunning; text: "Stop"; icon: "stop-f"; kind: "danger"; onClicked: Store.call("stop_tool") }
        AppButton { text: "Clear"; onClicked: Store.toolOut = "" }
    }
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 320
        radius: 8
        color: "#141414"
        border.color: Theme.hairline
        ScrollView {
            anchors.fill: parent
            anchors.margins: 1
            TextArea {
                readOnly: true
                text: Store.toolOut || ""
                placeholderText: "Results from the commands above appear here."
                placeholderTextColor: Theme.text3
                color: "#d6d6d6"
                font.family: Theme.mono
                font.pixelSize: 13
                wrapMode: TextArea.Wrap
                padding: 14
                selectByMouse: true
                background: null
                onTextChanged: cursorPosition = length
            }
        }
    }
}
