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

// Name the vertical lines from local branch tips. A name continues down the
// first parent, and back up the line that was waiting for that tip.
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
    var refName = ""
    for (r = 0; r < refs.length; r++) {
      if (known[String(refs[r])]) {
        refName = String(refs[r])
        break
      }
    }
    var lane = Number(commit.lane) || 0
    if (refName)
      carried[lane] = refName
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
}

if (typeof module !== "undefined" && typeof require !== "undefined" && require.main === module) {
  runTests()
  module.exports = { layout: layout, labelLines: labelLines }
} else if (typeof module !== "undefined") {
  module.exports = { layout: layout, labelLines: labelLines }
}
