#------------------------------------------------------------------------------------------------------
# OBJET : Module du constructeur CTM::ReadEM::workOnCurrentServices()
#------------------------------------------------------------------------------------------------------
# APPLICATION : Control-M EM + Batch Impact Manager (BIM)
#------------------------------------------------------------------------------------------------------
# AUTEUR : Yoann Le Garff
# DATE DE CREATION : 22/05/2014
# ETAT : STABLE
#------------------------------------------------------------------------------------------------------
# USAGE / AIDE
#   perldoc CTM::ReadEM::WorkOnBIMServices
#------------------------------------------------------------------------------------------------------
# DEPENDANCES OBLIGATOIRES
#   - CTM::Base
#   - CTM::Base::SubClass
#   - Carp
#   - Hash::Util
#------------------------------------------------------------------------------------------------------
# ATTENTION
#   Ce module n'a pas pour but d'etre directement charge par l'utilisateur
#------------------------------------------------------------------------------------------------------

#-> BEGIN

#----> ** initialisation **

package CTM::ReadEM::WorkOnBIMServices;

use strict;
use warnings;

use base qw/
    CTM::Base
    CTM::Base::SubClass
/;

use Carp qw/
    carp
    croak
/;
use Hash::Util qw/
    unlock_hash
/;

#----> ** variables de classe **

our $VERSION = 0.1771;

#----> ** fonctions privees (mais accessibles a l'utilisateur pour celles qui ne sont pas des references) **

my $_getAllViaLogID = sub {
    my ($dbh, $sqlRequest, $verbose, $logID) = @_;
    $sqlRequest .= " WHERE log_id IN ('" . join("', '", @{$logID}) . "');";
    print "VERBOSE - _getAllViaLogID() :\n\n" . $sqlRequest . "\n" if ($verbose);
    my $sth = $dbh->prepare($sqlRequest);
    if ($sth->execute()) {
        return 1, $sth->fetchall_hashref('log_id');
    } else {
        return 0, 0;
    }
};

#----> ** methodes privees **

#-> methodes liees aux services

my $_getFromRequest = sub {
    my ($self, $childSub, $sqlRequestSelectFrom, $errorType, $logID) = @_;
    $self->_setObjProperty('_working', 1);
    $self->unshiftError();
    if ($self->{'_CTM::ReadEM'}->getSessionIsConnected()) {
        if ($self->{_datas}) {
            $logID = [keys %{$self->{_datas}}] unless (defined $logID && ref $logID eq 'ARRAY');
            if (@{$logID}) {
                my ($situation, $hashRefPAlertsJobsForServices) = $_getAllViaLogID->($self->{'_CTM::ReadEM'}->{_DBI}, $sqlRequestSelectFrom, $self->{'_CTM::ReadEM'}->{verbose}, $logID);
                if ($situation) {
                    $self->_setObjProperty('_working', 0);
                    return $hashRefPAlertsJobsForServices;
                } else {
                    $self->_addError(CTM::Base::_myErrorMessage($childSub, 'erreur lors de la recuperation des ' . $errorType . " : la methode DBI 'execute()' a echouee : '" . $self->{'_CTM::ReadEM'}->{_DBI}->errstr() . "'."));
                }
            } else {
                $self->_setObjProperty('_working', 0);
                return {};
            }
        } else {
            $self->_addError(CTM::Base::_myErrorMessage($childSub, 'impossible de recuperer les ' . $errorType . ", les services n'ont pas pu etre generer via la methode 'workOnCurrentServices()'."));
        }
    } else {
        $self->_addError(CTM::Base::_myErrorMessage($childSub, "impossible de continuer car la connexion au SGBD n'est pas active."));
    }
    $self->_setObjProperty('_working', 0);
    return 0;
};

#----> ** methodes publiques **

#-> methodes liees aux services

sub refresh {
    return shift->SUPER::_refresh('workOnCurrentServices');
}

sub getSOAPEnvelope {
    my ($self, $logID) = @_;
    $self->_setObjProperty('_working', 1);
    $self->unshiftError();
    if ($self->{_datas}) {
        $logID = [keys %{$self->{_datas}}] unless (defined $logID && ref $logID eq 'ARRAY');
        my $XMLStr = <<XML;
<?xml version="1.0" encoding="iso-8859-1"?>
<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
<SOAP-ENV:Body>
    <ctmem:response_bim_services_info xmlns:ctmem="http://www.bmc.com/it-solutions/product-listing/control-m-enterprise-manager.html">
        <ctmem:status>OK</ctmem:status>
        <ctmem:services>
XML
        for (@{$logID}) {
            if (exists $self->{_datas}->{$_}) {
                $XMLStr .= <<XML;
            <ctmem:service>
XML
                while (my ($key, $value) = each %{$self->{_datas}->{$_}}) {
                    if (defined $value) {
                        $XMLStr .= <<XML;
                <ctmem:$key>$value</ctmem:$key>
XML
                    }
                }
                $XMLStr .= <<XML;
            </ctmem:service>
XML
            }
        }
        $XMLStr .= <<XML;
        </ctmem:services>
    </ctmem:response_bim_services_info>
</SOAP-ENV:Body>
</SOAP-ENV:Envelope>
XML
        chomp $XMLStr;
        $self->_setObjProperty('_working', 0);
        return \$XMLStr;
    }
    $self->_addError(CTM::Base::_myErrorMessage('getSOAPEnvelope', "impossible de generer le XML, les services n'ont pas pu etre generer via la methode 'workOnCurrentServices()'."));
    $self->_setObjProperty('_working', 0);
    return 0;
}

sub getAlerts {
    my ($self, $logID) = @_;
    return $self->$_getFromRequest('getAlerts', 'SELECT * FROM bim_alert', 'alertes', defined $logID && ref $logID eq 'ARRAY' ? $logID : []);
}

sub getProblematicsJobs {
    my ($self, $logID) = @_;
    return $self->$_getFromRequest('getProblematicsJobs', 'SELECT * FROM bim_prob_jobs', 'jobs en erreur', defined $logID && ref $logID eq 'ARRAY' ? $logID : []);
}

#-> Perl BuiltIn

BEGIN {
    *AUTOLOAD = \&CTM::Base::AUTOLOAD;
}

sub DESTROY {
    unlock_hash(%{+shift});
}

#-> END

__END__

=pod

=head1 NOM

C<CTM::ReadEM::WorkOnBIMServices>

=head1 SYNOPSIS

Module du constructeur C<CTM::ReadEM::workOnCurrentServices()>.
Pour plus de details, voir la documention POD de CTM::ReadEM.

=head1 DEPENDANCES

C<CTM::Base>, C<CTM::Base::SubClass>, C<Carp>, C<Hash::Util>

=head1 NOTES

Ce module est dedie au module C<CTM::ReadEM>.

=head1 AUTEUR

Le Garff Yoann <pe.weeble@yahoo.fr>

=head1 LICENCE

Voir licence Perl.

=cut