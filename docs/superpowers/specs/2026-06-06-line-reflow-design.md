# Line Reflow for Line-Segregated Text — Design

- **Date:** 2026-06-06
- **Status:** Approved (pending spec review)
- **Author:** Harvey

## Problem

PDFs (and other layout-wrapped sources) store text with a hard line
break at the end of every *visual* line, not at the end of every
sentence. `PDFPage.string` returns that text verbatim, e.g.:

```
Learning happens wherever people confront problems they do not yet know how to solve, and it\n
happens at least as often outside classrooms as within them: in the puzzle a player retries until it\n
clicks, in the game whose rules must be mastered before one can advance, in any unfamiliar task\n
approached by trial and error. What most determines whether a person learns or disengages in\n
these settings is not the outcome they reach but what they do in the process of struggling toward it.
```

`SentenceSegmenter` feeds this to `NLTokenizer(unit: .sentence)`, which
**treats a hard `\n` as a sentence boundary**. So every wrapped visual
line becomes its own "sentence." The reader then highlights and reads
one visual line at a time instead of the real sentence that spans those
lines. (Verified empirically: the block above tokenizes into 6
line-fragments as-is, but into the 2 correct sentences once newlines are
replaced with spaces.)

The same defect affects every source whose text arrives segregated by
lines: OCR output (Vision joins recognized lines with `\n`), plain-text
files exported from PDFs, and text copied out of a PDF via the global
"read selection" hotkey.

## Goal

For line-segregated sources, reflow wrapped lines into flowing text
*before* sentence segmentation so that:

- A "sentence" is a real sentence, spanning the lines it covers.
- The existing **two-tier behavior is preserved unchanged**: the
  sentence "wash" highlight spans the whole multi-line sentence, while
  reading/synthesis proceeds clause-by-clause (`KokoroChunker`) with the
  bright sub-highlight tracking the spoken clause/word. This is the
  "highlight the sentence, read in clauses" model that already exists —
  it simply starts operating on correct sentence boundaries.

### Non-goals

- No change to the highlight model, the clause chunker, or any speech
  engine.
- No de-hyphenation of words broken across a line (see Limitations).
- No reflow of sources that are *not* mechanically line-wrapped:
  Markdown, EPUB, DOCX, and the Scratchpad keep today's behavior.

## Key invariant: length-preserving reflow

The whole design rests on one property. The highlight layer maps a
sentence to its on-page range with UTF-16 offsets recorded during
segmentation:

- PDF: `PDFViewerView.selection(for:)` →
  `page.selection(for: NSRange(location: block.offsetInPage +
  sentence.offsetInBlock, length: sentence.lengthInBlock))` against the
  original `page.string`.
- Text/OCR views: offsets index into the displayed `rawText`.

If reflow replaces each line-break **character** with a single space
(1 char → 1 char), the string length and **every** UTF-16 offset are
identical to the original. So offsets produced from the reflowed copy
still address the correct characters in the original page/`rawText`, and
`page.selection(for:)` returns a multi-line `PDFSelection` →
the wash now spans the full sentence. No offset-remapping layer is
needed.

`\r\n` is handled character-wise: `\r`→space and `\n`→space, yielding
two spaces, which the tokenizer collapses harmlessly and which still
preserves length.

## Design

Approach **A** (chosen over a de-hyphenating reflow that would break the
length invariant, and over per-call-site string munging).

### 1. `LineReflow` utility

New file `App/Sources/Document/LineReflow.swift`:

```
enum LineReflow {
    /// Replaces single line breaks (a wrap within a paragraph) with a
    /// space, leaving blank-line runs (2+ consecutive breaks, i.e.
    /// paragraph separators) intact. Length-preserving: every output
    /// UTF-16 index equals the corresponding input index. Handles \n,
    /// \r, and \r\n.
    static func reflow(_ text: String) -> String
}
```

Rules:
- A line break that sits between two non-empty lines is a *wrap* →
  replace that single break character with a space.
- A run of 2+ break characters is a *paragraph separator* → leave as-is.
- All non-break characters are untouched; output `.utf16.count` ==
  input `.utf16.count`.

Preserving blank-line runs matters only for the single-block sources
(OCR/text/clipboard), where it keeps two paragraphs from merging into a
run-on sentence when the first ends without terminal punctuation (e.g. a
heading). For PDF the extractor has already split on blank lines, so a
block contains only single breaks and they all become spaces.

### 2. Opt-in flag on `SentenceSegmenter`

Centralize the behavior where offsets are produced, so exactly one place
owns the invariant and only opted-in callers change:

```
static func segment(_ blocks: [DocumentBlock],
                    reflowLineWraps: Bool = false) async -> [Sentence]
static func segmentSync(_ blocks: [DocumentBlock],
                        reflowLineWraps: Bool = false) -> [Sentence]
```

When `reflowLineWraps` is true, for each block tokenize
`LineReflow.reflow(block.text)` instead of `block.text`:
- `Sentence.text` is sliced from the reflowed copy → spoken text has
  spaces, not newlines (correct for TTS and for the clause chunker).
- `offsetInBlock` / `lengthInBlock` come from `NSRange(range, in:
  reflowed)`, which (by the length invariant) equal the offsets into the
  original block text → highlight mapping is unchanged.

Default `false` means every current caller behaves exactly as today
until it explicitly opts in.

### 3. Callers that opt in (`reflowLineWraps: true`)

| Source | File:line |
|---|---|
| PDF reader | `PDFViewer/PDFViewerView.swift:57` |
| OCR reader | `OCR/ImageOCRReaderView.swift:185` |
| Text-file reader | `Text/TextReaderView.swift:152` |
| Clipboard / selection / Services | `MenuBar/MenuBarCommand.swift:165` (`readText`) |
| Export — PDF | `Export/ExportSentenceLoader.swift:56` |
| Export — text | `Export/ExportSentenceLoader.swift:100` |
| Export — image/OCR | `Export/ExportSentenceLoader.swift:115` |

The export branches opt in so exported audio matches what playback reads
for the same file.

### 4. Callers left unchanged (default `false`)

Markdown (`MarkdownReaderView.swift:251`, export `:64`), Scratchpad
(`ScratchpadView.swift:199,216`), EPUB (`EPUBReaderView.swift:103`,
export `:74`), DOCX (`DOCXReaderView.swift:125`, export `:84`). These are
reflowable/structured or user-authored — their newlines are intentional.

For the opt-in *display* views (OCR, text), `rawText` continues to hold
the original newline'd text for faithful on-screen display; only the
segmented copy is reflowed. Offsets align because reflow is
length-preserving. The clipboard/selection path has no text view, so
there is no highlight to keep in sync there.

## Edge cases & known limitations (v1)

- **Hyphenation across a break** (`"disen-\ngages"`): becomes
  `"disen- gages"` — a stray hyphen the TTS will voice oddly. Proper
  de-hyphenation removes characters and would break the length
  invariant; deferred. Rare outside justified academic PDFs.
- **Lists / poetry inside one paragraph block**: line items joined into
  one sentence. Acceptable for the research-prose target; blank-line
  separation between items already survives.
- **Double spaces** from `\r\n` or a trailing space before a wrap:
  harmless; `NLTokenizer` ignores them and length is preserved.

## Testing

- **`LineReflowTests`** (new):
  - single `\n` between words → single space, same length.
  - `\r\n` → two spaces, same length.
  - blank-line run (`\n\n`, `\n\n\n`) preserved.
  - no non-break character altered; `output.utf16.count ==
    input.utf16.count` for representative inputs.
- **`SentenceSegmenterTests`** (extend):
  - `reflowLineWraps: true` on a multi-line PDF-style block yields the
    real sentences (e.g. the 5-line example → 2 sentences), not
    per-line fragments.
  - `reflowLineWraps: false` (default) leaves existing behavior and all
    current assertions unchanged.
  - **Offset round-trip:** for a reflowed multi-line sentence,
    `offsetInBlock + lengthInBlock` still slices the matching range out
    of the *original* (newline'd) block text — the highlight invariant.
- **`PDFTextExtractorTests`**: unchanged. The extractor still preserves
  single newlines inside a block; reflow now happens in the segmenter,
  so this test stays valid.

## Risks

- Low. The flag defaults off; only seven call sites change; the length
  invariant means no highlight/offset code is touched. Primary residual
  risk is the hyphenation artifact, documented above.
