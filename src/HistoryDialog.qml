import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: root
    objectName: "historyDialog"

    property bool darkMode: true
    property color textColor: darkMode ? "#d0d0d0" : "#42464c"
    property color strongTextColor: darkMode ? "#eeeeee" : "#222324"
    property color mutedColor: "#909191"
    property color activeButtonColor: "#428bca"
    property real textScale: 1
    property int containerWidth: 1280
    property int containerHeight: 820
    property var results: []
    property var summary: ({})

    signal clearRequested()

    function s(pixels) {
        return Math.round(pixels * textScale);
    }

    function describe(entry) {
        var text = entry.mode + " " + entry.amount;
        if (entry.punctuation)
            text += " p";
        if (entry.numbers)
            text += " n";
        return text;
    }

    title: "History"
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    implicitWidth: Math.round(760 * textScale)
    implicitHeight: Math.round(620 * textScale)
    width: Math.max(0, Math.min(implicitWidth, containerWidth - 32))
    height: Math.max(0, Math.min(implicitHeight, containerHeight - 32))
    x: Math.round((containerWidth - width) / 2)
    y: Math.round((containerHeight - height) / 2)
    padding: 24

    onOpened: closeButton.forceActiveFocus()

    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.65) }

    background: Rectangle {
        color: root.darkMode ? "#181818" : "#fbfbfb"
        border.color: root.darkMode ? "#343434" : "#d8d8d8"
        border.width: 1
        radius: 0
    }

    header: ColumnLayout {
        spacing: 6
        Label {
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            Layout.topMargin: 20
            text: root.title
            color: root.strongTextColor
            font.family: "IBM Plex Mono"
            font.pixelSize: Math.round(15 * root.textScale)
            font.bold: true
        }
        Label {
            objectName: "historySummary"
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            Layout.bottomMargin: 8
            text: (root.summary.count || 0) === 0
                ? "No tests yet"
                : root.summary.count + (root.summary.count === 1 ? " test" : " tests")
                  + "  ·  average " + Math.round(root.summary.average) + " wpm"
                  + "  ·  best " + Math.round(root.summary.best) + " wpm"
            color: root.textColor
            opacity: 0.75
            font.family: "IBM Plex Mono"
            font.pixelSize: Math.round(11 * root.textScale)
            wrapMode: Text.Wrap
        }
    }

    contentItem: ColumnLayout {
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            visible: root.results.length > 0

            Repeater {
                model: [
                    { text: "date", width: 150 },
                    { text: "test", width: 130 },
                    { text: "wpm", width: 60 },
                    { text: "raw", width: 60 },
                    { text: "acc", width: 60 },
                    { text: "cons", width: 60 }
                ]
                delegate: Label {
                    required property var modelData
                    Layout.preferredWidth: root.s(modelData.width)
                    text: modelData.text
                    color: root.mutedColor
                    font.family: "IBM Plex Mono"
                    font.pixelSize: root.s(11)
                }
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.results
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: RowLayout {
                required property var modelData
                width: list.width
                height: root.s(26)
                spacing: 10

                Repeater {
                    model: [
                        { text: modelData.date, width: 150, strong: false },
                        { text: root.describe(modelData), width: 130, strong: false },
                        { text: Math.round(modelData.wpm), width: 60, strong: true },
                        { text: Math.round(modelData.raw), width: 60, strong: false },
                        { text: Math.round(modelData.accuracy) + "%", width: 60, strong: false },
                        { text: Math.round(modelData.consistency) + "%", width: 60, strong: false }
                    ]
                    delegate: Label {
                        required property var modelData
                        Layout.preferredWidth: root.s(modelData.width)
                        text: modelData.text
                        color: modelData.strong ? root.strongTextColor : root.textColor
                        font.family: "IBM Plex Mono"
                        font.pixelSize: root.s(12)
                        font.bold: modelData.strong
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    footer: Item {
        implicitHeight: closeButton.implicitHeight + 20

        SquareDialogButton {
            anchors.left: parent.left
            anchors.leftMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            text: "Clear history"
            visible: root.results.length > 0
            darkMode: root.darkMode
            textScale: root.textScale
            activeColor: root.activeButtonColor
            onClicked: root.clearRequested()
        }

        SquareDialogButton {
            id: closeButton
            anchors.right: parent.right
            anchors.rightMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            text: "Close"
            primary: true
            darkMode: root.darkMode
            textScale: root.textScale
            activeColor: root.activeButtonColor
            onClicked: root.close()
        }
    }
}
