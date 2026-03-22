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

    # Checklists — block-level ul detection
    $text =~ s{<ul([^>]*)>(.*?)</ul>}{
        my ($attrs, $inner) = ($1, $2);
        if ($attrs =~ /\bclass="[^"]*\bchecklist\b/) {
            $inner =~ s/<li[^>]*\bclass="[^"]*\bchecked\b[^"]*"[^>]*>/- [x] /gi;
            $inner =~ s/<li[^>]*data-done="YES"[^>]*>/- [x] /gi;
            $inner =~ s/<li[^>]*>/- [ ] /gi;
            $inner =~ s/<\/li>//gi;
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

exit $failures > 0 ? 1 : 0;
