#!/usr/bin/perl -w

#
# Perl routine to convert a .jpz crossword to an .ipuz crossword.
# 2011 Alex Boisvert
# Usage: jpz2ipuz.pl file.jpz
# ipuz is a trademark of Puzzazz, Inc., used with permission

# TODO:
# 1. There are probably a lot of bugs here.  List them!

# use strict;

use XML::Simple;
{ # Ugly fix to make it work with pp
	no strict 'refs';
	*{"XML::SAX::"}{HASH}{parsers} = sub {
		return [ {
			'Features' => {
				'http://xml.org/sax/features/namespaces/' => '1'
			},
			'Name' => 'XML::SAX::PurePerl'
		}
		]
	};
}
use XML::SAX::PurePerl;
use IO::Uncompress::Unzip qw(unzip $UnzipError) ;
use Encode;
use JSON;

my $name;
unless ($ARGV[0]) {die "Usage: $0 <foo.xml> or $0 <foo.jpz>";}
else {$name = $ARGV[0];}

my %puz_hash = parse_jpz($name);
$puz_hash{'origin'} = "jpz2ipuz";
$puz_hash{'kind'} = ["http://ipuz.org/acrostic#1"];
$puz_hash{'empty'} = "0";
$puz_hash{'version'} = "http://ipuz.org/v1";

$name =~ s/\.[^\.]*$/\.ipuz/;

my $data = to_json(\%puz_hash);
$data = "ipuz(\n$data)";

open OUT, ">$name" or die "Can't write to $name";
binmode OUT;
print OUT $data;
close OUT;

##
# SUBS
##

sub parse_jpz
{
	my $name = shift;
	
	# read in the .jpz file
	my $data1;
	open IN, $name or die "Can't read $name";
	{
		local $/;
		$data1 = <IN>;
	}
	close IN;

	my $z;

	# Unzip the data if it's zipped
	unless ($data1 =~ /crossword-compiler/) {
		my $status = unzip $name => \$z or die "unzip failed! $UnzipError\n";
		$data1 = $z;
	}

	# Convert everything to UTF
	$data1 = decode("iso-8859-1",$data1);
	
	# What we do need to decode (for some reason) is &nbsp;
	$data1 =~ s/\&nbsp\;/ /g;
	
	# Sometimes .jpz files have lots and lots of spaces.  Shrink them down.
	$data1 =~ s/\s+/ /g;

	my $xs = XML::Simple->new(NumericEscape=>2);
	my $xml = $xs->XMLin($data1);
	
	my %puzzle_data;

	$puzzle_data{'title'} = $xml->{'rectangular-puzzle'}->{'metadata'}->{'title'};
	$puzzle_data{'author'} = $xml->{'rectangular-puzzle'}->{'metadata'}->{'creator'};
	$puzzle_data{'copyright'} = $xml->{'rectangular-puzzle'}->{'metadata'}->{'copyright'};
	# Get rid of the annoying copyright symbol
	my $cpr = chr(65533);
	my $cpr2 = chr(169);
	$puzzle_data{'copyright'} =~ s/[$cpr$cpr2]/(c)/;
	$puzzle_data{'notes'} = $xml->{'rectangular-puzzle'}->{'instructions'};

	my $gridinfo = $xml->{'rectangular-puzzle'}->{'acrostic'}->{'grid'};
	my $w = $gridinfo->{'width'} || 1;
	my $h = $gridinfo->{'height'} || 1;
	$puzzle_data{'dimensions'} = { 'width' => int($w), 'height' => int($h)};

	my $cells = $gridinfo->{'cell'};
	foreach my $cell (@$cells) {
		my $r = $cell->{'y'} - 1;
		my $c = $cell->{'x'} - 1;
		if ($cell->{'type'}) {
			if ($cell->{'type'} eq 'block') {
				$puzzle_data{'puzzle'}[$r][$c] = '#';
				$puzzle_data{'solution'}[$r][$c] = '#';
			}
		}
		else {
			# Check for circles
			if ($cell->{'background-shape'}) {
				if ($cell->{'background-shape'} eq 'circle') {
					my %circle_hash;
					$circle_hash{'shapebg'} = 'circle';
					$puzzle_data{'puzzle'}[$r][$c]{'style'} = {%circle_hash};
					# Check for number
					if ($cell->{'number'}) {
						$puzzle_data{'puzzle'}[$r][$c]{'cell'} = int($cell->{'number'});
					}
					else {
						$puzzle_data{'puzzle'}[$r][$c]{'cell'} = 0;
					}
				}
			}
			else { # No circle
				if ($cell->{'number'}) {
					$puzzle_data{'puzzle'}[$r][$c] = int($cell->{'number'});
				}
				else {$puzzle_data{'puzzle'}[$r][$c] = 0;}
			}
			
			# Check the cell solution
			$puzzle_data{'solution'}[$r][$c] = $cell->{'solution'};
		} # end else
	} # end foreach @$cells

	my %words;
    foreach my $word (@{ $xml->{'rectangular-puzzle'}->{'acrostic'}->{'words'}->{'word'} }) {
        $words{ $word->{'id'} } = $word;
		print "$word\n";
    }

	my $clues = $xml->{'rectangular-puzzle'}->{'acrostic'}->{'clues'};

	foreach my $clue (@{$clues->{'clue'}}){
		my $label = $clue->{'number'};
		my $clue_text = $clue->{'content'};
		
		my @cells;
		if (exists $clue->{'word'} && exists $clue->{'word'}->{'id'}) {
            my $word_id = $clue->{'word'}->{'id'};
            if (exists $words{$word_id}) {
                my $word_cells = $words{$word_id}->{'cells'};
                if (ref($word_cells) eq 'ARRAY') {
                    foreach my $cell (@$word_cells) {
                        push @cells, [$cell->{'x'}, $cell->{'y'}];
                    }
                } else {
					# print "X : $word_cells->{'x'} "
                    push (@cells, [$word_cells->{'x'}, $word_cells->{'y'}]);
                }
            }
        }

		push (@{$puzzle_data{'clues'}->{'Clues'}},{
			'label'=> $label,
			'clue' => $clue_text,
			'cells' => \@cells, 
		});
	}
	
	return %puzzle_data;
}
