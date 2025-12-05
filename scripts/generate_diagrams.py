#!/usr/bin/env python3
"""Generate SVG diagrams from typestate code snippets.

This script uses the typestates CLI to generate DOT output from snippet files,
then converts them to SVG using Graphviz.

Usage:
    python scripts/generate_diagrams.py

Requires:
    - bin/typestates CLI built
    - graphviz installed (dot command)
"""

import subprocess
import sys
from pathlib import Path

SNIPPETS_DIR = Path("examples/snippets")
OUTPUT_DIR = Path("docs/assets/images/generated")


def extract_typestate_name(nim_file: Path) -> str:
    """Extract typestate name from a .nim file.

    Looks for 'typestate Name:' pattern and extracts the name.
    Handles generics like 'Container[T]' by extracting base name.
    """
    content = nim_file.read_text()
    for line in content.split("\n"):
        line = line.strip()
        if line.startswith("typestate "):
            # Extract: "typestate Payment:" -> "Payment"
            name = line.replace("typestate ", "").rstrip(":")
            # Handle generics: "Container[T]" -> "Container"
            if "[" in name:
                name = name.split("[")[0]
            return name.strip()
    # Fallback to filename without extension
    return nim_file.stem.replace("_typestate", "")


def generate_diagram(nim_file: Path, output_dir: Path) -> bool:
    """Generate SVG from a typestate snippet.

    Returns True on success, False on failure.
    """
    name = extract_typestate_name(nim_file)
    dot_file = output_dir / f"{name.lower()}.dot"
    svg_file = output_dir / f"{name.lower()}.svg"

    print(f"Processing {nim_file.name} -> {name}...")

    # Run typestates CLI to generate DOT
    result = subprocess.run(
        ["./bin/typestates", "dot", str(nim_file)],
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        print(f"  ERROR: typestates CLI failed: {result.stderr}")
        return False

    # Write DOT file
    dot_file.write_text(result.stdout)
    print(f"  Created: {dot_file}")

    # Convert to SVG using Graphviz
    try:
        subprocess.run(
            ["dot", "-Tsvg", str(dot_file), "-o", str(svg_file)],
            check=True,
            capture_output=True,
            text=True
        )
        print(f"  Created: {svg_file}")
    except subprocess.CalledProcessError as e:
        print(f"  ERROR: Graphviz failed: {e.stderr}")
        return False
    except FileNotFoundError:
        print("  ERROR: 'dot' command not found. Install graphviz.")
        return False

    return True


def main() -> int:
    """Main entry point. Returns 0 on success, 1 on failure."""

    # Check for snippets directory
    if not SNIPPETS_DIR.exists():
        print(f"ERROR: Snippets directory not found: {SNIPPETS_DIR}")
        return 1

    # Create output directory
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Check for CLI
    cli_path = Path("./bin/typestates")
    if not cli_path.exists():
        print("ERROR: typestates CLI not found. Run 'nimble build' first.")
        return 1

    # Process all snippet files
    snippet_files = list(SNIPPETS_DIR.glob("*_typestate.nim"))
    if not snippet_files:
        print(f"WARNING: No *_typestate.nim files found in {SNIPPETS_DIR}")
        return 0

    success_count = 0
    for nim_file in sorted(snippet_files):
        if generate_diagram(nim_file, OUTPUT_DIR):
            success_count += 1

    print(f"\nGenerated {success_count}/{len(snippet_files)} diagrams")

    if success_count < len(snippet_files):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
