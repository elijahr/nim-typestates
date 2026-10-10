import mod_door
import mod_circuit

var doorClosed = mod_door.Closed(Door())
let doorOpened = openDoor(move doorClosed)

var circuitOpen = mod_circuit.Open(Circuit())
let circuitClosed = closeCircuit(move circuitOpen)

echo "consumer passed: multi-module sealed typestates with shared state names work"
