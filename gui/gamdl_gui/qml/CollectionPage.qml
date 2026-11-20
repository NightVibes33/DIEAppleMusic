import QtQuick
import QtQuick.Layouts

// Album, playlist, artist or downloaded-album page, laid out like Apple Music:
// big artwork, title, artist in red, Play / Shuffle / Download, then the tracks.
PageScroll {
    id: page
    spacing: 0
    readonly property var c: Store.collection
    readonly property bool isArtist: c && c.kind === "artist"
    readonly property bool isLocal: c && c.kind === "local"
    readonly property var tracks: c ? c.tracks : []
    readonly property int totalMs: tracks.reduce(function (m, t) { return m + (t.duration || 0) }, 0)

    actions: Component {
        Row {
            spacing: 8
            AppButton { visible: page.c && page.c.link !== ""; text: "Copy Link"; icon: "link"; onClicked: Store.copyLinks([{ link: page.c.link }]) }
        }
    }

    function play(shuffle) {
        if (!tracks.length) return
        Store.shuffle = !!shuffle
        Store.playList(tracks, shuffle ? Math.floor(Math.random() * tracks.length) : 0)
    }
    function download() {
        if (isArtist) { Store.downloadEntries(tracks, c.title + " — Top Songs", { art: c.artwork, sub: c.title, auto: false }); return }
        Store.startJob([{ type: c.kind === "album" ? "albums" : "playlists", meta: c.meta, library: c.library, label: c.title }],
                       c.title, { art: c.artwork, sub: c.subtitle, auto: false })
    }
    function rowMenu(i) {
        Store.showMenu({ entries: [tracks[i]] })
    }

    // ---- header ----
    RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: 26
        spacing: 28
        Art {
            Layout.preferredWidth: page.width > 900 ? 230 : 180
            Layout.preferredHeight: Layout.preferredWidth
            Layout.alignment: Qt.AlignTop
            radius: page.isArtist ? width / 2 : 8
            source: page.c ? (page.c.artwork || "").replace(/\/\d+x\d+bb\./, "/600x600bb.") : ""
            glyph: page.isArtist ? "mic" : page.c && page.c.kind === "playlist" ? "playlist" : "album"
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignBottom
            spacing: 4
            Text {
                text: ({ album: "ALBUM", playlist: "PLAYLIST", artist: "ARTIST", local: "DOWNLOADED" })[page.c ? page.c.kind : ""] || ""
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.8
            }
            Text {
                Layout.fillWidth: true
                text: page.c ? page.c.title : ""
                color: Theme.text; font.family: Theme.display; font.pixelSize: 30; font.weight: Font.Bold
                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
            }
            Text {
                visible: page.c && page.c.subtitle !== ""
                text: page.c ? page.c.subtitle : ""
                color: Theme.brand; font.family: Theme.display; font.pixelSize: 20; font.weight: Font.DemiBold
            }
            Text {
                visible: page.tracks.length > 0
                text: page.tracks.length + (page.isArtist ? " top songs" : page.tracks.length === 1 ? " song" : " songs")
                      + (page.totalMs ? " · " + Math.round(page.totalMs / 60000) + " min" : "")
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
            }
            RowLayout {
                Layout.topMargin: 14
                spacing: 10
                AppButton { text: "Play"; icon: "play-f"; kind: "primary"; enabled: page.tracks.length > 0; onClicked: page.play(false) }
                AppButton { text: "Shuffle"; icon: "shuffle"; enabled: page.tracks.length > 1; onClicked: page.play(true) }
                AppButton { visible: !page.isLocal; text: page.isArtist ? "Download Top Songs" : "Download"; icon: "download"; enabled: page.isArtist ? page.tracks.length > 0 : true; onClicked: page.download() }
                AppButton { visible: page.isLocal && page.tracks.length > 0; text: "Show in Folder"; icon: "folder"; onClicked: Store.call("reveal", [page.tracks[0].path]) }
            }
        }
    }

    // ---- states ----
    Spinner { visible: page.c && page.c.loading; Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 30; size: 24 }
    Text {
        visible: page.c && page.c.error !== ""
        Layout.fillWidth: true
        text: page.c ? page.c.error : ""
        color: Theme.bad; font.family: Theme.font; font.pixelSize: 14; wrapMode: Text.Wrap
    }

    // ---- tracks ----
    Text {
        visible: page.isArtist && page.tracks.length > 0
        text: "Top Songs"; color: Theme.text; font.family: Theme.display; font.pixelSize: 20; font.weight: Font.Bold
        Layout.bottomMargin: 8
    }
    ListHeader { visible: page.tracks.length > 0; Layout.fillWidth: true; c4: "Time"; trailingWidth: 80 }
    Repeater {
        model: page.isArtist ? page.tracks.slice(0, 15) : page.tracks
        delegate: SongRow {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            trailingWidth: 80
            striped: index % 2 === 0
            artwork: modelData.artwork
            title: modelData.title
            sub: ""
            artist: modelData.artist
            album: modelData.album
            explicit: !!modelData.explicit
            playing: Store.isCurrent(modelData)
            onPlay: Store.playList(page.tracks, index)
            onActivated: Store.playList(page.tracks, index)
            prefetch: modelData
            onContextRequested: page.rowMenu(index)
            Text { anchors.verticalCenter: parent.verticalCenter; text: Store.fmtDur(modelData.duration); color: Theme.text2; font.family: Theme.font; font.pixelSize: 14 }
            actions: [
                IconButton { visible: !modelData.path; icon: "download"; iconSize: 17; width: 30; height: 30; tip: "Download"; onClicked: Store.downloadEntries([modelData]) },
                IconButton { icon: "more"; iconSize: 17; width: 30; height: 30; tip: "More"; onClicked: page.rowMenu(index) }
            ]
        }
    }

    // ---- artist: albums and singles ----
    Repeater {
        model: page.isArtist ? [["Albums", page.c.albums], ["Singles & EPs", page.c.singles]] : []
        delegate: ColumnLayout {
            required property var modelData
            visible: modelData[1].length > 0
            Layout.fillWidth: true
            Layout.topMargin: 30
            spacing: 14
            Text { text: modelData[0]; color: Theme.text; font.family: Theme.display; font.pixelSize: 20; font.weight: Font.Bold }
            CardGrid {
                id: agrid
                Layout.fillWidth: true
                Repeater {
                    model: modelData[1]
                    delegate: AlbumCard {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: agrid.cardWidth
                        Layout.maximumWidth: agrid.cardWidth
                        Layout.alignment: Qt.AlignTop
                        artwork: modelData.artwork
                        title: modelData.name
                        subtitle: modelData.details
                        primaryIcon: "play-f"
                        secondaryIcon: "download"
                        onClicked: Store.openSummary("albums", modelData, false)
                        onPrimary: Store.openSummary("albums", modelData, false)
                        onSecondary: Store.startJob([{ type: "albums", meta: modelData.meta, label: modelData.name }], modelData.name, { art: modelData.artwork, sub: modelData.artist, auto: false })
                        onContextRequested: Store.showMenu({ collection: { kind: "album", title: modelData.name, subtitle: modelData.artist, artwork: modelData.artwork, meta: modelData.meta, link: modelData.link } })
                    }
                }
            }
        }
    }
}
