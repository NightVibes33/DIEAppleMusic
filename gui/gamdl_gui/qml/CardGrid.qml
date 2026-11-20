import QtQuick
import QtQuick.Layouts

// Responsive album grid: as many ~176px columns as fit, 22px gutters.
// Columns are worked out from the page width, not the grid's own width, so a
// grid that starts out empty or narrow can't lock itself at that size.
GridLayout {
    id: g
    readonly property real avail: parent && parent.width > 0 ? parent.width : width
    readonly property int cols: Math.max(2, Math.floor((avail + 22) / (176 + 22)))
    readonly property real cardWidth: Math.max(120, (avail - (cols - 1) * 22) / cols)
    columns: cols
    columnSpacing: 22
    rowSpacing: 26
}
