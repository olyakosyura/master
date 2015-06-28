package Front::Controller::Geolocation;
use Mojo::Base 'Mojolicious::Controller';

use DB qw( :all );
use JSON qw( decode_json );
use LWP::UserAgent;

use threads;
use threads::shared;
use Thread::Queue;
use Data::Dumper;

sub url { 'http://geocode-maps.yandex.ru/1.x/?format=json&geocode=' }
sub threads_count { 4 }

my %requests :shared;

sub begin {
    my $self = shift;

    my $data = select_all($self, "select id, name, coordinates from buildings where status = 'Голова'");
    return $self->render(status => 500) unless $data;

    for (keys %requests) {
        delete $requests{$_} if $requests{$_}{time} <= time - 4 * 60 * 60; # exp time for cache is 4 hours
    }

    my $req_id = int rand time;
    $requests{$req_id} = shared_clone({
        complete    => 0,
        time        => time,
        data        => Thread::Queue->new, # to enqueue data
        queue       => Thread::Queue->new(@$data),
    });

    my @threads;
    for (1 .. threads_count) {
        push @threads, threads->create(sub {
            $self->do_work($req_id);
        });
    }

    $self->stash(db_data => $data);
    $self->stash(req_id => $req_id);

    return $self->render(template => 'base/coordinates');
}

sub parse_content {
    my ($self, $id, $content) = @_;
    return unless $content;

    my $res;
    eval {
        $res = decode_json $content;
        die "Invalid json" unless $res;
    } or $self->app->log->error("Can't decode yandex api response: $@");

    $res = $res->{response}{GeoObjectCollection};

    my %addrs;
    my $i = 0;
    for my $obj (@{$res->{featureMember}}) {
        ++$i;
        my $o = $obj->{GeoObject};
        $addrs{"$id.$i"} = {
            addr => "$o->{name}, $o->{description}",
            coords => $o->{Point}{pos},
        };
    }

    return {
        id => $id,
        success => 1,
        count => $res->{metaDataProperty}{GeocoderResponseMetaData}{found},
        data => \%addrs,
    };
}

sub do_work {
    my ($self, $req_id) = @_;
    my $data = $requests{$req_id};

    my $ua = LWP::UserAgent->new;
    $ua->timeout(10);
    $ua->env_proxy;

    my $tid = threads->tid();

    while (my $item = $data->{queue}->dequeue_timed(5)) {
        if ($item->{coordinates}) {
            $data->{data}->enqueue({
                old => 1,
                id => $item->{id},
                success => 1,
                count => 1,
                data => {
                    "$item->{id}.1" => {
                        addr => $item->{name},
                        coords => $item->{coordinates},
                    }
                },
            });
            next;
        }

        $self->app->log->debug("[$tid] Trying to request coordinates for building $item->{id} (addr $item->{name})\n");
        my $response = $ua->get(url() . $item->{name});
        if ($response->is_success) {
            $data->{data}->enqueue($self->parse_content($item->{id}, $response->decoded_content));
        } else {
            $self->app->log->error("Yandex api server not found\n") if $response->status_line =~ /404/;
            $self->app->log->error("Yandex api server has crashed\n") if $response->status_line =~ /500/;
            $self->app->log->error("Can't get coordinates for $item->{id}: " . $response->status_line);
            last if $response->status_line !~ /404|500/;
        }
    }

    $data->{complete}++;
}

sub status {
    my $self = shift;

    my $req_id = $self->param('req_id');
    my $last_id = $self->param('last_id');

    my $data = $requests{$req_id};
    return $self->render(json => { error => "bad request: req_id is unknown" }) unless $data;

    my @to_return;
    my $new_last_id = $last_id;
    while (my $item = $data->{data}->peek($new_last_id)) {
        ++$new_last_id;
        push @to_return, $item;
    }

    return $self->render(json => {
        count => scalar(@to_return),
        content => \@to_return,
        last_id => $new_last_id,
        complete => ($data->{complete} == threads_count() ? 1 : 0),
    });
}

sub save_changes {
    my $self = shift;
    my $args = $self->req->json;

    my $data = $requests{$args->{req_id}};
    return $self->render(json => { error => "bad request: req_id is unknown" }) unless $data;

    my $data_to_save = $args->{to_save};
    return $self->render(json => { error => 'invalid data' } ) unless $data_to_save and ref($data_to_save) eq "ARRAY" and @$data_to_save;

    my %saved_content;
    while (my $item = $data->{data}->dequeue_nb) {
        $saved_content{$item->{id}} = $item->{data};
    }

    my $q = prepare_query($self, "update buildings set coordinates = ? where id = ?");
    my $count = 0;
    for (@$data_to_save) {
        if ($saved_content{$_->{id}} and $saved_content{$_->{id}}{$_->{val}}) {
            $self->app->log->debug("Updating coords for id $_->{id} ($_->{val})");
            ++$count;
            execute_prepared($self, $q, $saved_content{$_->{id}}{$_->{val}}{coords}, $_->{id});
        } else {
            $self->app->log->warn("Cant save addr with id $_->{id} ($_->{val}): not found");
        }
    }

    return $self->render(json => { saved => $count });
}

1;
