#!/usr/bin/env bash
set -Eeuo pipefail

UPSTREAM_URL="https://github.com/HMCL-dev/HMCL.git"
WORK_DIR="${WORK_DIR:-$PWD/hmcl}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/drop_commits.py"
OUTPUT_DIR="${OUTPUT_DIR:-$PWD/release-assets}"

TARGETS=(
  "583e004d718102ae4489aa3f64bcde0c0161d000"
  "8827fd06d8ea8bcd899e54f76004f63a447e2601"
)

echo "==> Preparing source code"

if [[ -d "$WORK_DIR/.git" ]]; then
  git -C "$WORK_DIR" fetch origin \
    --prune --tags
else
  git clone "$UPSTREAM_URL" "$WORK_DIR"
fi

# 获取最新默认分支名称，避免硬编码 main。
DEFAULT_BRANCH="$(
  git -C "$WORK_DIR" symbolic-ref \
    --short refs/remotes/origin/HEAD 2>/dev/null \
    | sed 's#^origin/##' || true
)"

if [[ -z "$DEFAULT_BRANCH" ]]; then
  DEFAULT_BRANCH="main"
fi

git -C "$WORK_DIR" fetch origin \
  "$DEFAULT_BRANCH"

git -C "$WORK_DIR" checkout \
  -B rebuild-base "origin/$DEFAULT_BRANCH"

# 确保两个提交均存在，并且属于当前分支历史。
for commit in "${TARGETS[@]}"; do
  git -C "$WORK_DIR" cat-file \
    -e "${commit}^{commit}"

  git -C "$WORK_DIR" merge-base \
    --is-ancestor "$commit" HEAD
done

echo "==> Removing selected commits from local history"

# Rebase only the tail that contains the targets, not the whole history.
# A full `--root` re-apply rewrites ~5000+ commits and can stall on a
# committed .gitattributes line-ending change mid-history ("local changes
# would be overwritten"). The base is the first-parent of the OLDEST target
# (the target that is an ancestor of every other target; a chain). Divergent
# history (no single oldest) falls back to `--root`.
OLDEST=""
for t in "${TARGETS[@]}"; do
  covers_all=true
  for other in "${TARGETS[@]}"; do
    [[ "$t" == "$other" ]] && continue
    git -C "$WORK_DIR" merge-base --is-ancestor "$t" "$other" \
      || { covers_all=false; break; }
  done
  if [[ "$covers_all" == true ]]; then
    OLDEST="$t"
    break
  fi
done

REBASE_BASE=""
if [[ -n "$OLDEST" ]]; then
  REBASE_BASE="$(git -C "$WORK_DIR" rev-parse "${OLDEST}^" 2>/dev/null || true)"
fi

export GIT_SEQUENCE_EDITOR="python3 \"$PYTHON_SCRIPT\""

if [[ -n "$REBASE_BASE" ]]; then
  git -C "$WORK_DIR" \
    -c core.editor=true \
    rebase -i --rebase-merges "$REBASE_BASE"
else
  # Divergent history or root-level target: full rewrite.
  git -C "$WORK_DIR" \
    -c core.editor=true \
    rebase -i --rebase-merges --root
fi

unset GIT_SEQUENCE_EDITOR

echo "==> Verifying rewritten history"

for commit in "${TARGETS[@]}"; do
  if git -C "$WORK_DIR" merge-base \
      --is-ancestor "$commit" HEAD; then
    echo "ERROR: commit remains in ancestry: $commit" >&2
    exit 1
  fi
done

echo "==> Building HMCL"

chmod +x "$WORK_DIR/gradlew"

(
  cd "$WORK_DIR"
  ./gradlew --no-daemon clean makeExecutables
)

echo "==> Preparing release assets"

# makeExecutables runs in the HMCL subproject, so its outputs (jar, .exe,
# .sh, checksums) land in the subproject's build dir, matching upstream's
# own CI (Jenkinsfile archives 'HMCL/build/libs/*').
LIBS_DIR="$WORK_DIR/HMCL/build/libs"

mkdir -p "$OUTPUT_DIR"
find "$OUTPUT_DIR" -maxdepth 1 -type f -delete

if [[ ! -d "$LIBS_DIR" ]]; then
  echo "ERROR: $LIBS_DIR does not exist" >&2
  exit 1
fi

find "$LIBS_DIR" -maxdepth 1 -type f \
  -exec cp {} "$OUTPUT_DIR/" \;

if ! find "$OUTPUT_DIR" -maxdepth 1 -type f \
    | grep -q .; then
  echo "ERROR: no build artifacts found" >&2
  exit 1
fi

(
  cd "$OUTPUT_DIR"
  sha256sum * > SHA256SUMS.txt
)

echo "==> Build complete"
ls -lh "$OUTPUT_DIR"
