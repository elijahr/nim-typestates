## Compile-time typestate validation for Nim.
##
## This library enables formal validation of state machine patterns at compile
## time with clear error messages. Define valid states and transitions, then
## let the compiler enforce that your code follows them.
##
## Quick Start
## -----------
##
## ::
##
##   import nim_typestates
##
##   # 1. Define your base type and state types
##   type
##     File = object
##       path: string
##       handle: int
##     Closed = distinct File
##     Open = distinct File
##
##   # 2. Declare the typestate
##   typestate File:
##     states Closed, Open
##     transitions:
##       Closed -> Open
##       Open -> Closed
##
##   # 3. Implement transitions with validation
##   proc open(f: Closed, path: string): Open {.transition.} =
##     result = Open(f)
##     result.File.handle = rawOpen(path)
##
##   proc close(f: Open): Closed {.transition.} =
##     rawClose(f.File.handle)
##     result = Closed(f)
##
##   # 4. Use it - the compiler enforces valid transitions!
##   var f = Closed(File(path: "/tmp/test"))
##   let opened = f.open("/tmp/test")
##   let closed = opened.close()
##   # opened.open(...)  # Won't compile - Open can't transition to Open!
##
## Features
## --------
##
## - **Compile-time validation**: Invalid transitions fail at compile time
## - **Branching transitions**: ``Closed -> Open | Errored``
## - **Wildcard transitions**: ``* -> Closed`` (any state can close)
## - **Generated helpers**: ``FileState`` enum, ``FileStates`` union type
## - **Clear error messages**: Shows valid transitions when you make a mistake
##
## Pragmas
## -------
##
## - ``{.transition.}`` - Mark a proc as a state transition (validated)
## - ``{.notATransition.}`` - Mark a proc that operates on state but doesn't transition
##
## Generated Types
## ---------------
##
## For ``typestate File:``, the macro generates:
##
## - ``FileState`` - enum with ``fsClosed``, ``fsOpen``, etc.
## - ``FileStates`` - union type ``Closed | Open | ...``
## - ``state()`` procs for runtime state inspection
##
## See Also
## --------
##
## - `Typestate Pattern <https://cliffle.com/blog/rust-typestate/>`_
## - `Plaid Language <http://www.cs.cmu.edu/~aldrich/plaid/>`_

import std/macros
import nim_typestates/[types, parser, registry, pragmas, codegen]

export types, pragmas

macro typestate*(name: untyped, body: untyped): untyped =
  ## Define a typestate with states and valid transitions.
  ##
  ## The typestate block declares:
  ##
  ## - **states**: The distinct types that represent each state
  ## - **transitions**: Which state changes are allowed
  ##
  ## :param name: The base type name (must match your type definition)
  ## :param body: The states and transitions declarations
  ## :returns: Generated helper types (enum, union, state procs)
  ##
  ## Basic syntax::
  ##
  ##   typestate File:
  ##     states Closed, Open, Errored
  ##     transitions:
  ##       Closed -> Open | Errored    # Branching
  ##       Open -> Closed
  ##       * -> Closed                 # Wildcard
  ##
  ## What it generates:
  ##
  ## - ``FileState`` enum with ``fsClosed``, ``fsOpen``, ``fsErrored``
  ## - ``FileStates`` union type for generic procs
  ## - ``state()`` procs for runtime inspection
  ##
  ## Transition syntax:
  ##
  ## - ``A -> B`` - Simple transition
  ## - ``A -> B | C`` - Branching (can go to B or C)
  ## - ``* -> X`` - Wildcard (any state can go to X)
  ##
  ## See also: ``{.transition.}`` pragma for implementing transitions

  # Parse the typestate body
  let graph = parseTypestateBody(name, body)

  # Check if this is an extension (typestate already exists)
  let isExtension = hasTypestate(graph.name)

  # Register for later validation
  registerTypestate(graph)

  # Register sealed states for external checking
  if graph.isSealed:
    var stateNames: seq[string] = @[]
    for stateName in graph.states.keys:
      stateNames.add stateName
    registerSealedStates(graph.declaredInModule, stateNames)

  # Generate helper types (only for first definition, not extensions)
  if isExtension:
    result = newStmtList()  # Empty for extensions
  else:
    result = generateAll(graph)
