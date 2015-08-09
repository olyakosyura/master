package Files;
use Mojo::Base 'Mojolicious';

# This method will run once at server start
sub startup {
    my $self = shift;

    # Documentation browser under "/perldoc"
    $self->plugin('PODRenderer');
    $self->plugin('RenderFile');
    $self->secrets([qw( 0i+hE8eWI0pG4DOH55Kt2TSV/CJnXD+gF90wy6O0U0k= )]);

    # Router
    my $r = $self->routes;

    # Normal route to controller
    $r->get('files')->to('files#list');
    $r->get('file')->to('files#get');
}

1;
