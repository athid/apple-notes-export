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

### 1. Perl script — updated argument signature

Old:
```
perl script.pl <html_file> <links_file> <out_file> <title> <created> <modified>
```

New:
```
perl script.pl <html_file> <links_file> <images_file> <out_file> <title> <created> <modified>
```

The `$images_file` argument is inserted between `$links_file` and `$out_file`. The Perl `@ARGV` unpack becomes:

```perl
my ($html_file, $links_file, $images_file, $out_file, $title, $created, $modified) = @ARGV;
```

### 2. AppleScript — updated `do shell script` invocation

The existing call:
```applescript
do shell script "perl " & quoted form of perlScript & " " & quoted form of tmpHtml & " " & quoted form of tmpLinks & " " & quoted form of finalPath & " " & quoted form of noteTitle & " " & quoted form of createdStr & " " & quoted form of modifiedStr
```

Becomes:
```applescript
set tmpImages to "/tmp/apple_notes_images_tmp.txt"
do shell script "perl " & quoted form of perlScript & " " & quoted form of tmpHtml & " " & quoted form of tmpLinks & " " & quoted form of tmpImages & " " & quoted form of finalPath & " " & quoted form of noteTitle & " " & quoted form of createdStr & " " & quoted form of modifiedStr
```

### 3. AppleScript — building `imageLinks`

In `writeNote`, the existing attachment loop already builds `attachmentLinks` (all attachment types). In the same loop, a second string `imageLinks` is built containing only `![name](path)` entries for image-type attachments, in export order. Both strings are still written — `attachmentLinks` to the existing `tmpLinks` file, and `imageLinks` to the new `tmpImages` file.

**Images intentionally remain in the Attachments footer** (duplication accepted — the footer serves as an index and fallback for broken inline references).

If `imageLinks` is empty (note has no image attachments), an empty string is written to `tmpImages`. The Perl script handles this gracefully (see §4).

### 4. Perl script — new conversion rules

Conversions applied **before** the existing tag-strip step, in this order. Heading conversion **must** run before tag-strip because headings may contain nested `<span>` tags (Apple Notes often injects style spans); the trailing tag-strip removes those spans cleanly.

**Inline images — array consumption:**

```perl
open(my $img_fh, '<:utf8', $images_file) or die $!;
my @images = grep { /\S/ } split(/\n/, do { local $/; <$img_fh> });
close $img_fh;
my $img_idx = 0;

$text =~ s/<img[^>]*>/
    $img_idx < scalar(@images) ? $images[$img_idx++] : ''
/gei;
```

Each `<img>` tag is replaced by the next entry in `@images`. Unmatched `<img>` tags (e.g. Apple-injected checklist icons not in the `attachments` collection) are replaced with an empty string and silently dropped.

**Checklists:**

Apple Notes emits checklist `<ul>` blocks with a `checklist` class. Unchecked items inside a checklist `<ul>` become `- [ ] `; checked items (class `checked` or `data-done="YES"`) become `- [x] `; `<li>` elements outside a checklist context become plain `- ` bullets.

Implementation uses a block-level substitution to distinguish checklist context from regular lists:

```perl
# Step 1: convert entire <ul class="checklist">…</ul> blocks
$text =~ s{<ul([^>]*)>(.*?)</ul>}{
    my ($attrs, $inner) = ($1, $2);
    if ($attrs =~ /\bclass="[^"]*\bchecklist\b/) {
        # checked items
        $inner =~ s/<li[^>]*\bclass="[^"]*\bchecked\b[^"]*"[^>]*>/- [x] /gi;
        $inner =~ s/<li[^>]*data-done="YES"[^>]*>/- [x] /gi;
        # remaining unchecked items
        $inner =~ s/<li[^>]*>/- [ ] /gi;
        $inner;
    } else {
        "<ul$attrs>$inner</ul>";  # leave non-checklist uls for next step
    }
}gsei;

# Step 2: convert remaining (non-checklist) <li> to plain bullets
$text =~ s/<li[^>]*>/- /gi;
```

Note: the `<ul>` / `</ul>` wrapper tags for non-checklist lists are stripped by the existing `<[^>]+>` tag-strip. Checklist `<ul>` wrappers are consumed by the block substitution. Both leave an extra blank line above/below list blocks — a known cosmetic artifact, accepted.

**Regular lists** (non-checklist `<li>` elements) are handled by the same fallback `<li>` rule above, producing `- `. Ordered list numbering is not preserved (all items become `- `); Apple Notes rarely uses ordered lists.

**Conversion table (applied in order):**

| HTML | Markdown | Notes |
|------|----------|-------|
| `<h1>…</h1>` | `# …\n` | Must run before tag-strip |
| `<h2>…</h2>` | `## …\n` | |
| `<h3>…</h3>` | `### …\n` | |
| `<h4>…</h4>` | `#### …\n` | |
| `<h5>…</h5>` | `##### …\n` | |
| `<h6>…</h6>` | `###### …\n` | |
| `<b>…</b>` / `<strong>…</strong>` | `**…**` | |
| `<i>…</i>` / `<em>…</em>` | `*…*` | |
| `<s>…</s>` / `<del>…</del>` / `<strike>…</strike>` | `~~…~~` | |
| `<img …>` | `![name](path)` or `` | Array-consumed in order |
| `<li class="…checked…">` inside checklist `<ul>` | `- [x] ` | Word-boundary class match; block-level detection |
| `<li data-done="YES">` inside checklist `<ul>` | `- [x] ` | Alternate Apple format |
| remaining `<li>` inside checklist `<ul>` | `- [ ] ` | Unchecked checklist item |
| `<li>` outside checklist `<ul>` | `- ` | Plain bullet |

After these conversions the existing tag-strip and whitespace-collapse runs unchanged.

## Known Edge Cases

- **Underline** (`<u>`) has no standard Markdown equivalent — left to tag-strip (dropped).
- **Bold/italic inside headings** (e.g. `<h2><b>Title</b></h2>`) produces `## **Title**` — visually redundant but harmless.
- **Nested formatting** (e.g. `<b><i>…</i></b>`) handled by sequential regex; complex nesting may produce slightly off results but is rare in Apple Notes output.
- **Checklist `<ul>` wrappers** produce an extra blank line above/below checklist blocks — cosmetic artifact, accepted.
- **Apple-injected `<img>` icons** (checklist state icons, emoji images) not in the `attachments` collection are unmatched and silently dropped.
