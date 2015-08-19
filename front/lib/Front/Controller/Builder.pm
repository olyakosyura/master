package Front::Controller::Builder;
use Mojo::Base 'Mojolicious::Controller';

use AccessDispatcher qw( send_request );
use MainConfig qw( DATA_PORT );

sub index {
    my $self = shift;
    $self->app->log->debug("HELLLLLOOOOO!!!!");
    $self->render(template => 'base/index');
}

sub login {
    my $self = shift;
    $self->app->log->debug($self->render(template => 'base/login'));
}

1;
