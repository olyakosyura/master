package Front;
use Mojo::Base 'Mojolicious';

use AccessDispatcher qw( send_request role_less_then );
use MainConfig qw( GENERAL_URL SESSION_PORT );

my %access_rules = (
    '/'          => 'user',
    '/report_v2' => 'user',
    '/login'     => 'user',
    '/upload'    => 'admin',
    '/objects'   => 'manager',
    '/users'     => 'admin',
    '/maps'      => 'user',

    '/geolocation'          => 'admin',
    '/geolocation/status'   => 'admin',
    '/geolocation/save'     => 'admin',
);

# This method will run once at server start
sub startup {
    my $self = shift;

    # Documentation browser under "/perldoc"
    $self->plugin('PODRenderer');
    $self->secrets([qw( 0i+hE8eWI0pG4DOH55Kt2TSV/CJnXD+gF90wy6O0U0k= )]);

    $self->routes->get('/login')->to(cb => sub {
        my $self = shift;
        $self->stash(general_url => GENERAL_URL);
        $self->render(template => 'base/login');
    });

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

        my $url = $r->url;
        $url =~ s#^(/[^?]*)#$1#;

        if (defined $res->{status}) {
            return $self->render(template => 'base/login') && undef if $res->{status} == 401;
            return $self->render(status => $res->{status}) && undef;
        }

        return $self->redirect_to(GENERAL_URL . '/login') && undef if $res->{error};

        $self->stash(general_url => GENERAL_URL, url => $url);
        $self->stash(%$res); # login name lastname role uid email objects_count

        if (!role_less_then $res->{role}, $access_rules{$url} || 'admin') {
            $self->app->log->warn("Access to $url ($access_rules{$url} is needed) denied for $res->{login} ($res->{role})");
            $self->render(template => 'base/not_found');
            return undef;
        }

        return 1;
    });

    $auth->get('/')->to("builder#index");
    $auth->get('/objects')->to("builder#objects");
    $auth->get('/users')->to("builder#users");
    $auth->get('/upload')->to(cb => sub { shift->render(template => 'base/upload'); });
    $auth->get('/report_v2')->to("builder#report_v2");
    $auth->get('/maps')->to("builder#maps");
    $auth->get('/geolocation')->to("builder#start_geolocation");
    $auth->get('/geolocation/status')->to("builder#geolocation_status");
    $auth->post('/geolocation/save')->to("builder#save_geolocation_changes");

    $auth->any('/*any' => { any => '' } => sub {
        my $self = shift;
        if ($self->param('any') ne 'login') {
            $self->render(template => 'base/not_found');
        }
    });
}

1;
