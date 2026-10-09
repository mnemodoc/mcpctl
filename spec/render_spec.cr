require "./spec_helper"

private CONFIG_YAML = <<-YAML
  servers:
    default:
      plain:
        targets: [claude, zed]
        command: ~/bin/plain
        args: [serve, ~/conf.yml]
      secret-stdio:
        targets: [claude, zed]
        command: /usr/bin/tool
        env:
          URL: https://x
        secret_env:
          TOKEN: mcp.tool
      open-http:
        targets: [claude, zed]
        url: https://open/mcp
      auth-http:
        targets: [claude, zed]
        url: https://auth/mcp
        headers:
          Host: h.example
        secret_headers:
          Authorization: mcp.auth
        note: |-
          First line.
          Second line.
      zed-only:
        targets: [zed]
        enabled: false
        url: http://127.0.0.1:1/mcp
  zed_raw:
    from-extension:
      enabled: true
      settings: {}
  YAML

private def renderer
  Mcpctl::Renderer.new(Mcpctl::Config.from_yaml(CONFIG_YAML), home: "/H", mcpctl: "/H/.local/bin/mcpctl")
end

describe Mcpctl::Renderer do
  describe "#claude" do
    it "renders every Claude Code entry in the shape `claude mcp add-json` stores" do
      renderer.claude.should eq({
        "plain"        => JSON.parse(%({"type":"stdio","command":"/H/bin/plain","args":["serve","/H/conf.yml"]})),
        "secret-stdio" => JSON.parse(%({"type":"stdio","command":"/H/.local/bin/mcpctl","args":["launch","secret-stdio"]})),
        "open-http"    => JSON.parse(%({"type":"http","url":"https://open/mcp"})),
        "auth-http"    => JSON.parse(%({"type":"http","url":"https://auth/mcp","headers":{"Host":"h.example"},"headersHelper":"/H/.local/bin/mcpctl headers"})),
      })
    end
  end

  describe "#claude, for a stdio server without arguments" do
    # `claude mcp add-json` stores `"args": []` when the entry has none
    # (claude 2.1.285): rendering it omitted would report a change on every sync.
    it "writes an empty args, as Claude Code stores it" do
      config = Mcpctl::Config.from_yaml("servers:\n  default:\n    bare:\n      targets: [claude, zed]\n      command: /bin/bare\n")
      bare = Mcpctl::Renderer.new(config, home: "/H", mcpctl: "/bin/mcpctl")

      bare.claude.should eq({"bare" => JSON.parse(%({"type":"stdio","command":"/bin/bare","args":[]}))})
      bare.zed.should eq({"bare" => JSON.parse(%({"command":"/bin/bare"}))})
    end
  end

  describe "a server of a named group" do
    # `mcpctl launch` looks the server up by the name written in its arguments:
    # it has to be the exposed one, or launch would find no such server.
    it "is rendered and launched under <group>-<server>" do
      yaml = "servers:\n  infra:\n    tool:\n      targets: [claude, zed]\n      command: /bin/tool\n      secret_env:\n        T: mcp.t\n"
      grouped = Mcpctl::Renderer.new(Mcpctl::Config.from_yaml(yaml), home: "/H", mcpctl: "/bin/mcpctl")

      grouped.claude.should eq({"infra-tool" => JSON.parse(%({"type":"stdio","command":"/bin/mcpctl","args":["launch","infra-tool"]}))})
      grouped.zed.should eq({"infra-tool" => JSON.parse(%({"command":"/bin/mcpctl","args":["launch","infra-tool"]}))})
    end
  end

  describe "#zed" do
    it "renders Zed entries, routing every secret through mcpctl launch" do
      renderer.zed.should eq({
        "plain"          => JSON.parse(%({"command":"/H/bin/plain","args":["serve","/H/conf.yml"]})),
        "secret-stdio"   => JSON.parse(%({"command":"/H/.local/bin/mcpctl","args":["launch","secret-stdio"]})),
        "open-http"      => JSON.parse(%({"url":"https://open/mcp"})),
        "auth-http"      => JSON.parse(%({"command":"/H/.local/bin/mcpctl","args":["launch","auth-http"]})),
        "zed-only"       => JSON.parse(%({"enabled":false,"url":"http://127.0.0.1:1/mcp"})),
        "from-extension" => JSON.parse(%({"enabled":true,"settings":{}})),
      })
    end
  end

  describe "#zed_block" do
    it "renders the context_servers value with notes as comments, indented for depth one" do
      renderer.zed_block.should eq <<-JSONC
        {
            "plain": {
              "command": "/H/bin/plain",
              "args": [
                "serve",
                "/H/conf.yml"
              ]
            },
            "secret-stdio": {
              "command": "/H/.local/bin/mcpctl",
              "args": [
                "launch",
                "secret-stdio"
              ]
            },
            "open-http": {
              "url": "https://open/mcp"
            },
            // First line.
            // Second line.
            "auth-http": {
              "command": "/H/.local/bin/mcpctl",
              "args": [
                "launch",
                "auth-http"
              ]
            },
            "zed-only": {
              "enabled": false,
              "url": "http://127.0.0.1:1/mcp"
            },
            "from-extension": {
              "enabled": true,
              "settings": {}
            }
          }
        JSONC
    end
  end
end
