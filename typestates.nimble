# Package

version       = "0.1.0"
author        = "elijahr <elijahr+typestates@gmail.com>"
description   = "Compile-time typestate validation for Nim"
license       = "MIT"
srcDir        = "src"
namedBin      = {"typestates_bin": "typestates"}.toTable
binDir        = "bin"
installExt    = @["nim"]

# Dependencies

requires "nim >= 2.0.0"

# Tasks

task buildCli, "Build the CLI tool":
  exec "nim c -o:bin/typestates src/typestates_bin.nim"

task verify, "Verify typestate rules in source files":
  exec "nim c -r src/typestates_bin.nim verify src/"
