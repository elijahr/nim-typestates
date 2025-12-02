# NimScript configuration for nim-typestates
# Adds path to Nim's compiler modules for CLI tool

import std/os

# Find the Nim installation directory from the compiler path
# selfExe() returns path to nim binary like /path/to/nim/bin/nim
let nimBin = selfExe()
let nimDir = nimBin.parentDir.parentDir
let compilerPath = nimDir / "compiler"

if dirExists(compilerPath):
  switch("path", compilerPath)
  # Also add the parent to allow compiler/* imports
  switch("path", nimDir)
