## Event-Driven Voice Assistant Satellite Workflow
##
## This example demonstrates Reified Event-Typestates using the first-class
## `events:` DSL and 2D synchronous dispatcher code generation.
##
## Features demonstrated:
## - Top-level `events:` block with parameterless and typed payload events
## - Event-driven transition syntax: `State on Event -> NextState`
## - Wildcard event transitions: `* on Event -> NextState`
## - Auto-synthesized EventKind enum and tagged union Event ADT
## - Ergonomic event constructor helpers
## - Auto-synthesized FSM type and conversion procs
## - Synchronous, compile-time exhaustive 2D dispatcher:
##     proc dispatch*(fsm: var VoiceAssistantFSM, event: VoiceAssistantEvent): bool
##
## Run: nim c -r examples/events_workflow.nim

import ../src/typestates

type
  VoiceAssistant = object
    deviceId: string
    activeKeyword: string
    activeIntent: string
    errorMessage: string

  # Distinct state types
  Idle = distinct VoiceAssistant
  Listening = distinct VoiceAssistant
  Thinking = distinct VoiceAssistant
  Speaking = distinct VoiceAssistant
  ErrorState = distinct VoiceAssistant

typestate VoiceAssistant:
  consumeOnTransition = false
  states Idle, Listening, Thinking, Speaking, ErrorState

  events:
    WakeWordDetected(keyword: string)
    SpeechEnded
    IntentResolved(intent: string)
    PlaybackFinished
    ErrorOccurred(message: string)
    Reset

  transitions:
    Idle on WakeWordDetected -> Listening
    Listening on SpeechEnded -> Thinking
    Thinking on IntentResolved -> Speaking
    Speaking on PlaybackFinished -> Idle
    * on ErrorOccurred -> ErrorState
    * on Reset -> Idle

proc main() =
  echo "=== Voice Assistant Event-Driven Typestate Workflow ==="
  echo ""

  # 1. Initialize the FSM in the Idle state
  let initialDevice = VoiceAssistant(deviceId: "satellite-hallway-01")
  var fsm = Idle(initialDevice).toVoiceAssistantFSM()
  echo "1. Initial State: ", fsm.state
  assert fsm.state == fsIdle

  # 2. Receive wake-word detection event
  echo ""
  echo "2. Event: WakeWordDetected('hey_assistant')"
  let evWake = wakeWordDetected("hey_assistant")
  let okWake = fsm.dispatch(evWake)
  echo "   Dispatch Success: ", okWake
  echo "   Current State:    ", fsm.state
  assert okWake == true
  assert fsm.state == fsListening

  # 3. Test Total Event Accounting (unhandled event rejected with false)
  echo ""
  echo "3. Event: PlaybackFinished (Invalid in Listening state)"
  let okInvalid = fsm.dispatch(playbackFinished())
  echo "   Dispatch Success: ", okInvalid, " (rejected safely, zero state corruption)"
  echo "   Current State:    ", fsm.state
  assert okInvalid == false
  assert fsm.state == fsListening

  # 4. User finishes speaking
  echo ""
  echo "4. Event: SpeechEnded"
  let okSpeech = fsm.dispatch(speechEnded())
  echo "   Dispatch Success: ", okSpeech
  echo "   Current State:    ", fsm.state
  assert okSpeech == true
  assert fsm.state == fsThinking

  # 5. Cloud/Local intent resolved
  echo ""
  echo "5. Event: IntentResolved('TurnOnKitchenLights')"
  let evIntent = intentResolved("TurnOnKitchenLights")
  let okIntent = fsm.dispatch(evIntent)
  echo "   Dispatch Success: ", okIntent
  echo "   Current State:    ", fsm.state
  assert okIntent == true
  assert fsm.state == fsSpeaking

  # 6. Audio TTS response completes
  echo ""
  echo "6. Event: PlaybackFinished"
  let okDone = fsm.dispatch(playbackFinished())
  echo "   Dispatch Success: ", okDone
  echo "   Current State:    ", fsm.state
  assert okDone == true
  assert fsm.state == fsIdle

  # 7. Wildcard Error transition from any state
  echo ""
  echo "7. Universal Wildcard Event: ErrorOccurred('Microphone I2S bus timeout')"
  let okErr = fsm.dispatch(errorOccurred("Microphone I2S bus timeout"))
  echo "   Dispatch Success: ", okErr
  echo "   Current State:    ", fsm.state
  assert okErr == true
  assert fsm.state == fsErrorState

  # 8. Universal Reset back to Idle
  echo ""
  echo "8. Universal Wildcard Event: Reset"
  let okReset = fsm.dispatch(reset())
  echo "   Dispatch Success: ", okReset
  echo "   Current State:    ", fsm.state
  assert okReset == true
  assert fsm.state == fsIdle

  echo ""
  echo "=== All Event Transitions Verified Successfully! ==="

main()
