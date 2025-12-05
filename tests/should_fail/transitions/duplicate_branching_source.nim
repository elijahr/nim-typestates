## Expected error: "Duplicate branching transition from 'Created'"
## Each source state can only have one branching transition.

import ../../../src/typestates

type
  Payment = object
  Created = distinct Payment
  Approved = distinct Payment
  Declined = distinct Payment
  Banana = distinct Payment
  Potato = distinct Payment

typestate Payment:
  states Created, Approved, Declined, Banana, Potato
  transitions:
    Created -> Approved | Declined  # First branching from Created
    Created -> Banana | Potato      # ERROR: Second branching from Created
