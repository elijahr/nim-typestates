"""MkDocs hook to regenerate typestate diagrams on pre-build.

This hook runs before each mkdocs build (including during `mkdocs serve`)
and regenerates SVG diagrams from the snippet files.

To disable during development (avoid regenerating on every save):
    SKIP_DIAGRAM_GEN=1 mkdocs serve
"""

import logging
import os
import subprocess
from pathlib import Path

log = logging.getLogger("mkdocs.hooks.generate_diagrams")


def on_pre_build(config, **kwargs) -> None:
    """Generate diagrams before each build."""

    # Allow skipping during rapid development
    if os.environ.get("SKIP_DIAGRAM_GEN"):
        log.info("Skipping diagram generation (SKIP_DIAGRAM_GEN set)")
        return

    snippets_dir = Path("examples/snippets")
    cli_path = Path("bin/typestates")

    # Check if we have snippets to process
    if not snippets_dir.exists():
        log.debug("No snippets directory found, skipping diagram generation")
        return

    snippet_files = list(snippets_dir.glob("*_typestate.nim"))
    if not snippet_files:
        log.debug("No snippet files found, skipping diagram generation")
        return

    # Check if CLI exists
    if not cli_path.exists():
        log.warning(
            "typestates CLI not found at bin/typestates. "
            "Run 'nimble build' to enable diagram generation."
        )
        return

    # Check if graphviz is available
    try:
        subprocess.run(
            ["dot", "-V"],
            capture_output=True,
            check=True
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        log.warning(
            "Graphviz 'dot' command not found. "
            "Install graphviz to enable diagram generation."
        )
        return

    log.info(f"Generating diagrams from {len(snippet_files)} snippets...")

    # Run the generation script
    result = subprocess.run(
        ["python3", "scripts/generate_diagrams.py"],
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        log.error(f"Diagram generation failed: {result.stderr}")
    else:
        log.info("Diagrams generated successfully")
