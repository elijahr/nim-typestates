# Package

version       = "0.1.0"
author        = "Elijah Rutschman"
description   = "Compile-time typestate validation for Nim"
license       = "MIT"
srcDir        = "src"
namedBin      = {"nim_typestates_bin": "nim-typestates"}.toTable
binDir        = "bin"
installExt    = @["nim"]

# Dependencies

requires "nim >= 2.0.0"

# Tasks

task verify, "Verify typestate rules in source files":
  exec "nim c -r src/nim_typestates_bin.nim verify src/"
