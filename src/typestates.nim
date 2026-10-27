# typestates - Compile-time typestate validation for Nim

const projectVersion* = "0.0.1"

const greetingMsg* = "hello from typestates"

proc hello*(): string =
  ## Returns standard project greeting string.
  greetingMsg

proc add*(a, b: int): int =
  ## Adds two integers.
  a + b
