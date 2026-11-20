// Newest-first lane layout for a git log. Each commit gets a column, a list
// of columns that pass through the row, and edges to its parents.

function layout(commits) {
  var list = []
  var i
  var p
  for (i = 0; i < commits.length; i++) {
    var src = commits[i] || {}
    var rawParents = src.parents || []
    var parents = []
    for (p = 0; p < rawParents.length; p++) {
      if (rawParents[p])
        parents.push(String(rawParents[p]))
    }
    list.push({
      hash: String(src.hash || ""),
      short: String(src.short || ""),
      parents: parents,
      refs: src.refs || [],
      subject: String(src.subject || ""),
      date: String(src.date || ""),
      lane: 0,
      through: [],
      edges: [],
      width: 1
    })
  }

  var present = {}
  for (i = 0; i < list.length; i++) {
    if (list[i].hash)
      present[list[i].hash] = true
  }

  var lanes = []

  function occupy(hash) {
    var n
    for (n = 0; n < lanes.length; n++) {
      if (lanes[n] === null) {
        lanes[n] = hash
        return n
      }
    }
    lanes.push(hash)
    return lanes.length - 1
  }

  var maxWidth = 1
  for (i = 0; i < list.length; i++) {
    var commit = list[i]
    var incoming = []
    var n
    for (n = 0; n < lanes.length; n++) {
      if (lanes[n] === commit.hash)
        incoming.push(n)
    }
    var col = incoming.length > 0 ? incoming[0] : occupy(commit.hash)
    var through = []
    for (n = 0; n < lanes.length; n++) {
      if (lanes[n])
        through.push(n)
    }
    var known = []
    for (p = 0; p < commit.parents.length; p++) {
      if (present[commit.parents[p]])
        known.push(commit.parents[p])
    }
    var first = known.length > 0 ? known[0] : null
    for (n = 0; n < incoming.length; n++)
      lanes[incoming[n]] = null
    while (col >= lanes.length)
      lanes.push(null)
    var edges = []
    if (first) {
      lanes[col] = first
      edges.push({ from: col, to: col, kind: "down" })
    }
    for (n = 1; n < incoming.length; n++)
      edges.push({ from: incoming[n], to: col, kind: "merge" })
    for (p = 1; p < known.length; p++) {
      var dest = -1
      for (n = 0; n < lanes.length; n++) {
        if (lanes[n] === known[p]) {
          dest = n
          break
        }
      }
      if (dest < 0)
        dest = occupy(known[p])
      edges.push({ from: col, to: dest, kind: "branch" })
    }
    commit.parents = known
    commit.lane = col
    commit.through = through
    commit.edges = edges
    var width = Math.max(lanes.length, col + 1)
    commit.width = width
    if (width > maxWidth)
      maxWidth = width
  }

  return { commits: list, width: maxWidth }
}

function ignoredRef(name) {
  if (!name || name === "HEAD")
    return true
  return name.length >= 5 && name.lastIndexOf("/HEAD") === name.length - 5
}

// Git's default merge subject names the branch that was merged. The branch
// ref is often already deleted, so the side commits have no decoration.
function mergedBranchName(subject) {
  var text = String(subject || "")
  var pull = /^Merge pull request #[0-9]+ from [^ ]+\/(.+)$/.exec(text)
  if (pull && pull[1])
    return pull[1]
  var remote = /^Merge remote-tracking branch '([^']+)'/.exec(text)
  if (remote && remote[1])
    return remote[1]
  var named = /^Merge branch '([^']+)'/.exec(text)
  if (named && named[1])
    return named[1]
  return ""
}

function labelAbove(commits, index, lane, name) {
  var j
  for (j = index - 1; j >= 0; j--) {
    var prev = commits[j]
    var prevThrough = prev.through || []
    var seen = false
    var t
    for (t = 0; t < prevThrough.length; t++) {
      if (prevThrough[t] === lane)
        seen = true
    }
    if (!seen)
      break
    if (Number(prev.lane) === lane)
      break
    if (!prev.lineNames)
      prev.lineNames = []
    if (prev.lineNames[lane])
      break
    prev.lineNames[lane] = name
  }
}

// After ref labels, name the unlabeled side of a merge from its subject.
// Stop at the first parent, at a commit already labeled, or back on the
// merge's own lane.
function labelMergedLines(commits) {
  var indexOf = {}
  var i
  for (i = 0; i < commits.length; i++) {
    if (commits[i].hash)
      indexOf[commits[i].hash] = i
  }
  for (i = 0; i < commits.length; i++) {
    var commit = commits[i]
    var parents = commit.parents || []
    if (parents.length < 2)
      continue
    var name = mergedBranchName(commit.subject)
    if (!name)
      continue
    var base = String(parents[0] || "")
    var mergeLane = Number(commit.lane) || 0
    var p
    for (p = 1; p < parents.length; p++) {
      var hash = String(parents[p] || "")
      var guard = 0
      var first = true
      while (hash && indexOf[hash] !== undefined && guard < commits.length) {
        guard++
        if (hash === base)
          break
        var current = commits[indexOf[hash]]
        var sideLane = Number(current.lane) || 0
        if (!first && sideLane === mergeLane)
          break
        if (!current.lineNames)
          current.lineNames = []
        if (current.lineNames[sideLane])
          break
        current.lineNames[sideLane] = name
        if (first)
          labelAbove(commits, indexOf[hash], sideLane, name)
        first = false
        var next = current.parents && current.parents[0]
        hash = next ? String(next) : ""
      }
    }
  }
}

// Name the vertical lines from branch tips. A local name wins. A remote
// name fills a line that has none. A name continues down the first parent,
// and back up the line that was waiting for that tip.
function labelLines(commits, branchNames) {
  var known = {}
  var names = branchNames || []
  var i
  var r
  for (i = 0; i < names.length; i++) {
    if (names[i])
      known[String(names[i])] = true
  }
  var carried = []
  for (i = 0; i < commits.length; i++) {
    var commit = commits[i]
    var refs = commit.refs || []
    var localName = ""
    var otherName = ""
    for (r = 0; r < refs.length; r++) {
      var ref = String(refs[r] || "")
      if (ignoredRef(ref))
        continue
      if (known[ref]) {
        localName = ref
        break
      }
      if (!otherName && ref.indexOf("/") >= 0)
        otherName = ref
    }
    var lane = Number(commit.lane) || 0
    var refName = ""
    if (localName) {
      refName = localName
      carried[lane] = localName
    } else if (otherName && !carried[lane]) {
      refName = otherName
      carried[lane] = otherName
    }
    var through = commit.through || []
    var lineNames = []
    var c
    for (c = 0; c < through.length; c++) {
      var column = through[c]
      if (carried[column])
        lineNames[column] = carried[column]
    }
    commit.lineNames = lineNames
    if (refName) {
      var j
      for (j = i - 1; j >= 0; j--) {
        var prev = commits[j]
        var prevThrough = prev.through || []
        var seen = false
        var t
        for (t = 0; t < prevThrough.length; t++) {
          if (prevThrough[t] === lane)
            seen = true
        }
        if (!seen)
          break
        if (Number(prev.lane) === lane)
          break
        if (!prev.lineNames)
          prev.lineNames = []
        if (prev.lineNames[lane])
          break
        prev.lineNames[lane] = refName
      }
    }
    var continues = false
    var edges = commit.edges || []
    var e
    for (e = 0; e < edges.length; e++) {
      var edge = edges[e]
      if (!edge)
        continue
      if (edge.kind === "merge")
        carried[edge.from] = ""
      if (edge.kind === "down")
        continues = true
    }
    if (!continues)
      carried[lane] = ""
  }
  labelMergedLines(commits)
  return commits
}

function assertTest(cond, message) {
  if (!cond)
    throw new Error(message)
}

function runTests() {
  var linear = layout([
    { hash: "c3", parents: ["c2"] },
    { hash: "c2", parents: ["c1"] },
    { hash: "c1", parents: [] }
  ])
  assertTest(linear.width === 1, "linear history uses one lane")
  assertTest(linear.commits[0].lane === 0 && linear.commits[2].lane === 0, "linear lanes stay on column 0")
  assertTest(linear.commits[0].edges.length === 1 && linear.commits[0].edges[0].kind === "down", "linear commit links downward")
  assertTest(linear.commits[2].edges.length === 0, "root commit has no parent edge")

  var branched = layout([
    { hash: "a", parents: ["base"] },
    { hash: "b", parents: ["base"] },
    { hash: "base", parents: [] }
  ])
  assertTest(branched.width >= 2, "two tips of one parent use two lanes")
  assertTest(branched.commits[0].lane !== branched.commits[1].lane, "sibling tips do not share a lane")

  var merged = layout([
    { hash: "m", parents: ["a", "b"] },
    { hash: "a", parents: ["base"] },
    { hash: "b", parents: ["base"] },
    { hash: "base", parents: [] }
  ])
  assertTest(merged.commits[0].edges.length === 2, "a merge commit has two parent edges")
  assertTest(merged.width >= 2, "a merge uses more than one lane")

  var named = layout([
    { hash: "m", parents: ["a", "b"], refs: ["main"] },
    { hash: "a", parents: ["base"], refs: [] },
    { hash: "b", parents: ["base"], refs: ["feature"] },
    { hash: "base", parents: [], refs: [] }
  ])
  labelLines(named.commits, ["main", "feature", "unused"])
  var mainLane = named.commits[0].lane
  var featureLane = named.commits[2].lane
  assertTest(named.commits[0].lineNames[mainLane] === "main", "the branch tip labels its line")
  assertTest(named.commits[1].lineNames[mainLane] === "main", "the name continues down the first parent")
  assertTest(named.commits[2].lineNames[featureLane] === "feature", "a side branch labels its own line")
  assertTest(featureLane !== mainLane, "the side branch is a different line")
  var tagged = layout([{ hash: "t", parents: [], refs: ["v1.0", "main"] }])
  labelLines(tagged.commits, ["main"])
  assertTest(tagged.commits[0].lineNames[0] === "main", "a tag does not hide the branch name")

  var remote = layout([
    { hash: "M", parents: ["B"], refs: ["main"] },
    { hash: "F", parents: ["B"], refs: ["origin/feature"] },
    { hash: "B", parents: [], refs: [] }
  ])
  labelLines(remote.commits, ["main"])
  var remoteLane = remote.commits[1].lane
  assertTest(remote.commits[1].lineNames[remoteLane] === "origin/feature", "a remote tip labels its line")
  assertTest(remoteLane !== remote.commits[0].lane, "the remote tip is not on the local line")

  var both = layout([{ hash: "T", parents: [], refs: ["origin/main", "main"] }])
  labelLines(both.commits, ["main"])
  assertTest(both.commits[0].lineNames[0] === "main", "a local branch wins over its remote")

  var headOnly = layout([{ hash: "H", parents: [], refs: ["origin/HEAD"] }])
  labelLines(headOnly.commits, [])
  assertTest(!headOnly.commits[0].lineNames[0], "origin/HEAD does not label a line")

  var kept = layout([
    { hash: "M", parents: ["old"], refs: ["main"] },
    { hash: "old", parents: [], refs: ["v1.0"] }
  ])
  labelLines(kept.commits, ["main"])
  assertTest(kept.commits[1].lineNames[0] === "main", "a tag does not rename the line under it")

  var merged = layout([
    { hash: "M", parents: ["A", "F2"], refs: ["main"], subject: "Merge pull request #1 from timsonner/feature" },
    { hash: "F2", parents: ["F1"], refs: [], subject: "side" },
    { hash: "A", parents: ["B"], refs: [], subject: "main work" },
    { hash: "F1", parents: ["B"], refs: [], subject: "side work" },
    { hash: "B", parents: [], refs: [], subject: "base" }
  ])
  labelLines(merged.commits, ["main"])
  var sideLane = merged.commits[1].lane
  assertTest(merged.commits[1].lineNames[sideLane] === "feature", "a merged pull request labels its side commits")
  assertTest(merged.commits[3].lineNames[merged.commits[3].lane] === "feature", "the merged name continues down that side line")
  assertTest(merged.commits[2].lineNames[merged.commits[2].lane] === "main", "the merge does not rename the first parent")
  assertTest(merged.commits[4].lineNames[merged.commits[4].lane] === "main", "the merge stops at the shared parent")
}

if (typeof module !== "undefined" && typeof require !== "undefined" && require.main === module) {
  runTests()
  module.exports = { layout: layout, labelLines: labelLines }
} else if (typeof module !== "undefined") {
  module.exports = { layout: layout, labelLines: labelLines }
}
