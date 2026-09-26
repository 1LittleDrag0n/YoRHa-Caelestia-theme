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
    readonly property bool showPower: true       // the buttons from yorha-dock-buttons.json
    readonly property int  confirmSeconds: 20    // countdown before a power action goes ahead

    // While one of these Caelestia panels is open, the dock and its line get out of the
    // way. "launcher" is the start menu; the full set is listed by
    // `qs -c caelestia ipc call drawers list`: bar osd session launcher dashboard utilities sidebar
    readonly property string hideForDrawers: "launcher session dashboard utilities"

    readonly property string posFilePath: Quickshell.env("HOME") + "/.config/caelestia/yorha-dock-pos.json"
    readonly property string buttonFilePath: Quickshell.env("HOME") + "/.config/caelestia/yorha-dock-buttons.json"
    readonly property string iconFilePath: Quickshell.env("HOME") + "/.config/caelestia/yorha-dock-icons.json"
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
    readonly property color cKeyBar: "#40ffffff"
    readonly property string fontName: "JetBrainsMono Nerd Font"

    // ===== State =====
    property bool open: false
    property var windows: []            // running windows
    property var pins: []               // desktop entry ids pinned to the dock
    property var iconOverrides: ({})    // window class -> icon name or .desktop id, from yorha-dock-icons.json
    property var buttons: []            // extra buttons, from yorha-dock-buttons.json
    property var menuItems: []          // entries of a custom popup menu
    property var kdeDevices: []         // [{id, name}] paired KDE Connect devices
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
    property string confirmKind: ""     // "poweroff" | "reboot" | "" (no dialog)
    property bool   nudge: false        // flipped to force a repaint (see below)
    property int    nudgeTicks: 24      // how many repaints are still owed
    property bool   userHidden: false   // hidden by the hotkey
    property int    confirmLeft: 0      // seconds left on the countdown
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

    // qs -c yorha-dock ipc call dock toggle   (bound to a key in hypr-user.lua)
    IpcHandler {
        target: "dock"
        function hide(): void   { root.userHidden = true;  root.open = false; }
        function show(): void   { root.userHidden = false; root.bumpRegion(); }
        function open_(): void  { root.userHidden = false; root.open = true; }
    }

    // Hyprland only picks up a layer surface's input region when the surface
    // redraws. At login the region is set after the last paint, so the compositor
    // keeps the empty one and the line ignores clicks until the dock is restarted.
    // These forced repaints push the current region through.
    function bumpRegion() {
        root.nudgeTicks = Math.max(root.nudgeTicks, 8);
    }

    Timer {
        interval: 350
        repeat: true
        running: root.nudgeTicks > 0
        onTriggered: {
            root.nudge = !root.nudge;
            root.nudgeTicks--;
        }
    }

    onOpenChanged: bumpRegion()
    onPosXfChanged: bumpRegion()
    onPosYfChanged: bumpRegion()

    function moveBy(dx, dy) {
        root.dragging = true;
        root.posXf = root.clamp((root.lineCenterX + dx) / dockWin.width, 0.06, 0.94);
        root.posYf = root.clamp((root.lineTopY + dy) / dockWin.height, 0.0,
                                (dockWin.height - root.stripHeight) / dockWin.height);
    }

    function savePos() {
        posFile.setText(JSON.stringify({ x: root.posXf, y: root.posYf }));
    }

    // Hidden only when there are windows and every one of them is tiled.
    // Nothing else takes the dock away: if you can see the line, you can click it.
    readonly property bool allTiled: root.floatingOnly
                                     && root.windows.length > 0
                                     && !root.windows.some(w => w.floating || w.minimized)

    readonly property bool available: !root.allTiled && !root.userHidden && !root.shellPanelOpen

    // Everything the dock shows: pinned apps that aren't running, then open windows.
    readonly property var items: {
        const out = [];
        const running = root.windows.map(w => String(w.proc || w.appClass).toLowerCase());
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

    readonly property var powerActions: ({
        "poweroff": { label: "Power off", verb: "power off", icon: "\u23fb", cmd: ["systemctl", "poweroff"] },
        "reboot":   { label: "Restart",   verb: "restart",   icon: "\u21bb", cmd: ["systemctl", "reboot"] }
    })

    // what a button does when clicked
    function runButton(btn, tileX, tileY) {
        if (!btn) return;

        if (btn.power) {
            root.askPower(String(btn.power));
        } else if (btn.menu) {
            root.menuItems = (btn.menu === "kdeconnect") ? root.kdeMenu() : btn.menu;
            root.menuPos   = Qt.point(tileX, tileY);
            root.menuKind  = "custom";
            root.menuWin   = null;
            root.menuEntry = null;
            root.menuKey   = "";
            root.menuOpen  = true;
        } else if (btn.ipc) {
            Quickshell.execDetached(["sh", "-c", "qs -c caelestia ipc call " + btn.ipc]);
        } else if (btn.exec) {
            const CMD = Array.isArray(btn.exec) ? btn.exec : ["sh", "-c", String(btn.exec)];
            Quickshell.execDetached(CMD);
            root.open = false;
        } else if (btn.app) {
            const E = root.lookup(String(btn.app));
            if (E) { E.execute(); root.open = false; }
        }
    }

    function runMenuItem(item) {
        if (!item) return;
        if (item.edit)
            root.editFile(String(item.edit));
        else if (item.ipc)
            Quickshell.execDetached(["sh", "-c", "qs -c caelestia ipc call " + item.ipc]);
        else if (item.exec)
            Quickshell.execDetached(Array.isArray(item.exec) ? item.exec : ["sh", "-c", String(item.exec)]);
        root.menuOpen = false;
        root.open = false;
    }

    // Open a config file in Kate (or whatever can open it)
    function editFile(path) {
        Quickshell.execDetached(["sh", "-c", "kate '" + path + "' 2>/dev/null || xdg-open '" + path + "'"]);
    }

    function settingsMenu() {
        const CFG = Quickshell.env("HOME") + "/.config/caelestia/";
        const QS  = Quickshell.env("HOME") + "/.config/quickshell/";
        return [
            { label: "Dock buttons",        edit: CFG + "yorha-dock-buttons.json" },
            { label: "Desktop buttons",     edit: CFG + "yorha-desk-buttons.json" },
            { label: "Icon fixes",          edit: CFG + "yorha-dock-icons.json" },
            { label: "Hotkey list extras",  edit: CFG + "yorha-hotkeys.json" },
            { label: "── advanced", exec: null },
            { label: "Dock settings",       edit: QS + "yorha-dock/shell.qml" },
            { label: "Desktop widget",      edit: QS + "yorha-desk/shell.qml" },
            { label: "Hyprland config",     edit: CFG + "hypr-user.lua" }
        ];
    }

    // The built-in KDE Connect menu, rebuilt from the paired devices each time
    function kdeMenu() {
        const out = [{ label: "Open KDE Connect", exec: ["kdeconnect-app"] }];
        for (const d of root.kdeDevices) {
            out.push({ label: "── " + d.name, exec: null });
            out.push({ label: "   Ring it",        exec: ["kdeconnect-cli", "-d", d.id, "--ring"] });
            out.push({ label: "   Browse files",   exec: ["dolphin", "kdeconnect://" + d.id] });
            out.push({ label: "   Send clipboard", exec: ["sh", "-c", "kdeconnect-cli -d " + d.id + " --share-text \"$(wl-paste)\""] });
            out.push({ label: "   Send a file…",   exec: ["sh", "-c",
                "f=$(kdialog --getopenfilename \"$HOME\" 2>/dev/null || zenity --file-selection 2>/dev/null); " +
                "[ -n \"$f\" ] && kdeconnect-cli -d " + d.id + " --share \"$f\""] });
        }
        if (root.kdeDevices.length === 0)
            out.push({ label: "No paired devices", exec: null });
        return out;
    }

    function askPower(kind) {
        root.confirmKind = kind;
        root.confirmLeft = root.confirmSeconds;
        root.menuOpen    = false;
        confirmTimer.restart();
    }

    function doPower() {
        const ACTION = root.powerActions[root.confirmKind];
        confirmTimer.stop();
        root.confirmKind = "";
        if (ACTION)
            Quickshell.execDetached(ACTION.cmd);
    }

    function cancelPower() {
        confirmTimer.stop();
        root.confirmKind = "";
    }

    Timer {
        id: confirmTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.confirmLeft--;
            if (root.confirmLeft <= 0)
                root.doPower();
        }
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

    // Exact match against the installed .desktop files: the id, or the
    // StartupWMClass that apps set precisely so window classes can be matched.
    // heuristicLookup guesses by name and picks the wrong app often enough
    // (code-oss, zen, qt apps) that this runs first.
    function exactLookup(name) {
        const n = String(name).toLowerCase().replace(/\.desktop$/, "");
        try {
            const apps = DesktopEntries.applications;
            const list = apps && apps.values !== undefined ? apps.values : apps;
            if (!list) return null;
            for (const e of list) {
                if (!e) continue;
                if (String(e.id).toLowerCase().replace(/\.desktop$/, "") === n)
                    return e;
                if (e.startupClass && String(e.startupClass).toLowerCase() === n)
                    return e;
            }
        } catch (err) { /* older quickshell: fall through to the heuristic */ }
        return null;
    }

    // Window classes come in many shapes (org.kde.dolphin, Zen Browser, code-oss…),
    // so try a few forms before giving up.
    function lookup(name) {
        if (!name) return null;
        const n = String(name);

        // a manual override wins over everything
        const OVERRIDE = root.iconOverrides[n] || root.iconOverrides[n.toLowerCase()];
        if (OVERRIDE) {
            const e = root.exactLookup(OVERRIDE) || DesktopEntries.heuristicLookup(String(OVERRIDE));
            if (e) return e;
        }

        const tries = [n, n.toLowerCase(), n.split(".").pop(), n.split(".").pop().toLowerCase(),
                       n.split(" ")[0], n.split(" ")[0].toLowerCase(), n.replace(/\.desktop$/, "")];

        for (const t of tries) {
            if (!t) continue;
            const e = root.exactLookup(t);
            if (e) return e;
        }
        for (const t of tries) {
            if (!t) continue;
            const e = DesktopEntries.heuristicLookup(t);
            if (e) return e;
        }
        return null;
    }

    function entryFor(win) {
        if (!win)
            return null;
        if (win.proc) {
            const INNER = root.lookup(win.proc);   // btop, not foot
            if (INNER)
                return INNER;
        }
        return root.lookup(win.appClass);
    }

    // What gets stored in the pin file: the app id when we know it, otherwise the class.
    function keyFor(entry, win) {
        if (entry) return String(entry.id);
        if (win && win.proc) return String(win.proc);
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

    readonly property var defaultButtons: [
        { "icon": "󰂚", "label": "Notifications", "ipc": "drawers toggle sidebar" },
        { "icon": "󰄡", "label": "KDE Connect",   "menu": "kdeconnect" },
        { "divider": true },
        { "icon": "󰜉", "label": "Restart",   "power": "reboot" },
        { "icon": "󰐥", "label": "Power off", "power": "poweroff" }
    ]

    // ===== Extra buttons, from yorha-dock-buttons.json =====
    // Each entry is one of:
    //   { "icon": "<glyph>", "label": "…", "exec": ["cmd", "arg"] }
    //   { "app": "firefox.desktop", "label": "…" }          - a permanent app button
    //   { "icon": "…", "label": "…", "ipc": "drawers toggle sidebar" }   - Caelestia
    //   { "icon": "…", "label": "…", "power": "poweroff" | "reboot" }    - asks first
    //   { "icon": "…", "label": "…", "menu": "kdeconnect" }              - built-in menu
    //   { "icon": "…", "label": "…", "menu": [ { "label": "…", "exec": [...] } ] }
    //   { "divider": true }
    FileView {
        id: buttonFile
        path: root.buttonFilePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const v = JSON.parse(text());
                if (Array.isArray(v)) root.buttons = v;
            } catch (e) { root.buttons = root.defaultButtons; }
        }
        onLoadFailed: {
            root.buttons = root.defaultButtons;
            buttonFile.setText(JSON.stringify(root.defaultButtons, null, 2));
        }
    }

    // ===== Manual icon fixes, for windows whose class matches the wrong app =====
    // yorha-dock-icons.json, e.g. { "org.kde.dolphin": "system-file-manager" }
    FileView {
        id: iconFile
        path: root.iconFilePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const v = JSON.parse(text());
                if (v && typeof v === "object") root.iconOverrides = v;
            } catch (e) { /* no overrides */ }
        }
        onLoadFailed: iconFile.setText("{}\n")
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
        // yorha-windows resolves what is really running inside terminal windows
        // (btop in foot shows up as foot otherwise). Falls back to plain hyprctl.
        command: ["sh", "-c",
            "if [ -x \"$HOME/.local/bin/yorha-windows\" ]; then \"$HOME/.local/bin/yorha-windows\"; else " +
            "printf '{\"clients\":'; hyprctl -j clients; printf ',\"active\":'; hyprctl -j activewindow; printf '}'; fi"]

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
                        proc: c.proc || "",          // what is actually running in a terminal window
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

    // ===== Paired KDE Connect devices, for the built-in menu =====
    Process {
        id: kdeReader
        command: ["sh", "-c", "kdeconnect-cli -a --id-name-only 2>/dev/null"]
        function reload() { if (!running) running = true; }
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of this.text.split("\n")) {
                    const t = line.trim();
                    if (!t) continue;
                    const sp = t.indexOf(" ");
                    if (sp > 0)
                        out.push({ id: t.slice(0, sp), name: t.slice(sp + 1) });
                }
                root.kdeDevices = out;
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
            onStreamFinished: {
                let open = false;
                for (const line of this.text.split("\n"))
                    if (line.trim() === "1") open = true;
                root.shellPanelOpen = open;
            }
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

    onAvailableChanged: {
        bumpRegion();
        if (!available) { open = false; menuOpen = false; }
    }

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
            source: {
                const CLS  = tile.isWindow ? String(tile.win.proc || tile.win.appClass) : String(tile.item.key);
                const OVER = root.iconOverrides[CLS] || root.iconOverrides[CLS.toLowerCase()];
                if (OVER && !root.exactLookup(OVER))       // the override names an icon, not an app
                    return Quickshell.iconPath(String(OVER), "application-x-executable");
                if (tile.entry && tile.entry.icon)
                    return Quickshell.iconPath(tile.entry.icon, "application-x-executable");
                return Quickshell.iconPath(CLS.toLowerCase(), "application-x-executable");
            }
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

    // ===== One extra button, described by yorha-dock-buttons.json =====
    component ExtraTile: Item {
        id: xt
        required property var btn

        readonly property var  entry:   xt.btn.app ? root.lookup(String(xt.btn.app)) : null
        readonly property real centerX: xt.x + xt.width / 2 + (xt.parent ? xt.parent.x : 0)

        property real f: root.mag(xt.centerX)
        Behavior on f { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

        implicitWidth: root.iconSize + 14
        implicitHeight: root.iconSize + 14

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: xtHover.hovered ? root.cHover : "transparent"
        }

        // an app button draws its real icon, everything else draws a glyph
        IconImage {
            visible: xt.entry !== null
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 7
            implicitSize: Math.round(root.iconSize * xt.f)
            source: xt.entry && xt.entry.icon ? Quickshell.iconPath(xt.entry.icon, "application-x-executable") : ""
        }

        Text {
            visible: xt.entry === null
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 7
            text: xt.btn.icon ? String(xt.btn.icon) : "?"
            color: xtHover.hovered ? root.cAccent : root.cText
            font.family: root.fontName
            font.pixelSize: Math.round(root.iconSize * 0.66 * xt.f)
        }

        HoverHandler { id: xtHover; cursorShape: Qt.PointingHandCursor }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                const P = xt.mapToItem(dockWin.contentItem, xt.width / 2, 0);
                root.runButton(xt.btn, P.x, P.y);
            }
        }

        Rectangle {          // name on hover
            visible: xtHover.hovered && !root.menuOpen && root.confirmKind === ""
            anchors.bottom: parent.top
            anchors.bottomMargin: Math.round(root.iconSize * (xt.f - 1)) + 8
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: xtLabel.implicitWidth + 16
            implicitHeight: 24
            radius: 8
            color: root.cBgSolid
            border.color: root.cBorder
            border.width: 1
            Text {
                id: xtLabel
                anchors.centerIn: parent
                text: xt.btn.label ? String(xt.btn.label) : (xt.entry ? String(xt.entry.name) : "")
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

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "yorha-dock"
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        // One region for every state, so only its numbers change and never the
        // object itself: swapping the mask object left the compositor with a stale
        // input region, and the dock stopped taking clicks until it was restarted.
        //   not available -> nothing
        //   closed        -> just the line
        //   open          -> the whole surface, so a click anywhere closes it
        mask: clickRegion

        Rectangle {          // 1px, invisible: its colour changes force the repaint
            width: 1
            height: 1
            x: 0
            y: 0
            color: Qt.rgba(0, 0, 0, root.nudge ? 0.004 : 0.003)
        }

        Region {
            id: clickRegion
            readonly property bool wholeScreen: root.open || root.confirmKind !== ""
            x: !root.available ? 0 : (clickRegion.wholeScreen ? 0 : root.lineCenterX - root.stripW / 2)
            y: !root.available ? 0 : (clickRegion.wholeScreen ? 0 : root.lineTopY)
            width: !root.available ? 0 : (clickRegion.wholeScreen ? dockWin.width : root.stripW)
            height: !root.available ? 0 : (clickRegion.wholeScreen ? dockWin.height : root.stripHeight)
        }

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

            // ---------- settings gear, top right ----------
            Item {
                id: gear
                width: 22
                height: 22
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 3
                z: 5

                Text {
                    anchors.centerIn: parent
                    text: "󰒓"
                    color: gearHover.hovered ? root.cAccent : root.cSub
                    opacity: gearHover.hovered ? 1 : 0.65
                    font.family: root.fontName
                    font.pixelSize: 13
                }

                HoverHandler { id: gearHover; cursorShape: Qt.PointingHandCursor }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        const P = gear.mapToItem(dockWin.contentItem, gear.width / 2, 0);
                        root.menuItems = root.settingsMenu();
                        root.menuPos   = Qt.point(P.x, P.y);
                        root.menuKind  = "custom";
                        root.menuWin   = null;
                        root.menuEntry = null;
                        root.menuKey   = "";
                        root.menuOpen  = true;
                    }
                }

                Rectangle {      // label on hover
                    visible: gearHover.hovered && !root.menuOpen
                    anchors.bottom: parent.top
                    anchors.bottomMargin: 4
                    anchors.right: parent.right
                    implicitWidth: gearLabel.implicitWidth + 16
                    implicitHeight: 22
                    radius: 8
                    color: root.cBgSolid
                    border.color: root.cBorder
                    border.width: 1
                    Text {
                        id: gearLabel
                        anchors.centerIn: parent
                        text: "Settings"
                        color: root.cText
                        font.family: root.fontName
                        font.pixelSize: 11
                    }
                }
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

                Rectangle {          // divider before the fixed buttons
                    visible: root.showPower && root.buttons.length > 0
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: root.iconSize - 6
                    Layout.leftMargin: 7
                    Layout.rightMargin: 7
                    Layout.alignment: Qt.AlignVCenter
                    color: root.cBorder
                    opacity: 0.7
                }

                Repeater {
                    model: root.showPower ? root.buttons : []

                    delegate: Item {
                        required property var modelData

                        implicitWidth: modelData.divider ? 15 : extra.implicitWidth
                        implicitHeight: root.iconSize + 14

                        Rectangle {      // a divider the config asked for
                            visible: modelData.divider === true
                            anchors.centerIn: parent
                            width: 1
                            height: root.iconSize - 6
                            color: root.cBorder
                            opacity: 0.7
                        }

                        ExtraTile {
                            id: extra
                            visible: modelData.divider !== true
                            anchors.fill: parent
                            btn: modelData
                        }
                    }
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
            enabled: root.open && root.confirmKind === ""
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: { root.menuOpen = false; root.open = false; root.cursorX = -1; }
            z: -3
        }

        // ---------- power confirmation ----------
        Rectangle {          // dim the screen behind it
            anchors.fill: parent
            visible: root.confirmKind !== ""
            color: "#99000000"
            z: 50

            MouseArea { anchors.fill: parent }   // swallow clicks on the backdrop
        }

        Rectangle {
            id: confirmBox
            visible: root.confirmKind !== ""
            anchors.centerIn: parent
            z: 51

            readonly property var action: root.powerActions[root.confirmKind]

            implicitWidth: 380
            implicitHeight: confirmCol.implicitHeight + 40
            radius: 16
            color: root.cBgSolid
            border.color: root.cBorder
            border.width: 1

            MouseArea { anchors.fill: parent }   // clicks inside do nothing by themselves

            ColumnLayout {
                id: confirmCol
                anchors.centerIn: parent
                width: parent.width - 40
                spacing: 10

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: confirmBox.action ? confirmBox.action.icon : ""
                    color: root.cAccent
                    font.family: root.fontName
                    font.pixelSize: 34
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: confirmBox.action ? confirmBox.action.label.toUpperCase() : ""
                    color: root.cText
                    font.family: root.fontName
                    font.pixelSize: 15
                    font.letterSpacing: 2
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: confirmBox.action
                          ? "The system will " + confirmBox.action.verb + " in " + root.confirmLeft
                            + " second" + (root.confirmLeft === 1 ? "" : "s") + "."
                          : ""
                    color: root.cSub
                    font.family: root.fontName
                    font.pixelSize: 12
                }

                Rectangle {      // countdown bar
                    Layout.fillWidth: true
                    implicitHeight: 4
                    radius: 2
                    color: root.cKeyBar

                    Rectangle {
                        width: parent.width * (root.confirmSeconds > 0 ? root.confirmLeft / root.confirmSeconds : 0)
                        height: parent.height
                        radius: parent.radius
                        color: root.cAccent
                        Behavior on width { NumberAnimation { duration: 900 } }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: 10
                        color: cancelHover.hovered ? root.cHover : "transparent"
                        border.color: root.cBorder
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: root.cText
                            font.family: root.fontName
                            font.pixelSize: 12
                        }
                        HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
                        MouseArea { anchors.fill: parent; onClicked: root.cancelPower() }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: 10
                        color: okHover.hovered ? root.cAccent : "transparent"
                        border.color: root.cAccent
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: confirmBox.action ? confirmBox.action.label + " now" : ""
                            color: okHover.hovered ? "#1a1410" : root.cAccent
                            font.family: root.fontName
                            font.pixelSize: 12
                        }
                        HoverHandler { id: okHover; cursorShape: Qt.PointingHandCursor }
                        MouseArea { anchors.fill: parent; onClicked: root.doPower() }
                    }
                }
            }
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
                    visible: root.menuKind !== "dock" && root.menuKind !== "custom"
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
                    visible: root.menuKind !== "dock" && root.menuKind !== "custom"
                    Layout.fillWidth: true
                    Layout.topMargin: 3
                    Layout.bottomMargin: 3
                    implicitHeight: 1
                    color: root.cBorder
                }
                MenuItem {
                    visible: root.menuKind !== "dock" && root.menuKind !== "custom" && root.menuKey !== ""
                    label: root.isPinned(root.menuKey) ? "Unpin from dock" : "Pin to dock"
                    onPicked: {
                        if (root.isPinned(root.menuKey)) root.unpin(root.menuKey);
                        else root.pin(root.menuKey);
                    }
                }
                MenuItem {
                    visible: root.menuKind !== "dock" && root.menuKind !== "custom" && root.menuEntry !== null
                    label: "Uninstall…"
                    onPicked: root.uninstall(root.menuEntry)
                }
                MenuItem {
                    visible: root.menuKind === "win"
                    label: "Close"
                    command: 'hl.dsp.window.close({ ' + menu.addr + ' })'
                }

                // ---- a menu opened by one of the extra buttons ----
                Repeater {
                    model: root.menuKind === "custom" ? root.menuItems : []
                    delegate: MenuItem {
                        required property var modelData
                        label: String(modelData.label)
                        opacity: modelData.exec || modelData.ipc || modelData.edit ? 1 : 0.55   // headings are not clickable
                        onPicked: root.runMenuItem(modelData)
                    }
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
