# NimScript configuration for nim-typestates
# Adds path to Nim's compiler modules for ast_parser

import std/[os, strutils]

# Get nim compiler source path from nimble
let nimPkgPath = gorge("nimble path nim 2>/dev/null").strip()

if nimPkgPath.len > 0 and dirExists(nimPkgPath):
  # Use nimble-installed nim package - only add root, not compiler subdir
  switch("path", nimPkgPath)
else:
  # Fallback: find compiler from nim binary location
  let nimBin = selfExe()
  let nimDir = nimBin.parentDir.parentDir

  if dirExists(nimDir / "compiler"):
    switch("path", nimDir)
