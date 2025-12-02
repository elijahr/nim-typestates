## Module-level analysis for typestate validation.
##
## This module is now implemented via:
## - Compile-time checking in `pragmas.nim` (strictTransitions, isSealed)
## - `verifyTypestates()` macro in `verify.nim`
## - CLI tool in `cli.nim` for full-project analysis
##
## See the verify module for the implementation.

import verify
export verify
