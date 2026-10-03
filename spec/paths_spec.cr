require "./spec_helper"

describe Mcpctl::Paths do
  describe ".config" do
    it "prefers MCPCTL_CONFIG" do
      env = {"MCPCTL_CONFIG" => "/etc/mcp.yml", "XDG_CONFIG_HOME" => "/x"}
      Mcpctl::Paths.config(env, home: "/H").should eq "/etc/mcp.yml"
    end

    it "falls back to XDG_CONFIG_HOME" do
      Mcpctl::Paths.config({"XDG_CONFIG_HOME" => "/x"}, home: "/H").should eq "/x/mcpctl/servers.yml"
    end

    it "falls back to ~/.config when XDG_CONFIG_HOME is unset or empty" do
      Mcpctl::Paths.config({"XDG_CONFIG_HOME" => ""}, home: "/H").should eq "/H/.config/mcpctl/servers.yml"
      Mcpctl::Paths.config({} of String => String, home: "/H").should eq "/H/.config/mcpctl/servers.yml"
    end
  end

  describe ".expand" do
    it "expands a leading ~/ only" do
      Mcpctl::Paths.expand("~/a/b", home: "/H").should eq "/H/a/b"
      Mcpctl::Paths.expand("/a/~/b", home: "/H").should eq "/a/~/b"
      Mcpctl::Paths.expand("rel", home: "/H").should eq "rel"
    end
  end
end
