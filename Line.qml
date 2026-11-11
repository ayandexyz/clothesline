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
  // Each picture's width over height, by path; filled in as cards measure
  // them. Plain JS object, written in place, so filling it rebinds nothing.
  property var aspects: ({})
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
  // Switching this while mapped remaps the surface, which clears the focus
  // grab and lets a just-held line straight back up, so it stays None.
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

    WheelHandler {
      enabled: window.revealed
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      onWheel: function(event) { flick.scrollBy(event) }
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
          text: "Nothing hanging yet. Take a screenshot or copy something."
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
        // New items land at the right end of the line; when one arrives, or
        // the line comes down, bring that end into view so the freshest is
        // what shows. Anything else leaves the line where it was scrolled to.
        property string newestId: window.count > 0 ? String(window.items[window.count - 1].id) : ""
        onNewestIdChanged: flick.scrollToNewest()
        function scrollToNewest() {
          Qt.callLater(function() { flick.contentX = Math.max(0, flick.contentWidth - flick.width) })
        }
        Connections {
          target: window
          function onRevealedChanged() { if (window.revealed) flick.scrollToNewest() }
        }

        // The wheel slides the line sideways, whichever way it turns. The
        // cards' own mouse areas and the line's handler (below) both call
        // this, so it works over a card and in the gaps between them.
        function scrollBy(wheel) {
          var delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
          if (delta === 0 && wheel.pixelDelta) delta = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.pixelDelta.x
          flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, flick.contentX - delta))
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
              width: peg.cardWidth
              height: window.cardHeight + Style.space(20)

              readonly property bool isVideo: modelData.kind === "video"
              readonly property bool isImage: modelData.kind === "image"

              // A picture hangs whole: its card is as wide as the picture is
              // at the card's height, within reason, so nothing is cropped.
              // Remembered per file, so a card that is rebuilt is the right
              // width at once instead of growing into it and shifting the line.
              readonly property real aspect: aspectProbe.implicitHeight > 0
                ? aspectProbe.implicitWidth / aspectProbe.implicitHeight
                : (window.aspects[peg.modelData.path] || 0)
              readonly property real cardWidth: isImage && aspect > 0
                ? Math.max(Style.space(56), Math.min(Style.space(320), (window.cardHeight - Style.space(8)) * aspect + Style.space(8)))
                : window.cardWidth

              // Decoded tiny, only for its proportions.
              Image {
                id: aspectProbe
                visible: false
                asynchronous: true
                sourceSize: Qt.size(64, 64)
                source: peg.isImage && !window.aspects[peg.modelData.path] ? Util.fileUrl(peg.modelData.path) : ""
                onStatusChanged: {
                  if (status !== Image.Ready || implicitHeight <= 0) return
                  window.aspects[peg.modelData.path] = implicitWidth / implicitHeight
                }
              }
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
                // Opaque, so a note's text reads over whatever is behind it.
                color: Util.alpha(Color.popups.background, 1)
                radius: Style.cornerRadius * 0.6
                borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, 1)
                padding: Style.space(4)

                SizedImage {
                  visible: peg.modelData.kind === "image"
                  anchors.fill: parent
                  crop: false
                  // Video files have no usable thumbnail source here; a
                  // clapper glyph (below) stands in for them instead of asking
                  // Image to decode a video container.
                  url: peg.modelData.kind === "image" ? Util.fileUrl(peg.modelData.path) : ""
                }

                // A copy: a header naming what sort it is, then the text laid
                // out to suit it, and its size along the bottom.
                Item {
                  id: textCard
                  visible: peg.modelData.kind === "note" || peg.modelData.kind === "link"
                  anchors.fill: parent

                  readonly property string flavor: peg.modelData.flavor || "text"
                  // A long copy only ever shows its start; there's no point
                  // laying out all of it.
                  readonly property string body: visible ? String(peg.modelData.entry.text).trim().slice(0, 1200) : ""
                  readonly property int fullLength: visible ? String(peg.modelData.entry.text).trim().length : 0
                  readonly property int lineCount: body.split("\n").length
                  readonly property int titleEnd: body.indexOf("\n")
                  readonly property bool boxed: flavor === "command" || flavor === "code"
                  // A short line of text is set large in the middle, like a
                  // label, instead of as a title over nothing.
                  readonly property bool short: flavor !== "link" && !boxed && lineCount === 1 && body.length <= 48
                  readonly property var badge: ({
                    text: { glyph: "", label: "Note" },       // nf-fa-sticky_note
                    command: { glyph: "", label: "Command" }, // nf-fa-terminal
                    code: { glyph: "", label: "Code" },       // nf-fa-code
                    path: { glyph: "", label: "Path" },       // nf-fa-folder
                    email: { glyph: "", label: "Email" },     // nf-fa-envelope
                    link: { glyph: "", label: "Link" }        // nf-fa-link
                  })[flavor] || { glyph: "", label: "Note" }
                  readonly property var linkParts: {
                    var match = /^https?:\/\/([^\/?#]+)(.*)$/i.exec(flavor === "link" ? body : "")
                    return match ? { host: match[1].replace(/^www\./i, ""), rest: match[2] } : { host: "", rest: "" }
                  }

                  Rectangle {
                    id: header
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    height: Style.space(20)
                    radius: Style.cornerRadius * 0.4
                    color: Util.alpha(Commons.Color.accent, 0.16)

                    Row {
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(6)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(5)

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: textCard.badge.glyph
                        color: Commons.Color.accent
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                      }

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: textCard.badge.label.toUpperCase()
                        color: Color.popups.text
                        opacity: 0.8
                        font.family: Style.font.family
                        font.pixelSize: Math.max(1, Style.font.caption - 1)
                        font.bold: true
                        font.letterSpacing: 1
                      }
                    }
                  }

                  Item {
                    id: content
                    anchors {
                      top: header.bottom; topMargin: Style.space(6)
                      left: parent.left; leftMargin: Style.space(3)
                      right: parent.right; rightMargin: Style.space(3)
                      bottom: footer.top; bottomMargin: Style.space(4)
                    }
                    clip: true

                    // Short text, set large in the middle.
                    Text {
                      visible: textCard.short
                      anchors.fill: parent
                      horizontalAlignment: Text.AlignHCenter
                      verticalAlignment: Text.AlignVCenter
                      textFormat: Text.PlainText
                      text: textCard.body
                      color: Color.popups.text
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      font.bold: true
                      wrapMode: Text.Wrap
                      elide: Text.ElideRight
                    }

                    // Longer text: the first line as a title, the rest under it.
                    Column {
                      visible: !textCard.short && !textCard.boxed && textCard.flavor !== "link"
                      width: parent.width
                      spacing: Style.space(4)

                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: textCard.titleEnd < 0 ? textCard.body : textCard.body.slice(0, textCard.titleEnd)
                        color: Color.popups.text
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                        wrapMode: textCard.flavor === "path" || textCard.flavor === "email" ? Text.WrapAnywhere : Text.Wrap
                        maximumLineCount: textCard.titleEnd < 0 ? 6 : 2
                        elide: Text.ElideRight
                      }

                      Rectangle {
                        visible: textCard.titleEnd >= 0
                        width: parent.width
                        height: 1
                        color: Util.alpha(Color.popups.text, 0.12)
                      }

                      Text {
                        visible: textCard.titleEnd >= 0
                        width: parent.width
                        textFormat: Text.PlainText
                        text: textCard.titleEnd < 0 ? "" : textCard.body.slice(textCard.titleEnd + 1)
                        color: Color.popups.text
                        opacity: 0.7
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.Wrap
                        maximumLineCount: 5
                        elide: Text.ElideRight
                      }
                    }

                    // A command or code, in a darker well like a terminal,
                    // keeping its lines; a command gets a prompt.
                    Rectangle {
                      visible: textCard.boxed
                      anchors.fill: parent
                      radius: Style.cornerRadius * 0.4
                      color: Qt.darker(Color.popups.background, 1.6)
                      border.color: Util.alpha(Color.popups.text, 0.08)
                      border.width: 1

                      Text {
                        id: prompt
                        visible: textCard.flavor === "command"
                        x: Style.space(5)
                        y: Style.space(4)
                        textFormat: Text.PlainText
                        text: "$"
                        color: Commons.Color.accent
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }

                      Text {
                        anchors {
                          top: parent.top; topMargin: Style.space(4)
                          left: prompt.visible ? prompt.right : parent.left
                          leftMargin: Style.space(prompt.visible ? 4 : 5)
                          right: parent.right; rightMargin: Style.space(4)
                          bottom: parent.bottom; bottomMargin: Style.space(4)
                        }
                        textFormat: Text.PlainText
                        text: textCard.flavor === "command" ? textCard.body.replace(/^\$\s+/, "") : textCard.body
                        color: Color.popups.text
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WrapAnywhere
                        elide: Text.ElideRight
                        clip: true
                      }
                    }

                    // A link: a big glyph, its site, and the path under it.
                    Column {
                      visible: textCard.flavor === "link"
                      anchors.centerIn: parent
                      width: parent.width
                      spacing: Style.space(4)

                      Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Style.space(30)
                        height: width
                        radius: width / 2
                        color: Util.alpha(Commons.Color.accent, 0.16)

                        Text {
                          anchors.centerIn: parent
                          textFormat: Text.PlainText
                          text: "" // nf-fa-globe
                          color: Commons.Color.accent
                          font.family: Style.font.family
                          font.pixelSize: Style.font.title
                        }
                      }

                      Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        textFormat: Text.PlainText
                        text: textCard.linkParts.host
                        color: Color.popups.text
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                        elide: Text.ElideMiddle
                      }

                      Text {
                        width: parent.width
                        visible: textCard.linkParts.rest.length > 1
                        horizontalAlignment: Text.AlignHCenter
                        textFormat: Text.PlainText
                        text: textCard.linkParts.rest
                        color: Color.popups.text
                        opacity: 0.6
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WrapAnywhere
                        maximumLineCount: 2
                        elide: Text.ElideRight
                      }
                    }
                  }

                  Text {
                    id: footer
                    anchors { left: parent.left; leftMargin: Style.space(4); right: parent.right; rightMargin: Style.space(4); bottom: parent.bottom; bottomMargin: Style.space(1) }
                    textFormat: Text.PlainText
                    text: textCard.flavor === "link"
                      ? "Open ↗"
                      : textCard.lineCount > 1
                        ? textCard.lineCount + " lines"
                        : textCard.fullLength + (textCard.fullLength === 1 ? " char" : " chars")
                    color: Color.popups.text
                    opacity: 0.45
                    font.family: Style.font.family
                    font.pixelSize: Math.max(1, Style.font.caption - 1)
                    elide: Text.ElideRight
                  }
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
                    if (!window.service) return
                    window.service.copyToClipboard(peg.modelData)
                    copiedTimer.restart()
                  }
                  onDoubleClicked: if (window.service) window.service.openExternally(peg.modelData)
                  onWheel: function(wheel) { flick.scrollBy(wheel) }
                }

                // A click says it copied, in the middle of the card, then
                // fades away.
                Timer {
                  id: copiedTimer
                  interval: 1100
                }

                Rectangle {
                  anchors.centerIn: parent
                  width: copiedRow.implicitWidth + Style.space(18)
                  height: copiedRow.implicitHeight + Style.space(10)
                  radius: height / 2
                  color: Commons.Color.accent
                  opacity: copiedTimer.running ? 1 : 0
                  scale: copiedTimer.running ? 1 : 0.85
                  visible: opacity > 0
                  Behavior on opacity { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutQuad } }
                  Behavior on scale { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutBack } }

                  Row {
                    id: copiedRow
                    anchors.centerIn: parent
                    spacing: Style.space(5)

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: "" // nf-fa-check
                      color: Commons.Color.background
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: "Copied!"
                      color: Commons.Color.background
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }
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
                  onClicked: if (window.service) window.service.dismiss(peg.modelData.id)
                }
              }
            }
          }
        }
      }
    }
  }

  // A tiny right-click menu: annotate (images only), open (notes and links),
  // reveal in files, delete.
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
            { label: "Open in browser", visible: !!itemMenu.item && itemMenu.item.kind === "link", action: function(item) { window.service.openExternally(item) } },
            { label: "Open in editor", visible: !!itemMenu.item && itemMenu.item.kind === "note", action: function(item) { window.service.openExternally(item) } },
            { label: "Reveal in files", visible: !!itemMenu.item && !!itemMenu.item.path, action: function(item) { window.service.revealInFiles(item) } },
            { label: !!itemMenu.item && itemMenu.item.source === "clipboard" ? "Delete from history" : "Delete", visible: true, action: function(item) { window.service.trash(item) } }
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
