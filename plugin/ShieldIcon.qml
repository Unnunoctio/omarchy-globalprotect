import QtQuick
import QtQuick.Shapes
import qs.Commons

// Shield with a keyhole, the same motif as the app icon. Drawn as a Shape
// rather than loading the SVG because small SVGs render poorly in the bar.
// Everything is defined in a fixed 64x64 space and scaled in one go.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  // Solid shield while the tunnel is up, outline when it is not: the state
  // reads at a glance even without telling the colours apart.
  property bool filled: true
  // What the keyhole is painted with while the shield is filled; the caller
  // passes the background the icon sits on so it reads as cut out.
  property color holeColor: Color.background

  readonly property color keyholeColor: filled ? holeColor : color

  implicitWidth: iconSize * 0.86
  implicitHeight: iconSize
  width: implicitWidth
  height: implicitHeight

  Item {
    width: 64
    height: 64
    anchors.centerIn: parent
    scale: root.height / 64

    Shape {
      anchors.fill: parent
      antialiasing: true
      layer.enabled: true
      layer.samples: 4

      ShapePath {
        fillColor: root.filled ? root.color : "transparent"
        strokeColor: root.color
        strokeWidth: 5
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: "M32 4 L59 14 V33 C59 47 48 57 32 62 C16 57 5 47 5 33 V14 Z" }
      }
    }

    // Lock: shackle arc, body and keyhole.
    Shape {
      x: 22
      y: 21
      width: 20
      height: 12
      antialiasing: true
      layer.enabled: true
      layer.samples: 4

      ShapePath {
        fillColor: "transparent"
        strokeColor: root.keyholeColor
        strokeWidth: 4
        capStyle: ShapePath.RoundCap
        PathSvg { path: "M4 12 V7 A6 6 0 0 1 16 7 V12" }
      }
    }

    Rectangle {
      x: 20
      y: 31
      width: 24
      height: 17
      radius: 3
      color: root.keyholeColor
    }

    Rectangle {
      x: 30
      y: 37
      width: 4
      height: 5
      radius: 2
      color: root.filled ? root.color : root.holeColor
    }
  }
}
