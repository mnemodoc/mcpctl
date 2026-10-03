# Canonical version/provenance block for a Crystal project.
#
# WHERE IT GOES
#   A binary with a helpers file  -> src/<project>/helpers.cr
#   A single-file binary          -> the top of src/<project>.cr
#   A library shard               -> wherever VERSION already lives
#
#   Replace `Mcpctl` with the project's module. Nothing else needs editing —
#   NAME and VERSION both come from shard.yml, so the block is transposable
#   as-is between projects.
#
# THE ONE PATH TO ADJUST
#   `read_file` is anchored on __DIR__, so its relative path depends on how
#   deep the file sits: `../../shard.yml` from src/<project>/helpers.cr,
#   `../shard.yml` from src/<project>.cr. Get it wrong and the build fails
#   loudly at compile time, which is the good failure mode.
#
# WHY EVERY BACKTICK IS ANCHORED (`git -C`, `shards version <dir>`)
#   A macro backtick runs the command in the COMPILER's working directory,
#   not in the source file's directory. Verified: compiling /tmp/p.cr from
#   another repository makes `pwd` report that other repository. For a binary
#   the two coincide and a bare `git log` looks fine; for a LIBRARY vendored
#   under lib/, a bare `git log` reports the provenance of the APPLICATION
#   compiling it — a version string that is confidently wrong. `-C #{__DIR__}`
#   anchors it on the shard's own tree, which also degrades correctly: a
#   vendored copy has no .git, git says nothing, and the fields read
#   "unknown".
#
# LIBRARY VS BINARY
#   Everything down to `self.version` applies to both. `self.version_line` and
#   the CLI wiring at the bottom are BINARY-ONLY: a library has no banner to
#   print. A library that only ever exposes a version number can stop at
#   VERSION and drop the rest.

module Mcpctl
  VERSION = {{ `shards version #{__DIR__}`.chomp.stringify }}
  # Read from shard.yml rather than written down a second time: a literal
  # would be free to drift from the shard, and nothing would catch it.
  NAME = {{ read_file("#{__DIR__}/../../shard.yml").lines.find(&.starts_with?("name:")).split(":")[1].strip }}
  # `|| true` because the build is not always a git checkout: a source tarball
  # has no repository, git prints nothing, and without the fallback the version
  # string reads "1.0.0 ()" in every bug report quoting it.
  GIT_REF = {{ `git -C #{__DIR__} log -n 1 --format="%H" 2>/dev/null | head -c 8 || true`.chomp.stringify }}
  # Non-empty when the working tree carried uncommitted changes at compile
  # time. This is the one piece of provenance whose absence makes the version
  # *false* rather than merely incomplete: without it, a binary built from
  # patched sources reports the exact string the pristine release reports.
  GIT_DIRTY = {{ `git -C #{__DIR__} status --porcelain 2>/dev/null | head -c 1 || true`.chomp.stringify }}
  # The nearest tag and the distance to it ("v1.2.0", "v1.2.0-4-gd86b19d8"),
  # which is what catches a shard.yml version drifting from the tag actually
  # built. Empty outside a checkout, and in a repository with no tag at all.
  GIT_TAG = {{ `git -C #{__DIR__} describe --tags 2>/dev/null || true`.chomp.stringify }}
  # Compile timestamp, UTC and ISO 8601: answers "since when has this been
  # running" without a round-trip to the image registry. POSIX syntax, so it
  # behaves the same under busybox in an Alpine builder and under GNU date.
  BUILT_AT = {{ `date -u +%Y-%m-%dT%H:%M:%SZ`.chomp.stringify }}
  # The platform this binary was compiled for, taken from the compiler's own
  # flags and NOT from `Crystal::DESCRIPTION`, whose "Default target" is the
  # compiler's own and would lie under cross-compilation. When static binaries
  # ship for several architectures, this is what tells a wrongly pulled image
  # from the right one at a glance.
  TARGET = {{ flag?(:linux) ? "linux" : (flag?(:darwin) ? "darwin" : (flag?(:windows) ? "windows" : "unknown")) }} +
           "/" + {{ flag?(:x86_64) ? "amd64" : (flag?(:aarch64) ? "arm64" : "unknown") }}

  # The commit as it deserves to be quoted: the short ref, suffixed `-dirty`
  # when the tree was patched, and "unknown" when there was no repository to
  # ask.
  def self.commit : String
    return "unknown" if GIT_REF.empty?
    GIT_DIRTY.empty? ? GIT_REF : "#{GIT_REF}-dirty"
  end

  # The nearest git tag, or "unknown". Every field of the build block is always
  # printed: a line that disappears reads as a rendering bug, where "unknown"
  # states plainly that the build could not know.
  def self.git_tag : String
    GIT_TAG.empty? ? "unknown" : GIT_TAG
  end

  # The provenance on its own — version, commit, platform, NO program name.
  # This is the one to hand to anything whose `name` is a separate field: an
  # MCP serverInfo, a `status` payload, a User-Agent built from parts. Folding
  # the name in here would duplicate it in all of them.
  def self.version : String
    "#{VERSION} (#{commit}, #{TARGET})"
  end

  # BINARY ONLY. The self-describing one-liner behind `--version`, sized for a
  # fleet inventory that collects one row per service: the row's left-hand
  # column is gone the moment the line is pasted into a bug report, so the line
  # names itself.
  #
  #   myapp 1.2.0 (d86b19d8-dirty, linux/amd64)
  def self.version_line : String
    "#{NAME} #{version}"
  end
end

# BINARY ONLY — wiring, for reference.
#
# The banner, on the CLI root (Admiral):
#
#   define_version Mcpctl.version_line
#
# The detail, in an `info`-style subcommand — decomposed rather than folded
# into one string, which is the whole difference between the two surfaces: the
# banner is harvested by a fleet inventory and must stay on one line, this is
# read by a human chasing down which build answered. Print every field, always,
# and mirror the same keys under --json:
#
#   version: 1.2.0
#   commit:  d86b19d8-dirty
#   tag:     v1.2.0
#   built:   2026-08-02T11:42:45Z
#   target:  linux/amd64
#
# Anywhere the banner is already prefixed by hand — `puts "myapp #{version}"` —
# replace it with `puts Mcpctl.version_line` rather than leaving the name
# written down in two places.
