"""UTC time helpers used across auth/deps and quota logic.

Centralised here so we have a single source of truth and tests are easy.
Note: admin.py still has duplicate helpers (owned by another agent); they will
be reconciled in a follow-up pass.
"""
from __future__ import annotations

import calendar
from datetime import datetime, timedelta, timezone


def utc_now() -> datetime:
    """Current UTC time as a timezone-aware datetime."""
    return datetime.now(timezone.utc)


def start_of_today_utc() -> datetime:
    """Midnight (00:00:00) UTC for the current day."""
    now = utc_now()
    return now.replace(hour=0, minute=0, second=0, microsecond=0)


def start_of_current_month_utc() -> datetime:
    """Midnight UTC on the 1st of the current month."""
    now = utc_now()
    return now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)


def days_remaining_in_month() -> int:
    """Whole days left in the current month, including today (>= 1)."""
    now = utc_now()
    _, last_day = calendar.monthrange(now.year, now.month)
    return last_day - now.day + 1


__all__ = [
    "utc_now",
    "start_of_today_utc",
    "start_of_current_month_utc",
    "days_remaining_in_month",
]
