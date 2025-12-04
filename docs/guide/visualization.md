# Visualization

The `typestates dot` command generates GraphViz DOT output for visualizing state machines as diagrams.

## Basic Usage

```bash
# Generate DOT output
typestates dot src/

# Save to file
typestates dot src/ > states.dot

# Generate PNG directly
typestates dot src/ | dot -Tpng -o states.png

# Generate SVG for web
typestates dot src/ | dot -Tsvg -o states.svg
```

## Example: File State Machine

Given this typestate definition:

```nim
import typestates

type
  File = object
    path: string
  Closed = distinct File
  Open = distinct File

typestate File:
  states Closed, Open
  transitions:
    Closed -> Open
    Open -> Closed
```

Running `typestates dot src/` produces:

```dot
digraph File {
  rankdir=LR;
  node [shape=box];

  Closed;
  Open;

  Closed -> Open;
  Open -> Closed;
}
```

Rendered as a diagram:

![File State Machine](../assets/images/file-states.svg)

## Example: Payment Processing

A more complex example with branching transitions:

```nim
typestate Payment:
  states Created, Authorized, Captured, PartiallyRefunded, FullyRefunded, Settled, Voided
  transitions:
    Created -> Authorized
    Authorized -> Captured | Voided
    Captured -> PartiallyRefunded | FullyRefunded | Settled
    PartiallyRefunded -> PartiallyRefunded | FullyRefunded | Settled
    FullyRefunded -> Settled
```

DOT output:

```dot
digraph Payment {
  rankdir=LR;
  node [shape=box];

  Created;
  Authorized;
  Captured;
  PartiallyRefunded;
  FullyRefunded;
  Settled;
  Voided;

  Created -> Authorized;
  Authorized -> Captured;
  Authorized -> Voided;
  Captured -> PartiallyRefunded;
  Captured -> FullyRefunded;
  Captured -> Settled;
  PartiallyRefunded -> PartiallyRefunded;
  PartiallyRefunded -> FullyRefunded;
  PartiallyRefunded -> Settled;
  FullyRefunded -> Settled;
}
```

![Payment State Machine](../assets/images/payment-states.svg)

## Example: Wildcard Transitions

Wildcard transitions (`* -> State`) are rendered with dashed edges:

```nim
typestate DbConnection:
  states Pooled, CheckedOut, InTransaction, Closed
  transitions:
    Pooled -> CheckedOut | Closed
    CheckedOut -> Pooled | InTransaction | Closed
    InTransaction -> CheckedOut
    * -> Closed
```

DOT output:

```dot
digraph DbConnection {
  rankdir=LR;
  node [shape=box];

  Pooled;
  CheckedOut;
  InTransaction;
  Closed;

  Pooled -> CheckedOut;
  Pooled -> Closed;
  CheckedOut -> Pooled;
  CheckedOut -> InTransaction;
  CheckedOut -> Closed;
  InTransaction -> CheckedOut;
  Pooled -> Closed [style=dashed];
  CheckedOut -> Closed [style=dashed];
  InTransaction -> Closed [style=dashed];
  Closed -> Closed [style=dashed];
}
```

![Database Connection States](../assets/images/db-connection-states.svg)

The dashed edges indicate transitions that apply from any state (wildcard).

## Installing GraphViz

The DOT output can be rendered with GraphViz. Install it for your platform:

=== "macOS"
    ```bash
    brew install graphviz
    ```

=== "Ubuntu/Debian"
    ```bash
    sudo apt install graphviz
    ```

=== "Windows"
    ```bash
    choco install graphviz
    ```

## Output Formats

GraphViz supports many output formats:

| Format | Command | Use Case |
|--------|---------|----------|
| PNG | `dot -Tpng` | Documentation, README |
| SVG | `dot -Tsvg` | Web, scalable graphics |
| PDF | `dot -Tpdf` | Print, documentation |
| DOT | (raw output) | Further processing |

## Customizing Output

You can post-process the DOT output for custom styling:

```bash
# Add custom colors
typestates dot src/ | sed 's/shape=box/shape=box, fillcolor=lightblue, style=filled/' | dot -Tpng -o colored.png

# Change layout direction (top-to-bottom)
typestates dot src/ | sed 's/rankdir=LR/rankdir=TB/' | dot -Tpng -o vertical.png
```

## Generating Documentation Images

To include diagrams in your documentation:

```bash
# Create images directory
mkdir -p docs/assets/images

# Generate all typestate diagrams
typestates dot src/ | csplit -f docs/assets/images/state- -b '%02d.dot' - '/^digraph/' '{*}'

# Convert each to SVG
for f in docs/assets/images/state-*.dot; do
  dot -Tsvg "$f" -o "${f%.dot}.svg"
done
```

## Multiple Typestates

If your project has multiple typestates, the `dot` command outputs them all sequentially:

```bash
$ typestates dot src/
digraph File {
  ...
}

digraph Payment {
  ...
}

digraph Session {
  ...
}
```

You can split them into separate files with tools like `csplit` or process them programmatically.
