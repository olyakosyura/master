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

    my $c = send_request($self,
        url => 'calc_types',
        port => DATA_PORT,
    );

    $self->stash(calc_types => $c);
    $self->stash(districts => $r);
    $self->render(template => 'base/index');
}

1;
