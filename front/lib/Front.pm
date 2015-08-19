package Front;
use Mojo::Base 'Mojolicious';

use AccessDispatcher qw( send_request role_less_then _session);
use MainConfig qw( FILES_HOST GENERAL_URL SESSION_PORT );

my %access_rules = (
    '/'          => 'user',
    '/login'     => 'user',
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
        $self->stash(general_url => GENERAL_URL, url => $url);

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

        use Data::Dumper;
        $self->app->log->debug(Dumper $res);

        my %data = (
            login => '',
            name => '',
            lastname => '',
            role => '',
            uid => '',
            email => '',
        );

        if ($res->{error}) {
            _session($self, {expires => 1});
            $self->stash(logged_in => 0);
        } else {
            %data = (%data, %$res);
            $self->stash(logged_in => 1);
        }

        $self->stash(%data);

        return 1;
    });

    my $auth = $any->under('/' => sub {
        my $self = shift;
        my $r = $self->req;

        my $url = $r->url;
        $url =~ s#^(/[^?]*)#$1#;

=cut
        if (defined $res->{status}) {
            return $self->render(template => 'base/login') && undef if $res->{status} == 401;
            return $self->render(status => $res->{status}) && undef;
        }

        unless ($self->stash('logged_in')) {
            return $self->redirect_to(GENERAL_URL . '/login') && undef if $res->{error};
        }

        if (!role_less_then $self->stash('role'), $access_rules{$url} || 'admin') {
            $self->app->log->warn("Access to $url ($access_rules{$url} is needed) denied for $res->{login} ($res->{role})");
            $self->render(status => 404);
            return undef;
        }
=cut

        return 1;
    });

    $any->get('/')->to("builder#index");
    $any->get('/orders')->to("builder#orders");
    $any->get('/login')->to("builder#login");
    $auth->get('/track')->to("builder#track");

    $any->any('/*any' => { any => '' } => sub {
        my $self = shift;
        if ($self->param('any') ne 'login') {
            $self->render(status => 404);
        }
        $self->app->log->info("TES2T");
    });
}

1;
