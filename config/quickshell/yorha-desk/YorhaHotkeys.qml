import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: hk

    // (old placement settings, no longer used; kept so older shell.qml lines still load)
    property Item below
    property int posTop: 0
    property int posLeft: 0

    // YoRHa palette (same as the app widget)
    readonly property color cBg: "#801a1410"
    readonly property color cCard: "#e61a1410"
    readonly property color cBorder: "#6b5a2e"
    readonly property color cAccent: "#8f7c4a"
    readonly property color cText: "#c4b89c"
    readonly property color cSub: "#8a847c"
    readonly property color cHover: "#406b5a2e"
    readonly property color cKey: "#402a241c"
    readonly property color cWarn: "#c0584a"
    readonly property string fontName: "JetBrainsMono Nerd Font"

    property bool open: false
    property var allBinds: []
    property string query: ""
    property string category: "All"

    readonly property var categories: {
        const c = ["All"];
        for (const b of allBinds)
            if (!c.includes(b.cat)) c.push(b.cat);
        return c;
    }

    function refilter() {
        filtered.clear();
        const q = query.toLowerCase().trim();
        for (const b of allBinds) {
            if (category !== "All" && b.cat !== category) continue;
            if (q === "clash" || q === "clashes") { if (!(b.clash || []).length) continue; }
            else if (q && !(b.keys + " " + b.action + " " + b.cat).toLowerCase().includes(q)) continue;
            filtered.append({ cat: b.cat, keys: b.keys, action: b.action,
                              clash: (b.clash || []).join("   ") });
        }
    }
    onQueryChanged: refilter()
    onCategoryChanged: refilter()
    onAllBindsChanged: refilter()

    ListModel { id: filtered }

    // The list is read from your live Hyprland config by ~/.local/bin/yorha-hotkeys
    // every time the popup opens, so it always matches what you have set up.
    property bool loading: false
    property string errorText: ""

    function reload() {
        if (reader.running) return;
        hk.loading = true;
        reader.running = true;
    }

    Process {
        id: reader
        command: [Quickshell.env("HOME") + "/.local/bin/yorha-hotkeys"]
        stdout: StdioCollector {
            onStreamFinished: {
                hk.loading = false;
                try { hk.allBinds = JSON.parse(this.text); hk.errorText = ""; }
                catch (e) { hk.errorText = "Couldn't read hotkeys: " + e; }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (this.text.trim()) console.warn("yorha-hotkeys:", this.text.trim())
        }
    }

    Component.onCompleted: reload()
    onOpenChanged: if (open) reload()

    // `qs -c yorha-desk ipc call hotkeys toggle` (bound to Super+/)
    IpcHandler {
        target: "hotkeys"
        function toggle(): void { hk.open = !hk.open; }
    }

    // The HOTKEYS button itself lives inside the app widget's window
    // (HotkeysButton.qml), so it always moves together with it.

    // ---------- the popup ----------
    PanelWindow {
        visible: hk.open
        screen: Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "yorha-hotkeys-popup"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore
        color: "#66000000"

        onVisibleChanged: if (visible) { search.text = ""; hk.category = "All"; search.forceActiveFocus(); }

        // click outside closes
        MouseArea { anchors.fill: parent; onClicked: hk.open = false }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.6, 900)
            height: parent.height * 0.78
            radius: 16
            color: hk.cCard
            border.color: hk.cBorder
            border.width: 1

            // swallow clicks inside the card
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "󰌌  HOTKEYS"; color: hk.cAccent; font.family: hk.fontName; font.pixelSize: 16; font.letterSpacing: 2 }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: hk.loading ? "reading config…" : filtered.count + " shown"
                        color: hk.cSub; font.family: hk.fontName; font.pixelSize: 11
                    }
                    Text {
                        text: "  ✕"
                        color: closeMouse.containsMouse ? hk.cText : hk.cSub
                        font.family: hk.fontName
                        font.pixelSize: 16
                        MouseArea { id: closeMouse; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: hk.open = false }
                    }
                }

                // search box
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: 10
                    color: hk.cKey
                    border.color: search.activeFocus ? hk.cAccent : hk.cBorder
                    border.width: 1

                    TextInput {
                        id: search
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        color: hk.cText
                        selectionColor: hk.cBorder
                        font.family: hk.fontName
                        font.pixelSize: 13
                        clip: true
                        onTextChanged: hk.query = text
                        Keys.onEscapePressed: hk.open = false

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !search.text
                            text: "Search keys or actions…   (type \"clash\" to see conflicts)"
                            color: hk.cSub
                            font.family: hk.fontName
                            font.pixelSize: 13
                        }
                    }
                }

                // category chips
                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: hk.categories
                        delegate: Rectangle {
                            required property string modelData
                            implicitWidth: chipText.implicitWidth + 20
                            implicitHeight: 28
                            radius: 10
                            color: hk.category === modelData ? hk.cAccent : (chipMouse.containsMouse ? hk.cHover : "transparent")
                            border.color: hk.cBorder
                            border.width: 1

                            Text {
                                id: chipText
                                anchors.centerIn: parent
                                text: modelData
                                color: hk.category === modelData ? "#1a1410" : hk.cText
                                font.family: hk.fontName
                                font.pixelSize: 11
                            }
                            MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: hk.category = modelData }
                        }
                    }
                }

                // the list
                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: filtered
                    boundsBehavior: Flickable.StopAtBounds

                    section.property: "cat"
                    section.delegate: Text {
                        required property string section
                        text: "▣ " + section.toUpperCase()
                        color: hk.cAccent
                        font.family: hk.fontName
                        font.pixelSize: 12
                        font.letterSpacing: 1.5
                        topPadding: 12
                        bottomPadding: 4
                    }

                    delegate: Rectangle {
                        id: rowItem
                        required property string keys
                        required property string action
                        required property string clash
                        width: list.width
                        implicitHeight: clash ? 52 : 34
                        radius: 8
                        color: rowMouse.containsMouse ? hk.cHover : "transparent"

                        MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 12

                            // key combos: "A+B / C+D" -> keycaps
                            Row {
                                Layout.preferredWidth: 360
                                spacing: 6
                                Repeater {
                                    model: rowItem.keys.split(" / ")
                                    delegate: Row {
                                        id: combo
                                        required property string modelData
                                        required property int index
                                        spacing: 3
                                        Text {
                                            visible: combo.index > 0
                                            text: "or"
                                            color: hk.cSub
                                            font.family: hk.fontName
                                            font.pixelSize: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Repeater {
                                            model: combo.modelData.split("+")
                                            delegate: Rectangle {
                                                required property string modelData
                                                implicitWidth: capText.implicitWidth + 12
                                                implicitHeight: 22
                                                radius: 6
                                                color: hk.cKey
                                                border.color: hk.cBorder
                                                border.width: 1
                                                Text {
                                                    id: capText
                                                    anchors.centerIn: parent
                                                    text: modelData.trim()
                                                    color: hk.cText
                                                    font.family: hk.fontName
                                                    font.pixelSize: 11
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Column {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    width: parent.width
                                    text: rowItem.action
                                    color: hk.cText
                                    font.family: hk.fontName
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                                // the same key is bound to something else too
                                Text {
                                    visible: rowItem.clash !== ""
                                    width: parent.width
                                    text: "⚠ clash: " + rowItem.clash
                                    color: hk.cWarn
                                    font.family: hk.fontName
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: filtered.count === 0
                        text: hk.errorText || (hk.loading && hk.allBinds.length === 0 ? "Reading your config…" : "No matching hotkeys")
                        color: hk.cSub
                        font.family: hk.fontName
                        font.pixelSize: 13
                    }
                }
            }
        }
    }
}
