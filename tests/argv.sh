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

secret_branch='zzBranchSecretzz'
secret_subject='zzSubjectSecretzz'
secret_body='zzBodySecretzz'
secret_patch='zzPatchSecretzz'

repo=$tmp/argv-repo
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email git-tree@example.com
git -C "$repo" config user.name git-tree
git -C "$repo" config commit.gpgsign false
printf '%s\n' start > "$repo/file"
git -C "$repo" add file
git -C "$repo" commit -q -m start
git -C "$repo" switch -q -c "$secret_branch"
printf '%s\n' "$secret_patch" >> "$repo/file"
git -C "$repo" add file
git -C "$repo" commit -q -m "$(printf '%s\n\n%s\n' "$secret_subject" "$secret_body")"
hash=$(git -C "$repo" rev-parse HEAD)
title=$(basename "$repo")

real_git=$(command -v git)
real_jq=$(command -v jq)
bin=$tmp/bin
mkdir -p "$bin"
log=$tmp/argv.log
: > "$log"
export GIT_TREE_ARGV_LOG=$log

cat > "$bin/git" <<EOF
#!/bin/bash
{
  printf '%s' "\$0"
  for arg in "\$@"; do
    printf '\\0%s' "\$arg"
  done
  printf '\\n'
} >> "\$GIT_TREE_ARGV_LOG"
exec $real_git "\$@"
EOF
cat > "$bin/jq" <<EOF
#!/bin/bash
{
  printf '%s' "\$0"
  for arg in "\$@"; do
    printf '\\0%s' "\$arg"
  done
  printf '\\n'
} >> "\$GIT_TREE_ARGV_LOG"
exec $real_jq "\$@"
EOF
chmod +x "$bin/git" "$bin/jq"

proc=$tmp/proc.log
: > "$proc"
flag=$tmp/sampling
touch "$flag"
(
  while [[ -f $flag ]]; do
    for cmdf in /proc/[0-9]*/cmdline; do
      [[ -r $cmdf ]] || continue
      tr '\0' ' ' < "$cmdf" 2>/dev/null || true
      printf '\n'
    done
    sleep 0.02
  done
) >> "$proc" &
sampler=$!

graph=$(PATH="$bin:$PATH" "$helper" --path "$repo" --title "$title" --class folio)
view=$(PATH="$bin:$PATH" GIT_TREE_VIEW="$secret_branch" "$helper" --path "$repo" --title "$title" --class folio)
commit=$(PATH="$bin:$PATH" "$helper" --path "$repo" --title "$title" --class folio --commit "$hash")

rm -f "$flag"
wait "$sampler" || true

needles=$tmp/needles
printf '%s\n' "$secret_branch" "$secret_subject" "$secret_body" "$secret_patch" > "$needles"
labels=(branch subject body patch)
leaked=0
i=0
while IFS= read -r needle; do
  if grep -a -F -q -e "$needle" "$log" "$proc"; then
    echo "argv: FAIL ${labels[$i]} appeared in process arguments" >&2
    leaked=1
  fi
  i=$((i + 1))
done < "$needles"

if [[ $leaked -ne 0 ]]; then
  echo "argv: failed" >&2
  exit 1
fi

[[ -s $log ]] || { echo "argv: no git or jq arguments were logged" >&2; exit 1; }

jq -e --arg branch "$secret_branch" --arg subject "$secret_subject" '
  .ok == true and .branch == $branch and ([.commits[].subject] | index($subject)) != null
' <<<"$graph" >/dev/null || { echo "argv: graph JSON lost the repository text" >&2; exit 1; }

jq -e --arg branch "$secret_branch" --arg subject "$secret_subject" '
  .ok == true and .viewing == $branch and .commits[0].subject == $subject
' <<<"$view" >/dev/null || { echo "argv: view JSON lost the repository text" >&2; exit 1; }

jq -e --arg subject "$secret_subject" --arg body "$secret_body" --arg patch "$secret_patch" '
  .ok == true and .kind == "commit" and .subject == $subject
  and (.body | contains($body)) and (.diff | contains($patch))
' <<<"$commit" >/dev/null || { echo "argv: commit JSON lost the repository text" >&2; exit 1; }

echo "argv: ok"
