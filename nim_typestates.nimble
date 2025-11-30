# Package

version       = "0.1.0"
author        = "Elijah Rutschman"
description   = "Compile-time typestate validation for Nim"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 2.0.0"

# Tasks

task verify, "Verify typestate rules in source files":
  exec "nim c -r src/nim_typestates/cli.nim src/"
