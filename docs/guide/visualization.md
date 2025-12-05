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

## Edge Styles

The CLI uses dark mode styling with different edge styles to distinguish transition types:

| Type | Style | Description |
|------|-------|-------------|
| Normal | Solid light gray | Standard state transitions |
| Wildcard | Dotted gray | Transitions from any state (`* -> State`) |
| Bridge | Dashed light purple | Cross-typestate transitions |

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
digraph {
  rankdir=LR;
  bgcolor="transparent";
  pad=0.5;

  node [shape=box, style="rounded,filled", fillcolor="#2d2d2d", color="#b39ddb", fontcolor="#e0e0e0", fontname="Helvetica", fontsize=11, margin="0.2,0.1"];
  edge [fontname="Helvetica", fontsize=9, color="#b0b0b0"];

  subgraph cluster_File {
    label="File";
    fontname="Helvetica Bold";
    fontsize=12;
    fontcolor="#e0e0e0";
    style="rounded";
    color="#b39ddb";
    bgcolor="#1e1e1e";
    margin=16;

    Closed;
    Open;

    Closed -> Open;
    Open -> Closed;
  }
}
```

Rendered as a diagram:

![File State Machine](../assets/images/generated/file.svg)

!!! note "Output Format"
    The CLI generates a unified graph with each typestate as a labeled subgraph.
    This allows multiple typestates and bridges to be visualized together in a single diagram.

## Example: Payment Processing

A more complex example with branching transitions:

```nim
typestate Payment:
  states Created, Authorized, Captured, PartiallyRefunded, FullyRefunded, Settled, Voided
  transitions:
    Created -> Authorized
    Authorized -> Captured | Voided as AuthResult
    Captured -> PartiallyRefunded | FullyRefunded | Settled as CaptureResult
    PartiallyRefunded -> PartiallyRefunded | FullyRefunded | Settled as RefundResult
    FullyRefunded -> Settled
```

DOT output:

```dot
digraph {
  rankdir=LR;
  bgcolor="transparent";
  pad=0.5;

  node [shape=box, style="rounded,filled", fillcolor="#2d2d2d", color="#b39ddb", fontcolor="#e0e0e0", fontname="Helvetica", fontsize=11, margin="0.2,0.1"];
  edge [fontname="Helvetica", fontsize=9, color="#b0b0b0"];

  subgraph cluster_Payment {
    label="Payment";
    fontname="Helvetica Bold";
    fontsize=12;
    fontcolor="#e0e0e0";
    style="rounded";
    color="#b39ddb";
    bgcolor="#1e1e1e";
    margin=16;

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
}
```

![Payment State Machine](../assets/images/generated/payment.svg)

## Example: Wildcard Transitions

Wildcard transitions (`* -> State`) are rendered with dotted gray edges:

```nim
typestate DbConnection:
  states Pooled, CheckedOut, InTransaction, Closed
  transitions:
    Pooled -> CheckedOut | Closed as PoolResult
    CheckedOut -> Pooled | InTransaction | Closed as CheckoutResult
    InTransaction -> CheckedOut
    * -> Closed
```

DOT output:

```dot
digraph {
  rankdir=LR;
  bgcolor="transparent";
  pad=0.5;

  node [shape=box, style="rounded,filled", fillcolor="#2d2d2d", color="#b39ddb", fontcolor="#e0e0e0", fontname="Helvetica", fontsize=11, margin="0.2,0.1"];
  edge [fontname="Helvetica", fontsize=9, color="#b0b0b0"];

  subgraph cluster_DbConnection {
    label="DbConnection";
    fontname="Helvetica Bold";
    fontsize=12;
    fontcolor="#e0e0e0";
    style="rounded";
    color="#b39ddb";
    bgcolor="#1e1e1e";
    margin=16;

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
    Pooled -> Closed [style=dotted, color="#757575"];
    CheckedOut -> Closed [style=dotted, color="#757575"];
    InTransaction -> Closed [style=dotted, color="#757575"];
    Closed -> Closed [style=dotted, color="#757575"];
  }
}
```

![Database Connection States](../assets/images/generated/dbconnection.svg)

The dotted gray edges indicate transitions that apply from any state (wildcard).

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

The CLI produces dark mode styled output by default with light purple accents. You can post-process for further customization:

```bash
# Change layout direction (top-to-bottom)
typestates dot src/ | sed 's/rankdir=LR/rankdir=TB/' | dot -Tpng -o vertical.png

# Light mode (swap colors)
typestates dot src/ | sed 's/#2d2d2d/#f5f5f5/g; s/#1e1e1e/#fafafa/g; s/#e0e0e0/#212121/g; s/#b0b0b0/#424242/g' | dot -Tpng -o light.png
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

If your project has multiple typestates, the `dot` command outputs them all in a single unified graph with separate subgraphs. Bridges between typestates are shown as dashed purple edges.

### Example: Authentication Flow with Session

This example shows two typestates with bridges connecting them:

```nim
# Session typestate
type
  Session = object
    userId: string
  Active = distinct Session
  Expired = distinct Session

typestate Session:
  states Active, Expired
  transitions:
    Active -> Expired

# AuthFlow typestate with bridges to Session
type
  AuthFlow = object
    userId: string
  Pending = distinct AuthFlow
  Authenticated = distinct AuthFlow
  Failed = distinct AuthFlow

typestate AuthFlow:
  states Pending, Authenticated, Failed
  transitions:
    Pending -> Authenticated
    Pending -> Failed
  bridges:
    Authenticated -> Session.Active
    Failed -> Session.Expired
```

Running `typestates dot` produces:

```dot
digraph {
  rankdir=LR;
  bgcolor="transparent";
  pad=0.5;

  node [shape=box, style="rounded,filled", fillcolor="#2d2d2d", color="#b39ddb", fontcolor="#e0e0e0", fontname="Helvetica", fontsize=11, margin="0.2,0.1"];
  edge [fontname="Helvetica", fontsize=9, color="#b0b0b0"];

  subgraph cluster_Session {
    label="Session";
    fontname="Helvetica Bold";
    fontsize=12;
    fontcolor="#e0e0e0";
    style="rounded";
    color="#b39ddb";
    bgcolor="#1e1e1e";
    margin=16;

    Active;
    Expired;

    Active -> Expired;
  }

  subgraph cluster_AuthFlow {
    label="AuthFlow";
    fontname="Helvetica Bold";
    fontsize=12;
    fontcolor="#e0e0e0";
    style="rounded";
    color="#b39ddb";
    bgcolor="#1e1e1e";
    margin=16;

    Pending;
    Authenticated;
    Failed;

    Pending -> Authenticated;
    Pending -> Failed;
  }

  // Bridges (cross-typestate)
  Authenticated -> Active [style=dashed, color="#b39ddb", penwidth=1.5];
  Failed -> Expired [style=dashed, color="#b39ddb", penwidth=1.5];
}
```

Rendered as a diagram:

![Multiple Typestates with Bridges](../assets/images/generated/multi.svg)

This unified format allows you to visualize relationships between different typestates when using bridges.

## Auto-Generated Diagrams

The diagrams in this documentation can be automatically regenerated from source code snippets. This ensures they stay in sync with the actual typestate definitions.

### Generating Diagrams

```bash
# Generate all diagrams from examples/snippets/
nimble generateDocs

# Or manually:
python3 scripts/generate_diagrams.py
```

This reads `*_typestate.nim` files from `examples/snippets/` and generates SVG diagrams in `docs/assets/images/generated/`.

### Creating New Diagram Sources

To add a new auto-generated diagram:

1. Create a snippet in `examples/snippets/yourname_typestate.nim`:

```nim
import ../../src/typestates

type
  YourType = object
  StateA = distinct YourType
  StateB = distinct YourType

typestate YourType:
  states StateA, StateB
  transitions:
    StateA -> StateB
```

2. Run `nimble generateDocs` to regenerate all diagrams.

3. Reference the generated image: `![YourType](../assets/images/generated/yourtype.svg)`
