## Robot Arm Controller with Typestates
##
## Hardware control is where typestates REALLY shine. Wrong operation order
## can damage expensive equipment or cause safety hazards:
## - Moving arm before homing: crash into limits
## - Operating without calibration: inaccurate positioning
## - Emergency stop not handled: damage or injury
## - Power off while moving: motor damage
##
## This example models a robotic arm controller with safety states.

import ../src/typestates

type
  RobotArm = object
    x, y, z: float          # Current position
    homeX, homeY, homeZ: float  # Home position
    speed: float            # Movement speed
    toolAttached: bool
    emergencyReason: string

  # Robot arm states
  PoweredOff = distinct RobotArm     ## No power to motors
  Initializing = distinct RobotArm   ## Powering up, running diagnostics
  NeedsHoming = distinct RobotArm    ## Powered but position unknown
  Homing = distinct RobotArm         ## Currently finding home position
  Ready = distinct RobotArm          ## Homed and ready for commands
  Moving = distinct RobotArm         ## Currently executing movement
  EmergencyStop = distinct RobotArm  ## E-stop triggered, frozen

typestate RobotArm:
  states PoweredOff, Initializing, NeedsHoming, Homing, Ready, Moving, EmergencyStop
  transitions:
    PoweredOff -> Initializing
    Initializing -> NeedsHoming
    NeedsHoming -> Homing
    Homing -> Ready
    Ready -> Moving | PoweredOff
    Moving -> Ready | EmergencyStop
    EmergencyStop -> NeedsHoming | PoweredOff  # Must re-home after E-stop

# ============================================================================
# Power and Initialization
# ============================================================================

proc powerOn(arm: PoweredOff): Initializing {.transition.} =
  ## Power on the robot arm and start initialization.
  echo "  [ARM] Powering on..."
  echo "  [ARM] Running motor diagnostics..."
  result = Initializing(arm.RobotArm)

proc completeInit(arm: Initializing): NeedsHoming {.transition.} =
  ## Complete initialization, now needs homing.
  echo "  [ARM] Diagnostics passed"
  echo "  [ARM] WARNING: Position unknown - homing required!"
  result = NeedsHoming(arm.RobotArm)

proc powerOff(arm: Ready): PoweredOff {.transition.} =
  ## Safely power off the arm when ready.
  echo "  [ARM] Powering off safely..."
  result = PoweredOff(arm.RobotArm)

proc powerOffEmergency(arm: EmergencyStop): PoweredOff {.transition.} =
  ## Power off after emergency stop.
  echo "  [ARM] Emergency power off"
  result = PoweredOff(arm.RobotArm)

# ============================================================================
# Homing Operations
# ============================================================================

proc startHoming(arm: NeedsHoming): Homing {.transition.} =
  ## Begin the homing sequence to find reference position.
  echo "  [ARM] Starting homing sequence..."
  echo "  [ARM] Moving to limit switches at low speed..."
  result = Homing(arm.RobotArm)

proc homingComplete(arm: Homing, homeX, homeY, homeZ: float): Ready {.transition.} =
  ## Complete homing and set reference position.
  var a = arm.RobotArm
  a.x = homeX
  a.y = homeY
  a.z = homeZ
  a.homeX = homeX
  a.homeY = homeY
  a.homeZ = homeZ
  echo "  [ARM] Homing complete. Position: (", homeX, ", ", homeY, ", ", homeZ, ")"
  echo "  [ARM] Ready for commands!"
  result = Ready(a)

proc resetAfterEmergency(arm: EmergencyStop): NeedsHoming {.transition.} =
  ## Reset emergency stop - position is now uncertain.
  echo "  [ARM] E-stop reset. Position uncertain - must re-home!"
  var a = arm.RobotArm
  a.emergencyReason = ""
  result = NeedsHoming(a)

# ============================================================================
# Movement Operations
# ============================================================================

proc moveTo(arm: Ready, x, y, z: float): Moving {.transition.} =
  ## Start moving to target position.
  echo "  [ARM] Moving to (", x, ", ", y, ", ", z, ")..."
  result = Moving(arm.RobotArm)

proc moveComplete(arm: Moving, x, y, z: float): Ready {.transition.} =
  ## Movement completed successfully.
  var a = arm.RobotArm
  a.x = x
  a.y = y
  a.z = z
  echo "  [ARM] Reached position (", x, ", ", y, ", ", z, ")"
  result = Ready(a)

proc emergencyStop(arm: Moving, reason: string): EmergencyStop {.transition.} =
  ## Trigger emergency stop during movement!
  var a = arm.RobotArm
  a.emergencyReason = reason
  echo "  [ARM] !!! EMERGENCY STOP !!!"
  echo "  [ARM] Reason: ", reason
  echo "  [ARM] Motors locked. Manual intervention required."
  result = EmergencyStop(a)

# ============================================================================
# Status and Configuration (no state change)
# ============================================================================

func position(arm: Ready): tuple[x, y, z: float] =
  ## Get current position (only valid when Ready).
  (arm.RobotArm.x, arm.RobotArm.y, arm.RobotArm.z)

proc setSpeed(arm: Ready, speed: float): Ready {.notATransition.} =
  ## Configure movement speed.
  var a = arm.RobotArm
  a.speed = speed
  echo "  [ARM] Speed set to ", speed, " mm/s"
  result = Ready(a)

proc attachTool(arm: Ready, toolName: string): Ready {.notATransition.} =
  ## Attach a tool to the arm.
  var a = arm.RobotArm
  a.toolAttached = true
  echo "  [ARM] Tool attached: ", toolName
  result = Ready(a)

# ============================================================================
# Example Usage
# ============================================================================

when isMainModule:
  echo "=== Robot Arm Controller Demo ===\n"

  echo "1. Starting with powered-off arm..."
  var arm = PoweredOff(RobotArm())

  echo "\n2. Powering on..."
  let initializing = arm.powerOn()

  echo "\n3. Completing initialization..."
  let needsHoming = initializing.completeInit()

  echo "\n4. Starting homing sequence..."
  let homing = needsHoming.startHoming()

  echo "\n5. Homing complete..."
  let ready = homing.homingComplete(0.0, 0.0, 100.0)

  echo "\n6. Configuring arm..."
  let configured = ready
    .setSpeed(50.0)
    .attachTool("gripper")

  echo "\n7. Moving to pick position..."
  let moving1 = configured.moveTo(100.0, 50.0, 20.0)
  let atPick = moving1.moveComplete(100.0, 50.0, 20.0)

  echo "\n8. Moving to place position..."
  let moving2 = atPick.moveTo(200.0, 50.0, 20.0)
  let atPlace = moving2.moveComplete(200.0, 50.0, 20.0)

  echo "\n9. Returning home and powering off..."
  let moving3 = atPlace.moveTo(0.0, 0.0, 100.0)
  let atHome = moving3.moveComplete(0.0, 0.0, 100.0)
  let off = atHome.powerOff()

  echo "\n=== Demo complete! ===\n"

  # =========================================================================
  # COMPILE-TIME ERRORS - These dangerous bugs are prevented:
  # =========================================================================

  echo "The following DANGEROUS bugs are caught at COMPILE TIME:\n"

  # BUG 1: Moving without homing (position unknown!)
  # let bad1 = needsHoming.moveTo(100.0, 0.0, 0.0)
  echo "  [PREVENTED] moveTo() without homing - could crash into limits!"

  # BUG 2: Power off while moving (motor damage!)
  # let bad2 = moving1.powerOff()
  echo "  [PREVENTED] powerOff() while moving - motor damage risk!"

  # BUG 3: Continue after emergency stop
  # let estop = moving2.emergencyStop("Obstacle detected")
  # let bad3 = estop.moveTo(0.0, 0.0, 0.0)
  echo "  [PREVENTED] moveTo() after E-stop - dangerous!"

  # BUG 4: Skip initialization
  # let bad4 = initializing.startHoming()
  echo "  [PREVENTED] startHoming() before initialization complete"

  # BUG 5: Configure speed while moving
  # let bad5 = moving1.setSpeed(100.0)
  echo "  [PREVENTED] setSpeed() while moving - could cause issues"

  echo "\nUncomment any of the 'bad' lines to see the compile error!"
