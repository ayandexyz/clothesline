import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Headless singleton owned by the Omarchy shell. Watches the screenshot and
// screen-recording output directories, keeps a "line" of the most recent
// captures (newest last, like laundry pinned up as it comes out of the
// basket), and lets the bar widget (BarWidget.qml, which hosts the popout)
// read and act on it. Keep this as an Item: a file named Service.qml cannot
// instantiate Service or it recursively instantiates itself.
Item {
  id: root

  readonly property string homeDir: Quickshell.env("HOME") || ""
  readonly property string picturesDir: Quickshell.env("XDG_PICTURES_DIR") || (root.homeDir + "/Pictures")
  readonly property string videosDir: Quickshell.env("XDG_VIDEOS_DIR") || (root.homeDir + "/Videos")
  // Matches the env vars Omarchy's own capture scripts honor (see
  // omarchy-capture-screenshot / omarchy-capture-screenrecording), so the
  // line watches wherever captures are actually landing.
  readonly property string screenshotDir: Quickshell.env("OMASNAP_SCREENSHOT_DIR")
    || Quickshell.env("OMARCHY_SCREENSHOT_DIR")
    || (root.picturesDir + "/Screenshots")
  readonly property string recordingDir: Quickshell.env("OMARCHY_SCREENRECORD_DIR") || root.videosDir

  readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || root.homeDir + "/.local/share"
  readonly property string dataDir: dataHome + "/clothesline"
  // Capture files removed from the line (but left on disk) go here, by path,
  // so a rescan doesn't bring a dismissed item straight back.
  property var dismissed: ({})
  property bool prefsLoaded: false

  readonly property int maxItems: 24
  readonly property var imageExtensions: ["png", "jpg", "jpeg", "webp", "gif", "bmp"]
  readonly property var videoExtensions: ["mp4", "m4v", "mov", "webm", "mkv"]

  /** Newest last: { path, name, kind: "image"|"video", mtime (epoch seconds) }. */
  property var items: []
  readonly property int count: items.length

  function isDismissed(path) {
    return root.dismissed[path] === true
  }

  function saveDismissed() {
    mkdirProcess.running = true
  }

  Process {
    id: mkdirProcess
    command: ["mkdir", "-p", root.dataDir]
    onExited: {
      if (exitCode === 0)
        dismissedFile.setText(JSON.stringify(Object.keys(root.dismissed)) + "\n")
    }
  }

  /** Removes an item from the line without touching the file on disk. */
  function dismiss(path) {
    var key = String(path || "")
    if (!key || root.dismissed[key]) return
    var next = {}
    for (var existing in root.dismissed) next[existing] = true
    next[key] = true
    root.dismissed = next
    root.items = root.items.filter(function(item) { return item.path !== key })
    root.saveDismissed()
  }

  /** Deletes the file (via gio trash, so it is recoverable) and drops it from the line. */
  function trash(path) {
    var key = String(path || "")
    if (!key) return
    trashProcess.run(key)
    root.dismiss(key)
  }

  function clearAll() {
    for (var i = 0; i < root.items.length; i++) root.dismiss(root.items[i].path)
  }

  Process {
    id: trashProcess
    function run(path) {
      trashProcess.command = ["gio", "trash", "--", path]
      trashProcess.running = true
    }
  }

  // --- scanning --------------------------------------------------------------

  function extensionOf(name) {
    var match = /\.([A-Za-z0-9]+)$/.exec(String(name || ""))
    return match ? match[1].toLowerCase() : ""
  }

  function kindFor(name) {
    var ext = root.extensionOf(name)
    if (root.imageExtensions.indexOf(ext) >= 0) return "image"
    if (root.videoExtensions.indexOf(ext) >= 0) return "video"
    return ""
  }

  // `find -printf` keeps parsing simple and avoids a shell having to glob
  // untrusted directory contents; each directory is passed as a literal
  // argv entry, never interpolated into a command string.
  function scanDir(dir) {
    if (!dir) return
    var process = dir === root.screenshotDir ? screenshotScanProcess : recordingScanProcess
    process.command = ["find", dir, "-maxdepth", "1", "-type", "f",
      "-printf", "%T@ %p\\n"]
    process.collected = []
    process.running = true
  }

  Process {
    id: screenshotScanProcess
    property var collected: []
    stdout: SplitParser {
      onRead: function(line) {
        var text = String(line || "")
        var spaceIndex = text.indexOf(" ")
        if (spaceIndex < 0) return
        var mtime = Number(text.slice(0, spaceIndex))
        var path = text.slice(spaceIndex + 1)
        if (!isFinite(mtime) || !path) return
        var name = path.slice(path.lastIndexOf("/") + 1)
        var kind = root.kindFor(name)
        if (!kind || root.isDismissed(path)) return
        screenshotScanProcess.collected.push({ path: path, name: name, kind: kind, mtime: mtime })
      }
    }
    onExited: root.mergeScan(screenshotScanProcess.collected)
  }

  Process {
    id: recordingScanProcess
    property var collected: []
    stdout: SplitParser {
      onRead: function(line) {
        var text = String(line || "")
        var spaceIndex = text.indexOf(" ")
        if (spaceIndex < 0) return
        var mtime = Number(text.slice(0, spaceIndex))
        var path = text.slice(spaceIndex + 1)
        if (!isFinite(mtime) || !path) return
        var name = path.slice(path.lastIndexOf("/") + 1)
        var kind = root.kindFor(name)
        if (!kind || root.isDismissed(path)) return
        recordingScanProcess.collected.push({ path: path, name: name, kind: kind, mtime: mtime })
      }
    }
    onExited: root.mergeScan(recordingScanProcess.collected)
  }

  function mergeScan(found) {
    var byPath = {}
    for (var i = 0; i < root.items.length; i++) byPath[root.items[i].path] = root.items[i]
    for (var j = 0; j < found.length; j++) byPath[found[j].path] = found[j]
    for (var path in byPath) if (root.isDismissed(path)) delete byPath[path]

    var merged = Object.keys(byPath).map(function(key) { return byPath[key] })
    merged.sort(function(a, b) { return a.mtime - b.mtime })
    if (merged.length > root.maxItems) merged = merged.slice(merged.length - root.maxItems)
    root.items = merged
  }

  function rescan() {
    root.scanDir(root.screenshotDir)
    root.scanDir(root.recordingDir)
  }

  Timer {
    id: pollTimer
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.rescan()
  }

  // Watching the directories themselves means a fresh capture shows up on
  // the line within a second or two instead of waiting for the next poll.
  FileView {
    path: root.screenshotDir
    watchChanges: true
    printErrors: false
    onFileChanged: Qt.callLater(root.rescan)
  }

  FileView {
    path: root.recordingDir
    watchChanges: true
    printErrors: false
    onFileChanged: Qt.callLater(root.rescan)
  }

  FileView {
    id: dismissedFile
    path: root.dataDir + "/dismissed.json"
    printErrors: false
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        if (Array.isArray(parsed)) {
          var next = {}
          for (var i = 0; i < parsed.length; i++) next[String(parsed[i])] = true
          root.dismissed = next
        }
      } catch (_) {}
      root.prefsLoaded = true
      root.rescan()
    }
    onLoadFailed: {
      root.prefsLoaded = true
      root.rescan()
    }
  }

}
