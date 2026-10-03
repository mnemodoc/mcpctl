module Mcpctl
  # Machine-specific values, optional in servers.yml, resolved with defaults.
  class Settings
    MCP_REMOTE = "mcp-remote@0.14.3"

    def initialize(@raw : RawSettings, @home : String,
                   @which : Proc(String, String?) = ->(name : String) { Process.find_executable(name) })
    end

    # Written into the generated configs, so it must survive an upgrade: the PATH
    # entry (e.g. /opt/homebrew/bin/mcpctl) is kept as is, never resolved to a
    # versioned Cellar path.
    def mcpctl : String
      path(@raw.mcpctl) || executable("mcpctl")
    end

    def npx : String
      path(@raw.npx) || executable("npx")
    end

    def mcp_remote : String
      @raw.mcp_remote || MCP_REMOTE
    end

    def zed_settings : String
      Paths.expand(@raw.zed_settings || "~/.config/zed/settings.json", home: @home)
    end

    def claude_json : String
      Paths.expand(@raw.claude_json || "~/.claude.json", home: @home)
    end

    private def path(value : String?) : String?
      value.try { |v| Paths.expand(v, home: @home) }
    end

    private def executable(name : String) : String
      @which.call(name) || raise Error.new("#{name} not found in PATH: set settings.#{name}")
    end
  end
end
