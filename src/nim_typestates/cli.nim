## Command-line tool for nim-typestates.
##
## Usage::
##
##   nim-typestates verify [paths...]
##   nim-typestates dot [paths...]
##
## Parses source files and verifies typestate rules or generates DOT output.

import std/[os, strutils, sequtils, tables, strformat]

type
  ParsedTransition* = object
    ## A transition parsed from source code.
    ##
    ## :var fromState: Source state name, or "*" for wildcard
    ## :var toStates: List of destination state names
    ## :var isWildcard: True if this is a wildcard transition
    fromState*: string
    toStates*: seq[string]
    isWildcard*: bool

  ParsedTypestate* = object
    ## A typestate definition parsed from source code.
    ##
    ## :var name: The typestate name (e.g., "File")
    ## :var states: List of state type names
    ## :var transitions: List of parsed transitions
    ## :var isSealed: Whether the typestate is sealed
    ## :var strictTransitions: Whether strict mode is enabled
    name*: string
    states*: seq[string]
    transitions*: seq[ParsedTransition]
    isSealed*: bool
    strictTransitions*: bool

  VerifyResult* = object
    ## Results from verifying source files.
    ##
    ## :var errors: List of error messages
    ## :var warnings: List of warning messages
    ## :var transitionsChecked: Count of transitions validated
    ## :var filesChecked: Count of files processed
    errors*: seq[string]
    warnings*: seq[string]
    transitionsChecked*: int
    filesChecked*: int

  ParseResult* = object
    ## Results from parsing source files for typestates.
    ##
    ## :var typestates: List of parsed typestate definitions
    ## :var filesChecked: Count of files processed
    typestates*: seq[ParsedTypestate]
    filesChecked*: int

proc parseTypestatesFromFile(path: string): ParseResult =
  ## Parse a Nim file and extract typestate definitions.
  ##
  ## :param path: Path to the Nim source file
  ## :returns: Parsed typestates and file count
  result = ParseResult()
  result.filesChecked = 1

  if not fileExists(path):
    return

  let content = readFile(path)
  let lines = content.splitLines()

  var inTypestateBlock = false
  var inTransitionsBlock = false
  var currentTypestate: ParsedTypestate
  var blockIndent = 0

  for line in lines:
    let trimmed = line.strip()

    # Detect typestate block start
    if trimmed.startsWith("typestate "):
      inTypestateBlock = true
      inTransitionsBlock = false
      currentTypestate = ParsedTypestate(
        name: trimmed.split(" ")[1].replace(":", ""),
        states: @[],
        transitions: @[],
        isSealed: true,
        strictTransitions: true
      )
      blockIndent = line.len - line.strip(trailing = false).len

    # Detect states declaration
    if inTypestateBlock and trimmed.startsWith("states "):
      let statesPart = trimmed.replace("states ", "")
      currentTypestate.states = statesPart.split(",").mapIt(it.strip())

    # Detect transitions block
    if inTypestateBlock and trimmed == "transitions:":
      inTransitionsBlock = true
      continue

    # Parse transition lines
    if inTransitionsBlock and "->" in trimmed:
      let parts = trimmed.split("->")
      if parts.len == 2:
        let fromPart = parts[0].strip()
        let toPart = parts[1].strip()
        let toStates = toPart.split("|").mapIt(it.strip())
        currentTypestate.transitions.add ParsedTransition(
          fromState: fromPart,
          toStates: toStates,
          isWildcard: fromPart == "*"
        )

    # Detect flags
    if inTypestateBlock and "isSealed = false" in trimmed:
      currentTypestate.isSealed = false
    if inTypestateBlock and "strictTransitions = false" in trimmed:
      currentTypestate.strictTransitions = false

    # Detect end of typestate block (next top-level declaration)
    if inTypestateBlock and trimmed.len > 0:
      let currentIndent = line.len - line.strip(trailing = false).len
      if currentIndent <= blockIndent and not trimmed.startsWith("typestate"):
        if trimmed.startsWith("proc ") or trimmed.startsWith("func ") or
           trimmed.startsWith("type ") or trimmed.startsWith("import "):
          inTypestateBlock = false
          inTransitionsBlock = false
          if currentTypestate.states.len > 0:
            result.typestates.add currentTypestate

  # Don't forget the last typestate if file ends
  if inTypestateBlock and currentTypestate.states.len > 0:
    result.typestates.add currentTypestate

proc parseTypestates*(paths: seq[string]): ParseResult =
  ## Parse all Nim files in the given paths for typestates.
  ##
  ## :param paths: List of file or directory paths to scan
  ## :returns: All parsed typestates and total file count
  result = ParseResult()

  for path in paths:
    if path.endsWith(".nim"):
      let fileResult = parseTypestatesFromFile(path)
      result.typestates.add fileResult.typestates
      result.filesChecked += fileResult.filesChecked
    elif dirExists(path):
      for file in walkDirRec(path):
        if file.endsWith(".nim"):
          let fileResult = parseTypestatesFromFile(file)
          result.typestates.add fileResult.typestates
          result.filesChecked += fileResult.filesChecked

proc generateDot*(ts: ParsedTypestate): string =
  ## Generate GraphViz DOT output for a typestate.
  ##
  ## Creates a directed graph representation suitable for rendering
  ## with ``dot``, ``neato``, or other GraphViz tools.
  ##
  ## :param ts: The parsed typestate to visualize
  ## :returns: DOT format string
  ##
  ## Example output::
  ##
  ##   digraph File {
  ##     rankdir=LR;
  ##     node [shape=box];
  ##
  ##     Closed;
  ##     Open;
  ##
  ##     Closed -> Open;
  ##     Open -> Closed;
  ##   }
  var lines: seq[string] = @[]

  lines.add "digraph " & ts.name & " {"
  lines.add "  rankdir=LR;"
  lines.add "  node [shape=box];"
  lines.add ""

  # Add nodes
  for state in ts.states:
    lines.add "  " & state & ";"

  lines.add ""

  # Add edges
  for trans in ts.transitions:
    if trans.isWildcard:
      for fromState in ts.states:
        for toState in trans.toStates:
          lines.add "  " & fromState & " -> " & toState & " [style=dashed];"
    else:
      for toState in trans.toStates:
        lines.add "  " & trans.fromState & " -> " & toState & ";"

  lines.add "}"
  result = lines.join("\n")

proc verifyFile(path: string, typestateStates: Table[string, seq[string]],
                typestateStrict: Table[string, bool]): VerifyResult =
  ## Verify procs in a file against known typestates.
  ##
  ## :param path: Path to the Nim source file
  ## :param typestateStates: Map of typestate name to state names
  ## :param typestateStrict: Map of typestate name to strictTransitions flag
  ## :returns: Verification results with errors and warnings
  result = VerifyResult()
  result.filesChecked = 1

  if not fileExists(path):
    result.errors.add "File not found: " & path
    return

  let content = readFile(path)
  let lines = content.splitLines()

  for i, line in lines:
    let trimmed = line.strip()

    if trimmed.startsWith("proc ") or trimmed.startsWith("func "):
      let hasTransition = "{.transition.}" in trimmed or "{. transition .}" in trimmed
      let hasNotATransition = "{.notATransition.}" in trimmed or "{. notATransition .}" in trimmed

      if "(" in trimmed and ":" in trimmed:
        let paramsPart = trimmed.split("(")[1].split(")")[0]
        if ":" in paramsPart:
          let firstParamType = paramsPart.split(":")[1].split(",")[0].split(")")[0].strip()

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
  ##
  ## Checks that all procs operating on state types are properly marked
  ## with ``{.transition.}`` or ``{.notATransition.}``.
  ##
  ## :param paths: List of file or directory paths to verify
  ## :returns: Verification results with errors, warnings, and counts
  result = VerifyResult()

  # First pass: collect all typestates
  let parseResult = parseTypestates(paths)
  var typestateStates: Table[string, seq[string]]
  var typestateStrict: Table[string, bool]

  for ts in parseResult.typestates:
    typestateStates[ts.name] = ts.states
    typestateStrict[ts.name] = ts.strictTransitions

  # Second pass: verify procs
  for path in paths:
    if path.endsWith(".nim"):
      let fileResult = verifyFile(path, typestateStates, typestateStrict)
      result.errors.add fileResult.errors
      result.warnings.add fileResult.warnings
      result.transitionsChecked += fileResult.transitionsChecked
      result.filesChecked += fileResult.filesChecked
    elif dirExists(path):
      for file in walkDirRec(path):
        if file.endsWith(".nim"):
          let fileResult = verifyFile(file, typestateStates, typestateStrict)
          result.errors.add fileResult.errors
          result.warnings.add fileResult.warnings
          result.transitionsChecked += fileResult.transitionsChecked
          result.filesChecked += fileResult.filesChecked
