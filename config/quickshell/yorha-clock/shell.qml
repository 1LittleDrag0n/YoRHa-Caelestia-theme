//@ pragma UseQApplication
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// YoRHa desktop clock.
//
// Everything you might want to change lives in
// ~/.config/caelestia/yorha-clock.json - it is written the first time this
// runs, and re-read whenever it changes, so you never have to touch this file:
//
//   x, y          where it sits (also saved automatically when you drag it)
//   use24         true = 14:37, false = 02:37 PM
//   showSeconds   seconds after the minutes
//   showBar       the thin second-hand line under the time
//   showDate      the date row
//   label         the small caps line at the top, "" to hide it
//   scale         1.0 is normal, 1.5 is half again as big
//   opacity       0..1 for the panel background
//   locked        true stops it being dragged
//   monitor       "" for the first screen, or a name like "DP-1"
//
// Hide / show it with:  qs -c yorha-clock ipc call clock toggle
PanelWindow {
    id: root

    // ------------------------------------------------------------ palette
    readonly property color cBg: "#801a1410"
    readonly property color cBgSolid: "#e61a1410"
    readonly property color cBorder: "#6b5a2e"
    readonly property color cAccent: "#8f7c4a"
    readonly property color cText: "#c4b89c"
    readonly property color cSub: "#8a847c"
    readonly property string fontName: "JetBrainsMono Nerd Font"

    // ------------------------------------------------------------- config
    readonly property string cfgPath: Quickshell.env("HOME") + "/.config/caelestia/yorha-clock.json"

    property int     posX: 80
    property int     posY: 80
    property bool    use24: true
    property bool    showSeconds: true
    property bool    showBar: true
    property bool    showDate: true
    property string  label: "YoRHa UNIT"
    property real    uiScale: 1.0
    property real    bgOpacity: 0.5
    property bool    locked: false
    property string  monitor: ""

    property bool hidden: false
    property bool loading: false

    function applyConfig(raw) {
        let c;
        try { c = JSON.parse(raw); } catch (e) { return; }
        if (!c || typeof c !== "object") return;

        root.loading = true;
        if (c.x !== undefined)           root.posX = Number(c.x);
        if (c.y !== undefined)           root.posY = Number(c.y);
        if (c.use24 !== undefined)       root.use24 = !!c.use24;
        if (c.showSeconds !== undefined) root.showSeconds = !!c.showSeconds;
        if (c.showBar !== undefined)     root.showBar = !!c.showBar;
        if (c.showDate !== undefined)    root.showDate = !!c.showDate;
        if (c.label !== undefined)       root.label = String(c.label);
        if (c.scale !== undefined)       root.uiScale = Math.max(0.5, Math.min(4, Number(c.scale)));
        if (c.opacity !== undefined)     root.bgOpacity = Math.max(0, Math.min(1, Number(c.opacity)));
        if (c.locked !== undefined)      root.locked = !!c.locked;
        if (c.monitor !== undefined)     root.monitor = String(c.monitor);
        root.loading = false;
    }

    function saveConfig() {
        if (root.loading) return;
        cfgFile.setText(JSON.stringify({
            x: Math.round(root.posX),
            y: Math.round(root.posY),
            use24: root.use24,
            showSeconds: root.showSeconds,
            showBar: root.showBar,
            showDate: root.showDate,
            label: root.label,
            scale: root.uiScale,
            opacity: root.bgOpacity,
            locked: root.locked,
            monitor: root.monitor
        }, null, 2));
    }

    FileView {
        id: cfgFile
        path: root.cfgPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.applyConfig(text())
        onLoadFailed: root.saveConfig()
    }

    // -------------------------------------------------------------- clock
    property date now: new Date()

    Timer {
        interval: root.showSeconds || root.showBar ? 200 : 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    readonly property string tHour: Qt.formatDateTime(root.now, root.use24 ? "HH" : "hh")
    readonly property string tMin:  Qt.formatDateTime(root.now, "mm")
    readonly property string tSec:  Qt.formatDateTime(root.now, "ss")
    readonly property string tAmPm: Qt.formatDateTime(root.now, "AP")
    readonly property string tDate: Qt.formatDateTime(root.now, "dddd  dd.MM.yyyy").toUpperCase()

    // ------------------------------------------------------------- window
    screen: {
        const list = Quickshell.screens;
        if (root.monitor !== "")
            for (const s of list)
                if (s.name === root.monitor) return s;
        return list.length > 0 ? list[0] : null;
    }

    anchors { top: true; left: true; right: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "yorha-clock"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // only the widget itself takes clicks; the rest of the desktop is untouched
    mask: Region {
        x: root.hidden ? 0 : Math.round(root.posX)
        y: root.hidden ? 0 : Math.round(root.posY)
        width: root.hidden ? 0 : Math.round(frame.width)
        height: root.hidden ? 0 : Math.round(frame.height)
    }

    IpcHandler {
        target: "clock"
        function toggle(): void { root.hidden = !root.hidden }
        function show(): void   { root.hidden = false }
        function hide(): void   { root.hidden = true }
        function reload(): void { cfgFile.reload() }
        function center(): void {
            root.posX = Math.round((root.width - frame.width) / 2);
            root.posY = Math.round((root.height - frame.height) / 2);
            root.saveConfig();
        }
    }

    // -------------------------------------------------------------- frame
    Item {
        id: frame

        x: Math.round(root.posX)
        y: Math.round(root.posY)
        width: body.implicitWidth + 44 * root.uiScale
        height: body.implicitHeight + 34 * root.uiScale
        visible: !root.hidden
        opacity: root.hidden ? 0 : 1

        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.fill: parent
            radius: 16
            color: Qt.rgba(0.102, 0.078, 0.063, root.bgOpacity)
            border.color: root.cBorder
            border.width: 1
        }

        // corner brackets
        Repeater {
            model: [[0, 0], [1, 0], [0, 1], [1, 1]]
            delegate: Item {
                id: corner
                required property var modelData
                readonly property bool atRight: corner.modelData[0] === 1
                readonly property bool atBottom: corner.modelData[1] === 1
                readonly property real arm: 14 * root.uiScale

                x: corner.atRight ? frame.width - corner.arm - 7 : 7
                y: corner.atBottom ? frame.height - corner.arm - 7 : 7
                width: corner.arm
                height: corner.arm

                Rectangle {
                    width: corner.arm
                    height: 2
                    y: corner.atBottom ? corner.arm - 2 : 0
                    color: root.cAccent
                }
                Rectangle {
                    width: 2
                    height: corner.arm
                    x: corner.atRight ? corner.arm - 2 : 0
                    color: root.cAccent
                }
            }
        }

        Column {
            id: body
            anchors.centerIn: parent
            spacing: 6 * root.uiScale

            // small caps label
            Text {
                visible: root.label !== ""
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.label.toUpperCase()
                color: root.cSub
                font.family: root.fontName
                font.pixelSize: 11 * root.uiScale
                font.letterSpacing: 4 * root.uiScale
            }

            // HH : MM  ss
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 0

                Text {
                    id: bigTime
                    text: root.tHour + ":" + root.tMin
                    color: root.cText
                    font.family: root.fontName
                    font.pixelSize: 64 * root.uiScale
                    font.letterSpacing: 2 * root.uiScale
                    font.weight: Font.Light
                }

                Column {
                    visible: root.showSeconds || !root.use24
                    anchors.bottom: bigTime.bottom
                    anchors.bottomMargin: 12 * root.uiScale
                    leftPadding: 8 * root.uiScale
                    spacing: 2

                    Text {
                        visible: !root.use24
                        text: root.tAmPm
                        color: root.cSub
                        font.family: root.fontName
                        font.pixelSize: 13 * root.uiScale
                        font.letterSpacing: 2 * root.uiScale
                    }
                    Text {
                        visible: root.showSeconds
                        text: root.tSec
                        color: root.cAccent
                        font.family: root.fontName
                        font.pixelSize: 18 * root.uiScale
                        font.letterSpacing: 1 * root.uiScale
                    }
                }
            }

            // seconds sweep
            Rectangle {
                visible: root.showBar
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(bigTime.implicitWidth, dateRow.implicitWidth)
                height: 2
                color: Qt.rgba(0.42, 0.36, 0.18, 0.45)

                Rectangle {
                    height: parent.height
                    width: parent.width * ((root.now.getSeconds() + root.now.getMilliseconds() / 1000) / 60)
                    color: root.cAccent
                }
            }

            Text {
                id: dateRow
                visible: root.showDate
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.tDate
                color: root.cSub
                font.family: root.fontName
                font.pixelSize: 12 * root.uiScale
                font.letterSpacing: 2.5 * root.uiScale
            }
        }

        // drag to move, position is remembered
        MouseArea {
            id: dragArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: root.locked ? Qt.ArrowCursor
                                     : (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
            hoverEnabled: true

            property real ox: 0
            property real oy: 0

            onPressed: mouse => { ox = mouse.x; oy = mouse.y }
            onPositionChanged: mouse => {
                if (!pressed || root.locked) return;
                root.posX = Math.max(0, Math.min(root.width - frame.width, root.posX + (mouse.x - ox)));
                root.posY = Math.max(0, Math.min(root.height - frame.height, root.posY + (mouse.y - oy)));
            }
            onReleased: root.saveConfig()
        }

        // settings, same as the dock and desk widgets
        Rectangle {
            id: gear
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 6
            width: 22
            height: 22
            radius: 11
            color: gearHover.hovered ? root.cHoverBg : "transparent"
            opacity: dragArea.containsMouse || gearHover.hovered ? 1 : 0

            Behavior on opacity { NumberAnimation { duration: 140 } }

            Text {
                anchors.centerIn: parent
                text: ""
                color: root.cAccent
                font.family: root.fontName
                font.pixelSize: 12
            }

            HoverHandler { id: gearHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: Quickshell.execDetached(["kate", root.cfgPath])
            }
        }
    }

    readonly property color cHoverBg: "#406b5a2e"
}
