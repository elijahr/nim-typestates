"""MkDocs hook to regenerate typestate diagrams on pre-build.

This hook runs before each mkdocs build (including during `mkdocs serve`)
and regenerates SVG diagrams from the snippet files only if sources changed.

To force regeneration:
    FORCE_DIAGRAM_GEN=1 mkdocs serve

To disable completely:
    SKIP_DIAGRAM_GEN=1 mkdocs serve
"""

import logging
import os
import subprocess
from pathlib import Path

log = logging.getLogger("mkdocs.hooks.generate_diagrams")


def _needs_regeneration(snippet_files: list[Path], output_dir: Path, cli_path: Path) -> bool:
    """Check if any snippet is newer than its corresponding SVG output."""
    for snippet in snippet_files:
        # Output filename is based on typestate name or file stem
        stem = snippet.stem.replace("_typestate", "").lower()
        svg_path = output_dir / f"{stem}.svg"

        # If output doesn't exist, needs regeneration
        if not svg_path.exists():
            return True

        # If snippet is newer than output, needs regeneration
        if snippet.stat().st_mtime > svg_path.stat().st_mtime:
            return True

    # Also check if CLI is newer than any output (CLI changes affect output)
    if cli_path.exists():
        cli_mtime = cli_path.stat().st_mtime
        for svg in output_dir.glob("*.svg"):
            if cli_mtime > svg.stat().st_mtime:
                return True

    return False


def on_pre_build(config, **kwargs) -> None:
    """Generate diagrams before each build if sources changed."""

    # Allow skipping completely
    if os.environ.get("SKIP_DIAGRAM_GEN"):
        log.debug("Skipping diagram generation (SKIP_DIAGRAM_GEN set)")
        return

    snippets_dir = Path("examples/snippets")
    output_dir = Path("docs/assets/images/generated")
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

    # Check if regeneration is needed (unless forced)
    force = os.environ.get("FORCE_DIAGRAM_GEN")
    if not force and not _needs_regeneration(snippet_files, output_dir, cli_path):
        log.debug("Diagrams are up-to-date, skipping generation")
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
