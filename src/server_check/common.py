"""Shared helpers for Linux diagnostic collectors."""

import json
import subprocess
from pathlib import Path


class Unavailable(RuntimeError):
    """A required system utility or data source is absent."""


class PermissionDenied(RuntimeError):
    """A data source cannot be read with the current privileges."""


def read_text(path: str) -> str:
    try:
        return Path(path).read_text(encoding="utf-8", errors="replace")
    except FileNotFoundError as exc:
        raise Unavailable(f"{path} is unavailable") from exc
    except PermissionError as exc:
        raise PermissionDenied(f"cannot read {path}") from exc


def run(*args: str) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            args, capture_output=True, text=True, encoding="utf-8",
            errors="replace", timeout=15, check=False,
        )
    except FileNotFoundError as exc:
        raise Unavailable(f"{args[0]} is not installed") from exc


def command_json(*args: str) -> object:
    completed = run(*args)
    if completed.returncode:
        detail = (completed.stderr or completed.stdout).strip()
        if "permission denied" in detail.lower():
            raise PermissionDenied(detail)
        raise RuntimeError(detail or f"{args[0]} exited with code {completed.returncode}")
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"{args[0]} returned invalid JSON") from exc
