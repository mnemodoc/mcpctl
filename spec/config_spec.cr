require "./spec_helper"

describe Mcpctl::Config do
  describe ".parse" do
    it "refuses a server declared twice instead of keeping the last one" do
      yaml = <<-YAML
        servers:
          a:
            targets: [zed]
            command: /bin/one
          a:
            targets: [claude]
            command: /bin/two
        YAML

      expect_raises(Mcpctl::Error, "duplicate key a at line 5") { Mcpctl::Config.parse(yaml) }
    end

    it "refuses a duplicate key at any depth" do
      yaml = <<-YAML
        servers:
          a:
            targets: [zed]
            command: /bin/one
            env:
              TOKEN: x
              TOKEN: y
        YAML

      expect_raises(Mcpctl::Error, "duplicate key TOKEN at line 7") { Mcpctl::Config.parse(yaml) }
    end
  end

  describe "#validate!" do
    {
      "a server with both command and url"    => {"targets: [zed]\n    command: /bin/x\n    url: https://x", "a: exactly one of command or url is required"},
      "a server with neither command nor url" => {"targets: [zed]", "a: exactly one of command or url is required"},
      "a server with no target"               => {"targets: []\n    command: /bin/x", "a: targets must be a non-empty subset of claude, zed"},
      "an unknown target"                     => {"targets: [zed, cursor]\n    command: /bin/x", "a: targets must be a non-empty subset of claude, zed"},
      "secret_env on an HTTP server"          => {"targets: [zed]\n    url: https://x\n    secret_env: {T: mcp.t}", "a: secret_env needs a command"},
      "headers on a stdio server"             => {"targets: [zed]\n    command: /bin/x\n    headers: {H: v}", "a: headers and secret_headers need a url"},
      "secret_headers on a stdio server"      => {"targets: [zed]\n    command: /bin/x\n    secret_headers: {H: mcp.h}", "a: headers and secret_headers need a url"},
    }.each do |label, (body, message)|
      it "refuses #{label}" do
        expect_raises(Mcpctl::Error, message) { Mcpctl::Config.parse("servers:\n  a:\n    #{body}\n") }
      end
    end

    it "refuses a name declared both in servers and zed_raw" do
      yaml = "servers:\n  a:\n    targets: [zed]\n    command: /bin/x\nzed_raw:\n  a: {}\n"

      expect_raises(Mcpctl::Error, "declared in both servers and zed_raw: a") { Mcpctl::Config.parse(yaml) }
    end

    it "accepts the shipped servers.example.yml" do
      config = Mcpctl::Config.load(File.join(__DIR__, "..", "servers.example.yml"))

      config.servers.keys.should eq ["code-index", "public-docs", "grafana", "observability", "staging-db"]
      config.zed_raw.keys.should eq ["some-extension-server"]
    end
  end
end
