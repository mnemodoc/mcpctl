#!/usr/bin/env bash
# Assembles the licenses/ folder baked into the binary from licenses.manifest:
# shard texts are copied from disk; clib/runtime texts are grouped by SPDX id
# from the committed canonical texts in licenses-spdx/.
#
# WHY THIS EXISTS
#   A statically linked binary carries its dependencies' code, so it has to
#   carry their notices too. Harvesting them at build time — rather than
#   committing a hand-written NOTICE that rots — keeps the shipped artifact
#   honest as the dependency list moves.
#
# WHERE IT GOES
#   scripts/harvest-licenses.sh, driven by the `dev:licenses` mise task, which
#   every task that compiles the application declares in its `depends`. The
#   folder is generated, so it belongs in .gitignore — and a CI job that runs a
#   compiling task standalone will otherwise fail at macro time, since
#   baked_file_system reads the folder while the compiler runs.
#
# THE TWO INPUTS THE PROJECT OWNS
#   licenses.manifest — one entry per line, `kind | name | source`:
#       shard   | mcp      | lib/mcp/LICENSE      on-disk text, copied verbatim
#       project | myapp    | LICENSE              same, for the project itself
#       clib    | openssl  | Apache-2.0           SPDX id, grouped by that id
#       runtime | libgc    | Boehm-GC             same
#     `#` starts a comment. shard/project entries carry a real copyright line,
#     so they are copied as-is; clib/runtime entries share one canonical text
#     between several dependencies, hence the grouping.
#   licenses-spdx/<id>.txt — the canonical text of each SPDX id used above,
#     committed once and never edited.
#
# The missing-file cases are hard errors on purpose: a notice silently absent
# from a redistributed binary is the failure this script exists to prevent.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
MANIFEST=licenses.manifest
OUT=licenses

# A project that bakes no licenses can delete this script, the task and its
# `depends`. Until it does, skipping cleanly beats failing every build.
if [ ! -f "$MANIFEST" ]; then
  echo "harvest: no $MANIFEST, nothing to assemble"
  exit 0
fi

rm -rf "$OUT"
mkdir -p "$OUT"

# clib/runtime licenses are grouped by SPDX id. macOS ships bash 3.2 (no
# associative arrays), so accumulate the "used by" names in per-id list files
# under a hidden scratch dir instead of `declare -A`. The dir is removed before
# the final count so it never lands in the baked output.
SCRATCH="$OUT/.used"
mkdir -p "$SCRATCH"

while IFS='|' read -r kind name source; do
  kind="$(echo "$kind" | tr -d '[:space:]')"
  name="$(echo "$name" | tr -d '[:space:]')"
  source="$(echo "$source" | tr -d '[:space:]')"
  [ -z "$kind" ] && continue
  case "$kind" in
    \#*) continue ;;
    shard|project)
      # On-disk license text copied verbatim (carries a real copyright line):
      # shards from lib/<name>/LICENSE, the project from the root LICENSE.
      if [ ! -f "$source" ]; then
        echo "harvest: missing license '$source' for '$name' (run shards install / the submodule plan)" >&2
        exit 1
      fi
      cp "$source" "$OUT/$name.txt"
      ;;
    clib|runtime)
      if [ ! -f "licenses-spdx/$source.txt" ]; then
        echo "harvest: missing licenses-spdx/$source.txt for '$name'" >&2
        exit 1
      fi
      echo "$name" >> "$SCRATCH/$source.list"
      ;;
  esac
done < <(grep -v '^#' "$MANIFEST")

# Sorted glob → deterministic baked output. Join the accumulated names with ", ".
for list in "$SCRATCH"/*.list; do
  [ -e "$list" ] || continue
  id="$(basename "$list" .list)"
  names="$(awk 'NR>1{printf ", "} {printf "%s", $0} END{print ""}' "$list")"
  {
    echo "Used by: $names"
    echo
    cat "licenses-spdx/$id.txt"
  } > "$OUT/clib-$id.txt"
done

rm -rf "$SCRATCH"

echo "harvested $(find "$OUT" -maxdepth 1 -type f | wc -l | tr -d ' ') license files into $OUT/"
