## OpenXPKI::Server::Authentication::External.pm 
##
## Written 2005 by Martin Bartosch and Michael Bell
## Rewritten 2006 by Michael Bell
## Updated to use new Service::Default semantics 2007 by Alexander Klink
## (C) Copyright 2005-2007 by The OpenXPKI Project

package OpenXPKI::Server::Authentication::External;

use strict;
use warnings;

use OpenXPKI::Debug;
use OpenXPKI::Exception;
use OpenXPKI::Server::Context qw( CTX );

## constructor and destructor stuff

sub new {
    my $that = shift;
    my $class = ref($that) || $that;

    my $self = {};

    bless $self, $class;

    ##! 1: "start"

    my $path = shift;
    my $config = CTX('config');

    ##! 2: "load name and description for handler"

    $self->{DESC} = $config->get("$path.description");
    $self->{NAME} = $config->get("$path.label"); 

    ##! 2: "load command"
    $self->{COMMAND} = $config->get("$path.command"); 

    ##! 2: "command: ".$self->{COMMAND}
    
    $self->{ROLE} = $config->get("$path.role"); 
    
    ##! 2: "role: ".$self->{ROLE}
    
    if (not length $self->{ROLE})
    {
        delete $self->{ROLE};
        $self->{PATTERN} = $config->get("$path.pattern"); 
        $self->{REPLACE} = $config->get("$path.replacement");
    }

    # get environment settings
    ##! 2: "loading environment variable settings"

    my @clearenv;
    my $environment = $config->get_hash("$path.env");
    	
    foreach my $name (keys %{$environment}) {
        
        $self->{ENV}->{$name} = $environment->{$name};
        if (exists $self->{CLEARENV})
        {
            push @{$self->{CLEARENV}}, $name;
        } else {
            $self->{CLEARENV} = [ $name ];
        }
        ##! 4: "setenv: $name ::= $value"
    }
		
    ##! 2: "finished"

    return $self;
}

sub login_step {
    ##! 1: 'start' 
    my $self    = shift;
    my $arg_ref = shift;
 
    my $name    = $arg_ref->{HANDLER};
    my $msg     = $arg_ref->{MESSAGE};
    my $answer  = $msg->{PARAMS};

    if (! exists $msg->{PARAMS}->{LOGIN} ||
        ! exists $msg->{PARAMS}->{PASSWD}) {
        ##! 4: 'no login data received (yet)' 
        return (undef, undef, 
            {
		SERVICE_MSG => "GET_PASSWD_LOGIN",
		PARAMS      => {
                    NAME        => $self->{NAME},
                    DESCRIPTION => $self->{DESC},
	        },
            },
        );
    }

    my ($account, $passwd) = ($answer->{LOGIN}, $answer->{PASSWD});

    ##! 2: "credentials ... present"
    ##! 2: "account ... $account"

    # see security warning below (near $out=`$cmd`)

    foreach my $name (keys %{$self->{ENV}})
    {
        my $value = $self->{ENV}->{$name};
	# we don't want to see expanded passwords in the log file,
	# so we just replace the password after logging it
	$value =~ s/__USER__/$account/g;
	$value =~ s/__PASSWD__/$passwd/g;

	# set environment for executable
	$ENV{$name} = $value;
    }
    my $command = $self->{COMMAND};
    ##! 2: "execute command"

    # execute external program. this is safe, since cmd
    # is taken literally from the configuration.
    # NOTE: do not extend this code to allow login parameters
    # to be passed on the command line.
    # - the credentials may be visible in the OS process 
    #   environment
    # - worse yet, it is untrusted user input that might
    #   easily be used to execute arbitrary commands on the
    #   system.
    # SO DON'T EVEN THINK ABOUT IT!
    my $out = `$command`;
    map { delete $ENV{$_} } @{$self->{CLEARENV}}; # clear environment

    ##! 2: "command returned $?, STDOUT was: $out"
		
    if ($? != 0)
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_SERVER_AUTHENTICATION_EXTERNAL_LOGIN_FAILED",
            params  => {
		USER => $account,
	    });
        return (undef, undef, {});
    }

    $self->{USER} = $account;

    if (! exists $self->{ROLE})
    {
        $out =~ s/$self->{PATTERN}/$self->{REPLACE}/ if (defined $self->{PATTERN} && defined $self->{REPLACE});
        
        # Assert if the role is not defined
        if (!CTX('config')->get_hash("auth.roles.$out")) {
            OpenXPKI::Exception->throw (
                message => "I18N_OPENXPKI_SERVER_AUTHENTICATION_EXTERNAL_UNKNOWN_ROLE",
                params  => { ROLE => $out });
        }        
        $self->{ROLE} = $out;
    }

    return (
        $self->{USER},
        $self->{ROLE},
        {
            SERVICE_MSG => 'SERVICE_READY',
        },
    );
}

1;
__END__

=head1 Name

OpenXPKI::Server::Authentication::External - support for external authentication.

=head1 Description

This is the class which supports OpenXPKI with an authentication method
via an external program. The parameters are passed as a hash reference.

=head1 Functions

=head2 new

is the constructor. It requires the config prefix as single argument.

This is the minimum parameter set for any authentication class.
The configuration includes a command tag and a role or a regular expression
configuration (pattern and replacement). Additionally it is possible to
specify environment variables. The tag env must include a name and a value
parameter. Please note that the strings __USER__ and __PASSWORD__ in the value
parameter will be replaced by the entered user and passphrase.

=head2 login

returns (user, role, service ready message) triple if login was
successful, (undef, undef, {}) otherwise.

