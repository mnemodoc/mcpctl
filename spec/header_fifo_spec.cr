require "./spec_helper"

describe Mcpctl::HeaderFifo do
  it "hands the headers to the child through a FIFO that is gone once the child has read it" do
    dir = File.tempname("mcpctl-spec")
    Dir.mkdir(dir)
    out_file = File.join(dir, "received")

    status = Mcpctl::HeaderFifo.run(
      "/bin/sh", ["-c", %(cat "$1" > "$2"; if [ -e "$(dirname "$1")" ]; then echo present; else echo gone; fi > "$2.count"; exit 3), "sh", Mcpctl::HeaderFifo::PLACEHOLDER, out_file],
      {"Host" => "h.example", "Authorization" => "Bearer abc"},
    )

    File.read(out_file).should eq "Host: h.example\nAuthorization: Bearer abc\n"
    status.exit_code.should eq 3
    File.read("#{out_file}.count").strip.should eq "gone"
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "terminates a child that never opens the FIFO instead of leaving it running" do
    dir = File.tempname("mcpctl-spec")
    Dir.mkdir(dir)
    pid_file = File.join(dir, "pid")

    expect_raises(Mcpctl::Error, "child never opened the header FIFO") do
      Mcpctl::HeaderFifo.run(
        "/bin/sh", ["-c", %(echo $$ > "$2"; exec sleep 30), "sh", Mcpctl::HeaderFifo::PLACEHOLDER, pid_file],
        {"Authorization" => "Bearer abc"}, open_timeout: 1.second)
    end

    Process.exists?(File.read(pid_file).to_i64).should be_false
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "never leaves the secret in the child's arguments" do
    dir = File.tempname("mcpctl-spec")
    Dir.mkdir(dir)
    out_file = File.join(dir, "argv")

    Mcpctl::HeaderFifo.run(
      "/bin/sh", ["-c", %(echo "$@" > "$2"; cat "$1" > /dev/null), "sh", Mcpctl::HeaderFifo::PLACEHOLDER, out_file],
      {"Authorization" => "Bearer abc"},
    )

    File.read(out_file).should_not contain "Bearer abc"
  ensure
    FileUtils.rm_rf(dir) if dir
  end
end
