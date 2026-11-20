pragma Singleton
import QtQuick

// Apple Music for Windows, sampled from the real app: sidebar #202020 over a #1c1c1c page.
QtObject {
    readonly property color sidebar: "#202020"
    readonly property color page: "#1c1c1c"
    readonly property color fill: "#2d2d2d"
    readonly property color fillHover: "#333333"
    readonly property color fillQuiet: Qt.rgba(1, 1, 1, 0.055)
    readonly property color stripe: Qt.rgba(1, 1, 1, 0.025)
    readonly property color hairline: Qt.rgba(1, 1, 1, 0.08)
    readonly property color panel: "#242424"
    readonly property color sheet: "#2b2b2b"
    readonly property color text: "#ffffff"
    readonly property color text2: "#a2a2a2"
    readonly property color text3: "#6f6f6f"
    readonly property color select: "#0091ff"
    readonly property color brand: "#fa2d48"
    readonly property color brandHover: "#ff4560"
    readonly property color ok: "#34c759"
    readonly property color warn: "#ffb340"
    readonly property color bad: "#ff5a5f"
    readonly property string appName: "死ねアップル"
    readonly property string font: "Segoe UI Variable Text"
    readonly property string display: "Segoe UI Variable Display"
    readonly property string mono: "Cascadia Mono"
}
