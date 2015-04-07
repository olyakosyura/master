package Data::Controller::Results;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw( encode_json );

use MainConfig qw( :all );
use AccessDispatcher qw( send_request check_access );

use Data::Dumper;
use utf8;

use DB qw( :all );
use Helpers qw( :all );

#use Spreadsheet::ParseExcel;
use Spreadsheet::XLSX;

sub add_buildings {
    my $self = shift;

    my $args = $self->req->params->to_hash;
    return $self->render(json => { status => 400, error => "file not found" }) unless $args->{filename} or not -f $args->{filename};

    my $excel = Spreadsheet::XLSX->new($args->{filename});

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
        0 => { sql_name => 'contract_id', default => 0 },
        1 => { sql_name => 'company_id', callback => sub {
            my ($line_no, $cur_id, @line) = @_;
            my $name = $line[1]->{Val};
            my $district = $line[7]->{Val};
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
    for my $sheet (@{$excel->{Worksheet}}) {
        $have_data = 1;
        $self->app->log->debug(sprintf "Sheet: %s", $sheet->{Name});
        $sheet->{MaxRow} ||= $sheet->{MinRow};

        my $row_no = 0;
        for my $row ($sheet->{MinRow} .. $sheet->{MaxRow}) {
            $sheet->{MaxCol} ||= $sheet->{MinCol};

            my @cells = @{ $sheet->{Cells}[$row] || [] };
            next unless @cells;

            if (@cells < $fields_count) {
                push @errors, { line => $row, error => "Invalid columns count: " . scalar(@cells), };
                next;
            }

            unless (defined $cells[0]->{Val}) {
                push @errors, { line => $row, error => "Id field not found" };
                next;
            }

            ++$row_no;
            next if $row_no == 1; # skip header

            for my $col ($sheet->{MinCol} ..  $sheet->{MaxCol}) {
                next unless defined $fields{$col};

                my $ref = $fields{$col};
                my $v = ((defined $ref->{callback} ? $ref->{callback}->($row, $col, @cells) : $cells[$col]->{Val}) || $ref->{default});

                utf8::decode($v);
                $v =~ s/^\s*//;
                $v =~ s/\s*$//;
                push @content, $v;
            }

            $_exec->();
        }
    }

    return $self->render(json => { error => "invalid file format" });

    $_exec->(1);

    unlink $args->{filename};
    return $self->render(json => { ok => 1, errors => { count => scalar @errors, errors => \@errors } });
}

1;
