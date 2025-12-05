## Test: Converter with transition pragma works
import ../../../src/typestates

type
  Auth = object
    token: string
  Unauthenticated = distinct Auth
  Authenticated = distinct Auth

typestate Auth:
  strictTransitions = false
  states Unauthenticated, Authenticated
  transitions:
    Unauthenticated -> Authenticated

converter authenticate(a: Unauthenticated): Authenticated {.transition.} =
  var auth = a.Auth
  auth.token = "valid_token"
  Authenticated(auth)

let unauth = Unauthenticated(Auth(token: ""))
let authed: Authenticated = unauth  # Implicit conversion via converter
doAssert authed.Auth.token == "valid_token"
echo "converter_transition test passed"
