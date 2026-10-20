import QtQuick

// The words of the test, wrapped into lines, three of which show at a time.
// The line being typed stays on the second and the lines above scroll away.
Item {
    id: view

    property var wordsModel
    property int currentIndex: 0
    property string fontFamily: "IBM Plex Mono"
    property int pixelSize: 26
    property color textColor: "#eeeeee"
    property color mutedColor: "#909191"
    property color errorColor: "#ca4754"
    property color accentColor: "#5584aa"
    // The caret holds still while typing and blinks while it waits.
    property bool running: false

    readonly property real lineHeight: Math.round(pixelSize * 1.9)
    readonly property real spaceWidth: metrics.advanceWidth(" ")
    property real scrollOffset: 0
    property bool animateScroll: true

    height: lineHeight * 3
    clip: true

    FontMetrics {
        id: metrics
        font.family: view.fontFamily
        font.pixelSize: view.pixelSize
        font.kerning: false
    }

    // Back to the first line, without sliding there.
    function reset() {
        animateScroll = false;
        scrollOffset = 0;
        caret.visible = false;
        Qt.callLater(function() {
            view.animateScroll = true;
            view.sync();
        });
    }

    // Puts the caret after the typed letters of the current word and scrolls
    // that word's line to where it belongs.
    function sync() {
        var item = repeater.itemAt(currentIndex);
        if (!item)
            return;

        var typedLength = item.typed.length;
        var word = item.word;
        var shown = word.substring(0, Math.min(typedLength, word.length));
        if (typedLength > word.length)
            shown += item.typed.substring(word.length);

        caret.x = item.x + metrics.advanceWidth(shown);
        caret.y = item.y + (lineHeight - caret.height) / 2;
        caret.visible = true;

        if (item.y >= scrollOffset + lineHeight * 2 - 0.5)
            scrollOffset = item.y - lineHeight;
        else if (item.y < scrollOffset)
            scrollOffset = item.y;
    }

    onCurrentIndexChanged: sync()

    Item {
        id: content
        width: parent.width
        height: flow.height
        y: -view.scrollOffset

        Behavior on y {
            enabled: view.animateScroll
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Flow {
            id: flow
            width: parent.width

            Repeater {
                id: repeater
                model: view.wordsModel

                delegate: Item {
                    id: wordItem

                    required property int index
                    required property string word
                    required property string typed

                    readonly property bool committed: index < view.currentIndex
                    readonly property bool wrong: committed && typed !== word

                    // The word's own space is part of its width, so the Flow
                    // needs no spacing of its own, which it would apply to
                    // the lines as well.
                    width: lettersRow.width + view.spaceWidth
                    height: view.lineHeight

                    function refresh() {
                        if (index === view.currentIndex)
                            view.sync();
                    }

                    onTypedChanged: refresh()
                    onXChanged: refresh()
                    onYChanged: refresh()

                    Row {
                        id: lettersRow
                        height: parent.height

                        Repeater {
                            model: Math.max(wordItem.word.length, wordItem.typed.length)

                            delegate: Text {
                                required property int index

                                readonly property bool extra: index >= wordItem.word.length
                                readonly property bool entered: index < wordItem.typed.length

                                height: lettersRow.height
                                verticalAlignment: Text.AlignVCenter
                                text: extra ? wordItem.typed.charAt(index)
                                            : wordItem.word.charAt(index)
                                font.family: view.fontFamily
                                font.pixelSize: view.pixelSize
                                font.kerning: false
                                color: extra
                                    ? view.errorColor
                                    : !entered
                                        ? view.mutedColor
                                        : wordItem.typed.charAt(index) === wordItem.word.charAt(index)
                                            ? view.textColor
                                            : view.errorColor
                                opacity: extra ? 0.7 : 1
                            }
                        }
                    }

                    // A word left behind with a mistake in it.
                    Rectangle {
                        visible: wordItem.wrong
                        x: 0
                        y: parent.height / 2 + view.pixelSize * 0.62
                        width: lettersRow.width
                        height: Math.max(1, Math.round(view.pixelSize / 13))
                        color: view.errorColor
                    }
                }
            }
        }

        Rectangle {
            id: caret
            width: Math.max(2, Math.round(view.pixelSize / 11))
            height: Math.round(view.pixelSize * 1.2)
            radius: 0
            color: view.accentColor
            visible: false

            Behavior on x {
                enabled: view.animateScroll
                NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
            }
            Behavior on y {
                enabled: view.animateScroll
                NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
            }

            SequentialAnimation on opacity {
                running: !view.running
                loops: Animation.Infinite
                NumberAnimation { to: 0.15; duration: 520 }
                NumberAnimation { to: 1; duration: 520 }
                onRunningChanged: if (!running) caret.opacity = 1
            }
        }
    }
}
