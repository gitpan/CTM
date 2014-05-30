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

our $VERSION = 0.17;
our $AUTOLOAD;

#----> ** fonctions privees (mais accessibles a l'utilisateur pour celles qui ne sont pas des references) **

sub _uniqItemsArrayRef {
  return [keys %{{map { $_ => undef } @{+shift}}}];
}

sub _isUnix {
    return grep (/^${^O}$/i, qw/aix bsdos dgux dynixptx freebsd linux hpux irix openbsd dec_osf svr4 sco_sv svr4 unicos unicosmk solaris sunos netbsd sco3 ultrix macos rhapsody/);
}

sub _dateToPosixTimestamp {
    my ($year, $mon, $day, $hour, $min, $sec) = split /[\/\-\s:]+/, shift;
    my $time = eval {
        timelocal($sec, $min, $hour, $day, $mon - 1, $year);
    };
    return $time =~ /^\d+$/ ? $time : undef;
}

sub _myErrorMessage {
    my ($nameSpace, $message) = @_;
    return "'" . $nameSpace . "()' : " . $message;
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
    } else {
        carp(_myErrorMessage((caller 0)[3], "tentative d'utilisation d'une methode protegee."));
    }
    return 0;
}

sub _addError {
    my ($self, $value) = @_;
    if (caller->isa(__PACKAGE__)) {
        unlock_value(%{$self}, '_errorArrayRef');
        unshift @{$self->{_errorArrayRef}}, $value;
        lock_value(%{$self}, '_errorArrayRef');
        return 1;
    } else {
        carp(_myErrorMessage((caller 0)[3], "tentative d'utilisation d'une methode protegee."));
    }
    return 0;
}

#----> ** methodes publiques **

#-> accesseurs/mutateurs

sub getProperty {
    my ($self, $property) = @_;
    if (exists $self->{$property}) {
        return $self->{$property};
    } else {
        carp(_myErrorMessage((caller 0)[3], "propriete ('" . $property . "') inexistante."));
    }
    return 0;
}

sub setPublicProperty {
    my ($self, $property, $value) = @_;
    unless (exists $self->{$property}) {
        carp(_myErrorMessage((caller 0)[3], "tentative de creation d'une propriete ('" . $property . "')."));
    } elsif ($property =~ /^_/) {
        carp(_myErrorMessage((caller 0)[3], "tentative de modication d'une propriete ('" . $property . "') protegee ou privee."));
    }
    return $self->_setObjProperty($property, $value);
}

sub getError {
    my ($self, $arrayItem) = @_;
    my $error = $self->{_errorArrayRef}->[(defined $arrayItem && $arrayItem =~ /^[\+\-]?\d+$/) ? $arrayItem : 0];
    return defined $error ? $error : undef;
}

sub unshiftError {
    return shift->_addError(undef);
}

sub clearErrors {
    my $self = shift;
    unlock_value(%{$self}, '_errorArrayRef');
    $self->{_errorArrayRef} = [];
    lock_value(%{$self}, '_errorArrayRef');
    return 1;
}

#-> Perl BuiltIn

sub AUTOLOAD {
    my $self = shift;
    if ($AUTOLOAD) {
        no strict qw/refs/;
        (my $called = $AUTOLOAD) =~ s/.*:://;
        croak("'" . $AUTOLOAD . "' : la methode '" . $called . "()' n'existe pas.") unless (exists $self->{$called});
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