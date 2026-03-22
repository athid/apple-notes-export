# Design: Rich HTML → Markdown Conversion

**Date:** 2026-03-22
**Status:** Approved

## Problem

The existing `export-notes.applescript` converts Apple Notes HTML bodies to Markdown by stripping all tags via Perl regex. This loses:

- Headings (`<h1>`–`<h6>`)
- Inline images (`<img>` tags embedded in the note body)
- Checklist / todo items and their checked state
- Bold, italic, strikethrough formatting

Attachments are already copied to disk and linked at the bottom of each note in an "Attachments" section. The goal is to also render them inline where they appear in the note body.

## Approach

Enhance the embedded Perl script (Approach A). Apple Notes generates consistent, well-structured HTML — targeted regex substitutions applied before the existing tag-strip step are sufficient. No new runtime dependencies.

## Changes

### 1. Perl script — new conversion rules

A new argument is added: `$images_file` — a newline-separated list of exported image markdown references (`![name](relative/path)`), one per inline image, in document order.

Conversions applied **before** the existing tag-strip, in this order:

| HTML | Markdown |
|------|----------|
| `<h1>…</h1>` | `# …` |
| `<h2>…</h2>` | `## …` |
| `<h3>…</h3>` | `### …` |
| `<h4>…</h4>` | `#### …` |
| `<h5>…</h5>` | `##### …` |
| `<h6>…</h6>` | `###### …` |
| `<b>…</b>` / `<strong>…</strong>` | `**…**` |
| `<i>…</i>` / `<em>…</em>` | `*…*` |
| `<s>…</s>` / `<del>…</del>` / `<strike>…</strike>` | `~~…~~` |
| `<img …>` | `![name](path)` — consumed in order from `$images_file`; unmatched drops silently |
| `<li>` in checklist context (checked) | `- [x] ` |
| `<li>` in checklist context (unchecked) | `- [ ] ` |
| `<li>` outside checklist | `- ` |

**Checklist detection:** Apple Notes marks checked items with `class="checked"` on the `<li>` or `data-done="YES"`. The Perl script handles both patterns.

After conversions, the existing tag-strip and whitespace-collapse runs unchanged.

### 2. AppleScript — image path list

In `writeNote`, after the attachment export loop, a second string `imageLinks` is built containing only the markdown image references (the `![…](…)` lines) for image-type attachments, in export order. This is written to `/tmp/apple_notes_images_tmp.txt` and passed as the new argument to the Perl script.

The existing `attachmentLinks` / "Attachments" footer section is preserved unchanged.

## Arguments to Perl script (updated)

```
perl script.pl <html_file> <links_file> <images_file> <out_file> <title> <created> <modified>
```

## Unresolved edge cases

- Apple Notes may embed small inline images (e.g. checklist icons, emoji as images) as `<img>` tags that are not in the `attachments` collection. These will be unmatched and silently dropped, which is correct.
- Underline (`<u>`) has no standard Markdown equivalent and is intentionally not converted (left to tag-strip).
- Nested formatting (e.g. `<b><i>…</i></b>`) is handled by sequential regex; complex nesting may produce slightly off results but is rare in Apple Notes.
