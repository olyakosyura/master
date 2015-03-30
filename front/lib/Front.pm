package Front;
use Mojo::Base 'Mojolicious';

# This method will run once at server start
sub startup {
    my $self = shift;

    # Documentation browser under "/perldoc"
    $self->plugin('PODRenderer');
    $self->secrets([qw( 0i+hE8eWI0pG4DOH55Kt2TSV/CJnXD+gF90wy6O0U0k= )]);

    # Router
    my $auth = $self->routes->under('/')->to('users#check_session');

    # Normal route to controller
    $auth->get('/login')->to('users#login');
    $auth->get('/logout')->to('users#logout');
    $auth->get('/roles')->to('users#roles');
    $auth->get('/register')->to('users#add');
    $auth->get('/users_list')->to('users#list');
    #$auth->put('/change_user')->to('users#change'); TODO
    #$auth->delete('/del_user')->to('users#delete'); TODO

    $auth->get('/districts')->to('data#districts');
    $auth->get('/companies')->to('data#companies');
    $auth->get('/buildings')->to('data#buildings');

    $auth->get('/build')->to('results#build');
}

1;
