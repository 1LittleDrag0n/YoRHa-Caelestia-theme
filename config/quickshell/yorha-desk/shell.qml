import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

ShellRoot {
    id: root

    // ===== Settings =====
    // Favourite apps: names are matched loosely against installed apps
    readonly property var favourites: ["dolphin", "konsole", "zen", "blender", "resolve", "spotify"]
    readonly property string desktopDir: Quickshell.env("HOME") + "/Desktop"
    readonly property int posTop: 80
    readonly property int posLeft: 90
    readonly property int iconSize: 44
    readonly property int columns: 4

    // YoRHa palette
    readonly property color cBg: "#801a1410"
    readonly property color cBorder: "#6b5a2e"
    readonly property color cAccent: "#8f7c4a"
    readonly property color cText: "#c4b89c"
    readonly property color cSub: "#8a847c"
    readonly property color cHover: "#406b5a2e"
    readonly property string fontName: "JetBrainsMono Nerd Font"

    property bool expanded: false

    component Tile: Item {
        id: tile
        property string label
        property string iconName
        signal activated()

        width: 84
        height: 84

        Rectangle {
            anchors.fill: parent
            color: mouse.containsMouse ? root.cHover : "transparent"
            radius: 10
            border.color: mouse.containsMouse ? root.cBorder : "transparent"
            border.width: 1
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 4

            IconImage {
                Layout.alignment: Qt.AlignHCenter
                implicitSize: root.iconSize
                source: tile.iconName.startsWith("/")
                ? "file://" + tile.iconName
                : Quickshell.iconPath(tile.iconName, "application-x-executable")
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 78
                text: tile.label
                color: root.cText
                font.family: root.fontName
                font.pixelSize: 10
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.activated()
        }
    }

    PanelWindow {
        screen: Quickshell.screens[0]
        anchors { top: true; left: true }
        margins.top: root.posTop
        margins.left: root.posLeft

        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "yorha-desk"
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        implicitWidth: panel.implicitWidth
        implicitHeight: panel.implicitHeight + 12 + hotkeysBtn.implicitHeight
        HotkeysButton {
            id: hotkeysBtn
            y: panel.height + 12
            width: panel.width
            onClicked: hotkeys.open = true
        }

        Rectangle {
            id: panel
            implicitWidth: content.implicitWidth + 24
            implicitHeight: content.implicitHeight + 24
            color: root.cBg
            radius: 16
            border.color: root.cBorder
            border.width: 1

            ColumnLayout {
                id: content
                anchors.centerIn: parent
                spacing: 8

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "▣ FAVOURITES"
                        color: root.cAccent
                        font.family: root.fontName
                        font.pixelSize: 12
                        font.letterSpacing: 1.5
                    }
                    Item { Layout.fillWidth: true }
                    Text {          // yorha-settings-gear
                        text: "󰒓"
                        color: gearMouse.containsMouse ? root.cText : root.cSub
                        font.family: root.fontName
                        font.pixelSize: 12
                        rightPadding: 8
                        MouseArea {
                            id: gearMouse
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["sh", "-c",
                                "cd \"$HOME/.config/caelestia\"; kate yorha-desk-buttons.json yorha-dock-buttons.json yorha-dock-icons.json yorha-hotkeys.json 2>/dev/null || xdg-open yorha-desk-buttons.json"])
                        }
                    }

                    Text {
                        text: root.expanded ? "[-]" : "[+]"
                        color: toggle.containsMouse ? root.cText : root.cSub
                        font.family: root.fontName
                        font.pixelSize: 12
                        MouseArea {
                            id: toggle
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.expanded = !root.expanded
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.cBorder }

                // Favourites
                GridLayout {
                    columns: root.columns
                    rowSpacing: 2
                    columnSpacing: 2

                    Repeater {
                        model: root.favourites
                        delegate: Tile {
                            required property string modelData
                            readonly property var entry: { DesktopEntries.applications.values; return DesktopEntries.heuristicLookup(modelData); }
                            visible: entry != null
                            label: entry ? entry.name : ""
                            iconName: entry ? entry.icon : ""
                            onActivated: if (entry) entry.execute()
                        }
                    }
                }

                // Desktop shortcuts (expanded)
                ColumnLayout {
                    visible: root.expanded
                    spacing: 8

                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.cBorder }

                    Text {
                        text: "▣ DESKTOP"
                        color: root.cAccent
                        font.family: root.fontName
                        font.pixelSize: 12
                        font.letterSpacing: 1.5
                    }

                    GridLayout {
                        columns: root.columns
                        rowSpacing: 2
                        columnSpacing: 2

                        Repeater {
                            model: FolderListModel {
                                folder: "file://" + root.desktopDir
                                nameFilters: ["*.desktop"]
                                showDirs: false
                            }

                            delegate: Tile {
                                id: dtile
                                required property string filePath
                                required property string fileBaseName
                                property string raw: ""

                                function field(key) {
                                    const m = raw.match(new RegExp("^" + key + "=(.*)$", "m"));
                                    return m ? m[1].trim() : "";
                                }

                                label: field("Name") || fileBaseName
                                iconName: field("Icon")
                                onActivated: Quickshell.execDetached(["gio", "launch", filePath])

                                FileView {
                                    path: dtile.filePath
                                    onLoaded: dtile.raw = text()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    YorhaHotkeys { id: hotkeys }
}
