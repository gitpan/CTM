#------------------------------------------------------------------------------------------------------
# OBJET : "Classe abstraite" des sous-modules ou sous-classes de CTM::ReadEM
# APPLICATION : Control-M
# AUTEUR : Yoann Le Garff
# DATE DE CREATION : 09/05/2014
#------------------------------------------------------------------------------------------------------
# USAGE / AIDE
#   perldoc CTM::Base::SubClass
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
/;
use String::Util qw/
    crunch
/;
use Hash::Util qw/
    lock_hash
    unlock_hash
/;
use Storable qw/
    dclone
/;

#----> ** variables de classe **

our $VERSION = 0.18;

#----> ** methodes privees **

my $_clone = sub {
    my $self = shift;
    my $clone = {
        CTM::Base::_CLASS_INFOS->{common}->{rootClass}->{propertyName} => $self->getParentClass(),
        CTM::Base::_CLASS_INFOS->{common}->{objectProperties}->{subClassDatas}->{name} => dclone($self->getItems()),
        CTM::Base::_CLASS_INFOS->{common}->{objectProperties}->{parameters}->{name} => dclone($self->getParams()),
        CTM::Base::_CLASS_INFOS->{common}->{objectProperties}->{errors}->{name} => dclone($self->getErrors()),
        CTM::Base::_CLASS_INFOS->{common}->{objectProperties}->{working}->{name} => 0
    };
    return bless $clone, ref $self;
};

#----> ** methodes protegees **

sub _resetAndRefresh {
    my ($self, $workMethod) = @_;
    if (caller->isa(__PACKAGE__)) {
        sleep 1 while ($self->_isWorking());
        my $selfTemp = $self->getParentClass()->$workMethod(
            %{$self->getParams()}
        );
        my $_errorsTemp = $self->getErrors();
        $self = $selfTemp;
        unlock_hash(%{$self});
        $self->{CTM::Base::_CLASS_INFOS->{common}->{objectProperties}->{errors}->{name}} = $_errorsTemp;
        lock_hash(%{$self});
        return 1;
    } else {
        carp(CTM::Base::_myErrorMessage((caller 0)[3], "tentative d'utilisation d'une methode protegee."));
    }
    return 0;
}

#-> methodes en rapport avec les alarmes/alertes

sub _setSerials {
    my ($self, $childSub, $sqlRequest, $serialID) = @_;
    my $subName = (caller 0)[3];
    if (caller->isa(__PACKAGE__)) {
        $self->_tagAtWork;
        $self->unshiftError();
        if ($self->getParentClass()->isSessionSeemAlive()) {
            my @serialID = ($serialID eq 'ARRAY' && @{$serialID}) ? @{$serialID} : keys %{$self->getItems()};
            if (@serialID) {
                my $sth = $self->getParentClass()->_DBI()->prepare($sqlRequest . ' WHERE serial IN (' . join(', ', ('?') x @serialID) . ')');
                $self->getParentClass()->_invokeVerbose($subName, "\n". $sth->{Statement} . "\n");
                if ($sth->execute(@serialID)) {
                    $self->_tagAtRest;
                    return 1;
                } else {
                    $self->_addError(CTM::Base::_myErrorMessage($childSub, "la connexion est etablie mais la methode DBI 'do()' a echouee : '" . crunch($self->getParentClass()->_DBI()->errstr()) . "'."));
                }
            }
        } else {
            $self->_addError(CTM::Base::_myErrorMessage($childSub, "impossible de continuer car la connexion au SGBD n'est pas active."));
        }
        $self->_tagAtRest;
    } else {
        carp(CTM::Base::_myErrorMessage($subName, "tentative d'utilisation d'une methode protegee."));
    }
    return 0;
}

#----> ** methodes publiques **

sub clone {
    my $selfClone = shift->$_clone();
    lock_hash(%{$selfClone});
    return $selfClone;
}

sub countItems {
    my $self = shift;
    return scalar keys %{$self->getItems()};
}

#-> accesseurs/mutateurs

sub getParentClass {
    my $self = shift;
    return $self->{CTM::Base::_CLASS_INFOS->{common}->{rootClass}->{propertyName}};
}

sub getParams {
    my $self = shift;
    return $self->{CTM::Base::_CLASS_INFOS->{common}->{objectProperties}->{parameters}->{name}};
}

sub getItems {
    my $self = shift;
    return ref $self->{CTM::Base::_CLASS_INFOS->{common}->{objectProperties}->{subClassDatas}->{name}} eq 'HASH' ? $self->{CTM::Base::_CLASS_INFOS->{common}->{objectProperties}->{subClassDatas}->{name}} : {};
}

sub keepItemsWithAnd {
    my ($self, $properties) = @_;
    my $subName = (caller 0)[3];
    if (ref $properties eq 'HASH') {
        while (my ($itemId, $item) = each %{$self->getItems()}) {
            while (my ($property, $expr) = each %{$properties}) {
                if (defined $item->{$property} && ref $expr eq 'ARRAY' && @{$expr}) {
                    delete $self->getItems()->{$itemId} unless (eval join ' ', map { /^\$_$/ ? $item->{$property} : $_ } @{$expr});
                }
            }
        }
    } else {
        croak(CTM::Base::_myErrorMessage($subName, CTM::Base::_myUsageMessage('$obj->' . $subName, "{ 'property' => 'expr' }")));
    }
    return $self;
}

sub keepItemsWithOr {
    my ($self, $properties) = @_;
    my $subName = (caller 0)[3];
    if (ref $properties eq 'HASH') {
        my %test;
        while (my ($itemId, $item) = each %{$self->getItems()}) {
            $test{$itemId} = {};
            while (my ($property, $expr) = each %{$properties}) {
                if (defined $item->{$property} && ref $expr eq 'ARRAY' && @{$expr}) {
                    $test{$itemId}->{$property} = eval join ' ', map { /^\$_$/ ? $item->{$property} : $_ } @{$expr};
                }
            }
        }
        for (keys %test) {
            delete $self->getItems()->{$_} unless (grep $_, values %{$self->getItems()->{$_}});
        }
    } else {
        croak(CTM::Base::_myErrorMessage($subName, CTM::Base::_myUsageMessage('$obj->' . $subName, "{ 'property' => 'expr' }")));
    }
    return $self;
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

CTM::Base::SubClass

=head1 SYNOPSIS

"Classe abstraite" des sous-modules ou sous-classes C<CTM::ReadEM>.
Pour plus de details, voir la documention POD de C<CTM::ReadEM>.

=head1 DEPENDANCES DIRECTES

C<CTM::Base>

C<Carp>

C<String::Util>

C<Hash::Util>

C<Storable>

=head1 NOTES

Ce module est dedie aux sous-modules ou sous-classes C<CTM::ReadEM>.

=head1 LIENS

- Depot GitHub : http://github.com/le-garff-yoann/CTM

=head1 AUTEUR

Le Garff Yoann <pe.weeble@yahoo.fr>

=head1 LICENCE

Voir licence Perl.

=cut
