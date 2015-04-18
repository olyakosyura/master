package ExcelParser;

use strict;
use warnings;

sub new {
    my $class = shift;
    my $xls = shift;

    my $self = bless { }, $class;

    return $self->set_error('invalid filename') unless $xls;
    return $self->set_error('file not found') unless -f $xls;

    $self->{fname} = $xls unless $self->_init($xls);
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

    return 0;
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
    return 0;
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

use MainConfig qw( :all );
use AccessDispatcher qw( send_request check_access );

use Excel::Writer::XLSX;
use File::Temp;

use Data::Dumper;

use DB qw( :all );
use Helpers qw( :all );

use Translation qw( :all );

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

sub prepare_int {
    my $v = shift;
    $v =~ s/,//g if $v;
    return $v;
}

sub add_buildings {
    my $self = shift;

    my $args = $self->req->params->to_hash;
    return $self->render(json => { status => 400, error => "file not found" }) unless $args->{filename} or not -f $args->{filename};

    my ($parser, $error) = parser $self, $args->{filename};
    return $self->render(json => { status => 400, error => $error }) if $error;

    return $self->render(json => { status => 400, error => "Too many sheets found in document, maximum 1" })
        if scalar $parser->worksheets() > 1;

    my $districts = select_all $self, "select id, name from districts";
    $districts = { map { $_->{name} => { id => $_->{id}, companies => {} } } @$districts };

    my $companies = select_all $self, 'select c.id as id, c.name as name, d.name as district ' .
        'from companies c join districts d on d.id = c.district_id';

    my %buildings = map { $_->{id} => 1 } @{ select_all $self, "select id from buildings" };

    for (@$companies) {
        $districts->{$_->{district}}->{companies}->{$_->{name}} = $_->{id};
    }

    my @errors;
    my $fields_count = 8; # ;(

    my %fields = (
        0 => { sql_name => 'id', callback => sub {
            my ($line_no, $cur_id, @line) = @_;
            my $cell = $line[0];

            if ($buildings{$cell}) {
                push @errors, { line => $line_no, error => "building id $cell is already exists in db" };
                return undef;
            }

            $buildings{$cell} = 1;
            return $cell;
        }},
        1 => { sql_name => 'company_id', callback => sub {
            my ($line_no, $cur_id, @line) = @_;
            my $name = $line[1];
            my $district = $line[7];

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
    my $lines_per_req = 1;
    my @content;

    my $sql_line = 0;
    my $count = 0;
    my $_exec = sub {
        my $force = shift;
        ++$sql_line unless $force;
        ++$count unless $force;
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
            my @new_content;
            for my $col ($min_c .. $max_c) {
                next unless defined $fields{$col};

                my $ref = $fields{$col};
                my $v = ((defined $ref->{callback} ? $ref->{callback}->($row, $col, @cells) : $cells[$col]) || $ref->{default});

                unless (defined $v) {
                    @new_content = ();
                    last;
                }
                push @new_content, $v;
            }

            next unless @new_content;

            push @content, @new_content;
            $_exec->();
        }
    }

    return $self->render(json => { error => "invalid file format" }) unless $have_data;

    $_exec->(1);

    return $self->render(json => { ok => 1, count => $count, errors => { count => scalar @errors, errors => \@errors } });
}

sub add_categories {
    my $self = shift;

    my $args = $self->req->params->to_hash;
    return $self->render(json => { status => 400, error => "file not found" }) unless $args->{filename} or not -f $args->{filename};

    my ($parser, $error) = parser $self, $args->{filename};
    return $self->render(json => { status => 400, error => $error }) if $error;

    return $self->render(json => { status => 400, error => "Too many sheets found in document, maximum 1" })
        if scalar $parser->worksheets() > 1;

    my %fields = (
        0 => 'object_name',
        1 => 'category_name',
    );

    my @keys = sort keys %fields;
    my $q = 'insert into categories (' . join(',', @fields{@keys}) . ') values (' . join(',', map { '?' } @keys) . ')';
    my %categories = map { my $v = $_->{object_name}; utf8::decode($v); $v => $_->{id} }
        @{ select_all $self, 'select object_name, id from categories' };

    my $rows = 0;
    my @errors;
    for my $sheet ($parser->worksheets) {
        $parser->set_worksheet($sheet);
        my ($min_r, $max_r) = $parser->row_range;

        for my $row ($min_r + 1 .. $max_r) { # Skip first line
            my $e = -1;
            my @data = map { $parser->cell($row, $_) || ($e = $_) } @keys;
            utf8::decode($data[0]);
            if ($e > -1) {
                push @errors, { line => $row, error => "Cell $e is empty" };
            } elsif (defined $categories{$data[0]}) {
                push @errors, { line => $row, error => "Category $data[0] already exists" };
            } else {
                ++$rows;
                execute_query($self, $q, @data);
            }
        }
    }
    return $self->render(json => { ok => 1, count => $rows, errors => { count => scalar @errors, errors => \@errors, }, });
}

sub add_buildings_meta {
    my $self = shift;

    my $args = $self->req->params->to_hash;

    my ($parser, $error) = parser $self, $args->{filename};
    return $self->render(json => { status => 400, error => $error }) if $error;

    return $self->render(json => { status => 400, error => "Too many sheets found in document, maximum 1" })
        if scalar $parser->worksheets() > 1;

    my %buildings = map { $_->{id} => 1 } @{ select_all $self, "select id from buildings" };
    my %existed = map { $_->{id} => 1 } @{ select_all $self, "select building_id as id from buildings_meta" };

    my @errors;
    my %fields = (
        0 => { sql_name => 'building_id', required => 1, action => sub {
            my ($val, $row) = @_;
            unless ($buildings{$val}) {
                push @errors, { line => $row, error => "Buildings $val not found in database" };
                return undef;
            }
            if (defined $existed{$val}) {
                push @errors, { line => $row, error => "Building $val already found in buildings_meta" };
                return undef;
            }
            return $val;
        }},
        2 => { sql_name => 'characteristic', required => 1, },
        3 => { sql_name => 'build_date', },
        4 => { sql_name => 'reconstruction_date', },
        5 => { sql_name => 'heat_load', },
        6 => { sql_name => 'cost', action => \&prepare_int },
    );

    my ($sheet) = $parser->worksheets;
    $parser->set_worksheet($sheet);

    my @keys = sort keys %fields;
    my $q = "insert into buildings_meta (" . (join ',', map { $fields{$_}->{sql_name} } @keys) .
        ") values (" . (join ',', map { '?' } @keys) . ')';

    my $count = 0;
    my ($min_r, $max_r) = $parser->row_range;
    for my $row ($min_r .. $max_r) {
        my @data;
        my $e = 1;
        for my $k (@keys) {
            my $v = $parser->cell($row, $k);
            if ($fields{$k}->{action}) {
                $v = $fields{$k}->{action}->($v, $row);
                if (not(defined $v) && $fields{$k}->{required}) {
                    $e = undef;
                    last;
                }
            }
            push @data, $v;
        }

        next unless $e;
        execute_query $self, $q, @data;
        ++$count;
    }

    return $self->render(json => { count => $count, ok => 1, errors => { count => scalar @errors, errors => \@errors } });
}

sub add_content {
    my $self = shift;
    my $args = $self->req->params->to_hash;

    my ($parser, $error) = parser $self, $args->{filename};
    return $self->render(json => { status => 400, error => $error }) if $error;

    return $self->render(json => { status => 400, error => "Too many sheets found in document, maximum 1" })
        if scalar $parser->worksheets() > 1;

    my ($sheet) = $parser->worksheets;
    $parser->set_worksheet($sheet);

    my $have_data = 0;

    my %content = map {
        my $t = $_;
        $t => { map { $_->{name} => $_->{id} } @{ select_all $self, "select name, id from $t" } }
    } qw( laying_methods isolations characteristics objects_subtypes );

    my $add_n_get = sub {
        my ($table_name, $v) = @_;
        return undef unless $v;
        unless (defined $content{$table_name}->{$v}) {
            execute_query $self, "insert into $table_name (name) values (?)", $v;
            $content{$table_name}->{$v} = last_id $self;
        }
        return $content{$table_name}->{$v};
    };

    my @errors;
    my %categories = map { $_->{object_name} => $_->{id} } @{ select_all $self, 'select object_name, id from categories' };
    my %buildings = map { $_->{id} => 1 } @{ select_all $self, "select id from buildings" };
    my %existed_objects = map { $_->{id} => 1 } @{ select_all $self, "select distinct building as id from objects" };

    my $deleted = 0;
    my %actions = (
        1  => { sql_name => 'building', required => 1, callback => sub {
            my $v = shift;
            return undef unless defined $v;
            unless (defined $buildings{$v}) {
                push @errors, { line => shift, error => "Building id '$v' is unknown" };
                return undef;
            }
            if ($existed_objects{$v}) {
                my $r = execute_query $self, "delete from objects where building = ?", $v;
                push @errors, { line => shift, error => "Objects for building $v was replaced" };
                $deleted += $r || 1;
                delete $existed_objects{$v};
            }
            return $v;
        }},
        5  => { sql_name => 'object_name', required => 1, callback => sub {
            my $v = shift;
            utf8::decode($v);
            if ($v) {
                $v =~ s/^\s+//;
                $v =~ s/\s+$//;
            }
            return $categories{$v} if defined $categories{$v};
            push @errors, { line => shift, error => "Category '$v' not found in database" };
            return undef;
        }},
        6  => { sql_name => 'characteristic', callback => sub { $add_n_get->('characteristics', shift); }},
        7  => { sql_name => 'characteristic_value', callback => \&prepare_int, },
        8  => { sql_name => 'size', callback => \&prepare_int },
        9  => { sql_name => 'isolation', callback => sub { $add_n_get->('isolations', shift); }},
        10 => { sql_name => 'laying_method', callback => sub { $add_n_get->('laying_methods', shift); }},
        11 => { sql_name => 'install_year', callback => \&prepare_int, },
        12 => { sql_name => 'reconstruction_year', callback => \&prepare_int, },
        14 => { sql_name => 'wear', callback => sub {
            my $v = shift;
            return 0 unless $v;
            $v =~ /([\d.]+)(%)?/;
            $v = $1 || 0;
            $v *= 100 unless $2;
            return $v;
        }},
        37 => { sql_name => 'cost', callback => \&prepare_int },
        39 => { sql_name => 'last_usage_limit', callback => \&prepare_int },
        41 => { sql_name => 'objects_subtype', callback => sub { $add_n_get->('objects_subtypes', shift); }},
    );

    my @fields_order = sort keys %actions;
    my $fields_names = join ',', map { $actions{$_}->{sql_name} || () } @fields_order;
    my $qqq = join ',', map { '?' } 1 .. scalar @fields_order;

    my $rows = 0;
    my ($min_r, $max_r) = $parser->row_range;

    for my $row ($min_r .. $max_r) {                    # skip first row
        next if $parser->cell($row, 0);

        my @query;
        my $e = 1;
        for my $col (@fields_order) {
            my $r = $parser->cell($row, $col);
            my $ref = $actions{$col};
            if (defined $ref->{callback}) {
                $r = $ref->{callback}->($r, $row);

                if (not(defined $r) && $ref->{required}) {
                    $e = 0;
                    last;
                }
            }
            push @query, $r;
        }
        next unless $e;

        execute_query $self, "insert into objects($fields_names) values ($qqq)", @query;
        ++$rows;
    }

    return $self->render(json => { ok => 1, count => $rows, deleted => $deleted, errors => { count => scalar @errors, errors => \@errors } });
}

sub render_xlsx {
    my ($self, $content, $workbook, $calc_type_required) = @_;

    my $header_bg_color = $workbook->set_custom_color(9, 201, 194, 194);
    my $splitter_bg_color = $workbook->set_custom_color(10, 230, 223, 223);

    # look at http://search.cpan.org/~jmcnamara/Excel-Writer-XLSX-0.15/lib/Excel/Writer/XLSX.pm to edit styles below
    my %styles = (
        header => {
            text_wrap => 1,
            align => 'center',
            valign => 'vcenter',
            color => 'black',
            bg_color => $header_bg_color,
        },
        text => {
            text_wrap => 1,
            valign => 'vcenter',
        },
        integer => {
            shrink => 1,
            align => 'center',
            valign => 'vcenter',
        },
        float => {
            align => 'center',
            valign => 'vcenter',
        },
        year => {
            align => 'center',
            valign => 'vcenter',
        },
        money => {
            align => 'center',
            valign => 'vcenter',
        },
        percent => {
            num_format => '##\%;[Red](##\%)',
            align => 'center',
            valign => 'vcenter',
        },
        building_splitter => {
            bold => 1,
            bg_color => $splitter_bg_color,
        },
    );

    my %styles_cache = map { $_ => $workbook->add_format(%{$styles{$_}}) } keys %styles;
    my %splitter_styles_cache = map { $_ => $workbook->add_format(%{$styles{$_}}, %{$styles{building_splitter}}) } keys %styles;

    my %fields = (
        # mysql name             header_text        style       column_width
        contract_id         => [ contract_id,       'integer',  10, ],
        company_name        => [ company_name,      'text',     50, ],
        address             => [ address,           'text',     40, ],
        district            => [ district,          'text',     10, ],
        object_name         => [ object_name,       'text',     50, ],
        category_name       => [ category,          'text',     30, ],
        characteristic      => [ characteristic,    'text',     30, ],
        count               => [ count,             'float',    10, ],
        size                => [ size,              'integer',  10, ],
        isolation_type      => [ isolation_type,    'text',     30, ],
        laying_method       => [ laying_method,     'text',     20, ],
        install_year        => [ install_year,      'year',     10, ],
        reconstruction_year => [ reconstruction_year, 'year',   10, ],
        wear                => [ wear,              'percent',  10, ],
        cost                => [ cost,              'money',    10, ],
        building_cost       => [ building_cost,     'money',    10, ],
        usage_limit         => [ usage_limit,       'integer',  10, ],
        calc_type           => [ calc_type,         'text',     30, ],
    );

    my @order = qw(
        contract_id
        company_name
        address
        district
        object_name
        category_name
        characteristic
        count
        size
        isolation_type
        laying_method
        install_year
        reconstruction_year
        wear
        building_cost
        cost
        usage_limit
    );

    if ($calc_type_required) {
        push @order, 'calc_type';
    }

    my %skip_if_object = map { $_ => 1 } qw( building_cost contract_id );
    my %print_if_building = map { $_ => 1 } qw( contract_id company_name address district building_cost );

    my $worksheet = $workbook->add_worksheet();
    $worksheet->freeze_panes(1,4);

    my $last_building_id = -100500;
    my $xls_row = 0;
    for my $row (-1 .. @$content - 1) {
        if ($row >= 0 && $last_building_id != $content->[$row]{building_cost}) {
            $last_building_id = $content->[$row]{building_cost};
            for my $index (0 .. @order - 1) {
                unless ($print_if_building{$order[$index]}) {
                    $worksheet->write($xls_row, $index, undef, $splitter_styles_cache{$fields{$order[$index]}->[1]});
                } else {
                    $worksheet->write($xls_row, $index, $content->[$row]{$order[$index]}, $splitter_styles_cache{$fields{$order[$index]}->[1]});
                }
            }
            ++$xls_row;
        }
        for my $index (0 .. @order - 1) {
            my $f = $fields{$order[$index]};
            if ($row == -1) {
                $worksheet->set_column($index, $index, $f->[2]);
                $worksheet->write($xls_row, $index, $f->[0], $styles_cache{'header'});
            } else {
                next if $skip_if_object{$order[$index]};
                $worksheet->write($xls_row, $index, $content->[$row]{$order[$index]}, $styles_cache{$f->[1]});
            }
        }
        ++$xls_row;
    }
}

sub build {
    my $self = shift;

    my $f = File::Temp->new(UNLINK => 1);

    my $workbook = Excel::Writer::XLSX->new($f->filename);

    my %sql_statements = (
        district => 'where d.id = ?',
        company => 'where c.id = ?',
        building => 'where b.id = ?',
        object => 'where o.id = ?',
        region => 'where d.region = ?',
    );

    my @order = qw( object building company district region );
    my $args = $self->req->params->to_hash;

    my $sql_part;
    my $sql_arg;

    for (@order) {
        if (defined $args->{$_}) {
            $sql_part = $sql_statements{$_};
            $sql_arg = $args->{$_};
            last;
        }
    }

    unless (defined $sql_arg) {
        return $self->render(json => { status => 400, error => join(' or ', keys %sql_statements) . " not empty argument is required" });
    }

    my $calc_type_required = 1;
    if ($self->req->headers->referrer =~ m{/objects$}) {
        $calc_type_required = 0;
    }

    if ($calc_type_required && !defined $args->{calc_type}) {
        # TODO: Not really implmented
        return $self->render(json => { status => 400, error => "calc_type argument is required" });
    }

    my @extra_args = (
        ', ct.name as calc_type',
        sprintf('join calc_types ct on ct.id %c ?', $args->{calc_type} && $args->{calc_type} == -1 ? '>' : '='),
    );

    my $sql_stat = <<SQL;
        select
            b.id as contract_id,
            bm.cost as building_cost,
            d.name as district,
            c.name as company_name,
            b.name as address,
            cat.object_name as object_name,
            cat.category_name as category_name,
            charac.name as characteristic,
            o.size as size,
            o.characteristic_value as count,
            o.size as size,
            i.name as isolation_type,
            l.name as laying_method,
            o.install_year as install_year,
            o.reconstruction_year as reconstruction_year,
            o.wear as wear,
            o.cost as cost,
            o.last_usage_limit as usage_limit
            %s
        from objects o
        join buildings b on b.id = o.building
        join companies c on c.id = b.company_id
        join districts d on d.id = c.district_id
        join categories cat on cat.id = o.object_name
        %s
        left outer join characteristics charac on charac.id = o.characteristic
        left outer join isolations i on i.id = o.isolation
        left outer join laying_methods l on l.id = o.laying_method
        left outer join buildings_meta bm on bm.building_id = b.id
        %s
        order by b.id, o.id
SQL
    my $r = select_all($self,
        sprintf($sql_stat, ($calc_type_required ? @extra_args : ('', '')), $sql_part),
        ($calc_type_required ? $args->{calc_type} : ()), $sql_arg);

    $workbook->set_properties(
        title => xlsx_default_title,
        author => ($args->{name} || "") . " " . ($args->{lastname} || ""),
        # TODO: add other properties
        # http://search.cpan.org/~jmcnamara/Excel-Writer-XLSX-0.15/lib/Excel/Writer/XLSX.pm#add_format(_%properties_)
    );

    $self->render_xlsx($r, $workbook, $calc_type_required);
    $workbook->close;

    $f->unlink_on_destroy(0);
    return $self->render(json => { filename => $f->filename });
}

1;
