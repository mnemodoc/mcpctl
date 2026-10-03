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
    getter servers : Hash(String, Server) = {} of String => Server
    getter zed_raw : Hash(String, YAML::Any) = {} of String => YAML::Any

    def self.load(path : String) : Config
      parse(File.read(path))
    end

    def self.parse(yaml : String) : Config
      reject_duplicate_keys(YAML::Nodes.parse(yaml))
      from_yaml(yaml).tap(&.validate!)
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

    def validate! : Nil
      servers.each { |name, server| server.validate!(name) }
      clash = servers.keys & zed_raw.keys
      raise Error.new("declared in both servers and zed_raw: #{clash.join(", ")}") unless clash.empty?
    end

    def server(name : String) : Server
      servers[name]? || raise Error.new("unknown server: #{name}")
    end
  end
end
