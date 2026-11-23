#!/bin/bash

set -euo pipefail

root=$(dirname "$(readlink -f "$0")")
root=$(dirname "$root")
helper=${GIT_TREE_HELPER:-$root/helpers/snapshot}

export GIT_TERMINAL_PROMPT=0
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

tmp=$(mktemp -d)
httpd_pid=
cleanup() {
  if [[ -n ${httpd_pid:-} ]]; then
    kill "$httpd_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

mark=$tmp/mark.sh
printf '%s\n' '#!/bin/bash' 'if [[ -n ${MARKER:-} ]]; then printf x >> "$MARKER"; fi' 'exit 0' > "$mark"
chmod +x "$mark"

fail=0

new_repo() {
  local name=$1
  local repo=$tmp/$name
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email git-tree@example.com
  git -C "$repo" config user.name git-tree
  git -C "$repo" config commit.gpgsign false
  printf '%s\n' start > "$repo/file"
  git -C "$repo" add file
  git -C "$repo" commit -q -m start
  git -C "$repo" switch -q -c side
  printf '%s\n' side > "$repo/sidefile"
  git -C "$repo" add sidefile
  git -C "$repo" commit -q -m side
  git -C "$repo" switch -q main
  printf '%s\n' "$repo"
}

run_one() {
  local label=$1
  shift
  local expect='.ok == true'
  if [[ ${1:-} == --expect ]]; then
    expect=$2
    shift 2
  fi
  local marker=$tmp/marker
  local out err
  rm -f "$marker"
  err=$tmp/err
  out=$(MARKER=$marker "$@" 2>"$err" || true)
  if [[ -e $marker ]]; then
    echo "hostile: FAIL $label marker" >&2
    fail=1
    return
  fi
  if ! jq -e "$expect" <<<"$out" >/dev/null 2>&1; then
    echo "hostile: FAIL $label not-ok $(jq -r '.reason // "bad-json"' <<<"$out" 2>/dev/null || true)" >&2
    fail=1
    return
  fi
  echo "hostile: ok $label"
}

run_paths() {
  local repo=$1
  local title hash
  title=$(basename "$repo")
  hash=$(git -C "$repo" rev-parse HEAD)
  run_one "$2 graph" "$helper" --path "$repo" --title "$title" --class folio
  run_one "$2 view" env GIT_TREE_VIEW=side "$helper" --path "$repo" --title "$title" --class folio
  run_one "$2 commit" "$helper" --path "$repo" --title "$title" --class folio --commit "$hash"
}

repo=$(new_repo fsmonitor)
git -C "$repo" config core.fsmonitor "$mark"
printf '%s\n' dirty >> "$repo/file"
run_paths "$repo" fsmonitor

repo=$(new_repo filter-clean)
printf '%s\n' '* filter=evil' > "$repo/.gitattributes"
git -C "$repo" add .gitattributes
git -C "$repo" commit -q -m attrs
git -C "$repo" config filter.evil.clean "$mark"
git -C "$repo" config filter.evil.required true
printf '%s\n' dirty >> "$repo/file"
run_paths "$repo" filter-clean

repo=$(new_repo filter-process)
printf '%s\n' '* filter=evil' > "$repo/.gitattributes"
git -C "$repo" add .gitattributes
git -C "$repo" commit -q -m attrs
git -C "$repo" config filter.evil.process "$mark"
printf '%s\n' dirty >> "$repo/file"
run_paths "$repo" filter-process

repo=$(new_repo info-filter)
mkdir -p "$repo/.git/info"
printf '%s\n' '* filter=evil' > "$repo/.git/info/attributes"
git -C "$repo" config filter.evil.clean "$mark"
git -C "$repo" config filter.evil.required true
printf '%s\n' dirty >> "$repo/file"
run_paths "$repo" info-filter

repo=$(new_repo diff-external)
git -C "$repo" config diff.external "$mark"
run_paths "$repo" diff-external

repo=$(new_repo textconv)
printf '%s\n' '* diff=evil' > "$repo/.gitattributes"
git -C "$repo" add .gitattributes
git -C "$repo" commit -q -m attrs
git -C "$repo" config diff.evil.textconv "$mark"
run_paths "$repo" textconv

repo=$(new_repo info-textconv)
mkdir -p "$repo/.git/info"
printf '%s\n' '* diff=evil' > "$repo/.git/info/attributes"
git -C "$repo" config diff.evil.textconv "$mark"
run_paths "$repo" info-textconv

repo=$(new_repo diff-command)
printf '%s\n' '* diff=evil' > "$repo/.gitattributes"
git -C "$repo" add .gitattributes
git -C "$repo" commit -q -m attrs
git -C "$repo" config diff.evil.command "$mark"
run_paths "$repo" diff-command

repo=$(new_repo pager)
git -C "$repo" config core.pager "$mark"
git -C "$repo" config pager.status "$mark"
git -C "$repo" config pager.log "$mark"
git -C "$repo" config pager.show "$mark"
run_paths "$repo" pager

repo=$(new_repo alias)
git -C "$repo" config alias.status "!$mark"
git -C "$repo" config alias.log "!$mark"
git -C "$repo" config alias.show "!$mark"
git -C "$repo" config alias.config "!$mark"
run_paths "$repo" alias

repo=$(new_repo hooks)
mkdir -p "$repo/.git/hooks"
cp "$mark" "$repo/.git/hooks/post-index-change"
chmod +x "$repo/.git/hooks/post-index-change"
printf '%s\n' dirty >> "$repo/file"
run_paths "$repo" hooks

inc=$tmp/inc-fs.gitconfig
printf '%s\n' '[core]' "	fsmonitor = $mark" > "$inc"
repo=$(new_repo include-path)
git -C "$repo" config include.path "$inc"
run_paths "$repo" include-path

repo=$(new_repo include-if)
git -C "$repo" config includeIf."gitdir:**".path "$inc"
run_paths "$repo" include-if

inc_filter=$tmp/inc-filter.gitconfig
printf '%s\n' '[filter "evil"]' "	clean = $mark" '	required = true' > "$inc_filter"
repo=$(new_repo include-filter)
printf '%s\n' '* filter=evil' > "$repo/.gitattributes"
git -C "$repo" add .gitattributes
git -C "$repo" commit -q -m attrs
git -C "$repo" config include.path "$inc_filter"
printf '%s\n' dirty >> "$repo/file"
run_paths "$repo" include-filter

repo=$(new_repo submodule)
mod=$tmp/mod
mkdir -p "$mod"
git -C "$mod" init -q -b main
git -C "$mod" config user.email git-tree@example.com
git -C "$mod" config user.name git-tree
git -C "$mod" config commit.gpgsign false
printf '%s\n' m > "$mod/f"
git -C "$mod" add f
git -C "$mod" commit -q -m m
git -C "$repo" -c protocol.file.allow=always submodule add "$mod" sub >/dev/null 2>&1
git -C "$repo" commit -q -m 'add sub'
git -C "$repo/sub" config core.fsmonitor "$mark"
printf '%s\n' dirty >> "$repo/sub/f"
git -C "$repo" config submodule.recurse true
run_paths "$repo" submodule

repo=$(new_repo filter-weird-subsection)
mkdir -p "$repo/slash" "$repo/utf" "$repo/space"
printf '%s\n' '* filter=evil!' > "$repo/.gitattributes"
printf '%s\n' '* filter=evil/x' > "$repo/slash/.gitattributes"
printf '%s\n' '* filter=évil' > "$repo/utf/.gitattributes"
printf '%s\n' '* filter=evil name' > "$repo/space/.gitattributes"
printf '%s\n' a > "$repo/file"
printf '%s\n' a > "$repo/slash/file"
printf '%s\n' a > "$repo/utf/file"
printf '%s\n' a > "$repo/space/file"
git -C "$repo" add .gitattributes slash utf space file
git -C "$repo" commit -q -m attrs
git -C "$repo" config filter.evil!.clean "$mark"
git -C "$repo" config filter.evil!.required true
git -C "$repo" config filter.evil/x.process "$mark"
git -C "$repo" config "filter.evil name.clean" "$mark"
git -C "$repo" config "filter.evil name.required" true
git -C "$repo" config "filter.évil.clean" "$mark"
git -C "$repo" config "filter.évil.required" true
printf '%s\n' dirty >> "$repo/file"
printf '%s\n' dirty >> "$repo/slash/file"
printf '%s\n' dirty >> "$repo/utf/file"
printf '%s\n' dirty >> "$repo/space/file"
title=$(basename "$repo")
hash=$(git -C "$repo" rev-parse HEAD)
run_one "filter-weird-subsection graph" env LC_ALL=C "$helper" --path "$repo" --title "$title" --class folio
run_one "filter-weird-subsection view" env LC_ALL=C GIT_TREE_VIEW=side "$helper" --path "$repo" --title "$title" --class folio
run_one "filter-weird-subsection commit" env LC_ALL=C "$helper" --path "$repo" --title "$title" --class folio --commit "$hash"

promisor_remote() {
  local repo=$1
  local url=$2
  local blob
  blob=$(git -C "$repo" rev-parse HEAD:file)
  rm -f "$repo/.git/objects/${blob:0:2}/${blob:2}"
  git -C "$repo" config remote.origin.url "$url"
  git -C "$repo" config remote.origin.promisor true
  git -C "$repo" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  git -C "$repo" config extensions.partialclone origin
}

run_promisor() {
  local repo=$1
  local label=$2
  local title hash
  title=$(basename "$repo")
  hash=$(git -C "$repo" rev-parse HEAD)
  run_one "$label graph" --expect '.ok == true and (.commits | length) > 0' \
    "$helper" --path "$repo" --title "$title" --class folio
  run_one "$label view" --expect '.ok == true and .viewing == "side" and (.commits | length) > 0' \
    env GIT_TREE_VIEW=side "$helper" --path "$repo" --title "$title" --class folio
  run_one "$label commit" --expect '.ok == true and .kind == "commit" and (.diff | length) == 0' \
    "$helper" --path "$repo" --title "$title" --class folio --commit "$hash"
}

repo=$(new_repo promisor-ssh)
promisor_remote "$repo" 'ssh://127.0.0.1/no-such-repo'
git -C "$repo" config core.sshCommand "$mark"
run_promisor "$repo" promisor-ssh

repo=$(new_repo promisor-proxy)
promisor_remote "$repo" 'git://127.0.0.1/no-such-repo'
git -C "$repo" config core.gitProxy "$mark"
run_promisor "$repo" promisor-proxy

portf=$tmp/port
python3 - "$portf" << 'PY' &
import http.server
import sys
portf = sys.argv[1]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="git"')
        self.end_headers()
    def do_POST(self):
        self.do_GET()
    def log_message(self, fmt, *args):
        return
server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
with open(portf, "w") as handle:
    handle.write(str(server.server_address[1]))
server.serve_forever()
PY
httpd_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [[ -s $portf ]] && break
  sleep 0.1
done
[[ -s $portf ]] || { echo "hostile: FAIL promisor-http server" >&2; exit 1; }
port=$(cat "$portf")
repo=$(new_repo promisor-http)
promisor_remote "$repo" "http://127.0.0.1:${port}/repo.git"
git -C "$repo" config credential.helper "$mark"
run_promisor "$repo" promisor-http

if [[ $fail -ne 0 ]]; then
  echo "hostile: failed" >&2
  exit 1
fi
echo "hostile: ok"
