#!/usr/bin/perl
#------------------------------------------------------------------------------------------------------
# OBJET : Test pour CTM::ReadEM. Instanciation de la classe CTM::ReadEM
#------------------------------------------------------------------------------------------------------
# APPLICATION : Control-M
#------------------------------------------------------------------------------------------------------
# AUTEUR : Yoann Le Garff
# DATE DE CREATION : 20/07/2014
# ETAT : STABLE
#------------------------------------------------------------------------------------------------------
# AIDE :
#   perldoc 01init.t
#------------------------------------------------------------------------------------------------------
# DEPENDANCES OBLIGATOIRES
#   - Test::More
#   - CTM::ReadEM
#------------------------------------------------------------------------------------------------------

#-> BEGIN

#---> ** initialisation **

use strict;
use warnings;

use Test::More tests => 3;

#---> ** section principale **

my $session;

my %params = (
    ctmEMVersion => 7,
    DBMSType => 'Pg',
    DBMSAddress => '127.0.0.1',
    DBMSPort => 5432,
    DBMSInstance => 'ctmem',
    DBMSUser => 'root',
    DBMSPassword => 'root'
);

BEGIN {
    use_ok('CTM::ReadEM', ':all');
}

eval {
    $session = CTM::ReadEM->new(%params);
};

ok( ! $@ && defined $session && ref $session eq 'CTM::ReadEM', 'eval { CTM::ReadEM->new(%params) }; ! $@ && defined $session && ref $session eq \'CTM::ReadEM\';');
ok(getNbSessionsCreated() == 1, 'getNbSessionsCreated() == 1;');

#-> END

__END__

=pod

=head1 NOM

01init.t

=head1 SYNOPSIS

Test pour C<CTM::ReadEM>. Instanciation de la classe C<CTM::ReadEM>.

=head1 DEPENDANCES

C<Test::More>, C<CTM::ReadEM>

=head1 AUTEUR

Le Garff Yoann <pe.weeble@yahoo.fr>

=head1 LICENCE

Voir licence Perl.

=cut
