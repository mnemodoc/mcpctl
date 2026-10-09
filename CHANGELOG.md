# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **Servers are declared under a group** — breaking: `servers: <group>: <server>:`
  instead of `servers: <server>:`. A group is a namespace: the clients see
  `<group>-<server>`, so two groups may reuse a short name; the servers of the
  `default` group keep their own name. Two servers ending up with the same name
  are refused, and a server left directly under `servers:` fails with a message
  that says so. To keep the current names, move every server under `default`;
  any other group renames its servers in Claude Code and Zed, and the tool
  permissions written against the old names (`mcp__<name>__…`) must follow.
- **Secret store entries named after the server** (documentation): the README
  and `servers.example.yml` use `mcp.<group>.<server>`, `mcp.<server>` in the
  `default` group. A convention only — `mcpctl` reads whatever entry
  `servers.yml` names.

### Fixed
- **Renaming a server no longer trips the guard**: a value dropped from the old
  entry is safe as long as `servers.yml` still declares it, or the keychain
  holds it, under any server name. The guard only looked under the old name,
  so renaming a server with a URL, a plain argument or a literal secret was
  refused. Its message now reads "is neither declared in servers.yml nor a
  keychain secret".

## [0.1.1] - 2026-10-05

### Fixed
- **Renaming or removing a server with secrets no longer blocks `sync`**: the
  guard mistook the `launch <name>` indirection it writes itself for a possible
  secret and refused the rewrite. Only that exact pair, under the entry's own
  name, is exempt — any other dropped argument is still checked.

## [0.1.0] - 2026-10-03

### Added
- **One declaration for every MCP client**: `servers.yml` drives the user-scope
  servers of Claude Code (through `claude mcp add-json/remove`) and the
  `context_servers` block of Zed, which is spliced in place — the rest of
  `settings.json`, comments included, is left byte for byte.
- **Secrets never written into a client config**: they live in the OS secret
  store (macOS keychain through `security`, Linux Secret Service through
  `secret-tool`) and are read at launch by `mcpctl launch` (stdio servers) or
  `mcpctl headers` (Claude Code `headersHelper`).
- **Token-protected HTTP servers in Zed**, which cannot read a secret: bridged
  to stdio by `mcp-remote`, which receives its headers through a FIFO — never
  in `argv`, never on disk.
- **A guard against losing a secret**: `sync` refuses to rewrite Zed or
  Claude Code when a string it would drop — `args` included, short of a path
  or a bare flag — is neither declared in `servers.yml` nor equal to a stored
  secret of that server.
- `sync --check` reports changes per entry and never prints a value; it exits
  3 when there are changes to apply.
- `settings:` section for machine-specific paths, with PATH-based defaults.
- `mcpctl licenses` prints the third-party notices baked into the binary.

[0.1.1]: https://github.com/mnemodoc/mcpctl/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/mnemodoc/mcpctl/releases/tag/v0.1.0
