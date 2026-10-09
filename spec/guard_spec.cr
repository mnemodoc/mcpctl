require "./spec_helper"

private CONFIG = Mcpctl::Config.from_yaml(<<-YAML)
  servers:
    default:
      obs:
        targets: [zed]
        url: https://obs/mcp
        secret_headers:
          Authorization: mcp.obs
      graf:
        targets: [zed]
        command: /opt/bin/graf
        env:
          GRAFANA_URL: https://graf
        secret_env:
          TOKEN: mcp.graf
  YAML

private NEW_ENTRIES = {
  "obs"  => JSON.parse(%({"command":"/bin/mcpctl","args":["launch","obs"]})),
  "graf" => JSON.parse(%({"command":"/bin/mcpctl","args":["launch","graf"]})),
}

private OLD_ENTRIES = {
  "obs"      => JSON.parse(%({"url":"https://obs/mcp","headers":{"Authorization":"Bearer s3cr3t-obs"}})),
  "graf"     => JSON.parse(%({"command":"/old/path/graf","settings":{"grafana_url":"https://graf","grafana_api_key":"s3cr3t-graf"}})),
  "gone-ext" => JSON.parse(%({"enabled":true,"settings":{}})),
}

private def keychain(values : Hash(String, String))
  ->(service : String) { values[service]? }
end

describe Mcpctl::Guard do
  it "accepts when every dropped literal is stored in the keychain with the same value" do
    errors = Mcpctl::Guard.dropped(CONFIG, OLD_ENTRIES, NEW_ENTRIES,
      keychain({"mcp.obs" => "Bearer s3cr3t-obs", "mcp.graf" => "s3cr3t-graf"}))

    errors.should be_empty
  end

  it "refuses a dropped literal whose keychain value differs, without echoing the value" do
    errors = Mcpctl::Guard.dropped(CONFIG, OLD_ENTRIES, NEW_ENTRIES,
      keychain({"mcp.obs" => "Bearer other", "mcp.graf" => "s3cr3t-graf"}))

    errors.should eq ["obs: headers.Authorization would be dropped but is neither declared in servers.yml nor a keychain secret"]
  end

  it "refuses a declared secret missing from the keychain" do
    errors = Mcpctl::Guard.missing_secrets(CONFIG, keychain({"mcp.obs" => "Bearer s3cr3t-obs"}))

    errors.should eq ["graf: keychain entry mcp.graf not found"]
  end

  it "refuses a literal dropped from a server that is no longer declared" do
    old = OLD_ENTRIES.merge({"legacy" => JSON.parse(%({"headers":{"Authorization":"Bearer x"}}))})

    errors = Mcpctl::Guard.dropped(CONFIG, old, NEW_ENTRIES,
      keychain({"mcp.obs" => "Bearer s3cr3t-obs", "mcp.graf" => "s3cr3t-graf"}))

    errors.should eq ["legacy: headers.Authorization would be dropped but is neither declared in servers.yml nor a keychain secret"]
  end

  it "refuses a dropped argument that is neither a path nor a bare flag" do
    old = OLD_ENTRIES.merge({"tool" => JSON.parse(%({"command":"/old/tool","args":["--api-key","sk-only-copy","--token=sk-inline"]}))})

    errors = Mcpctl::Guard.dropped(CONFIG, old, NEW_ENTRIES,
      keychain({"mcp.obs" => "Bearer s3cr3t-obs", "mcp.graf" => "s3cr3t-graf"}))

    errors.should eq [
      "tool: args[1] would be dropped but is neither declared in servers.yml nor a keychain secret",
      "tool: args[2] would be dropped but is neither declared in servers.yml nor a keychain secret",
    ]
  end

  it "lets the launch indirection of a renamed or removed server go" do
    old = OLD_ENTRIES.merge({"old-graf" => JSON.parse(%({"command":"/bin/mcpctl","args":["launch","old-graf"]}))})

    errors = Mcpctl::Guard.dropped(CONFIG, old, NEW_ENTRIES,
      keychain({"mcp.obs" => "Bearer s3cr3t-obs", "mcp.graf" => "s3cr3t-graf"}))

    errors.should be_empty
  end

  it "still refuses launch-shaped args that name another server" do
    old = OLD_ENTRIES.merge({"tool" => JSON.parse(%({"command":"/old/tool","args":["launch","sk-only-copy"]}))})

    errors = Mcpctl::Guard.dropped(CONFIG, old, NEW_ENTRIES,
      keychain({"mcp.obs" => "Bearer s3cr3t-obs", "mcp.graf" => "s3cr3t-graf"}))

    errors.should eq [
      "tool: args[0] would be dropped but is neither declared in servers.yml nor a keychain secret",
      "tool: args[1] would be dropped but is neither declared in servers.yml nor a keychain secret",
    ]
  end

  # A group renames its servers: the old entry goes, its values stay readable
  # in servers.yml under the new name, so nothing is lost.
  it "lets the literal secret of a renamed server go when the keychain holds it under its new name" do
    old = {"grafana" => JSON.parse(%({"command":"/opt/bin/graf","env":{"TOK":"s3cret"}}))}
    new = {"monitoring-grafana" => JSON.parse(%({"command":"/bin/mcpctl","args":["launch","monitoring-grafana"]}))}
    config = Mcpctl::Config.from_yaml(<<-YAML)
      servers:
        monitoring:
          grafana:
            targets: [zed]
            command: /opt/bin/graf
            secret_env:
              TOK: mcp.monitoring.grafana
      YAML

    Mcpctl::Guard.dropped(config, old, new, keychain({"mcp.monitoring.grafana" => "s3cret"})).should be_empty
  end

  it "lets the values of a renamed server go when servers.yml declares them under its new name" do
    old = {
      "old-obs"  => JSON.parse(%({"type":"http","url":"https://obs/mcp"})),
      "old-graf" => JSON.parse(%({"command":"/opt/bin/graf","args":["mcp"],"env":{"GRAFANA_URL":"https://graf"}})),
    }
    new = {
      "obs"  => JSON.parse(%({"type":"http","url":"https://obs/mcp"})),
      "graf" => JSON.parse(%({"command":"/opt/bin/graf","args":["mcp"],"env":{"GRAFANA_URL":"https://graf"}})),
    }
    config = Mcpctl::Config.from_yaml(<<-YAML)
      servers:
        default:
          obs:
            targets: [zed]
            url: https://obs/mcp
          graf:
            targets: [zed]
            command: /opt/bin/graf
            args: [mcp]
            env:
              GRAFANA_URL: https://graf
      YAML

    Mcpctl::Guard.dropped(config, old, new, keychain({} of String => String)).should be_empty
  end

  it "lets an old command, old paths and bare flags in args go" do
    old = OLD_ENTRIES.merge({"graf" => JSON.parse(%({"command":"/old/graf","args":["--stdio","/old/conf.yml","~/old.yml"],"settings":{"grafana_api_key":"s3cr3t-graf"}}))})

    errors = Mcpctl::Guard.dropped(CONFIG, old, NEW_ENTRIES,
      keychain({"mcp.obs" => "Bearer s3cr3t-obs", "mcp.graf" => "s3cr3t-graf"}))

    errors.should be_empty
  end
end
