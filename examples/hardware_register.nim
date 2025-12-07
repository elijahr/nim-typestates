## Hardware Register Access with ptr Types
##
## When interfacing with hardware or memory-mapped I/O, you often work with
## raw pointers. Typestates can enforce correct access patterns:
## - Registers must be initialized before use
## - Some registers are read-only after configuration
## - Certain sequences must be followed
##
## This example shows how typestates work with ptr types for low-level code.
##
## Run: nim c -r examples/hardware_register.nim

import std/strutils
import ../src/typestates

type
  Register = object
    address: uint32
    value: uint32

  # Register states
  Uninitialized = distinct Register
  Configured = distinct Register
  Locked = distinct Register

typestate Register:
  # Hardware registers are accessed via pointers
  consumeOnTransition = false
  states Uninitialized, Configured, Locked
  transitions:
    Uninitialized -> Configured
    Configured -> Configured   # Can reconfigure
    Configured -> Locked       # Lock to prevent further changes

# ============================================================================
# Register Operations (ptr types)
# ============================================================================

proc initRegister(reg: ptr Uninitialized, value: uint32): ptr Configured {.transition.} =
  ## Initialize a hardware register with a value.
  echo "  [REG 0x", reg[].Register.address.toHex, "] Init: 0x", value.toHex
  var r = Register(reg[])
  r.value = value
  reg[] = Uninitialized(r)
  cast[ptr Configured](reg)

proc configure(reg: ptr Configured, value: uint32): ptr Configured {.transition.} =
  ## Reconfigure a register (only when not locked).
  echo "  [REG 0x", reg[].Register.address.toHex, "] Configure: 0x", value.toHex
  var r = Register(reg[])
  r.value = value
  reg[] = Configured(r)
  reg

proc lock(reg: ptr Configured): ptr Locked {.transition.} =
  ## Lock the register to prevent further modifications.
  echo "  [REG 0x", reg[].Register.address.toHex, "] LOCKED"
  cast[ptr Locked](reg)

proc read(reg: ptr Configured): uint32 =
  ## Read value from configured register.
  Register(reg[]).value

proc read(reg: ptr Locked): uint32 =
  ## Read value from locked register.
  Register(reg[]).value

# ============================================================================
# Example: GPIO Configuration
# ============================================================================

when isMainModule:
  echo "=== Hardware Register Demo (ptr types) ===\n"

  # Simulate memory-mapped registers
  var gpioModeReg = Uninitialized(Register(address: 0x4002_0000'u32, value: 0))
  var gpioSpeedReg = Uninitialized(Register(address: 0x4002_0008'u32, value: 0))

  echo "1. Initializing GPIO registers..."
  let modePtr = addr(gpioModeReg).initRegister(0x0000_0001)  # Output mode
  let speedPtr = addr(gpioSpeedReg).initRegister(0x0000_0003)  # High speed

  echo "\n2. Reading configured values..."
  echo "   Mode register: 0x", modePtr.read().toHex
  echo "   Speed register: 0x", speedPtr.read().toHex

  echo "\n3. Reconfiguring mode register..."
  let modePtr2 = modePtr.configure(0x0000_0002)  # Alternate function mode
  echo "   New mode: 0x", modePtr2.read().toHex

  echo "\n4. Locking speed register..."
  let lockedSpeed = speedPtr.lock()
  echo "   Locked value: 0x", lockedSpeed.read().toHex

  echo "\n=== Register configuration complete! ===\n"

  # =========================================================================
  # COMPILE-TIME ERRORS
  # =========================================================================

  echo "The following bugs are caught at COMPILE TIME:\n"

  # BUG 1: Reading uninitialized register
  # var uninit = Uninitialized(Register(address: 0xDEAD, value: 0))
  # echo addr(uninit).read()  # ERROR: no matching proc for ptr Uninitialized
  echo "  [PREVENTED] read() on uninitialized register"

  # BUG 2: Configuring locked register
  # discard lockedSpeed.configure(0xFF)  # ERROR: no matching proc for ptr Locked
  echo "  [PREVENTED] configure() on locked register"

  # BUG 3: Locking uninitialized register
  # var uninit2 = Uninitialized(Register(address: 0xBEEF, value: 0))
  # discard addr(uninit2).lock()  # ERROR: no matching proc for ptr Uninitialized
  echo "  [PREVENTED] lock() on uninitialized register"

  echo "\nPtr types enable type-safe hardware access!"
