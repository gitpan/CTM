#------------------------------------------------------------------------------------------------------
# OBJET : "Classe abstraite" des modules de CTM
# APPLICATION : Control-M
# AUTEUR : Yoann Le Garff
# DATE DE CREATION : 09/05/2014
#------------------------------------------------------------------------------------------------------
# USAGE / AIDE
#   perldoc CTM::Base
#------------------------------------------------------------------------------------------------------

#-> BEGIN

#----> ** initialisation **

package CTM::Base;

use 5.6.1;

use strict;
use warnings;

use constant {
    _CLASS_INFOS => {
        common => {
            rootClass => {
                name => 'CTM::ReadEM',
                propertyName => '_CTM::ReadEM'
            },
            baseClass => {
                name => 'CTM::Base'
            },
            baseSubClass => {
                name => 'CTM::Base::SubClass'
            },
            objectProperties => {
                verbose => {
                    name => 'verbose'
                },
                working => {
                    name => '_working'
                },
                errors => {
                    name => '_errors'
                },
                DBI => {
                    name => '_DBI'
                },
                sessionIsConnected => {
                    name => '_sessionIsConnected'
                },
                parameters => {
                    name => '_params'
                },
                subClassDatas => {
                    name => '_datas'
                }
            }
        },
        rootClass => {
            classProperties => {
                nbSessionsInstanced => {
                    name => 'nbSessionsInstanced'
                },
                nbSessionsConnected => {
                    name => 'nbSessionsConnected'
                }
            }
        },
        BIMCurrentBIMServices => {
            moduleLastName => 'WorkOnCurrentBIMServices',
            baseMethod => 'getCurrentBIMServices',
            workMethod => 'workOnCurrentBIMServices'
        },
        GASAlarms => {
            moduleLastName => 'WorkOnAlarms',
            baseMethod => 'getAlarms',
            workMethod => 'workOnAlarms'
        },
        GASExceptionAlerts => {
            moduleLastName => 'WorkOnExceptionAlerts',
            baseMethod => 'getExceptionAlerts',
            workMethod => 'workOnExceptionAlerts'
        },
        CMComponents => {
            moduleLastName => 'WorkOnComponents',
            baseMethod => 'getComponents',
            workMethod => 'workOnComponents'
        }
    }
};

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

#----> ** variables de classe **

our $VERSION = 0.18;
our $AUTOLOAD;

#----> ** fonctions privees (mais accessibles a l'utilisateur pour celles qui ne sont pas des references) **

sub _myErrorMessage($$) {
    my ($subroutine, $message) = @_;
    return "'" . $subroutine . "()' : " . $message;
}

sub _myUsageMessage($$) {
    my ($namespace, $properties) = @_;
    return 'USAGE : ' . (split(/::/, $namespace))[-1] . '(' . $properties . ').';
}

#----> ** methodes protegees **

sub _invokeVerbose {
    my ($self, $subroutine, $message) = @_;
    if (caller->isa(__PACKAGE__)) {
        printf STDERR "VERBOSE - '%s()' : %s", $subroutine, $message if ($self->{_CLASS_INFOS->{common}->{objectProperties}->{verbose}->{name}});
    } else {
        carp(_myErrorMessage((caller 0)[3], "tentative d'utilisation d'une methode protegee."));
    }
    return 0;
}

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

sub _isWorking {
    my $self = shift;
    if (caller->isa(__PACKAGE__)) {
        return $self->{_CLASS_INFOS->{common}->{objectProperties}->{working}->{name}};
    } else {
        carp(_myErrorMessage((caller 0)[3], "tentative d'utilisation d'une methode protegee."));
    }
    return 0;
}

sub _tagAtWork {
    my $self = shift;
    if (caller->isa(__PACKAGE__)) {
        return $self->_setObjProperty(_CLASS_INFOS->{common}->{objectProperties}->{working}->{name}, 1);
    } else {
        carp(_myErrorMessage((caller 0)[3], "tentative d'utilisation d'une methode protegee."));
    }
    return 0;
}

sub _tagAtRest {
    my $self = shift;
    if (caller->isa(__PACKAGE__)) {
        return $self->_setObjProperty(_CLASS_INFOS->{common}->{objectProperties}->{working}->{name}, 0);
    } else {
        carp(_myErrorMessage((caller 0)[3], "tentative d'utilisation d'une methode protegee."));
    }
    return 0;
}

sub _addError {
    my ($self, $value) = @_;
    if (caller->isa(__PACKAGE__)) {
        unlock_value(%{$self}, _CLASS_INFOS->{common}->{objectProperties}->{errors}->{name});
        unshift @{$self->getErrors()}, $value;
        lock_value(%{$self}, _CLASS_INFOS->{common}->{objectProperties}->{errors}->{name});
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
    my $subName = (caller 0)[3];
    croak(_myErrorMessage($subName, _myUsageMessage('$obj->' . $subName, '$definedPropertyName'))) unless (defined $property);
    $self->unshiftError();
    return $self->{$property} if (exists $self->{$property});
    carp(_myErrorMessage($subName, "propriete ('" . $property . "') inexistante."));
    return 0;
}

sub setPublicProperty {
    my ($self, $property, $value) = @_;
    my $subName = (caller 0)[3];
    croak(_myErrorMessage($subName, _myUsageMessage('$obj->' . $subName, '$definedPropertyName, $definedValue'))) unless (defined $property);
    $self->unshiftError();
    unless (exists $self->{$property}) {
        carp(_myErrorMessage($subName, "tentative de creation d'une propriete ('" . $property . "')."));
    } elsif (substr($property, 0, 1) eq '_') {
        carp(_myErrorMessage($subName, "tentative de modication d'une propriete ('" . $property . "') protegee ou privee."));
    } else {
        return $self->_setObjProperty($property, $value);
    }
    return 0;
}

sub getErrors {
    return shift->{_CLASS_INFOS->{common}->{objectProperties}->{errors}->{name}};
}

sub getError {
    my ($self, $arrayItem) = @_;
    return $self->getErrors()->[(defined $arrayItem && $arrayItem =~ /^[\+\-]?\d+$/) ? $arrayItem : 0];
}

sub countErrors {
    my $self = shift;
    return scalar @{$self->getErrors()};
}

sub unshiftError {
    return shift->_addError(undef);
}

sub clearErrors {
    my $self = shift;
    unlock_value(%{$self}, _CLASS_INFOS->{common}->{objectProperties}->{errors}->{name});
    delete @{$self->getErrors()}[0..@{$self->getErrors()}];
    lock_value(%{$self}, _CLASS_INFOS->{common}->{objectProperties}->{errors}->{name});
    return 1;
}

#-> Perl BuiltIn

sub AUTOLOAD {
    my $self = shift;
    if ($AUTOLOAD) {
        no strict qw/refs/;
        (my $called = $AUTOLOAD) =~ s/.*:://;
        croak("'" . $AUTOLOAD . "()' est introuvable.") unless (exists $self->{$called});
        return $self->{$called};
    }
    return undef;
}

1;

#-> END

__END__

=pod

=head1 NOM

CTM::Base

=head1 SYNOPSIS

"Classe abstraite" des modules de C<CTM>.
Pour plus de details, voir la documention POD de C<CTM::ReadEM>.

=head1 DEPENDANCES DIRECTES

C<Carp>

C<Hash::Util>

=head1 NOTES

Ce module est dedie aux modules C<CTM>.

=head1 LIENS

- Depot GitHub : http://github.com/le-garff-yoann/CTM

=head1 AUTEUR

Le Garff Yoann <pe.weeble@yahoo.fr>

=head1 LICENCE

Voir licence Perl.

=cut
