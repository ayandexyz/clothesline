import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Bar entry point: a small picture glyph with a count badge. Click opens the
// line (Panel.qml, which hosts the hanging-item strip).
BarWidget {
  id: root
  moduleName: "io.github.ayandexyz.clothesline"
  property var shell: null
  property var service: null

  readonly property int count: service ? service.count : 0

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function findService() {
    var found = null
    if (root.bar && root.bar.shell && typeof root.bar.shell.serviceFor === "function")
      found = root.bar.shell.serviceFor(root.moduleName)
    else if (root.shell && typeof root.shell.serviceFor === "function")
      found = root.shell.serviceFor(root.moduleName)
    if (found && found !== root.service) {
      root.service = found
      root.injectPanel()
    }
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.service = root.service
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  Timer {
    interval: 1000
    repeat: true
    running: root.service === null
    triggeredOnStart: true
    onTriggered: root.findService()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: vertical ? -1 : glyphContent.implicitWidth + scaledHorizontalMargin * 2
    fixedHeight: vertical ? glyphContent.implicitHeight + scaledVerticalPadding * 2 : -1
    tooltipText: root.count > 0
      ? root.count + " item" + (root.count === 1 ? "" : "s") + " hanging on the line"
      : "Clothesline: nothing new"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }

    Row {
      id: glyphContent
      anchors.centerIn: parent
      spacing: Style.space(4)

      Text {
        id: glyph
        // nf-fa-picture_o, monochrome, so it takes the theme's bar color.
        text: "\uf03e"
        textFormat: Text.PlainText
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
      }

      Rectangle {
        id: badge
        visible: root.count > 0
        anchors.verticalCenter: glyph.verticalCenter
        height: badgeText.implicitHeight + Style.space(2)
        width: Math.max(height, badgeText.implicitWidth + Style.space(8))
        radius: height / 2
        color: Commons.Color.accent

        Text {
          id: badgeText
          anchors.centerIn: parent
          text: root.count > 99 ? "99+" : String(root.count)
          textFormat: Text.PlainText
          color: Commons.Color.background
          font.family: button.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }
    }
  }
}
