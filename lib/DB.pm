package DB;

use strict;
use warnings;

use DBI;
use Carp;

use MainConfig qw( :all );

use base qw(Exporter);

our @EXPORT_OK = qw(
    select_row
    select_all
    execute_query
    last_err
    last_id
);

our %EXPORT_TAGS = (
    all => [@EXPORT_OK],
);

my $dbh;

BEGIN {
    $dbh = DBI->connect(
        'dbi:mysql:database=' . DB_NAME . ':host=' . DB_HOST . ':port=' . DB_PORT,
        DB_USER, DB_PASS,
        {
            AutoCommit => 1,
            RaiseError => 1,
            mysql_enable_utf8 => 1,
        }
    ) or croak "Can't connect to '" . DB_NAME . "' database: " . DBI::errstr();
}

sub last_err {
    my $ctl = shift;
    return $dbh->errstr;
}

sub select_row {
    my ($ctl, $query, @args) = @_;

    $ctl->app->log->debug(sprintf "SQL query: '%s'. [args: %s]", $query, join(',', @args));
    my $sth = $dbh->prepare($query);
    $sth->execute(@args) or return $ctl->app->log->warn($dbh->errstr) and undef;

    return $sth->fetchrow_hashref();
}

sub select_all {
    my ($ctl, $query, @args) = @_;
    $ctl->app->log->debug(sprintf "SQL query: '%s'. [args: %s]", $query, join(',', @args));
    return $dbh->selectall_arrayref($query, { Slice => {} }, @args) or ($ctl->app->log->warn($dbh->errstr) and undef);
}

sub execute_query {
    my ($ctl, $query, @args) = @_;
    $ctl->app->log->debug(sprintf "SQL query: '%s'. [args: %s]", $query, join(',', map { defined $_ ? $_ : "undef" } @args));
    return $dbh->do($query, undef, @args) or ($ctl->app->log->warn($dbh->errstr) and undef);
}

sub last_id {
    my $ctl = shift;
    my $row = select_row $ctl, 'select last_insert_id() as id';
    return $row && $row->{id};
}

1;
