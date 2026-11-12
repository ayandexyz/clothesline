import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Headless singleton owned by the Omarchy shell. Watches the screenshot and
// screen-recording output directories and Omarchy's clipboard history, keeps
// a "line" of the most recent captures and copies (newest last, like laundry
// pinned up as it comes out of the basket), and lets the bar widget
// (BarWidget.qml) read and act on it. It also hangs the line itself
// (Line.qml) across the top of every screen. Keep this as an Item: a file
// named Service.qml cannot instantiate Service or it recursively instantiates
// itself.
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
  // Items removed from the line (but left on disk, or in the clipboard
  // history) go here, by id, so a rescan doesn't bring one straight back.
  property var dismissed: ({})
  property bool prefsLoaded: false

  // Omarchy's clipboard plugin records every copy here (newest first), and
  // already leaves out what password managers mark as secret. The line only
  // reads it, so nothing is captured twice.
  // The shell fills this in on every service that declares it, so it can't
  // be readonly.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || root.homeDir + "/.local/state"
  readonly property string clipboardHistoryPath: root.stateHome + "/omarchy/clipboard-history.json"
  // The history has no times, so each copy is stamped when the line first
  // sees it; that is what places it among the captures.
  property var clipboardSeen: ({})
  property bool seenLoaded: false

  // Captures and copies are capped apart, so a run of copies never pushes the
  // screenshots off; 50 copies is what Omarchy's own clipboard panel shows.
  readonly property int maxCaptures: 24
  readonly property int maxCopies: 50
  readonly property var imageExtensions: ["png", "jpg", "jpeg", "webp", "gif", "bmp"]
  readonly property var videoExtensions: ["mp4", "m4v", "mov", "webm", "mkv"]

  /**
   * Newest last: { id, path, name, kind: "image"|"video"|"note"|"link",
   * source: "capture"|"clipboard", mtime (epoch seconds) }. Clipboard items
   * also carry their history entry (text, mime) as `entry`.
   */
  property var items: []
  readonly property int count: items.length
  property string itemsSignature: ""

  property var captures: []
  // The newest copies, the ones that hang while nothing is searched.
  property var clips: []
  // The history as written, entries kept whole, so deleting one rewrites
  // everything else exactly as Omarchy left it.
  property var clipboardRaw: []

  // The screen whose line the bar widget is holding down, or "" when every
  // line is left to drop on hover alone.
  property string heldScreen: ""
  // Clicking the bar button to close a held line first lets the line's focus
  // grab go (the click landed outside it), then presses the button; without
  // this, that press would hold the line straight back down.
  property real releasedAt: 0

  function toggleLine(screenName) {
    var name = String(screenName || "")
    if (root.heldScreen === "" && Date.now() - root.releasedAt < 300) return
    if (root.heldScreen === name) root.releaseLine()
    else root.holdLine(name)
  }

  function holdLine(screenName) {
    root.heldScreen = String(screenName || "")
  }

  function releaseLine() {
    if (root.heldScreen !== "") root.releasedAt = Date.now()
    root.heldScreen = ""
  }

  Variants {
    model: Quickshell.screens

    Line {
      required property var modelData
      screen: modelData
      service: root
    }
  }

  // --- item actions ----------------------------------------------------------

  // Copies the file itself to the clipboard (not its path) so pasting into
  // chat apps, editors, etc. pastes the image/video, matching what copying
  // straight out of the capture preview would do. A note or link copies its
  // text back, through the same helper Omarchy's clipboard panel uses.
  function copyToClipboard(item) {
    if (!item) return
    if (item.kind === "note" || item.kind === "link") {
      var index = root.historyIndexOf(item)
      if (index < 0) return
      Util.execArgv([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--copy-only", "--history-index", String(index)])
      return
    }
    copyProcess.run(item.path, item.kind, item.entry ? item.entry.mime : "")
  }

  function openExternally(item) {
    if (!item) return
    if (item.kind === "note" || item.kind === "link") {
      // A link opens in the browser, a note in the editor.
      var index = root.historyIndexOf(item)
      if (index >= 0) Util.execArgv([root.omarchyPath + "/bin/omarchy-clipboard-open", "--history-index", String(index)])
      return
    }
    Util.execArgv(["xdg-open", item.path])
  }

  function annotate(item) {
    if (!item || item.kind !== "image") return
    Util.execArgv(["omasnap", "--file", item.path])
  }

  function revealInFiles(item) {
    if (!item || !item.path) return
    var dirPath = item.path.slice(0, item.path.lastIndexOf("/")) || "/"
    Util.execArgv(["xdg-open", dirPath])
  }

  Process {
    id: copyProcess
    function run(path, kind, mime) {
      if (!mime) mime = kind === "video" ? "video/mp4" : "image/png"
      // cat | wl-copy keeps the clipboard entry a real file payload (so
      // pasting elsewhere gets the image/video, not a path string), without
      // interpolating the path into a shell string: it only ever reaches
      // argv, both for cat and for the mime type.
      copyProcess.command = ["sh", "-c", "exec cat -- \"$1\" | wl-copy --type \"$2\"", "sh", path, mime]
      copyProcess.running = true
    }
  }

  // --- the line's contents ---------------------------------------------------

  function isDismissed(id) {
    return root.dismissed[id] === true
  }

  function saveDismissed() {
    mkdirProcess.running = true
  }

  Process {
    id: mkdirProcess
    command: ["mkdir", "-p", root.dataDir]
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      dismissedFile.setText(JSON.stringify(Object.keys(root.dismissed)) + "\n")
      if (root.seenLoaded) seenFile.setText(JSON.stringify(root.clipboardSeen) + "\n")
    }
  }

  /** Removes an item from the line without touching the file on disk or the clipboard history. */
  function dismiss(id) {
    var key = String(id || "")
    if (!key || root.dismissed[key]) return
    var next = {}
    for (var existing in root.dismissed) next[existing] = true
    next[key] = true
    root.dismissed = next
    root.captures = root.captures.filter(function(item) { return item.id !== key })
    root.clips = root.clips.filter(function(item) { return item.id !== key })
    root.rebuild()
    root.saveDismissed()
  }

  /**
   * Lets an item go for good: a capture's file goes to the trash (so it is
   * recoverable), a copy leaves the clipboard history.
   */
  function trash(item) {
    if (!item) return
    if (item.source === "clipboard") {
      root.removeFromHistory(item)
      root.clips = root.clips.filter(function(clip) { return clip.id !== item.id })
      root.rebuild()
      return
    }
    trashProcess.run(item.path)
    root.dismiss(item.id)
  }

  function clearAll() {
    var ids = root.items.map(function(item) { return item.id })
    for (var i = 0; i < ids.length; i++) root.dismiss(ids[i])
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
        screenshotScanProcess.collected.push({ id: path, path: path, name: name, kind: kind, source: "capture", mtime: mtime })
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
        recordingScanProcess.collected.push({ id: path, path: path, name: name, kind: kind, source: "capture", mtime: mtime })
      }
    }
    onExited: root.mergeScan(recordingScanProcess.collected)
  }

  function mergeScan(found) {
    var byPath = {}
    for (var i = 0; i < root.captures.length; i++) byPath[root.captures[i].path] = root.captures[i]
    for (var j = 0; j < found.length; j++) byPath[found[j].path] = found[j]
    for (var path in byPath) if (root.isDismissed(path)) delete byPath[path]

    var merged = Object.keys(byPath).map(function(key) { return byPath[key] })
    merged.sort(function(a, b) { return a.mtime - b.mtime })
    if (merged.length > root.maxCaptures) merged = merged.slice(merged.length - root.maxCaptures)
    root.captures = merged
    root.rebuild()
  }

  // Captures and copies share one line, in the order they arrived. A
  // screenshot also lands in Omarchy's clipboard history (the capture tool
  // copies it), so drop clipboard images that are just a capture we already
  // show.
  function rebuild() {
    var capturePaths = {}
    for (var i = 0; i < root.captures.length; i++) capturePaths[root.captures[i].path] = true
    var clips = root.clips.filter(function(item) { return !(item.kind === "image" && capturePaths[item.path]) })
    var merged = root.captures.concat(clips)
    merged.sort(function(a, b) { return a.mtime - b.mtime })
    // The folders are rescanned every few seconds; handing the line a new
    // list that says the same thing would rebuild every card and lose the
    // place it was scrolled to.
    var signature = merged.map(function(item) { return item.id + "@" + item.mtime }).join("\n")
    if (signature === root.itemsSignature) return
    root.itemsSignature = signature
    root.items = merged
  }

  // --- the clipboard ---------------------------------------------------------

  // A copy that is one web address and nothing else hangs as a link.
  function isLink(text) {
    return /^https?:\/\/[^\s]+$/i.test(String(text || "").trim())
  }

  // What sort of note a copy is, so its card can say so at a glance: a
  // command, a path, an email address, some code, or plain text.
  function noteFlavor(text) {
    var body = String(text || "").trim().slice(0, 4000)
    var oneLine = body.indexOf("\n") < 0
    if (oneLine && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(body)) return "email"
    if (oneLine && /^(~|\.{0,2}\/)[^\s]*$/.test(body)) return "path"
    if (/^(\$\s+|sudo |git |npm |pnpm |npx |yarn |bun |cd |ls |docker |kubectl |python3? |pip |cargo |go |make |curl |wget |ssh |systemctl |journalctl |pacman |yay |omarchy|hyprctl |mkdir |rm |cp |mv |cat |grep |echo |export |source )/.test(body))
      return "command"
    var codeMarks = (body.match(/[{};]\s*$|=>|\b(function|const|let|return|import|def|class)\b|\w+\.\w+\(/gm) || []).length
    if (codeMarks >= 2 || (!oneLine && codeMarks >= 1)) return "code"
    return "text"
  }

  function entryKey(entry) {
    if (!entry) return ""
    if (entry.type === "image") return "image:" + String(entry.path || "")
    return "text:" + String(entry.text || "")
  }

  function clipId(entry) {
    return "clip:" + Qt.md5(root.entryKey(entry))
  }

  function historyIndexOf(item) {
    if (!item || !item.entry) return -1
    var key = root.entryKey(item.entry)
    for (var i = 0; i < root.clipboardRaw.length; i++)
      if (root.entryKey(root.clipboardRaw[i]) === key) return i
    return -1
  }

  function loadClipboard(raw) {
    var parsed = []
    try {
      var value = JSON.parse(String(raw || "[]"))
      if (Array.isArray(value)) parsed = value
    } catch (_) {}

    // Omarchy moves a copy back to the front of its history when you copy
    // it again, even if it's one already here. Rank the old history first,
    // so a re-copy that jumped ahead of where it used to sit gets stamped
    // fresh instead of staying pinned to when it was first seen.
    var oldRank = {}
    for (var o = 0; o < root.clipboardRaw.length; o++)
      oldRank[root.clipId(root.clipboardRaw[o])] = o
    root.clipboardRaw = parsed

    var now = Date.now() / 1000
    var seen = {}
    var next = []
    // Only the newest copies could ever make it onto the line.
    for (var i = 0; i < parsed.length && next.length < root.maxCopies; i++) {
      var entry = parsed[i]
      if (!entry || typeof entry !== "object") continue
      var kind = ""
      if (entry.type === "image" && entry.path) kind = "image"
      else if (entry.type === "text" && String(entry.text || "").trim().length > 0)
        kind = root.isLink(entry.text) ? "link" : "note"
      if (!kind) continue

      var id = root.clipId(entry)
      if (seen[id] !== undefined) continue
      var recopied = oldRank[id] !== undefined && oldRank[id] > i
      // Unseen (or re-copied) entries are stamped now, a hair apart so they
      // keep the history's order among themselves.
      seen[id] = (!recopied && root.clipboardSeen[id] !== undefined) ? root.clipboardSeen[id] : now - i * 0.001

      var item = {
        id: id,
        path: kind === "image" ? String(entry.path) : "",
        name: kind === "image" ? String(entry.path).slice(String(entry.path).lastIndexOf("/") + 1) : "",
        kind: kind,
        flavor: kind === "note" ? root.noteFlavor(entry.text) : kind,
        source: "clipboard",
        mtime: seen[id],
        entry: kind === "image"
          ? { type: "image", path: String(entry.path), mime: String(entry.mime || "image/png") }
          : { type: "text", text: String(entry.text) }
      }
      if (!root.isDismissed(id)) next.push(item)
    }

    var changed = JSON.stringify(seen) !== JSON.stringify(root.clipboardSeen)
    root.clipboardSeen = seen
    root.clips = next
    root.rebuild()
    if (changed) root.saveDismissed()
  }

  // Omarchy's clipboard plugin watches the same file and reloads it, so an
  // entry deleted here is gone from its panel too.
  function removeFromHistory(item) {
    var key = root.entryKey(item.entry)
    if (!key) return
    var next = root.clipboardRaw.filter(function(entry) { return root.entryKey(entry) !== key })
    if (next.length === root.clipboardRaw.length) return
    root.clipboardRaw = next
    clipboardFile.setText(JSON.stringify(next, null, 2) + "\n")
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
      root.refreshClipboard()
    }
    onLoadFailed: {
      root.prefsLoaded = true
      root.rescan()
      root.refreshClipboard()
    }
  }

  FileView {
    id: seenFile
    path: root.dataDir + "/clipboard-seen.json"
    printErrors: false
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) root.clipboardSeen = parsed
      } catch (_) {}
      root.seenLoaded = true
      root.refreshClipboard()
    }
    onLoadFailed: {
      root.seenLoaded = true
      root.refreshClipboard()
    }
  }

  // Dismissals and first-seen times have to be in before the history is
  // read, or every copy would look new and dismissed ones would flash back.
  function refreshClipboard() {
    if (root.prefsLoaded && root.seenLoaded && clipboardFile.loaded) root.loadClipboard(clipboardFile.text())
  }

  FileView {
    id: clipboardFile
    path: root.clipboardHistoryPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.refreshClipboard()
    onLoadFailed: if (root.prefsLoaded && root.seenLoaded) root.loadClipboard("[]")
    onFileChanged: reload()
  }

}
