# ameba:disable Lint/SpecFilename -- run explicitly by `mise dev:spec-secret-tool`, kept out of the `*_spec.cr` glob on purpose
# Integration spec against a real Secret Service, through the real secret-tool.
#
# Not named *_spec.cr on purpose: `crystal spec` must not pick it up on macOS,
# nor on a Linux machine without an unlocked keyring. It runs through
# `mise dev:spec-secret-tool`, which starts a D-Bus session and an unlocked
# gnome-keyring around it (the Linux CI jobs install both).
{% unless flag?(:linux) %}
  {% raise "spec/integration/secret_tool.cr needs Linux and a Secret Service: run it through `mise dev:spec-secret-tool`" %}
{% end %}

require "../spec_helper"

private SERVICE_PREFIX = "mcpctl.integration.#{Process.pid}"

# Stores through stdin, as the README tells users to: never in argv.
private def store(name : String, value : String) : String
  service = "#{SERVICE_PREFIX}.#{name}"
  status = Process.run("secret-tool", ["store", "--label=#{service}", "service", service],
    input: IO::Memory.new(value), output: Process::Redirect::Close, error: :inherit)
  raise "secret-tool store #{service} failed" unless status.success?
  service
end

describe "Mcpctl::Secrets against the Secret Service" do
  {
    "a plain value"          => "Bearer abc",
    "a trailing newline"     => "ends with a newline\n",
    "surrounding blanks"     => "  padded ",
    "non-ASCII characters"   => "mot-de-passe-café",
    "an embedded newline"    => "line1\nline2",
    "quotes and backslashes" => %(a"b\\c),
  }.each do |label, value|
    it "reads back #{label} byte for byte" do
      Mcpctl::Secrets.get(store(label.gsub(' ', '-'), value)).should eq value
    end
  end

  it "returns nil for an entry that does not exist" do
    Mcpctl::Secrets.get("#{SERVICE_PREFIX}.absent").should be_nil
  end
end
