# mcpctl

[![CI](https://github.com/mnemodoc/mcpctl/actions/workflows/ci.yml/badge.svg)](https://github.com/mnemodoc/mcpctl/actions/workflows/ci.yml)

Declare your MCP servers once, in one YAML file, and let `mcpctl` write them into **Claude Code**
and **Zed** — with every secret kept in the OS secret store, never in a client config.

```console
$ mcpctl sync --check
claude: + openobserve
claude: - aws-mcp
zed: ~ mcp-server-grafana
$ mcpctl sync
```

## Why

Each MCP client has its own config file, its own format and its own idea of where a token goes.
Keeping them aligned by hand drifts, and the token usually ends up in plain text — Zed in
particular has no way to read a secret from anywhere: an `Authorization` header is written as is
in `settings.json`.

Tools that sync MCP configs across clients exist ([mcpr](https://github.com/mathematic-inc/mcpr),
[mcp-sync](https://github.com/EnjoyableWork/mcp-sync), [MCP Dock](https://github.com/OldJii/mcp-dock)…),
but they copy the values — secrets included — into each client. `mcpctl` is built around the
opposite rule:

- **Secrets stay in the OS store** — macOS keychain, or the Secret Service on Linux. A client
  config only ever holds an indirection to `mcpctl`.
- **Token-protected HTTP servers work in Zed**, through a stdio bridge fed by a FIFO: the token is
  never in a process's arguments (readable by `ps`) and never on disk.
- **A sync never destroys the only readable copy of a token**: if a value would be dropped from
  Zed or from Claude Code and is neither declared in `servers.yml` nor in the secret store, `sync`
  refuses and names the entry and the key — never the value. Only a command path, and in `args`
  a path or a bare flag (`--stdio`, not `--token=…`), may disappear unchecked.
- **Zed's `settings.json` is edited in place**: only the `context_servers` block is replaced (or
  appended, when the file has none yet), the rest of the file — comments included — stays byte for
  byte. If the file changes while `sync` runs, it is left alone and `sync` asks to be run again.
- **Claude Code is changed through its own CLI** (`claude mcp add-json/remove --scope user`),
  never by rewriting `~/.claude.json`, which Claude Code itself keeps rewriting.

## How a server reaches its secret

| Server | Claude Code | Zed |
| --- | --- | --- |
| No secret | the command or URL, as declared | same |
| stdio + `secret_env` | `mcpctl launch <name>`: reads the secrets, exports them, `exec`s the server | same |
| HTTP + `secret_headers` | `headersHelper: mcpctl headers` — Claude Code asks for the headers on each connection | `mcpctl launch <name>`: starts [`mcp-remote`](https://github.com/punkpeye/mcp-remote) as a stdio bridge and hands it the headers through a FIFO |

The FIFO: `mcp-remote` reads its `--header-file` once, at startup. `mcpctl` creates the FIFO in a
`0700` directory, starts the bridge, opens the FIFO for writing as soon as the bridge has opened
it for reading, **removes it**, then writes the headers. Nothing is left behind once the
handshake is done.

## Install

```sh
brew install mnemodoc/tap/mcpctl
```

Or from source, with [mise](https://mise.jdx.dev):

```sh
git clone https://github.com/mnemodoc/mcpctl && cd mcpctl
mise install && mise dev:deps && mise release:build   # bin/mcpctl
```

Requirements at run time: the `claude` CLI for the Claude Code side; `npx` for HTTP servers that
need the bridge in Zed; `secret-tool` (package `libsecret-tools`) on Linux.

## Configure

`mcpctl` reads `$MCPCTL_CONFIG`, else `$XDG_CONFIG_HOME/mcpctl/servers.yml`, else
`~/.config/mcpctl/servers.yml`. Start from [`servers.example.yml`](servers.example.yml).

```yaml
servers:
  monitoring:                         # a group: the clients see monitoring-grafana, …
    grafana:
      targets: [claude, zed]          # one name on both sides: it is what de-duplicates a server
                                      # Zed forwards to an agent that also declares it
      command: /opt/homebrew/bin/mcp-grafana
      env:
        GRAFANA_URL: https://grafana.example.com
      secret_env:
        GRAFANA_SERVICE_ACCOUNT_TOKEN: mcp.monitoring.grafana   # name of the entry in the secret store

    observability:
      targets: [claude, zed]
      url: https://observability.example.com/mcp
      secret_headers:
        Authorization: mcp.monitoring.observability
```

Servers are declared under a group, `servers: <group>: <server>:`. A group is a namespace: Claude
Code and Zed see `<group>-<server>` — the name `mcpctl launch` takes and the one tool permissions
are written against — so two groups may reuse a short name. The servers of the `default` group
keep their own name. Two servers ending up with the same name (`a` + `b-c` and `a-b` + `c`) are
refused, and so is a server written directly under `servers:`.

| Key | Meaning |
| --- | --- |
| `targets` | `claude`, `zed`, or both |
| `command`, `args` | stdio server; a leading `~/` is expanded |
| `env` | non-secret environment |
| `url`, `headers` | HTTP server, non-secret headers |
| `secret_env` | `VARIABLE: store-entry`, read by `mcpctl launch` |
| `secret_headers` | `Header: store-entry`, read by `mcpctl headers` (Claude Code) or passed through the FIFO (Zed) |
| `enabled` | `false` declares the server disabled in Zed and leaves it out of Claude Code |
| `note` | copied as comments above the entry in Zed |
| `zed_raw` (top level) | entries copied verbatim into Zed — servers provided by a Zed extension |
| `settings` (top level) | `mcpctl`, `npx`, `mcp_remote`, `zed_settings`, `claude_json` — machine-specific paths, all optional |

`settings.mcpctl` defaults to the `mcpctl` found in `PATH`, **kept unresolved**
(`/opt/homebrew/bin/mcpctl`, not a versioned Cellar path): it is written into the client configs,
so it has to survive an upgrade.

## Store a secret

`mcpctl` reads whatever entry `servers.yml` names; it enforces no naming scheme. The convention
below keeps the secret store as readable as `servers.yml`, one entry per server secret:

| Server | Entry |
| --- | --- |
| `<server>` in a group | `mcp.<group>.<server>` — `monitoring` / `grafana` → `mcp.monitoring.grafana` |
| `<server>` in `default` | `mcp.<server>`, after the name the clients see |
| a second secret of the same server | `mcp.<group>.<server>.<purpose>` — `mcp.monitoring.grafana.db` |

The entry then tells which server reads it, the store lists the secrets of a group together
(`security dump-keychain | grep mcp.monitoring.`), and two groups reusing a short name never share
an entry by accident. Renaming a server or moving it to another group means renaming its entry
too: copy the value under the new name, point `servers.yml` at it, check that `mcpctl sync --check`
finds it (a missing entry is refused), then delete the old one.

Always through standard input — a value passed as an argument is visible to `ps` and lands in the
shell history.

```sh
# macOS
read -rs v && printf '%s\n%s\n' "$v" "$v" | security add-generic-password -U -a "$USER" -s mcp.monitoring.grafana -w; unset v

# Linux
secret-tool store --label="mcp.monitoring.grafana" service mcp.monitoring.grafana   # prompts for the value
```

Rotating a secret needs no `sync`: it is read each time the server starts.

## Commands

| Command | Does |
| --- | --- |
| `mcpctl sync --check` | lists the changes per entry, writes nothing, prints no value; exits `0` when up to date, `3` when there are changes to apply, `1` when the guard refuses or an error occurs |
| `mcpctl sync` | applies; idempotent — a second run reports `up to date` |
| `mcpctl launch <name>` | started by the clients, not by hand |
| `mcpctl headers` | Claude Code `headersHelper`; the server comes from `CLAUDE_CODE_MCP_SERVER_NAME` |
| `mcpctl licenses` | third-party notices baked into the binary |

After a `sync`, Zed reloads its settings live; an open Claude Code session keeps its servers until
it restarts.

**After uninstalling a Zed extension, run `mcpctl sync` again**: Zed deletes the `context_servers`
entry carrying the extension's id, even when that entry has become a command declared here.

## What `sync` owns

- **Claude Code**: every user-scope MCP server. One that is not in `servers.yml` is removed.
  Project-scope servers (`.mcp.json`) and claude.ai connectors are left alone.
- **Zed**: the `context_servers` block, entirely.

## Limits

- Two clients: Claude Code and Zed.
- `mcp-remote` is a third-party npm package, fetched by `npx` on first use.
- On Linux the Secret Service needs an unlocked D-Bus session — not available on a headless
  server.

## Development

```sh
mise dev:deps
mise dev:spec          # specs
mise dev:ameba         # static analysis
mise dev:format-check
```

## License

MIT — see [LICENSE](LICENSE). Third-party notices: `mcpctl licenses`.
