# OpenXPKI::Client::UI::Secret
# Written 2013 by Oliver Welter
# (C) Copyright 2013 by The OpenXPKI Project

package OpenXPKI::Client::UI::Secret;

use Moose; 
use Data::Dumper;
use OpenXPKI::i18n qw( i18nGettext );

extends 'OpenXPKI::Client::UI::Result';

sub init_index {
    
    my $self = shift;
    my $args = shift;
   
    my $secrets  = $self->send_command("get_secrets");
  
    my @result;
    foreach my $secret (keys %{$secrets}) {     
        my $status = $self->send_command("is_secret_complete", {SECRET => $secret}) || 0;
        push @result, [ 
            i18nGettext($secrets->{$secret}->{LABEL}), 
            i18nGettext($secrets->{$secret}->{TYPE}), 
            i18nGettext($status ? 'I18N_OPENXPKI_SECRET_COMPLETE' : 'I18N_OPENXPKI_SECRET_INCOMPLETE'), 
            $secret 
        ];
    }
        
    $self->_page ({
        label => 'Manage the secrets of this realm',
        description => 'The list shows the state of your secret groups defined in this realm. To login/logout click on the row.',
        target => 'main'
    });
    
    $self->add_section({
        type => 'grid',
        processing_type => 'all',
        content => {
            actions => [{   
                path => 'secret!manage!id!{_id}',
                target => 'modal',
            }],            
            columns => [                        
                { sTitle => "Name" },
                { sTitle => "Type" },
                { sTitle => "Status"},
                { sTitle => "_id"},
            ],
            data => \@result            
        }
    }); 
    
}


sub init_manage {
 
    my $self = shift;
    my $args = shift;
   
    my $secret = $self->param('id');
    my $status = $self->send_command("is_secret_complete", {SECRET => $secret}) || 0;
    
    if ($status) {
        $self->_page ({label => 'Clear secret'});
        $self->add_section({
            type => 'text',        
            content => {
                description => 'Secret is complete',                
                buttons => [{ label => 'Clear', page => 'secret!clear!id!'.$secret, css_class => 'btn-warning', target => 'modal' }]
            }
        });
    } else {
        $self->_page ({label => 'Unlock secret'});
        $self->add_section({
            type => 'form',             
            content => {
                fields => [ 
                    { 'name' => 'phrase', 'label' => 'Passphrase', 'type' => 'password' }, 
                    { 'name' => 'id', 'type' => 'hidden', value => $secret }
                ],                
                buttons => [{ 
                    label => 'Unlock',
                    do_submit => 1, 
                    action => 'secret!unlock', 
                    css_class => 'btn-danger',                    
                }]
            }
        });        
    }
    
    return $self;
}

sub init_clear {
    
    my $self = shift;
    my $args = shift;
   
    my $secret = $self->param('id');
    my $status = $self->send_command("clear_secret", {SECRET => $secret});
    
    if ($status) {
        $self->set_status('Secret was cleared','success');
    } elsif (defined $status) {
        $self->set_status('Clearing failed - please check again!','error');
    }
    
    $self->init_index();
        
    return $self;
}

sub action_unlock {
 
    my $self = shift;
    my $args = shift;

    my $phrase = $self->param('phrase');
    my $secret = $self->param('id');
    my $msg = $self->send_command ( "set_secret_part", 
        { SECRET => $secret, VALUE => $phrase });
        
    if ($msg) {
        $self->set_status('Secret accepted','success');
        $self->init_index();
    } elsif (defined $msg) {
        $self->set_status('Secret rejected','error');        
    }     
    
    return $self;
    
}

1;