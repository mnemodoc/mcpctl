require "./spec_helper"

describe Mcpctl::Jsonc do
  source = <<-JSONC
    // Zed settings
    {
      "theme": "x // not a comment }",
      /* block { comment */
      "context_servers": {
        // inner comment with a brace }
        "a": { "url": "http://h/{x}" },
      },
      "after": [1, 2,],
    }
    JSONC

  describe ".replace_member" do
    it "replaces only the value of the top-level member, byte for byte elsewhere" do
      result = Mcpctl::Jsonc.replace_member(source, "context_servers", %({"b": 1}))

      result.should eq <<-JSONC
        // Zed settings
        {
          "theme": "x // not a comment }",
          /* block { comment */
          "context_servers": {"b": 1},
          "after": [1, 2,],
        }
        JSONC
    end

    it "ignores a nested member of the same name" do
      nested = %({"outer": {"context_servers": {}}, "context_servers": {"k": 1}})

      Mcpctl::Jsonc.replace_member(nested, "context_servers", "{}")
        .should eq %({"outer": {"context_servers": {}}, "context_servers": {}})
    end

    it "raises when the member is absent" do
      expect_raises(Mcpctl::Error, /context_servers/) do
        Mcpctl::Jsonc.replace_member(%({"x": 1}), "context_servers", "{}")
      end
    end
  end

  describe ".set_member" do
    it "replaces the member when it exists" do
      Mcpctl::Jsonc.set_member(source, "context_servers", %({"b": 1}))
        .should eq Mcpctl::Jsonc.replace_member(source, "context_servers", %({"b": 1}))
    end

    it "appends the member as the last one of the root object when it is absent" do
      Mcpctl::Jsonc.set_member(%({\n  "theme": "x"\n}\n), "context_servers", %({"b": 1}))
        .should eq %({\n  "theme": "x",\n  "context_servers": {"b": 1}\n}\n)
    end

    it "keeps an existing trailing comma and a comment after the last member" do
      Mcpctl::Jsonc.set_member(%(// top\n{\n  "theme": "x", // why\n  "after": [1, 2],\n}\n), "context_servers", "{}")
        .should eq %(// top\n{\n  "theme": "x", // why\n  "after": [1, 2],\n  "context_servers": {}\n}\n)
      Mcpctl::Jsonc.set_member(%({\n  "theme": "x" // why\n}), "context_servers", "{}")
        .should eq %({\n  "theme": "x", // why\n  "context_servers": {}\n})
    end

    it "fills an empty root object" do
      Mcpctl::Jsonc.set_member("{}", "context_servers", "{}").should eq %({\n  "context_servers": {}\n})
    end

    it "refuses a root that is not an object" do
      expect_raises(Mcpctl::Error, "the root of the file is not an object") do
        Mcpctl::Jsonc.set_member("[]", "context_servers", "{}")
      end
    end
  end

  describe ".parse" do
    it "parses JSONC with comments and trailing commas, keeping slashes inside strings" do
      parsed = Mcpctl::Jsonc.parse(source)

      parsed["theme"].as_s.should eq "x // not a comment }"
      parsed["context_servers"]["a"]["url"].as_s.should eq "http://h/{x}"
      parsed["after"].as_a.map(&.as_i).should eq [1, 2]
    end
  end
end
