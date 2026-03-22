# Rich HTML → Markdown Conversion Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the Apple Notes exporter to convert headings, bold/italic/strikethrough, inline images, and checklists from HTML to Markdown instead of stripping them.

**Architecture:** All conversion logic lives in an embedded Perl script inside `export-notes.applescript`. A standalone `test/test-conversion.pl` is used to test the Perl conversion logic in isolation before embedding it. The AppleScript gains a second image-paths temp file and passes it as a new argument to Perl.

**Tech Stack:** AppleScript, Perl 5 (built into macOS), shell (bash via `do shell script`)

**Spec:** `docs/superpowers/specs/2026-03-22-rich-html-to-markdown-design.md`

---

## Chunk 1: Headings and inline formatting

### Task 1: Create Perl test harness + heading tests

**Files:**
- Create: `test/test-conversion.pl`

The test harness defines a `convert(html)` sub that runs all the conversion regexes (extracted from the embedded Perl) and returns the resulting Markdown. Tests call `ok($got, $expected, $name)` which prints PASS/FAIL and counts failures.

- [ ] **Step 1: Create `test/test-conversion.pl`**

```perl
#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use open qw(:std :utf8);

my $failures = 0;

sub ok {
    my ($got, $expected, $name) = @_;
    if ($got eq $expected) {
        print "PASS: $name\n";
    } else {
        $failures++;
        print "FAIL: $name\n";
        print "  got:      |$got|\n";
        print "  expected: |$expected|\n";
    }
}

sub convert {
    my ($text) = @_;

    # === NEW CONVERSIONS (applied before tag-strip) ===
    # Headings
    for my $n (1..6) {
        my $hashes = '#' x $n;
        $text =~ s{<h$n[^>]*>(.*?)</h$n>}{"\n$hashes $1\n"}gsei;
    }

    # Inline formatting (identical patterns to embedded Perl)
    $text =~ s{<(?:b|strong)\b[^>]*>(.*?)</(?:b|strong)>}{**$1**}gsi;
    $text =~ s{<(?:i|em)\b[^>]*>(.*?)</(?:i|em)>}{*$1*}gsi;
    $text =~ s{<(?:s|del|strike)\b[^>]*>(.*?)</(?:s|del|strike)>}{~~$1~~}gsi;

    # === EXISTING tag-strip (unchanged) ===
    $text =~ s/<br\s*\/?>/\n/gi;
    $text =~ s/<\/(div|p|li|h[1-6])>/\n/gi;
    $text =~ s/<[^>]+>//g;
    $text =~ s/&nbsp;/ /g;
    $text =~ s/&lt;/</g;
    $text =~ s/&gt;/>/g;
    $text =~ s/&amp;/&/g;
    $text =~ s/&quot;/"/g;
    $text =~ s/&#(\d+);/chr($1)/ge;
    $text =~ s/&#x([0-9a-fA-F]+);/chr(hex($1))/ge;
    $text =~ s/[ \t]+$//mg;
    $text =~ s/^[ \t]+$//mg;
    $text =~ s/\n{3,}/\n\n/g;
    $text =~ s/^\s+|\s+$//g;

    return $text;
}

# --- Heading tests ---
ok(convert('<h1>Title</h1>'), '# Title', 'h1');
ok(convert('<h2>Sub</h2>'),   '## Sub',  'h2');
ok(convert('<h3>Sub</h3>'),   '### Sub', 'h3');
ok(convert('<h6>Deep</h6>'),  '###### Deep', 'h6');
ok(convert('<h2><span style="color:red">Styled</span></h2>'), '## Styled', 'h2 with nested span');

# --- Inline formatting tests ---
ok(convert('<b>bold</b>'),             '**bold**',   'bold <b>');
ok(convert('<strong>bold</strong>'),   '**bold**',   'bold <strong>');
ok(convert('<i>italic</i>'),           '*italic*',   'italic <i>');
ok(convert('<em>italic</em>'),         '*italic*',   'italic <em>');
ok(convert('<s>struck</s>'),           '~~struck~~', 'strikethrough <s>');
ok(convert('<del>struck</del>'),       '~~struck~~', 'strikethrough <del>');
ok(convert('<strike>struck</strike>'), '~~struck~~', 'strikethrough <strike>');
ok(convert('<b><i>both</i></b>'),      '***both***', 'nested bold+italic');

exit $failures > 0 ? 1 : 0;
```

- [ ] **Step 2: Run tests — expect PASS**

```bash
perl test/test-conversion.pl
```

Expected: all tests PASS immediately because the conversion sub above already contains the implementation. Verify output is all PASS with exit code 0.

```
PASS: h1
PASS: h2
...
PASS: nested bold+italic
```

- [ ] **Step 3: Verify exit code is 0**

```bash
perl test/test-conversion.pl; echo "exit: $?"
```

Expected: `exit: 0`

- [ ] **Step 4: Commit**

```bash
git add test/test-conversion.pl
git commit -m "test: add Perl conversion test harness with heading and formatting tests"
```

---

### Task 2: Update embedded Perl in AppleScript — headings and inline formatting

**Files:**
- Modify: `export-notes.applescript` (the `writePerlScript` handler, lines 21–52)

The Perl script is built as a string via `set pl to pl & "..." & linefeed`. We insert the new conversion rules after the argument unpacking lines but before the existing `$text =~ s/<br...>` line.

**Important:** AppleScript string literals use `"` as delimiter. Double-quotes inside the Perl code must be escaped as `\"`. The `$` sign does not need escaping in AppleScript strings. Backslashes in the Perl regex must be doubled (`\\n` in Perl → `\\\\n` in AppleScript string literal) — but since the script uses `linefeed` for actual newlines and Perl regex `\n` inside double-quoted strings, check each backslash carefully. The existing lines use `\\n`, `\\s`, etc. already — follow the same pattern.

- [ ] **Step 1: Open `export-notes.applescript` and locate the insertion point**

The new lines go after line 29 (`set pl to pl & "local $/; my $text = <$fh>; close $fh;" & linefeed`) and before line 31 (`set pl to pl & "$text =~ s/<br\\s*\\/?>/\\n/gi;" & linefeed`).

- [ ] **Step 2: Insert heading and formatting conversions into `writePerlScript`**

Replace this block (lines 31–33, the opening of the existing conversions):
```applescript
	set pl to pl & "$text =~ s/<br\\s*\\/?>/\\n/gi;" & linefeed
	set pl to pl & "$text =~ s/<\\/(div|p|li|h[1-6])>/\\n/gi;" & linefeed
	set pl to pl & "$text =~ s/<[^>]+>//g;" & linefeed
```

With:
```applescript
	-- Headings (must run before tag-strip; nested spans handled by subsequent tag-strip)
	set pl to pl & "for my $n (1..6) { my $hashes = '#' x $n; $text =~ s{<h$n\\b[^>]*>(.*?)</h$n>}{\"\\n$hashes $1\\n\"}gsei; }" & linefeed
	-- Inline formatting
	set pl to pl & "$text =~ s{<(?:b|strong)\\b[^>]*>(.*?)</(?:b|strong)>}{**$1**}gsi;" & linefeed
	set pl to pl & "$text =~ s{<(?:i|em)\\b[^>]*>(.*?)</(?:i|em)>}{*$1*}gsi;" & linefeed
	set pl to pl & "$text =~ s{<(?:s|del|strike)\\b[^>]*>(.*?)</(?:s|del|strike)>}{~~$1~~}gsi;" & linefeed
	-- Existing tag-strip (unchanged)
	set pl to pl & "$text =~ s/<br\\s*\\/?>/\\n/gi;" & linefeed
	set pl to pl & "$text =~ s/<\\/(div|p|li|h[1-6])>/\\n/gi;" & linefeed
	set pl to pl & "$text =~ s/<[^>]+>//g;" & linefeed
```

- [ ] **Step 3: Verify the Perl script writes and runs without syntax errors**

```bash
osascript -e '
set pl to ""
set pl to pl & "use strict; use warnings; use utf8;" & linefeed
set pl to pl & "for my $n (1..6) { my $hashes = '"'"'#'"'"' x $n; $text =~ s{<h$n\\b[^>]*>(.*?)</h$n>}{\"\\n$hashes $1\\n\"}gsei; }" & linefeed
set pl to pl & "$text =~ s{<(?:b|strong)\\b[^>]*>(.*?)</(?:b|strong)>}{**$1**}gsi;" & linefeed
do shell script "printf '"'"'%s'"'"' " & quoted form of pl & " | perl -c -"
'
```

Expected output: `- syntax OK`

- [ ] **Step 4: Commit**

```bash
git add export-notes.applescript
git commit -m "feat: convert headings and inline formatting (bold, italic, strikethrough) to Markdown"
```

---

## Chunk 2: Checklist conversion

### Task 3: Add checklist tests to test harness

**Files:**
- Modify: `test/test-conversion.pl`

- [ ] **Step 1: Add the checklist conversion sub to `convert()` in `test/test-conversion.pl`**

Insert these lines in the `convert` sub, after the inline formatting block and before the existing tag-strip block:

```perl
    # Checklists — block-level ul detection
    $text =~ s{<ul([^>]*)>(.*?)</ul>}{
        my ($attrs, $inner) = ($1, $2);
        if ($attrs =~ /\bclass="[^"]*\bchecklist\b/) {
            $inner =~ s/<li[^>]*\bclass="[^"]*\bchecked\b[^"]*"[^>]*>/- [x] /gi;
            $inner =~ s/<li[^>]*data-done="YES"[^>]*>/- [x] /gi;
            $inner =~ s/<li[^>]*>/- [ ] /gi;
            $inner;
        } else {
            "<ul$attrs>$inner</ul>";
        }
    }gsei;
    # Regular list items (outside checklist context)
    $text =~ s/<li[^>]*>/- /gi;
```

- [ ] **Step 2: Add checklist test cases at the bottom of `test/test-conversion.pl`** (before the `exit` line)

```perl
# --- Checklist tests ---
ok(
    convert('<ul class="checklist"><li class="checked"><p>Done</p></li><li><p>Todo</p></li></ul>'),
    "- [x] Done\n- [ ] Todo",
    'checklist with one checked, one unchecked'
);
ok(
    convert('<ul class="checklist"><li data-done="YES"><p>Done</p></li></ul>'),
    "- [x] Done",
    'checklist data-done="YES" format'
);
ok(
    convert('<ul class="checklist other-class"><li class="checked item"><p>Done</p></li></ul>'),
    "- [x] Done",
    'checklist with multiple classes'
);
# Regular list should produce plain bullets, not checkboxes
ok(
    convert('<ul><li>Item A</li><li>Item B</li></ul>'),
    "- Item A\n- Item B",
    'regular bullet list produces plain bullets'
);
```

- [ ] **Step 3: Run tests**

```bash
perl test/test-conversion.pl
```

Expected: all tests PASS, exit code 0.

- [ ] **Step 4: Commit**

```bash
git add test/test-conversion.pl
git commit -m "test: add checklist and bullet list conversion tests"
```

---

### Task 4: Update embedded Perl — checklist conversion

**Files:**
- Modify: `export-notes.applescript` (inside `writePerlScript`, after the inline formatting lines added in Task 2)

The checklist conversion uses `s{...}{...}gsei` with a code block. In AppleScript string literals the `{` and `}` delimiters don't need escaping, but `$1` / `$2` inside the replacement block are Perl variables (fine). The `/e` modifier evaluates the replacement as code.

- [ ] **Step 1: Insert checklist conversion lines after the inline formatting lines in `writePerlScript`**

After the `~~$1~~` strikethrough line and before `-- Existing tag-strip`, add:

```applescript
	-- Checklists (block-level ul.checklist detection)
	set pl to pl & "$text =~ s{<ul([^>]*)>(.*?)</ul>}{" & linefeed
	set pl to pl & "    my ($attrs, $inner) = ($1, $2);" & linefeed
	set pl to pl & "    if ($attrs =~ /\\bclass=\"[^\"]*\\bchecklist\\b/) {" & linefeed
	set pl to pl & "        $inner =~ s/<li[^>]*\\bclass=\"[^\"]*\\bchecked\\b[^\"]*\"[^>]*>/- [x] /gi;" & linefeed
	set pl to pl & "        $inner =~ s/<li[^>]*data-done=\"YES\"[^>]*>/- [x] /gi;" & linefeed
	set pl to pl & "        $inner =~ s/<li[^>]*>/- [ ] /gi;" & linefeed
	set pl to pl & "        $inner;" & linefeed
	set pl to pl & "    } else {" & linefeed
	set pl to pl & "        \"<ul$attrs>$inner</ul>\";" & linefeed
	set pl to pl & "    }" & linefeed
	set pl to pl & "}gsei;" & linefeed
	set pl to pl & "$text =~ s/<li[^>]*>/- /gi;" & linefeed
```

- [ ] **Step 2: Verify Perl syntax by running a quick syntax check**

```bash
# Write the Perl script to disk and check syntax
osascript export-notes.applescript 2>&1 | head -5 || true
# Alternatively, extract the embedded Perl logic manually:
perl -e '
$text = "";
# paste key new lines and check -c
' -c 2>&1
```

Since running the full AppleScript requires Notes to be open, do a targeted syntax check instead:

```bash
perl -c - <<'PERL'
use strict; use warnings; use utf8;
my $text = "<ul class=\"checklist\"><li class=\"checked\"><p>Done</p></li><li><p>Todo</p></li></ul>";
$text =~ s{<ul([^>]*)>(.*?)</ul>}{
    my ($attrs, $inner) = ($1, $2);
    if ($attrs =~ /\bclass="[^"]*\bchecklist\b/) {
        $inner =~ s/<li[^>]*\bclass="[^"]*\bchecked\b[^"]*"[^>]*>/- [x] /gi;
        $inner =~ s/<li[^>]*data-done="YES"[^>]*>/- [x] /gi;
        $inner =~ s/<li[^>]*>/- [ ] /gi;
        $inner;
    } else {
        "<ul$attrs>$inner</ul>";
    }
}gsei;
$text =~ s/<li[^>]*>/- /gi;
$text =~ s/<[^>]+>//g;
print $text;
PERL
```

Expected output: `- [x] Done- [ ] Todo` (whitespace collapses handled by later rules).

- [ ] **Step 3: Commit**

```bash
git add export-notes.applescript
git commit -m "feat: convert Apple Notes checklists to GFM checkboxes (- [x] / - [ ])"
```

---

## Chunk 3: Inline images + AppleScript wiring

### Task 5: Add image tests to test harness

**Files:**
- Modify: `test/test-conversion.pl`

The image conversion needs the `@images` array pre-populated (simulating what the AppleScript writes to `$images_file`). We test this by calling a variant of `convert` that accepts the image list.

- [ ] **Step 1: Refactor `convert` in `test/test-conversion.pl` to accept an optional images array**

Change the `convert` sub signature to:

```perl
sub convert {
    my ($text, @images) = @_;
    my $img_idx = 0;

    # ... heading and formatting conversions unchanged ...

    # Inline images
    $text =~ s/<img[^>]*>/
        $img_idx < scalar(@images) ? $images[$img_idx++] : ''
    /gei;

    # ... checklist and tag-strip conversions unchanged ...
}
```

- [ ] **Step 2: Add image test cases** (before `exit`)

```perl
# --- Inline image tests ---
ok(
    convert('<p>See <img src="x-coredata://abc"> below</p>', '![photo.jpg](MyNote/photo.jpg)'),
    'See ![photo.jpg](MyNote/photo.jpg) below',
    'single inline image replaced'
);
ok(
    convert('<img src="a"><img src="b">',
        '![a.jpg](Note/a.jpg)', '![b.jpg](Note/b.jpg)'),
    '![a.jpg](Note/a.jpg)![b.jpg](Note/b.jpg)',
    'two inline images consumed in order'
);
ok(
    convert('<img src="icon.png">plain text'),  # no images array — unmatched
    'plain text',
    'unmatched img tag silently dropped'
);
```

- [ ] **Step 3: Run tests**

```bash
perl test/test-conversion.pl
```

Expected: all tests PASS, exit code 0.

- [ ] **Step 4: Commit**

```bash
git add test/test-conversion.pl
git commit -m "test: add inline image replacement tests"
```

---

### Task 6: Update Perl script — inline image replacement

**Files:**
- Modify: `export-notes.applescript` (`writePerlScript` and argument unpack line)

- [ ] **Step 1: Update `@ARGV` unpack in `writePerlScript`**

Find this line (currently line 25):
```applescript
	set pl to pl & "my ($html_file, $links_file, $out_file, $title, $created, $modified) = @ARGV;" & linefeed
```

Replace with:
```applescript
	set pl to pl & "my ($html_file, $links_file, $images_file, $out_file, $title, $created, $modified) = @ARGV;" & linefeed
```

- [ ] **Step 2: Add `$images_file` reading and `<img>` substitution to `writePerlScript`**

After the `$links` trimming line (currently `$links =~ s/^\s+|\s+$//g if defined $links;`) and before the heading conversions, insert:

```applescript
	set pl to pl & "open(my $img_fh, '<:utf8', $images_file) or die $!;" & linefeed
	set pl to pl & "my @images = grep { /\\S/ } split(/\\n/, do { local $/; <$img_fh> });" & linefeed
	set pl to pl & "close $img_fh;" & linefeed
	set pl to pl & "my $img_idx = 0;" & linefeed
```

Then after the inline formatting lines and before the checklist block, insert the `<img>` substitution:

```applescript
	-- Inline images (consumed in document order from images_file)
	set pl to pl & "$text =~ s/<img[^>]*>/" & linefeed
	set pl to pl & "    $img_idx < scalar(@images) ? $images[$img_idx++] : ''" & linefeed
	set pl to pl & "/gei;" & linefeed
```

- [ ] **Step 3: Verify Perl syntax**

```bash
perl -c - <<'PERL'
use strict; use warnings; use utf8;
use open qw(:std :utf8);
my ($html_file, $links_file, $images_file, $out_file, $title, $created, $modified) = @ARGV;
open(my $fh, '<:utf8', $html_file) or die $!;
local $/; my $text = <$fh>; close $fh;
open($fh, '<:utf8', $links_file) or die $!;
my $links = <$fh>; close $fh;
$links =~ s/^\s+|\s+$//g if defined $links;
open(my $img_fh, '<:utf8', $images_file) or die $!;
my @images = grep { /\S/ } split(/\n/, do { local $/; <$img_fh> });
close $img_fh;
my $img_idx = 0;
for my $n (1..6) { my $hashes = '#' x $n; $text =~ s{<h$n\b[^>]*>(.*?)</h$n>}{"\n$hashes $1\n"}gsei; }
$text =~ s{<(?:b|strong)\b[^>]*>(.*?)</(?:b|strong)>}{**$1**}gsi;
$text =~ s{<(?:i|em)\b[^>]*>(.*?)</(?:i|em)>}{*$1*}gsi;
$text =~ s{<(?:s|del|strike)\b[^>]*>(.*?)</(?:s|del|strike)>}{~~$1~~}gsi;
$text =~ s/<img[^>]*>/
    $img_idx < scalar(@images) ? $images[$img_idx++] : ''
/gei;
$text =~ s{<ul([^>]*)>(.*?)</ul>}{
    my ($attrs, $inner) = ($1, $2);
    if ($attrs =~ /\bclass="[^"]*\bchecklist\b/) {
        $inner =~ s/<li[^>]*\bclass="[^"]*\bchecked\b[^"]*"[^>]*>/- [x] /gi;
        $inner =~ s/<li[^>]*data-done="YES"[^>]*>/- [x] /gi;
        $inner =~ s/<li[^>]*>/- [ ] /gi;
        $inner;
    } else {
        "<ul$attrs>$inner</ul>";
    }
}gsei;
$text =~ s/<li[^>]*>/- /gi;
$text =~ s/<br\s*\/?>/\n/gi;
$text =~ s/<\/(div|p|li|h[1-6])>/\n/gi;
$text =~ s/<[^>]+>//g;
PERL
```

Expected: `- syntax OK`

- [ ] **Step 4: Commit**

```bash
git add export-notes.applescript
git commit -m "feat: add inline image replacement in Perl script (array-consumed in document order)"
```

---

### Task 7: Update AppleScript — build `imageLinks` and pass `tmpImages`

**Files:**
- Modify: `export-notes.applescript` (`writeNote` handler, lines 54–134)

- [ ] **Step 1: Add `imageLinks` string initialisation in `writeNote`**

Find the `set attachmentLinks to ""` line (line 96 in the current file — just before `repeat with attItem in attData`):
```applescript
	set attachmentLinks to ""
```

Add immediately after:
```applescript
	set imageLinks to ""
```

- [ ] **Step 2: Populate `imageLinks` inside the attachment export loop**

Inside the loop where `attachmentLinks` is built (lines 116–119), the existing code already has:
```applescript
			if attExt is in {"jpg", "jpeg", "png", "gif", "webp", "heic", "svg"} then
				set attachmentLinks to attachmentLinks & "![" & relName & "](" & safeTitle & "/" & relName & ")" & linefeed
			else
				set attachmentLinks to attachmentLinks & "[" & relName & "](" & safeTitle & "/" & relName & ")" & linefeed
			end if
```

Change to:
```applescript
			if attExt is in {"jpg", "jpeg", "png", "gif", "webp", "heic", "svg"} then
				set attachmentLinks to attachmentLinks & "![" & relName & "](" & safeTitle & "/" & relName & ")" & linefeed
				set imageLinks to imageLinks & "![" & relName & "](" & safeTitle & "/" & relName & ")" & linefeed
			else
				set attachmentLinks to attachmentLinks & "[" & relName & "](" & safeTitle & "/" & relName & ")" & linefeed
			end if
```

- [ ] **Step 3: Write `imageLinks` to `tmpImages` and update the Perl invocation**

Find these lines (around line 128–133):
```applescript
	set tmpHtml to "/tmp/apple_notes_export_tmp.html"
	set tmpLinks to "/tmp/apple_notes_links_tmp.txt"
	do shell script "printf '%s' " & quoted form of noteBody & " > " & quoted form of tmpHtml
	do shell script "printf '%s' " & quoted form of attachmentLinks & " > " & quoted form of tmpLinks

	do shell script "perl " & quoted form of perlScript & " " & quoted form of tmpHtml & " " & quoted form of tmpLinks & " " & quoted form of finalPath & " " & quoted form of noteTitle & " " & quoted form of createdStr & " " & quoted form of modifiedStr
```

Replace with:
```applescript
	set tmpHtml to "/tmp/apple_notes_export_tmp.html"
	set tmpLinks to "/tmp/apple_notes_links_tmp.txt"
	set tmpImages to "/tmp/apple_notes_images_tmp.txt"
	do shell script "printf '%s' " & quoted form of noteBody & " > " & quoted form of tmpHtml
	do shell script "printf '%s' " & quoted form of attachmentLinks & " > " & quoted form of tmpLinks
	do shell script "printf '%s' " & quoted form of imageLinks & " > " & quoted form of tmpImages

	do shell script "perl " & quoted form of perlScript & " " & quoted form of tmpHtml & " " & quoted form of tmpLinks & " " & quoted form of tmpImages & " " & quoted form of finalPath & " " & quoted form of noteTitle & " " & quoted form of createdStr & " " & quoted form of modifiedStr
```

- [ ] **Step 4: Run all Perl tests one final time to confirm nothing regressed**

```bash
perl test/test-conversion.pl
```

Expected: all PASS, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add export-notes.applescript
git commit -m "feat: wire imageLinks through AppleScript to Perl for inline image rendering"
```

---

## Final verification

- [ ] Open `export-notes.applescript` in Script Editor and run it against a test Apple Notes account that has notes with:
  - Headings (h1/h2)
  - Bold, italic, strikethrough text
  - A checklist with some items checked
  - An attached image
- [ ] Open the resulting `.md` file and confirm:
  - Headings render as `#` / `##` etc.
  - Bold/italic/strikethrough render as `**` / `*` / `~~`
  - Checklist items render as `- [x]` / `- [ ]`
  - The image appears inline in the body AND in the Attachments footer
