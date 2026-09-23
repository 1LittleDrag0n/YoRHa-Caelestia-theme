import QtQuick
import QtQuick.Layouts

// The HOTKEYS button that sits under the app widget (inside the same window).
Rectangle {
    id: btn
    signal clicked()

    readonly property color cBg: "#801a1410"
    readonly property color cBorder: "#6b5a2e"
    readonly property color cAccent: "#8f7c4a"
    readonly property color cText: "#c4b89c"
    readonly property color cHover: "#406b5a2e"
    readonly property string fontName: "JetBrainsMono Nerd Font"

    implicitWidth: row.implicitWidth + 28
    implicitHeight: 44
    radius: 16
    color: mouse.containsMouse ? cHover : cBg
    border.color: cBorder
    border.width: 1

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 8
        Text { text: "󰌌"; color: btn.cAccent; font.family: btn.fontName; font.pixelSize: 20 }
        Text { text: "HOTKEYS"; color: btn.cText; font.family: btn.fontName; font.pixelSize: 12; font.letterSpacing: 1.5 }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
