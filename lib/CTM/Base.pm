#@(#)------------------------------------------------------------------------------------------------------
#@(#) OBJET : "Classe abstraite" des modules de CTM::*
#@(#)------------------------------------------------------------------------------------------------------
#@(#) APPLICATION : Control-M
#@(#)------------------------------------------------------------------------------------------------------
#@(#) AUTEUR : Yoann Le Garff
#@(#) DATE DE CREATION : 09/05/2014
#@(#) ETAT : STABLE
#@(#)------------------------------------------------------------------------------------------------------

#==========================================================================================================
# USAGE / AIDE
#   perldoc CTM::Base
#
# DEPENDANCES OBLIGATOIRES
#   - 'Carp'
#   - 'Hash::Util'
#   - 'Time::Local'
#
# ATTENTION
#   "Classe abstraite" des modules de CTM::*. Ce module n'a pas pour but d'etre charge par l'utilisateur
#==========================================================================================================

#-> BEGIN

#----> ** initialisation **

package CTM::Base;

require 5.6.1;

use strict;
use warnings;

use Carp;
use Hash::Util;
use Time::Local;

#----> ** variables de classe **

our $VERSION = 0.161;

#----> ** fonctions privees **

my $_setObjProperty = sub {
    my ($self, $property, $value) = @_;
    my $action = exists $self->{$property} ? 1 : 0;
    $action ? Hash::Util::unlock_value(%{$self}, $property) : Hash::Util::unlock_hash(%{$self});
    $self->{$property} = $value;
    $action ? Hash::Util::lock_value(%{$self}, $property) : Hash::Util::lock_hash(%{$self});
    return 1;
};

#-> privees mais accessibles a l'utilisateur)

sub _uniqItemsArrayRef {
  return [keys %{{map { $_ => undef } @{+shift}}}];
}

sub _myOSIsUnix {
    return grep (/^${^O}$/i, qw/aix bsdos dgux dynixptx freebsd linux hpux irix openbsd dec_osf svr4 sco_sv svr4 unicos unicosmk solaris sunos netbsd sco3 ultrix macos rhapsody/);
}

sub _dateToPosixTimestamp {
    my ($year, $mon, $day, $hour, $min, $sec) = split /[\/\-\s:]+/, shift;
    my $time = timelocal($sec, $min, $hour, $day, $mon - 1 ,$year);
    return $time =~ /^\d+$/ ? $time : undef;
}

sub _myErrorMessage {
    my ($nameSpace, $message) = @_;
    return "'" . $nameSpace . "()' : " . $message;
}

#----> ** methodes publiques **

sub getProperty {
    my ($self, $property) = @_;
    if (exists $self->{$property}) {
        return $self->{$property};
    } else {
        Carp::carp(_myErrorMessage((caller 0)[3], "propriete ('" . $property . "') inexistante."));
        return 0;
    }
}

sub setPublicProperty {
    my ($self, $property, $value) = @_;
    unless (exists $self->{$property}) {
        Carp::carp(_myErrorMessage((caller 0)[3], "tentative de creation d'une propriete ('" . $property . "')."));
    } elsif ($property =~ /^_/) {
        Carp::carp(_myErrorMessage((caller 0)[3], "tentative de modication d'une propriete ('" . $property . "') privee."));
    }
    return $self->$_setObjProperty($property, $value);
}

sub getError {
    return shift->getProperty('_errorMessage');
}

sub clearError {
    return shift->$_setObjProperty('_errorMessage', undef);
}

1;

#-> END

__END__

=pod

=head1 NOM

CTM::Base

=head1 SYNOPSIS

"Classe abstraite" des modules de CTM::*.
Pour plus de details, voir la documention POD de CTM::ReadEM.

=head1 DEPENDANCES

Carp, Hash::Util, Time::Local

=head1 NOTES

Ce module est dedie au module CTM::ReadEM.

=head1 AUTEUR

Le Garff Yoann <weeble@cpan.org>

=head1 LICENCE

Voir licence Perl.

=cut