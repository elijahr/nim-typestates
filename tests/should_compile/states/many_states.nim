## Test: Typestate with many states (20+) compiles
import ../../../src/typestates

type
  BigMachine = object
  S01 = distinct BigMachine
  S02 = distinct BigMachine
  S03 = distinct BigMachine
  S04 = distinct BigMachine
  S05 = distinct BigMachine
  S06 = distinct BigMachine
  S07 = distinct BigMachine
  S08 = distinct BigMachine
  S09 = distinct BigMachine
  S10 = distinct BigMachine
  S11 = distinct BigMachine
  S12 = distinct BigMachine
  S13 = distinct BigMachine
  S14 = distinct BigMachine
  S15 = distinct BigMachine
  S16 = distinct BigMachine
  S17 = distinct BigMachine
  S18 = distinct BigMachine
  S19 = distinct BigMachine
  S20 = distinct BigMachine

typestate BigMachine:
  consumeOnTransition = false # Opt out for existing tests
  strictTransitions = false
  states S01,
    S02, S03, S04, S05, S06, S07, S08, S09, S10, S11, S12, S13, S14, S15, S16, S17, S18,
    S19, S20
  transitions:
    S01 -> S02
    S02 -> S03
    S03 -> S04
    S04 -> S05
    S05 -> S06
    S06 -> S07
    S07 -> S08
    S08 -> S09
    S09 -> S10
    S10 -> S11
    S11 -> S12
    S12 -> S13
    S13 -> S14
    S14 -> S15
    S15 -> S16
    S16 -> S17
    S17 -> S18
    S18 -> S19
    S19 -> S20

echo "many_states test passed"
