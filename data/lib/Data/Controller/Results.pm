package ExcelParser;

use strict;
use warnings;

sub new {
    my $class = shift;
    my $xls = shift;

    my $self = bless { }, $class;

    return $self->set_error('invalid filename') unless $xls;
    return $self->set_error('file not found') unless -f $xls;

    $self->{fname} = $xls if $self->_init($xls);
    return $self;
}

sub set_error {
    my $self = shift;
    $self->{error} = shift;
    return $self;
}

sub last_error {
    my $self = shift;
    return $self->{error};
}

sub set_worksheet {
    my ($self, $s) = @_;
    $self->{sheet} = $s;
}

sub DESTROY {
    my $self = shift;
    unlink $self->{xls} if defined $self->{xls};
}

1;

package XLSParser;

use strict;
use warnings;

use Spreadsheet::ParseExcel;

use base "ExcelParser";

sub _init {
    my ($self, $fname) = @_;

    $self->{parser} = Spreadsheet::ParseExcel->new();
    return $self->set_error("ParseXLS: can't create parser: $@") unless $self->{parser};

    $self->{workbook} = $self->{parser}->parse($fname);
    return $self->set_error("ParseXLS: invalid file format") unless $self->{workbook};
}

sub worksheets {
    my $self = shift;
    return $self->{workbook}->worksheets;
}

sub row_range {
    my $self = shift;
    return $self->{sheet}->row_range;
}

sub col_range {
    my $self = shift;
    return $self->{sheet}->col_range;
}

sub cell {
    my ($self, $row, $col) = @_;
    return $self->{sheet}->get_cell($row, $col) && $self->{sheet}->get_cell($row, $col)->value;
}

1;

package XLSXParser;

use strict;
use warnings;

use Spreadsheet::XLSX;
use base "ExcelParser";

sub _init {
    my $self = shift;
    my $fname = shift;

    eval {
        $self->{parser} = Spreadsheet::XLSX->new($fname);
    };

    return $self->set_error("ParseXLSX: invalid file format: $@") if $@;
}

sub worksheets {
    my $self = shift;
    return @{ $self->{parser}->{Worksheet} };
}

sub col_range {
    my ($self) = @_;
    my $sheet = $self->{sheet};

    $sheet->{MaxCol} ||= $sheet->{MinCol};
    return ($sheet->{MinCol}, $sheet->{MaxCol});
}

sub row_range {
    my ($self) = @_;
    my $sheet = $self->{sheet};

    $sheet->{MaxRow} ||= $sheet->{MinRow};
    return ($sheet->{MinRow}, $sheet->{MaxRow});
}

sub cell {
    my ($self, $row, $col) = @_;
    return $self->{sheet}->{Cells}->[$row]->[$col]->{Val};
}

1;

package Data::Controller::Results;
use strict;
use warnings;
use utf8;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw( encode_json );

use MainConfig qw( :all );
use AccessDispatcher qw( send_request check_access );

use Data::Dumper;

use DB qw( :all );
use Helpers qw( :all );

sub parser {
    my ($self, $f) = @_;

    my $parser = XLSXParser->new($f);
    return ($parser) unless $parser->last_error;

    $self->app->log->warn($parser->last_error);
    $parser = XLSParser->new($f);
    return ($parser) unless $parser->last_error;

    $self->app->log->warn($parser->last_error);
    return (undef, "Can't create parser: " . $parser->last_error);
}

sub add_buildings {
    my $self = shift;

    my $args = $self->req->params->to_hash;
    return $self->render(json => { status => 400, error => "file not found" }) unless $args->{filename} or not -f $args->{filename};

    my ($parser, $error) = parser $self, $args->{filename};
    return $self->render(json => { status => 400, error => $error }) if $error;

    my $districts = select_all $self, "select id, name from districts";
    $districts = { map { $_->{name} => { id => $_->{id}, companies => {} } } @$districts };

    my $companies = select_all $self, 'select c.id as id, c.name as name, d.name as district ' .
        'from companies c join districts d on d.id = c.district_id';

    for (@$companies) {
        $districts->{$_->{district}}->{companies}->{$_->{name}} = $_->{id};
    }

    my @errors;
    my $fields_count = 8; # ;(

    my %fields = (
        0 => { sql_name => 'id', default => 0 },
        1 => { sql_name => 'company_id', callback => sub {
            my ($line_no, $cur_id, @line) = @_;
            my $name = $line[1];
            my $district = $line[7];
            utf8::decode($name);
            utf8::decode($district);

            unless ($districts->{$district}) {
                execute_query($self, 'insert into districts(name) values (?)', $district);
                $districts->{$district}->{id} = last_id $self;
                $districts->{$district}->{companies} = {};
            }

            my $cmp = $districts->{$district}->{companies};
            unless ($cmp->{$name}) {
                execute_query($self, 'insert into companies(district_id, name) values (?, ?)', $districts->{$district}->{id}, $name);
                $cmp->{$name} = last_id $self;
            }

            return $cmp->{$name};
        }},
        2 => { sql_name => 'name', default => '', },
        3 => { sql_name => 'status', default => '', },
        4 => { sql_name => 'corpus', default => '' },
    );

    my $sql_fields = join ',', map { $fields{$_}->{sql_name} } sort keys %fields;
    my $sql_placeholders = '(' . join(',', map { '?' } (1 .. scalar keys %fields)) . ')';
    my $lines_per_req = int(100 / scalar keys %fields);
    my @content;

    my $sql_line = 0;
    my $_exec = sub {
        my $force = shift;
        ++$sql_line unless $force;
        if (($force && $sql_line > 1) || $sql_line >= $lines_per_req) {
            execute_query($self, "insert into buildings ($sql_fields) values " .
                join(',', map { $sql_placeholders } (1 .. $sql_line)), @content);
            @content = ();
            $sql_line = 0;
        }
    };

    my $have_data = 0;
    for my $sheet ($parser->worksheets) {
        $have_data = 1;
        $parser->set_worksheet($sheet);
        my ($min_r, $max_r) = $parser->row_range;

        for my $row ($min_r .. $max_r) {
            my ($min_c, $max_c) = $parser->col_range;

            unless (defined $parser->cell($row, $min_c)) {
                next;
            }

            my $id = $parser->cell($row, $min_c);
            if ($id && $id !~ /^\d+$/) {
                utf8::decode $id;
                push @errors, { line => $row, error => "Id field is not numerical: $id" };
                $id = undef;
            }
            next unless $id;

            my @cells = map { $parser->cell($row, $_) } $min_c .. $max_c;
            for my $col ($min_c .. $max_c) {
                next unless defined $fields{$col};

                my $ref = $fields{$col};
                my $v = ((defined $ref->{callback} ? $ref->{callback}->($row, $col, @cells) : $cells[$col]) || $ref->{default});

                utf8::decode($v);
                push @content, $v;
            }

            $_exec->();
        }
    }

    return $self->render(json => { error => "invalid file format" }) unless $have_data;

    $_exec->(1);

    return $self->render(json => { ok => 1, errors => { count => scalar @errors, errors => \@errors } });
}

sub add_content {
    my $self = shift;
    my $args = $self->req->params->to_hash;

    my ($parser, $error) = parser $self, $args->{filename};
    return $self->render(json => { status => 400, error => $error }) if $error;
    return $self->render(json => { status => '200' }); # TODO: Remove me

    my @errors;
    my $have_data = 0;

    my $building_id;
    my %content = map {
        my $t = $_;
        $t => { map { $_->{name} => $_->{id} } @{ select_all $self, "select name, id from $t" } }
    } qw( objects_names laying_methods isolations characteristics categories );

    warn Dumper \%content;

    my $add_n_get = sub {
        my ($table_name, $v) = @_;
        return undef unless $v;
        unless (defined $content{$table_name}->{$v}) {
            execute_query $self, "insert into $table_name (name) values (?)", $v;
            $content{$table_name}->{$v} = last_id $self;
        }
        return $content{$table_name}->{$v};
    };

=cut
    [Wed Apr  8 23:46:31 2015] [debug] 0, 0 -> № п/п
    [Wed Apr  8 23:46:31 2015] [debug] 0, 1 -> № объекта по контракту
    [Wed Apr  8 23:46:31 2015] [debug] 0, 2 -> Наименование учреждения
    [Wed Apr  8 23:46:31 2015] [debug] 0, 3 -> Адрес
    [Wed Apr  8 23:46:31 2015] [debug] 0, 4 -> Наименование объекта
    [Wed Apr  8 23:46:31 2015] [debug] 0, 5 -> Характеристика
    [Wed Apr  8 23:46:31 2015] [debug] 0, 6 -> Протяженность, м/
    кол-во (шт)
    [Wed Apr  8 23:46:31 2015] [debug] 0, 7 -> Диаметр тепловых сетей, мм (Габариты каналов, м)
    [Wed Apr  8 23:46:31 2015] [debug] 0, 8 -> Тип изоляции
    [Wed Apr  8 23:46:31 2015] [debug] 0, 9 -> Способ прокладки тепловых сетей
    [Wed Apr  8 23:46:31 2015] [debug] 0, 10 -> Год ввода в эксплуатацию тепловых сетей
    [Wed Apr  8 23:46:31 2015] [debug] 0, 11 -> Год последней реконструкции тепловых сетей
    [Wed Apr  8 23:46:31 2015] [debug] 0, 12 -> Тепловая нагрузка, Гкал/час
    [Wed Apr  8 23:46:31 2015] [debug] 0, 13 -> Рыночная стоимость, руб.   (по элементно)
    [Wed Apr  8 23:46:31 2015] [debug] 0, 14 -> Рыночная стоимость, руб. (по зданию (по адресу))
    [Wed Apr  8 23:46:31 2015] [debug] 0, 15 -> Оставшийся  срок полезного использования, лет
    [Wed Apr  8 23:46:31 2015] [debug] 0, 16 -> Амортизация
=cut

    my %actions = (
        1  => { sql_name => 'building_id', callback => sub {
            my $v = shift;
            return $building_id unless $v;
            $building_id = int($v);
            return $building_id;
        }},
        14 => { callback => sub {
            my $v = shift;
            return undef unless $v;
            $v =~ s/,//g;
            execute_query($self, 'update buildings set cost = ? where id = ?', int($v), $building_id) if defined $building_id;
            return undef;
        }},
        4  => { sql_name => 'object_name', callback => sub { $add_n_get->('objects_names', shift); }},
        5  => { sql_name => 'category', callback => sub { $add_n_get->('categories', shift); }},
        6  => { sql_name => 'characteristic', callback => sub { $add_n_get->('characteristics', shift); }},
        7  => { sql_name => 'length', },
        8  => { sql_name => 'size', },
        9  => { sql_name => 'isolation', callback => sub { $add_n_get->('isolations', shift); }},
        10 => { sql_name => 'laying_method', callback => sub { $add_n_get->('laying_methods', shift); }},
        11 => { sql_name => 'install_year', },
        12 => { sql_name => 'reconstruction_year', },
        13 => { sql_name => 'cost', callback => sub { my $v = shift; $v =~ s/,//g if $v; return $v; }},
        15 => { sql_name => 'normal_usage_limit', },
        16 => { sql_name => 'usage_limit', }, # TODO: is it needed?
        17 => { sql_name => 'amortisation_per_year', },
        18 => { sql_name => 'amortisation', },
    );

    my @fields_order = sort keys %actions;

    my $sql_fields_count = 0;
    my $fields_names = join ',', map { ++$sql_fields_count; $_->{sql_name} || () } @actions{@fields_order};
    my $qqq = join ',', map { '?' } 1 .. $sql_fields_count;

    for my $sheet ($parser->worksheets) {
        $parser->set_worksheet($sheet);
        my ($min_r, $max_r) = $parser->row_range;

        my ($min_c, $max_c) = $parser->col_range;
        for my $col ($min_c .. $max_c) { # TODO: Remove me
            $self->app->log->debug("0, $col -> " . $parser->cell(0, $col));
        }
        return $self->render(json => { status => '200' });

        my @query;
        for my $row ($min_r + 2 .. $max_r) {                    # skip first 2 rows
            my $old_building_id = $building_id || -1;
            for my $col (@fields_order) {
                my $r = $parser->cell($row, $col);
                my $ref = $actions{$col};
                if (defined $ref->{callback}) {
                    $r = $ref->{callback}->($r);
                }
                next unless $r;
                utf8::decode($r);
                push @query, $r;
            }
            if ($#query == $#fields_order) {
                execute_query $self, "insert into buildings($fields_names) values ($qqq)", @query;
            } elsif ($building_id == $old_building_id) {
                push @errors, { line => $row, error => "Invalaid items count found in row: " .
                    (scalar @query) . ". " . (scalar @fields_order) . " expected" };
            }
        }
    }

    return $self->render(json => { ok => 1, errors => { count => scalar @errors, errors => \@errors } });
}

1;
