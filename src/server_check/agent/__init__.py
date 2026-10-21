"""Interfaces for future in-band Python diagnostic checks."""

from .runner import CheckPlugin, run_plugins

__all__ = ["CheckPlugin", "run_plugins"]
