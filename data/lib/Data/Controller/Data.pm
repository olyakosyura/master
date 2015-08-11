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
    my $filter_heads = defined $args && $args->{heads_only} || undef;
    $q = "%$q%" if $q;

    return $self->render(json => { status => 400, error => "invalid district" }) if defined $d && $d !~ /^\d+$/;

    my @args = ($self, "select c.id as id, c.name as name, d.name as district from companies c join districts d on d.id = c.district_id " .
        ($filter_heads ? "inner join buildings b on c.id = b.company_id and b.status = 'Голова' " : "") .
        (defined $q ? "where c.name like ? " : "") .
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

sub filter_objects {
    my $self = shift;

    my $bounds = sub {
        my $a = $self->param('start');
        my $b = $self->param('end');

        die "invalid bounds\n" unless defined($a) && defined($b);

        $a ||= 0;
        $b ||= 0;

        if ($a > $b) {
            ($a, $b) = ($b, $a);
        }

        ($a, $b);
    };

    my $types_param = sub {
        my $arg = $self->param('types');
        die "types are required\n" unless defined $arg;
        split ',', $arg;
    };

    my %cases = (
        company => {
            req => "select id from buildings where company_id = ?",
            args => sub {
                my $arg = $self->param("company");
                die "company id is required\n" unless defined $arg;
                $arg;
            },
        },
        cost => {
            req => "select distinct(building_id) as id from buildings_meta where cost > ? and cost < ?",
            args => $bounds,
        },
        repair => {
            req => "select distinct(building_id) as id from buildings_meta where reconstruction_date > ? and reconstruction_date < ?",
            args => $bounds,
        },
        type => {
            req => "select distinct(building_id) as id from buildings_meta where characteristic in (%s)",
            post => sub {
                join ',', map { '?' } (1 .. (scalar $types_param->()))
            },
            args => $types_param,
        },
    );

    my ($req, @args);
    eval {
        for my $type (keys %cases) {
            if ($self->param('type') eq $type) {
                $req = sprintf $cases{$type}->{req}, ($cases{$type}->{post} || sub {})->();
                @args = $cases{$type}->{args}->();
            }
        }
    };

    return $self->render(json => { status => 400, error => "$@" }) if $@;

    my $r = select_all($self, $req, @args);
    return $self->render(json => { status => 500, error => "db_error" }) unless defined $r;

    return $self->render(json => { status => 200, count => scalar(@$r), data => $r });
}

sub calc_types {
    my $self = shift;

    my $r = select_all $self, "select id, name from calc_types order by order_index";
    return $self->render(json => { ok => 1, count => scalar @$r, types => $r });
}

sub company_info {
    my $self = shift;

    my $obj_id = $self->param('obj_id');
    return $self->render(json => { status => 400, error => 'obj_id is undefined' }) unless defined $obj_id;

    my $r = select_all $self, "select c.id as company_id, c.name as company_name, b.name as addr " .
        "from buildings b join companies c on c.id = b.company_id where b.id = ?", $obj_id;

    return $self->render(json => { status => 500, error => 'db error' }) unless defined $r;
    return $self->render(json => { status => 200, error => 'object not found' }) unless @$r;

    $r = $r->[0];
    my $c_id = $r->{company_id};
    my %to_return = (
        company => $r->{company_name},
        addr => $r->{addr},
    );

    $r = select_all $self, "select status, name as addr, corpus, id, status = 'Голова' as is_primary, bm.characteristic as type, " .
        "bm.cost as cost, bm.heat_load as heat_load from buildings join buildings_meta bm on bm.building_id = id " .
        "where company_id = ?", $c_id;
    return $self->render(json => { status => 500, error => 'db_error' }) unless defined $r;

    $to_return{buildings} = $r;
    $to_return{count} = scalar @$r;
    return $self->render(json => \%to_return);
}

1;
