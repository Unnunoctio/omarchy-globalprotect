import QtQuick
import QtQuick.Shapes
import qs.Commons

// Escudo con ojo de cerradura, el mismo motivo del icono .desktop. Se dibuja
// como Shape en vez de cargar el SVG porque los SVG chicos rinden mal en la
// barra. Todo se define en un espacio fijo de 64x64 y se escala de una.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  // Escudo solido cuando el tunel esta arriba, contorno cuando no: el estado
  // se lee de un vistazo aun sin distinguir el matiz del color.
  property bool filled: true
  // Con que se pinta la cerradura cuando el escudo esta relleno; el llamador
  // pasa el fondo sobre el que apoya el icono para que se lea como calado.
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

    // Cerradura: arco del grillete, cuerpo y ojo.
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
