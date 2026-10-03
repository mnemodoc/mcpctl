module Mcpctl
  # Reads secrets from the OS store, through the tool that manages it:
  #   macOS  login keychain   /usr/bin/security (its ACL lets it read entries it created, without a prompt)
  #   Linux  Secret Service   secret-tool, from libsecret (needs an unlocked D-Bus session)
  # Entries are looked up by service name (e.g. mcp.openobserve).
  module Secrets
    {% if flag?(:darwin) %}
      OS = :macos
    {% elsif flag?(:linux) %}
      OS = :linux
    {% else %}
      OS = :unsupported
    {% end %}

    def self.command(service : String, os : Symbol = OS) : {String, Array(String)}
      case os
      when :macos then {"/usr/bin/security", ["find-generic-password", "-g", "-s", service]}
      when :linux then {"secret-tool", ["lookup", "service", service]}
      else             raise Error.new("no secret store supported on this OS")
      end
    end

    # `secret-tool lookup` adds a line ending only when writing to a terminal;
    # read through a pipe, as here, its output is the value itself (verified with
    # libsecret-tools 0.21.4). Nothing is trimmed: a trailing newline is part of
    # the secret.
    def self.parse(output : String) : String
      output
    end

    # `security -g` writes the password to stderr, quoted when it is printable,
    # in hexadecimal otherwise (non-ASCII, newline, quote, backslash). `-w` is
    # not used: it prints the hexadecimal form bare, which cannot be told apart
    # from a printable password made of hexadecimal digits.
    def self.parse_keychain(stderr : String) : String?
      stderr.each_line do |line|
        if hex = line.match(/\Apassword: 0x([0-9A-Fa-f]*)/).try(&.[1])
          return String.new(hex.hexbytes)
        elsif quoted = line.match(/\Apassword: "(.*)"\z/).try(&.[1])
          return quoted
        end
      end
      nil
    end

    def self.get(service : String, command : {String, Array(String)} = command(service)) : String?
      tool, args = command
      raise Error.new("#{tool} not found: install it to read secrets") unless Process.find_executable(tool)

      output = IO::Memory.new
      error = IO::Memory.new
      status = Process.run(tool, args, output: output, error: error)
      return nil unless status.success?

      tool == "/usr/bin/security" ? parse_keychain(error.to_s) : parse(output.to_s)
    end

    def self.fetch(service : String) : String
      get(service) || raise Error.new("secret #{service} not found")
    end
  end
end
