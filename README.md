# Apple Notes Exporter

AppleScript that exports all your Apple Notes to Markdown files on disk, preserving folder structure and attachments.

## Output Structure

```
~/Desktop/NotesExport/
  <Account>/
    <Folder>/
      <Note Title>.md
      <Note Title>/        ← only created if the note has attachments
        photo.jpg
        document.pdf
```

Each `.md` file contains YAML frontmatter followed by the note body:

```markdown
---
title: My Note
created: 2024-03-01T10:00:00
modified: 2025-01-15T14:32:00
---

Note content here...

## Attachments

![photo.jpg](My Note/photo.jpg)
[document.pdf](My Note/document.pdf)
```

Images are linked with `![]()` syntax. All other file types use plain `[]()` links.

## Requirements

- macOS (tested on macOS 14+)
- Script Editor (`/Applications/Utilities/Script Editor.app`)

No additional software required — the script uses only Perl, which is built into every macOS.

## Usage

1. Open **Script Editor**
2. File → Open → select `export-notes.applescript`
3. Click **Run** (▶)
4. Grant Notes access when macOS prompts for permission
5. When complete, a dialog shows the export summary with an option to open the export folder

The export is written to `~/Desktop/NotesExport/`.

## Permissions

On first run, macOS will ask for permission to access Notes. Grant it. If the script hangs or shows a permission error, go to **System Settings → Privacy & Security → Automation** and ensure Script Editor has access to Notes.

## Error Handling

Notes that fail to export are skipped and logged to:

```
~/Desktop/NotesExport/export-errors.log
```

Common causes:
- **Error 100000** — note contains large attachments or embedded images that Notes can't serialize via AppleScript. The script falls back to `plaintext` for these notes, so text content is still exported.
- Notes that are still syncing from iCloud may fail transiently; re-running the script will retry them.

The error log is cleared at the start of each run.

## Notes on Attachments

Attachments are copied from Notes' internal storage (`~/Library/Group Containers/group.com.apple.notes/`) to a subfolder beside the note file. The source files are never modified.

Attachments with a `url` property that doesn't point to an existing local file (e.g. web links) are silently skipped.

## Re-running

The script does **not** merge with a previous export — it overwrites existing `.md` files and re-copies attachments. Delete `~/Desktop/NotesExport/` before re-running if you want a clean export.
