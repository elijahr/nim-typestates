## Negative compile-time test: unhandled event in 2D state x event matrix
## Must fail compilation because (Idle, SpeechEnded) has no declared transition
## or wildcard ignore.
# expects: "Unhandled event"
import ../../../src/typestates

type
  AudioContext = object
  Idle = distinct AudioContext
  Active = distinct AudioContext

typestate AudioFSM:
  states Idle, Active
  events:
    WakeWord
    SpeechEnded

  transitions:
    (Idle, WakeWord) -> Active
    (Active, SpeechEnded) -> Idle
    # Unhandled: (Idle, SpeechEnded) has no transition and no wildcard ignore

verifyTypestates()
