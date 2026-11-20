import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

PageScroll {
    id: page
    spacing: 16
    readonly property var kinds: [["songs", "Songs"], ["artists", "Artists"], ["albums", "Albums"], ["playlists", "Playlists"], ["music-videos", "Music Videos"]]
    readonly property bool songs: Store.searchKind === "songs"

    actions: Component {
        ComboBox {
            id: apiBox
            model: [{ v: "apple-music", t: "Apple Music" }, { v: "itunes", t: "iTunes" }]
            textRole: "t"
            valueRole: "v"
            implicitWidth: 140
            implicitHeight: 30
            currentIndex: Store.searchApi === "itunes" ? 1 : 0
            onActivated: { Store.searchApi = currentValue; Store.runSearch() }
            font.family: Theme.font
            background: Rectangle { radius: 6; color: Theme.fill }
            contentItem: Text { leftPadding: 10; text: apiBox.displayText; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; verticalAlignment: Text.AlignVCenter }
        }
    }

    function entry(i) {
        var r = Store.results.get(i)
        var meta = Store.resultMeta(i)
        return { title: r.name, artist: r.artist, album: r.album, artwork: r.artwork, explicit: r.explicit, duration: r.duration,
                 meta: meta, link: (meta.attributes || {}).url || "", downloadType: "songs" }
    }
    function summary(i) {
        var r = Store.results.get(i)
        var meta = Store.resultMeta(i)
        return { name: r.name, artist: r.artist, artwork: r.artwork, meta: meta, link: (meta.attributes || {}).url || "" }
    }
    function playSongs(i) {
        var list = []
        for (var k = 0; k < Store.results.count; k++) list.push(entry(k))
        Store.playList(list, i)
    }
    function playCollection(i) {
        if (Store.searchKind === "music-videos") { Store.toast("Music videos can't play in the app yet. Download them instead.", "", "video"); return }
        Store.status = "Loading tracks…"
        Store.call("collection_tracks", [Store.searchKind === "albums" ? "albums" : "playlists", Store.resultMeta(i)], function (r) {
            Store.status = ""
            if (!r.ok) { Store.toast(Store.friendlyError(r.error), "bad", "alert"); return }
            Store.playList(r.tracks.map(function (t) {
                return { title: t.name, artist: t.artist, album: t.album, artwork: t.artwork, explicit: t.explicit, meta: t.meta }
            }), 0)
        })
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: page.kinds
            Chip {
                required property var modelData
                text: modelData[1]
                on: Store.searchKind === modelData[0]
                onClicked: { Store.searchKind = modelData[0]; Store.runSearch() }
            }
        }
    }

    EmptyState {
        visible: !Store.searchTerm
        Layout.fillWidth: true
        icon: "search"
        title: "Search Apple Music"
        text: "Find songs, albums, playlists and music videos. Play them right here or download them."
    }
    Rectangle {
        visible: Store.searchError !== ""
        Layout.fillWidth: true
        implicitHeight: errText.implicitHeight + 20
        radius: 8
        color: Qt.rgba(1, 0.35, 0.37, 0.12)
        Text { id: errText; anchors.fill: parent; anchors.margins: 10; text: Store.searchError; color: "#ffb3b5"; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: 13 }
    }
    EmptyState {
        visible: Store.searchTerm !== "" && !Store.searchLoading && Store.results.count === 0 && Store.searchError === ""
        Layout.fillWidth: true
        icon: "search"
        title: "No results"
        text: "Nothing matched “" + Store.searchTerm + "”. Try another category or spelling."
    }

    // Songs
    ListHeader { visible: page.songs && Store.results.count > 0; Layout.fillWidth: true; c4: "Time"; trailingWidth: 80 }
    Repeater {
        model: page.songs ? Store.results : 0
        delegate: SongRow {
            required property var model
            required property int index
            Layout.fillWidth: true
            trailingWidth: 80
            striped: index % 2 === 0
            artwork: model.artwork
            title: model.name
            sub: ""
            artist: model.artist
            album: model.album
            explicit: model.explicit
            playing: Store.current !== null && !Store.current.path && Store.current.title === model.name && Store.current.artist === model.artist
            onPlay: page.playSongs(index)
            onActivated: page.playSongs(index)
            prefetch: page.entry(index)
            onContextRequested: Store.showMenu({ entries: [page.entry(index)] })
            Text { anchors.verticalCenter: parent.verticalCenter; text: Store.fmtDur(model.duration); color: Theme.text2; font.family: Theme.font; font.pixelSize: 14 }
            actions: [IconButton { icon: "download"; iconSize: 17; width: 30; height: 30; tip: "Download"; onClicked: Store.downloadResult(index) }]
        }
    }

    // Albums, playlists, videos
    CardGrid {
        id: grid
        visible: !page.songs && Store.results.count > 0
        Layout.fillWidth: true
        Repeater {
            model: page.songs ? 0 : Store.results
            delegate: AlbumCard {
                required property var model
                required property int index
                Layout.fillWidth: true
                Layout.preferredWidth: grid.cardWidth
                Layout.maximumWidth: grid.cardWidth
                Layout.alignment: Qt.AlignTop
                artwork: model.artwork
                title: model.name
                subtitle: model.artist
                glyph: Store.searchKind === "music-videos" ? "video" : Store.searchKind === "artists" ? "mic" : "album"
                round: Store.searchKind === "artists"
                primaryIcon: Store.searchKind === "music-videos" || Store.searchKind === "artists" ? "" : "play-f"
                secondaryIcon: Store.searchKind === "artists" ? "" : "download"
                onPrimary: page.playCollection(index)
                onSecondary: Store.downloadResult(index)
                onClicked: {
                    if (Store.searchKind === "music-videos") Store.downloadResult(index)
                    else Store.openSummary(Store.searchKind, page.summary(index), false)
                }
                onContextRequested: {
                    var s = page.summary(index)
                    if (Store.searchKind === "albums" || Store.searchKind === "playlists")
                        Store.showMenu({ collection: { kind: Store.searchKind === "albums" ? "album" : "playlist", title: s.name, subtitle: s.artist, artwork: s.artwork, meta: s.meta, link: s.link } })
                    else Store.showMenu({ link: s.link, entries: [] })
                }
            }
        }
    }

    Spinner { visible: Store.searchLoading && Store.results.count === 0; Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 40; size: 22 }
    AppButton {
        visible: Store.searchMore
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 14
        text: "Show More"
        busy: Store.searchLoading
        onClicked: Store.searchNext()
    }
}
