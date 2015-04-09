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

    #$r->put('/change_user')->to('users#change'); TODO
    #$r->delete('/del_user')->to('users#delete'); TODO

    $r->get('/districts')->to('data#districts');
    $r->get('/companies')->to('data#companies');
    $r->get('/buildings')->to('data#buildings');

    $r->get('/build')->to('results#build');
    $r->post('/add_buildings')->to('results#add_buildings');
    $r->post('/add_categories')->to('results#add_categories');
    $r->post('/add_content')->to('results#add_content');
}

1;
