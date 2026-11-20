import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

// Full-window Now Playing, modeled on Apple Music: breathing artwork colors,
// big art and transport on the left, synced lyrics or Up Next on the right.
Item {
    id: np
    property var player
    property string panel: "lyrics"   // lyrics | queue | ""
    readonly property bool open: Store.nowPlayingOpen
    readonly property var cur: Store.current
    readonly property string art: cur && cur.artwork ? cur.artwork.replace(/\/\d+x\d+bb\./, "/1000x1000bb.") : ""
    readonly property bool showPanel: panel !== "" && width > 980
    // The player reports its position only a few times a second; between
    // reports, advance it with the clock so the scrubber and lyrics glide.
    readonly property real rawPos: player ? player.position : 0
    property real pos: rawPos
    property real _anchorPos: 0
    property real _anchorTime: 0
    onRawPosChanged: { _anchorPos = rawPos; _anchorTime = Date.now(); if (!smoother.running) pos = rawPos }
    Connections {
        target: Store
        function onPlayingChanged() { np._anchorPos = np.rawPos; np._anchorTime = Date.now(); np.pos = np.rawPos }
    }
    FrameAnimation {
        id: smoother
        running: np.visible && Store.playing
        onTriggered: np.pos = Math.min(np.dur > 0 ? np.dur : Infinity, np._anchorPos + (Date.now() - np._anchorTime) * (np.player ? np.player.playbackRate : 1))
    }
    readonly property real dur: player ? player.duration : 0
    readonly property int lyricIndex: Store.lyricsSynced ? Store.lyricIndexAt(pos + 250) : -1

    // Opens with a long, soft ease out of the mini player; closes quickly.
    visible: opacity > 0.01
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: np.open ? 360 : 200; easing.type: np.open ? Easing.OutCubic : Easing.InCubic } }
    transform: [
        Translate { y: np.open ? 0 : -56; Behavior on y { NumberAnimation { duration: np.open ? 520 : 240; easing.type: np.open ? Easing.OutQuint : Easing.InCubic } } },
        Scale {
            origin.x: np.width / 2
            origin.y: 0
            xScale: np.open ? 1 : 0.9
            yScale: np.open ? 1 : 0.9
            Behavior on xScale { NumberAnimation { duration: np.open ? 520 : 240; easing.type: np.open ? Easing.OutQuint : Easing.InCubic } }
            Behavior on yScale { NumberAnimation { duration: np.open ? 520 : 240; easing.type: np.open ? Easing.OutQuint : Easing.InCubic } }
        }
    ]
    focus: open
    Keys.onEscapePressed: Store.nowPlayingOpen = false
    Keys.onSpacePressed: Store.toggle()
    Keys.onLeftPressed: if (player) player.position = Math.max(0, player.position - 5000)
    Keys.onRightPressed: if (player) player.position = Math.min(dur, player.position + 5000)

    function fmt(ms) { return Store.fmtDur(ms) }

    // ---- background: slow breathing colors sampled from the current artwork ----
    Rectangle { anchors.fill: parent; color: "#151515" }
    Item {
        anchors.fill: parent
        clip: true
        Image {
            id: bgSrc
            source: np.art
            sourceSize: Qt.size(256, 256)
            fillMode: Image.PreserveAspectCrop
            visible: false
            width: 256
            height: 256
        }
        MultiEffect {
            id: blobA
            source: bgSrc
            // Big enough that the blob's edges (offset included) stay outside
            // the window; an edge inside it shows as a hard line.
            width: Math.max(np.width, np.height) * 2.2
            height: width
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -np.width * 0.15
            blurEnabled: true
            blur: 1.0
            blurMax: 64
            saturation: 0.55
            brightness: -0.08
            visible: bgSrc.status === Image.Ready
            opacity: 0.9
            RotationAnimation on rotation { from: 0; to: 360; duration: 120000; loops: Animation.Infinite; running: np.visible && bgSrc.status === Image.Ready }
            SequentialAnimation on opacity {
                running: np.visible && bgSrc.status === Image.Ready
                loops: Animation.Infinite
                NumberAnimation { to: 0.62; duration: 9000; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.9; duration: 9000; easing.type: Easing.InOutSine }
            }
        }
        MultiEffect {
            id: blobB
            source: bgSrc
            width: Math.max(np.width, np.height) * 2.2
            height: width
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: np.width * 0.25
            anchors.verticalCenterOffset: np.height * 0.2
            blurEnabled: true
            blur: 1.0
            blurMax: 64
            saturation: 0.7
            opacity: 0.55
            visible: bgSrc.status === Image.Ready
            RotationAnimation on rotation { from: 360; to: 0; duration: 90000; loops: Animation.Infinite; running: np.visible && bgSrc.status === Image.Ready }
            SequentialAnimation on opacity {
                running: np.visible && bgSrc.status === Image.Ready
                loops: Animation.Infinite
                PauseAnimation { duration: 9000 }
                NumberAnimation { to: 0.3; duration: 9000; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.55; duration: 9000; easing.type: Easing.InOutSine }
            }
        }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.38) }
    }

    WindowDragArea {}

    // ---- top controls ----
    IconButton {
        x: 16; y: 12
        icon: "chev-down"; iconSize: 22; tip: "Close Now Playing"
        onClicked: Store.nowPlayingOpen = false
    }
    Row {
        anchors.right: parent.right
        anchors.top: parent.top
        Repeater {
            model: [["min", 0], [Window.window && Window.window.visibility === Window.Maximized ? "restore" : "max", 1], ["close", 2]]
            Rectangle {
                required property var modelData
                width: 46; height: 32
                color: wm.containsMouse ? (modelData[1] === 2 ? "#c42b1c" : Qt.rgba(1, 1, 1, 0.1)) : "transparent"
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

    // ---- left: artwork, details, transport ----
    Item {
        id: left
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: np.showPanel ? parent.width * 0.47 : parent.width
        readonly property real artSize: Math.max(220, Math.min(height * 0.5, width * 0.62, 520))

        ColumnLayout {
            anchors.centerIn: parent
            width: left.artSize
            spacing: 0

            Item {
                Layout.preferredWidth: left.artSize
                Layout.preferredHeight: left.artSize
                Item {
                    anchors.fill: parent
                    scale: Store.playing ? 1.0 : 0.88
                    Behavior on scale { NumberAnimation { duration: 600; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
                    RectangularShadow { anchors.fill: artImg; radius: 10; blur: 60; offset.y: 22; color: Qt.rgba(0, 0, 0, 0.55); spread: -10 }
                    Art { id: artImg; anchors.fill: parent; radius: 10; source: np.art; glyph: "note" }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 28
                spacing: 8
                Text {
                    Layout.maximumWidth: left.artSize - 24
                    text: np.cur ? np.cur.title : "Not Playing"
                    color: "#ffffff"
                    font.family: Theme.display
                    font.pixelSize: 21
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }
                Explicit { visible: np.cur && np.cur.explicit }
                Item { Layout.fillWidth: true }
                Text {
                    visible: Store.playSource === "preview"
                    text: "PREVIEW"
                    color: Qt.rgba(1, 1, 1, 0.75)
                    font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 0.8
                }
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 2
                text: np.cur ? [np.cur.artist, np.cur.album].filter(function (x) { return x }).join(" — ") : ""
                color: Qt.rgba(1, 1, 1, 0.62)
                font.family: Theme.font
                font.pixelSize: 17
                elide: Text.ElideRight
            }

            // Scrubber
            Item {
                id: scrub
                Layout.fillWidth: true
                Layout.topMargin: 22
                Layout.preferredHeight: 14
                property bool dragging: false
                property real dragFrac: 0
                readonly property real frac: dragging ? dragFrac : (np.dur > 0 ? np.pos / np.dur : 0)
                Rectangle {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: scrubMa.containsMouse || scrub.dragging ? 8 : 5
                    radius: height / 2
                    color: Qt.rgba(1, 1, 1, 0.22)
                    Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Rectangle { width: parent.width * scrub.frac; height: parent.height; radius: parent.radius; color: Qt.rgba(1, 1, 1, scrubMa.containsMouse || scrub.dragging ? 0.95 : 0.75) }
                }
                MouseArea {
                    id: scrubMa
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    function at(x) { return Math.max(0, Math.min(1, (x - 6) / scrub.width)) }
                    onPressed: (m) => { scrub.dragging = true; scrub.dragFrac = at(m.x) }
                    onPositionChanged: (m) => { if (scrub.dragging) scrub.dragFrac = at(m.x) }
                    onReleased: { if (np.player && np.dur > 0) np.player.position = scrub.dragFrac * np.dur; scrub.dragging = false }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                Text { text: np.fmt(scrub.dragging ? scrub.dragFrac * np.dur : np.pos); color: Qt.rgba(1, 1, 1, 0.55); font.family: Theme.font; font.pixelSize: 12 }
                Item { Layout.fillWidth: true }
                Text { text: "-" + np.fmt(np.dur - (scrub.dragging ? scrub.dragFrac * np.dur : np.pos)); color: Qt.rgba(1, 1, 1, 0.55); font.family: Theme.font; font.pixelSize: 12 }
            }

            // Transport
            Row {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 18
                spacing: 30
                IconButton { anchors.verticalCenter: parent.verticalCenter; icon: "shuffle"; iconSize: 20; active: Store.shuffle; onClicked: Store.shuffle = !Store.shuffle }
                IconButton { anchors.verticalCenter: parent.verticalCenter; icon: "prev"; iconSize: 34; width: 52; height: 52; onClicked: Store.prev() }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: Store.playing ? "pause-f" : "play-f"; iconSize: 46; width: 64; height: 64; radius: 32
                    onClicked: Store.toggle()
                    Spinner { anchors.centerIn: parent; size: 30; visible: Store.loading }
                }
                IconButton { anchors.verticalCenter: parent.verticalCenter; icon: "next"; iconSize: 34; width: 52; height: 52; onClicked: Store.next(false) }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "repeat"; iconSize: 20; active: Store.repeatMode > 0
                    onClicked: Store.repeatMode = (Store.repeatMode + 1) % 3
                    Text { visible: Store.repeatMode === 2; text: "1"; color: Theme.select; font.pixelSize: 9; font.weight: Font.Black; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 5 }
                }
            }

            // Volume
            VolumeSlider {
                Layout.fillWidth: true
                Layout.topMargin: 18
                sliderWidth: width - 2 * (iconSize + 8) - 2 * spacing - 4
                iconSize: 18
                showMaxIcon: true
                trackHeight: 5
            }

            // Panel toggles
            Row {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 22
                spacing: 18
                Repeater {
                    model: [["lyrics", "lyrics", "Lyrics"], ["queue", "queue", "Up Next"]]
                    Rectangle {
                        required property var modelData
                        width: 40; height: 40; radius: 20
                        readonly property bool on: np.panel === modelData[0]
                        color: on ? Qt.rgba(1, 1, 1, 0.9) : tm.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : "transparent"
                        Icon { anchors.centerIn: parent; name: modelData[1]; size: 20; color: parent.on ? "#1c1c1c" : "#ffffff" }
                        MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; onClicked: np.panel = parent.on ? "" : modelData[0] }
                        ToolTip.visible: tm.containsMouse
                        ToolTip.text: modelData[2]
                        ToolTip.delay: 600
                    }
                }
            }
        }
    }

    // ---- right: synced lyrics ----
    Item {
        id: right
        visible: np.showPanel && np.panel === "lyrics"
        anchors.left: left.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.rightMargin: 56
        anchors.topMargin: 56
        anchors.bottomMargin: 40

        ListView {
            id: lyricList
            anchors.fill: parent
            model: Store.lyricLines
            clip: true
            spacing: 22
            boundsBehavior: Flickable.StopAtBounds
            header: Item { height: Store.lyricsSynced ? lyricList.height * 0.28 : 20 }
            footer: Item { height: lyricList.height * 0.6 }
            onMovementStarted: { userScroll.restart(); glide.stop() }
            onMovementEnded: userScroll.restart()
            Timer { id: userScroll; interval: 3000; onTriggered: lyricList.follow(false) }

            // Apple Music style: the list moves to the new line at once, and every
            // line then eases into place, the ones further down a little later.
            signal cascade(real delta)
            property int lastIndex: -1
            NumberAnimation { id: glide; target: lyricList; property: "contentY"; duration: 700; easing.type: Easing.OutCubic }
            function follow(stagger) {
                if (!Store.lyricsSynced || np.lyricIndex < 0 || userScroll.running || lyricList.moving) return
                var item = itemAtIndex(np.lyricIndex)
                if (!item) { positionViewAtIndex(np.lyricIndex, ListView.Beginning); item = itemAtIndex(np.lyricIndex); if (!item) return }
                var target = Math.max(originY, Math.min(item.y - height * 0.28, contentHeight + originY - height))
                var delta = target - contentY
                if (Math.abs(delta) < 1) return
                if (stagger && Math.abs(delta) < height * 0.6) {
                    glide.stop()
                    contentY = target
                    cascade(delta)
                } else {
                    glide.to = target
                    glide.restart()
                }
            }
            Connections {
                target: np
                // Cascade only when the song moves on to the next line; a seek glides.
                function onLyricIndexChanged() { lyricList.follow(np.lyricIndex === lyricList.lastIndex + 1); lyricList.lastIndex = np.lyricIndex }
                function onOpenChanged() { if (np.open) Qt.callLater(lyricList.follow, false) }
            }
            onCountChanged: Qt.callLater(follow, false)
            delegate: Text {
                id: line
                required property var modelData
                required property int index
                readonly property bool active: index === np.lyricIndex
                readonly property int distance: Math.abs(index - np.lyricIndex)
                transform: Translate { id: shift }
                Connections {
                    target: lyricList
                    function onCascade(delta) {
                        // Start where the line was, then ease to its new place.
                        var order = Math.max(0, Math.min(8, line.index - np.lyricIndex + 1))
                        settle.stop()
                        shift.y += delta   // keep any offset still easing out
                        wait.duration = order * 45
                        settle.start()
                    }
                }
                SequentialAnimation {
                    id: settle
                    PauseAnimation { id: wait; duration: 0 }
                    NumberAnimation { target: shift; property: "y"; to: 0; duration: 650; easing.type: Easing.OutCubic }
                }
                width: lyricList.width
                text: modelData.text === "" ? "• • •" : modelData.text
                wrapMode: Text.Wrap
                color: "#ffffff"
                font.family: Theme.display
                font.pixelSize: 30
                font.weight: Font.Bold
                lineHeight: 1.08
                opacity: !Store.lyricsSynced ? 0.85 : active ? 1.0 : (lineHover.hovered ? 0.6 : Math.max(0.18, 0.42 - distance * 0.04))
                scale: active ? 1.0 : 0.97
                transformOrigin: Item.Left
                Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                // Blur grows gradually with distance from the current line.
                property real blurAmount: !Store.lyricsSynced || lineHover.hovered || active ? 0 : Math.min(0.5, Math.max(0, distance - 1) * 0.12)
                Behavior on blurAmount { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                layer.enabled: blurAmount > 0.01
                layer.effect: MultiEffect { blurEnabled: true; blur: line.blurAmount; blurMax: 12 }
                HoverHandler { id: lineHover }
                TapHandler {
                    enabled: line.modelData.t !== null && line.modelData.t !== undefined
                    onTapped: if (np.player) { np.player.position = line.modelData.t; if (!Store.playing) np.player.play() }
                }
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            visible: Store.lyricLines.length === 0
            spacing: 12
            Spinner { Layout.alignment: Qt.AlignHCenter; visible: Store.lyricsLoading; size: 24 }
            Text {
                Layout.alignment: Qt.AlignHCenter
                visible: !Store.lyricsLoading
                text: !np.cur ? "Play a song to see its lyrics." : Store.lyricsError ? "Couldn't load lyrics." : "Lyrics aren't available for this song."
                color: Qt.rgba(1, 1, 1, 0.6)
                font.family: Theme.display
                font.pixelSize: 20
                font.weight: Font.DemiBold
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 360
                visible: !Store.lyricsLoading && !!Store.lyricsError
                text: Store.lyricsError
                color: Qt.rgba(1, 1, 1, 0.45)
                font.family: Theme.font
                font.pixelSize: 13
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    // ---- right: Up Next ----
    Item {
        visible: np.showPanel && np.panel === "queue"
        anchors.left: left.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.rightMargin: 56
        anchors.topMargin: 64
        anchors.bottomMargin: 40
        ColumnLayout {
            anchors.fill: parent
            spacing: 12
            Text { text: "Playing Next"; color: "#ffffff"; font.family: Theme.display; font.pixelSize: 22; font.weight: Font.Bold }
            Text {
                visible: Store.playQueue.length > 0
                text: (Store.shuffle ? "Shuffle on · " : "") + Math.max(0, Store.playQueue.length - Store.playIndex - 1) + " songs"
                color: Qt.rgba(1, 1, 1, 0.55); font.family: Theme.font; font.pixelSize: 13
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: Store.playQueue.slice(Store.playIndex + 1)
                ScrollBar.vertical: ScrollBar {}
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: 58
                    radius: 8
                    color: qh.hovered ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                    HoverHandler { id: qh }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (m) => {
                            if (m.button === Qt.RightButton) Store.showMenu({ entries: [modelData], queueIndex: Store.playIndex + 1 + index })
                            else Store.jumpTo(Store.playIndex + 1 + index)
                        }
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 12
                        Art { Layout.preferredWidth: 44; Layout.preferredHeight: 44; radius: 5; source: modelData.artwork || "" }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text { Layout.fillWidth: true; text: modelData.title; color: "#ffffff"; font.family: Theme.font; font.pixelSize: 15; elide: Text.ElideRight }
                            Text { Layout.fillWidth: true; text: modelData.artist || ""; color: Qt.rgba(1, 1, 1, 0.55); font.family: Theme.font; font.pixelSize: 13; elide: Text.ElideRight }
                        }
                        IconButton { visible: qh.hovered; icon: "x"; iconSize: 14; width: 30; height: 30; tip: "Remove from Up Next"; onClicked: Store.removeFromQueue(Store.playIndex + 1 + index) }
                    }
                }
                Text {
                    visible: parent.count === 0
                    text: "Nothing else is queued."
                    color: Qt.rgba(1, 1, 1, 0.55); font.family: Theme.font; font.pixelSize: 14
                }
            }
        }
    }
}
