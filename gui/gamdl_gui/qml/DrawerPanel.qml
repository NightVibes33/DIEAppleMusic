import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

// Slide-in panel like Apple Music's Up Next: downloads and activity.
Item {
    id: d
    property string tab: ""
    width: 340
    visible: opacity > 0
    opacity: tab ? 1 : 0
    transform: Translate { x: d.tab ? 0 : 16; Behavior on x { NumberAnimation { duration: 180 } } }
    Behavior on opacity { NumberAnimation { duration: 180 } }
    z: 6

    RectangularShadow { anchors.fill: bg; radius: 10; blur: 50; offset.y: 16; color: Qt.rgba(0, 0, 0, 0.55) }
    Rectangle { id: bg; anchors.fill: parent; radius: 10; color: Qt.rgba(0.15, 0.15, 0.15, 0.97); border.color: Qt.rgba(1, 1, 1, 0.08) }
    MouseArea { anchors.fill: parent }  // keep clicks inside the panel

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Chip { text: "Downloading"; on: d.tab === "queue"; onClicked: d.tab = "queue" }
            Chip { text: "Activity"; on: d.tab === "log"; onClicked: d.tab = "log" }
            Item { Layout.fillWidth: true }
            IconButton { icon: "x"; iconSize: 16; onClicked: d.tab = "" }
        }

        // Downloads
        Flickable {
            visible: d.tab === "queue"
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: qcol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            ColumnLayout {
                id: qcol
                width: parent.width
                spacing: 2
                Text {
                    Layout.margins: 6
                    text: Store.activeCount + " IN PROGRESS"
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.7
                }
                Text {
                    visible: Store.itemsTotal === 0
                    Layout.margins: 6
                    text: "Nothing is downloading."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
                }
                Repeater {
                    model: Store.jobs
                    delegate: ColumnLayout {
                        id: jd
                        required property int jobId
                        Layout.fillWidth: true
                        spacing: 2
                        Repeater {
                            model: Store.jobModel(jd.jobId)
                            delegate: Rectangle {
                                required property var model
                                Layout.fillWidth: true
                                implicitHeight: 54
                                radius: 6
                                color: qh.hovered ? Theme.fillQuiet : "transparent"
                                HoverHandler { id: qh }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 10
                                    Art { Layout.preferredWidth: 40; Layout.preferredHeight: 40; radius: 4; source: model.artwork }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Text { Layout.fillWidth: true; text: model.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; elide: Text.ElideRight }
                                        Text {
                                            Layout.fillWidth: true
                                            text: model.status ? Store.statusText(model.status) : model.stage + (model.pct >= 0 ? " " + Math.round(model.pct) + "%" : "") + (model.detail ? " · " + model.detail : "")
                                            color: model.status === "failed" ? Theme.bad : Theme.text2; font.family: Theme.font; font.pixelSize: 12; elide: Text.ElideRight
                                        }
                                        Meter { visible: !model.status; Layout.fillWidth: true; value: model.pct }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Activity
        ListView {
            id: logList
            visible: d.tab === "log"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: Store.logModel
            spacing: 2
            ScrollBar.vertical: ScrollBar {}
            onCountChanged: positionViewAtEnd()
            delegate: Text {
                required property string level
                required property string msg
                required property string time
                width: logList.width - 12
                x: 6
                text: "<span style='color:#6f6f6f'>" + time + "</span>&nbsp;&nbsp;" + msg.replace(/&/g, "&amp;").replace(/</g, "&lt;")
                textFormat: Text.StyledText
                color: level === "error" ? Theme.bad : level === "warn" ? Theme.warn : level === "debug" ? Theme.text3 : "#cfcfcf"
                font.family: Theme.mono
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
            Text {
                visible: logList.count === 0
                x: 6
                text: "Sign-in, downloads and errors show up here."
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
            }
        }
    }
}
