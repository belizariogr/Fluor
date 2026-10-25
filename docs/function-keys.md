# Per-key media/function exceptions

Open **Preferences → F Keys**. Each key from F1
through F12 can follow the current mode, always act as a function key, or always
perform its keyboard's original media action. Several exceptions can be active
at once; they also apply while Fn/Globe is held, across all applications and
compatible keyboards.

Each key has the same three-icon selector used by Fluor's current-app menu:
follow mode, media (brightness icon), and function (`fn` icon). Click an icon to
change the key immediately; hover for its label. F1–F6 and F7–F12 are arranged
in two columns, with a shared icon legend above them.

Media actions are discovered from each keyboard's `FnFunctionUsageMap`, not
assumed from a particular Apple keyboard layout. A keyboard without that table
is reported as unsupported rather than assigned guessed actions. The media
action can therefore be Dictation on one keyboard and keyboard backlight on
another. Reserved macOS shortcuts, such as Command-F5 for VoiceOver, remain
subject to the system's shortcut handling.

Choices are saved in `FunctionKeyOverrides`, independently of application rules.
Exceptions are suspended when Fluor is disabled or the session is inactive, and
removed on normal exit. Fluor merges its entries into each keyboard service's
`UserKeyMapping`, records the entries it replaced before writing, and restores
only entries that still match its own last write. Recovery data is scoped to
the current boot, since keyboard registry IDs can be reused after reboot.
After an unexpected process termination, recovery runs on the next launch.

## Tests

- `bash scripts/test-function-keys.sh`: isolated XCTest coverage of mapping,
  persistence, restore, hotplug, failure and crash-recovery behavior.
- `bash scripts/test-function-keys.sh --native`: also temporarily apply
  F5/function and F10/media through IOKit, verify the system's mappings and
  restore the original entries. No keystrokes are synthesized.
- `python3 scripts/test-function-keys-ui.py`: build a separate temporary app,
  open all preference tabs in three cycles, check all twelve controls are
  visible, and exercise edits/reset. Its preferences use a separate bundle ID.
  Add `--show` to leave the window open for visual inspection.
  Use `--snapshots` to render light/dark layout snapshots under
  `build/function-key-snapshots`.

For hardware acceptance, set F5 to **Always function** and F10 to **Always
media**. In both global modes and in apps with different rules, press each key
with and without Fn: F5 must reach the app without opening Dictation; F10 must
mute. Check modifier combinations, holding/releasing keys, a second keyboard
with a different layout, sleep/wake, disable/re-enable and normal exit. Finally
reset the exceptions and confirm the keyboard's previous behavior returns.
