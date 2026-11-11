# Glypheo import — 2026-11-11

## Scope

- Read `.glypheo` NSKeyedArchiver property lists without instantiating archived classes.
- Preserve source order, cue source IDs, Unicode, whitespace, line breaks and separate track text columns.
- Flatten groups into one table with group/status notes and sequential cue numbers.
- Reuse background parsing, mapping, preview, diff, live-cue protection, atomic apply and Undo.
- Disabled source cues and empty dialogue default to ignored; the operator can enable them in preview.
- Stable source IDs support re-import while preserving production Cue UUIDs.
- No new dependency or persistent project schema change.

## Verification

- Before changes: 99 tests, 12 desktop/environment skips, no failures with UDP socket permission. The sandbox-only attempt failed the existing OSC socket test.
- After implementation: 103 tests, 12 skips, no failures, including the local user-provided sample (2,839 cues, two groups, four tracks). Source document remains outside the repository.
- Synthetic tests cover multiline Unicode, track columns, disabled-cue defaults and invalid/duplicate source IDs. Additional re-import test checks Cue identity preservation; the final targeted run passed 4 synthetic tests, with the optional local-sample test skipped because its environment variable was not set (the real sample passed in the full run above).
- Release compilation passed for both x86_64 and arm64. Existing packaging script then failed when `sips` tried to convert `Scripts/AppIcon.svg` (Cannot extract image from file / Error 13); no new DMG was produced.
- No manual native UI, IME, physical output or original Glypheo visual-fidelity acceptance performed in this task.

## Limitations

Plain text import only. Fonts, per-character styles, fades, hierarchy, panels and output settings do not migrate; warnings are shown in preview. Cue numbers are generated from document order rather than original hierarchical display numbering. Other Glypheo archive versions are not yet verified. Configure and check SubtitleStage layouts before use in a show.
