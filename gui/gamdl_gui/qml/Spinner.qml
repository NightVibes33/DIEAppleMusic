import QtQuick

Item {
    id: root
    property real size: 16
    property color color: "#ffffff"
    width: size
    height: size
    Canvas {
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.lineWidth = 2
            ctx.lineCap = "round"
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.22)
            ctx.beginPath(); ctx.arc(width / 2, height / 2, width / 2 - 1.5, 0, Math.PI * 2); ctx.stroke()
            ctx.strokeStyle = root.color
            ctx.beginPath(); ctx.arc(width / 2, height / 2, width / 2 - 1.5, -Math.PI / 2, 0); ctx.stroke()
        }
        RotationAnimation on rotation { from: 0; to: 360; duration: 800; loops: Animation.Infinite; running: root.visible }
    }
}
