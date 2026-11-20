import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Graph.js" as Graph

// Overlay for the git repository open in Files.
// The shell calls open() on summon and close() on hide.
// keepLoaded keeps this mounted, so the shortcut can toggle it immediately.
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) ? String(manifest.id) : "timsonner.git-tree"
  readonly property string pluginDir: {
    var dir = (manifest && manifest.__sourceDir) ? String(manifest.__sourceDir) : ""
    if (dir.length > 0)
      return dir
    var url = String(Qt.resolvedUrl("."))
    if (url.indexOf("file://") === 0)
      url = url.slice(7)
    if (url.length > 0 && url.charAt(url.length - 1) === "/")
      url = url.slice(0, -1)
    try { return decodeURIComponent(url) } catch (e) { return url }
  }
  readonly property string helperPath: root.pluginDir.length > 0 ? root.pluginDir + "/helpers/snapshot" : ""

  property bool opened: false
  property bool wantOpen: false
  property bool pending: false
  property bool again: false
  property int request: 0

  property string reason: ""
  property string pathText: ""
  property string titleText: ""
  property string branchName: ""
  property string headShort: ""
  property bool detached: false
  property bool dirty: false
  property var branches: []
  property var commits: []
  property int laneCount: 1
  property string detailHash: ""
  property bool detailLoading: false
  property string detailError: ""
  property var detail: null
  property var diffLines: []
  property bool diffCut: false
  property int showToken: 0
  property bool showAgain: false
  property string viewing: ""
  property string viewError: ""
  property string viewBusy: ""
  property string viewPending: ""
  property int viewToken: 0
  property bool viewAgain: false
  property string hoverBranch: ""
  property var hoverRow: null
  property double backAt: 0

  readonly property int rowHeight: Style.space(32)
  readonly property int laneWidth: Style.space(16)
  readonly property color background: Commons.Color.menu.background
  readonly property color foreground: Commons.Color.menu.text
  readonly property color border: Commons.Color.menu.border
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  readonly property color scrim: Commons.Color.menu.scrim
  readonly property int cornerRadius: Style.cornerRadius

  readonly property string headingText: {
    var lang = strings.language
    if (root.reason === "" && root.titleText.length > 0)
      return root.titleText
    return strings.t("title")
  }
  readonly property string shownPath: root.reason === "" ? root.pathText : ""
  readonly property string branchLine: {
    var lang = strings.language
    if (root.reason !== "")
      return ""
    if (root.detached)
      return strings.t("header.detached").arg(root.headShort)
    if (root.branchName.length > 0)
      return strings.t("header.branch").arg(root.branchName)
    return ""
  }
  readonly property string message: {
    var lang = strings.language
    if (root.reason === "not-folio")
      return strings.t("error.notFolio")
    if (root.reason === "title-mismatch")
      return strings.t("error.title").arg(root.titleText)
    if (root.reason === "not-repo")
      return strings.t("error.notRepo").arg(root.pathText)
    if (root.reason === "cwd")
      return strings.t("error.cwd")
    if (root.reason === "no-window")
      return strings.t("error.noWindow")
    if (root.reason === "git-failed")
      return strings.t("error.git")
    return ""
  }
  readonly property string hintText: {
    var lang = strings.language
    if (root.detailHash.length > 0)
      return strings.t("hint.back")
    if (root.viewing.length > 0)
      return strings.t("hint.branch")
    return strings.t("hint.dismiss")
  }
  readonly property string viewNote: {
    var lang = strings.language
    if (root.viewBusy.length > 0)
      return strings.t("view.working").arg(root.viewBusy)
    if (root.viewError === "view-failed")
      return strings.t("view.failed")
    if (root.viewing.length > 0 && root.viewing !== root.branchName)
      return strings.t("header.viewing").arg(root.viewing)
    return ""
  }
  readonly property string focusBranch: root.viewing.length > 0 ? root.viewing : root.branchName
  readonly property color diffAdded: "#9ece6a"
  readonly property color diffAddedBg: Qt.rgba(root.diffAdded.r, root.diffAdded.g, root.diffAdded.b, 0.32)
  readonly property color diffRemovedBg: Qt.rgba(Commons.Color.urgent.r, Commons.Color.urgent.g, Commons.Color.urgent.b, 0.34)
  readonly property color diffHunkBg: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.16)

  function laneColor(index) {
    var palette = [Commons.Color.accent, Commons.Color.foreground, Commons.Color.urgent, Commons.Color.muted]
    var n = Math.abs(Math.floor(Number(index) || 0)) % palette.length
    return palette[n]
  }

  function carries(refs, name) {
    if (!name || !refs)
      return false
    var i
    for (i = 0; i < refs.length; i++) {
      if (refs[i] === name)
        return true
    }
    return false
  }

  function localBranch(name) {
    var wanted = String(name || "")
    if (wanted.length === 0)
      return false
    var i
    for (i = 0; i < root.branches.length; i++) {
      if (root.branches[i] && root.branches[i].name === wanted)
        return true
    }
    return false
  }

  function paintLanes(ctx, lane, through, edges, laneSpan, rowSpan, lineNames, hoverName) {
    ctx.reset()
    ctx.lineCap = "round"
    ctx.lineWidth = Math.max(1, Style.space(2))
    ctx.globalAlpha = 1
    function colorFor(column) {
      var name = ""
      if (lineNames && column >= 0)
        name = String(lineNames[column] || "")
      if (hoverName && name.length > 0 && name === hoverName)
        return Commons.Color.accent
      return root.laneColor(column)
    }
    var i
    for (i = 0; i < through.length; i++) {
      var column = through[i]
      var x = column * laneSpan + laneSpan / 2
      ctx.strokeStyle = colorFor(column)
      ctx.beginPath()
      ctx.moveTo(x, 0)
      ctx.lineTo(x, rowSpan)
      ctx.stroke()
    }
    for (i = 0; i < edges.length; i++) {
      var edge = edges[i]
      if (!edge || edge.from === edge.to)
        continue
      var x1 = edge.from * laneSpan + laneSpan / 2
      var x2 = edge.to * laneSpan + laneSpan / 2
      ctx.strokeStyle = colorFor(edge.kind === "merge" ? edge.from : edge.to)
      ctx.beginPath()
      if (edge.kind === "merge") {
        ctx.moveTo(x1, 0)
        ctx.lineTo(x2, rowSpan / 2)
      } else {
        ctx.moveTo(x1, rowSpan / 2)
        ctx.lineTo(x2, rowSpan)
      }
      ctx.stroke()
    }
    ctx.fillStyle = colorFor(lane)
    ctx.beginPath()
    ctx.arc(lane * laneSpan + laneSpan / 2, rowSpan / 2, Math.max(2, Style.space(3)), 0, Math.PI * 2)
    ctx.fill()
  }

  function noteLineHover(name, row) {
    root.hoverRow = row
    root.hoverBranch = String(name || "")
  }

  function clearLineHover(row) {
    if (root.hoverRow !== row)
      return
    root.hoverRow = null
    root.hoverBranch = ""
  }

  function refsText(refs) {
    if (!refs || !refs.length)
      return ""
    return refs.join(", ")
  }

  function refsBeside(refs, name) {
    if (!refs || !refs.length)
      return ""
    var kept = []
    var i
    for (i = 0; i < refs.length; i++) {
      if (refs[i] && refs[i] !== name)
        kept.push(refs[i])
    }
    return kept.join(", ")
  }

  function dateText(iso) {
    var when = new Date(iso)
    if (isNaN(when.getTime()))
      return ""
    return when.toLocaleString(Qt.locale(Commons.I18n.formatLocale), "yyyy-MM-dd HH:mm")
  }

  function splitDiff(text) {
    var raw = String(text || "")
    if (raw.length === 0) {
      root.diffCut = false
      return []
    }
    var parts = raw.split("\n")
    if (parts.length > 0 && parts[parts.length - 1] === "")
      parts.pop()
    var cap = 1200
    if (parts.length > cap) {
      root.diffCut = true
      return parts.slice(0, cap)
    }
    root.diffCut = false
    return parts
  }

  function diffKind(line) {
    var text = String(line || "")
    if (text.indexOf("@@") === 0)
      return "hunk"
    if (text.indexOf("+++") === 0 || text.indexOf("---") === 0 || text.indexOf("diff ") === 0 || text.indexOf("index ") === 0)
      return "meta"
    if (text.indexOf("+") === 0)
      return "add"
    if (text.indexOf("-") === 0)
      return "del"
    return "ctx"
  }

  function diffTextColor(kind) {
    if (kind === "hunk")
      return Commons.Color.accent
    if (kind === "meta")
      return Commons.Color.muted
    if (kind === "add")
      return root.diffAdded
    if (kind === "del")
      return Commons.Color.urgent
    return root.foreground
  }

  function diffBackground(kind) {
    if (kind === "add")
      return root.diffAddedBg
    if (kind === "del")
      return root.diffRemovedBg
    if (kind === "hunk")
      return root.diffHunkBg
    return "transparent"
  }

  function personText(commit) {
    if (!commit)
      return ""
    var name = String(commit.author || "")
    var email = String(commit.email || "")
    if (name.length > 0 && email.length > 0)
      return name + " <" + email + ">"
    return name.length > 0 ? name : email
  }

  function clearDetail() {
    root.detailHash = ""
    root.detail = null
    root.diffLines = []
    root.diffCut = false
    root.detailLoading = false
    root.detailError = ""
    root.showAgain = false
    if (showProc.running)
      showProc.running = false
  }

  function back() {
    var now = Date.now()
    if (now - root.backAt < 80)
      return
    root.backAt = now
    if (root.detailHash.length > 0) {
      root.clearDetail()
      return
    }
    if (root.viewing.length > 0 && root.pathText.length > 0 && root.helperPath.length > 0) {
      root.loadView("")
      return
    }
    root.dismiss()
  }

  function startShow() {
    showProc.exited = false
    showProc.streamReady = false
    showProc.command = [
      root.helperPath,
      "--commit", root.detailHash,
      "--path", root.pathText,
      "--title", root.titleText,
      "--class", "folio"
    ]
    showProc.running = true
  }

  function openCommit(hash) {
    var id = String(hash || "")
    if (!/^[0-9a-fA-F]{8,64}$/.test(id))
      return
    if (root.pathText.length === 0 || root.helperPath.length === 0)
      return
    root.detailHash = id
    root.detail = null
    root.diffLines = []
    root.diffCut = false
    root.detailError = ""
    root.detailLoading = true
    detailFlick.contentX = 0
    detailFlick.contentY = 0
    root.showToken += 1
    showProc.token = root.showToken
    if (showProc.running) {
      root.showAgain = true
      showProc.running = false
      return
    }
    root.startShow()
  }

  function finishShow(token, output) {
    if (token !== root.showToken || !root.wantOpen || root.detailHash.length === 0)
      return
    if (!root.detailLoading)
      return
    var data = null
    try {
      data = JSON.parse(output || "")
    } catch (e) {
      data = null
    }
    root.detailLoading = false
    if (!data || data.ok !== true || String(data.kind || "") !== "commit") {
      root.detailError = "git-failed"
      root.detail = null
      root.diffLines = []
      return
    }
    if (String(data.hash || "").toLowerCase() !== root.detailHash.toLowerCase()) {
      root.detailError = "git-failed"
      root.detail = null
      root.diffLines = []
      return
    }
    root.detailError = ""
    root.detail = data
    root.diffLines = root.splitDiff(String(data.diff || ""))
  }

  function close() {
    root.wantOpen = false
    root.viewing = ""
    root.viewError = ""
    root.viewBusy = ""
    root.viewPending = ""
    root.viewAgain = false
    root.viewToken += 1
    if (viewProc.running)
      viewProc.running = false
    root.request += 1
    root.pending = false
    root.again = false
    root.opened = false
    root.clearDetail()
    if (snapProc.running)
      snapProc.running = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  function open(payloadJson) {
    root.clearDetail()
    root.viewing = ""
    root.viewError = ""
    root.viewBusy = ""
    root.viewPending = ""
    root.viewAgain = false
    root.viewToken += 1
    if (viewProc.running)
      viewProc.running = false
    root.wantOpen = true
    root.request += 1
    root.pending = true
    root.reason = ""
    snapProc.token = root.request
    snapProc.output = ""
    if (snapProc.running) {
      root.again = true
      return
    }
    if (root.helperPath.length === 0) {
      root.pending = false
      root.reason = "git-failed"
      root.opened = true
      return
    }
    snapProc.running = true
  }

  function toggle() {
    if (root.opened || root.pending)
      root.dismiss()
    else
      root.open("{}")
  }

  function applyGraph(data) {
    root.reason = ""
    root.branchName = String(data.branch || "")
    root.headShort = String(data.head || "")
    root.detached = data.detached === true
    root.dirty = data.dirty === true
    root.branches = data.branches || []
    var laid = Graph.layout(data.commits || [])
    var branchNames = []
    var b
    for (b = 0; b < root.branches.length; b++) {
      if (root.branches[b] && root.branches[b].name)
        branchNames.push(String(root.branches[b].name))
    }
    root.hoverBranch = ""
    root.hoverRow = null
    root.commits = Graph.labelLines(laid.commits, branchNames)
    root.laneCount = Math.max(1, laid.width || 1)
    root.opened = true
    Qt.callLater(root.revealFocusBranch)
  }

  function revealFocusBranch() {
    var name = root.focusBranch
    if (name.length === 0)
      return
    var i
    for (i = 0; i < branchRepeater.count; i++) {
      var row = branchRepeater.itemAt(i)
      if (!row || !row.branch || row.branch.name !== name)
        continue
      var top = row.y
      var bottom = top + row.height
      if (top < branchFlick.contentY)
        branchFlick.contentY = Math.max(0, top)
      else if (bottom > branchFlick.contentY + branchFlick.height)
        branchFlick.contentY = Math.max(0, bottom - branchFlick.height)
      return
    }
  }

  function finishRead(token, output) {
    if (token !== root.request || !root.wantOpen)
      return
    root.pending = false
    var data = null
    try {
      data = JSON.parse(output || "")
    } catch (e) {
      data = null
    }
    if (!data || typeof data !== "object") {
      root.reason = "git-failed"
      root.pathText = ""
      root.titleText = ""
      root.branches = []
      root.commits = []
      root.opened = true
      return
    }
    root.pathText = String(data.path || "")
    root.titleText = String(data.title || "")
    if (data.ok !== true) {
      root.reason = String(data.reason || "git-failed")
      root.branchName = ""
      root.headShort = ""
      root.detached = false
      root.dirty = false
      root.branches = []
      root.commits = []
      root.laneCount = 1
      root.opened = true
      return
    }
    root.viewing = String(data.viewing || "")
    root.viewError = ""
    root.viewBusy = ""
    root.applyGraph(data)
  }

  function viewBranch(name) {
    var branch = String(name || "")
    if (branch.length === 0 || branch.indexOf("\n") >= 0 || branch.indexOf("\t") >= 0 || branch.indexOf("..") >= 0 || branch.charAt(0) === "-")
      return
    if (root.pending || root.pathText.length === 0 || root.helperPath.length === 0 || root.reason !== "")
      return
    var next = branch
    if (root.viewing === branch || (root.viewing.length === 0 && branch === root.branchName))
      next = ""
    if (next.length === 0 && root.viewing.length === 0)
      return
    root.loadView(next)
  }

  function selectBranch(name) {
    var branch = String(name || "")
    if (branch.length === 0 || branch.indexOf("\n") >= 0 || branch.indexOf("\t") >= 0 || branch.indexOf("..") >= 0 || branch.charAt(0) === "-")
      return
    if (root.pending || root.pathText.length === 0 || root.helperPath.length === 0 || root.reason !== "")
      return
    if (root.viewing === branch)
      return
    root.loadView(branch)
  }

  function loadView(name) {
    root.viewError = ""
    root.viewBusy = String(name || "")
    root.viewPending = String(name || "")
    root.viewToken += 1
    viewProc.token = root.viewToken
    if (viewProc.running) {
      root.viewAgain = true
      viewProc.running = false
      return
    }
    root.startView()
  }

  function startView() {
    viewProc.exited = false
    viewProc.streamReady = false
    var cmd = [root.helperPath, "--path", root.pathText, "--title", root.titleText, "--class", "folio"]
    if (root.viewPending.length > 0) {
      cmd.push("--view")
      cmd.push(root.viewPending)
    }
    viewProc.command = cmd
    viewProc.running = true
  }

  function finishView(token, output) {
    if (token !== root.viewToken || !root.wantOpen)
      return
    root.viewBusy = ""
    var data = null
    try {
      data = JSON.parse(output || "")
    } catch (e) {
      data = null
    }
    if (!data || data.ok !== true || String(data.path || "") !== root.pathText) {
      root.viewError = "view-failed"
      return
    }
    root.viewError = ""
    root.viewing = String(data.viewing || "")
    root.applyGraph(data)
    historyFlick.contentY = 0
  }

  function handleCustom(data) {
    var name = String(data || "")
    var prefix = "timsonner.git-tree:"
    if (name.indexOf(prefix) === 0)
      name = name.slice(prefix.length)
    if (name === "toggle")
      root.toggle()
    else if (name === "open")
      root.open("{}")
    else if (name === "close")
      root.dismiss()
  }

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event)
        return
      var name = String(event.name || "")
      var data = String(event.data || "").trim()
      if (name === "custom")
        root.handleCustom(data)
      else if (name.indexOf("timsonner.git-tree:") === 0)
        root.handleCustom(name)
    }
  }

  Connections {
    target: panel
    function onContentRevealedChanged() {
      if (panel.contentRevealed && root.opened)
        keyCatcher.forceActiveFocus()
    }
  }

  Process {
    id: snapProc
    property int token: 0
    property string output: ""
    command: [root.helperPath]
    stdout: StdioCollector {
      onStreamFinished: snapProc.output = String(text || "")
    }
    stderr: StdioCollector {
      onStreamFinished: {
        var err = String(text || "").trim()
        if (err.length > 0)
          console.warn("git-tree:", err)
      }
    }
    onExited: function(exitCode) {
      var token = snapProc.token
      var output = snapProc.output
      root.finishRead(token, output)
      if (root.again && root.wantOpen) {
        root.again = false
        snapProc.output = ""
        snapProc.token = root.request
        snapProc.running = true
      }
    }
  }

  Process {
    id: showProc
    property int token: 0
    property bool exited: false
    property bool streamReady: false
    command: ["true"]
    stdout: StdioCollector {
      id: showOut
      waitForEnd: true
      onStreamFinished: {
        showProc.streamReady = true
        if (showProc.exited)
          root.finishShow(showProc.token, String(text || ""))
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        var err = String(text || "").trim()
        if (err.length > 0)
          console.warn("git-tree:", err)
      }
    }
    onExited: function(exitCode) {
      showProc.exited = true
      if (root.showAgain && root.wantOpen && root.detailHash.length > 0) {
        root.showAgain = false
        Qt.callLater(function() { root.startShow() })
        return
      }
      var token = showProc.token
      if (showProc.streamReady)
        root.finishShow(token, String(showOut.text || ""))
      else
        Qt.callLater(function() { root.finishShow(token, String(showOut.text || "")) })
    }
  }

  Process {
    id: viewProc
    property int token: 0
    property bool exited: false
    property bool streamReady: false
    command: ["true"]
    stdout: StdioCollector {
      id: viewOut
      waitForEnd: true
      onStreamFinished: {
        viewProc.streamReady = true
        if (viewProc.exited)
          root.finishView(viewProc.token, String(text || ""))
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        var err = String(text || "").trim()
        if (err.length > 0)
          console.warn("git-tree:", err)
      }
    }
    onExited: function(exitCode) {
      viewProc.exited = true
      if (root.viewAgain && root.wantOpen) {
        root.viewAgain = false
        Qt.callLater(function() { root.startView() })
        return
      }
      var token = viewProc.token
      if (viewProc.streamReady)
        root.finishView(token, String(viewOut.text || ""))
      else
        Qt.callLater(function() { root.finishView(token, String(viewOut.text || "")) })
    }
  }

  IpcHandler {
    target: "timsonner.git-tree"
    function open(): string {
      root.open("{}")
      return "ok"
    }
    function close(): string {
      root.dismiss()
      return "ok"
    }
    function toggle(): string {
      root.toggle()
      return "ok"
    }
    function back(): string {
      root.back()
      return "ok"
    }
    function show(hash: string): string {
      root.openCommit(hash)
      return "ok"
    }
    function review(name: string): string {
      root.viewBranch(name)
      return "ok"
    }
  }

  OverlayWindow {
    id: panel
    shown: root.opened
    shownKeyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "timsonner-git-tree"
    color: root.scrim

    Shortcut {
      sequences: ["Esc"]
      enabled: root.opened
      context: Qt.ApplicationShortcut
      onActivated: root.back()
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: Math.min(parent.width - Style.gapsOut * 2, root.detailHash.length > 0 ? Style.space(1180) : Style.space(980))
      height: Math.min(parent.height - Style.gapsOut * 2, Style.space(680))
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: function(event) {
          root.back()
          event.accepted = true
        }
      }

      Item {
        id: body
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Text {
          id: heading
          anchors.left: parent.left
          anchors.right: parent.right
          textFormat: Text.PlainText
          text: root.headingText
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }

        Text {
          id: pathLine
          anchors.top: heading.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: Style.spacing.xs
          visible: root.shownPath.length > 0
          textFormat: Text.PlainText
          text: root.shownPath
          color: root.foreground
          opacity: 0.62
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideMiddle
        }

        Text {
          id: branchLabel
          anchors.top: pathLine.visible ? pathLine.bottom : heading.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: Style.spacing.xs
          visible: text.length > 0
          textFormat: Text.PlainText
          text: root.branchLine
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          id: dirtyLabel
          anchors.top: branchLabel.visible ? branchLabel.bottom : (pathLine.visible ? pathLine.bottom : heading.bottom)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: Style.spacing.xs
          visible: root.reason === "" && root.dirty
          textFormat: Text.PlainText
          text: strings.t("header.dirty")
          color: Commons.Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        Text {
          id: viewLabel
          anchors.top: dirtyLabel.visible ? dirtyLabel.bottom : (branchLabel.visible ? branchLabel.bottom : (pathLine.visible ? pathLine.bottom : heading.bottom))
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: Style.spacing.xs
          visible: root.reason === "" && root.viewNote.length > 0
          textFormat: Text.PlainText
          text: root.viewNote
          color: root.viewError === "view-failed" ? Commons.Color.urgent : Commons.Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        Text {
          id: messageText
          anchors.top: viewLabel.visible ? viewLabel.bottom : dirtyLabel.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: Style.spacing.lg
          visible: root.message.length > 0
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: root.message
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Item {
          id: columns
          anchors.top: messageText.visible ? messageText.bottom : (viewLabel.visible ? viewLabel.bottom : dirtyLabel.bottom)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: hint.top
          anchors.topMargin: Style.spacing.lg
          anchors.bottomMargin: Style.spacing.md
          visible: root.reason === "" && root.detailHash.length === 0

          Item {
            id: branchPane
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.min(Style.space(280), parent.width * 0.34)

            Text {
              id: branchHeading
              anchors.left: parent.left
              anchors.right: parent.right
              textFormat: Text.PlainText
              text: strings.t("branches")
              color: root.foreground
              opacity: 0.62
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Flickable {
              id: branchFlick
              anchors.top: branchHeading.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.topMargin: Style.spacing.sm
              clip: true
              contentWidth: width
              contentHeight: branchColumn.implicitHeight
              boundsBehavior: Flickable.StopAtBounds

              Column {
                id: branchColumn
                width: branchFlick.width

                Text {
                  width: parent.width
                  visible: root.branches.length === 0
                  textFormat: Text.PlainText
                  text: strings.t("branches.empty")
                  color: root.foreground
                  opacity: 0.62
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WordWrap
                }

                Repeater {
                  id: branchRepeater
                  model: root.branches
                  delegate: Rectangle {
                    id: branchRow
                    required property var modelData
                    readonly property var branch: modelData
                    property bool hovered: false
                    readonly property bool selected: branchRow.branch.name === root.focusBranch && root.focusBranch.length > 0
                    width: branchColumn.width
                    height: branchBody.implicitHeight + Style.spacing.md
                    radius: Style.space(6)
                    color: branchRow.selected || branchRow.hovered ? Commons.Color.menu.selectedBackground : "transparent"

                    Rectangle {
                      anchors.left: parent.left
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom
                      width: branchRow.selected ? Math.max(3, Style.space(3)) : 0
                      color: Commons.Color.accent
                    }

                    Column {
                      id: branchBody
                      width: parent.width - Style.spacing.md * 2
                      x: Style.spacing.md
                      y: Style.spacing.sm
                      spacing: Style.spacing.xs

                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: branchRow.branch.name || ""
                        color: branchRow.selected ? Commons.Color.accent : root.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        font.weight: branchRow.selected || branchRow.branch.current ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                      }

                      Text {
                        width: parent.width
                        visible: root.viewing.length > 0 && branchRow.branch.name === root.viewing
                        textFormat: Text.PlainText
                        text: strings.t("branch.viewing")
                        color: Commons.Color.accent
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                      }

                      Text {
                        width: parent.width
                        visible: text.length > 0
                        textFormat: Text.PlainText
                        text: branchRow.branch.subject || ""
                        color: root.foreground
                        opacity: 0.62
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }

                      Flow {
                        width: parent.width
                        spacing: Style.spacing.sm

                        Text {
                          visible: branchRow.branch.current === true
                          textFormat: Text.PlainText
                          text: strings.t("branch.current")
                          color: Commons.Color.accent
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                        }
                        Text {
                          visible: (branchRow.branch.upstream || "").length > 0
                          textFormat: Text.PlainText
                          text: branchRow.branch.upstream || ""
                          color: root.foreground
                          opacity: 0.62
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                        }
                        Text {
                          visible: Number(branchRow.branch.ahead) > 0
                          textFormat: Text.PlainText
                          text: strings.tn("branch.ahead", Number(branchRow.branch.ahead) || 0).arg(Commons.I18n.formatNumber(Number(branchRow.branch.ahead) || 0))
                          color: root.foreground
                          opacity: 0.62
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                        }
                        Text {
                          visible: Number(branchRow.branch.behind) > 0
                          textFormat: Text.PlainText
                          text: strings.tn("branch.behind", Number(branchRow.branch.behind) || 0).arg(Commons.I18n.formatNumber(Number(branchRow.branch.behind) || 0))
                          color: root.foreground
                          opacity: 0.62
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                        }
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onEntered: branchRow.hovered = true
                      onExited: branchRow.hovered = false
                      onClicked: root.viewBranch(branchRow.branch.name)
                    }
                  }
                }
              }
            }
          }

          Item {
            id: historyPane
            anchors.left: branchPane.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: Style.spacing.lg

            Row {
              id: historyHeadingRow
              anchors.left: parent.left
              anchors.right: parent.right
              spacing: Style.spacing.sm

              Text {
                id: historyHeading
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: strings.t("history")
                color: root.foreground
                opacity: 0.62
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Rectangle {
                id: focusChip
                visible: root.focusBranch.length > 0
                anchors.verticalCenter: parent.verticalCenter
                width: visible ? focusChipText.width + Style.spacing.sm * 2 : 0
                height: visible ? focusChipText.implicitHeight + Style.spacing.xs : 0
                radius: height / 2
                color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.22)

                Text {
                  id: focusChipText
                  anchors.centerIn: parent
                  width: Math.min(implicitWidth, Style.space(220))
                  textFormat: Text.PlainText
                  text: root.focusBranch
                  color: Commons.Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.weight: Font.DemiBold
                  elide: Text.ElideMiddle
                }
              }
            }

            Flickable {
              id: historyFlick
              anchors.top: historyHeadingRow.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.topMargin: Style.spacing.sm
              clip: true
              contentWidth: width
              contentHeight: historyColumn.implicitHeight
              boundsBehavior: Flickable.StopAtBounds

              Column {
                id: historyColumn
                width: historyFlick.width

                Text {
                  width: parent.width
                  visible: root.commits.length === 0
                  textFormat: Text.PlainText
                  text: strings.t("history.empty")
                  color: root.foreground
                  opacity: 0.62
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WordWrap
                }

                Repeater {
                  model: root.commits
                  delegate: Item {
                    id: commitRow
                    required property var modelData
                    readonly property var commit: modelData
                    property bool hovered: false
                    readonly property bool carriesFocus: root.carries(commitRow.commit.refs, root.focusBranch)
                    width: historyColumn.width
                    height: root.rowHeight

                    Rectangle {
                      anchors.fill: parent
                      radius: Style.space(6)
                      color: commitRow.hovered ? Commons.Color.menu.selectedBackground : "transparent"
                    }

                    Item {
                      id: laneBox
                      anchors.left: parent.left
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom
                      width: Math.max(root.laneWidth, root.laneCount * root.laneWidth)

                      Canvas {
                        anchors.fill: parent
                        property int lane: commitRow.commit.lane || 0
                        property var lineNames: commitRow.commit.lineNames || []
                        property string hoverName: root.hoverBranch
                        property var through: commitRow.commit.through || []
                        property var edges: commitRow.commit.edges || []
                        onPaint: root.paintLanes(getContext("2d"), lane, through, edges, root.laneWidth, height, lineNames, hoverName)
                        Component.onCompleted: requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        onLaneChanged: requestPaint()
                        onLineNamesChanged: requestPaint()
                        onHoverNameChanged: requestPaint()
                        onThroughChanged: requestPaint()
                        onEdgesChanged: requestPaint()
                      }
                    }

                    Text {
                      id: hashText
                      anchors.left: laneBox.right
                      anchors.leftMargin: Style.spacing.md
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(92)
                      textFormat: Text.PlainText
                      text: commitRow.commit.short || ""
                      color: Commons.Color.accent
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }

                    Rectangle {
                      id: focusPill
                      visible: commitRow.carriesFocus
                      anchors.left: hashText.right
                      anchors.leftMargin: visible ? Style.spacing.sm : 0
                      anchors.verticalCenter: parent.verticalCenter
                      width: visible ? focusPillText.width + Style.spacing.sm * 2 : 0
                      height: visible ? focusPillText.implicitHeight + Style.spacing.xs : 0
                      radius: height / 2
                      color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.22)

                      Text {
                        id: focusPillText
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, Style.space(160))
                        textFormat: Text.PlainText
                        text: commitRow.carriesFocus ? root.focusBranch : ""
                        color: Commons.Color.accent
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.weight: Font.DemiBold
                        elide: Text.ElideMiddle
                      }
                    }

                    Text {
                      id: refText
                      anchors.left: focusPill.right
                      anchors.leftMargin: text.length > 0 ? Style.spacing.sm : 0
                      anchors.verticalCenter: parent.verticalCenter
                      width: text.length > 0 ? Math.min(implicitWidth, Style.space(150)) : 0
                      textFormat: Text.PlainText
                      text: root.refsBeside(commitRow.commit.refs, root.focusBranch)
                      color: root.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }

                    Text {
                      id: whenText
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: root.dateText(commitRow.commit.date)
                      color: root.foreground
                      opacity: 0.62
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      anchors.left: refText.right
                      anchors.leftMargin: Style.spacing.sm
                      anchors.right: whenText.left
                      anchors.rightMargin: Style.spacing.sm
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: commitRow.commit.subject || ""
                      color: root.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                    }

                    MouseArea {
                      anchors.left: laneBox.right
                      anchors.right: parent.right
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onEntered: commitRow.hovered = true
                      onExited: commitRow.hovered = false
                      onClicked: root.openCommit(commitRow.commit.hash)
                    }

                    MouseArea {
                      id: lineHover
                      z: 2
                      anchors.left: parent.left
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom
                      width: laneBox.width
                      hoverEnabled: true
                      cursorShape: lineHover.branch.length > 0 && root.localBranch(lineHover.branch) ? Qt.PointingHandCursor : Qt.ArrowCursor
                      property int column: {
                        if (!containsMouse || root.laneWidth <= 0)
                          return -1
                        return Math.max(0, Math.floor(mouseX / root.laneWidth))
                      }
                      property string branch: {
                        if (column < 0)
                          return ""
                        var names = commitRow.commit.lineNames || []
                        return String(names[column] || "")
                      }
                      onEntered: {
                        commitRow.hovered = true
                        root.noteLineHover(branch, commitRow)
                      }
                      onPositionChanged: {
                        if (containsMouse)
                          root.noteLineHover(branch, commitRow)
                      }
                      onExited: {
                        commitRow.hovered = false
                        Qt.callLater(function() { root.clearLineHover(commitRow) })
                      }
                      onClicked: {
                        if (branch.length > 0 && root.localBranch(branch))
                          root.selectBranch(branch)
                      }
                    }

                    Rectangle {
                      id: lineChip
                      z: 3
                      visible: lineHover.containsMouse && lineHover.branch.length > 0
                      x: lineHover.column * root.laneWidth + root.laneWidth
                      anchors.verticalCenter: parent.verticalCenter
                      width: visible ? lineChipText.width + Style.spacing.sm * 2 : 0
                      height: visible ? lineChipText.implicitHeight + Style.spacing.xs : 0
                      radius: height / 2
                      color: Qt.rgba(root.background.r, root.background.g, root.background.b, 1)
                      border.width: Math.max(1, Style.space(1))
                      border.color: Commons.Color.accent

                      Text {
                        id: lineChipText
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, Style.space(180))
                        textFormat: Text.PlainText
                        text: lineHover.branch
                        color: Commons.Color.accent
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.weight: Font.DemiBold
                        elide: Text.ElideMiddle
                      }
                    }
                  }
                }
              }
            }
          }
        }

        Item {
          id: detailPane
          anchors.top: messageText.visible ? messageText.bottom : (viewLabel.visible ? viewLabel.bottom : dirtyLabel.bottom)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: hint.top
          anchors.topMargin: Style.spacing.lg
          anchors.bottomMargin: Style.spacing.md
          visible: root.reason === "" && root.detailHash.length > 0
          readonly property var commit: root.detail
          readonly property var parents: (commit && commit.parents) ? commit.parents : []

          Item {
            id: backRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.max(backLabel.implicitHeight, hashLabel.implicitHeight)

            Text {
              id: backLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: strings.t("detail.back")
              color: Commons.Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            Text {
              id: hashLabel
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: detailPane.commit ? String(detailPane.commit.short || "") : root.detailHash.substring(0, 12)
              color: root.foreground
              opacity: 0.62
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: backLabel.implicitWidth + Style.spacing.lg
              cursorShape: Qt.PointingHandCursor
              onClicked: root.back()
            }
          }

          Flickable {
            id: detailFlick
            anchors.top: backRow.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.topMargin: Style.spacing.md
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: Math.max(width, detailColumn.childrenRect.width)
            contentHeight: detailColumn.height

            Column {
              id: detailColumn
              width: detailFlick.width
              spacing: Style.spacing.sm

              Text {
                width: detailFlick.width
                visible: root.detailLoading
                textFormat: Text.PlainText
                text: strings.t("detail.loading")
                color: root.foreground
                opacity: 0.62
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }

              Text {
                width: detailFlick.width
                visible: root.detailError.length > 0 && !root.detailLoading
                textFormat: Text.PlainText
                text: strings.t("detail.error")
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }

              Text {
                width: detailFlick.width
                visible: detailPane.commit !== null && !root.detailLoading
                textFormat: Text.PlainText
                text: detailPane.commit ? String(detailPane.commit.subject || "") : ""
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
              }

              Text {
                width: detailFlick.width
                visible: text.length > 0 && !root.detailLoading
                textFormat: Text.PlainText
                text: root.personText(detailPane.commit)
                color: root.foreground
                opacity: 0.62
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Text {
                width: detailFlick.width
                visible: detailPane.commit !== null && !root.detailLoading && text.length > 0
                textFormat: Text.PlainText
                text: detailPane.commit ? root.dateText(detailPane.commit.date || "") : ""
                color: root.foreground
                opacity: 0.62
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Text {
                width: detailFlick.width
                visible: detailPane.commit && detailPane.commit.merge === true && !root.detailLoading
                textFormat: Text.PlainText
                text: strings.t("detail.merge")
                color: root.foreground
                opacity: 0.62
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Text {
                visible: detailPane.parents.length > 0 && !root.detailLoading
                textFormat: Text.PlainText
                text: strings.t("detail.parents")
                color: root.foreground
                opacity: 0.62
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Flow {
                width: detailFlick.width
                spacing: Style.spacing.md
                visible: detailPane.parents.length > 0 && !root.detailLoading

                Repeater {
                  model: detailPane.parents.length
                  delegate: Text {
                    id: parentLink
                    required property int index
                    readonly property string parentHash: (index >= 0 && index < detailPane.parents.length) ? String(detailPane.parents[index] || "") : ""
                    textFormat: Text.PlainText
                    text: parentHash.substring(0, 12)
                    color: Commons.Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.openCommit(parentLink.parentHash)
                    }
                  }
                }
              }

              Text {
                width: detailFlick.width
                visible: detailPane.commit && String(detailPane.commit.body || "").trim().length > 0 && !root.detailLoading
                textFormat: Text.PlainText
                text: detailPane.commit ? String(detailPane.commit.body || "").trim() : ""
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }

              Text {
                visible: detailPane.commit && String(detailPane.commit.stat || "").trim().length > 0 && !root.detailLoading
                textFormat: Text.PlainText
                text: strings.t("detail.files")
                color: root.foreground
                opacity: 0.62
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Text {
                visible: detailPane.commit && String(detailPane.commit.stat || "").trim().length > 0 && !root.detailLoading
                textFormat: Text.PlainText
                text: detailPane.commit ? String(detailPane.commit.stat || "").trim() : ""
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Text {
                visible: detailPane.commit !== null && !root.detailLoading
                textFormat: Text.PlainText
                text: strings.t("detail.diff")
                color: root.foreground
                opacity: 0.62
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Text {
                width: detailFlick.width
                visible: detailPane.commit !== null && !root.detailLoading && root.diffLines.length === 0
                textFormat: Text.PlainText
                text: strings.t("detail.empty")
                color: root.foreground
                opacity: 0.62
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }

              Column {
                spacing: 0
                width: Math.max(implicitWidth, detailFlick.width)

                Repeater {
                  model: root.diffLines.length
                  delegate: Item {
                    id: diffRow
                    required property int index
                    readonly property string line: (index >= 0 && index < root.diffLines.length) ? String(root.diffLines[index]) : ""
                    readonly property string kind: root.diffKind(line)
                    width: Math.max(lineText.implicitWidth + Style.spacing.sm * 2, detailFlick.width)
                    implicitWidth: width
                    height: Math.max(lineText.implicitHeight, 1)

                    Rectangle {
                      anchors.fill: parent
                      color: root.diffBackground(diffRow.kind)
                    }

                    Text {
                      id: lineText
                      x: Style.spacing.sm
                      textFormat: Text.PlainText
                      text: diffRow.line.length > 0 ? diffRow.line : " "
                      color: root.diffTextColor(diffRow.kind)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }

              Text {
                width: detailFlick.width
                visible: detailPane.commit && (detailPane.commit.truncated === true || root.diffCut) && !root.detailLoading
                textFormat: Text.PlainText
                text: strings.t("detail.truncated")
                color: root.foreground
                opacity: 0.62
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }
        }

        Text {
          id: hint
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          textFormat: Text.PlainText
          text: root.hintText
          color: root.foreground
          opacity: 0.5
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }
}
