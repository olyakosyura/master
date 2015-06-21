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
    return $self->render(template => 'base/maps');
}

1;
