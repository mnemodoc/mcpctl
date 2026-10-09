require "./spec_helper"

describe Mcpctl::Config do
  describe ".parse" do
    it "refuses a server declared twice instead of keeping the last one" do
      yaml = <<-YAML
        servers:
          g:
            a:
              targets: [zed]
              command: /bin/one
            a:
              targets: [claude]
              command: /bin/two
        YAML

      expect_raises(Mcpctl::Error, "duplicate key a at line 6") { Mcpctl::Config.parse(yaml) }
    end

    it "refuses a duplicate key at any depth" do
      yaml = <<-YAML
        servers:
          g:
            a:
              targets: [zed]
              command: /bin/one
              env:
                TOKEN: x
                TOKEN: y
        YAML

      expect_raises(Mcpctl::Error, "duplicate key TOKEN at line 8") { Mcpctl::Config.parse(yaml) }
    end

    it "names each server <group>-<server>, in declaration order" do
      yaml = <<-YAML
        servers:
          tools:
            b:
              targets: [zed]
              command: /bin/b
            a:
              targets: [claude]
              command: /bin/a
          infra:
            c:
              targets: [zed]
              url: https://c/mcp
        YAML

      config = Mcpctl::Config.parse(yaml)

      config.servers.keys.should eq ["tools-b", "tools-a", "infra-c"]
      config.servers["infra-c"].url.should eq "https://c/mcp"
    end

    it "leaves the servers of the default group unprefixed" do
      yaml = <<-YAML
        servers:
          default:
            x:
              targets: [zed]
              command: /bin/x
          infra:
            c:
              targets: [zed]
              command: /bin/c
        YAML

      Mcpctl::Config.parse(yaml).servers.keys.should eq ["x", "infra-c"]
    end

    it "lets two groups use the same short name" do
      yaml = <<-YAML
        servers:
          tools:
            a:
              targets: [zed]
              command: /bin/one
          infra:
            a:
              targets: [claude]
              command: /bin/two
        YAML

      config = Mcpctl::Config.parse(yaml)

      config.servers.keys.should eq ["tools-a", "infra-a"]
      config.servers["infra-a"].command.should eq "/bin/two"
    end

    it "refuses two servers that end up with the same name" do
      yaml = <<-YAML
        servers:
          a:
            b-c:
              targets: [zed]
              command: /bin/one
          a-b:
            c:
              targets: [claude]
              command: /bin/two
        YAML

      expect_raises(Mcpctl::Error, "server name a-b-c given twice: a.b-c and a-b.c") { Mcpctl::Config.parse(yaml) }
    end

    it "refuses a server written directly under servers, without a group" do
      yaml = <<-YAML
        servers:
          a:
            targets: [zed]
            command: /bin/one
        YAML

      expect_raises(Mcpctl::Error, "servers.a.targets: expected a server, found a sequence; servers are declared under a group (servers: <group>: <server>:)") { Mcpctl::Config.parse(yaml) }
    end

    it "refuses an ungrouped server whose settings are all mappings" do
      yaml = <<-YAML
        servers:
          a:
            env:
              A: b
            headers:
              X: y
        YAML

      expect_raises(Mcpctl::Error, "servers.a: holds server settings (env, headers); servers are declared under a group (servers: <group>: <server>:)") { Mcpctl::Config.parse(yaml) }
    end

    it "accepts a server written as an alias of another one" do
      yaml = <<-YAML
        servers:
          default:
            a: &base
              targets: [claude]
              command: /bin/a
            b: *base
        YAML

      Mcpctl::Config.parse(yaml).servers.keys.should eq ["a", "b"]
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
        expect_raises(Mcpctl::Error, message) { Mcpctl::Config.parse("servers:\n  default:\n    a:\n      #{body.gsub("\n    ", "\n      ")}\n") }
      end
    end

    it "refuses a name declared both in servers and zed_raw" do
      yaml = "servers:\n  default:\n    a:\n      targets: [zed]\n      command: /bin/x\nzed_raw:\n  a: {}\n"

      expect_raises(Mcpctl::Error, "declared in both servers and zed_raw: a") { Mcpctl::Config.parse(yaml) }
    end

    it "accepts the shipped servers.example.yml" do
      config = Mcpctl::Config.load(File.join(__DIR__, "..", "servers.example.yml"))

      config.servers.keys.should eq ["code-index", "public-docs", "monitoring-grafana", "monitoring-observability", "monitoring-staging-db"]
      config.zed_raw.keys.should eq ["some-extension-server"]
    end
  end
end
