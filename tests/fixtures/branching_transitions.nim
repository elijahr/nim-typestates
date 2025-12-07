# Typestate with branching transitions

type
  Request = object
    url: string
  Pending = distinct Request
  Success = distinct Request
  Failed = distinct Request
  Cancelled = distinct Request

typestate Request:
  states Pending, Success, Failed, Cancelled
  transitions:
    Pending -> (Success | Failed | Cancelled) as RequestResult
    Failed -> Pending
