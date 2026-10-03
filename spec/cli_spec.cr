require "./spec_helper"
require "../src/mcpctl/cli"

private def cli(*argv : String) : {Int32, String, String}
  output = IO::Memory.new
  error = IO::Memory.new
  code = Mcpctl::CLI.run(argv.to_a, output, error)
  {code, output.to_s, error.to_s}
end

# A sync run against throwaway files; `zed_text` is the Zed settings content.
private def sync_with_zed(zed_text : String, &)
  dir = File.tempname("mcpctl-cli-spec")
  Dir.mkdir(dir)
  config = File.join(dir, "servers.yml")
  zed = File.join(dir, "settings.json")
  File.write(config, "settings:\n  mcpctl: /bin/mcpctl\nservers: {}\n")
  File.write(File.join(dir, "claude.json"), %({"mcpServers": {}}))
  File.write(zed, zed_text)
  yield cli("--config", config, "--zed-settings", zed, "--claude-json", File.join(dir, "claude.json"), "sync", "--check"), zed
ensure
  FileUtils.rm_rf(dir) if dir
end

describe Mcpctl::CLI do
  it "prints the usage, without needing a servers.yml, when no command is given" do
    code, _, error = cli("--config", "/nonexistent/servers.yml")

    code.should eq 2
    error.should start_with "Usage: mcpctl sync"
  end

  it "prints the usage, without needing a servers.yml, for an unknown command" do
    code, _, error = cli("--config", "/nonexistent/servers.yml", "frobnicate")

    code.should eq 2
    error.should start_with "Usage: mcpctl sync"
  end

  it "exits 3 from sync --check when changes are pending, 0 when up to date" do
    sync_with_zed(%({"context_servers": {"stale": {"command": "/bin/x"}}})) do |(code, output, _), _|
      output.should eq "claude: up to date\nzed: - stale\n"
      code.should eq 3
    end
    sync_with_zed(%({"context_servers": {}})) do |(code, _, _), _|
      code.should eq 0
    end
  end

  it "reports an unreadable Zed settings file by its path, without a backtrace" do
    sync_with_zed("") do |(code, _, error), zed|
      code.should eq 1
      error.should eq "mcpctl: #{zed}: unexpected token '<EOF>' at line 1, column 1\n"
    end
  end

  it "reports a Zed settings file whose root is not an object" do
    sync_with_zed("[]") do |(code, _, error), zed|
      code.should eq 1
      error.should eq "mcpctl: #{zed}: the root of the file is not an object\n"
    end
  end
end
