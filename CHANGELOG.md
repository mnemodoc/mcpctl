# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
