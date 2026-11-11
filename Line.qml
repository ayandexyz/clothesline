import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// One screen's line: a rope strung across the top of the screen, just under
// the bar, with recent screenshots and recordings pegged to it, newest at the
// right. It stays mapped and slides its contents out of sight when tucked, so
// opening never waits on a fresh layer surface; while tucked, the input mask
// shrinks to a thin strip under the middle of the bar and clicks fall through.
//
// Rest the pointer on that strip and the line drops down; move away and it
// tucks back up. Clicking the bar widget holds it down until a click lands
// elsewhere.
PanelWindow {
  id: window

  property var service: null

  readonly property var items: service ? service.items : []
  readonly property int count: items.length

  // Down because the pointer is resting on it, or held down by the bar widget.
  property bool hoverRevealed: false
  readonly property bool held: !!service && !!screen && service.heldScreen === screen.name
  readonly property bool menuOpen: itemMenu.item !== null
  readonly property bool revealed: hoverRevealed || held || menuOpen

  readonly property int ropeInset: Style.space(10)
  readonly property int cardWidth: Style.space(120)
  readonly property int cardHeight: Style.space(134)
  // How far the middle of the rope sags below its ends: a longer rope sags
  // further, as a real one would.
  readonly property real sag: Math.max(Style.space(24), width * 0.035)
  readonly property int lineHeight: ropeInset + sag + cardHeight + Style.space(24)
  // Room under the line for an item's right-click menu.
  readonly property int menuRoom: Style.space(90)

  // Where the rope sits at a given x across the window: a quadratic curve
  // whose control point is centered, so x runs linearly along it, and whose
  // control point sits at twice the sag so its lowest point is the sag.
  function ropeY(x) {
    var t = Math.max(0, Math.min(1, x / Math.max(1, window.width)))
    return window.ropeInset + 4 * window.sag * t * (1 - t)
  }

  // The rope's angle at a given x, in degrees: a pegged card leans with it,
  // downhill toward the middle.
  function ropeAngle(x) {
    var t = Math.max(0, Math.min(1, x / Math.max(1, window.width)))
    var slope = 4 * window.sag * (1 - 2 * t) / Math.max(1, window.width)
    return Math.atan(slope) * 180 / Math.PI
  }

  visible: !remapGuard.remapping
  color: "transparent"
  WlrLayershell.namespace: "clothesline"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  // Kept clear of the bar's reserved edge, so the line hangs from its bottom
  // edge, without reserving any room of its own.
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0
  anchors { top: true; left: true; right: true }
  implicitHeight: window.lineHeight + window.menuRoom

  mask: Region {
    item: window.revealed ? body : edgeTrigger

    Region { item: itemMenu.visible ? menuCard : null }
  }

  ScreenMoveRemap {
    id: remapGuard
    window: window
  }

  // A click anywhere else lets a held line go.
  HyprlandFocusGrab {
    active: window.held || window.menuOpen
    windows: [window]
    onCleared: {
      itemMenu.item = null
      if (window.service) window.service.releaseLine()
    }
  }

  Timer {
    id: dwellTimer
    // The pointer has to rest on the strip a moment, so sweeping up to the
    // bar's clock or workspaces doesn't drop the line every time.
    interval: 250
    onTriggered: if (edgeHover.hovered) window.hoverRevealed = true
  }

  Timer {
    id: hideTimer
    // Long enough to cross from the strip down onto the cards.
    interval: 300
    onTriggered: {
      if (!edgeHover.hovered && !bodyHover.hovered && !window.menuOpen) window.hoverRevealed = false
    }
  }

  // Under the middle of the bar, where Tendedero's menu-bar gesture lives.
  Item {
    id: edgeTrigger
    x: (window.width - width) / 2
    y: 0
    width: Math.round(window.width / 3)
    height: Style.space(4)

    HoverHandler {
      id: edgeHover
      onHoveredChanged: {
        if (hovered) dwellTimer.restart()
        else hideTimer.restart()
      }
    }
  }

  Item {
    id: body
    width: window.width
    height: window.lineHeight
    clip: true

    HoverHandler {
      id: bodyHover
      enabled: window.revealed
      onHoveredChanged: if (!hovered) hideTimer.restart()
    }

    Item {
      id: line
      width: parent.width
      height: parent.height
      // Slid up past the top of the window, under the bar, while tucked.
      y: window.revealed ? 0 : -height
      Behavior on y { NumberAnimation { duration: Style.duration(260); easing.type: Easing.OutCubic } }

      // A gentle swing each time the line comes down, settling to rest.
      property real swing: 0
      Connections {
        target: window
        function onRevealedChanged() {
          if (!window.revealed) return
          swingAnimation.restart()
        }
      }
      NumberAnimation {
        id: swingAnimation
        target: line
        property: "swing"
        from: 1
        to: 0
        duration: Style.duration(900)
        easing.type: Easing.OutElastic
        easing.amplitude: 1.2
        easing.period: 0.4
      }

      // A soft shade behind the line keeps the rope and cards legible over
      // whatever is on screen, fading out toward the bottom.
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0.0; color: Util.alpha(Commons.Color.background, 0.55) }
          GradientStop { position: 1.0; color: Util.alpha(Commons.Color.background, 0) }
        }
      }

      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
          strokeWidth: Style.space(1.5)
          strokeColor: Util.alpha(Commons.Color.foreground, 0.55)
          fillColor: "transparent"
          capStyle: ShapePath.RoundCap

          startX: 0
          startY: window.ropeInset
          PathQuad {
            x: window.width
            y: window.ropeInset
            controlX: window.width / 2
            controlY: window.ropeInset + window.sag * 2
            // ropeY() mirrors this curve; keep the two in step.
          }
        }
      }

      // The empty line still hangs a small tag, so dropping it isn't a blank
      // reveal of nothing.
      Rectangle {
        visible: window.count === 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: window.ropeY(window.width / 2) + Style.space(6)
        width: emptyText.implicitWidth + Style.space(20)
        height: emptyText.implicitHeight + Style.space(10)
        radius: Style.cornerRadius * 0.6
        color: Color.popups.background
        border.color: Color.popups.border
        border.width: 1

        Text {
          id: emptyText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: "Nothing hanging yet. Take a screenshot or recording."
          color: Color.popups.text
          opacity: 0.75
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }

      Flickable {
        id: flick
        visible: window.count > 0
        anchors.fill: parent
        contentWidth: Math.max(width, strip.implicitWidth + Style.space(40))
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        // New items land at the right end of the line; keep that end in view
        // so the freshest capture is what shows without scrolling.
        onContentWidthChanged: Qt.callLater(function() { flick.contentX = Math.max(0, flick.contentWidth - flick.width) })

        WheelHandler {
          onWheel: function(event) {
            var delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
            flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, flick.contentX - delta))
          }
        }

        Row {
          id: strip
          // Centered while it fits, so a short line hangs in the middle.
          x: Math.max(Style.space(20), (flick.contentWidth - implicitWidth) / 2)
          spacing: Style.space(14)

          Repeater {
            model: window.items

            Item {
              id: peg
              required property var modelData
              required property int index
              width: window.cardWidth
              height: window.cardHeight + Style.space(20)

              readonly property bool isVideo: modelData.kind === "video"
              // A small, stable wobble per item so the line doesn't look
              // perfectly mechanical, without re-randomizing on every refresh.
              readonly property real tilt: ((index * 37) % 7 - 3) * 0.6
              // Where the rope passes over this card, in the window.
              readonly property real centerX: strip.x + x + width / 2 - flick.contentX

              y: window.ropeY(centerX) - Style.space(4)
              // Clipped to a sloping rope, a card leans with it; hovering
              // straightens it for a clear look.
              readonly property real lean: window.ropeAngle(centerX)

              rotation: hoverArea.containsMouse ? 0 : peg.lean + peg.tilt + line.swing * (index % 2 === 0 ? 5 : -4)
              transformOrigin: Item.Top
              Behavior on rotation {
                enabled: !swingAnimation.running
                NumberAnimation { duration: Style.duration(150); easing.type: Easing.OutQuad }
              }

              // The clothespin: a small clip straddling the rope, directly
              // above the card it holds.
              Rectangle {
                width: Style.space(8)
                height: Style.space(20)
                radius: Style.space(2)
                anchors.horizontalCenter: parent.horizontalCenter
                y: -Style.space(8)
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
                y: Style.space(6)
                width: parent.width
                height: window.cardHeight
                color: Color.popups.background
                radius: Style.cornerRadius * 0.6
                borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, 1)
                padding: Style.space(4)

                SizedImage {
                  anchors.fill: parent
                  crop: true
                  // Video files have no usable thumbnail source here; a
                  // clapper glyph (below) stands in for them instead of asking
                  // Image to decode a video container.
                  url: peg.isVideo ? "" : Util.fileUrl(peg.modelData.path)
                }

                Text {
                  visible: peg.isVideo
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: "" // nf-fa-video_camera
                  color: Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                }

                MouseArea {
                  id: hoverArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) {
                      var at = card.mapToItem(window.contentItem, mouse.x, mouse.y)
                      itemMenu.openAt(peg.modelData, at.x, at.y)
                      return
                    }
                    if (window.service) window.service.copyToClipboard(peg.modelData)
                  }
                  onDoubleClicked: if (window.service) window.service.openExternally(peg.modelData)
                }
              }

              // Unpin glyph, top-right corner: takes it off the line without
              // touching the file.
              Rectangle {
                width: Style.space(18)
                height: Style.space(18)
                radius: width / 2
                anchors.top: card.top
                anchors.right: card.right
                anchors.margins: Style.space(2)
                visible: hoverArea.containsMouse || unpinArea.containsMouse
                color: Util.alpha(Commons.Color.background, 0.85)

                Text {
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: "×"
                  color: Commons.Color.foreground
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  id: unpinArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (window.service) window.service.dismiss(peg.modelData.path)
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
    property real menuX: 0
    property real menuY: 0
    visible: item !== null && window.revealed
    anchors.fill: parent

    function openAt(item, x, y) {
      itemMenu.menuX = x
      itemMenu.menuY = y
      itemMenu.item = item
    }

    BorderSurface {
      id: menuCard
      x: Math.max(0, Math.min(window.width - width, itemMenu.menuX))
      y: Math.max(0, Math.min(window.height - height, itemMenu.menuY))
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
            { label: "Annotate", visible: !!itemMenu.item && itemMenu.item.kind === "image", action: function(item) { window.service.annotate(item) } },
            { label: "Reveal in files", visible: true, action: function(item) { window.service.revealInFiles(item) } },
            { label: "Delete", visible: true, action: function(item) { window.service.trash(item.path) } }
          ]

          Text {
            required property var modelData
            visible: modelData.visible
            textFormat: Text.PlainText
            text: modelData.label
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            topPadding: Style.space(4)
            bottomPadding: Style.space(4)

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                var item = itemMenu.item
                itemMenu.item = null
                if (item && window.service) modelData.action(item)
              }
            }
          }
        }
      }
    }
  }
}
