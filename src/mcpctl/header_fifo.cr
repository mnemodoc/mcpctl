lib LibC
  fun mkfifo(path : Char*, mode : ModeT) : Int
end

module Mcpctl
  # Hands HTTP headers to a child process through a named pipe, so that a
  # secret never sits in the child's argv (readable by `ps`) nor on disk.
  #
  # mcp-remote reads its `--header-file` once, at startup (parseCommandLineArgs,
  # proxy.js of 0.14.3): a FIFO that disappears right after is enough.
  module HeaderFifo
    PLACEHOLDER  = "{fifo}"
    OPEN_TIMEOUT = 60.seconds
    POLL         = 20.milliseconds

    def self.run(command : String, args : Array(String), headers : Hash(String, String),
                 open_timeout : Time::Span = OPEN_TIMEOUT) : Process::Status
      dir = File.join(Dir.tempdir, "mcpctl-#{Random::Secure.hex(8)}")
      Dir.mkdir(dir, 0o700)
      fifo = File.join(dir, "headers")

      begin
        raise Error.new("mkfifo failed: #{Errno.value}") unless LibC.mkfifo(fifo, 0o600) == 0

        child = Process.new(command, args.map { |arg| arg == PLACEHOLDER ? fifo : arg },
          input: :inherit, output: :inherit, error: :inherit)
        # From here on, a signal meant for us (the client stopping the server)
        # must reach the child, even mid-handshake.
        forward_signals(child)
        begin
          writer = open_writer(fifo, child, open_timeout)
        rescue ex
          # Never leave the child behind: it holds the client's stdio.
          stop(child)
          raise ex
        end
      ensure
        # Both ends are open (or the child is gone): the path is no longer needed,
        # and removing it before writing means it never outlives the handshake.
        File.delete?(fifo)
        Dir.delete(dir) if Dir.exists?(dir)
      end

      if writer
        begin
          writer.print(headers.join { |name, value| "#{name}: #{value}\n" })
          writer.close
        rescue ex : IO::Error
          stop(child)
          raise Error.new("cannot hand the headers to the child: #{ex.message}")
        end
      end

      child.wait
    end

    private def self.stop(child : Process) : Nil
      child.terminate rescue nil
      child.wait
    end

    # Opening a FIFO for writing blocks until a reader shows up. A non-blocking
    # open fails with ENXIO instead, which lets us give up if the child dies
    # before reading.
    private def self.open_writer(fifo : String, child : Process, timeout : Time::Span) : IO::FileDescriptor?
      deadline = Time.instant + timeout
      loop do
        fd = LibC.open(fifo, LibC::O_WRONLY | LibC::O_NONBLOCK | LibC::O_CLOEXEC, 0)
        return IO::FileDescriptor.new(fd) if fd >= 0
        raise Error.new("cannot open #{fifo}: #{Errno.value}") unless Errno.value == Errno::ENXIO
        return nil if child.terminated?
        raise Error.new("child never opened the header FIFO") if Time.instant > deadline

        sleep POLL
      end
    end

    private def self.forward_signals(child : Process) : Nil
      {Signal::TERM, Signal::INT, Signal::HUP}.each do |signal|
        signal.trap { child.signal(signal) rescue nil }
      end
    end
  end
end
