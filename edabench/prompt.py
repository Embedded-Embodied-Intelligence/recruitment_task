"""Render the task prompt sent to the model from task/prompt.md.

HTML comments (canary, maintainer notes) are stripped, so the model sees only the task.
The prompt is identical for every dataset variant; ablations change the data, never the text.

Prompt variants are the one exception, and they are explicit:
- "full": the task as published;
- "no_quality_hint": without the line that asks to check data quality. It measures how
  much a model cleans the data unprompted (docs/prompt_design.md).
"""

from __future__ import annotations

import re
from pathlib import Path

PROMPT_PATH = Path(__file__).resolve().parents[1] / "task" / "prompt.md"
_COMMENT = re.compile(r"<!--.*?-->\s*", re.DOTALL)
QUALITY_HINT = "- The files are raw exports from production systems. Check data quality before you rely on any number.\n"
VARIANTS = ("full", "no_quality_hint")


def render_prompt(path: Path = PROMPT_PATH, variant: str = "full") -> str:
    if variant not in VARIANTS:
        raise ValueError(f"unknown prompt variant {variant!r}; known: {VARIANTS}")
    text = _COMMENT.sub("", path.read_text()).strip() + "\n"
    if variant == "no_quality_hint":
        if QUALITY_HINT not in text:
            raise ValueError("the quality hint line is not in the prompt; update QUALITY_HINT")
        text = text.replace(QUALITY_HINT, "")
    return text


if __name__ == "__main__":
    print(render_prompt(), end="")
