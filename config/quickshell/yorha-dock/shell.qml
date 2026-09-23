import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

// YoRHa dock: a line at the bottom of the screen; click it and the dock rises with
// every open window plus the apps you pinned to it.
ShellRoot {
    id: root

    // ===== Settings =====
    readonly property int stripHeight: 26        // height of the clickable strip
    readonly property int lineHeight: 14         // thickness of the line itself
    readonly property int lineWidth: 260         // length of the line
    readonly property int bottomGap: 26          // gap between the line and the screen edge
    readonly property int iconSize: 40
    readonly property real magnify: 1.7          // how much the icon under the cursor grows
    readonly property real magSpread: 1.3        // how wide the "magnifier glass" is
    readonly property bool glass: false          // true = frosted glass look, false = flat YoRHa
    readonly property real glassAlpha: 0.38      // dock background opacity in glass mode
    readonly property int refreshMs: 1500        // how often the window list is re-read
    readonly property int drawerMs: 300          // how often Caelestia's panels are checked
    readonly property bool floatingOnly: true    // dock only exists while a floating window does

    // While one of these Caelestia panels is open, the dock and its line get out of the
    // way. "launcher" is the start menu; the full set is listed by
    // `qs -c caelestia ipc call drawers list`: bar osd session launcher dashboard utilities sidebar
    readonly property string hideForDrawers: "launcher session dashboard utilities"

    readonly property string posFilePath: Quickshell.env("HOME") + "/.config/caelestia/yorha-dock-pos.json"
    readonly property string pinFilePath: Quickshell.env("HOME") + "/.config/caelestia/yorha-dock-pins.json"

    // YoRHa palette
    readonly property color cBgSolid: "#d91a1410"
    readonly property color cBg: root.glass ? Qt.rgba(0.10, 0.08, 0.06, root.glassAlpha) : root.cBgSolid
    readonly property color cEdge: root.glass ? Qt.rgba(0.73, 0.69, 0.55, 0.45) : root.cBorder
    readonly property color cBorder: "#6b5a2e"
    readonly property color cAccent: "#8f7c4a"
    readonly property color cText: "#c4b89c"
    readonly property color cSub: "#8a847c"
    readonly property color cHover: "#406b5a2e"
    readonly property color cLine: "#9c8a5c"
    readonly property string fontName: "JetBrainsMono Nerd Font"

    // ===== State =====
    property bool open: false
    property var windows: []            // running windows
    property var pins: []               // desktop entry ids pinned to the dock
    property string activeAddress: ""
    property string lastJson: ""
    property bool shellPanelOpen: false // Caelestia has something open at the moment
    property string menuKind: ""        // "win" | "app" | "dock" | "" (closed)
    property var menuWin: null
    property var menuEntry: null
    property string menuKey: ""
    property bool menuOpen: false
    property point menuPos: Qt.point(0, 0)
    property real cursorX: -1           // cursor position inside the dock, -1 = outside
    property double lastActionAt: 0

    // Where the line sits, as a fraction of the screen (so it survives resolution changes).
    // -1 means "the default spot", bottom middle.
    property real posXf: 0.5
    property real posYf: -1
    property bool dragging: false

    readonly property real lineCenterX: root.posXf * dockWin.width
    readonly property real lineTopY: root.posYf < 0
        ? dockWin.height - root.bottomGap - root.stripHeight
        : root.posYf * dockWin.height
    readonly property real stripW: root.lineWidth + 40

    function clamp(v, lo, hi) { return Math.max(lo, Math.min(v, hi)); }

    function moveBy(dx, dy) {
        root.dragging = true;
        root.posXf = root.clamp((root.lineCenterX + dx) / dockWin.width, 0.06, 0.94);
        root.posYf = root.clamp((root.lineTopY + dy) / dockWin.height, 0.0,
                                (dockWin.height - root.stripHeight) / dockWin.height);
    }

    function savePos() {
        posFile.setText(JSON.stringify({ x: root.posXf, y: root.posYf }));
    }

    // Hidden when every open window is tiled - but an empty desktop still gets the dock,
    // otherwise there would be no way to launch anything from it after logging in.
    readonly property bool available: (!root.floatingOnly
                                       || root.windows.length === 0
                                       || root.windows.some(w => w.floating || w.minimized)
                                       || root.pins.length > 0)
                                      && !root.shellPanelOpen

    // Everything the dock shows: pinned apps that aren't running, then open windows.
    readonly property var items: {
        const out = [];
        const running = root.windows.map(w => String(w.appClass).toLowerCase());
        for (const key of root.pins) {
            const e = root.lookup(key);
            const idl = String(e ? e.id : key).toLowerCase().replace(".desktop", "");
            if (running.some(c => idl.includes(c) || c.includes(idl)))
                continue;                       // it's running, so a window tile covers it
            out.push({ kind: "app", entry: e, win: null, key: key });
        }
        for (const w of root.windows)
            out.push({ kind: "win", entry: null, win: w, key: "" });
        return out;
    }

    // Magnification like a magnifying glass held over the icons: a smooth bell curve
    // around the cursor, so icons swell and shrink gradually as it moves.
    function mag(centerX) {
        if (!root.open || root.cursorX < 0) return 1;
        const sigma = root.iconSize * root.magSpread;
        const d = root.cursorX - centerX;
        return 1 + (root.magnify - 1) * Math.exp(-(d * d) / (2 * sigma * sigma));
    }

    function dispatch(expr) {
        root.lastActionAt = Date.now();
        Quickshell.execDetached(["hyprctl", "dispatch", expr]);
        reader.reload();
    }

    function activate(w) {
        if (w.minimized) {
            dispatch('hl.dsp.window.move({ window = "address:' + w.address + '", workspace = "e+0", follow = false })');
            dispatch('hl.dsp.focus({ window = "address:' + w.address + '" })');
        } else if (w.address === root.activeAddress) {
            dispatch('hl.dsp.window.move({ window = "address:' + w.address + '", workspace = "special:special", follow = false })');
        } else {
            dispatch('hl.dsp.focus({ window = "address:' + w.address + '" })');
        }
    }

    // Window classes come in many shapes (org.kde.dolphin, Zen Browser, code-oss…),
    // so try a few forms before giving up.
    function lookup(name) {
        if (!name) return null;
        const n = String(name);
        const tries = [n, n.toLowerCase(), n.split(".").pop(), n.split(".").pop().toLowerCase(),
                       n.split(" ")[0], n.split(" ")[0].toLowerCase(), n.replace(/\.desktop$/, "")];
        for (const t of tries) {
            if (!t) continue;
            const e = DesktopEntries.heuristicLookup(t);
            if (e) return e;
        }
        return null;
    }

    function entryFor(win) {
        return win ? root.lookup(win.appClass) : null;
    }

    // What gets stored in the pin file: the app id when we know it, otherwise the class.
    function keyFor(entry, win) {
        if (entry) return String(entry.id);
        return win ? String(win.appClass) : "";
    }

    function isPinned(key) {
        return key ? root.pins.indexOf(key) >= 0 : false;
    }

    function pin(key) {
        if (!key || root.isPinned(key)) return;
        root.pins = root.pins.concat([key]);
        pinFile.setText(JSON.stringify(root.pins));
    }

    function unpin(key) {
        if (!key) return;
        root.pins = root.pins.filter(k => k !== key);
        pinFile.setText(JSON.stringify(root.pins));
    }

    // Best effort: find the package owning the app's .desktop file and remove it, in a
    // terminal so you can see what is happening and type your password.
    function uninstall(entry) {
        if (!entry) return;
        const id = String(entry.id).endsWith(".desktop") ? String(entry.id) : String(entry.id) + ".desktop";
        const script =
            'f=/usr/share/applications/' + id + '; ' +
            'if [ ! -e "$f" ]; then echo "' + id + ' is not a system package, nothing to uninstall."; ' +
            'else p=$(pacman -Qoq "$f" 2>/dev/null); ' +
            'if [ -z "$p" ]; then echo "No package owns $f."; ' +
            'else echo "Package: $p"; sudo pacman -Rns "$p"; fi; fi; ' +
            'echo; printf "Press enter to close…"; read x';
        Quickshell.execDetached(["konsole", "-e", "sh", "-c", script]);
        root.menuOpen = false;
    }

    // ===== Where the dock was left, kept in a small json file =====
    FileView {
        id: posFile
        path: root.posFilePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const v = JSON.parse(text());
                if (typeof v.x === "number") root.posXf = v.x;
                if (typeof v.y === "number") root.posYf = v.y;
            } catch (e) { /* no saved position: use the default */ }
        }
    }

    // ===== Pinned apps, kept in a small json file =====
    FileView {
        id: pinFile
        path: root.pinFilePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const v = JSON.parse(text());
                if (Array.isArray(v)) root.pins = v.map(x => String(x));
            } catch (e) { /* missing or broken file: no pins */ }
        }
    }

    // ===== Reading the window list =====
    Process {
        id: reader
        command: ["sh", "-c",
            "printf '{\"clients\":'; hyprctl -j clients; printf ',\"active\":'; hyprctl -j activewindow; printf '}'"]

        function reload() { if (!running) running = true; }

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = this.text;
                if (raw === root.lastJson || raw.trim() === "")
                    return;
                root.lastJson = raw;
                let data;
                try { data = JSON.parse(raw); } catch (e) { return; }
                const newActive = (data.active && data.active.address) ? data.active.address : "";
                if (newActive !== root.activeAddress && Date.now() - root.lastActionAt > 600) {
                    root.open = false;          // you clicked something else
                    root.menuOpen = false;
                }
                root.activeAddress = newActive;
                const out = [];
                for (const c of data.clients) {
                    if (!c.mapped && !(c.workspace && String(c.workspace.name).startsWith("special")))
                        continue;
                    if (c.title === "" && c.class === "")
                        continue;
                    out.push({
                        address: c.address,
                        appClass: c.class,
                        title: c.title,
                        minimized: String(c.workspace ? c.workspace.name : "").startsWith("special"),
                        floating: !!c.floating,
                        pinned: !!c.pinned
                    });
                }
                root.windows = out;
            }
        }
    }

    // ===== Watching Caelestia's own panels (start menu, session menu…) =====
    Process {
        id: drawerReader
        command: ["sh", "-c",
            "for d in " + root.hideForDrawers + "; do qs -c caelestia ipc call drawers isOpen $d; done"]
        function reload() { if (!running) running = true; }
        stdout: StdioCollector {
            onStreamFinished: root.shellPanelOpen = this.text.indexOf("1") >= 0
        }
    }

    Component.onCompleted: { reader.reload(); drawerReader.reload(); }

    Timer {
        interval: root.refreshMs
        running: true
        repeat: true
        onTriggered: if (!root.menuOpen) reader.reload()
    }

    Timer {
        interval: root.drawerMs
        running: true
        repeat: true
        onTriggered: drawerReader.reload()
    }

    onAvailableChanged: if (!available) { open = false; menuOpen = false; }

    // ===== One tile: either an open window or a pinned app =====
    component DockTile: Item {
        id: tile
        required property var item

        readonly property var win: tile.item.win
        readonly property var entry: tile.item.entry ? tile.item.entry : root.entryFor(tile.item.win)
        readonly property bool isWindow: tile.item.kind === "win"
        readonly property string key: tile.isWindow ? root.keyFor(tile.entry, tile.win) : String(tile.item.key)
        readonly property bool isActive: tile.isWindow && tile.win.address === root.activeAddress

        // centre of this tile in the dock's own coordinates
        readonly property real centerX: tile.x + tile.width / 2 + (tile.parent ? tile.parent.x : 0)

        property real f: root.mag(tile.centerX)
        Behavior on f { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

        implicitWidth: root.iconSize + 14
        implicitHeight: root.iconSize + 14

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: tileHover.hovered ? root.cHover : "transparent"
            border.color: tile.isActive ? root.cAccent : "transparent"
            border.width: 1
        }

        IconImage {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 7
            implicitSize: Math.round(root.iconSize * tile.f)
            opacity: !tile.isWindow ? 0.75 : (tile.win.minimized ? 0.45 : 1.0)
            source: tile.entry && tile.entry.icon
                    ? Quickshell.iconPath(tile.entry.icon, "application-x-executable")
                    : Quickshell.iconPath(tile.isWindow ? String(tile.win.appClass).toLowerCase() : "",
                                          "application-x-executable")
        }

        // ■ focused · ▫ open · ▾ minimized · ˙ pinned app that isn't running
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            text: !tile.isWindow ? "·" : (tile.win.minimized ? "▾" : (tile.isActive ? "■" : "▫"))
            color: tile.isActive ? root.cAccent : root.cSub
            font.family: root.fontName
            font.pixelSize: 8
        }

        // kept-on-top marker
        Text {
            visible: tile.isWindow && tile.win.pinned
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 2
            text: "󰐃"
            color: root.cAccent
            font.family: root.fontName
            font.pixelSize: 10
        }

        HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    const p = tile.mapToItem(dockWin.contentItem, tile.width / 2, 0);
                    root.menuPos = Qt.point(p.x, p.y);
                    root.menuWin = tile.win;
                    root.menuEntry = tile.entry;
                    root.menuKey = tile.key;
                    root.menuKind = tile.isWindow ? "win" : "app";
                    root.menuOpen = true;
                } else if (mouse.button === Qt.MiddleButton) {
                    if (tile.isWindow)
                        root.dispatch('hl.dsp.window.close({ window = "address:' + tile.win.address + '" })');
                } else if (tile.isWindow) {
                    root.activate(tile.win);
                } else if (tile.entry) {
                    tile.entry.execute();
                    root.open = false;
                } else if (tile.key) {
                    Quickshell.execDetached(["sh", "-c", tile.key]);
                    root.open = false;
                }
            }
        }

        // name on hover
        Rectangle {
            visible: tileHover.hovered && !root.menuOpen
            anchors.bottom: parent.top
            anchors.bottomMargin: Math.round(root.iconSize * (tile.f - 1)) + 8
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: titleText.implicitWidth + 16
            implicitHeight: 24
            radius: 8
            color: root.cBgSolid
            border.color: root.cBorder
            border.width: 1
            Text {
                id: titleText
                anchors.centerIn: parent
                text: {
                    const t = tile.isWindow ? String(tile.win.title)
                                            : String(tile.entry ? tile.entry.name : tile.key);
                    return t.length > 60 ? t.slice(0, 60) + "…" : t;
                }
                color: root.cText
                font.family: root.fontName
                font.pixelSize: 11
            }
        }
    }

    // ===== A row in the right-click menu =====
    component MenuItem: Rectangle {
        id: mi
        property string label
        property string command: ""
        signal picked()

        implicitWidth: 240
        implicitHeight: 28
        radius: 6
        color: miHover.hovered ? root.cHover : "transparent"

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 10
            text: mi.label
            color: root.cText
            font.family: root.fontName
            font.pixelSize: 12
        }

        HoverHandler { id: miHover; cursorShape: Qt.PointingHandCursor }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (mi.command !== "")
                    root.dispatch(mi.command);
                root.menuOpen = false;
                mi.picked();
            }
        }
    }

    PanelWindow {
        id: dockWin
        screen: Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "yorha-dock"
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        // Closed: only the line takes clicks, and the screen edge below it stays free so
        // Caelestia's start menu still works. Open: the whole screen, so a click anywhere
        // outside the dock closes it.
        mask: !root.available ? emptyRegion : (root.open ? null : stripRegion)

        Region {
            id: stripRegion
            x: root.lineCenterX - root.stripW / 2
            y: root.lineTopY
            width: root.stripW
            height: root.stripHeight
        }
        Region { id: emptyRegion; x: 0; y: 0; width: 0; height: 0 }

        // ---------- the line ----------
        Item {
            id: strip
            x: root.lineCenterX - root.stripW / 2
            y: root.lineTopY
            width: root.stripW
            height: root.stripHeight
            opacity: (root.open || !root.available) ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 140 } }

            Rectangle {
                anchors.centerIn: parent
                width: root.lineWidth
                height: root.lineHeight
                radius: height / 2
                color: root.cBg
                border.color: root.cEdge
                border.width: 1
                antialiasing: true

                Rectangle {          // glassy sheen on the line
                    visible: root.glass
                    anchors.fill: parent
                    radius: parent.radius
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.18) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.10) }
                    }
                }

                Row {                // one dash per window
                    anchors.centerIn: parent
                    spacing: 5
                    Repeater {
                        model: root.windows
                        delegate: Rectangle {
                            required property var modelData
                            width: modelData.minimized ? 8 : 18
                            height: Math.max(3, root.lineHeight - 8)
                            radius: height / 2
                            color: modelData.address === root.activeAddress ? root.cAccent : root.cLine
                            opacity: modelData.minimized ? 0.5 : 1
                        }
                    }
                }
            }

            HoverHandler { cursorShape: Qt.PointingHandCursor }

            // Click to open the dock, or press and drag to move it somewhere else.
            MouseArea {
                id: lineMouse
                anchors.fill: parent
                enabled: !root.open
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                preventStealing: true
                cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                property real pressX: 0
                property real pressY: 0

                onPressed: mouse => {
                    lineMouse.pressX = mouse.x;
                    lineMouse.pressY = mouse.y;
                    root.dragging = false;
                }
                onPositionChanged: mouse => {
                    const dx = mouse.x - lineMouse.pressX;
                    const dy = mouse.y - lineMouse.pressY;
                    if (!root.dragging && Math.sqrt(dx * dx + dy * dy) < 8)
                        return;
                    root.moveBy(dx, dy);
                }
                onReleased: {
                    if (root.dragging) { root.savePos(); root.dragging = false; }
                    else { root.open = true; reader.reload(); }
                }
            }
        }

        // ---------- the dock ----------
        Rectangle {
            id: bar
            // The dock opens right where the line is, so the pointer is already on it:
            // its bottom edge lands on the bottom of the line.
            x: root.clamp(root.lineCenterX - width / 2, 8, dockWin.width - width - 8)
            y: root.clamp(root.lineTopY + root.stripHeight - height, 8, dockWin.height - height - 8)
            opacity: (root.open && root.available) ? 1 : 0
            scale: (root.open && root.available) ? 1 : 0.92
            transformOrigin: Item.Bottom
            Behavior on opacity { NumberAnimation { duration: 110 } }
            Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

            implicitWidth: tiles.implicitWidth + 20
            implicitHeight: root.iconSize + 22
            radius: 18
            color: root.cBg
            border.color: root.cEdge
            border.width: 1
            visible: opacity > 0
            antialiasing: true

            // glass: a bright top edge fading into a darker bottom
            Rectangle {
                visible: root.glass
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.16) }
                    GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.04) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.12) }
                }
            }

            // a highlight that slides along with the cursor, like light through glass
            Item {
                visible: root.glass
                anchors.fill: parent
                clip: true
                Rectangle {
                    width: 220
                    height: parent.height * 2
                    y: -parent.height / 2
                    x: (root.cursorX < 0 ? -400 : root.cursorX - width / 2)
                    rotation: 12
                    opacity: root.cursorX < 0 ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.13) }
                        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                    }
                }
            }

            // thin bright line along the top edge
            Rectangle {
                visible: root.glass
                anchors.top: parent.top
                anchors.topMargin: 1
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 28
                height: 1
                color: Qt.rgba(1, 1, 1, 0.28)
            }

            // tracks the cursor, for both the magnification and the sheen
            HoverHandler {
                onPointChanged: root.cursorX = point.position.x
                onHoveredChanged: if (!hovered) root.cursorX = -1
            }

            RowLayout {
                id: tiles
                anchors.centerIn: parent
                spacing: 2

                Repeater {
                    model: root.items
                    delegate: DockTile {
                        required property var modelData
                        item: modelData
                    }
                }

                Text {
                    visible: root.items.length === 0
                    text: "NO WINDOWS"
                    color: root.cSub
                    font.family: root.fontName
                    font.pixelSize: 11
                    font.letterSpacing: 1.5
                    Layout.margins: 12
                }
            }

            MouseArea {              // right-click menu, and left-drag to move the dock
                z: -1
                anchors.fill: parent
                anchors.margins: -6
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                preventStealing: true

                property real pressX: 0
                property real pressY: 0

                onPressed: mouse => { pressX = mouse.x; pressY = mouse.y; root.dragging = false; }
                onPositionChanged: mouse => {
                    if (!(pressedButtons & Qt.LeftButton)) return;
                    const dx = mouse.x - pressX;
                    const dy = mouse.y - pressY;
                    if (!root.dragging && Math.sqrt(dx * dx + dy * dy) < 8) return;
                    root.moveBy(dx, dy);
                }
                onReleased: if (root.dragging) { root.savePos(); root.dragging = false; }

                onClicked: mouse => {
                    if (mouse.button !== Qt.RightButton) return;
                    root.menuPos = Qt.point(mouse.x + bar.x, bar.y);
                    root.menuWin = null;
                    root.menuEntry = null;
                    root.menuKind = "dock";
                    root.menuOpen = true;
                }
            }
        }

        // a click anywhere outside the dock closes it
        MouseArea {
            anchors.fill: parent
            enabled: root.open
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: { root.menuOpen = false; root.open = false; root.cursorX = -1; }
            z: -3
        }

        // ---------- right-click menu ----------
        Rectangle {
            id: menu
            visible: root.menuOpen
            x: Math.max(8, Math.min(root.menuPos.x - width / 2, dockWin.width - width - 8))
            y: Math.max(8, root.menuPos.y - height - 10)
            implicitWidth: menuCol.implicitWidth + 12
            implicitHeight: menuCol.implicitHeight + 12
            radius: 12
            color: root.cBgSolid
            border.color: root.cBorder
            border.width: 1

            readonly property var w: root.menuWin
            readonly property string addr: menu.w ? 'window = "address:' + menu.w.address + '"' : ""

            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }   // swallow clicks

            ColumnLayout {
                id: menuCol
                anchors.centerIn: parent
                spacing: 1

                Text {
                    visible: root.menuKind !== "dock"
                    text: {
                        const t = menu.w ? String(menu.w.title)
                                         : (root.menuEntry ? String(root.menuEntry.name) : "");
                        return t.length > 30 ? t.slice(0, 30) + "…" : t;
                    }
                    color: root.cAccent
                    font.family: root.fontName
                    font.pixelSize: 11
                    Layout.leftMargin: 10
                    Layout.bottomMargin: 4
                }

                // ---- an open window ----
                MenuItem {
                    visible: root.menuKind === "win"
                    label: menu.w && menu.w.minimized ? "Restore" : "Minimize"
                    command: menu.w
                        ? (menu.w.minimized
                           ? 'hl.dsp.window.move({ ' + menu.addr + ', workspace = "e+0", follow = false })'
                           : 'hl.dsp.window.move({ ' + menu.addr + ', workspace = "special:special", follow = false })')
                        : ""
                }
                MenuItem {
                    visible: root.menuKind === "win"
                    label: "Maximize / restore"
                    command: 'hl.dsp.window.fullscreen({ mode = "maximized", ' + menu.addr + ' })'
                }
                MenuItem {
                    visible: root.menuKind === "win"
                    label: menu.w && menu.w.floating ? "Tile" : "Float"
                    command: 'hl.dsp.window.float({ ' + menu.addr + ' })'
                }
                MenuItem {
                    visible: root.menuKind === "win"
                    label: menu.w && menu.w.pinned ? "Don't keep on top" : "Keep on top"
                    command: 'hl.dsp.window.pin({ action = "toggle", ' + menu.addr + ' })'
                }
                MenuItem {
                    visible: root.menuKind === "win"
                    label: "Send to next desktop"
                    command: 'hl.dsp.window.move({ ' + menu.addr + ', workspace = "+1", follow = false })'
                }
                MenuItem {
                    visible: root.menuKind === "win" && root.menuEntry !== null
                    label: "New window"
                    onPicked: if (root.menuEntry) root.menuEntry.execute()
                }

                // ---- a pinned app that isn't running ----
                MenuItem {
                    visible: root.menuKind === "app"
                    label: "Open"
                    onPicked: { if (root.menuEntry) root.menuEntry.execute(); root.open = false; }
                }

                // ---- both ----
                Rectangle {
                    visible: root.menuKind !== "dock"
                    Layout.fillWidth: true
                    Layout.topMargin: 3
                    Layout.bottomMargin: 3
                    implicitHeight: 1
                    color: root.cBorder
                }
                MenuItem {
                    visible: root.menuKind !== "dock" && root.menuKey !== ""
                    label: root.isPinned(root.menuKey) ? "Unpin from dock" : "Pin to dock"
                    onPicked: {
                        if (root.isPinned(root.menuKey)) root.unpin(root.menuKey);
                        else root.pin(root.menuKey);
                    }
                }
                MenuItem {
                    visible: root.menuKind !== "dock" && root.menuEntry !== null
                    label: "Uninstall…"
                    onPicked: root.uninstall(root.menuEntry)
                }
                MenuItem {
                    visible: root.menuKind === "win"
                    label: "Close"
                    command: 'hl.dsp.window.close({ ' + menu.addr + ' })'
                }

                // ---- right-click on the dock itself ----
                MenuItem {
                    visible: root.menuKind === "dock"
                    label: "App launcher"
                    command: 'hl.dsp.global("caelestia:launcher")'
                }
                MenuItem {
                    visible: root.menuKind === "dock"
                    label: "Desktop grid"
                    onPicked: Quickshell.execDetached(["hyprctl", "eval", 'hl.plugin.hyprexpo.expo("toggle")'])
                }
                MenuItem {
                    visible: root.menuKind === "dock"
                    label: "Window overview"
                    onPicked: Quickshell.execDetached(["hyprctl", "eval", 'hl.plugin.hymission.toggle("onlycurrentworkspace")'])
                }
                MenuItem {
                    visible: root.menuKind === "dock"
                    label: "Show minimized drawer"
                    command: 'hl.dsp.workspace.toggle_special("special")'
                }
                MenuItem {
                    visible: root.menuKind === "dock"
                    label: "Hotkeys"
                    onPicked: Quickshell.execDetached(["qs", "-c", "yorha-desk", "ipc", "call", "hotkeys", "toggle"])
                }
                MenuItem {
                    visible: root.menuKind === "dock"
                    label: "Lock screen"
                    command: 'hl.dsp.global("caelestia:lock")'
                }
            }
        }
    }
}
