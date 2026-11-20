import QtQuick
import QtQuick.Layouts

PageScroll {
    id: page
    spacing: 0
    property string filter: ""
    readonly property var songs: {
        var n = Store.history.count  // re-evaluate when history changes
        var q = filter.trim().toLowerCase()
        return Store.historyEntries()
            .filter(function (s) { return !q || (s.title + " " + s.artist + " " + s.album).toLowerCase().indexOf(q) >= 0 })
            .sort(function (a, b) { return a.title.localeCompare(b.title) })
    }
    actions: Component {
        Row {
            spacing: 8
            Field {
                width: 220
                placeholderText: "Filter songs"
                text: page.filter
                onTextChanged: page.filter = text
            }
            AppButton { text: "Play All"; icon: "play-f"; kind: "primary"; visible: page.songs.length > 0; onClicked: Store.playList(page.songs, 0) }
        }
    }

    EmptyState {
        visible: page.songs.length === 0
        Layout.fillWidth: true
        icon: "note"
        title: page.filter ? "No matches" : "No songs yet"
        text: page.filter ? "No songs match \u201c" + page.filter + "\u201d." : "Songs you download, and music already in your music folder, appear here. Double-click one to play it."
        action: "Download Something"
        onActionClicked: Store.go("home")
    }
    ListHeader { visible: page.songs.length > 0; Layout.fillWidth: true; c1: "Title"; c4: "Downloaded"; trailingWidth: 110 }
    Repeater {
        model: page.songs
        delegate: SongRow {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            trailingWidth: 110
            striped: index % 2 === 0
            artwork: modelData.artwork
            title: modelData.title
            sub: modelData.kind
            artist: modelData.artist
            album: modelData.album
            explicit: modelData.explicit
            playing: Store.isCurrent(modelData)
            onPlay: Store.playList(page.songs, index)
            onActivated: Store.playList(page.songs, index)
            onContextRequested: Store.showMenu({ entries: [modelData] })
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.time ? new Date(modelData.time).toLocaleDateString(Qt.locale(), Locale.ShortFormat) : ""
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 14
            }
            actions: [IconButton { icon: "folder"; iconSize: 17; width: 30; height: 30; tip: "Show in folder"; onClicked: Store.call("reveal", [modelData.path]) }]
        }
    }
}
