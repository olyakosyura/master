package Data::Controller::Orders;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw( encode_json );

use MainConfig qw( :all );
use AccessDispatcher qw( send_request check_access _session );

use Data::Dumper;

use DB qw( :all );
use Helpers qw( :all );

sub orders {
    my $self = shift;
    my $uid = shift;
    my $id = shift;

    my @args;
    my $whr = "";

    if (defined $uid) {
        @args = ($uid);
        $whr = " where u.id = ?";
    }
    if (defined $id) {
        $whr = " where o.id = ?";
        @args = ($id);
    }

    return select_all($self, sprintf(q/
            select
                u.login as login,
                o.id as id,
                c.name as cargo,
                o.submit_date,
                o.closed,
                o.departure,
                o.destination,
                o.quantity,
                (o.quantity * c.cost) as cost,
                o.status
            from orders o
            join cargo c on c.id = o.cargo_id
            join users u on u.id = o.uid
            %s
            order by o.submit_date
        /, $whr), @args);
}

sub list {
    my $self = shift;

    my $args = $self->req->params->to_hash;

    my $r = $self->orders($args->{all_users} ? undef : $args->{user_id}) || [];
    return $self->render(json => { count => scalar @$r, orders => $r });
}

sub add_order {
    my $self = shift;

    my $params = check_params $self, qw( cargo count depart dest user_id );
    return unless $params;

    execute_query $self, q/insert into orders(uid, cargo_id, departure, destination, quantity, status) values (?, ?, ?, ?, ?, "Submited")/,
        @$params{qw( user_id cargo depart dest count )};

    my $id = last_id($self);
    my $c = ($self->orders($params->{user_id}, $id) || [])->[0];

    return $self->render(json => { data => $c});
}

sub change_state {
    my $self = shift;

    my $params = check_params $self, qw( order_id state close );
    return unless $params;

    if ($params->{close}) {
        $params->{state} = "Delivered";
    }

    execute_query $self, q/insert into orders_history(order_id, old_status) select id, status from orders where id = ?/, $params->{order_id};
    execute_query $self, q/update orders set closed = ?, status = ? where id = ?/, ($params->{close} ? 1 : 0), @$params{qw(state order_id)};
    return $self->render(json => { data => ($self->orders(undef, $params->{order_id}) || [])->[0] });
}

1;
