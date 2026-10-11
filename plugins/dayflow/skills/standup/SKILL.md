---
name: standup
description: Draft a standup or daily status update from the user's Dayflow timeline. Use when the user asks for a standup, daily update, or "what did I do yesterday".
---

# Standup from Dayflow

1. Work out which day the user means. "Yesterday" on a Monday usually means
   Friday; ask only if it is unclear.
2. Call `get_daily` for that date. If Dayflow already wrote a Daily, use its
   highlights, tasks, and blockers as the starting point.
3. If there is no Daily, call `get_timeline` for the day and build the update
   from the activities, skipping `Idle`, `System`, and distraction entries.
4. Call `get_activity_detail` for at most three activities where the one-line
   summary is too thin to describe the work.

Write the update as three short sections: what got done, what is next, and
blockers. Describe outcomes rather than apps and minutes, keep it to what a
teammate needs, and leave out anything personal. Say "None" for blockers
rather than inventing one.
