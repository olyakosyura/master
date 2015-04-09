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

    return $self->render(json => { status => 400, error => "Too many sheets found in document, maximum 1" })
        if scalar $parser->worksheets() > 1;

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

                push @content, $v;
            }

            $_exec->();
        }
    }

    return $self->render(json => { error => "invalid file format" }) unless $have_data;

    $_exec->(1);

    return $self->render(json => { ok => 1, errors => { count => scalar @errors, errors => \@errors } });
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
        2 => 'usage_limit',
    );

    my @keys = sort keys %fields;
    my $q = 'insert into categories (' . join(',', @fields{@keys}) . ') values (' . join(',', map { '?' } @keys) . ')';
    my %categories = map { $_->{object_name} => $_->{id} } @{ select_all $self, 'select object_name, id from categories' };

    warn Dumper \%categories;

    my $rows = 0;
    my @errors;
    for my $sheet ($parser->worksheets) {
        $parser->set_worksheet($sheet);
        my ($min_r, $max_r) = $parser->row_range;

        for my $row ($min_r + 1 .. $max_r) { # Skip first line
            my $e = -1;
            my @data = map { $parser->cell($row, $_) || ($e = $_) } @keys;
            if ($e > -1) {
                push @errors, { row => $row, error => "Cell $e is empty" };
            } elsif (defined $categories{$data[0]}) {
                push @errors, { row => $row, error => "Category $data[0] already exists" };
            } else {
                ++$rows;
                execute_query($self, $q, @data);
            }
        }
    }
    return $self->render(json => { ok => 1, count => $rows, errors => \@errors });
}

sub add_content {
    my $self = shift;
    my $args = $self->req->params->to_hash;

    my ($parser, $error) = parser $self, $args->{filename};
    return $self->render(json => { status => 400, error => $error }) if $error;

    #return $self->render(json => { status => 400, error => "Too many sheets found in document, maximum 1" })
    #    if scalar $parser->worksheets() > 1; TODO FIXME !!!

    my $have_data = 0;

    my $building_id;
    my %content = map {
        my $t = $_;
        $t => { map { $_->{name} => $_->{id} } @{ select_all $self, "select name, id from $t" } }
    } qw( laying_methods isolations characteristics );

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

    my %actions = (
        1  => { sql_name => 'building', callback => sub {
            my ($row, $v) = @_;
            return $building_id unless $v;
            $building_id = int($v);
            return $building_id;
        }},
        14 => { callback => sub {
            my ($row, $v) = @_;
            return undef unless $v;
            $v =~ s/,//g;
            execute_query($self, 'update buildings set cost = ? where id = ?', int($v), $building_id) if defined $building_id;
            return undef;
        }},
        4  => { sql_name => 'object_name', callback => sub {
            my ($row, $v) = @_;
            return undef unless $v;
            return $categories{$v} if defined $categories{$v};
            push @errors, { row => $row, error => "Category $v not found in database (skip)" };
            return undef;
        }},
        6  => { sql_name => 'characteristic', callback => sub { $add_n_get->('characteristics', $_[1]); }},
        7  => { sql_name => 'length', },
        8  => { sql_name => 'size', },
        9  => { sql_name => 'isolation', callback => sub { $add_n_get->('isolations', $_[1]); }},
        10 => { sql_name => 'laying_method', callback => sub { $add_n_get->('laying_methods', $_[1]); }},
        11 => { sql_name => 'install_year', },
        12 => { sql_name => 'reconstruction_year', },
        13 => { sql_name => 'cost', callback => sub { my ($row, $v) = @_; $v =~ s/,//g if $v; return $v; }},
    );

    my @fields_order = sort grep { $actions{$_}->{sql_name} } keys %actions;

    my $sql_fields_count = 0;
    my $fields_names = join ',', map { ++$sql_fields_count; $_->{sql_name} || () } @actions{@fields_order};
    my $qqq = join ',', map { '?' } 1 .. $sql_fields_count;

    my $rows = 0;
    for my $sheet ($parser->worksheets) {
        next unless $sheet->{Name} eq 'амортизация';
        $parser->set_worksheet($sheet);
        my ($min_r, $max_r) = $parser->row_range;

        for my $row ($min_r + 2 .. $max_r) {                    # skip first 2 rows
            my @query;
            my $old_building_id = $building_id || -1;
            for my $col (@fields_order) {
                my $r = $parser->cell($row, $col);
                my $ref = $actions{$col};
                if (defined $ref->{callback}) {
                    $r = $ref->{callback}->($row, $r);
                }
                next unless $r;
                push @query, $r;
            }
            if (scalar @query == scalar @fields_order) {
                execute_query $self, "insert into objects($fields_names) values ($qqq)", @query;
                ++$rows;
            } elsif ($building_id == $old_building_id) {
                push @errors, { line => $row, error => "Invalaid items count found in row: " .
                    (scalar @query) . ". " . (scalar @fields_order) . " expected" };
            }
        }
    }

    return $self->render(json => { ok => 1, count => $rows, errors => { count => scalar @errors, errors => \@errors } });
}

1;
