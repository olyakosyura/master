package Front::Controller::Builder;
use Mojo::Base 'Mojolicious::Controller';

use AccessDispatcher qw( send_request );
use MainConfig qw( :all );

sub index {
    my $self = shift;
    $self->render(template => 'base/index');
    return 1;
}

sub login {
    my $self = shift;

    my $res = send_request($self,
        method => 'get',
        url => 'about',
        port => SESSION_PORT,
        args => {
            user_agent => $self->req->headers->user_agent,
            session_id => $self->signed_cookie('session'),
        },
    );

    if ($res and $res->{status} and $res->{status} == 200) {
        return $self->redirect_to(GENERAL_URL);
    }

    return $self->render(template => 'base/login');
}

1;
