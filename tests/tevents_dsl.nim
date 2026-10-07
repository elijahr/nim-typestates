## Test first-class 'events:' DSL, tagged union generation, and 2D dispatcher.

import std/unittest
import ../src/typestates

type
  VoiceAssistant = object
    device: string
    wakeWord: string
    beamAngle: int

  Idle = distinct VoiceAssistant
  Woken = distinct VoiceAssistant
  Listening = distinct VoiceAssistant
  Thinking = distinct VoiceAssistant

typestate VoiceAssistant:
  consumeOnTransition = false
  states Idle, Woken, Listening, Thinking
  events:
    WakeWord(wakeWord: string, beamAngle: int)
    ChimeDone(ok: bool)
    SpeechEnded
    Reset
  transitions:
    Idle on WakeWord -> Woken
    Woken on ChimeDone -> Listening
    Listening on SpeechEnded -> Thinking
    * on Reset -> Idle

suite "Events DSL & Dispatcher Codegen":
  test "Synthesized EventKind enum and Event tagged union":
    check evWakeWord is VoiceAssistantEventKind
    check evChimeDone is VoiceAssistantEventKind
    check evSpeechEnded is VoiceAssistantEventKind
    check evReset is VoiceAssistantEventKind

    # Test camelCase constructor helper
    let ev1 = wakeWord("computer", 45)
    check ev1.kind == evWakeWord
    check ev1.wakeWordWakeWord == "computer"
    check ev1.wakeWordBeamAngle == 45

    # Test init-prefixed constructor helper
    let ev2 = initWakeWord("computer", 180)
    check ev2.kind == evWakeWord
    check ev2.wakeWordWakeWord == "computer"
    check ev2.wakeWordBeamAngle == 180

    let ev3 = chimeDone(true)
    check ev3.kind == evChimeDone
    check ev3.chimeDoneOk == true

    let ev4 = speechEnded()
    check ev4.kind == evSpeechEnded

  test "Synthesized FSM type and conversion procs":
    var idleState = Idle(VoiceAssistant(device: "respeaker"))
    var fsm = idleState.toVoiceAssistantFSM()

    check fsm.state == fsIdle
    check fsm.idle.device == "respeaker"

  test "Synchronous dispatch with 2D case analysis, payload mapping, and context preservation":
    var idle = Idle(VoiceAssistant(device: "respeaker"))
    var fsm = idle.toVoiceAssistantFSM()

    # Step 1: Idle -> Woken via WakeWord (using initWakeWord)
    check fsm.dispatch(initWakeWord("computer", 180)) == true
    check fsm.state == fsWoken
    # Verify payload fields populated and prior context preserved
    check fsm.woken.wakeWord == "computer"
    check fsm.woken.beamAngle == 180
    check fsm.woken.device == "respeaker" # Prior context from Idle preserved!

    # Step 2: Invalid event in Woken (SpeechEnded is not valid from Woken)
    check fsm.dispatch(speechEnded()) == false
    check fsm.state == fsWoken # state remains intact!
    check fsm.woken.wakeWord == "computer"
    check fsm.woken.beamAngle == 180
    check fsm.woken.device == "respeaker"

    # Step 3: Woken -> Listening via ChimeDone
    check fsm.dispatch(chimeDone(true)) == true
    check fsm.state == fsListening
    check fsm.listening.device == "respeaker"
    check fsm.listening.wakeWord == "computer"
    check fsm.listening.beamAngle == 180

    # Step 4: Listening -> Thinking via SpeechEnded
    check fsm.dispatch(speechEnded()) == true
    check fsm.state == fsThinking
    check fsm.thinking.device == "respeaker"
    check fsm.thinking.wakeWord == "computer"
    check fsm.thinking.beamAngle == 180

    # Step 5: Wildcard transition (* on Reset -> Idle)
    check fsm.dispatch(reset()) == true
    check fsm.state == fsIdle
    check fsm.idle.device == "respeaker"
