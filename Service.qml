import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Headless singleton owned by the Omarchy shell. Reads Omarchy's clipboard
// history — the same file and the same entries Super+Ctrl+V shows — and
// keeps a "line" of the most recent copies (newest last, like laundry pinned
// up as it comes out of the basket) for the bar widget (BarWidget.qml) to
// read and act on. It also hangs the line itself (Line.qml) across the top
// of every screen. It is a second, bar-drop-down view onto Omarchy's own
// clipboard history, not a separate store. Keep this as an Item: a file
// named Service.qml cannot instantiate Service or it recursively instantiates
// itself.
Item {
  id: root

  readonly property string homeDir: Quickshell.env("HOME") || ""

  // Omarchy's clipboard plugin records every copy here (newest first), and
  // already leaves out what password managers mark as secret. The line only
  // reads it, so nothing is captured twice.
  // The shell fills this in on every service that declares it, so it can't
  // be readonly.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || root.homeDir + "/.local/state"
  readonly property string clipboardHistoryPath: root.stateHome + "/omarchy/clipboard-history.json"

  // 50 copies is what Omarchy's own clipboard panel shows.
  readonly property int maxCopies: 50

  /**
   * Newest last: { id, path, name, kind: "image"|"note"|"link", mtime
   * (Omarchy's own history order, negated: 0, -1, -2, ... so the newest
   * sorts last), source: "clipboard" }. Each item also carries its history
   * entry (text, mime) as `entry`.
   */
  property var items: []
  readonly property int count: items.length
  property string itemsSignature: ""

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
  // chat apps, editors, etc. pastes the image. A note or link copies its
  // text back, through the same helper Omarchy's clipboard panel uses.
  function copyToClipboard(item) {
    if (!item) return
    if (item.kind === "note" || item.kind === "link") {
      var index = root.historyIndexOf(item)
      if (index < 0) return
      Util.execArgv([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--copy-only", "--history-index", String(index)])
      return
    }
    copyProcess.run(item.path, item.entry ? item.entry.mime : "")
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

  // item.path points into Omarchy's clipboard image cache, not a file this
  // plugin owns, so this only opens its folder — it never writes there.
  function revealInFiles(item) {
    if (!item || !item.path) return
    var dirPath = item.path.slice(0, item.path.lastIndexOf("/")) || "/"
    Util.execArgv(["xdg-open", dirPath])
  }

  Process {
    id: copyProcess
    function run(path, mime) {
      // cat | wl-copy keeps the clipboard entry a real file payload (so
      // pasting elsewhere gets the image, not a path string), without
      // interpolating the path into a shell string: it only ever reaches
      // argv, both for cat and for the mime type.
      copyProcess.command = ["sh", "-c", "exec cat -- \"$1\" | wl-copy --type \"$2\"", "sh", path, mime || "image/png"]
      copyProcess.running = true
    }
  }

  // --- the line's contents ---------------------------------------------------

  // The only way an item leaves the line: it leaves Omarchy's clipboard
  // history too, so the line and Super+Ctrl+V's panel never disagree about
  // what's there.
  function trash(item) {
    if (!item) return
    root.removeFromHistory(item)
    root.clips = root.clips.filter(function(clip) { return clip.id !== item.id })
    root.rebuild()
  }

  // The line is just the clipboard's copies, in the order they arrived.
  function rebuild() {
    var merged = root.clips.slice().sort(function(a, b) { return a.mtime - b.mtime })
    // The history file can change without actually reordering anything;
    // handing the line a new list that says the same thing would rebuild
    // every card and lose the place it was scrolled to.
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
    root.clipboardRaw = parsed

    var seenIds = {}
    var next = []
    // Omarchy's history is already newest-first and reorders a re-copy to
    // the front itself; mirror that order (index 0 = newest) exactly
    // instead of guessing at recency with a timestamp of our own, so the
    // line can never disagree with Omarchy's own panel about what's newest.
    for (var i = 0; i < parsed.length && next.length < root.maxCopies; i++) {
      var entry = parsed[i]
      if (!entry || typeof entry !== "object") continue
      var kind = ""
      if (entry.type === "image" && entry.path) kind = "image"
      else if (entry.type === "text" && String(entry.text || "").trim().length > 0)
        kind = root.isLink(entry.text) ? "link" : "note"
      if (!kind) continue

      var id = root.clipId(entry)
      if (seenIds[id]) continue
      seenIds[id] = true

      next.push({
        id: id,
        path: kind === "image" ? String(entry.path) : "",
        name: kind === "image" ? String(entry.path).slice(String(entry.path).lastIndexOf("/") + 1) : "",
        kind: kind,
        flavor: kind === "note" ? root.noteFlavor(entry.text) : kind,
        source: "clipboard",
        mtime: -i,
        entry: kind === "image"
          ? { type: "image", path: String(entry.path), mime: String(entry.mime || "image/png") }
          : { type: "text", text: String(entry.text) }
      })
    }

    root.clips = next
    root.rebuild()
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

  function refreshClipboard() {
    if (clipboardFile.loaded) root.loadClipboard(clipboardFile.text())
  }

  FileView {
    id: clipboardFile
    path: root.clipboardHistoryPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.refreshClipboard()
    onLoadFailed: root.loadClipboard("[]")
    onFileChanged: reload()
  }

}
