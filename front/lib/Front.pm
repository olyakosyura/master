package Front;
use Mojo::Base 'Mojolicious';

use AccessDispatcher qw( send_request );
use MainConfig qw( GENERAL_URL SESSION_PORT );

# This method will run once at server start
sub startup {
    my $self = shift;

    # Documentation browser under "/perldoc"
    $self->plugin('PODRenderer');
    $self->secrets([qw( 0i+hE8eWI0pG4DOH55Kt2TSV/CJnXD+gF90wy6O0U0k= )]);

    my $auth = $self->routes->under('/' => sub {
        my $self = shift;
        my $r = $self->req;

        my $res = send_request($self,
            method => 'get',
            url => 'about',
            port => SESSION_PORT,
            args => {
                user_agent => $self->req->headers->user_agent,
                session_id => $self->session('session'),
            },
        );
        return $self->render(status => 500) unless $res;

        if (defined $res->{status}) {
            return $self->render(template => 'base/login') && undef if $res->{status} == 401;
            return $self->render(status => $res->{status}) && undef;
        }

        $self->stash(general_url => GENERAL_URL);
        return $self->render(template => 'base/login') && undef if $res->{error};

        $self->stash(%$res); # login name lastname role uid email
        return 1;
    });

    $auth->get('/')->to("builder#index");
    $auth->get('/upload')->to("builder#upload");
}

1;
