#------------------------------------------------------------------------------------------------------
# OBJET : Module du constructeur CTM::ReadEM::workOnAlarms()
#------------------------------------------------------------------------------------------------------
# APPLICATION : Control-M EM + Global Alert Server (GAS)
#------------------------------------------------------------------------------------------------------
# AUTEUR : Yoann Le Garff
# DATE DE CREATION : 27/05/2014
# ETAT : STABLE
#------------------------------------------------------------------------------------------------------
# USAGE / AIDE
#   perldoc CTM::ReadEM::WorkOnAlarms
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

package CTM::ReadEM::WorkOnAlarms;

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

our $VERSION = 0.176;

#----> ** methodes publiques **

sub refresh {
    return shift->SUPER::_refresh('workOnAlarms');
}

sub notice {
    return shift->SUPER::_setSerials('notice', 'workOnAlarms', 'alarms', "UPDATE alarm SET handled = '1'", @_);
}

sub unnotice {
    return shift->SUPER::_setSerials('unnotice', 'workOnAlarms', 'alarms', "UPDATE alarm SET handled = '0'", @_);
}

sub handle {
    return shift->SUPER::_setSerials('handle', 'workOnAlarms', 'alarms', "UPDATE alarm SET handled = '2'", @_);
}

sub unhandle {
    return shift->SUPER::_setSerials('unhandle', 'workOnAlarms', 'alarms', "UPDATE alarm SET handled = '1'", @_);
}

sub delete {
    return shift->SUPER::_setSerials('delete', 'workOnAlarms', 'alarms', 'DELETE * FROM alarm', @_);
}

sub setSeverity {
    my ($self, $severity, $serialID) = @_;
    croak(CTM::Base::_myErrorMessage('setSeverity', "usage : \$obj->setPublicProperty(\$R_or_U_or_V).")) unless ($severity eq 'R' || $severity eq 'U' || $severity eq 'V');
    return shift->SUPER::_setSerials('setSeverity', 'workOnAlarms', 'alarms', "UPDATE alarm SET severity = '" . $severity . "'", $serialID);
}

sub setNote {
    my ($self, $notes, $serialID) = @_;
    croak(CTM::Base::_myErrorMessage('setNote', "usage : la 'note' ne peut pas valoir undef.")) unless (defined $notes);
    return shift->SUPER::_setSerials('setNote', 'workOnAlarms', 'alarms', "UPDATE alarm SET notes = '" . $notes . "'", $serialID);
}

#-> Perl BuiltIn

BEGIN {
    *AUTOLOAD = \&CTM::Base::AUTOLOAD;
}

sub DESTROY {
    unlock_hash(%{+shift});
}

1;

#-> END

__END__

=pod

=head1 NOM

C<CTM::ReadEM::WorkOnAlarms>

=head1 SYNOPSIS

Module du constructeur C<CTM::ReadEM::workOnAlarms()>.
Pour plus de details, voir la documention POD de C<CTM::ReadEM>.

=head1 DEPENDANCES

C<CTM::Base>, C<CTM::Base::SubClass>, C<Carp>, C<Hash::Util>

=head1 NOTES

Ce module est dedie au module C<CTM::ReadEM>.

=head1 AUTEUR

Le Garff Yoann <weeble@cpan.org>

=head1 LICENCE

Voir licence Perl.

=cut
