import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Transport | now playing / downloading display | volume, panels, window controls.
Item {
    id: bar
    property var player
    property string drawer: ""
    signal drawerToggled(string tab)
    signal closeRequested()
    signal lyricsRequested()

    readonly property bool maximized: Window.window && Window.window.visibility === Window.Maximized

    WindowDragArea {}
    function toggleMax() { if (maximized) Window.window.showNormal(); else Window.window.showMaximized() }

    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: Qt.rgba(1, 1, 1, 0.06) }

    // Transport
    Row {
        id: transport
        anchors.left: parent.left
        anchors.leftMargin: 34
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        IconButton { icon: "shuffle"; iconSize: 18; active: Store.shuffle; tip: "Shuffle"; anchors.verticalCenter: parent.verticalCenter; onClicked: Store.shuffle = !Store.shuffle }
        IconButton { icon: "prev"; iconSize: 22; tip: "Previous"; anchors.verticalCenter: parent.verticalCenter; onClicked: Store.prev() }
        IconButton {
            icon: Store.playing ? "pause-f" : "play-f"; iconSize: 28; width: 42; height: 42
            tip: Store.playing ? "Pause" : "Play"; anchors.verticalCenter: parent.verticalCenter
            onClicked: Store.toggle()
        }
        IconButton { icon: "next"; iconSize: 22; tip: "Next"; anchors.verticalCenter: parent.verticalCenter; onClicked: Store.next(false) }
        IconButton {
            icon: "repeat"; iconSize: 18; active: Store.repeatMode > 0; anchors.verticalCenter: parent.verticalCenter
            tip: ["Repeat off", "Repeat all", "Repeat one"][Store.repeatMode]
            onClicked: Store.repeatMode = (Store.repeatMode + 1) % 3
            Text { visible: Store.repeatMode === 2; text: "1"; color: Theme.select; font.pixelSize: 8; font.weight: Font.Black; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 6 }
        }
    }

    // LCD
    Rectangle {
        id: lcd
        anchors.verticalCenter: parent.verticalCenter
        // Centered in the gap between the transport and the volume and panel
        // buttons, so it never sits under either.
        readonly property real gapLeft: transport.x + transport.width + 16
        readonly property real gapRight: rightSide.x - 16
        width: Math.max(200, Math.min(428, gapRight - gapLeft))
        x: gapLeft + (gapRight - gapLeft - width) / 2
        height: 50
        radius: 6
        clip: true
        color: Qt.rgba(0.12, 0.12, 0.12, 0.55)
        border.color: Qt.rgba(1, 1, 1, 0.07)
        readonly property bool showPlayer: Store.current !== null
        readonly property var dl: Store.focus

        Item {
            id: lcdArt
            width: 50
            height: 50
            Rectangle { anchors.fill: parent; color: "#282828" }
            Art {
                anchors.fill: parent
                radius: 0
                source: lcd.showPlayer ? (Store.current.artwork || "") : lcd.dl ? lcd.dl.artwork : ""
                visible: lcd.showPlayer || lcd.dl
            }
            Icon { anchors.centerIn: parent; name: "note"; size: 22; color: "#777777"; visible: !lcd.showPlayer && !lcd.dl }
            Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.45); visible: Store.loading; Spinner { anchors.centerIn: parent } }
        }
        // Click the artwork or title to expand into Now Playing.
        MouseArea {
            anchors.left: parent.left
            anchors.top: parent.top
            width: lcd.showPlayer ? parent.width : 50
            height: lcd.showPlayer ? 34 : 50
            enabled: lcd.showPlayer
            cursorShape: Qt.PointingHandCursor
            onClicked: Store.nowPlayingOpen = true
        }

        // Player mode
        Item {
            anchors.left: lcdArt.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            visible: lcd.showPlayer
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 6
                width: parent.width - 100
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 5
                    Text {
                        id: pt
                        width: Math.min(implicitWidth, lcd.width - 170)
                        text: Store.current ? Store.current.title : ""
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight
                    }
                    Explicit { visible: Store.current && Store.current.explicit; anchors.verticalCenter: pt.verticalCenter }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Store.current ? [Store.current.artist, Store.current.album].filter(function (x) { return x }).join(" — ") : ""
                    color: Qt.rgba(1, 1, 1, 0.62); font.family: Theme.font; font.pixelSize: 12; elide: Text.ElideRight
                }
            }
            Text {
                visible: Store.playSource === "preview"
                text: "PREVIEW"
                color: Qt.rgba(1, 1, 1, 0.85); font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 0.6
                anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 6
            }
            Text {
                anchors.left: parent.left; anchors.leftMargin: 10; anchors.bottom: parent.bottom; anchors.bottomMargin: 1
                text: Store.fmtDur(bar.player ? bar.player.position : 0)
                color: Qt.rgba(1, 1, 1, 0.55); font.pixelSize: 11; font.family: Theme.font
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 10; anchors.bottom: parent.bottom; anchors.bottomMargin: 1
                text: "-" + Store.fmtDur(bar.player ? bar.player.duration - bar.player.position : 0)
                color: Qt.rgba(1, 1, 1, 0.55); font.pixelSize: 11; font.family: Theme.font
            }
            Rectangle {
                id: scrub
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                anchors.leftMargin: 48; anchors.rightMargin: 48; anchors.bottomMargin: scrubMa.containsMouse ? 4 : 5
                height: scrubMa.containsMouse ? 6 : 4
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.16)
                Rectangle {
                    height: parent.height; radius: parent.radius; color: Qt.rgba(1, 1, 1, 0.8)
                    width: bar.player && bar.player.duration > 0 ? parent.width * bar.player.position / bar.player.duration : 0
                }
                MouseArea {
                    id: scrubMa
                    anchors.fill: parent; anchors.margins: -6
                    hoverEnabled: true
                    onClicked: (m) => { if (bar.player && bar.player.duration > 0) bar.player.position = Math.max(0, Math.min(1, (m.x - 6) / scrub.width)) * bar.player.duration }
                }
            }
            // Download badge while a song plays
            Rectangle {
                visible: Store.activeCount > 0
                anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 5
                height: 18; radius: 9; width: dlRow.implicitWidth + 12
                color: Qt.rgba(0.98, 0.18, 0.28, 0.85)
                Row { id: dlRow; anchors.centerIn: parent; spacing: 3
                    Icon { name: "download"; size: 11; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: Store.activeCount; color: "#ffffff"; font.pixelSize: 11; font.weight: Font.DemiBold; font.family: Theme.font }
                }
                MouseArea { anchors.fill: parent; onClicked: bar.drawerToggled("queue") }
            }
        }

        // Download mode
        Item {
            anchors.left: lcdArt.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            visible: !lcd.showPlayer && lcd.dl !== null
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 6
                width: parent.width - 100
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: lcd.dl ? lcd.dl.title : ""
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight
                }
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: lcd.dl ? (lcd.dl.stage + (lcd.dl.pct >= 0 ? " " + Math.round(lcd.dl.pct) + "%" : "")) : ""
                    color: Qt.rgba(1, 1, 1, 0.62); font.family: Theme.font; font.pixelSize: 12; elide: Text.ElideRight
                }
            }
            Text {
                anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 6
                text: (Store.itemsDone + 1) + " of " + Store.itemsTotal
                color: Qt.rgba(1, 1, 1, 0.55); font.pixelSize: 11; font.family: Theme.font
            }
            Meter {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                anchors.leftMargin: 14; anchors.rightMargin: 14; anchors.bottomMargin: 5
                height: 3
                value: lcd.dl ? lcd.dl.pct : -1
                tint: Qt.rgba(1, 1, 1, 0.75)
            }
        }

        // Idle
        Item {
            anchors.left: lcdArt.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            visible: !lcd.showPlayer && lcd.dl === null
            Row {
                anchors.centerIn: parent
                spacing: 8
                visible: Store.status !== ""
                Spinner { anchors.verticalCenter: parent.verticalCenter }
                Text { text: Store.status; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
            }
            Rectangle {
                anchors.centerIn: parent
                visible: Store.status === ""
                width: 22; height: 22; radius: 6; opacity: 0.75
                gradient: Gradient {
                    GradientStop { position: 0; color: "#ff5c75" }
                    GradientStop { position: 1; color: "#d81c3c" }
                }
                Icon { anchors.centerIn: parent; name: "note"; size: 13 }
            }
        }
    }

    // Right side
    Row {
        id: rightSide
        anchors.right: winCtl.left
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        VolumeSlider { anchors.verticalCenter: parent.verticalCenter; sliderWidth: 90; iconSize: 17 }
        Item { width: 6; height: 1 }
        IconButton { icon: "lyrics"; tip: "Lyrics"; active: Store.nowPlayingOpen; onClicked: { bar.lyricsRequested(); Store.nowPlayingOpen = !Store.nowPlayingOpen } }
        IconButton { icon: "activity"; tip: "Activity"; active: bar.drawer === "log"; onClicked: bar.drawerToggled("log") }
        IconButton { icon: "queue"; tip: "Downloading"; active: bar.drawer === "queue"; onClicked: bar.drawerToggled("queue") }
    }

    Row {
        id: winCtl
        anchors.right: parent.right
        anchors.top: parent.top
        Repeater {
            model: [["min", "Minimize"], [bar.maximized ? "restore" : "max", bar.maximized ? "Restore" : "Maximize"], ["close", "Close"]]
            Rectangle {
                required property var modelData
                required property int index
                width: 46; height: 32
                color: ma.containsMouse ? (index === 2 ? "#c42b1c" : Qt.rgba(1, 1, 1, 0.08)) : "transparent"
                Icon { anchors.centerIn: parent; name: modelData[0]; size: 10 }
                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (index === 0) Window.window.showMinimized()
                        else if (index === 1) bar.toggleMax()
                        else bar.closeRequested()
                    }
                }
            }
        }
    }
}
