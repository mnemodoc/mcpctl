require "./spec_helper"

describe Mcpctl::Secrets do
  describe ".command" do
    it "reads the macOS login keychain through security" do
      Mcpctl::Secrets.command("mcp.x", :macos)
        .should eq({"/usr/bin/security", ["find-generic-password", "-g", "-s", "mcp.x"]})
    end

    it "reads the Secret Service through secret-tool on Linux" do
      Mcpctl::Secrets.command("mcp.x", :linux)
        .should eq({"secret-tool", ["lookup", "service", "mcp.x"]})
    end
  end

  describe ".parse" do
    it "drops the single newline the tools append, and nothing else" do
      Mcpctl::Secrets.parse("Bearer abc\n").should eq "Bearer abc"
      Mcpctl::Secrets.parse("Bearer abc").should eq "Bearer abc"
      Mcpctl::Secrets.parse("  padded \n").should eq "  padded "
    end
  end

  describe ".parse_keychain" do
    # `security -g` prints the password on stderr, quoted when printable,
    # hexadecimal (then a lossy quoted rendering) otherwise.
    it "reads a quoted printable password verbatim" do
      Mcpctl::Secrets.parse_keychain(%(password: "Bearer abc"\n)).should eq "Bearer abc"
      Mcpctl::Secrets.parse_keychain(%(password: "deadbeef"\n)).should eq "deadbeef"
    end

    it "decodes the hexadecimal form, used for non-ASCII and special characters" do
      Mcpctl::Secrets.parse_keychain(%(password: 0x636166C3A9  "caf\\303\\251"\n)).should eq "café"
      Mcpctl::Secrets.parse_keychain(%(password: 0x6122625C63  "a"b\\134c"\n)).should eq %(a"b\\c)
      Mcpctl::Secrets.parse_keychain(%(password: 0x6C696E65310A6C696E6532  "line1\\012line2"\n)).should eq "line1\nline2"
    end

    it "returns nil when there is no password line" do
      Mcpctl::Secrets.parse_keychain("security: SecKeychainSearchCopyNext: not found\n").should be_nil
    end
  end

  describe ".get" do
    it "names the missing tool instead of reporting an absent secret" do
      expect_raises(Mcpctl::Error, "no-such-tool not found: install it to read secrets") do
        Mcpctl::Secrets.get("mcp.x", {"no-such-tool", ["lookup"]})
      end
    end

    it "returns nil when the tool reports the entry as absent" do
      Mcpctl::Secrets.get("mcp.x", {"/usr/bin/false", [] of String}).should be_nil
    end
  end
end
