#------------------------------------------------------------------------------------------------------
# OBJET : "Classe abstraite" des sous-classes de CTM::ReadEM
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
#   - CTM::Base::SubClass
#   - Carp
#   - Hash::Util
#------------------------------------------------------------------------------------------------------
# ATTENTION
#   "Classe abstraite" des sous-classes de CTM::ReadEM. Ce module n'a pas pour but d'etre charge par l'utilisateur
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

our $VERSION = 0.171;

#----> ** methodes protegees **

sub _refresh {
    my ($self, $baseMethod) = @_;
    if (caller->isa(__PACKAGE__)) {
        while ($self->{_working}) {
            my $selfTemp = $self->{'_CTM::ReadEM'}->$baseMethod(
                %{$self->{'_CTM::ReadEM'}->{_params}}
            );
            if (defined $self->{'_CTM::ReadEM'}->{_errorArrayRef}) {
                $self->_addError($self->{'_CTM::ReadEM'}->{_errorArrayRef});
            } else {
                $self->{'_CTM::ReadEM'}->unshiftError();
                $selfTemp->_addError($self->{_errorArrayRef});
                unlock_hash(%{$self});
                $self = $selfTemp;
                lock_hash(%{$self});
                return 1;
            }
        }
    } else {
        carp(_myErrorMessage((caller 0)[3], "tentative d'utilisation d'une methode protegee."));
    }
    return 0;
}

#----> ** methodes publiques **

sub countItems {
    return scalar keys %{shift->{_datas}};
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

"Classe abstraite" des sous-classes de C<CTM::ReadEM>.
Pour plus de details, voir la documention POD de C<CTM::ReadEM>.

=head1 DEPENDANCES

C<CTM::Base>, C<Carp>, C<Hash::Util>

=head1 NOTES

Ce module est dedie aux sous-classes de C<CTM::ReadEM>.

=head1 AUTEUR

Le Garff Yoann <weeble@cpan.org>

=head1 LICENCE

Voir licence Perl.

=cut