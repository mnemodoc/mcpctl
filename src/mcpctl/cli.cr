require "option_parser"
require "./lib"
require "./version"
require "./licenses"

module Mcpctl
  # STDOUT of `launch` is the MCP JSON-RPC channel: diagnostics go to STDERR only.
  module CLI
    COMMANDS = {"sync", "launch", "headers", "licenses"}
    # Exit code of `sync --check` when there is something to apply: distinct from
    # 1 (refused or failed), so a script can tell drift from breakage.
    PENDING = 3

    # Returns the exit code; `launch` never returns (it execs or exits with the bridge).
    def self.run(argv : Array(String), output : IO = STDOUT, err : IO = STDERR) : Int32
      home = Path.home.to_s
      config_path = Paths.config(ENV, home: home)
      check = false
      zed_settings = nil
      claude_json = nil
      early = nil

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: mcpctl sync [--check] | launch <server> | headers | licenses\n"
        opts.on("--config PATH", "servers.yml (default: $MCPCTL_CONFIG, then $XDG_CONFIG_HOME/mcpctl/servers.yml)") { |value| config_path = value }
        opts.on("--check", "sync: show the changes, write nothing") { check = true }
        opts.on("--zed-settings PATH", "sync: Zed settings file (overrides settings.zed_settings)") { |value| zed_settings = value }
        opts.on("--claude-json PATH", "sync: Claude Code config read for comparison (overrides settings.claude_json)") { |value| claude_json = value }
        opts.on("--version", "Show version") { early = Mcpctl.version_line }
        opts.on("-h", "--help", "Show help") { early = opts.to_s }
      end
      parser.parse(argv)
      if message = early
        output.puts message
        return 0
      end

      # Settled before servers.yml is read: neither the usage nor the notices need it.
      command = argv.shift?
      return usage(parser, err) unless COMMANDS.includes?(command)
      if command == "licenses"
        print_licenses(output)
        return 0
      end

      config = Config.load(Paths.expand(config_path, home: home))
      settings = Settings.new(config.settings, home: home)
      case command
      when "launch"
        name = argv.shift?
        return usage(parser, err) unless name
        launch(config, settings, name)
      when "headers"
        headers(config, output)
        0
      when "sync"
        renderer = Renderer.new(config, home: home, mcpctl: settings.mcpctl)
        zed = zed_settings.try { |value| Paths.expand(value, home: home) } || settings.zed_settings
        claude = claude_json.try { |value| Paths.expand(value, home: home) } || settings.claude_json
        case Sync.new(config, renderer, zed, claude, out: output, err: err).run(check)
        in .refused?          then 1
        in .pending?          then PENDING
        in .clean?, .applied? then 0
        end
      else
        usage(parser, err)
      end
    rescue ex : Error | OptionParser::Exception | YAML::ParseException | File::Error | IO::Error
      err.puts "mcpctl: #{ex.message}"
      1
    end

    # Third-party notices baked into the binary; needs no servers.yml.
    def self.print_licenses(output : IO) : Nil
      Licenses.files.sort_by(&.path).each do |file|
        output.puts "==> #{file.path.lstrip('/')}"
        output.puts file.gets_to_end
      end
    end

    private def self.usage(parser, err : IO) : Int32
      err.puts parser
      2
    end

    # Starts a server with its secrets: stdio servers get them in their
    # environment; HTTP servers are bridged to stdio by mcp-remote, which
    # receives the headers through a FIFO.
    def self.launch(config : Config, settings : Settings, name : String) : NoReturn
      server = config.server(name)
      home = Path.home.to_s

      if url = server.url
        headers = server.headers.merge(server.secret_headers.transform_values { |service| Secrets.fetch(service) })
        status = HeaderFifo.run(settings.npx, ["-y", settings.mcp_remote, url, "--header-file", HeaderFifo::PLACEHOLDER], headers)
        exit(status.exit_code? || 1)
      else
        env = server.env.merge(server.secret_env.transform_values { |service| Secrets.fetch(service) })
        command = server.command || raise Error.new("#{name}: no command to launch")
        Process.exec(Paths.expand(command, home: home), server.args.map { |arg| Paths.expand(arg, home: home) }, env: env)
      end
    end

    # headersHelper of Claude Code: the server comes from CLAUDE_CODE_MCP_SERVER_NAME,
    # the output is a JSON object of the secret headers only (static ones are in the config).
    def self.headers(config : Config, output : IO) : Nil
      name = ENV["CLAUDE_CODE_MCP_SERVER_NAME"]? || raise Error.new("CLAUDE_CODE_MCP_SERVER_NAME is not set")
      server = config.server(name)
      output.puts server.secret_headers.transform_values { |service| Secrets.fetch(service) }.to_json
    end
  end
end
