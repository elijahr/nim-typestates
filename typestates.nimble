# Package

version       = "0.2.1"
author        = "elijahr <elijahr+typestates@gmail.com>"
description   = "Compile-time typestate validation for Nim"
license       = "MIT"
srcDir        = "src"
namedBin      = {"typestates_bin": "typestates"}.toTable
binDir        = "bin"
installExt    = @["nim"]

# Dependencies

requires "nim >= 2.2.0"

# Tasks

task buildCli, "Build the CLI tool":
  exec "nim c -o:bin/typestates src/typestates_bin.nim"

task verify, "Verify typestate rules in source files":
  exec "nim c -r src/typestates_bin.nim verify src/"

task compileExamples, "Compile all example files":
  for file in listFiles("examples"):
    if file.endsWith(".nim"):
      echo "Compiling: ", file
      exec "nim c --hints:off " & file
  # Also compile snippets
  for file in listFiles("examples/snippets"):
    if file.endsWith(".nim"):
      echo "Compiling: ", file
      exec "nim c --hints:off " & file
  echo "All examples compiled successfully!"

task generateDocs, "Generate documentation assets and build docs":
  echo "Building typestates CLI..."
  exec "nimble build -y"
  echo "Generating diagrams from snippets..."
  exec "python3 scripts/generate_diagrams.py"
  echo "Building documentation..."
  exec "mkdocs build"
  echo "Documentation generated successfully!"
