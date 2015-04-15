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
        return $self->redirect_to(GENERAL_URL . '/login') && undef if $res->{error};

        $self->stash(%$res); # login name lastname role uid email objects_count
        return 1;
    });

    $self->routes->get('/login')->to(cb => sub {
        my $self = shift;
        $self->stash(general_url => GENERAL_URL);
        $self->render(template => 'base/login');
    });

    $auth->get('/')->to(cb => sub { shift->render(template => 'base/index'); });
    $auth->get('/upload')->to(cb => sub { shift->render(template => 'base/upload'); });
}

1;
