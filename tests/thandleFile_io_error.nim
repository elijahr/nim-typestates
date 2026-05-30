## Regression test for Gemini round-3 HIGH finding on
## `parseTypestatesAstWithNodes.handleFile`:
##
## Pre-fix the `handleFile` closure only caught `ParseError`. The underlying
## `parsePNode` call chain (`readFile` -> compiler I/O) can also raise
## `IOError` / `OSError` for permission-denied, unreadable, or otherwise
## inaccessible `.nim` files. An uncaught `IOError` aborts the entire batch
## verification — `typestates verify --format=github src/` would crash on
## the first unreadable file instead of recording a structured failure and
## continuing with the rest of the batch, defeating the whole point of the
## per-file failure routing introduced in earlier rounds.
##
## This test creates a `.nim` file, chmods it `0o000` (unreadable), runs
## `parseTypestatesAstWithNodes`, and asserts:
##   1. the call returns normally (no escaping IOError)
##   2. the unreadable file is recorded in `parse.failures`
##   3. a sibling readable file in the same batch is still parsed
##      (filesChecked > 0, demonstrating the batch did not abort)
##
## If the test is run as root, `chmod 0o000` does not actually prevent
## reading. In that case we skip with an explanatory message rather than
## report a false green — root masking the failure mode is itself a hazard
## the operator should know about.

import std/[unittest, os, tables]
when not defined(windows):
  import std/posix
import ../src/typestates/ast_parser

suite "handleFile IOError handling (Gemini round-3 HIGH)":
  test "unreadable .nim file produces structured failure, does not abort batch":
    when defined(windows):
      skip()
    else:
      if geteuid() == 0:
        # Running as root: chmod 0o000 does not block read access, so we
        # cannot exercise the IOError path. Skip rather than fake-pass.
        skip()
      else:
        let tmpDir = getTempDir() / "thandleFile_io_error_test"
        createDir(tmpDir)
        defer:
          # Best-effort cleanup: restore perms so removeDir can recurse.
          for f in walkDirRec(tmpDir):
            discard chmod(f.cstring, 0o600)
          removeDir(tmpDir)

        let unreadable = tmpDir / "unreadable.nim"
        let readable = tmpDir / "readable.nim"
        writeFile(unreadable, "discard\n")
        writeFile(
          readable,
          """
import typestates

typestate Sample:
  states A, B
  initial A
  terminal B
  A -> B
""",
        )
        # Strip read permission on the unreadable file. After this, `readFile`
        # inside `parsePNode` raises IOError.
        check chmod(unreadable.cstring, 0o000) == 0

        # Must not raise. Pre-fix this aborts with an uncaught IOError.
        let project = parseTypestatesAstWithNodes(@[unreadable, readable])

        # The unreadable file MUST appear in failures (not just be silently
        # dropped).
        var foundUnreadable = false
        for f in project.parse.failures:
          if f.path == unreadable:
            foundUnreadable = true
            break
        check foundUnreadable

        # The readable file MUST still have been parsed — the batch did not
        # abort. filesChecked counts successfully-parsed files only.
        check project.parse.filesChecked >= 1
        check project.nodes.hasKey(readable)
