## Compile-time typestate validation for Nim.
##
## Example:
##   ```nim
##   type
##     File = object
##       path: string
##     Closed = distinct File
##     Open = distinct File
##
##   typestate File:
##     states: Closed, Open
##     transitions:
##       Closed -> Open
##       Open -> Closed
##   ```

import std/macros
import nim_typestates/[types, parser, registry, pragmas, codegen]

export types, pragmas

macro typestate*(name: untyped, body: untyped): untyped =
  ## Define a typestate with states and transitions.
  ##
  ## Example:
  ##   ```nim
  ##   typestate File:
  ##     states Closed, Open
  ##     transitions:
  ##       Closed -> Open
  ##       Open -> Closed
  ##   ```

  # Parse the typestate body
  let graph = parseTypestateBody(name, body)

  # Register for later validation
  registerTypestate(graph)

  # Generate helper types
  result = generateAll(graph)
