# Sleep-Session Handoff

Scratchpad while Harvey is asleep. Delete or rename when back.

## Files to drop into `~/rhea-fixtures/` (optional)

I'm generating synthetic fixtures inline as I go, so nothing here is blocking.
If you want the Peekaboo-captured E2E screenshots to use your real content, place these:

| Path | Expected | Used for |
|---|---|---|
| `~/rhea-fixtures/short-english.md` | ≤5 KB English markdown with headings + formatting | MarkdownReaderView quick smoke |
| `~/rhea-fixtures/long-english.md` | 20+ KB English markdown | scroll perf |
| `~/rhea-fixtures/short-english.pdf` | 1-3 page English PDF | PDF rendering basics |
| `~/rhea-fixtures/long-english.pdf` | 10+ page research PDF | extraction + highlight scale |
| `~/rhea-fixtures/chinese.pdf` | 1+ page Chinese PDF | language detection + voice routing |
| `~/rhea-fixtures/chinese.md` | Chinese markdown | bilingual path |
| `~/rhea-fixtures/mixed.md` | Markdown with EN+ZH paragraphs | bilingual auto-switch |

If absent, I synthesize them in `/tmp/rhea-fixtures/` at test time.

## Fixtures I generate / use and DO NOT DELETE

- `/tmp/rhea-e2e/` — all Peekaboo screenshots go here. Overwritten per run, not deleted.
- `/tmp/rhea-fixtures/` — synthesized test content. Persists across runs.
- `/tmp/rhea-run-network-tests` — sentinel file for opt-in URL tests. Created + removed by `Scripts/test.sh --network`.

## Work order while you sleep

- [x] Bug: library click doesn't load document (security-scoped bookmark fail in non-sandboxed Debug)
- [x] Bug: `open -a Rhea file.pdf` didn't route (added `.onOpenURL`)
- [ ] M2.6: Services menu "Read with Rhea" + global hotkey
- [ ] M2.4: Word-level highlight via `willSpeakRangeOfSpeechString` (system voices)
- [ ] M3.5: Research-PDF heuristics (footnote/citation stripping)
- [ ] M4.1: m4b audiobook export (AVAssetWriter)
- [ ] M4.4: Menubar "Read Clipboard"
- [ ] M4.5: Reading analytics (local, opt-in)
- [ ] M4.6: Pronunciation dictionary
- [ ] M4.3: EPUB support (stretch)

Skipping in this session:
- M2.3 WhisperKit forced alignment (new SwiftPM dep + another model download — needs its own round)
- M3.1–M3.4 Qwen3-TTS bilingual orchestrator (new SwiftPM dep + 1-3 GB model — needs its own round)
- Global hotkey via CGEventTap (needs Accessibility permission UX polish)

## Where to look when you wake up

- `git log` for the commit trail
- `/tmp/rhea-e2e/*.png` for UI screenshots at each milestone
- `Scripts/test.sh` output: expected 100% pass offline + network
- `docs/MILESTONES.md` for updated milestone statuses
