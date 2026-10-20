import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

// What the test came to: speed and accuracy large on the left, the speed
// through the test on the right, and the details of it underneath.
Item {
    id: root

    property var result: ({})
    property string description
    property bool personalBest: false
    property real previousBest: 0
    property bool recorded: true
    property string fontFamily: "IBM Plex Mono"
    property real textScale: 1
    property color textColor: "#eeeeee"
    property color mutedColor: "#909191"
    property color accentColor: "#5584aa"
    property color errorColor: "#ca4754"

    implicitHeight: layout.implicitHeight

    function s(pixels) {
        return Math.max(1, Math.round(pixels * textScale));
    }

    function fmt(value, digits) {
        return value === undefined || value === null || isNaN(value) ? "-" : Number(value).toFixed(digits);
    }

    readonly property var stats: [
        { label: "test", value: description },
        { label: "raw", value: fmt(result.raw, 0) },
        { label: "characters", value: (result.correct || 0) + " / " + (result.incorrect || 0)
                                      + " / " + (result.extra || 0) + " / " + (result.missed || 0),
          tip: "correct / incorrect / extra / missed" },
        { label: "consistency", value: fmt(result.consistency, 0) + "%" },
        { label: "time", value: fmt(result.seconds, result.seconds < 10 ? 1 : 0) + "s" }
    ]

    readonly property string bestText: !recorded
        ? "nothing was typed right, so this result was not saved"
        : personalBest
            ? "new personal best!"
            : previousBest > 0
                ? "personal best " + Math.round(previousBest) + " wpm"
                : "first result for this test"

    function drawGraph(canvas, w, h) {
        var ctx = canvas.getContext("2d");
        ctx.setTransform(canvas.dpr, 0, 0, canvas.dpr, 0, 0);
        ctx.clearRect(0, 0, w, h);

        var points = result.samples || [];
        if (points.length === 0)
            return;

        var padL = s(40), padR = s(10), padT = s(10), padB = s(26);
        var pw = Math.max(1, w - padL - padR);
        var ph = Math.max(1, h - padT - padB);
        var maxSecond = Math.max(points[points.length - 1].second, 1);
        var maxValue = 0;
        for (var i = 0; i < points.length; ++i)
            maxValue = Math.max(maxValue, points[i].wpm, points[i].raw);
        var step = maxValue > 200 ? 50 : maxValue > 100 ? 25 : maxValue > 50 ? 10 : 5;
        var top = Math.max(step, Math.ceil(maxValue * 1.05 / step) * step);

        function px(second) { return padL + second / maxSecond * pw; }
        function py(value) { return padT + ph - value / top * ph; }

        var muted = String(mutedColor);
        var accent = String(accentColor);
        var error = String(errorColor);

        ctx.font = s(11) + "px '" + fontFamily + "'";
        ctx.fillStyle = muted;
        ctx.strokeStyle = muted;
        ctx.lineWidth = 1;
        ctx.textAlign = "right";
        ctx.textBaseline = "middle";
        for (var v = 0; v <= top; v += step) {
            ctx.globalAlpha = 0.18;
            ctx.beginPath();
            ctx.moveTo(padL, Math.round(py(v)) + 0.5);
            ctx.lineTo(padL + pw, Math.round(py(v)) + 0.5);
            ctx.stroke();
            ctx.globalAlpha = 0.9;
            ctx.fillText(String(v), padL - s(8), py(v));
        }

        ctx.textAlign = "center";
        ctx.textBaseline = "top";
        var tick = Math.max(1, Math.ceil(maxSecond / 8));
        for (var sec = tick; sec <= maxSecond + 0.001; sec += tick)
            ctx.fillText(String(Math.round(sec)), px(sec), padT + ph + s(8));

        function line(key, color, width, alpha) {
            ctx.globalAlpha = alpha;
            ctx.strokeStyle = color;
            ctx.lineWidth = width;
            ctx.lineJoin = "round";
            ctx.lineCap = "round";
            ctx.beginPath();
            for (var j = 0; j < points.length; ++j) {
                var x = px(points[j].second);
                var y = py(points[j][key]);
                if (j === 0)
                    ctx.moveTo(x, y);
                else
                    ctx.lineTo(x, y);
            }
            ctx.stroke();
            if (points.length <= 40) {
                ctx.fillStyle = color;
                for (var k = 0; k < points.length; ++k) {
                    ctx.beginPath();
                    ctx.arc(px(points[k].second), py(points[k][key]), s(3) * (width / 2), 0, Math.PI * 2);
                    ctx.fill();
                }
            }
        }

        line("raw", muted, s(2), 0.55);
        line("wpm", accent, s(2.5), 1);

        // A cross where a mistake was made.
        ctx.globalAlpha = 1;
        ctx.strokeStyle = error;
        ctx.lineWidth = s(2);
        var arm = s(4);
        for (var m = 0; m < points.length; ++m) {
            if (points[m].errors <= 0)
                continue;
            var cx = px(points[m].second);
            var cy = py(points[m].raw);
            ctx.beginPath();
            ctx.moveTo(cx - arm, cy - arm);
            ctx.lineTo(cx + arm, cy + arm);
            ctx.moveTo(cx + arm, cy - arm);
            ctx.lineTo(cx - arm, cy + arm);
            ctx.stroke();
        }
        ctx.globalAlpha = 1;
    }

    ColumnLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: root.s(28)

        RowLayout {
            Layout.fillWidth: true
            spacing: root.s(32)

            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: root.s(150)
                spacing: 0

                Label {
                    text: "wpm"
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: root.s(16)
                }
                Label {
                    objectName: "wpmValue"
                    text: root.fmt(root.result.wpm, 0)
                    color: root.accentColor
                    font.family: root.fontFamily
                    font.pixelSize: root.s(68)
                }
                Label {
                    Layout.topMargin: root.s(8)
                    text: "acc"
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: root.s(16)
                }
                Label {
                    objectName: "accuracyValue"
                    text: root.fmt(root.result.accuracy, 0) + "%"
                    color: root.accentColor
                    font.family: root.fontFamily
                    font.pixelSize: root.s(68)
                }
            }

            Item {
                id: graphBox
                Layout.fillWidth: true
                Layout.preferredHeight: root.s(240)

                Canvas {
                    id: graph

                    // Draw at the physical size and scale the item back down,
                    // so surface pixels match screen pixels on hidpi screens.
                    readonly property real dpr: Screen.devicePixelRatio
                    width: graphBox.width * dpr
                    height: graphBox.height * dpr
                    transformOrigin: Item.TopLeft
                    scale: 1 / dpr
                    onDprChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: root.drawGraph(graph, graphBox.width, graphBox.height)
                }

                Connections {
                    target: root
                    function onResultChanged() { graph.requestPaint(); }
                    function onTextScaleChanged() { graph.requestPaint(); }
                    function onMutedColorChanged() { graph.requestPaint(); }
                    function onAccentColorChanged() { graph.requestPaint(); }
                    function onErrorColorChanged() { graph.requestPaint(); }
                    function onFontFamilyChanged() { graph.requestPaint(); }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: root.s(36)

            Repeater {
                model: root.stats

                delegate: ColumnLayout {
                    required property var modelData
                    spacing: root.s(2)

                    ToolTip.visible: tipHover.hovered && (modelData.tip || "").length > 0
                    ToolTip.text: modelData.tip || ""

                    Label {
                        text: modelData.label
                        color: root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: root.s(13)
                    }
                    Label {
                        text: modelData.value
                        color: root.textColor
                        font.family: root.fontFamily
                        font.pixelSize: root.s(22)
                    }

                    HoverHandler { id: tipHover }
                }
            }

            Item { Layout.fillWidth: true }
        }

        Label {
            objectName: "bestLabel"
            text: root.bestText
            color: root.personalBest ? root.accentColor : root.mutedColor
            font.family: root.fontFamily
            font.pixelSize: root.s(13)
        }
    }
}
