import QtQuick
import QtQuick.Controls

// A word in the test settings bar: muted until hovered, accent when chosen.
Item {
    id: control

    property string text
    property bool active: false
    property color activeColor: "#5584aa"
    property color idleColor: "#909191"
    property color hoverColor: "#eeeeee"
    property string fontFamily: "IBM Plex Mono"
    property int pixelSize: 13

    signal clicked()

    implicitWidth: label.implicitWidth + 20
    implicitHeight: label.implicitHeight + 14
    width: implicitWidth
    height: implicitHeight

    Label {
        id: label
        anchors.centerIn: parent
        text: control.text
        font.family: control.fontFamily
        font.pixelSize: control.pixelSize
        color: control.active
            ? control.activeColor
            : hitArea.containsMouse ? control.hoverColor : control.idleColor
    }

    MouseArea {
        id: hitArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: control.clicked()
    }
}
