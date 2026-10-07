## Test first-class 'events:' DSL, tagged union generation, and 2D dispatcher.

import std/unittest
import ../src/typestates

type
  VoiceAssistant = object
    device: string

  Idle = distinct VoiceAssistant
  Woken = distinct VoiceAssistant
  Listening = distinct VoiceAssistant
  Thinking = distinct VoiceAssistant

typestate VoiceAssistant:
  consumeOnTransition = false
  states Idle, Woken, Listening, Thinking
  events:
    WakeWord(word: string, angle: int)
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

    let ev1 = wakeWord("computer", 45)
    check ev1.kind == evWakeWord
    check ev1.wakeWordWord == "computer"
    check ev1.wakeWordAngle == 45

    let ev2 = chimeDone(true)
    check ev2.kind == evChimeDone
    check ev2.chimeDoneOk == true

    let ev3 = speechEnded()
    check ev3.kind == evSpeechEnded

  test "Synthesized FSM type and conversion procs":
    var idleState = Idle(VoiceAssistant(device: "respeaker"))
    var fsm = idleState.toVoiceAssistantFSM()

    check fsm.state == fsIdle

  test "Synchronous dispatch with 2D case analysis":
    var idle = Idle(VoiceAssistant(device: "respeaker"))
    var fsm = idle.toVoiceAssistantFSM()

    # Step 1: Idle -> Woken via WakeWord
    check fsm.dispatch(wakeWord("jarvis", 90)) == true
    check fsm.state == fsWoken

    # Step 2: Invalid event in Woken (SpeechEnded is not valid from Woken)
    check fsm.dispatch(speechEnded()) == false
    check fsm.state == fsWoken # state remains intact!

    # Step 3: Woken -> Listening via ChimeDone
    check fsm.dispatch(chimeDone(true)) == true
    check fsm.state == fsListening

    # Step 4: Listening -> Thinking via SpeechEnded
    check fsm.dispatch(speechEnded()) == true
    check fsm.state == fsThinking

    # Step 5: Wildcard transition (* on Reset -> Idle)
    check fsm.dispatch(reset()) == true
    check fsm.state == fsIdle
