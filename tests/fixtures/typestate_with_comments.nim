# Typestate with comments for testing AST parser

type
  Connection = object  # Base type
    host: string
  Disconnected = distinct Connection  ## Disconnected state
  Connected = distinct Connection  ## Connected state

# This is a block comment before typestate
typestate Connection:  # inline comment after colon
  # Comment inside typestate
  states Disconnected, Connected  # inline comment after states
  transitions:
    # Comment before transition
    Disconnected -> Connected  # inline comment after transition
    Connected -> Disconnected
