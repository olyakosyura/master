package Files::Controller::Files;
use Mojo::Base 'Mojolicious::Controller';

use strict;
use warnings;

use Cache::Memcached;
use MIME::Base64 qw( encode_base64url decode_base64url );
use Encode qw( decode );
use File::stat;

use DB qw( :all );
use AccessDispatcher qw( check_session );
use MainConfig qw( :all );

sub open_memc {
    my $self = shift;
    $self->{memc} = Cache::Memcached->new({
        servers => [ MEMC_HOST . ':' . MEMC_PORT ],
    }) unless defined $self->{memc};

    $self->app->log->error("Can't open connection to Memcached") unless $self->{memc};
}

sub load_paths {
    my $self = shift;
    $self->open_memc;

    unless ($self->{memc}->get('files_cache_expire_flag')) {
        my $r = select_all($self, 'select f.id as id, f.path as path, d.name as district, d.id as district_id, ' .
            'c.id as company_id, c.name as company from files f ' .
            'join districts d on d.id = f.district_id join companies c on c.id = f.company_id');

        return $self->app->log->error("Can't fetch files from DB") unless $r;

        for my $row (@$r) {
            $self->{memc}->set('files_paths_cache_' . $row->{district_id} . '_' . $row->{company_id}, $row, EXP_TIME);
        }

        $self->{memc}->set('files_cache_expire_flag', 1, EXP_TIME) if @$r;
    }
}

sub list {
    my $self = shift;
    $self->load_paths;

    my ($district_id, $company_id) = map { $self->param($_) } qw( district company );
    return $self->render(json => { error => "district and company args are required" })
        unless defined $district_id and defined $company_id;

    my $data;
    my $i = 0;
    while (not $data and $i < 2) {
        $data = $self->{memc}->get("files_paths_cache_$district_id" . "_$company_id");
        $self->load_paths unless $data;
        ++$i;
    }

    return $self->render(json => { error => "invalid district or company" }) unless $data;

    my $dir;
    my $path = ROOT_FILES_PATH . "/$data->{path}";
    opendir $dir, $path;
    my @files = readdir $dir;
    closedir $dir;

    my @content;

    $i = 0;
    for my $f (sort @files) {
        my $fname = decode('utf8', $f);

        next if $fname =~ /^\.\.?$/;
        my $s = stat "$path/$fname";

        my $data = encode_base64url pack "iiiii", $district_id, $company_id, $i, $s->size, $s->mtime;
        push @content, {
            name => $fname,
            size => $s->size,
            url => "http://" . FILES_HOST . "/file?f=$data",
        };
        $i++;
    }

    return $self->render(json => { files => \@content });
}

sub get {
    my $self = shift;
    $self->load_paths;

    my $f_info = $self->param('f');
    return $self->redirect_to(URL_404) unless $f_info;

    my ($district_id, $company_id, $index, $size, $mtime) = unpack 'iiiii', decode_base64url($f_info);
    unless (defined $district_id and defined $company_id and defined $index and defined $size and defined $mtime) {
        $self->app->log->error("Invalid f hash came");
        return $self->redirect_to(URL_404);
    }

    my $data;
    my $i = 0;
    while (not $data and $i < 2) {
        $data = $self->{memc}->get("files_paths_cache_$district_id" . "_$company_id");
        $self->load_paths unless $data;
        ++$i;
    }

    my $dir;
    my $path = ROOT_FILES_PATH . "/$data->{path}";
    opendir $dir, $path;
    my @files = readdir $dir;
    closedir $dir;

    $path = "$path/" . decode('utf8', $files[$index]);
    my $s = stat $path;
    if ($s->size != $size or $s->mtime != $mtime) {
        $self->app->log->error("File outdated");
        return $self->redirect_to(URL_404);
    }

    my $ret = check_session $self;

    $self->session(expires => 1) if $ret->{error};
    return $self->redirect_to(URL_401) if $ret->{error} && $ret->{error} ne 'unauthorized';

    $self->render_file(filepath => $path, filename => $files[$index]);
    return $self->rendered(200);
}

1;
