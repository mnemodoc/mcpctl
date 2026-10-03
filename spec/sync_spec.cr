require "./spec_helper"

# A throwaway home: servers.yml, Zed settings, ~/.claude.json, and a fake
# `claude` CLI that logs each call and fails `add-json` when told to.
private class Sandbox
  getter dir : String
  getter stdout = IO::Memory.new
  getter stderr = IO::Memory.new

  def initialize(servers_yaml : String, claude_servers : String, zed_text : String)
    @dir = File.tempname("mcpctl-sync-spec")
    Dir.mkdir(@dir)
    File.write(zed_path, zed_text)
    File.write(claude_json, %({"mcpServers": #{claude_servers}}))
    File.write(claude_bin, <<-SH, perm: 0o755)
      #!/bin/sh
      echo "$*" >> "#{log_path}"
      if [ -e "#{@dir}/zed-edit" ]; then cat "#{@dir}/zed-edit" > "#{zed_path}"; rm "#{@dir}/zed-edit"; fi
      if [ "$2" = add-json ] && [ -e "#{@dir}/fail-add" ] && printf '%s' "$*" | grep -qF -- "$(cat "#{@dir}/fail-add")"; then exit 1; fi
      exit 0
      SH
    @config = Mcpctl::Config.from_yaml(servers_yaml)
  end

  def zed_path
    File.join(@dir, "settings.json")
  end

  def claude_json
    File.join(@dir, "claude.json")
  end

  def claude_bin
    File.join(@dir, "claude")
  end

  def log_path
    File.join(@dir, "claude.log")
  end

  # Makes every `add-json` whose arguments contain `marker` fail.
  def fail_add!(marker : String)
    File.write(File.join(@dir, "fail-add"), marker)
  end

  # Simulates the user saving Zed's settings while `claude` runs.
  def edit_zed_during_claude!(text : String)
    File.write(File.join(@dir, "zed-edit"), text)
  end

  def calls : Array(String)
    File.exists?(log_path) ? File.read_lines(log_path) : [] of String
  end

  # Keychain reads, one entry per call: each one spawns `security` in production.
  getter lookups = [] of String

  def sync(keychain = {} of String => String) : Mcpctl::Sync
    renderer = Mcpctl::Renderer.new(@config, home: "/H", mcpctl: "/bin/mcpctl")
    lookup = ->(service : String) { @lookups << service; keychain[service]? }
    Mcpctl::Sync.new(@config, renderer, zed_path, claude_json,
      lookup: lookup, claude: claude_bin, out: @stdout, err: @stderr)
  end

  def cleanup
    FileUtils.rm_rf(@dir)
  end
end

private def sandbox(servers_yaml : String, claude_servers = "{}", zed_text = %({"context_servers": {}}), &)
  box = Sandbox.new(servers_yaml, claude_servers, zed_text)
  yield box
ensure
  box.try &.cleanup
end

private PLAIN = <<-YAML
  servers:
    plain:
      targets: [claude, zed]
      command: /bin/echo
  YAML

describe Mcpctl::Sync do
  it "refuses to remove a Claude Code entry that holds a literal secret" do
    sandbox(PLAIN, %({"legacy": {"type": "stdio", "command": "/x", "env": {"API_KEY": "literal-s3cret"}}})) do |box|
      box.sync.run(false).should eq Mcpctl::Sync::Outcome::Refused

      box.calls.should be_empty
      box.stderr.to_s.should contain "guard: claude: legacy: env.API_KEY would be dropped but matches no keychain secret of this server"
      box.stderr.to_s.should_not contain "literal-s3cret"
    end
  end

  it "refuses to replace a Claude Code entry whose literal header is not in the keychain" do
    yaml = <<-YAML
      servers:
        obs:
          targets: [claude]
          url: https://obs/mcp
          secret_headers:
            Authorization: mcp.obs
      YAML
    current = %({"obs": {"type": "http", "url": "https://obs/mcp", "headers": {"Authorization": "Bearer old"}}})

    sandbox(yaml, current) do |box|
      box.sync({"mcp.obs" => "Bearer new"}).run(false).should eq Mcpctl::Sync::Outcome::Refused

      box.calls.should be_empty
      box.stderr.to_s.should contain "guard: claude: obs: headers.Authorization would be dropped"
    end
  end

  it "puts the previous Claude Code entry back when adding its replacement fails" do
    sandbox(PLAIN, %({"plain": {"type": "stdio", "command": "/bin/old"}})) do |box|
      box.fail_add!("/bin/echo")

      expect_raises(Mcpctl::Error, "claude mcp add-json plain failed; the previous entry was restored") do
        box.sync.run(false)
      end
      box.calls.should eq [
        "mcp remove --scope user plain",
        %(mcp add-json --scope user plain {"type":"stdio","command":"/bin/echo","args":[]}),
        %(mcp add-json --scope user plain {"type":"stdio","command":"/bin/old"}),
      ]
      File.read(box.zed_path).should eq %({"context_servers": {}})
    end
  end

  it "leaves Zed's settings alone when they changed while the sync ran" do
    sandbox(PLAIN) do |box|
      box.edit_zed_during_claude!(%({"theme": "edited", "context_servers": {}}))

      expect_raises(Mcpctl::Error, "changed during the sync") do
        box.sync.run(false)
      end
      File.read(box.zed_path).should eq %({"theme": "edited", "context_servers": {}})
    end
  end

  it "adds context_servers to a Zed settings file that has none yet" do
    sandbox(PLAIN, zed_text: %({\n  "theme": "x"\n}\n)) do |box|
      box.sync.run(false).should eq Mcpctl::Sync::Outcome::Applied

      File.read(box.zed_path).should eq <<-JSONC
        {
          "theme": "x",
          "context_servers": {
            "plain": {
              "command": "/bin/echo"
            }
          }
        }

        JSONC
    end
  end

  it "reports pending changes in check mode, and applies nothing" do
    sandbox(PLAIN) do |box|
      box.sync.run(true).should eq Mcpctl::Sync::Outcome::Pending

      box.calls.should be_empty
      File.read(box.zed_path).should eq %({"context_servers": {}})
    end
  end

  it "reports a clean state when both clients already match" do
    sandbox("servers: {}") do |box|
      box.sync.run(true).should eq Mcpctl::Sync::Outcome::Clean
      box.stdout.to_s.should eq "claude: up to date\nzed: up to date\n"
    end
  end

  it "keeps the permissions of Zed's settings even over a stale temporary file" do
    sandbox(PLAIN) do |box|
      File.chmod(box.zed_path, 0o644)
      File.write("#{box.zed_path}.mcpctl-tmp", "stale", perm: 0o600)

      box.sync.run(false).should eq Mcpctl::Sync::Outcome::Applied

      File.info(box.zed_path).permissions.value.should eq 0o644
      Dir.children(box.dir).select(&.starts_with?("settings.json.")).should eq ["settings.json.mcpctl-tmp"]
    end
  end

  it "reads each keychain entry once per sync" do
    yaml = <<-YAML
      servers:
        obs:
          targets: [claude, zed]
          url: https://obs/mcp
          secret_headers:
            Authorization: mcp.obs
      YAML
    claude = %({"obs": {"type": "http", "url": "https://obs/mcp", "headers": {"Authorization": "Bearer t"}}})
    zed = %({"context_servers": {"obs": {"url": "https://obs/mcp", "headers": {"Authorization": "Bearer t"}}}})

    sandbox(yaml, claude, zed) do |box|
      box.sync({"mcp.obs" => "Bearer t"}).run(true).should eq Mcpctl::Sync::Outcome::Pending

      box.lookups.should eq ["mcp.obs"]
    end
  end

  it "removes a Claude Code entry whose only values are paths, flags and its type" do
    sandbox(PLAIN, %({"old": {"type": "stdio", "command": "/opt/old", "args": ["--stdio"]}})) do |box|
      box.sync.run(false).should eq Mcpctl::Sync::Outcome::Applied

      box.calls.should eq [
        %(mcp add-json --scope user plain {"type":"stdio","command":"/bin/echo","args":[]}),
        "mcp remove --scope user old",
      ]
    end
  end
end
