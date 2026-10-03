module Mcpctl
  # Brings Claude Code and Zed in line with servers.yml. Never prints a value:
  # the report names entries only, since the Zed side may still hold literals.
  class Sync
    MEMBER = "context_servers"

    # Refused: the guard blocked the sync, nothing was written.
    # Pending: changes found in check mode, nothing was written.
    # Clean: both clients already match servers.yml.
    # Applied: changes found and written.
    enum Outcome
      Refused
      Pending
      Clean
      Applied
    end

    # op ('+', '~', '-'), name, entry to add, entry replaced or removed.
    alias ClaudeOp = {Char, String, JSON::Any?, JSON::Any?}

    def initialize(@config : Config, @renderer : Renderer, @zed_settings : String, @claude_json : String,
                   @lookup : Proc(String, String?) = ->(service : String) { Secrets.get(service) },
                   @claude : String? = nil, @out : IO = STDOUT, @err : IO = STDERR)
    end

    def run(check : Bool) : Outcome
      old_claude = root_object(@claude_json, File.read(@claude_json))["mcpServers"]?.try(&.as_h?) || {} of String => JSON::Any
      new_claude = @renderer.claude
      claude_ops = claude_operations(old_claude, new_claude)
      zed_text = File.read(@zed_settings)
      old_zed = root_object(@zed_settings, zed_text)[MEMBER]?.try(&.as_h?) || {} of String => JSON::Any
      new_zed = @renderer.zed
      new_text = Jsonc.set_member(zed_text, MEMBER, @renderer.zed_block)

      zed_changes = entry_changes(old_zed, new_zed)
      report("claude", claude_ops.map { |op, name, _, _| {op, name} })
      report("zed", zed_changes)

      # Each lookup spawns the store's tool: read every entry once for the three checks.
      known = {} of String => String?
      lookup = ->(service : String) { known.has_key?(service) ? known[service] : (known[service] = @lookup.call(service)) }
      errors = Guard.missing_secrets(@config, lookup) +
               Guard.dropped(@config, old_claude, new_claude, lookup).map { |e| "claude: #{e}" } +
               Guard.dropped(@config, old_zed, new_zed, lookup).map { |e| "zed: #{e}" }
      errors.each { |e| @err.puts "guard: #{e}" }
      return Outcome::Refused unless errors.empty?

      changed = !(claude_ops.empty? && zed_changes.empty?)
      return changed ? Outcome::Pending : Outcome::Clean if check

      apply_claude(claude_ops)
      write_atomically(@zed_settings, new_text, expected: zed_text) unless new_text == zed_text
      changed ? Outcome::Applied : Outcome::Clean
    end

    # Errors name the file: two JSON files are read, and a bare "unexpected token"
    # does not say which one.
    private def root_object(path : String, text : String) : Hash(String, JSON::Any)
      root = begin
        Jsonc.parse(text)
      rescue ex : JSON::ParseException | Error
        raise Error.new("#{path}: #{ex.message}")
      end
      root.as_h? || raise Error.new("#{path}: the root of the file is not an object")
    end

    # User-scope servers are wholly owned by servers.yml: anything else is removed.
    # Each operation carries the entry to add and the entry it replaces or removes.
    private def claude_operations(current : Hash(String, JSON::Any), desired : Hash(String, JSON::Any)) : Array(ClaudeOp)
      ops = [] of ClaudeOp
      desired.each do |name, entry|
        next if current[name]? == entry

        ops << {current.has_key?(name) ? '~' : '+', name, entry, current[name]?}
      end
      current.each { |name, entry| ops << {'-', name, nil, entry} unless desired.has_key?(name) }
      ops
    end

    private def entry_changes(old : Hash(String, JSON::Any), new : Hash(String, JSON::Any)) : Array({Char, String})
      changes = [] of {Char, String}
      new.each { |name, entry| changes << {old.has_key?(name) ? '~' : '+', name} unless old[name]? == entry }
      old.each_key { |name| changes << {'-', name} unless new.has_key?(name) }
      changes
    end

    private def report(side : String, changes : Array({Char, String})) : Nil
      if changes.empty?
        @out.puts "#{side}: up to date"
      else
        changes.each { |op, name| @out.puts "#{side}: #{op} #{name}" }
      end
    end

    # Through the CLI, never by writing ~/.claude.json: it is a Seafile symlink
    # that Claude Code rewrites itself — a rename would replace the link.
    # The CLI has no "replace": a `~` is a remove then an add, so a failed add
    # puts the previous entry back rather than leave the server missing.
    private def apply_claude(ops : Array(ClaudeOp)) : Nil
      claude = @claude || Process.find_executable("claude") || raise Error.new("claude CLI not found in PATH")
      ops.each do |op, name, entry, previous|
        unless op == '+'
          raise Error.new("claude mcp remove #{name} failed") unless cli(claude, ["mcp", "remove", "--scope", "user", name])
        end
        next if entry.nil? || add(claude, name, entry)

        raise Error.new("claude mcp add-json #{name} failed") unless previous
        restored = add(claude, name, previous)
        raise Error.new("claude mcp add-json #{name} failed; #{restored ? "the previous entry was restored" : "restoring the previous entry failed too"}")
      end
    end

    private def add(claude : String, name : String, entry : JSON::Any) : Bool
      cli(claude, ["mcp", "add-json", "--scope", "user", name, entry.to_json])
    end

    private def cli(command : String, args : Array(String)) : Bool
      Process.run(command, args, output: Process::Redirect::Close, error: @err).success?
    end

    # Same directory, same permissions, then rename: Zed never sees a half-written file.
    # The file was read before the Claude Code calls, seconds ago: if it moved
    # since (a setting saved in Zed), writing would silently revert that change.
    private def write_atomically(path : String, content : String, expected : String) : Nil
      real = File.realpath(path)
      raise Error.new("#{path} changed during the sync: run it again") unless File.read(real) == expected
      # A name of its own per run: two syncs never share a temporary file, and
      # one left by a crash is never reused with its permissions.
      tmp = "#{real}.mcpctl-#{Random::Secure.hex(6)}"
      begin
        # Created owner-only (the file may still hold literal secrets), then
        # given the original permissions, which the umask would otherwise trim.
        File.write(tmp, content, perm: 0o600)
        File.chmod(tmp, File.info(real).permissions)
        File.rename(tmp, real)
      ensure
        File.delete?(tmp)
      end
    end
  end
end
