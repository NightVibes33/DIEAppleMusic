import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Rectangle {
    id: p
    property string status
    property string tip
    readonly property string tone: ({ downloaded: "ok", overwritten: "ok", skipped: "warn", partial: "warn", failed: "bad" })[status] || ""
    readonly property color fg: tone === "ok" ? Theme.ok : tone === "warn" ? Theme.warn : tone === "bad" ? Theme.bad : Theme.text2
    implicitHeight: 22
    implicitWidth: row.implicitWidth + 18
    radius: 11
    color: tone === "" ? Theme.fill : Qt.rgba(fg.r, fg.g, fg.b, 0.13)
    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Icon {
            size: 13
            color: p.fg
            name: ({ downloaded: "check", overwritten: "check", skipped: "skip", partial: "alert", failed: "alert", cancelled: "stop" })[p.status] || "check"
        }
        Text { text: Store.statusText(p.status); color: p.fg; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true }
    ToolTip.visible: p.tip !== "" && ma.containsMouse
    ToolTip.text: p.tip
}
