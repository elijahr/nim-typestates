## Command-line verification tool for nim-typestates.
##
## Usage:
##   nim_typestates check [paths...]
##   nim_typestates check src/
##
## Parses source files and verifies typestate rules.

import std/[os, strutils, sequtils, parseopt, tables, strformat]

type
  VerifyResult* = object
    errors*: seq[string]
    warnings*: seq[string]
    transitionsChecked*: int
    filesChecked*: int

proc parseNimFile(path: string): VerifyResult =
  ## Parse a Nim file and extract typestate information.
  ## Uses simple regex-based parsing for robustness.
  result = VerifyResult()
  result.filesChecked = 1

  if not fileExists(path):
    result.errors.add "File not found: " & path
    return

  let content = readFile(path)
  let lines = content.splitLines()

  # Simple state machine parser
  var inTypestateBlock = false
  var currentTypestate = ""
  var typestateStates: Table[string, seq[string]]  # typestate -> states
  var typestateSealed: Table[string, bool]
  var typestateStrict: Table[string, bool]

  for i, line in lines:
    let trimmed = line.strip()

    # Detect typestate block start
    if trimmed.startsWith("typestate "):
      inTypestateBlock = true
      currentTypestate = trimmed.split(" ")[1].replace(":", "")
      typestateStates[currentTypestate] = @[]
      typestateSealed[currentTypestate] = true  # default
      typestateStrict[currentTypestate] = true  # default

    # Detect states declaration
    if inTypestateBlock and trimmed.startsWith("states "):
      let statesPart = trimmed.replace("states ", "")
      let states = statesPart.split(",").mapIt(it.strip())
      typestateStates[currentTypestate] = states

    # Detect flags
    if inTypestateBlock and "isSealed = false" in trimmed:
      typestateSealed[currentTypestate] = false
    if inTypestateBlock and "strictTransitions = false" in trimmed:
      typestateStrict[currentTypestate] = false

    # Detect end of typestate block (next top-level declaration)
    if inTypestateBlock and not trimmed.startsWith(" ") and not trimmed.startsWith("\t"):
      if trimmed.startsWith("proc ") or trimmed.startsWith("func "):
        inTypestateBlock = false

    # Check procs
    if trimmed.startsWith("proc ") or trimmed.startsWith("func "):
      let hasTransition = "{.transition.}" in trimmed or "{. transition .}" in trimmed
      let hasNotATransition = "{.notATransition.}" in trimmed or "{. notATransition .}" in trimmed

      # Extract first param type (basic parsing)
      if "(" in trimmed and ":" in trimmed:
        let paramsPart = trimmed.split("(")[1].split(")")[0]
        if ":" in paramsPart:
          let firstParamType = paramsPart.split(":")[1].split(",")[0].split(")")[0].strip()

          # Check if this type is a state
          for tsName, states in typestateStates:
            if firstParamType in states:
              if not hasTransition and not hasNotATransition:
                if typestateStrict.getOrDefault(tsName, true):
                  result.errors.add fmt"{path}:{i+1} - Unmarked proc on state '{firstParamType}' (strictTransitions enabled)"
                else:
                  result.warnings.add fmt"{path}:{i+1} - Unmarked proc on state '{firstParamType}'"
              else:
                result.transitionsChecked += 1

proc verify*(paths: seq[string]): VerifyResult =
  ## Verify all Nim files in the given paths.
  result = VerifyResult()

  for path in paths:
    if path.endsWith(".nim"):
      let fileResult = parseNimFile(path)
      result.errors.add fileResult.errors
      result.warnings.add fileResult.warnings
      result.transitionsChecked += fileResult.transitionsChecked
      result.filesChecked += fileResult.filesChecked
    elif dirExists(path):
      for file in walkDirRec(path):
        if file.endsWith(".nim"):
          let fileResult = parseNimFile(file)
          result.errors.add fileResult.errors
          result.warnings.add fileResult.warnings
          result.transitionsChecked += fileResult.transitionsChecked
          result.filesChecked += fileResult.filesChecked

when isMainModule:
  var paths: seq[string] = @[]

  for kind, key, val in getopt():
    case kind
    of cmdArgument:
      paths.add key
    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h":
        echo "Usage: nim_typestates check [paths...]"
        echo "  Verify typestate rules in Nim source files."
        quit(0)
    of cmdEnd:
      discard

  if paths.len == 0:
    paths = @["src/"]

  let result = verify(paths)

  echo "Checked ", result.filesChecked, " files, ", result.transitionsChecked, " transitions"

  for warning in result.warnings:
    echo "WARNING: ", warning

  for error in result.errors:
    echo "ERROR: ", error

  if result.errors.len > 0:
    echo "\n", result.errors.len, " error(s) found"
    quit(1)
  else:
    echo "\nAll checks passed!"
    quit(0)
