module Mcpctl
  # One server of servers.yml. Unknown keys are rejected, so a typo fails
  # loudly instead of silently dropping a setting.
  class Server
    include YAML::Serializable
    include YAML::Serializable::Strict

    TARGETS = {"claude", "zed"}

    getter targets : Array(String) = [] of String
    getter command : String? = nil
    getter args : Array(String) = [] of String
    getter env : Hash(String, String) = {} of String => String
    getter url : String? = nil
    getter headers : Hash(String, String) = {} of String => String
    getter secret_env : Hash(String, String) = {} of String => String
    getter secret_headers : Hash(String, String) = {} of String => String
    getter? enabled : Bool = true
    getter note : String? = nil

    # The keys a server accepts, read off its fields so the list cannot drift.
    def self.setting_names : Array(String)
      {{ @type.instance_vars.map(&.name.stringify) }}
    end

    def claude?
      targets.includes?("claude")
    end

    def zed?
      targets.includes?("zed")
    end

    def http?
      !url.nil?
    end

    def secret?
      !secret_env.empty? || !secret_headers.empty?
    end

    def secret_services : Array(String)
      (secret_env.values + secret_headers.values).uniq
    end

    def validate!(name : String) : Nil
      raise Error.new("#{name}: exactly one of command or url is required") unless command.nil? ^ url.nil?
      raise Error.new("#{name}: targets must be a non-empty subset of claude, zed") if targets.empty? || targets.any? { |target| !TARGETS.includes?(target) }
      raise Error.new("#{name}: secret_env needs a command") if http? && !secret_env.empty?
      raise Error.new("#{name}: headers and secret_headers need a url") if !http? && !(headers.empty? && secret_headers.empty?)
    end
  end

  # The `settings:` section as written; see Settings for the defaults.
  class RawSettings
    include YAML::Serializable
    include YAML::Serializable::Strict

    getter mcpctl : String? = nil
    getter npx : String? = nil
    getter mcp_remote : String? = nil
    getter zed_settings : String? = nil
    getter claude_json : String? = nil

    def initialize
    end
  end

  class Config
    include YAML::Serializable
    include YAML::Serializable::Strict

    getter settings : RawSettings = RawSettings.new
    # Group whose servers keep their own name in the generated configs.
    DEFAULT_GROUP = "default"

    # Group name -> its servers. A group is a namespace: the clients see
    # `<group>-<server>` (see .exposed_name), so two groups may reuse a name.
    @[YAML::Field(key: "servers")]
    getter groups : Hash(String, Hash(String, Server)) = {} of String => Hash(String, Server)
    getter zed_raw : Hash(String, YAML::Any) = {} of String => YAML::Any

    def self.load(path : String) : Config
      parse(File.read(path))
    end

    def self.parse(yaml : String) : Config
      document = YAML::Nodes.parse(yaml)
      reject_duplicate_keys(document)
      reject_ungrouped_servers(document)
      from_yaml(yaml).tap(&.validate!)
    end

    # Every server under the name the clients see, groups in declaration order.
    # Exposed names are unique (see #validate!), so no entry overwrites another.
    def servers : Hash(String, Server)
      all = {} of String => Server
      groups.each do |group, members|
        members.each { |name, server| all[Config.exposed_name(group, name)] = server }
      end
      all
    end

    # `concerto` + `grafana` -> `concerto-grafana`; the default group adds nothing.
    def self.exposed_name(group : String, name : String) : String
      group == DEFAULT_GROUP ? name : "#{group}-#{name}"
    end

    # YAML::Serializable keeps the last of two equal keys without a word, which
    # would silently drop a whole server declaration.
    private def self.reject_duplicate_keys(node : YAML::Nodes::Node) : Nil
      case node
      when YAML::Nodes::Document, YAML::Nodes::Sequence
        node.nodes.each { |child| reject_duplicate_keys(child) }
      when YAML::Nodes::Mapping
        seen = Set(String).new
        node.nodes.each_slice(2) do |(key, value)|
          if key.is_a?(YAML::Nodes::Scalar) && !seen.add?(key.value)
            raise Error.new("duplicate key #{key.value} at line #{key.start_line}")
          end
          reject_duplicate_keys(value)
        end
      end
    end

    UNGROUPED_HINT = "servers are declared under a group (servers: <group>: <server>:)"

    # A server written directly under `servers:` would parse as a group whose
    # members are its own settings, and fail on a message that names neither.
    # Every member of a group must be a server: a mapping, or an alias that
    # from_yaml resolves. A "group" whose members all bear setting names
    # (`env`, `headers`) is a server too, even if each of them is a mapping.
    private def self.reject_ungrouped_servers(document : YAML::Nodes::Document) : Nil
      root = document.nodes.first?
      return unless root.is_a?(YAML::Nodes::Mapping)
      root.nodes.each_slice(2) do |(key, value)|
        next unless key.is_a?(YAML::Nodes::Scalar) && key.value == "servers" && value.is_a?(YAML::Nodes::Mapping)
        value.nodes.each_slice(2) do |(group, members)|
          next unless group.is_a?(YAML::Nodes::Scalar) && members.is_a?(YAML::Nodes::Mapping)
          reject_ungrouped_server(group.value, members)
        end
      end
    end

    private def self.reject_ungrouped_server(group : String, members : YAML::Nodes::Mapping) : Nil
      names = [] of String
      members.nodes.each_slice(2) do |(member, body)|
        next unless member.is_a?(YAML::Nodes::Scalar)
        names << member.value
        case body
        when YAML::Nodes::Sequence, YAML::Nodes::Scalar
          raise Error.new("servers.#{group}.#{member.value}: expected a server, found #{kind(body)}; #{UNGROUPED_HINT}")
        end
      end
      return if names.empty? || !names.all? { |name| Server.setting_names.includes?(name) }
      raise Error.new("servers.#{group}: holds server settings (#{names.join(", ")}); #{UNGROUPED_HINT}")
    end

    private def self.kind(node : YAML::Nodes::Node) : String
      node.is_a?(YAML::Nodes::Sequence) ? "a sequence" : "a scalar"
    end

    def validate! : Nil
      # `a` + `b-c` and `a-b` + `c` both give `a-b-c`.
      origin = {} of String => String
      groups.each do |group, members|
        members.each_key do |name|
          exposed = Config.exposed_name(group, name)
          if first = origin[exposed]?
            raise Error.new("server name #{exposed} given twice: #{first} and #{group}.#{name}")
          end
          origin[exposed] = "#{group}.#{name}"
        end
      end
      servers.each { |name, server| server.validate!(name) }
      clash = servers.keys & zed_raw.keys
      raise Error.new("declared in both servers and zed_raw: #{clash.join(", ")}") unless clash.empty?
    end

    def server(name : String) : Server
      servers[name]? || raise Error.new("unknown server: #{name}")
    end
  end
end
