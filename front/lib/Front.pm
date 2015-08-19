package Front;
use Mojo::Base 'Mojolicious';

use AccessDispatcher qw( send_request role_less_then );
use MainConfig qw( FILES_HOST GENERAL_URL SESSION_PORT );

my %access_rules = (
    '/'          => 'user',
    '/report_v2' => 'user',
    '/login'     => 'user',
    '/upload'    => 'admin',
    '/objects'   => 'manager',
    '/users'     => 'admin',
    '/maps'      => 'user',
    '/geolocation'          => 'admin',
    '/404.html'  => 'user',
);

# This method will run once at server start
sub startup {
    my $self = shift;

    # Documentation browser under "/perldoc"
    $self->plugin('PODRenderer');
    $self->secrets([qw( 0i+hE8eWI0pG4DOH55Kt2TSV/CJnXD+gF90wy6O0U0k= )]);

    my $any = $self->routes->under('/' => sub {
        my $self = shift;
        my $url = $self->req->url;
        $url =~ s#^(/[^?]*)#$1#;
        $self->stash(url => $url);
        $self->app->log->info($url);
    });

    my $auth = $any->under('/' => sub {
        my $self = shift;
        my $r = $self->req;

        my $res = send_request($self,
            method => 'get',
            url => 'about',
            port => SESSION_PORT,
            args => {
                user_agent => $self->req->headers->user_agent,
                session_id => $self->signed_cookie('session'),
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

        $self->stash(general_url => GENERAL_URL);
        $self->stash(files_url => FILES_HOST);
        $self->stash(%$res); # login name lastname role uid email objects_count

        if (!role_less_then $res->{role}, $access_rules{$url} || 'admin') {
            $self->app->log->warn("Access to $url ($access_rules{$url} is needed) denied for $res->{login} ($res->{role})");
            $self->render(template => 'base/not_found');
            return undef;
        }

        return 1;
    });

    $any->get('/')->to("builder#index");
    $any->get('/orders')->to("builder#orders");
    $any->get('/login')->to("builder#login");
    $auth->get('/track')->to("builder#track");
=cut
    $any->any('/*any' => { any => '' } => sub {
        my $self = shift;
        if ($self->param('any') ne 'login') {
            $self->render(template => 'base/not_found');
        }
        $self->app->log->info("TES2T");
    });
=cut
}

1;
