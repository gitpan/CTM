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
#   perldoc CTM::ReadEM::_workOnExceptionAlerts
#------------------------------------------------------------------------------------------------------
# DEPENDANCES OBLIGATOIRES
#   - CTM::Base
#   - CTM::ReadEM
#   - Carp
#   - Hash::Util
#------------------------------------------------------------------------------------------------------

#-> BEGIN

#----> ** initialisation **

package CTM::ReadEM::_workOnExceptionAlerts;

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

our $VERSION = 0.174;

#----> ** methodes publiques **

sub refresh {
    return shift->SUPER::_refresh('workOnExceptionAlerts');
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

C<CTM::ReadEM::_workOnExceptionAlerts>

=head1 SYNOPSIS

Module du constructeur C<CTM::ReadEM::workOnExceptionAlerts()>.
Pour plus de details, voir la documention POD de C<CTM::ReadEM>.

=head1 DEPENDANCES

C<CTM::Base>, C<CTM::ReadEM>, C<Carp>, C<Hash::Util>

=head1 NOTES

Ce module est dedie au module C<CTM::ReadEM>.

=head1 AUTEUR

Le Garff Yoann <weeble@cpan.org>

=head1 LICENCE

Voir licence Perl.

=cut