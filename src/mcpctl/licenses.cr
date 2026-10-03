require "baked_file_system"

module Mcpctl
  # Third-party notices a statically linked binary has to carry, baked at
  # compile time. The folder is assembled by the `dev:licenses` task (or the
  # `licenses` target of Makefile.release) from licenses.manifest.
  class Licenses
    extend BakedFileSystem

    bake_folder "../../licenses"
  end
end
