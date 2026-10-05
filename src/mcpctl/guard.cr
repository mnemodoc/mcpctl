module Mcpctl
  # Refuses a client rewrite — Zed's context_servers or Claude Code's user-scope
  # servers — that would destroy the only readable copy of a secret.
  #
  # Every string a current entry holds and the new one no longer does is
  # "dropped". A dropped string must either be a value declared in servers.yml,
  # or equal a keychain secret of that same server — otherwise the rewrite would
  # lose it. Messages name the entry and the key path, never the value.
  module Guard
    # Never a secret: an old command path legitimately disappears, and `type`
    # is Claude Code's transport tag (stdio, http).
    EXEMPT_KEYS = {"command", "type"}
    # Command lines: their paths and bare flags are exempt, any other word is checked.
    COMMAND_LINE_KEYS = {"args", "headersHelper"}

    # Declared secrets missing from the store: a sync would wire an indirection
    # that cannot resolve.
    def self.missing_secrets(config : Config, lookup : Proc(String, String?)) : Array(String)
      errors = [] of String
      config.servers.each do |name, server|
        server.secret_services.each do |service|
          errors << "#{name}: keychain entry #{service} not found" unless lookup.call(service)
        end
      end
      errors
    end

    def self.dropped(config : Config, old : Hash(String, JSON::Any), new : Hash(String, JSON::Any),
                     lookup : Proc(String, String?)) : Array(String)
      errors = [] of String

      old.each do |name, entry|
        server = config.servers[name]?
        kept = Set(String).new
        new[name]?.try { |current| leaves(current).each { |_, value| kept << value } }
        server.try { |declared| kept.concat(declared_values(declared)) }
        secrets = server.try(&.secret_services.compact_map { |service| lookup.call(service) }) || [] of String
        indirection = launch_indirection?(name, entry)

        leaves(entry).each do |path, value|
          next if indirection && path.starts_with?("args[")
          next if exempt?(path, value)
          next if kept.includes?(value) || secrets.includes?(value)

          errors << "#{name}: #{path} would be dropped but matches no keychain secret of this server"
        end
      end

      errors
    end

    # `launch <name>` under the entry's own name is the indirection the renderer
    # writes for a server with secrets: it holds the server name, never a value,
    # so renaming or removing that server must not trip the guard.
    private def self.launch_indirection?(name : String, entry : JSON::Any) : Bool
      entry["args"]?.try(&.as_a?) == [JSON::Any.new("launch"), JSON::Any.new(name)]
    end

    # Arguments are checked like any other string, except the two shapes that
    # cannot carry a secret: a path, and a flag with no inline value (`--stdio`,
    # but not `--token=…`). A token passed as `--api-key <value>` is the value.
    private def self.exempt?(path : String, value : String) : Bool
      key = path.split(/[.\[]/).first
      return true if EXEMPT_KEYS.includes?(key)
      return false unless COMMAND_LINE_KEYS.includes?(key)

      value.starts_with?('/') || value.starts_with?("~/") || (value.starts_with?('-') && !value.includes?('='))
    end

    private def self.declared_values(server : Server) : Array(String)
      [server.url, server.command].compact + server.args + server.env.values + server.headers.values
    end

    # String leaves of a JSON value, with a dotted path.
    private def self.leaves(value : JSON::Any, path : String = "") : Array({String, String})
      case raw = value.raw
      when String
        [{path, raw}]
      when Hash
        raw.flat_map { |key, child| leaves(child, path.empty? ? key : "#{path}.#{key}") }
      when Array
        raw.each_with_index.flat_map { |child, i| leaves(child, "#{path}[#{i}]") }.to_a
      else
        [] of {String, String}
      end
    end
  end
end
