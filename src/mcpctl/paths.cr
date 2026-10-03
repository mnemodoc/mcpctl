module Mcpctl
  module Paths
    # MCPCTL_CONFIG, then $XDG_CONFIG_HOME/mcpctl/servers.yml, then ~/.config/mcpctl/servers.yml.
    def self.config(env, home : String) : String
      if explicit = env["MCPCTL_CONFIG"]?.presence
        return explicit
      end

      base = env["XDG_CONFIG_HOME"]?.presence || File.join(home, ".config")
      File.join(base, "mcpctl", "servers.yml")
    end

    # Expands a leading `~/` only: the generated configs must hold absolute paths.
    def self.expand(path : String, home : String) : String
      path.starts_with?("~/") ? File.join(home, path[2..]) : path
    end
  end
end
