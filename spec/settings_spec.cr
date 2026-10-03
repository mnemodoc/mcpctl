require "./spec_helper"

private def settings(yaml : String, found : Hash(String, String) = {"mcpctl" => "/opt/homebrew/bin/mcpctl", "npx" => "/usr/local/bin/npx"})
  config = Mcpctl::Config.from_yaml(yaml)
  Mcpctl::Settings.new(config.settings, home: "/H", which: ->(name : String) { found[name]? })
end

describe Mcpctl::Settings do
  it "defaults every value from the PATH and the usual client locations" do
    s = settings("servers: {}")

    s.mcpctl.should eq "/opt/homebrew/bin/mcpctl"
    s.npx.should eq "/usr/local/bin/npx"
    s.mcp_remote.should eq "mcp-remote@0.14.3"
    s.zed_settings.should eq "/H/.config/zed/settings.json"
    s.claude_json.should eq "/H/.claude.json"
  end

  it "takes explicit values, with ~ expanded in paths" do
    s = settings(<<-YAML)
      settings:
        mcpctl: ~/.local/bin/mcpctl
        npx: ~/.local/share/mise/shims/npx
        mcp_remote: mcp-remote@1.0.0
        zed_settings: /z/settings.json
        claude_json: ~/alt.json
      servers: {}
      YAML

    s.mcpctl.should eq "/H/.local/bin/mcpctl"
    s.npx.should eq "/H/.local/share/mise/shims/npx"
    s.mcp_remote.should eq "mcp-remote@1.0.0"
    s.zed_settings.should eq "/z/settings.json"
    s.claude_json.should eq "/H/alt.json"
  end

  it "raises a pointed error when a needed executable is neither set nor in the PATH" do
    s = settings("servers: {}", found: {} of String => String)

    expect_raises(Mcpctl::Error, "mcpctl not found in PATH: set settings.mcpctl") { s.mcpctl }
    expect_raises(Mcpctl::Error, "npx not found in PATH: set settings.npx") { s.npx }
  end

  it "rejects an unknown setting" do
    expect_raises(YAML::ParseException, /npxx/) do
      Mcpctl::Config.from_yaml("settings: {npxx: /bin/npx}\nservers: {}")
    end
  end
end
