import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The line itself: a horizontal strip of recent screenshots and recordings,
// newest at the right, like photos clipped to a clothesline. Left click
// copies the item to the clipboard; the trash glyph on each thumbnail
// unpins it (file stays on disk — see Service.trash for actually deleting).
Panel {
  id: root
  moduleName: "io.github.ayandexyz.clothesline"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null

  readonly property var items: service ? service.items : []
  readonly property int count: items.length

  function open() {
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  // Copies the file itself to the clipboard (not its path) so pasting into
  // chat apps, editors, etc. pastes the image/video, matching what copying
  // straight out of the capture preview would do.
  function copyToClipboard(item) {
    if (!item) return
    copyProcess.run(item.path, item.kind)
  }

  function openExternally(item) {
    if (!item) return
    Util.execArgv(["xdg-open", item.path])
  }

  function annotate(item) {
    if (!item || item.kind !== "image") return
    Util.execArgv(["omasnap", "--file", item.path])
  }

  function revealInFiles(item) {
    if (!item) return
    var dirPath = item.path.slice(0, item.path.lastIndexOf("/")) || "/"
    Util.execArgv(["xdg-open", dirPath])
  }

  function unpin(item) {
    if (!item || !service) return
    service.dismiss(item.path)
  }

  function remove(item) {
    if (!item || !service) return
    service.trash(item.path)
  }

  Process {
    id: copyProcess
    function run(path, kind) {
      var mime = kind === "video" ? "video/mp4" : "image/png"
      // cat | wl-copy keeps the clipboard entry a real file payload (so
      // pasting elsewhere gets the image/video, not a path string), without
      // interpolating the path into a shell string: it only ever reaches
      // argv, both for cat and for the mime type.
      copyProcess.command = ["sh", "-c", "exec cat -- \"$1\" | wl-copy --type \"$2\"", "sh", path, mime]
      copyProcess.running = true
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    centerOnBar: false
    contentWidth: panel.fittedContentWidth(Math.min(Style.space(560), strip.implicitWidth + Style.space(16)))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onMoveRequested: function(dx, dy) { if (dx !== 0) root.switchPanel(dx) }
    }

    Column {
      id: content
      width: parent.width
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: "Clothesline"
        color: root.barForeground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        visible: root.count === 0
        text: "Nothing hanging yet. Take a screenshot or recording and it shows up here."
        color: root.barForeground
        opacity: 0.7
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.Wrap
      }

      Flickable {
        id: flick
        visible: root.count > 0
        width: parent.width
        height: visible ? ropeArea.implicitHeight : 0
        contentWidth: ropeArea.implicitWidth
        contentHeight: ropeArea.implicitHeight
        flickableDirection: Flickable.HorizontalFlick
        clip: true
        // New items land at the right end of the line; start scrolled there
        // so the freshest capture is what's visible without scrolling.
        onContentWidthChanged: Qt.callLater(function() { flick.contentX = Math.max(0, flick.contentWidth - flick.width) })

        // The wire: a horizontal rope with a slight sag, newest capture
        // pinned at the right end, like laundry drying across a yard.
        Item {
          id: ropeArea
          readonly property real ropeY: Style.space(10)
          implicitWidth: strip.implicitWidth
          implicitHeight: ropeY + strip.implicitHeight

          Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
              strokeWidth: Style.space(1.5)
              strokeColor: Util.alpha(root.barForeground, 0.45)
              fillColor: "transparent"
              capStyle: ShapePath.RoundCap

              startX: 0
              startY: ropeArea.ropeY
              PathQuad {
                x: ropeArea.implicitWidth
                y: ropeArea.ropeY
                controlX: ropeArea.implicitWidth / 2
                controlY: ropeArea.ropeY + Math.min(Style.space(14), ropeArea.implicitWidth * 0.02)
              }
            }
          }

          Row {
            id: strip
            y: ropeArea.ropeY
            spacing: Style.space(10)
            height: Style.space(140)

            Repeater {
              model: root.items

              Item {
                id: peg
                required property var modelData
                required property int index
                width: Style.space(120)
                height: strip.height

                readonly property bool isVideo: modelData.kind === "video"
                // A small, stable wobble per item so the line doesn't look
                // perfectly mechanical, without animating or re-randomizing
                // on every refresh.
                readonly property real tilt: ((index * 37) % 7 - 3) * 0.6

                rotation: hoverArea.hovered ? 0 : peg.tilt
                transformOrigin: Item.Top
                Behavior on rotation { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                // The clothespin: a small metal clip straddling the rope,
                // directly above the card it holds.
                Rectangle {
                  id: pin
                  width: Style.space(8)
                  height: Style.space(20)
                  radius: Style.space(2)
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.top: parent.top
                  anchors.topMargin: -Style.space(14)
                  z: 2
                  gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.lighter(Commons.Color.muted, 1.1) }
                    GradientStop { position: 0.5; color: Qt.lighter(Commons.Color.muted, 1.6) }
                    GradientStop { position: 1.0; color: Commons.Color.muted }
                  }
                  border.color: Util.alpha("#000000", 0.25)
                  border.width: 1
                }

                BorderSurface {
                  id: card
                  anchors.top: parent.top
                  anchors.topMargin: Style.space(6)
                  width: parent.width
                  height: parent.height - Style.space(6)
                  color: Color.popups.background
                  radius: Style.cornerRadius * 0.6
                  borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, 1)
                  padding: Style.space(4)

                  SizedImage {
                    id: thumb
                    anchors.fill: parent
                    crop: true
                    // Video files have no usable thumbnail source here; a
                    // generic clapper glyph (below) stands in for them instead
                    // of asking Image to decode a video container.
                    url: peg.isVideo ? "" : Util.fileUrl(peg.modelData.path)
                  }

                  Text {
                    visible: peg.isVideo
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "\uf03d" // nf-fa-video_camera
                    color: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.title
                  }

                  MouseArea {
                    id: hoverArea
                    readonly property bool hovered: containsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: function(mouse) {
                      if (mouse.button === Qt.RightButton) { itemMenu.item = peg.modelData; itemMenu.visible = true; return }
                      root.copyToClipboard(peg.modelData)
                    }
                    onDoubleClicked: root.openExternally(peg.modelData)
                  }
                }

                // Unpin glyph, top-right corner: removes it from the line
                // without touching the file.
                Rectangle {
                  width: Style.space(18)
                  height: Style.space(18)
                  radius: width / 2
                  anchors.top: card.top
                  anchors.right: card.right
                  anchors.margins: Style.space(2)
                  color: Util.alpha(Commons.Color.background, 0.85)

                  Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "\u00d7"
                    color: root.barForeground
                    font.pixelSize: Style.font.caption
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.unpin(peg.modelData)
                  }
                }
              }
            }
          }
        }
      }
    }

    // A tiny right-click menu: annotate (images only), reveal in files, delete.
    Item {
      id: itemMenu
      property var item: null
      visible: false
      anchors.fill: parent

      MouseArea {
        anchors.fill: parent
        onClicked: itemMenu.visible = false
      }

      BorderSurface {
        x: Style.space(12)
        y: Style.space(12)
        width: menuColumn.implicitWidth + Style.space(16)
        height: menuColumn.implicitHeight + Style.space(8)
        color: Color.popups.background
        radius: Style.cornerRadius * 0.6
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, 1)

        Column {
          id: menuColumn
          x: Style.space(8)
          y: Style.space(4)

          Repeater {
            model: [
              { label: "Annotate", visible: itemMenu.item && itemMenu.item.kind === "image", action: function() { root.annotate(itemMenu.item) } },
              { label: "Reveal in files", visible: true, action: function() { root.revealInFiles(itemMenu.item) } },
              { label: "Delete", visible: true, action: function() { root.remove(itemMenu.item) } }
            ]

            Text {
              required property var modelData
              visible: modelData.visible
              textFormat: Text.PlainText
              text: modelData.label
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
              topPadding: Style.space(4)
              bottomPadding: Style.space(4)

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { modelData.action(); itemMenu.visible = false }
              }
            }
          }
        }
      }
    }
  }
}
