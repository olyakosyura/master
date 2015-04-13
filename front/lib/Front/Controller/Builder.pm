package Front::Controller::Builder;
use Mojo::Base 'Mojolicious::Controller';

sub index {
  my $self = shift;
  $self->render(template => 'base/index');
}

1;
