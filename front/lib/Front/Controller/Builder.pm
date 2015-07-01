package Front::Controller::Builder;
use Mojo::Base 'Mojolicious::Controller';

use AccessDispatcher qw( send_request );
use MainConfig qw( DATA_PORT );

sub index {
    my $self = shift;

    my $r = send_request($self,
        url => 'districts',
        port => DATA_PORT,
    );
    return $self->render(template => 'base/internal_err') unless $r;

    my $c = send_request($self,
        url => 'calc_types',
        port => DATA_PORT,
    );
    return $self->render(template => 'base/internal_err') unless $c;

    $self->stash(calc_types => $c);
    $self->stash(districts => $r);
    $self->render(template => 'base/index');
}

sub report_v2 {
    my $self = shift;

    my $r = send_request($self,
        url => 'districts',
        port => DATA_PORT,
    );
    return $self->render(template => 'base/internal_err') unless $r;

    my $c = send_request($self,
        url => 'calc_types',
        port => DATA_PORT,
    );
    return $self->render(template => 'base/internal_err') unless $c;

    $self->stash(calc_types => $c);
    $self->stash(districts => $r);
    $self->render(template => 'base/index_2');
}

sub objects {
    my $self = shift;

    my $r = send_request($self,
        url => 'districts',
        port => DATA_PORT,
    );
    return $self->render(template => 'base/internal_err') unless $r;

    $self->stash(districts => $r);
    $self->render(template => 'base/objects');
}

sub users {
    my $self = shift;

    my $r = send_request($self,
        url => 'users_list',
        port => DATA_PORT,
    );
    return $self->render(template => 'base/internal_err') unless $r;

    $self->stash(users => $r->{users} || []);
    return $self->render(template => 'base/users');
}

sub maps {
    my $self = shift;

    my $r = send_request($self,
        url => 'districts',
        port => DATA_PORT,
    );
    return $self->render(template => 'base/internal_err') unless $r;
    $self->stash(districts => $r);

    $r = send_request($self,
        url => 'companies',
        port => DATA_PORT,
        args => {
            region => 'Москва',
        }
    );
    return $self->render(template => 'base/internal_err') unless $r && $r->{companies};
    $self->stash(companies => $r->{companies});

    $r = send_request($self,
        url => 'geolocation/objects',
        port => DATA_PORT,
    );
    return $self->render(template => 'base/internal_err') unless $r;

    # Following crazy code is really needed because buildings characteristics in DB
    # have cyrillic characters, which are different from perl utf-8 cyrillic chars =(
    # Just close your eyes and cry...
    my %characteristics;
    my @_colors = qw( #33CCCC #66CC66 #9933CC #FF9999 #FFCC33 #CC6699 #9999FF #CC99FF );
    for (@$r) {
        $characteristics{$_->{characteristic}} = 1;
    }

    my %colors;
    my $i = 0;
    for (sort keys %characteristics) {
        $colors{$_} = $_colors[$i++] || '#000000';
    }
    $colors{unknown} = '#336600';

    $self->stash(geoobjects => [ map {
        my $o = $_;
        $o ? {
            (map { $_ => $o->{$_} } qw( name coordinates id )),
            color => $colors{$o->{characteristic} || 'unknown'},
        } : {}
    } @$r ]);

    return $self->render(template => 'base/maps');
}

sub start_geolocation {
    my $self = shift;

    my $r = send_request($self,
        url => 'geolocation/start',
        port => DATA_PORT,
    );

    return $self->render(template => 'base/internal_err') unless $r && ($r->{status} || "") eq '200';

    $self->stash(db_data => $r->{objects});
    $self->stash(req_id => $r->{req_id});
    return $self->render(template => 'base/coordinates');
}

sub geolocation_status {
    my $self = shift;

    my $r = send_request($self,
        url => 'geolocation/status',
        port => DATA_PORT,
        args => {
            req_id => $self->param('req_id') || -1,
            last_id => $self->param('last_id') || 0,
        },
    );

    return $self->render(template => 'base/internal_err') unless $r && ($r->{status} || '') eq '200';
    return $self->render(json => $r);
}

sub save_geolocation_changes {
    my $self = shift;
    my $args = $self->req->text;

    my $r = send_request($self,
        url => 'geolocation/save',
        port => DATA_PORT,
        method => 'POST',
        data => $args,
    );

    return $self->render(template => 'base/internal_err') unless $r && ($r->{status} || '') eq '200';
    return $self->render(json => $r);
}

1;
