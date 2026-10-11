---
name: onboarding
description: Check that Dayflow is installed and recording, then summarize the user's day. Use when the user chooses Set up for Dayflow or asks for onboarding.
---

# Set up Dayflow

Call `get_status` with `{}`.

- If the Dayflow tools are missing or the call fails because no data was
  found, the Dayflow Mac app is not installed or has not recorded yet. Tell
  the user to install it from https://dayflow.so, finish its onboarding, and
  let it record for about fifteen minutes. Stop there.
- If `last_capture_at` is more than an hour old, mention that recording looks
  paused and that they can resume it from Dayflow's menu bar icon.
- If `pending_batches` is above zero, mention that recent time is still being
  analyzed and will appear shortly.

Then call `get_timeline` with `{}` and give the user a three or four line
summary of their day so far, so they see it working. Tell them what they can
ask for next: where their time went, a standup, or a weekly review.

If `edits_enabled` is false, mention once that this plugin can only read the
timeline until they turn on edits in Dayflow under Settings, AI Tools. If
they installed the plugin during an existing task, continue that task.
