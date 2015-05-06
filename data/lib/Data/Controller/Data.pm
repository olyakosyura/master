package Data::Controller::Data;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw( encode_json );

use MainConfig qw( :all );
use AccessDispatcher qw( send_request check_access );

use Data::Dumper;

use DB qw( :all );
use Helpers qw( :all );

sub districts {
    my $self = shift;

    my $args = $self->req->params->to_hash;
    my $q = defined $args && $args->{q} || undef;
    $q = "%$q%" if $q;

    my @args = ($self, "select id, name, region from districts" . (defined $q ? " where name like ? order by name" : ""));
    push @args, $q if defined $q;
    my $r = select_all @args;

    return return_500 $self unless $r;

    return $self->render(json => { ok => 1, count => scalar @$r, districts => $r });
}

sub companies {
    my $self = shift;

    my $args = $self->req->params->to_hash;
    my $q = defined $args && $args->{q} || undef;
    my $d = defined $args && $args->{district} || undef;
    my $region = defined $args && $args->{region} || undef;
    $q = "%$q%" if $q;

    return $self->render(json => { status => 400, error => "invalid district" }) if defined $d && $d !~ /^\d+$/;

    my @args = ($self, "select c.id as id, c.name as name, d.name as district from companies c join districts d " . 
        "on d.id = c.district_id " . (defined $q ? "where c.name like ? " : "") .
        (defined $d ? (defined $q ? "and" : "where") . " c.district_id=? " : "") .
        (defined $region ? (defined $q || defined $d ? "and" : "where") . " d.region=? " : "") . "order by c.name");

    push @args, $q if defined $q;
    push @args, $d if defined $d;
    push @args, $region if defined $region;
    my $r = select_all @args;

    return return_500 $self unless $r;

    return $self->render(json => { ok => 1, count => scalar @$r, companies => $r });
}

sub buildings {
    my $self = shift;

    my $args = $self->req->params->to_hash;
    my $q = "%$args->{q}%" if $args->{q};
    delete $args->{district} if defined $args->{company};

    my $id_found = defined $args->{company} || defined $args->{district};

    return $self->render(json => { status => 400, error => "invalid district" }) if defined $args->{district} && $args->{district} !~ /^\d+$/;
    return $self->render(json => { status => 400, error => "invalid company" }) if defined $args->{company} && $args->{company} !~ /^\d+$/;

    my @args = (
        "select b.id as id, b.name as name, d.name as district, c.name as company " .
        "from buildings b join companies c on c.id = b.company_id join districts d on d.id = c.district_id " .
        (defined $args->{company} ? "where c.id = ? " : "") .
        (defined $args->{district} ? "where d.id = ? " : "") .
        (defined $args->{q} ? ($id_found ? "and " : "where ") . " b.name like ? " : "") .
        "order by b.name",
    );

    push @args, $args->{company} || $args->{district} if $id_found;
    push @args, $q if defined $q;

    my $r = select_all $self, @args;

    return return_500 $self unless $r;

    return $self->render(json => { ok => 1, count => scalar @$r, buildings => $r });
}

sub objects {
    my $self = shift;

    my $args = $self->req->params->to_hash;
    my $q = "%$args->{q}%" if $args->{q};

    for (qw( building )) { # TODO: add other cases (district && company)
        return $self->render(json => { status => 400, error => "invalid $_" }) if defined $args->{$_} && $args->{$_} !~ /^\d+$/;
    }

    my @args = (
        "select o.id as id, cat.object_name as name from objects o join categories cat on o.object_name = cat.id " .
        (defined $args->{building} ? "where building = ? " : "") .
        (defined $args->{q} ? (defined $args->{building} ? "and " : "where ") . "cat.object_name like ? " : "") .
        "order by cat.object_name"
    );

    push @args, $args->{building} if defined $args->{building};
    push @args, $q if defined $q;

    my $r = select_all $self, @args;

    return return_500 $self unless $r;
    return $self->render(json => { ok => 1, count => scalar @$r, objects => $r });
}

sub calc_types {
    my $self = shift;

    my $r = select_all $self, "select id, name from calc_types";
    return $self->render(json => { ok => 1, count => scalar @$r, types => $r });

}

1;
