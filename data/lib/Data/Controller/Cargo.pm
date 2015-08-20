package Data::Controller::Cargo;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw( encode_json );

use MainConfig qw( :all );
use AccessDispatcher qw( send_request check_access _session );

use Data::Dumper;

use DB qw( :all );
use Helpers qw( :all );

sub list {
    my $self = shift;

    my $r = select_all($self, "select id, name, cost from cargo order by name");

    $r ||= [];
    return $self->render(json => { count => scalar @$r, cargo => $r });
}

sub add_cargo {
    my $self = shift;

    my $params = check_params $self, qw( name cost );
    return unless $params;

    execute_query($self, "insert into cargo(name, cost) values (?, ?)", @$params{qw( name cost )});
    return $self->render(json => { id => last_id($self), name => $params->{name}, cost => $params->{cost} });
}

1;
