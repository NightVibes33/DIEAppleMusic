import QtQuick

// A download in the queue: live stage and progress, then the result.
SongRow {
    id: q
    property var it
    property int jobId
    artwork: it.artwork
    title: it.title
    sub: it.status && it.message ? it.message : it.kind
    subColor: it.status === "failed" ? Theme.bad : (it.status && it.message ? Theme.warn : Theme.text2)
    artist: it.artist
    album: it.album
    explicit: it.explicit
    glyph: it.kind === "Song" ? "note" : "video"
    playable: it.path !== ""
    playing: Store.current !== null && it.path !== "" && Store.current.path === it.path

    function playFromHere() {
        var m = Store.jobModel(q.jobId), entries = [], start = 0
        for (var i = 0; i < m.count; i++) {
            var r = m.get(i)
            if (!r.path) continue
            if (r.path === q.it.path) start = entries.length
            entries.push({ title: r.title, artist: r.artist, album: r.album, artwork: r.artwork, explicit: r.explicit, path: r.path })
        }
        Store.playList(entries, start)
    }
    onPlay: playFromHere()
    onContextRequested: {
        if (it.path) Store.showMenu({ entries: [{ title: it.title, artist: it.artist, album: it.album, artwork: it.artwork, explicit: it.explicit, path: it.path }] })
    }
    onActivated: if (it.path) playFromHere()

    Item {
        anchors.fill: parent
        Column {
            visible: !q.it.status
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            Item {
                width: parent.width
                height: 16
                Text {
                    text: q.it.stage + (q.it.pct >= 0 ? " " + Math.round(q.it.pct) + "%" : "")
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                    elide: Text.ElideRight; width: parent.width - speed.width - 6
                }
                Text { id: speed; anchors.right: parent.right; text: q.it.detail; color: Theme.text3; font.family: Theme.font; font.pixelSize: 12 }
            }
            Meter { width: parent.width; value: q.it.pct }
        }
        Pill { visible: q.it.status !== ""; status: q.it.status; tip: q.it.message; anchors.verticalCenter: parent.verticalCenter }
    }

    actions: [
        IconButton { visible: q.it.path !== ""; icon: "folder"; iconSize: 17; width: 30; height: 30; tip: "Show in folder"; onClicked: Store.call("reveal", [q.it.path]) },
        IconButton { visible: q.it.message !== "" && q.it.path === ""; icon: "paste"; iconSize: 17; width: 30; height: 30; tip: "Copy error"; onClicked: Store.copy(q.it.message) }
    ]
}
