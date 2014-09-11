#------------------------------------------------------------------------------------------------------
# OBJET : Installation de CTM::* et de ses dependances
#------------------------------------------------------------------------------------------------------
# APPLICATION : ControlM
#------------------------------------------------------------------------------------------------------
# AUTEUR : Yoann Le Garff
# DATE DE CREATION : 16/05/2014
# ETAT : STABLE
#------------------------------------------------------------------------------------------------------
# AIDE :
#   perldoc Makefile.PL
#------------------------------------------------------------------------------------------------------
# USAGE
#   perl Makefile.PL
#------------------------------------------------------------------------------------------------------
# DEPENDANCES OBLIGATOIRES
#   - ExtUtils::MakeMaker
#------------------------------------------------------------------------------------------------------

#-> BEGIN

#---> ** initialisation **

use strict;
use warnings;

use ExtUtils::MakeMaker 6.64, qw/WriteMakefile/;

#---> ** section principale **

WriteMakefile(
    NAME => 'CTM',
    AUTHOR => 'Le Garff Yoann <pe.weeble@yahoo.fr>',
    META_MERGE => {
        resources => {
            repository => {
                type => 'git',
                url => 'git://github.com/Le-Garff-Yoann/CTM',
                web => 'https://github.com/Le-Garff-Yoann/CTM'
            }
        }
    },
    LICENSE => 'perl',
    VERSION_FROM => 'lib/CTM/ReadEM.pm',
    MIN_PERL_VERSION => '5.6.1',
    CONFIGURE_REQUIRES => {
       'ExtUtils::MakeMaker' => 6.64
    },
    PREREQ_PM => {
        'Carp' => 0,
        'Hash::Util' => 0,
        'Exporter' => 0,
        'Date::Calc' => 6.0,
        'POSIX'  => 0,
        'Try::Tiny' => 0,
        'Perl::OSType' => 0,
        'List::MoreUtils' => 0,
        'DBI'  => 0
    },
    TEST_REQUIRES => {
        'Test::More' => 0
    },
    test => {
        TESTS => 't/*.t'
    },
    clean => {
        FILES => 'blib/* pm_to_blib MYMETA* *.bak *.old'
    }
);

#-> END

__END__

=pod

=head1 NOM

Makefile.PL

=head1 SYNOPSIS

Makefile.PL pour les modules C<CTM::*>.

=head1 DEPENDANCES

C<ExtUtils::MakeMaker>

=head1 AUTEUR

Le Garff Yoann <pe.weeble@yahoo.fr>

=head1 LICENCE

Voir licence Perl.

=cut
