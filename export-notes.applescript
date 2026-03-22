-- Export Apple Notes to Markdown files with YAML frontmatter + attachments
-- Folder structure:
--   ~/Desktop/NotesExport/<Account>/<Folder>/<Note>.md
--   ~/Desktop/NotesExport/<Account>/<Folder>/<Note>/attachment.jpg
-- Run in Script Editor

property exportRoot : (POSIX path of (path to desktop)) & "NotesExport/"
property perlScript : "/tmp/notes_exporter.pl"

on sanitizeName(n)
	set sanitized to do shell script "printf '%s' " & quoted form of n & " | tr '/:*?\"<>|\\\\' '-' | sed 's/^[[:space:]-]*//;s/[[:space:]-]*$//'"
	if sanitized is "" then return "Untitled"
	return sanitized
end sanitizeName

on formatDate(d)
	return do shell script "date -j -f '%A, %B %e, %Y at %I:%M:%S %p' " & quoted form of (d as string) & " '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || echo " & quoted form of (d as string)
end formatDate

-- Write the Perl helper script to a temp file (Perl is built into every macOS)
on writePerlScript()
	set pl to ""
	set pl to pl & "use strict; use warnings; use utf8;" & linefeed
	set pl to pl & "use open qw(:std :utf8);" & linefeed
	set pl to pl & "my ($html_file, $links_file, $images_file, $out_file, $title, $created, $modified) = @ARGV;" & linefeed
	set pl to pl & "open(my $fh, '<:utf8', $html_file) or die $!;" & linefeed
	set pl to pl & "local $/; my $text = <$fh>; close $fh;" & linefeed
	set pl to pl & "open($fh, '<:utf8', $links_file) or die $!;" & linefeed
	set pl to pl & "my $links = <$fh>; close $fh;" & linefeed
	set pl to pl & "$links =~ s/^\\s+|\\s+$//g if defined $links;" & linefeed
	set pl to pl & "open(my $img_fh, '<:utf8', $images_file) or die $!;" & linefeed
	set pl to pl & "my @images = grep { /\\S/ } split(/\\n/, do { local $/; <$img_fh> });" & linefeed
	set pl to pl & "close $img_fh;" & linefeed
	set pl to pl & "my $img_idx = 0;" & linefeed
	-- Headings (must run before tag-strip; nested spans handled by subsequent tag-strip)
	set pl to pl & "for my $n (1..6) { my $hashes = '#' x $n; $text =~ s{<h$n\\b[^>]*>(.*?)</h$n>}{\"\\n$hashes $1\\n\"}gsei; }" & linefeed
	-- Inline formatting
	set pl to pl & "$text =~ s{<(?:b|strong)\\b[^>]*>(.*?)</(?:b|strong)>}{**$1**}gsi;" & linefeed
	set pl to pl & "$text =~ s{<(?:i|em)\\b[^>]*>(.*?)</(?:i|em)>}{*$1*}gsi;" & linefeed
	set pl to pl & "$text =~ s{<(?:s|del|strike)\\b[^>]*>(.*?)</(?:s|del|strike)>}{~~$1~~}gsi;" & linefeed
	-- Inline images (consumed in document order from images_file)
	set pl to pl & "$text =~ s/<img[^>]*>/" & linefeed
	set pl to pl & "    $img_idx < scalar(@images) ? $images[$img_idx++] : ''" & linefeed
	set pl to pl & "/gei;" & linefeed
	-- Checklists (block-level ul.checklist detection)
	set pl to pl & "$text =~ s{<ul([^>]*)>(.*?)</ul>}{" & linefeed
	set pl to pl & "    my ($attrs, $inner) = ($1, $2);" & linefeed
	set pl to pl & "    if ($attrs =~ /\\bclass=\"[^\"]*\\bchecklist\\b/) {" & linefeed
	set pl to pl & "        $inner =~ s/<\\/li>//gi;" & linefeed
	set pl to pl & "        $inner =~ s/<li[^>]*\\bclass=\"[^\"]*\\bchecked\\b[^\"]*\"[^>]*>/- [x] /gi;" & linefeed
	set pl to pl & "        $inner =~ s/<li[^>]*data-done=\"YES\"[^>]*>/- [x] /gi;" & linefeed
	set pl to pl & "        $inner =~ s/<li[^>]*>/- [ ] /gi;" & linefeed
	set pl to pl & "        $inner;" & linefeed
	set pl to pl & "    } else {" & linefeed
	set pl to pl & "        \"<ul$attrs>$inner</ul>\";" & linefeed
	set pl to pl & "    }" & linefeed
	set pl to pl & "}gsei;" & linefeed
	set pl to pl & "$text =~ s/<li[^>]*>/- /gi;" & linefeed
	-- Existing tag-strip (unchanged)
	set pl to pl & "$text =~ s/<br\\s*\\/?>/\\n/gi;" & linefeed
	set pl to pl & "$text =~ s/<\\/(div|p|li|h[1-6])>/\\n/gi;" & linefeed
	set pl to pl & "$text =~ s/<[^>]+>//g;" & linefeed
	set pl to pl & "$text =~ s/&nbsp;/ /g;" & linefeed
	set pl to pl & "$text =~ s/&lt;/</g;" & linefeed
	set pl to pl & "$text =~ s/&gt;/>/g;" & linefeed
	set pl to pl & "$text =~ s/&amp;/&/g;" & linefeed
	set pl to pl & "$text =~ s/&quot;/\"/g;" & linefeed
	set pl to pl & "$text =~ s/&#(\\d+);/chr($1)/ge;" & linefeed
	set pl to pl & "$text =~ s/&#x([0-9a-fA-F]+);/chr(hex($1))/ge;" & linefeed
	set pl to pl & "$text =~ s/[ \\t]+$//mg;" & linefeed
	set pl to pl & "$text =~ s/^[ \\t]+$//mg;" & linefeed
	set pl to pl & "$text =~ s/\\n{3,}/\\n\\n/g;" & linefeed
	set pl to pl & "$text =~ s/^\\s+|\\s+$//g;" & linefeed
	set pl to pl & "my $body = $text;" & linefeed
	set pl to pl & "$body .= \"\\n\\n## Attachments\\n\\n$links\" if $links;" & linefeed
	set pl to pl & "my $fm = \"---\\ntitle: $title\\ncreated: $created\\nmodified: $modified\\n---\\n\\n$body\\n\";" & linefeed
	set pl to pl & "open(my $out, '>:utf8', $out_file) or die $!;" & linefeed
	set pl to pl & "print $out $fm;" & linefeed
	set pl to pl & "close $out;" & linefeed
	do shell script "printf '%s' " & quoted form of pl & " > " & quoted form of perlScript
end writePerlScript

on writeNote(theNote, folderPath)
	tell application "Notes"
		tell theNote
			set noteTitle to name
			set noteCreated to creation date
			set noteModified to modification date
			try
				set noteBody to body
			on error
				try
					set noteBody to "<p>" & plaintext & "</p>"
				on error
					set noteBody to "<p>(note body could not be retrieved)</p>"
				end try
			end try
			set attData to {}
			try
				set attList to attachments
				repeat with k from 1 to count of attList
					set att to item k of attList
					try
						set end of attData to {name of att, URL of att}
					end try
				end repeat
			end try
		end tell
	end tell
	
	set safeTitle to my sanitizeName(noteTitle)
	set noteFilePath to folderPath & safeTitle & ".md"
	
	set counter to 1
	set finalPath to noteFilePath
	repeat
		set fileExists to do shell script "[ -f " & quoted form of finalPath & " ] && echo yes || echo no"
		if fileExists is "no" then exit repeat
		set finalPath to folderPath & safeTitle & "-" & counter & ".md"
		set counter to counter + 1
	end repeat
	
	-- Export attachments
	set attachmentFolder to folderPath & safeTitle & "/"
	set attachmentLinks to ""
	set imageLinks to ""
	repeat with attItem in attData
		set attName to item 1 of attItem
		set attURL to item 2 of attItem
		try
			set attSrcPath to do shell script "perl -MURI::Escape -e 'print uri_unescape(substr($ARGV[0], 7))' " & quoted form of attURL
			set attExists to do shell script "[ -f " & quoted form of attSrcPath & " ] && echo yes || echo no"
			if attExists is "yes" then
				do shell script "mkdir -p " & quoted form of attachmentFolder
				set attDest to attachmentFolder & attName
				set attCounter to 1
				repeat
					set attDestExists to do shell script "[ -f " & quoted form of attDest & " ] && echo yes || echo no"
					if attDestExists is "no" then exit repeat
					set attDest to attachmentFolder & attCounter & "-" & attName
					set attCounter to attCounter + 1
				end repeat
				do shell script "cp " & quoted form of attSrcPath & " " & quoted form of attDest
				set relName to do shell script "basename " & quoted form of attDest
				set attExt to do shell script "echo " & quoted form of relName & " | sed 's/.*\\.//'"
				if attExt is in {"jpg", "jpeg", "png", "gif", "webp", "heic", "svg"} then
					set attachmentLinks to attachmentLinks & "![" & relName & "](" & safeTitle & "/" & relName & ")" & linefeed
					set imageLinks to imageLinks & "![" & relName & "](" & safeTitle & "/" & relName & ")" & linefeed
				else
					set attachmentLinks to attachmentLinks & "[" & relName & "](" & safeTitle & "/" & relName & ")" & linefeed
				end if
			end if
		end try
	end repeat
	
	set createdStr to my formatDate(noteCreated)
	set modifiedStr to my formatDate(noteModified)
	
	set tmpHtml to "/tmp/apple_notes_export_tmp.html"
	set tmpLinks to "/tmp/apple_notes_links_tmp.txt"
	set tmpImages to "/tmp/apple_notes_images_tmp.txt"
	do shell script "printf '%s' " & quoted form of noteBody & " > " & quoted form of tmpHtml
	do shell script "printf '%s' " & quoted form of attachmentLinks & " > " & quoted form of tmpLinks
	do shell script "printf '%s' " & quoted form of imageLinks & " > " & quoted form of tmpImages

	do shell script "perl " & quoted form of perlScript & " " & quoted form of tmpHtml & " " & quoted form of tmpLinks & " " & quoted form of tmpImages & " " & quoted form of finalPath & " " & quoted form of noteTitle & " " & quoted form of createdStr & " " & quoted form of modifiedStr
end writeNote

tell application "Notes"
	set noteCount to 0
	set folderCount to 0
	set skippedCount to 0
	
	do shell script "mkdir -p " & quoted form of exportRoot
	do shell script "rm -f " & quoted form of (exportRoot & "export-errors.log")
	writePerlScript() of me
	
	-- Count total notes first so progress bar has an accurate total
	tell me to set progress description to "Counting notes..."
	tell me to set progress additional description to ""
	set totalNotes to 0
	repeat with acct in accounts
		set fldrList to folders of acct
		repeat with i from 1 to count of fldrList
			set totalNotes to totalNotes + (count of notes of item i of fldrList)
		end repeat
	end repeat
	
	tell me to set progress total steps to totalNotes
	tell me to set progress completed steps to 0
	tell me to set progress description to "Exporting " & totalNotes & " notes..."
	
	repeat with acct in accounts
		set acctName to name of acct
		set safeAcct to my sanitizeName(acctName)
		
		set fldrList to folders of acct
		repeat with i from 1 to count of fldrList
			set fldr to item i of fldrList
			set fldrName to name of fldr
			set safeFldr to my sanitizeName(fldrName)
			
			set folderPath to exportRoot & safeAcct & "/" & safeFldr & "/"
			do shell script "mkdir -p " & quoted form of folderPath
			set folderCount to folderCount + 1
			
			set noteList to notes of fldr
			repeat with j from 1 to count of noteList
				set n to item j of noteList
				try
					set currentTitle to name of n
					tell me to set progress additional description to currentTitle & " (" & (noteCount + skippedCount + 1) & " of " & totalNotes & ")"
					my writeNote(n, folderPath)
					set noteCount to noteCount + 1
				on error errMsg
					set skippedCount to skippedCount + 1
					try
						set noteName to name of n
					on error
						set noteName to "unknown"
					end try
					do shell script "echo " & quoted form of ("Skipped: " & noteName & " - " & errMsg) & " >> " & quoted form of (exportRoot & "export-errors.log")
				end try
				tell me to set progress completed steps to noteCount + skippedCount
			end repeat
		end repeat
	end repeat
	
	set summary to "Export complete!" & return & return & "Notes exported: " & noteCount & return & "Folders created: " & folderCount & return & "Skipped (errors): " & skippedCount & return & return & "Location: " & exportRoot
	if skippedCount > 0 then
		set summary to summary & return & "(See export-errors.log for details)"
	end if
	set dialogResult to display dialog summary buttons {"Open Folder", "OK"} default button "OK"
	if button returned of dialogResult is "Open Folder" then
		do shell script "open " & quoted form of exportRoot
	end if
end tell
