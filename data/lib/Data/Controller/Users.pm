package Data::Controller::Users;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw( encode_json );

use MainConfig qw( :all );
use AccessDispatcher qw( send_request check_access );

use Data::Dumper;

use DB qw( :all );

sub check_params {
    my $self = shift;

    my %params;
    my $p = $self->req->params->to_hash;
    for (@_) {
        $params{$_} = $p->{$_};
        return $self->render(status => 400, json => { error => sprintf "%s field is required", ucfirst }) && undef unless $params{$_};
    }

    return \%params;
}

sub _i_err {
    my $self = shift;
    return $self->render(status => 500, json => { error => 'internal' });
}

sub add {
    my $self = shift;

    my $params = check_params $self, qw( login password name lastname email role );
    return unless $params;

    my $r = select_all($self, "select id, name from roles");
    my $role_id;

    return $self->render(status => 400, json => { error => "invalid", description => "invalid email" })
        unless $params->{email} =~ /^[^@]+@[^@]+$/;

    return $self->render(status => 400, json => { error => "invalid", description => "invalid role" })
        unless grep { $_->{name} eq $params->{role} && (($role_id = $_->{id}) || 1) } @$r;

    $r = select_row($self, "select id from users where login = ?", $params->{login});
    return $self->render(status => 409, json => { error => 'User already exists' }) if $r;

    $r = execute_query($self, "insert into users(role, login, pass, name, lastname, email) values (?, ?, ?, ?, ?, ?)",
        $role_id, @$params{qw(login password name lastname email)});

    return _i_err $self unless $r;

    $r = send_request($self,
        method => 'get',
        url => 'login',
        port => SESSION_PORT,
        check_session => 0,
        args => {
            login => $params->{login},
            password => $params->{password},
            user_agent => $self->req->headers->user_agent,
        });

    return _i_err $self unless $r;
    return $self->render(status => 401, json => { error => "internal", description => "session: " . $r->{error} }) if !$r or $r->{error};

    $self->session(session => $r->{session_id});
    return $self->render(json => { ok => 1 });
}

sub roles {
    my $self = shift;

    my $r = select_all($self, "select name from roles order by name");
    return $self->render(json => { ok => 1, roles => $r, count => scalar @$r }) if $r;
    return _i_err $self;
}

1;
