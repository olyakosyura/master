package Data;
use Mojo::Base 'Mojolicious';

# This method will run once at server start
sub startup {
    my $self = shift;

    # Documentation browser under "/perldoc"
    $self->plugin('PODRenderer');
    $self->secrets([qw( e16wEG+SnmVPRhQgNhS36VWV3ruZrV0mI1RajjJBt7w= )]);

    # Router
    my $r = $self->routes;

    # Normal route to controller
    $r->get('/roles')->to('users#roles');
    $r->get('/register')->to('users#add');
    $r->get('/users_list')->to('users#list');

    $r->get('/cargo')->to('cargo#list');
    $r->get('/add_cargo')->to('cargo#add_cargo');

    $r->get('/orders')->to('orders#list');
    $r->get('/add_order')->to('orders#add_order');
    $r->get('/change_order_state')->to('orders#change_state');

}

1;
