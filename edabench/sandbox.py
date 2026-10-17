"""A stateful Python sandbox for models that cannot execute code themselves.

Free OpenAI-compatible APIs only return text, so the harness gives them one tool,
`run_python`, and executes the code here. The sandbox is a Jupyter kernel started in a
fresh working directory that holds only the task files, so variables persist between
calls like in a notebook (which is how the Claude apps run code too).

Isolation is best-effort, not a security boundary: the code runs as the current user.
- the working directory contains only the published task files (never the answer key);
- network access is switched off inside the kernel (socket connections fail) and for
  child processes (proxy variables point to a closed port, pip has no index), so the
  model cannot install packages or fetch anything, matching a sandbox without egress;
- every call has a wall-clock timeout, and output is truncated before it reaches the
  model, to bound the context and the free-tier token budget.
"""

from __future__ import annotations

import os
import queue
import re
import shutil
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path

from jupyter_client.manager import KernelManager

MAX_OUTPUT_CHARS = 4000
TIMEOUT_S = 120

_NO_NETWORK = """
import socket as _socket
def _blocked(*args, **kwargs):
    raise OSError("network access is disabled in this sandbox")
_socket.socket.connect = _blocked
_socket.socket.connect_ex = _blocked
_socket.create_connection = _blocked
del _socket, _blocked
"""
_NO_NETWORK_ENV = {
    "HTTP_PROXY": "http://127.0.0.1:9", "HTTPS_PROXY": "http://127.0.0.1:9",
    "http_proxy": "http://127.0.0.1:9", "https_proxy": "http://127.0.0.1:9",
    "NO_PROXY": "", "PIP_NO_INDEX": "1", "MPLBACKEND": "Agg",
}


@dataclass
class Execution:
    code: str
    output: str
    error: str | None = None
    timed_out: bool = False
    truncated: bool = False

    def for_model(self) -> str:
        text = self.output
        if self.error:
            text += ("\n" if text else "") + self.error
        if self.timed_out:
            text += "\n[execution stopped: time limit reached]"
        if self.truncated:
            text += "\n[output truncated: print less, e.g. head() or aggregates]"
        return text or "[no output]"


def truncate(text: str, limit: int = MAX_OUTPUT_CHARS) -> tuple[str, bool]:
    """Keep the head and the tail, which is where tracebacks and results usually are."""
    if len(text) <= limit:
        return text, False
    half = limit // 2
    return f"{text[:half]}\n...\n{text[-half:]}", True


@dataclass
class PythonSandbox:
    files: list[Path]
    timeout_s: float = TIMEOUT_S
    max_output_chars: int = MAX_OUTPUT_CHARS
    workdir: Path = field(init=False)
    history: list[Execution] = field(default_factory=list, init=False)

    def __enter__(self) -> "PythonSandbox":
        self.workdir = Path(tempfile.mkdtemp(prefix="edabench_"))
        for f in self.files:
            shutil.copy(f, self.workdir / Path(f).name)
        self._km = KernelManager(kernel_name="python3")
        self._km.start_kernel(cwd=str(self.workdir), env={**os.environ, **_NO_NETWORK_ENV})
        self._kc = self._km.client()
        self._kc.start_channels()
        self._kc.wait_for_ready(timeout=60)
        self._run(_NO_NETWORK, record=False)
        return self

    def __exit__(self, *exc) -> None:
        self._kc.stop_channels()
        self._km.shutdown_kernel(now=True)
        shutil.rmtree(self.workdir, ignore_errors=True)

    def run(self, code: str) -> Execution:
        return self._run(code, record=True)

    def _run(self, code: str, record: bool) -> Execution:
        msg_id = self._kc.execute(code, store_history=True)
        chunks, error, timed_out = [], None, False
        deadline = time.monotonic() + self.timeout_s
        while True:
            try:
                msg = self._kc.get_iopub_msg(timeout=max(0.1, deadline - time.monotonic()))
            except queue.Empty:
                if timed_out:  # the interrupt did not stop it either: start over
                    self._km.restart_kernel(now=True)
                    self._kc.wait_for_ready(timeout=60)
                    self._run(_NO_NETWORK, record=False)
                    error = "the kernel was restarted, all variables are lost"
                    break
                # Interrupt, then wait for the cell to finish so that its late output
                # cannot leak into the next call.
                self._km.interrupt_kernel()
                timed_out, deadline = True, time.monotonic() + 10
                continue
            if msg["parent_header"].get("msg_id") != msg_id:
                continue
            kind, content = msg["msg_type"], msg["content"]
            if kind == "stream":
                chunks.append(content["text"])
            elif kind in ("execute_result", "display_data"):
                data = content.get("data", {})
                chunks.append(data.get("text/plain", "[image]" if "image/png" in data else "") + "\n")
            elif kind == "error":
                error = "\n".join(content["traceback"][-3:]) if content.get("traceback") else content["evalue"]
                error = _strip_ansi(error)
            elif kind == "status" and content["execution_state"] == "idle":
                break
        output, truncated = truncate("".join(chunks), self.max_output_chars)
        ex = Execution(code, output, error, timed_out, truncated)
        if record:
            self.history.append(ex)
        return ex


def _strip_ansi(text: str) -> str:
    return re.sub(r"\x1b\[[0-9;]*m", "", text)
