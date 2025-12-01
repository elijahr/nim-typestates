## Binary entry point for nim-typestates CLI.
## Installed as `nim-typestates` command.

import std/[os, strutils]
import nim_typestates/cli

proc showHelp() =
  echo "nim-typestates - Compile-time typestate validation for Nim"
  echo ""
  echo "Usage:"
  echo "  nim-typestates verify [paths...]   Verify typestate rules"
  echo "  nim-typestates dot [paths...]      Generate GraphViz DOT output"
  echo ""
  echo "Options:"
  echo "  -h, --help      Show this help"
  echo "  -v, --version   Show version"
  echo ""
  echo "Examples:"
  echo "  nim-typestates verify src/"
  echo "  nim-typestates dot src/ > typestates.dot"
  echo "  nim-typestates dot src/ | dot -Tpng -o typestates.png"
  echo ""
  echo "Notes:"
  echo "  Files must be valid Nim syntax. Syntax errors cause verification"
  echo "  to fail with a clear error message. Uses Nim's AST parser for"
  echo "  accurate extraction of typestate definitions."

proc showVersion() =
  echo "nim-typestates 0.1.0"

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
      let parseResult = parseTypestates(paths)

      if parseResult.typestates.len == 0:
        echo "No typestates found in ", paths.join(", ")
        quit(1)

      for ts in parseResult.typestates:
        echo generateDot(ts)
        echo ""

      quit(0)
    except ParseError as e:
      echo "ERROR: ", e.msg
      quit(1)

  else:
    echo "Unknown command: ", command
    echo "Run 'nim-typestates --help' for usage."
    quit(1)
