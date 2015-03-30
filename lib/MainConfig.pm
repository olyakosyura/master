package MainConfig;

use strict;
use warnings;

use Carp qw(croak);

use Cwd 'abs_path';
use base qw(Exporter);

my %PARAMS = (
    # undef params are required
    FRONT_PORT      => 6000,
    DATA_PORT       => 6001,
    SESSION_PORT    => 6002,

    DB_HOST         => 'localhost',
    DB_PORT         => 3306,
    DB_NAME         => undef,
    DB_USER         => undef,
    DB_PASS         => undef,

    MEMC_HOST       => 'localhost',
    MEMC_PORT       => 11211,
);

our @EXPORT_OK = keys %PARAMS;
our %EXPORT_TAGS = ( all => [@EXPORT_OK], );

my $path = abs_path($0);
$path =~ s#/\w*$##;
$path .= '/../../config';

my %CFG;

open my $f, '<', $path or croak "Can't open $path: $!\n";
while (<$f>) {
    /(\w*)\s*=\s*(.*)/;
    $CFG{$1} = $2;
}

close $f;

sub make_sub {
    my ($sub_name) = @_;
    local $@;
    eval "sub $sub_name() { return \$CFG{$sub_name} || \$PARAMS{$sub_name} || croak \"Can't locate $sub_name in config\\n\"; }";
    croak "Can't make subs: $@\n" if $@;
}

for (keys %PARAMS) {
    croak "$_ config param is required\n" if !defined $PARAMS{$_} && !defined $CFG{$_};
    make_sub $_;
}

1;
