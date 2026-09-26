import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// The button row under the app widget. What is in it comes from
// ~/.config/caelestia/yorha-desk-buttons.json, so buttons can be added without
// touching this file. Each entry is one of:
//
//   { "builtin": "hotkeys", "wide": true }        the hotkey list
//   { "builtin": "trash" }                        opens trash:/ and shows a count
//   { "icon": "󰄡", "label": "KDE Connect", "exec": ["kdeconnect-app"] }
//   { "app": "org.kde.dolphin.desktop", "label": "Files" }
//   { "icon": "…", "label": "…", "ipc": "drawers toggle sidebar" }   Caelestia
//
// "wide": true makes a button take the leftover width; the rest are square.
Item {
    id: bar
    signal clicked()            // the hotkeys button, wired up in shell.qml

    readonly property color cBg: "#801a1410"
    readonly property color cBgSolid: "#e61a1410"
    readonly property color cBorder: "#6b5a2e"
    readonly property color cAccent: "#8f7c4a"
    readonly property color cText: "#c4b89c"
    readonly property color cSub: "#8a847c"
    readonly property color cHover: "#406b5a2e"
    readonly property string fontName: "JetBrainsMono Nerd Font"

    readonly property string configPath: Quickshell.env("HOME") + "/.config/caelestia/yorha-desk-buttons.json"
    readonly property string trashDir: Quickshell.env("HOME") + "/.local/share/Trash/files"

    readonly property var defaultButtons: [
        { "builtin": "hotkeys", "wide": true },
        { "builtin": "trash" },
        { "icon": "󰄡", "label": "KDE Connect", "exec": ["kdeconnect-app"] }
    ]

    property var buttons: defaultButtons
    property int trashCount: 0

    implicitHeight: 44

    FileView {
        id: configFile
        path: bar.configPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const v = JSON.parse(text());
                if (Array.isArray(v) && v.length > 0) bar.buttons = v;
            } catch (e) { bar.buttons = bar.defaultButtons; }
        }
        onLoadFailed: {
            bar.buttons = bar.defaultButtons;
            configFile.setText(JSON.stringify(bar.defaultButtons, null, 2));
        }
    }

    // how many things are in the trash
    Process {
        id: counter
        command: ["sh", "-c", "find '" + bar.trashDir + "' -mindepth 1 -maxdepth 1 2>/dev/null | wc -l"]
        function reload() { if (!running) running = true; }
        stdout: StdioCollector {
            onStreamFinished: bar.trashCount = parseInt(this.text.trim()) || 0
        }
    }

    Component.onCompleted: counter.reload()

    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: counter.reload()
    }

    function run(btn) {
        if (!btn) return;

        if (btn.builtin === "hotkeys") {
            bar.clicked();
        } else if (btn.builtin === "trash") {
            Quickshell.execDetached(["dolphin", "trash:/"]);
            counter.reload();
        } else if (btn.ipc) {
            Quickshell.execDetached(["sh", "-c", "qs -c caelestia ipc call " + btn.ipc]);
        } else if (btn.exec) {
            Quickshell.execDetached(Array.isArray(btn.exec) ? btn.exec : ["sh", "-c", String(btn.exec)]);
        } else if (btn.app) {
            const E = DesktopEntries.heuristicLookup(String(btn.app));
            if (E) E.execute();
        }
    }

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 8

        Repeater {
            model: bar.buttons

            delegate: Rectangle {
                id: btnItem
                required property var modelData

                readonly property var  entry: modelData.app ? DesktopEntries.heuristicLookup(String(modelData.app)) : null
                readonly property bool isTrash: modelData.builtin === "trash"
                readonly property string glyph: modelData.icon ? String(modelData.icon)
                                              : (modelData.builtin === "hotkeys" ? "󰌌"
                                              : (btnItem.isTrash ? (bar.trashCount > 0 ? "󰩹" : "󰎟") : ""))
                readonly property string title: modelData.label ? String(modelData.label)
                                              : (modelData.builtin === "hotkeys" ? "HOTKEYS"
                                              : (btnItem.isTrash
                                                 ? (bar.trashCount === 0 ? "Trash is empty"
                                                    : "Trash — " + bar.trashCount + " item" + (bar.trashCount === 1 ? "" : "s"))
                                                 : (btnItem.entry ? String(btnItem.entry.name) : "")))

                Layout.fillWidth: modelData.wide === true
                Layout.preferredWidth: modelData.wide === true ? -1 : 58
                Layout.fillHeight: true

                radius: 16
                color: btnHover.hovered ? bar.cHover : bar.cBg
                border.color: bar.cBorder
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    IconImage {
                        visible: btnItem.entry !== null
                        implicitSize: 22
                        source: btnItem.entry && btnItem.entry.icon
                                ? Quickshell.iconPath(btnItem.entry.icon, "application-x-executable") : ""
                    }

                    Text {
                        visible: btnItem.entry === null
                        text: btnItem.glyph
                        color: (btnItem.isTrash && bar.trashCount > 0) ? bar.cAccent : bar.cAccent
                        font.family: bar.fontName
                        font.pixelSize: 19
                    }

                    Text {          // the wide button shows its label, and trash its count
                        visible: modelData.wide === true || (btnItem.isTrash && bar.trashCount > 0)
                        text: modelData.wide === true ? btnItem.title
                                                      : (bar.trashCount > 99 ? "99+" : bar.trashCount)
                        color: modelData.wide === true ? bar.cText : bar.cSub
                        font.family: bar.fontName
                        font.pixelSize: modelData.wide === true ? 12 : 11
                        font.letterSpacing: modelData.wide === true ? 1.5 : 0
                    }
                }

                HoverHandler { id: btnHover; cursorShape: Qt.PointingHandCursor }
                MouseArea { anchors.fill: parent; onClicked: bar.run(modelData) }

                Rectangle {          // label on hover, for the square buttons
                    visible: btnHover.hovered && modelData.wide !== true
                    anchors.bottom: parent.top
                    anchors.bottomMargin: 6
                    anchors.horizontalCenter: parent.horizontalCenter
                    implicitWidth: hoverLabel.implicitWidth + 16
                    implicitHeight: 24
                    radius: 8
                    color: bar.cBgSolid
                    border.color: bar.cBorder
                    border.width: 1
                    Text {
                        id: hoverLabel
                        anchors.centerIn: parent
                        text: btnItem.title
                        color: bar.cText
                        font.family: bar.fontName
                        font.pixelSize: 11
                    }
                }
            }
        }
    }
}
