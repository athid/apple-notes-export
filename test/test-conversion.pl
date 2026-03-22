#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use open qw(:std :utf8);
use MIME::Base64;

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

my $TMPDIR = "/tmp/test_apple_notes_$$";
system('mkdir', '-p', $TMPDIR);

# Returns (converted_text, @inline_image_links)
sub convert {
    my ($text, $att_folder, $safe_title) = @_;
    $att_folder //= $TMPDIR;
    $safe_title //= 'TestNote';
    my $img_counter = 0;
    my @inline_image_links;

    # === NEW CONVERSIONS (applied before tag-strip) ===
    # Headings
    for my $n (1..6) {
        my $hashes = '#' x $n;
        $text =~ s{<h$n[^>]*>(.*?)</h$n>}{"\n$hashes $1\n"}gsei;
    }

    # Inline formatting
    $text =~ s{<(?:b|strong)\b[^>]*>(.*?)</(?:b|strong)>}{**$1**}gsi;
    $text =~ s{<(?:i|em)\b[^>]*>(.*?)</(?:i|em)>}{*$1*}gsi;
    $text =~ s{<(?:s|del|strike)\b[^>]*>(.*?)</(?:s|del|strike)>}{~~$1~~}gsi;

    # Inline images: extract base64 data URIs, decode to files
    $text =~ s{<img\b[^>]*\bsrc="data:image/([^;]+);base64,([^"]+)"[^>]*>}{
        $img_counter++;
        my $ext = lc($1); $ext =~ s/jpeg/jpg/;
        my $fname = 'image-' . $img_counter . '.' . $ext;
        my $dest = $att_folder . '/' . $fname;
        unless (-d $att_folder) { system('mkdir', '-p', $att_folder); }
        open(my $bin_fh, '>:raw', $dest) or warn 'Cannot write ' . $dest . "\n";
        print $bin_fh decode_base64($2); close $bin_fh;
        my $md = '![' . $fname . '](' . $safe_title . '/' . $fname . ')';
        push @inline_image_links, $md;
        $md;
    }gsei;
    # Drop any remaining img tags (no data URI src)
    $text =~ s/<img[^>]*>//gi;

    # Checklists — block-level ul detection
    $text =~ s{<ul([^>]*)>(.*?)</ul>}{
        my ($attrs, $inner) = ($1, $2);
        if ($attrs =~ /\bclass="[^"]*\bchecklist\b/) {
            $inner =~ s/<\/li>//gi;
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

    return wantarray ? ($text, @inline_image_links) : $text;
}

# Minimal 1x1 white PNG in base64 (a real PNG file, 68 bytes decoded)
my $PNG_B64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
# Minimal 1x1 JPEG in base64
my $JPEG_B64 = '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/xAAUAQEAAAAAAAAAAAAAAAAAAAAA/8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAwDAQACEQMRAD8AJQAB/9k=';

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

# --- Inline image tests (data URI approach) ---
my $imgdir = "$TMPDIR/img_test";

# Single PNG image inline
my ($result, @links) = convert(
    "<p>See <img src=\"data:image/png;base64,$PNG_B64\"> below</p>",
    $imgdir, 'MyNote'
);
ok($result, 'See ![image-1.png](MyNote/image-1.png) below', 'single inline image replaced in text');
ok(scalar(@links), 1, 'single image produces one inline_image_link');
ok($links[0], '![image-1.png](MyNote/image-1.png)', 'inline_image_link value correct');
ok(-f "$imgdir/image-1.png" ? 'yes' : 'no', 'yes', 'PNG file written to disk');

# JPEG extension normalised to jpg
system('rm', '-rf', $imgdir);
($result) = convert(
    "<img src=\"data:image/jpeg;base64,$JPEG_B64\">",
    $imgdir, 'MyNote'
);
ok($result, '![image-1.jpg](MyNote/image-1.jpg)', 'jpeg MIME type normalised to .jpg');
ok(-f "$imgdir/image-1.jpg" ? 'yes' : 'no', 'yes', 'JPEG file written to disk');

# HEIC extension preserved
system('rm', '-rf', $imgdir);
($result) = convert(
    "<img src=\"data:image/heic;base64,$PNG_B64\">",
    $imgdir, 'MyNote'
);
ok($result, '![image-1.heic](MyNote/image-1.heic)', 'heic MIME type preserved');

# Two images in order
system('rm', '-rf', $imgdir);
($result) = convert(
    "<img src=\"data:image/png;base64,$PNG_B64\"><img src=\"data:image/png;base64,$PNG_B64\">",
    $imgdir, 'MyNote'
);
ok($result, '![image-1.png](MyNote/image-1.png)![image-2.png](MyNote/image-2.png)', 'two images numbered in order');

# Non-data-URI img tags are dropped silently
($result) = convert('<img src="x-coredata://abc">plain text');
ok($result, 'plain text', 'non-data-URI img tag dropped');

# Clean up
system('rm', '-rf', $TMPDIR);

exit $failures > 0 ? 1 : 0;
