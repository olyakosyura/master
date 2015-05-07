package Translation;

use strict;
use warnings;

use Carp qw(croak);
use Cwd 'abs_path';
use base qw(Exporter);

my $path = abs_path($0);
$path =~ s#/\w*$##;
$path .= '/../../translation';

open my $file, '<:encoding(utf-8)', $path or die "Can't open translation file";

my %translation = ();

sub make_sub {
    my ($sub_name) = @_;
    local $@;
    eval <<SUB;
        sub $sub_name() {
            croak "Can't locate $sub_name in translation\\n" unless defined(\$translation{$sub_name});
            return \$translation{$sub_name};
        }
SUB
    croak "Can't make subs: $@\n" if $@;
}

while (<$file>) {
    next unless /^(\w+)\s*=\s*(.*)\s*(?:#.*)?$/;
    $translation{$1} = $2;
    make_sub $1;
}

our @EXPORT_OK = keys %translation;
our %EXPORT_TAGS = ( all => [@EXPORT_OK], );

1;
