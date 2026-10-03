# frozen_string_literal: true

# Brewfile — the macOS side of mcpctl's toolchain (template: ~/.claude/templates/crystal/Brewfile).
#
#   brew bundle              install everything listed here
#   brew bundle check        report what is missing, install nothing
#
# Not the compiler: mise owns Crystal and shards, pinned in mise.toml.

# The Apple bash is 3.2; scripts/harvest-licenses.sh is written against it, the
# rest of the tooling assumes a modern one.
brew 'bash'

# The task runner and the toolchain it pins.
brew 'mise'

# GNU coreutils, for `timeout`: the tasks bound ameba and the spec runs with it,
# and macOS has no /usr/bin/timeout. Put its gnubin ahead of Apple's tools:
#   export PATH="$(brew --prefix)/opt/coreutils/libexec/gnubin:$PATH"
brew 'coreutils'

# release:static and dev:docker-image go through `docker buildx bake`.
cask 'docker'
