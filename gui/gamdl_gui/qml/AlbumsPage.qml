import QtQuick
import QtQuick.Layouts

PageScroll {
    id: page
    property bool sortByName: false
    readonly property var groups: sortByName ? Store.albums.slice().sort(function (a, b) { return a.album.localeCompare(b.album) }) : Store.recentAlbums
    actions: Component {
        Row { spacing: 8
        AppButton { text: Store.scanning ? "Scanning…" : "Refresh"; icon: "sync"; enabled: !Store.scanning; onClicked: Store.scanLibrary() }
        AppButton { text: "Open Music Folder"; icon: "folder"; onClicked: Store.call("open_output", [], function (ok) { if (!ok) Store.toast("Choose a music folder in Settings first.", "bad", "alert") }) }
        }
    }

    EmptyState {
        visible: page.groups.length === 0
        Layout.fillWidth: true
        icon: "album"
        title: "No downloads yet"
        text: "Everything you download with " + Theme.appName + " shows up here, grouped by album."
        action: "Download Something"
        onActionClicked: Store.go("home")
    }
    CardGrid {
        id: grid
        Layout.fillWidth: true
        Repeater {
            model: page.groups
            delegate: AlbumCard {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: grid.cardWidth
                Layout.maximumWidth: grid.cardWidth
                Layout.alignment: Qt.AlignTop
                artwork: modelData.artwork
                title: modelData.album
                subtitle: modelData.artist
                onPrimary: Store.playList(modelData.tracks.slice().reverse(), 0)
                onSecondary: Store.call("reveal", [modelData.tracks[0].path])
                onClicked: Store.openLocalAlbum(modelData)
                onContextRequested: Store.showMenu({ entries: modelData.tracks.slice().reverse() })
            }
        }
    }
}
