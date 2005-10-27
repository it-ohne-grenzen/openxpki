
package OpenXPKI::Server::DBI::Hash;

use OpenXPKI qw(set_error errno errval debug);
use OpenXPKI::Server::DBI::SQL;
use OpenXPKI::Server::DBI::Schema;

=head1 Description

The Hash module of OpenXPKI::Server::DBI implements the hash interface
of the database.

=head1 General Functions

=head2 new

is the constructor. It needs at minimum SQL with an instance
of OpenXPKI::Server::DBI::SQL.  You can specify optionally DEBUG.

=cut

sub new
{
    shift;
    my $self = { @_ };
    bless $self, "OpenXPKI::Server::DBI::Hash";
    $self->{schema} = OpenXPKI::Server::DBI::Schema->new();
    $self->debug ("init complete");
    return $self;
}

sub set_session_id
{
    my $self = shift;
    $self->{SESSION_ID} = shift;
    return $self->{SESSION_ID};
}

sub set_log_ref
{
    my $self = shift;
    $self->{log} = shift;
    return $self->{log};
}

########################################################################

=head1 SQL related Functions

=head2 insert

inserts the columns which are found in the parameter HASH which is
a hash reference into the table which is specififed with TABLE. The
column TABLE_SERIAL is automatically set to HASH->{KEY} if it is not
specified explicitly.

=cut

sub insert
{
    my $self = shift;
    my $keys = { @_ };

    my $table = $keys->{TABLE};
    my $hash  = $keys->{HASH};

    $hash->{$table."_SERIAL"} = $keys->{HASH}->{KEY}
        if (not exists $hash->{$table."_SERIAL"});
    $self->debug ("table: $table serial: ".$hash->{$table."_SERIAL"});

    $self->{SQL}->insert (TABLE => $table, DATA => $hash);

    $self->__log_write_action (TABLE  => $table,
                               MODE   => "INSERT",
                               HASH   => $hash);  
    return 1;
}

########################################################################

=head2 update

updates the columns which are found in the parameter DATA which is
a hash reference into the table which is specififed with TABLE. The
column TABLE_SERIAL is automatically set to DATA->{KEY} if it is not
specified explicitly. WHERE is a hash reference too and includes
the filter of the update operation. All parameters are required.
If WHERE is missing then we process one from the index of the table
and the DATA parameter.

=cut

sub update
{
    my $self = shift;
    my $keys = { @_ };

    my $table = $keys->{TABLE};
    my $data  = $keys->{DATA};
    my $where = undef;
       $where = $keys->{WHERE} if (exists $keys->{WHERE});

    $data->{$table."_SERIAL"} = $data->{KEY}
        if (not exists $data->{$table."_SERIAL"} and exists $data->{KEY});

    if (not $where)
    {
        ## extracts the index from the data
        foreach my $key (@{$self->{schema}->get_table_index ($table)})
        {
            $where->{$key} = $data->{$key};
            delete $data->{$key};
        }
    }

    $self->{SQL}->update (TABLE => $table, WHERE => $where, DATA => $data);

    ## FIXME: to be 100 percent safe it is necessary to protect $data
    $self->__log_write_action (TABLE  => $table,
                               MODE   => "UPDATE",
                               HASH   => {%{$where}, %{$data}});  
    return 1;
}

########################################################################

=head2 select

implements an access method to the SQL select operation. Please
look at OpenXPKI::Server::DBI::SQL to get an overview about the available
query options.

The function returns a reference to an array of hashes or undef on error.

=cut

sub select
{
    my $self = shift;
    my $keys = { @_ };
    my $result = $self->{SQL}->select (@_);

    ## build a hash from the returned array

    my @array = ();
    my $cols  = $self->{schema}->get_table_columns ($keys->{TABLE});
    foreach my $arrayref (@{$result})
    {
        my $hashref = undef;
        next if (not $arrayref);
        for (my $i=0; $i<scalar @{$cols}; $i++)
        {
            $hashref->{$cols->[$i]} = $arrayref->[$i];
        }
        push @array, $hashref;
    }

    return [ @array ];
}

########################################################################

=head2 __log_write_action

Parameters are TABLE, MODE and HASH.
MODE is update or insert.
HASH is the inserted or updated HASH which must include the index.

The function logs the write operations and creates or updates
the entries in the dataexchange table.

Never call this function from outside the module. It is fully internal and
highly critical for the whole infrastructure.

=cut

sub __log_write_action
{
    my $self  = shift;
    my ($package, $filename, $line, $subroutine, $hasargs,
        $wantarray, $evaltext, $is_require, $hints, $bitmask) = caller(0);
    my $keys  = { @_ };
    my $table = $keys->{TABLE};
    my $hash  = $keys->{HASH};
    my $mode  = $keys->{MODE};
    my $message;

    ## ignore management tables
    return 1 if ($table eq "AUDITTRAIL");
    return 1 if ($table eq "DATAEXCHANGE");

    ## set status if available
    my $status = undef;
       $status = $hash->{STATUS} if (exists $hash->{STATUS});

    ## set the index
    my %index = ();
    foreach my $col (@{$self->{schema}->get_table_index($table)})
    {
        if ($col eq "${table}_SERIAL")
        {
            $index{SERIAL}  = $hash->{$col};
        } else {
            ## planned for index with more than one column
            ## example: external_ca/internal_ca
            $index{$col} = $hash->{$col};
        }
    }

    ## log the action
    if ($mode eq "UPDATE")
    {
        $message = "Row updated.";
    } else {
        $message = "Row inserted";
    }
    $message .= "\ntable=".$table.
                "\nstatus=".$status.
                "\nsession=".$self->{SESSION_ID};
    foreach my $key (keys %index)
    {
        $message .= "\n".lc($key)."=".$index{$key};
    }
    $self->{log}->log (FACILITY => "audit",
                       PRIORITY => "info",
                       MESSAGE  => $message,
                       MODULE   => $package,
                       FILENAME => $filename,
                       LINE     => $line);

    ## write dataexchange log
    $self->{SQL}->delete (TABLE => "DATAEXCHANGE",
                          DATA  => {TABLE => $table, %index});
    my $serial = $self->{SQL}->get_new_serial (NAME => "DATAEXCHANGE");
    $self->{SQL}->insert (TABLE => "DATAEXCHANGE",
                          DATA  => {"DATAEXCHANGE_SERIAL" => $serial,
                                    "TABLE"        => $table,
                                    "SERVERID"     => -1,
                                    "EXPORTID"     => 0,
                                    %index}));

    return 1;
}

########################################################################

=head1 See also

OpenXPKI::Server::DBI::SQL and OpenXPKI::Server::DBI::Schema

=cut

1;