module Mcpctl
  # Turns servers.yml into the entries each client expects. Pure: no I/O,
  # no keychain access — secrets only ever appear as `mcpctl` indirections.
  class Renderer
    ENTRY_INDENT = "    "
    BLOCK_INDENT = "  "

    def initialize(@config : Config, @home : String, @mcpctl : String)
    end

    # Shape stored by `claude mcp add-json` (verified: stored verbatim).
    # Disabled servers are left out — Claude Code has no user-scope "disabled" state.
    def claude : Hash(String, JSON::Any)
      @config.servers.each_with_object({} of String => JSON::Any) do |(name, server), entries|
        next unless server.claude? && server.enabled?

        entries[name] = claude_entry(name, server)
      end
    end

    def zed : Hash(String, JSON::Any)
      entries = {} of String => JSON::Any
      @config.servers.each { |name, server| entries[name] = zed_entry(name, server) if server.zed? }
      @config.zed_raw.each { |name, raw| entries[name] = JSON.parse(raw.to_json) }
      entries
    end

    # Value of `context_servers`, ready to be spliced at depth one of settings.json.
    def zed_block : String
      entries = zed
      lines = ["{"]
      entries.each_with_index do |(name, entry), index|
        @config.servers[name]?.try(&.note).try(&.each_line(chomp: true) { |line| lines << "#{ENTRY_INDENT}// #{line}".rstrip })
        body = entry.to_pretty_json(indent: "  ").gsub("\n", "\n#{ENTRY_INDENT}")
        lines << "#{ENTRY_INDENT}#{name.to_json}: #{body}#{index < entries.size - 1 ? "," : ""}"
      end
      lines << "#{BLOCK_INDENT}}"
      lines.join("\n")
    end

    private def claude_entry(name : String, server : Server) : JSON::Any
      entry = {} of String => JSON::Any
      if url = server.url
        entry["type"] = JSON::Any.new("http")
        entry["url"] = JSON::Any.new(url)
        entry["headers"] = string_map(server.headers) unless server.headers.empty?
        entry["headersHelper"] = JSON::Any.new("#{@mcpctl} headers") unless server.secret_headers.empty?
      else
        entry["type"] = JSON::Any.new("stdio")
        stdio_fields(entry, name, server)
        # Claude Code stores an absent args as `[]` (claude 2.1.285): match it,
        # or every sync would report this entry as changed.
        entry["args"] ||= JSON::Any.new([] of JSON::Any)
      end
      JSON::Any.new(entry)
    end

    private def zed_entry(name : String, server : Server) : JSON::Any
      entry = {} of String => JSON::Any
      entry["enabled"] = JSON::Any.new(false) unless server.enabled?
      url = server.url
      if url && server.secret_headers.empty?
        entry["url"] = JSON::Any.new(url)
        entry["headers"] = string_map(server.headers) unless server.headers.empty?
      else
        # Zed cannot read a secret: HTTP servers with one go through the mcp-remote bridge.
        stdio_fields(entry, name, server)
      end
      JSON::Any.new(entry)
    end

    private def stdio_fields(entry : Hash(String, JSON::Any), name : String, server : Server) : Nil
      if server.secret?
        entry["command"] = JSON::Any.new(@mcpctl)
        entry["args"] = JSON::Any.new(["launch", name].map { |arg| JSON::Any.new(arg) })
      elsif command = server.command
        entry["command"] = JSON::Any.new(expand(command))
        entry["args"] = JSON::Any.new(server.args.map { |arg| JSON::Any.new(expand(arg)) }) unless server.args.empty?
        entry["env"] = string_map(server.env) unless server.env.empty?
      end
    end

    private def string_map(hash : Hash(String, String)) : JSON::Any
      JSON::Any.new(hash.transform_values { |v| JSON::Any.new(v) })
    end

    private def expand(path : String) : String
      Paths.expand(path, home: @home)
    end
  end
end
