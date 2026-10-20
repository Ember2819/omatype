import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Window
import "TypingEngine.js" as Engine

ApplicationWindow {
    id: win
    width: 1280
    height: 820
    minimumWidth: 720
    minimumHeight: 520
    visible: true
    title: "Omatype"

    readonly property bool darkMode: backend.darkMode
    readonly property color pageColor: backend.themeBackground
    readonly property color textColor: backend.themeForeground
    readonly property color mutedColor: backend.themeMuted
    readonly property color errorColor: backend.themeError
    readonly property color accentColor: backend.themeAccent
    // The desktop's text size knob (GNOME's text-scaling-factor, which
    // `omarchy display text size` drives) anchored so its 12px default leaves
    // the app at the sizes it was designed around, times the user's own
    // text size set with Ctrl+= / Ctrl+- / Ctrl+wheel.
    readonly property real textScale: backend.textScale
    readonly property int testFontPixelSize: scaledSize(26)
    readonly property int footerHeight: scaledSize(32)
    // Never wider than the window, whatever the floor asks for: a tiling
    // compositor can resize the window below its minimum width.
    readonly property int testWidth: Math.max(0, Math.min(
        Math.round(testMetrics.averageCharacterWidth * 62), width - 48))

    // What is being tested.
    property string mode: "time"
    property int timeAmount: 30
    property int wordAmount: 25
    property bool punctuation: false
    property bool numbers: false
    readonly property var timeAmounts: [15, 30, 60, 120]
    readonly property var wordAmounts: [10, 25, 50, 100]
    readonly property var amounts: mode === "time" ? timeAmounts : wordAmounts
    readonly property int amount: mode === "time" ? timeAmount : wordAmount
    readonly property string description: mode + " " + amount
        + (punctuation ? " · punctuation" : "") + (numbers ? " · numbers" : "")

    // "idle" waits for the first key, "running" is the test itself, and
    // "finished" shows the results.
    property string phase: "idle"
    property var test: null
    property var generator: null
    property real startMs: 0
    property real elapsed: 0
    property int lastSampled: 0
    // The engine state is a plain object, so this counts its changes for the
    // bindings that read it.
    property int revision: 0
    property real liveWpm: 0
    property real liveAccuracy: 100
    property var result: ({})
    property bool personalBest: false
    property real previousBest: 0
    property bool recorded: true
    property real zoomNotches: 0

    readonly property string counterText: {
        var tick = win.revision + win.elapsed;
        if (win.phase !== "running" || !win.test)
            return "";
        if (win.mode === "time")
            return String(Math.max(0, Math.ceil(win.amount - win.elapsed)));
        return win.test.index + " / " + win.amount;
    }

    Material.theme: darkMode ? Material.Dark : Material.Light
    Material.accent: backend.themeAccent
    color: pageColor

    // Every hardcoded size in the interface is expressed at text scale 1.
    function scaledSize(pixels) {
        return Math.max(1, Math.round(pixels * win.textScale));
    }

    function toggleFullScreen() {
        win.visibility = win.visibility === Window.FullScreen
            ? Window.Windowed
            : Window.FullScreen;
    }

    function focusTyping() {
        typingInput.forceActiveFocus();
    }

    function flag(value, fallback) {
        return value === undefined ? fallback : String(value) === "true";
    }

    function loadSettings() {
        var savedMode = String(backend.setting("mode", "time"));
        mode = savedMode === "words" ? "words" : "time";
        var savedTime = parseInt(backend.setting("timeAmount", 30));
        timeAmount = timeAmounts.indexOf(savedTime) >= 0 ? savedTime : 30;
        var savedWords = parseInt(backend.setting("wordAmount", 25));
        wordAmount = wordAmounts.indexOf(savedWords) >= 0 ? savedWords : 25;
        punctuation = flag(backend.setting("punctuation", false), false);
        numbers = flag(backend.setting("numbers", false), false);
    }

    function setMode(newMode) {
        if (mode === newMode)
            return;
        mode = newMode;
        backend.setSetting("mode", newMode);
        newTest(false);
    }

    function setAmount(value) {
        if (value === amount)
            return;
        if (mode === "time") {
            timeAmount = value;
            backend.setSetting("timeAmount", value);
        } else {
            wordAmount = value;
            backend.setSetting("wordAmount", value);
        }
        newTest(false);
    }

    function togglePunctuation() {
        punctuation = !punctuation;
        backend.setSetting("punctuation", punctuation);
        newTest(false);
    }

    function toggleNumbers() {
        numbers = !numbers;
        backend.setSetting("numbers", numbers);
        newTest(false);
    }

    // A fresh test, or the same words again after a run.
    function newTest(sameWords) {
        var words = [];
        if (sameWords && test) {
            // Back to the words the test began with, which is a hand of 60 in
            // a time test even after it grew while it ran.
            words = test.words.slice(0, mode === "time" ? Math.max(60, test.index + 1) : amount);
        } else {
            generator = Engine.createGenerator({ punctuation: punctuation, numbers: numbers });
            var count = mode === "time" ? 60 : amount;
            for (var i = 0; i < count; ++i)
                words.push(generator());
        }

        test = Engine.createState(words);
        wordsListModel.clear();
        for (var j = 0; j < words.length; ++j)
            wordsListModel.append({ word: words[j], typed: "" });

        phase = "idle";
        elapsed = 0;
        lastSampled = 0;
        liveWpm = 0;
        liveAccuracy = 100;
        revision += 1;
        wordsView.currentIndex = 0;
        wordsView.reset();
        focusTyping();
    }

    function extendWords(count) {
        var more = [];
        for (var i = 0; i < count; ++i)
            more.push(generator());
        Engine.appendWords(test, more);
        for (var j = 0; j < more.length; ++j)
            wordsListModel.append({ word: more[j], typed: "" });
    }

    function begin() {
        if (phase !== "idle")
            return;
        startMs = Date.now();
        phase = "running";
    }

    function updateLive() {
        var seconds = Math.max(elapsed, 1);
        liveWpm = Engine.wpm(test, seconds);
        liveAccuracy = Engine.accuracy(test);
    }

    function tick() {
        elapsed = (Date.now() - startMs) / 1000;
        if (mode === "time" && elapsed >= amount) {
            elapsed = amount;
            finishTest(amount);
            return;
        }

        var whole = Math.floor(elapsed);
        while (lastSampled < whole) {
            lastSampled += 1;
            Engine.sample(test, lastSampled);
        }
        updateLive();
    }

    function finishTest(seconds) {
        if (phase === "finished")
            return;
        var took = seconds !== undefined ? seconds : (Date.now() - startMs) / 1000;
        phase = "finished";
        elapsed = took;

        var outcome = Engine.result(test, Math.max(took, 0.1));
        result = outcome;

        recorded = outcome.correct > 0;
        personalBest = false;
        previousBest = 0;
        if (recorded) {
            var info = backend.recordResult({
                mode: mode,
                amount: amount,
                punctuation: punctuation,
                numbers: numbers,
                wpm: outcome.wpm,
                raw: outcome.raw,
                accuracy: outcome.accuracy,
                consistency: outcome.consistency,
                seconds: outcome.seconds,
                correct: outcome.correct,
                incorrect: outcome.incorrect,
                extra: outcome.extra,
                missed: outcome.missed
            });
            personalBest = info.personalBest;
            previousBest = info.previousBest;
        }
        focusTyping();
    }

    // Brings the screen up to date with what the engine just did.
    function afterAction() {
        wordsListModel.setProperty(test.index, "typed", test.typed[test.index]);
        wordsView.currentIndex = test.index;
        if (mode === "time" && test.words.length - test.index < 40)
            extendWords(40);
        revision += 1;
        if (phase === "running")
            updateLive();
        if (test.finished)
            finishTest();
    }

    // Returns whether the key was used, so the rest can reach the shortcuts.
    function handleKey(event) {
        var ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        var alt = (event.modifiers & Qt.AltModifier) !== 0;
        var meta = (event.modifiers & Qt.MetaModifier) !== 0;

        if (phase === "finished") {
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab
                    || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                newTest(false);
                return true;
            }
            if (event.key === Qt.Key_R && !ctrl && !alt && !meta) {
                newTest(true);
                return true;
            }
            return false;
        }

        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab
                || event.key === Qt.Key_Escape) {
            newTest(false);
            return true;
        }

        if (event.key === Qt.Key_Backspace) {
            var changed = ctrl ? Engine.deleteWord(test) : Engine.backspace(test);
            if (changed)
                afterAction();
            return true;
        }

        // AltGr arrives as Ctrl+Alt on some layouts and types a letter.
        var typing = !(ctrl || alt || meta) || (ctrl && alt);
        if (!typing)
            return false;

        var endOnLast = mode === "words";
        if (event.key === Qt.Key_Space) {
            if (Engine.space(test, endOnLast)) {
                begin();
                afterAction();
            }
            return true;
        }

        if (event.text.length === 1 && event.text >= " ") {
            if (Engine.typeChar(test, event.text, endOnLast)) {
                begin();
                afterAction();
            }
            return true;
        }
        return false;
    }

    function openHistory() {
        historyDialog.results = backend.recentResults(60);
        historyDialog.summary = backend.historySummary();
        historyDialog.open();
    }

    ListModel { id: wordsListModel }

    FontMetrics {
        id: testMetrics
        font.family: backend.testFont
        font.pixelSize: win.testFontPixelSize
    }

    Timer {
        interval: 100
        repeat: true
        running: win.phase === "running"
        onTriggered: win.tick()
    }

    Shortcut {
        sequences: ["Ctrl+?", "Ctrl+/", "F1"]
        onActivated: shortcutsDialog.open()
    }

    Shortcut {
        // Ctrl++ is a different shortcut to Qt, not a shifted Ctrl+=, and it is
        // the only one a layout that puts + on its own key can reach.
        sequences: ["Ctrl+=", "Ctrl++"]
        onActivated: backend.increaseTextSize()
    }

    Shortcut {
        sequence: "Ctrl+-"
        onActivated: backend.decreaseTextSize()
    }

    Shortcut {
        sequence: "Ctrl+0"
        onActivated: backend.resetTextSize()
    }

    Shortcut {
        sequence: "Ctrl+N"
        onActivated: backend.newWindow()
    }

    Shortcut {
        sequence: "Ctrl+H"
        onActivated: win.openHistory()
    }

    Shortcut {
        sequences: ["Meta+F", "F11"]
        onActivated: win.toggleFullScreen()
    }

    Shortcut {
        sequence: "Alt+T"
        onActivated: win.setMode(win.mode === "time" ? "words" : "time")
    }

    Shortcut {
        sequence: "Alt+P"
        onActivated: win.togglePunctuation()
    }

    Shortcut {
        sequence: "Alt+N"
        onActivated: win.toggleNumbers()
    }

    Repeater {
        model: 4
        delegate: Item {
            required property int index
            Shortcut {
                sequence: "Alt+" + (index + 1)
                onActivated: win.setAmount(win.amounts[index])
            }
        }
    }

    Item {
        id: stage
        anchors.fill: parent

        // Every key of the test lands here.
        Item {
            id: typingInput
            objectName: "typingInput"
            anchors.fill: parent
            focus: true
            Keys.onPressed: function(event) { event.accepted = win.handleKey(event); }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onClicked: win.focusTyping()
        }

        WheelHandler {
            // Ctrl+wheel changes the text size, as it does in a browser. A
            // wheel notch is a whole step, but a touchpad trickles in pixels,
            // so bank the fractions and step once a whole one is scrolled.
            acceptedModifiers: Qt.ControlModifier
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function(wheel) {
                win.zoomNotches += wheel.angleDelta.y / 120;
                while (win.zoomNotches >= 1) {
                    backend.increaseTextSize();
                    win.zoomNotches -= 1;
                }
                while (win.zoomNotches <= -1) {
                    backend.decreaseTextSize();
                    win.zoomNotches += 1;
                }
                wheel.accepted = true;
            }
        }

        // The settings of the test. They step out of the way once typing starts.
        Rectangle {
            id: configBar
            objectName: "configBar"
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(win.scaledSize(24), Math.round(win.height * 0.07))
            width: configRow.width + win.scaledSize(16)
            height: configRow.implicitHeight + win.scaledSize(8)
            color: backend.themePanel
            border.color: Qt.alpha(win.mutedColor, 0.3)
            border.width: 1
            radius: 0
            opacity: win.phase === "running" ? 0 : 1
            enabled: win.phase !== "running"
            visible: opacity > 0

            Behavior on opacity { NumberAnimation { duration: 160 } }

            Row {
                id: configRow
                anchors.centerIn: parent
                spacing: win.scaledSize(2)

                ConfigButton {
                    objectName: "punctuationButton"
                    text: "@ punctuation"
                    active: win.punctuation
                    activeColor: win.accentColor
                    idleColor: win.mutedColor
                    hoverColor: win.textColor
                    pixelSize: win.scaledSize(13)
                    onClicked: win.togglePunctuation()
                }

                ConfigButton {
                    objectName: "numbersButton"
                    text: "# numbers"
                    active: win.numbers
                    activeColor: win.accentColor
                    idleColor: win.mutedColor
                    hoverColor: win.textColor
                    pixelSize: win.scaledSize(13)
                    onClicked: win.toggleNumbers()
                }

                Rectangle {
                    width: 2
                    height: win.scaledSize(18)
                    anchors.verticalCenter: parent.verticalCenter
                    color: win.mutedColor
                    opacity: 0.35
                }

                ConfigButton {
                    objectName: "timeModeButton"
                    text: "time"
                    active: win.mode === "time"
                    activeColor: win.accentColor
                    idleColor: win.mutedColor
                    hoverColor: win.textColor
                    pixelSize: win.scaledSize(13)
                    onClicked: win.setMode("time")
                }

                ConfigButton {
                    objectName: "wordsModeButton"
                    text: "words"
                    active: win.mode === "words"
                    activeColor: win.accentColor
                    idleColor: win.mutedColor
                    hoverColor: win.textColor
                    pixelSize: win.scaledSize(13)
                    onClicked: win.setMode("words")
                }

                Rectangle {
                    width: 2
                    height: win.scaledSize(18)
                    anchors.verticalCenter: parent.verticalCenter
                    color: win.mutedColor
                    opacity: 0.35
                }

                Repeater {
                    model: win.amounts

                    delegate: ConfigButton {
                        required property int modelData
                        objectName: "amountButton" + modelData
                        text: String(modelData)
                        active: win.amount === modelData
                        activeColor: win.accentColor
                        idleColor: win.mutedColor
                        hoverColor: win.textColor
                        pixelSize: win.scaledSize(13)
                        onClicked: win.setAmount(modelData)
                    }
                }
            }
        }

        // The test itself.
        Item {
            id: testArea
            objectName: "testArea"
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(configBar.y + configBar.height + win.scaledSize(48),
                        Math.round(win.height * 0.3))
            width: win.testWidth
            height: counter.height + wordsView.height + restartHint.height + win.scaledSize(40)
            visible: win.phase !== "finished"

            Label {
                id: counter
                objectName: "counter"
                anchors.left: parent.left
                anchors.top: parent.top
                height: win.scaledSize(44)
                verticalAlignment: Text.AlignVCenter
                text: win.counterText
                color: win.accentColor
                font.family: backend.testFont
                font.pixelSize: win.scaledSize(30)
            }

            WordsView {
                id: wordsView
                objectName: "wordsView"
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: counter.bottom
                wordsModel: wordsListModel
                fontFamily: backend.testFont
                pixelSize: win.testFontPixelSize
                textColor: win.textColor
                mutedColor: win.mutedColor
                errorColor: win.errorColor
                accentColor: win.accentColor
                running: win.phase === "running"
            }

            Label {
                id: restartHint
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: wordsView.bottom
                anchors.topMargin: win.scaledSize(40)
                text: "tab  restart test"
                color: win.mutedColor
                font.family: "IBM Plex Mono"
                font.pixelSize: win.scaledSize(12)
                opacity: win.phase === "idle" ? 0.8 : 0

                Behavior on opacity { NumberAnimation { duration: 160 } }
            }
        }

        ResultsView {
            id: resultsView
            objectName: "resultsView"
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(win.scaledSize(24) + configBar.height + win.scaledSize(24),
                        Math.round((win.height - implicitHeight) * 0.35))
            width: Math.min(win.width - 48, Math.max(win.testWidth, win.scaledSize(900)))
            visible: win.phase === "finished"
            result: win.result
            description: win.description
            personalBest: win.personalBest
            previousBest: win.previousBest
            recorded: win.recorded
            fontFamily: backend.testFont
            textScale: win.textScale
            textColor: win.textColor
            mutedColor: win.mutedColor
            accentColor: win.accentColor
            errorColor: win.errorColor
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: win.scaledSize(48)
            visible: win.phase === "finished"
            text: "tab / enter  next test      r  repeat these words"
            color: win.mutedColor
            opacity: 0.8
            font.family: "IBM Plex Mono"
            font.pixelSize: win.scaledSize(12)
        }

        Row {
            id: footerStatus
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.leftMargin: 12
            anchors.bottomMargin: 10
            spacing: 12
            opacity: win.phase === "running" ? 0.15 : 0.55

            Behavior on opacity { NumberAnimation { duration: 160 } }

            FooterIconButton {
                objectName: "restartButton"
                iconName: "restart"
                iconColor: win.mutedColor
                tooltip: "Restart"
                onClicked: win.newTest(false)
            }

            FooterIconButton {
                objectName: "historyButton"
                iconName: "history"
                iconColor: win.mutedColor
                tooltip: "History"
                onClicked: win.openHistory()
            }

            FooterIconButton {
                id: fontButton
                objectName: "fontButton"
                iconName: "font"
                iconColor: win.mutedColor
                tooltip: "Font"
                onClicked: fontPicker.opened ? fontPicker.close() : fontPicker.open()
            }

            Label {
                text: backend.status
                color: win.mutedColor
                font.family: "IBM Plex Mono"
                font.pixelSize: win.scaledSize(11)
                visible: text !== ""
                elide: Text.ElideRight
                width: Math.min(360, win.width / 3)
                height: win.scaledSize(16)
                verticalAlignment: Text.AlignVCenter
            }
        }

        FontPicker {
            id: fontPicker
            objectName: "fontPicker"
            // Parented to its button, so a press on the button is not a press
            // outside that closes it only for the click to open it again.
            parent: fontButton
            x: -8
            y: -height - 10
            width: win.scaledSize(320)
            maximumHeight: Math.min(win.scaledSize(440), win.height - 80)
            fonts: backend.availableFonts
            currentFont: backend.testFont
            defaultFont: "IBM Plex Mono"
            darkMode: win.darkMode
            textScale: win.textScale
            textColor: win.textColor
            mutedColor: win.mutedColor
            highlightColor: backend.themeAccent
            onFontChosen: function(family) { backend.testFont = family; }
            onClosed: win.focusTyping()
        }

        // What the test is while it waits, and how it is going while it runs.
        Label {
            objectName: "statusLabel"
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 12
            anchors.bottomMargin: 10
            text: win.phase === "running"
                ? Math.round(win.liveWpm) + " wpm  " + Math.round(win.liveAccuracy) + "%"
                : win.description
            color: win.mutedColor
            opacity: 0.75
            font.family: "IBM Plex Mono"
            font.pixelSize: win.scaledSize(11)
        }
    }

    ShortcutsDialog {
        id: shortcutsDialog
        darkMode: win.darkMode
        textScale: win.textScale
        textColor: win.textColor
        activeButtonColor: backend.themeAccent
        containerWidth: win.width
        containerHeight: win.height
        onClosed: win.focusTyping()
    }

    HistoryDialog {
        id: historyDialog
        darkMode: win.darkMode
        textScale: win.textScale
        textColor: win.textColor
        mutedColor: win.mutedColor
        activeButtonColor: backend.themeAccent
        containerWidth: win.width
        containerHeight: win.height
        onClearRequested: {
            backend.clearHistory();
            results = [];
            summary = backend.historySummary();
        }
        onClosed: win.focusTyping()
    }

    Component.onCompleted: {
        var geometry = backend.windowGeometry();
        if (geometry.x >= 0) x = geometry.x;
        if (geometry.y >= 0) y = geometry.y;
        width = geometry.width;
        height = geometry.height;
        if (geometry.maximized) showMaximized();

        loadSettings();
        newTest(false);
    }

    Component.onDestruction: backend.saveWindowGeometry(x, y, width, height, visibility === Window.Maximized)
}
