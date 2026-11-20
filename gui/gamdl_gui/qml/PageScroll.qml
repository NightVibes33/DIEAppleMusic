import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Scrolling page body with the standard 40px side margins.
Flickable {
    id: page
    property Component actions: null
    default property alias content: col.data
    property alias spacing: col.spacing
    contentHeight: col.implicitHeight + 64
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    ColumnLayout {
        id: col
        x: page.width > 1000 ? 40 : 24
        y: 14
        width: page.width - 2 * x
        spacing: 12
    }
}
