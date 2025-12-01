# File with syntax error for testing CLI error handling

type
  File = object
    path: string

# Missing closing bracket causes syntax error
proc broken( =
  discard
