#------------------------------------------------------------------------------------------------------
# OBJET : "Classe abstraite" des modules de CTM::*
#------------------------------------------------------------------------------------------------------
# APPLICATION : Control-M
#------------------------------------------------------------------------------------------------------
# AUTEUR : Yoann Le Garff
# DATE DE CREATION : 09/05/2014
# ETAT : STABLE
#------------------------------------------------------------------------------------------------------
# USAGE / AIDE
#   perldoc CTM::Base
#------------------------------------------------------------------------------------------------------
# DEPENDANCES OBLIGATOIRES
#   - Carp
#   - Hash::Util
#   - Time::Local
#------------------------------------------------------------------------------------------------------
# ATTENTION
#   "Classe abstraite" des modules de CTM::*. Ce module n'a pas pour but d'etre charge par l'utilisateur
#------------------------------------------------------------------------------------------------------

#-> BEGIN

#----> ** initialisation **

package CTM::Base;

require 5.6.1;

use strict;
use warnings;

use Carp qw/
    carp
    croak
/;
use Hash::Util qw/
    lock_hash
    unlock_hash
    lock_value
    unlock_value
/;
use Time::Local;

#----> ** variables de classe **

our $VERSION = 0.172;
our $AUTOLOAD;

#----> ** fonctions privees (mais accessibles a l'utilisateur pour celles qui ne sont pas des references) **

sub _uniqItemsArrayRef($) {
  return [keys %{{map { $_ => undef } @{+shift}}}];
}

sub _isUnix() {
    return grep /^${^O}$/i, qw/aix bsdos dgux dynixptx freebsd linux hpux irix openbsd dec_osf svr4 sco_sv svr4 unicos unicosmk solaris sunos netbsd sco3 ultrix macos rhapsody/;
}

sub _dateToPosixTimestamp($) {
    my ($year, $mon, $day, $hour, $min, $sec) = split /[\/\-\s:]+/, shift;
    my $time = eval {
        timelocal($sec, $min, $hour, $day, $mon - 1, $year);
    };
    return $time =~ /^\d+$/ ? $time : undef;
}

sub _myErrorMessage($$) {
    my ($subroutine, $message) = @_;
    return "'" . $subroutine . "()' : " . $message;
}

#----> ** methodes protegees **

#-> accesseurs/mutateurs

sub _setObjProperty {
    my ($self, $property, $value) = @_;
    if (caller->isa(__PACKAGE__)) {
        my $action = exists $self->{$property};
        $action ? unlock_value(%{$self}, $property) : unlock_hash(%{$self});
        $self->{$property} = $value;
        $action ? lock_value(%{$self}, $property) : lock_hash(%{$self});
        return 1;
    }
    carp(_myErrorMessage('_setObjProperty', "tentative d'utilisation d'une methode protegee."));
    return 0;
}

sub _addError {
    my ($self, $value) = @_;
    if (caller->isa(__PACKAGE__)) {
        unlock_value(%{$self}, '_errors');
        unshift @{$self->{_errors}}, $value;
        lock_value(%{$self}, '_errors');
        return 1;
    }
    carp(_myErrorMessage('_addError', "tentative d'utilisation d'une methode protegee."));
    return 0;
}

#----> ** methodes publiques **

#-> accesseurs/mutateurs

sub getProperty {
    my ($self, $property) = @_;
    croak(_myErrorMessage('getProperty', "usage : \$obj->getProperty(\$propertyName).")) unless (defined $property);
    $self->unshiftError();
    return $self->{$property} if (exists $self->{$property});
    carp(_myErrorMessage('getProperty', "propriete ('" . $property . "') inexistante."));
    return 0;
}

sub setPublicProperty {
    my ($self, $property, $value) = @_;
    croak(_myErrorMessage('setPublicProperty', "usage : \$obj->setPublicProperty(\$propertyName, \$value).")) unless (defined $property);
    $self->unshiftError();
    unless (exists $self->{$property}) {
        carp(_myErrorMessage('setPublicProperty', "tentative de creation d'une propriete ('" . $property . "')."));
    } elsif ((substr $property, 0, 1) eq '_') {
        carp(_myErrorMessage('setPublicProperty', "tentative de modication d'une propriete ('" . $property . "') protegee ou privee."));
    } else {
        return $self->_setObjProperty($property, $value);
    }
    return 0;
}

sub getError {
    my ($self, $arrayItem) = @_;
    my $error = $self->{_errors}->[(defined $arrayItem && $arrayItem =~ /^[\+\-]?\d+$/) ? $arrayItem : 0];
    return $error;
}

sub unshiftError {
    return shift->_addError(undef);
}

sub clearErrors {
    my $self = shift;
    unlock_value(%{$self}, '_errors');
    $self->{_errors} = [];
    lock_value(%{$self}, '_errors');
    return 1;
}

#-> Perl BuiltIn

sub AUTOLOAD {
    my $self = shift;
    if ($AUTOLOAD) {
        no strict qw/refs/;
        (my $called = $AUTOLOAD) =~ s/.*:://;
        croak("'" . $AUTOLOAD . "'() est introuvable.") unless (exists $self->{$called});
        return $self->{$called};
    }
    return undef;
}

1;

#-> END

__END__

=pod

=head1 NOM

C<CTM::Base>

=head1 SYNOPSIS

"Classe abstraite" des modules de CTM::*.
Pour plus de details, voir la documention POD de C<CTM::ReadEM>.

=head1 DEPENDANCES

C<Carp>, C<Hash::Util>, C<Time::Local>

=head1 NOTES

Ce module est dedie au module C<CTM::ReadEM>.

=head1 AUTEUR

Le Garff Yoann <weeble@cpan.org>

=head1 LICENCE

Voir licence Perl.

=cut