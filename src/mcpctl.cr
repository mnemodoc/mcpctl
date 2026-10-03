require "./mcpctl/cli"

exit Mcpctl::CLI.run(ARGV.dup)
