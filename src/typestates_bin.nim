## Binary entry point for typestates CLI.
## Installed as `typestates` command.

import std/[os, strutils]
import typestates/cli

proc showHelp() =
  echo "typestates - Compile-time typestate validation for Nim"
  echo ""
  echo "Usage:"
  echo "  typestates verify [paths...]   Verify typestate rules"
  echo "  typestates dot [paths...]      Generate unified GraphViz DOT output"
  echo "  typestates dot --separate [paths...]  Generate separate DOT per typestate"
  echo ""
  echo "Options:"
  echo "  -h, --help      Show this help"
  echo "  -v, --version   Show version"
  echo "  --separate      For 'dot' command: generate separate graph per typestate"
  echo "  --no-style      For 'dot' command: output minimal DOT without styling"
  echo ""
  echo "Examples:"
  echo "  typestates verify src/"
  echo "  typestates dot src/ > typestates.dot"
  echo "  typestates dot --separate src/ > typestates.dot"
  echo "  typestates dot src/ | dot -Tpng -o typestates.png"
  echo "  typestates dot --no-style src/ | dot -Tpng -o custom.png"
  echo ""
  echo "Notes:"
  echo "  Files must be valid Nim syntax. Syntax errors cause verification"
  echo "  to fail with a clear error message. Uses Nim's AST parser for"
  echo "  accurate extraction of typestate definitions."
  echo ""
  echo "  The 'dot' command generates a unified graph by default, showing all"
  echo "  typestates with cross-typestate bridges as dashed edges. Use --separate"
  echo "  to generate individual graphs for each typestate."
  echo ""
  echo "  Use --no-style for minimal DOT output that's easier to customize with"
  echo "  your own colors, fonts, and styling."

proc showVersion() =
  echo "typestates 0.1.0"

when isMainModule:
  var args: seq[string] = @[]

  for i in 1..paramCount():
    args.add paramStr(i)

  if args.len == 0:
    showHelp()
    quit(0)

  let command = args[0]
  let paths = if args.len > 1: args[1..^1] else: @["."]

  case command
  of "help", "-h", "--help":
    showHelp()
    quit(0)

  of "version", "-v", "--version":
    showVersion()
    quit(0)

  of "verify":
    try:
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
    except ParseError as e:
      echo "ERROR: ", e.msg
      quit(1)

  of "dot":
    try:
      # Parse flags and paths from args
      var separateFlag = false
      var noStyleFlag = false
      var pathArgs: seq[string] = @[]

      for arg in paths:
        if arg == "--separate":
          separateFlag = true
        elif arg == "--no-style":
          noStyleFlag = true
        elif not arg.startsWith("-"):
          pathArgs.add arg

      if pathArgs.len == 0:
        pathArgs = @["."]

      let parseResult = parseTypestates(pathArgs)

      if parseResult.typestates.len == 0:
        echo "No typestates found in ", pathArgs.join(", ")
        quit(1)

      if separateFlag:
        # Generate separate graph for each typestate
        for ts in parseResult.typestates:
          echo generateSeparateDot(ts, noStyleFlag)
          echo ""
      else:
        # Generate unified graph
        echo generateUnifiedDot(parseResult.typestates, noStyleFlag)

      quit(0)
    except ParseError as e:
      echo "ERROR: ", e.msg
      quit(1)

  else:
    echo "Unknown command: ", command
    echo "Run 'typestates --help' for usage."
    quit(1)
