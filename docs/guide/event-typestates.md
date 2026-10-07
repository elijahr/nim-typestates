# Event-Driven Typestates

Event-driven typestates extend compile-time state machine verification with first-class event declarations and synchronous 2D dispatchers. Instead of manually matching on states and event payloads, the `typestate` macro synthesizes a tagged union event ADT, constructor helpers, an FSM wrapper, and an exhaustive synchronous dispatcher.

This architecture implements **Reified Event-Typestates**, ensuring compile-time exhaustiveness, deterministic state transitions, and zero dynamic allocation overhead on embedded targets like ESP32-S3.

---

## The 5 Core Invariants

Systems built with Reified Event-Typestates adhere to five foundational architectural invariants:

1. **Zero-Variable-Branching Invariant (Event Reification)**:
   - State transition handlers never inspect the runtime *type* of an event using loose `if` or `case` conditions.
   - The pairing of `(State S, Event E)` directly instantiates or transitions into a dedicated, typed state.
   - Any dynamic payload evaluation (e.g. validating an error code or checking wake-word strings) occurs in an explicit, typed Evaluation State.

2. **Synchronous Run-to-Completion Transitions**:
   - State transitions are 100% synchronous and instantaneous.
   - Asynchronous jobs (network I/O, audio streaming, LLM inference) are never awaited inside state transitions; they are kicked off detached and post completion events back to the event queue.

3. **Total Event Accounting**:
   - Every state explicitly declares its behavior for every possible event in the system.
   - Unhandled events transition through an explicit `*Ignored` state or return `false` from the dispatcher without corrupting active state. No events are dropped silently.

4. **Decoupled Transport Supervision**:
   - Transport and network health are supervisory observers, not enum states inside the primary business/voice lifecycle FSM.
   - Grace periods (e.g. 3-second debounce) prevent fleeting network jitter from corrupting active operational queries.

5. **Deterministic Hardware / Output Binding**:
   - Hardware registers, LED rings, display indicators, and actuators are pure projections of the current FSM state.

---

## DSL Syntax

### Declaring Events

Declare all events that your state machine recognizes inside an `events:` block. Events can be parameterless or carry typed payloads:

```nim
typestate VoiceAssistant:
  states Idle, Listening, Thinking, Speaking, ErrorState

  events:
    WakeWordDetected(name: string)
    SpeechEnded
    IntentResolved(intent: string, confidence: float)
    TtsFinished
    Reset
    Failed(reason: string, code: int)
```

### Transitioning on Events

Use the `State on Event -> NextState` syntax to bind state transitions to specific events:

```nim
typestate VoiceAssistant:
  states Idle, Listening, Thinking, Speaking, ErrorState

  events:
    WakeWordDetected(name: string)
    SpeechEnded
    IntentResolved(intent: string)
    TtsFinished
    Reset
    Failed(reason: string)

  transitions:
    Idle on WakeWordDetected -> Listening
    Listening on SpeechEnded -> Thinking
    Thinking on IntentResolved -> Speaking
    Speaking on TtsFinished -> Idle
    * on Reset -> Idle
    * on Failed -> ErrorState
```

Transitions can also use the wildcard `* on Event -> NextState` to transition from any source state when a universal event (like `Reset` or `Failed`) occurs.

### Compile-Time Validation

The macro verifies that every event referenced in a transition is declared in the `events:` block. If a transition references an undeclared event, compilation fails with a clear error:

```nim
# Error: Undeclared event 'UnknownEvent' in transition. Declare it in an 'events:' block.
Idle on UnknownEvent -> Listening
```

---

## Generated Artifacts

When an `events:` block is present in the `typestate` definition, the macro automatically synthesizes five typed artifacts:

### 1. Event Kind Enum (`<Name>EventKind`)

An enum listing all declared events, prefixed with `ev`:

```nim
type
  VoiceAssistantEventKind* = enum
    evWakeWordDetected
    evSpeechEnded
    evIntentResolved
    evTtsFinished
    evReset
    evFailed
```

### 2. Event Tagged Union (`<Name>Event`)

A tagged union object variant that packages event parameters safely without memory overhead:

```nim
type
  VoiceAssistantEvent* = object
    case kind*: VoiceAssistantEventKind
    of evWakeWordDetected:
      wakeworddetectedName*: string
    of evSpeechEnded:
      nil
    of evIntentResolved:
      intentresolvedIntent*: string
    of evTtsFinished:
      nil
    of evReset:
      nil
    of evFailed:
      failedReason*: string
```

Parameter field names are namespaced with `<event><Param>` to prevent collisions across different events that share parameter names.

### 3. Constructor Helpers

Ergonomic constructor procs are generated for each event:

```nim
proc wakeWordDetected*(name: string): VoiceAssistantEvent =
  VoiceAssistantEvent(kind: evWakeWordDetected, wakeworddetectedName: name)

proc speechEnded*(): VoiceAssistantEvent =
  VoiceAssistantEvent(kind: evSpeechEnded)

proc failed*(reason: string): VoiceAssistantEvent =
  VoiceAssistantEvent(kind: evFailed, failedReason: reason)
```

### 4. FSM Object Variant (`<Name>FSM`)

An FSM container wrapping the current active state:

```nim
type
  VoiceAssistantFSMState* = enum
    fsIdle
    fsListening
    fsThinking
    fsSpeaking
    fsErrorState

  VoiceAssistantFSM* = object
    case state*: VoiceAssistantFSMState
    of fsIdle:
      idleVal*: Idle
    of fsListening:
      listeningVal*: Listening
    of fsThinking:
      thinkingVal*: Thinking
    of fsSpeaking:
      speakingVal*: Speaking
    of fsErrorState:
      errorstateVal*: ErrorState

proc toVoiceAssistantFSM*(val: Idle): VoiceAssistantFSM = ...
```

### 5. Synchronous 2D Dispatcher (`dispatch*`)

A synchronous, compile-time exhaustive dispatcher that performs 2D case analysis:

```nim
proc dispatch*(fsm: var VoiceAssistantFSM, event: VoiceAssistantEvent): bool
```

- **Parameters**: `fsm` is passed as a `var` reference and mutated in-place upon a successful transition.
- **2D Exhaustiveness**: The dispatcher generates an outer `case fsm.state` and inner `case event.kind`.
- **Return Value**:
  - Returns `true` if the event caused a valid state transition.
  - Returns `false` if the event is unhandled in the current state. The FSM remains in its current state without modification.
- **Zero Overhead**: Compiles directly to C jump tables / switch statements with no heap allocation, dynamic closures, or runtime reflection.

---

## Complete Example

```nim
import typestates

type
  Device = object
    id: string

  Idle = distinct Device
  Listening = distinct Device
  Thinking = distinct Device
  Speaking = distinct Device
  ErrorState = distinct Device

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
  # Initialize the FSM in the Idle state
  var fsm = Idle(Device(id: "sat-01")).toVoiceAssistantFSM()
  echo "Initial state: ", fsm.state

  # Dispatch events
  let ok1 = fsm.dispatch(wakeWordDetected("hey_assistant"))
  echo "Dispatched WakeWordDetected -> Listening: ", ok1, " (state: ", fsm.state, ")"

  let ok2 = fsm.dispatch(speechEnded())
  echo "Dispatched SpeechEnded -> Thinking: ", ok2, " (state: ", fsm.state, ")"

  let ok3 = fsm.dispatch(intentResolved("TurnOnLights"))
  echo "Dispatched IntentResolved -> Speaking: ", ok3, " (state: ", fsm.state, ")"

  # Attempting an invalid event in Speaking state
  let okInvalid = fsm.dispatch(speechEnded())
  echo "Dispatched invalid event in Speaking state: ", okInvalid, " (state: ", fsm.state, ")"

  # Universal reset
  let okReset = fsm.dispatch(reset())
  echo "Dispatched Reset -> Idle: ", okReset, " (state: ", fsm.state, ")"

main()
```
