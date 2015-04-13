package Front::Controller::Builder;
use Mojo::Base 'Mojolicious::Controller';

sub index {
  my $self = shift;
  $self->render(template => 'base/index');
}

sub upload {
    my $self = shift;
    $self->app->log->debug("sdglkjsdlgkjsdlkgj");
    $self->render(template => 'base/upload');
}

1;
