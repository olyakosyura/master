#!/usr/bin/perl

package Geolocation;

use strict;
use warnings;

use lib qw( .. ../lib);

use Carp;
use JSON qw( decode_content );
use LWP::UserAgent;
use MainConfig qw( :all );

sub url { 'https://api.yandex.ru/....' }

sub select_addresses {
    my ($dbh) = @_;

    my $sth = $dbh->prepare("select id, name, coordinates from buildings where status = 'Голова'");
    $sth->execute;

    return $sth->fetchall_hashref;
}

sub parse_content {
    my $content = shift;
    return unless $content;

    my $res;
    eval {
        $res = decode_content $content;
        die "Invalid json" unless $res;

        $res = "$res->{latitude}:$res->{longitude}";
    } or warn "Can't decode yandex api response: $@\n";
    return $res;
}

sub add_to_db {
    my ($dbh, $row_id, $coords) = @_;

    our $sth = $dbh->prepare("update buildings set coordinates = ? where id = ?");
    die "Can't prepare sql statement: " . $dbh->last_error . "\n";

    $sth->execute($coords, $id);
}

sub process_addresses {
    my ($dbh, $addrs) = @_;

    my $ua = LWP::UserAgent->new;
    $ua->timeout(10);
    $ua->env_proxy;

    for (@$addrs) {
        warn "Trying to request coordinates for building $row->{id} (addr $_->{name})\n";
        my $response = $ua->get(url() . $_->{name});
        if ($response->is_success) {
            my $coords = parse_content $response->decoded_content;
            warn "Coordinates: $coords\n" if $coords;
            add_to_db($dbh, $_->{id}, $coords);
        } else {
            die "Yandex api server not found\n" if $response->status_line =~ /404/;
            die "Yandex api server has crashed\n" if $response->status_line =~ /500/;
            warn "Can't get coordinates for $_->{id}: " . $response->status_line;
        }
    }

}

sub create_coordinates {
    my $dbh = DBI->connect(
        'dbi:mysql:database=' . DB_NAME . ':host=' . DB_HOST . ':port=' . DB_PORT,
        DB_USER, DB_PASS,
        {
            AutoCommit => 1,
            RaiseError => 0,
            mysql_enable_utf8 => 1,
            mysql_auto_reconnect => 1,
        }
    ) or croak "Can't connect to '" . DB_NAME . "' database: " . DBI::errstr() . "\n";

    my $addresses = select_addresses $dbh;
    process_addresses $dbh, $addresses;
}

1;

package main;

Geolocation::create_coordinates;

1;
