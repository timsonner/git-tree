#!/bin/bash

set -euo pipefail

root=$(dirname "$(readlink -f "$0")")
root=$(dirname "$root")
helper=$root/helpers/snapshot

export GIT_TERMINAL_PROMPT=0
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

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
  if ! jq -e '.ok == true' <<<"$out" >/dev/null 2>&1; then
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

if [[ $fail -ne 0 ]]; then
  echo "hostile: failed" >&2
  exit 1
fi
echo "hostile: ok"
