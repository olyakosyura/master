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
    $r->get('/company')->to('data#company_info');
    $r->get('/buildings')->to('data#buildings');
    $r->get('/objects')->to('data#objects');
    $r->get('/calc_types')->to('data#calc_types');

    $r->get('/build')->to('results#build');
    $r->get('/rebuild_cache')->to('results#rebuild_cache');
    $r->post('/add_buildings')->to('results#add_buildings');
    $r->post('/add_categories')->to('results#add_categories');
    $r->post('/add_content')->to('results#add_content');
    $r->post('/add_buildings_meta')->to('results#add_buildings_meta');

    $r->get('/geolocation/objects')->to('geolocation#objects');
    $r->get('/geolocation/status')->to('geolocation#status');
    $r->get('/geolocation/start')->to('geolocation#start_geolocation');
    $r->post('/geolocation/save')->to('geolocation#save_changes');
}

1;
