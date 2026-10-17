"""Render the task prompt sent to the model from task/prompt.md.

HTML comments (canary, maintainer notes) are stripped, so the model sees only the task.
The prompt is identical for every dataset variant; ablations change the data, never the text.
"""

from __future__ import annotations

import re
from pathlib import Path

PROMPT_PATH = Path(__file__).resolve().parents[1] / "task" / "prompt.md"
_COMMENT = re.compile(r"<!--.*?-->\s*", re.DOTALL)


def render_prompt(path: Path = PROMPT_PATH) -> str:
    return _COMMENT.sub("", path.read_text()).strip() + "\n"


if __name__ == "__main__":
    print(render_prompt(), end="")
