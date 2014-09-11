#------------------------------------------------------------------------------------------------------
# OBJET : "Classe abstraite" des sous-modules ou sous-classes de CTM::ReadEM
#------------------------------------------------------------------------------------------------------
# APPLICATION : Control-M
#------------------------------------------------------------------------------------------------------
# AUTEUR : Yoann Le Garff
# DATE DE CREATION : 09/05/2014
# ETAT : STABLE
#------------------------------------------------------------------------------------------------------
# USAGE / AIDE
#   perldoc CTM::Base::SubClass
#------------------------------------------------------------------------------------------------------
# DEPENDANCES OBLIGATOIRES
#   - CTM::Base
#   - Carp
#   - Hash::Util
#------------------------------------------------------------------------------------------------------
# ATTENTION
#   Ce module n'a pas pour but d'etre charge par l'utilisateur
#------------------------------------------------------------------------------------------------------

#-> BEGIN

#----> ** initialisation **

package CTM::Base::SubClass;

use strict;
use warnings;

use base qw/
    CTM::Base
/;

use Carp qw/
    carp
    croak
/;
use Hash::Util qw/
    lock_hash
    unlock_hash
/;

#----> ** variables de classe **

our $VERSION = 0.1771;

#----> ** methodes protegees **

sub _refresh {
    my ($self, $baseMethod) = @_;
    if (caller->isa(__PACKAGE__)) {
        sleep 1 while ($self->{_working});
        my $selfTemp = $self->{'_CTM::ReadEM'}->$baseMethod(
            %{$self->{_params}}
        );
        my $_errorsTemp = $self->{_errors};
        $self = $selfTemp;
        unlock_hash(%{$self});
        $self->{_errors} = $_errorsTemp;
        lock_hash(%{$self});
        return 1;
    }
    carp(CTM::Base::_myErrorMessage('_refresh', "tentative d'utilisation d'une methode protegee."));
    return 0;
}

#-> methodes en rapport avec les alarmes/alertes

sub _setSerials {
    my ($self, $baseMethod, $baseConstructor, $errorType, $sqlRequest, $serialID) = @_;
    if (caller->isa(__PACKAGE__)) {
        $self->_setObjProperty('_working', 1);
        $self->unshiftError();
        if ($self->{'_CTM::ReadEM'}->getSessionIsConnected()) {
            if ($self->{_datas}) {
                $serialID = [keys %{$self->{_datas}}] unless (defined $serialID && ref $serialID eq 'ARRAY');
                $sqlRequest .= " WHERE serial IN ('" . join("', '", @{$serialID}) . "');";
                print "VERBOSE - _setSerials() :\n\n" . $sqlRequest . "\n" if ($self->{'_CTM::ReadEM'}->{verbose}); 
                if ($self->{'_CTM::ReadEM'}->{_DBI}->do($sqlRequest)) {
                    $self->_setObjProperty('_working', 0);
                    return 1;
                } else {
                    $self->_addError(CTM::Base::_myErrorMessage($baseMethod, "la connexion est etablie mais la methode DBI 'do()' a echouee : '" . $self->{'_CTM::ReadEM'}->{_DBI}->errstr() . "'."));
                }
            } else {
                $self->_addError(CTM::Base::_myErrorMessage($baseMethod, "impossible de prendre en compte les '" . $errorType . "' car ces elements n'ont pas etre generer via la methode '" . $baseConstructor . "()'."));
            }
        } else {
            $self->_addError(CTM::Base::_myErrorMessage($baseMethod, "impossible de continuer car la connexion au SGBD n'est pas active."));
        }
        $self->_setObjProperty('_working', 0);
    } else {
        carp(CTM::Base::_myErrorMessage('_setSerials', "tentative d'utilisation d'une methode protegee."));
    }
    return 0;
}

#----> ** methodes publiques **

sub countItems {
    my $self = shift;
    if (ref $self->{_datas} eq 'HASH') {
        return scalar keys %{$self->{_datas}};
    }
    return 0;
}

#-> accesseurs/mutateurs

sub getItems {
    return shift->{_datas};
}

#-> Perl BuiltIn

BEGIN {
    *AUTOLOAD = \&CTM::Base::AUTOLOAD;
}

1;

#-> END

__END__

=pod

=head1 NOM

C<CTM::Base::SubClass>

=head1 SYNOPSIS

"Classe abstraite" des sous-modules ou sous-classes C<CTM::ReadEM>.
Pour plus de details, voir la documention POD de C<CTM::ReadEM>.

=head1 DEPENDANCES

C<CTM::Base>, C<Carp>, C<Hash::Util>

=head1 NOTES

Ce module est dedie aux sous-modules ou sous-classes C<CTM::ReadEM>.

=head1 AUTEUR

Le Garff Yoann <pe.weeble@yahoo.fr>

=head1 LICENCE

Voir licence Perl.

=cut
