#------------------------------------------------------------------------------------------------------
# OBJET : Module du constructeur CTM::ReadEM::workOnExceptionAlerts()
#------------------------------------------------------------------------------------------------------
# APPLICATION : Control-M EM + Configuration Manager Alarms
#------------------------------------------------------------------------------------------------------
# AUTEUR : Yoann Le Garff
# DATE DE CREATION : 27/05/2014
# ETAT : STABLE
#------------------------------------------------------------------------------------------------------
# USAGE / AIDE
#   perldoc CTM::ReadEM::WorkOnExceptionAlerts
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

package CTM::ReadEM::WorkOnExceptionAlerts;

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
    return shift->SUPER::_refresh('refresh');
}

sub handle {
    return shift->SUPER::_setSerials('handle', 'workOnExceptionAlerts', 'ExceptionAlerts', "UPDATE exception_alerts SET status = '2'", @_);
}

sub unhandle {
    return shift->SUPER::_setSerials('unhandle', 'workOnExceptionAlerts', 'ExceptionAlerts', "UPDATE exception_alerts SET status = '1'", @_);
}

sub detete {
    return shift->SUPER::_setSerials('detete', 'workOnExceptionAlerts', 'ExceptionAlerts', 'DELETE * FROM exception_alerts', @_);
}

sub setNote {
    my ($self, $note, $serialID) = @_;
    croak(CTM::Base::_myErrorMessage('setNote', "usage : la 'note' ne peut pas valoir undef.")) unless (defined $note);
    return shift->SUPER::_setSerials('setNote', 'workOnExceptionAlerts', 'ExceptionAlerts', "UPDATE exception_alerts SET note = '" . $note . "'", $serialID);
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

C<CTM::ReadEM::WorkOnExceptionAlerts>

=head1 SYNOPSIS

Module du constructeur C<CTM::ReadEM::workOnExceptionAlerts()>.
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
