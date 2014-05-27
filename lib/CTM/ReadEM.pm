#@(#)------------------------------------------------------------------------------------------------------
#@(#) OBJET : Consultation de Control-M EM 6/7/8 via son SGBD
#@(#)------------------------------------------------------------------------------------------------------
#@(#) APPLICATION : Control-M EM
#@(#)------------------------------------------------------------------------------------------------------
#@(#) AUTEUR : Yoann Le Garff
#@(#) DATE DE CREATION : 17/03/2014
#@(#) ETAT : STABLE
#@(#)------------------------------------------------------------------------------------------------------

#==========================================================================================================
# USAGE / AIDE
#   perldoc CTM::ReadEM
#
# DEPENDANCES OBLIGATOIRES
#   - 'CTM::Base'
#   - 'CTM::ReadEM::_workOnBIMServices'
#   - 'Carp'
#   - 'Hash::Util'
#   - 'Exporter'
#   - 'POSIX'
#   - 'DBI'
#   - 'DBD::(Pg|mysql|Oracle|Sybase|ODBC)'
#==========================================================================================================

#-> BEGIN

#----> ** initialisation **

package CTM::ReadEM;

use strict;
use warnings;

use base qw/CTM::Base Exporter/;

use CTM::ReadEM::_workOnBIMServices 0.161;

use Carp;
use Hash::Util;
use Exporter;
use POSIX qw/strftime :signal_h/;
use DBI;

#----> ** variables de classe **

our $AUTOLOAD;
our $VERSION = 0.161;
our @EXPORT_OK = qw/
    $VERSION
    getStatusColorForService
    getNbSessionsCreated
    getNbSessionsConnected
/;

my %_sessionsState = (
    nbSessionsInstanced => 0,
    nbSessionsConnected => 0
);

#----> ** fonctions privees (mais accessibles a l'utilisateur pour celles qui ne sont pas des references) **

sub _calculStartEndDayTimeInPosixTimestamp {
    my ($time, $ctmDailyTime, $previousNextOrAll) = @_;
    if ($ctmDailyTime =~ /[\+\-]\d{4}$/) {
        #-> a mod pour +/-
        my ($ctmDailyPreviousOrNext, $ctmDailyHour, $ctmDailyMin) = (substr($ctmDailyTime, 0, 1), unpack '(a2)*', substr $ctmDailyTime, 1, 4);
        my ($minNow, $hoursNow, $dayNow, $monthNow, $yearNow) = split /\s+/, strftime('%M %H %d %m %Y', localtime $time);
        my ($previousDay, $previousDayMonth, $previousDayYear) = split /\s+/, strftime('%d %m %Y', localtime $time - 86400);
        my ($nextDay, $nextDayMonth, $nextDayYear) = split /\s+/, strftime('%d %m %Y', localtime $time + 86400);
        my ($startDayTimeInPosixTimestamp, $endDayTimeInPosixTimestamp);
        if ($hoursNow >= $ctmDailyHour && $minNow >= $ctmDailyMin) {
            $startDayTimeInPosixTimestamp = CTM::Base::_dateToPosixTimestamp($yearNow . '/' . $monthNow . '/' . $dayNow . '-' . $ctmDailyHour . ':' . $ctmDailyMin . ':' . 00);
            $endDayTimeInPosixTimestamp = CTM::Base::_dateToPosixTimestamp($nextDayYear . '/' . $nextDayMonth . '/' . $nextDay . '-' . $ctmDailyHour . ':' . $ctmDailyMin . ':' . 00);
        } else {
            $startDayTimeInPosixTimestamp = CTM::Base::_dateToPosixTimestamp($previousDayYear . '/' . $previousDayMonth . '/' . $previousDay . '-' . $ctmDailyHour . ':' . $ctmDailyMin . ':' . 00);
            $endDayTimeInPosixTimestamp = CTM::Base::_dateToPosixTimestamp($yearNow . '/' . $monthNow . '/' . $dayNow . '-' . $ctmDailyHour . ':' . $ctmDailyMin . ':' . 00);
        }
        #-< a mod pour +/-
        if (defined $startDayTimeInPosixTimestamp && defined $endDayTimeInPosixTimestamp) {
            for ($previousNextOrAll) {
                /^\*$/ && return 1, $startDayTimeInPosixTimestamp, $endDayTimeInPosixTimestamp;
                /^\+$/ && return 1, $endDayTimeInPosixTimestamp;
                return 1, $startDayTimeInPosixTimestamp;
            }
        } else {
            return 0, 1;
        }
    }
    return 0, 0;
}

my $_doesTablesExists = sub {
    my ($dbh, @tablesName) = @_;
    my @inexistingSQLTables;
    for (@tablesName) {
        my $sth = $dbh->table_info(undef, 'public', $_, 'TABLE');
        if ($sth->execute()) {
            push @inexistingSQLTables, $_ unless ($sth->fetchrow_array());
        } else {
            return 0, 0;
        }
    }
    return 1, \@inexistingSQLTables;
};

my $_getDatasCentersInfos = sub {
    my ($dbh, $verbose) = @_;
    my $sqlRequest = <<SQL;
SELECT d.data_center, d.netname, TO_CHAR(t.dt, 'YYYY/MM/DD HH:MI:SS') AS download_time_to_char, c.ctm_daily_time
FROM comm c, (
    SELECT data_center, MAX(download_time) AS dt
    FROM download
    GROUP by data_center
) t JOIN download d ON d.data_center = t.data_center AND t.dt = d.download_time
WHERE c.data_center = d.data_center
AND c.enabled = '1';
SQL
    print "> VERBOSE - \$_getDatasCentersInfos->() :\n\n" . $sqlRequest . "\n" if ($verbose);
    my $sth = $dbh->prepare($sqlRequest);
    if ($sth->execute()) {
        my $str = $sth->fetchall_hashref('data_center');
        for (values %{$str}) {
            ($_->{active_net_table_name} = $_->{netname}) =~ s/[^\d]//g;
            $_->{active_net_table_name} = 'a' . $_->{active_net_table_name} . '_ajob';
        }
        keys %{$str} ? return 1, $str : return 1, 0;
    } else {
        return 0, 0;
    }
};

my $_getBIMJobsFromActiveNetTable = sub {
    my ($dbh, $deleteFlag, $activeNetTable, $verbose) = @_;
    my @orderId;
    my $sqlRequest = <<SQL;
SELECT order_id
FROM $activeNetTable
WHERE appl_type = 'BIM'
SQL
    if ($deleteFlag) {
        $sqlRequest .= "AND delete_flag = '0';";
    } else {
        chomp $sqlRequest;
        $sqlRequest .= ';';
    }
    print "> VERBOSE - \$_getBIMJobsFromActiveNetTable->() :\n\n" . $sqlRequest . "\n" if ($verbose);
    my $sth = $dbh->prepare($sqlRequest);
    if ($sth->execute()) {
        while (my ($orderId) = $sth->fetchrow_array()) {
            push @orderId, $orderId;
        }
        return 1, \@orderId;
    } else {
        return 0, 0;
    }
};

my $_getAllServices = sub {
    my ($dbh, $jobsInformations, $datacenterInfos, $matching, $forLastNetName, $serviceStatus, $verbose) = @_;
    my (%servicesHash, @errorByNetName);
    for (keys(%{$datacenterInfos})) {
        if ($jobsInformations->{$_} && @{$jobsInformations->{$_}}) {
            my $sqlInClause = join "', '", @{$jobsInformations->{$_}};
            my $sqlRequest = <<SQL;
SELECT *, TO_CHAR(order_time, 'YYYY/MM/DD HH:MI:SS') AS order_time_to_char
FROM bim_log
WHERE log_id IN (
    SELECT MAX(log_id)
    FROM bim_log
    GROUP BY order_id
)
AND service_name LIKE '$matching'
AND order_id IN ('$sqlInClause')
SQL
            if ($forLastNetName) {
                $sqlRequest .= <<SQL;

AND active_net_name = '$datacenterInfos->{$_}->{netname}'
SQL
            }
            if (ref $serviceStatus eq 'ARRAY') {
                my @serviceSqlRequest;
                for (@{CTM::Base::_uniqItemsArrayRef($serviceStatus)}) {
                    /^OK$/ && push @serviceSqlRequest, "status_to = '4'";
                    /^Completed_OK$/ && push @serviceSqlRequest, "status_to = '8'";
                    /^Error$/ && push @serviceSqlRequest, "(status_to >= '16' AND status_to < '128')";
                    /^Warning$/ && push @serviceSqlRequest, "(status_to >= '128' AND status_to < '256')";
                    /^Completed_Late$/ && push @serviceSqlRequest, "status_to >= '256'";
                }
                $sqlRequest .= 'AND (' . join(' OR ', @serviceSqlRequest) . ")\n";
            }
            $sqlRequest .= <<SQL;
ORDER BY service_name;
SQL
            print "> VERBOSE - \$_getAllServices->() :\n\n" . $sqlRequest . "\n" if ($verbose);
            my $sth = $dbh->prepare($sqlRequest);
            if ($sth->execute()) {
                %servicesHash = (%servicesHash, %{$sth->fetchall_hashref('log_id')});
            } else {
                push @errorByNetName, $datacenterInfos->{$_}->{netname};
            }
        }
    }
    return \@errorByNetName, \%servicesHash;
};

#----> ** fonctions publiques **

sub getStatusColorForService($) {
    my $statusTo = shift;
    $statusTo = $statusTo->{status_to} if (ref $statusTo eq 'HASH');
    if (defined $statusTo && $statusTo =~ /^\d+$/) {
        if ($statusTo == 4) {
            return 'OK';
        } elsif ($statusTo == 8) {
            return 'Completed OK';
        } elsif ($statusTo >= 16 && $statusTo < 128) {
            return 'Error';
        } elsif ($statusTo >= 128 && $statusTo < 256) {
            return 'Warning';
        } elsif ($statusTo >= 256) {
            return 'Completed Late';
        }
    }
    return 0;
}

sub getNbSessionsCreated {
    return $_sessionsState{nbSessionsInstanced};
}

sub getNbSessionsConnected {
    return $_sessionsState{nbSessionsConnected};
}

#----> ** methodes privees **

#-> accesseurs/mutateurs

my $_setObjProperty = sub {
    my ($self, $property, $value) = @_;
    my $action = exists $self->{$property} ? 1 : 0;
    $action ? Hash::Util::unlock_value(%{$self}, $property) : Hash::Util::unlock_hash(%{$self});
    $self->{$property} = $value;
    $action ? Hash::Util::lock_value(%{$self}, $property) : Hash::Util::lock_hash(%{$self});
    return 1;
};

#-> constructeurs/destructeurs (methode privee)

my $_newSessionConstructor = sub {
    Carp::croak(CTM::Base::_myErrorMessage((caller 0)[3], "la methode n'est pas correctement declaree.")) unless (@_ % 2);
    my ($class, %params) = (shift, @_);
    my $self = {};
    if (exists $params{ctmEMVersion} && exists $params{DBMSType} && exists $params{DBMSAddress} && exists $params{DBMSPort} && exists $params{DBMSInstance} && exists $params{DBMSUser}) {
        $self->{_ctmEMVersion} = $params{ctmEMVersion};
        $self->{DBMSType} = $params{DBMSType};
        $self->{DBMSAddress} = $params{DBMSAddress};
        $self->{DBMSPort} = $params{DBMSPort};
        $self->{DBMSInstance} = $params{DBMSInstance};
        $self->{DBMSUser} = $params{DBMSUser};
        $self->{DBMSPassword} = exists $params{DBMSPassword} ? $params{DBMSPassword} : undef;
        $self->{DBMSTimeout} = (exists $params{DBMSTimeout} && defined $params{DBMSTimeout} && $params{DBMSTimeout} >= 0) ? $params{DBMSTimeout} : 0;
        $self->{verbose} = (exists $params{verbose} && defined $params{verbose}) ? $params{verbose} : 0;
    } else {
        Carp::croak(CTM::Base::_myErrorMessage((caller 0)[3], "la methode n'est pas correctement declaree."));
    }
    $self->{_errorMessage} = undef;
    $self->{_DBI} = undef;
    $self->{_sessionIsConnected} = 0;
    $class = ref $class || $class;
    $_sessionsState{nbSessionsInstanced}++;
    return bless $self, $class;
};

my $_workOnBIMServicesConstructor = sub {
    Carp::croak(CTM::Base::_myErrorMessage((caller 0)[3], "la methode n'est pas correctement declaree.")) unless (@_ % 2);
    my ($self, %params) = (shift, @_);
    my $subSelf = {};
    $self->clearError();
    $subSelf->{'_CTM::ReadEM'} = $self;
    $subSelf->{_working} = 0;
    $subSelf->{_errorMessage} = undef;
    $subSelf->{_params} = \%params;
    $subSelf->{_currentServices} = $self->getCurrentServices(%params);
    return bless $subSelf, 'CTM::ReadEM::_workOnBIMServices';
};

my $_connectToDB = sub {
    my $self = shift;
    $self->clearError();
    if (exists $self->{_ctmEMVersion} && exists $self->{DBMSType} && exists $self->{DBMSAddress} && exists $self->{DBMSPort} && exists $self->{DBMSInstance} && exists $self->{DBMSUser}) {
        if ($self->{_ctmEMVersion} =~ /^[678]$/ && $self->{DBMSType} =~ /^(Pg|Oracle|mysql|Sybase|ODBC)$/ && $self->{DBMSAddress} ne '' && $self->{DBMSPort} =~ /^\d+$/ && $self->{DBMSPort} >= 0  && $self->{DBMSPort} <= 65535 && $self->{DBMSInstance} ne '' && $self->{DBMSUser} ne '') {
            unless ($self->getSessionIsConnected()) {
                if (eval 'require DBD::' . $self->{DBMSType}) {
                    my $myOSIsUnix = CTM::Base::_myOSIsUnix();
                    my $ALRMDieSub = sub {
                        die "'DBI' : impossible de se connecter (timeout atteint) a la base '" . $self->{DBMSType} . ", instance '" .  $self->{DBMSInstance} . "' du serveur '" .  $self->{DBMSType} . "'.";
                    };
                    my $oldaction;
                    if ($myOSIsUnix) {
                        my $mask = POSIX::SigSet->new(SIGALRM);
                        my $action = POSIX::SigAction->new(
                            \&$ALRMDieSub,
                            $mask
                        );
                        $oldaction = POSIX::SigAction->new();
                        sigaction(SIGALRM, $action, $oldaction);
                    } else {
                        local $SIG{ALRM} = \&$ALRMDieSub;
                    }
                    $self->clearError();
                    eval {
                        my $connectionString = 'dbi:' . $self->{DBMSType};
                        if ($self->{DBMSType} eq 'ODBC') {
                            $connectionString .= ':driver={SQL Server};server=' . $self->{DBMSAddress} . ',' . $self->{DBMSPort} . ';database=' . $self->{DBMSInstance};
                        } else {
                            $connectionString .= ':host=' . $self->{DBMSAddress} . ';database=' . $self->{DBMSInstance} . ';port=' . $self->{DBMSPort};
                        }
                        $self->{_DBI} = DBI->connect(
                            $connectionString,
                            $self->{DBMSUser},
                            $self->{DBMSPassword},
                            {
                                'RaiseError' => 0,
                                'PrintError' => 0,
                                'AutoCommit' => 1
                            }
                        ) || do {
                            (my $errorMessage = "'DBI' : '" . $DBI::errstr . "'.") =~ s/\s+/ /g;
                            $self->$_setObjProperty('_errorMessage', $errorMessage);
                        };
                    };
                    alarm 0;
                    sigaction(SIGALRM, $oldaction) if ($myOSIsUnix);
                    return 0 if ($self->{_errorMessage});
                    if ($@) {
                        $self->$_setObjProperty('_errorMessage', CTM::Base::_myErrorMessage((caller 0)[3], $@));
                        return 0;
                    }
                    my ($situation, $inexistingSQLTables) = $_doesTablesExists->($self->{_DBI}, qw/bim_log bim_prob_jobs bim_alert comm download/);
                    if ($situation) {
                        unless (@{$inexistingSQLTables}) {
                            $self->$_setObjProperty('_sessionIsConnected', 1);
                            $_sessionsState{nbSessionsConnected}++;
                            return 1;
                        } else {
                            $self->$_setObjProperty('_errorMessage', CTM::Base::_myErrorMessage((caller 0)[3], "la connexion au SGBD est etablie mais il manque une ou plusieurs tables ('" . join("', '", @{$inexistingSQLTables}) . "') qui sont requises ."));
                        }
                    } else {
                        $self->$_setObjProperty('_errorMessage', CTM::Base::_myErrorMessage((caller 0)[3], "la connexion est etablie mais la ou les methodes DBI 'table_info()'/'execute()' ont echouees."));
                    }
                } else {
                    $@ =~ s/\s+/ /g;
                    $self->$_setObjProperty('_errorMessage', CTM::Base::_myErrorMessage((caller 0)[3], "impossible de charger le module 'DBD::" . $self->{DBMSType} . "' : '" . $@ . "'."));
                }
            } else {
                $self->$_setObjProperty('_errorMessage', CTM::Base::_myErrorMessage((caller 0)[3], "impossible de se connecter car cette instance est deja connectee."));
            }
        } else {
            Carp::croak(CTM::Base::_myErrorMessage((caller 0)[3], "un ou plusieurs parametres ne sont pas valides."));
        }
    } else {
        Carp::croak(CTM::Base::_myErrorMessage((caller 0)[3], "un ou plusieurs parametres ne sont pas valides."));
    }
    return 0;
};

my $_disconnectFromDB = sub {
    my $self = shift;
    $self->clearError();
    if ($self->{_sessionIsConnected}) {
        if ($self->{_DBI}->disconnect()) {
            $self->$_setObjProperty('_sessionIsConnected', 0);
            $_sessionsState{nbSessionsConnected}--;
            return 1;
        } else {
            $self->$_setObjProperty('_errorMessage', CTM::Base::_myErrorMessage((caller 0)[3], 'DBI : ' . $self->{_DBI}->errstr()));
        }
    } else {
        $self->$_setObjProperty('_errorMessage', CTM::Base::_myErrorMessage((caller 0)[3], "impossible de clore la connexion car cette instance n'est pas connectee."));
    }
    return 0;
};

#----> ** methodes publiques **

#-> wrappers de constructeurs/destructeurs

sub newSession {
    my $self = shift->$_newSessionConstructor(@_);
    Hash::Util::lock_hash(%{$self});
    return $self;
}

*new = \&newSession;

sub connectToDB {
    my $self = shift;
    Hash::Util::unlock_value(%{$self}, '_DBI');
    my $return = $self->$_connectToDB(@_);
    Hash::Util::lock_value(%{$self}, '_DBI');
    return $return;
}

sub disconnectFromDB {
    my $self = shift;
    Hash::Util::unlock_value(%{$self}, '_DBI');
    my $return = $self->$_disconnectFromDB(@_);
    Hash::Util::lock_value(%{$self}, '_DBI');
    return $return;
}

#-> methodes liees aux services du BIM

sub getCurrentServices {
    Carp::croak(CTM::Base::_myErrorMessage((caller 0)[3], "la methode n'est pas correctement declaree.")) unless (@_ % 2);
    my ($self, %params) = (shift, @_);
    $self->clearError();
    my ($situation, $datacenterInfos);
    if ($self->getSessionIsConnected()) {
        ($situation, $datacenterInfos) = $_getDatasCentersInfos->($self->{_DBI}, $self->{verbose});
        if ($situation) {
            my $time = time;
            my %jobsInformations = map { $_, undef } keys %{$datacenterInfos};
            my @activeNetTablesInError;
            for my $dataCenter (keys %{$datacenterInfos}) {
                ($situation, my $datacenterOdateStart, my $datacenterOdateEnd) = _calculStartEndDayTimeInPosixTimestamp($time, $datacenterInfos->{$dataCenter}->{ctm_daily_time}, '*');
                if ($situation) {
                    my $downloadTimeInTimestamp;
                    eval {
                        $downloadTimeInTimestamp = CTM::Base::_dateToPosixTimestamp($datacenterInfos->{$dataCenter}->{download_time_to_char});
                    };
                    unless ($downloadTimeInTimestamp == 0 || $@) {
                        if ($downloadTimeInTimestamp >= $datacenterOdateStart && $downloadTimeInTimestamp <= $datacenterOdateEnd) {
                            ($situation, $jobsInformations{$dataCenter}) = $_getBIMJobsFromActiveNetTable->($self->{_DBI}, exists $params{handleDeletedJobs} ? $params{handleDeletedJobs} : 1, $datacenterInfos->{$dataCenter}->{active_net_table_name}, $self->{verbose});
                            push @activeNetTablesInError, $datacenterInfos->{$dataCenter}->{active_net_table_name} unless ($situation);
                        } else {
                            delete $jobsInformations{$dataCenter};
                        }
                    } else {
                        $self->$_setObjProperty('_errorMessage', ($self->{_errorMessage} && $self->{_errorMessage} . ' ') . CTM::Base::_myErrorMessage((caller 0)[3], "le champ 'download_time_to_char' qui derive de la cle 'download_time' (DATETIME) via la fonction SQL TO_CHAR() (Control-M '" . $datacenterInfos->{$dataCenter}->{service_name} . "') n'est pas correct ou n'est pas gere par le module. Il est possible que la base de donnees du Control-M EM soit corrompue ou que la version renseignee (version '" . $self->{_ctmEMVersion} . "') ne soit pas correcte."));
                        return 0;
                    }
                } else {
                    if ($datacenterOdateStart) {
                        $self->$_setObjProperty('_errorMessage', ($self->{_errorMessage} && $self->{_errorMessage} . ' ') . CTM::Base::_myErrorMessage((caller 0)[3], "une erreur a eu lieu lors de la generation du timestamp POSIX pour la date de debut et de fin de la derniere montee au plan."));
                    } else {
                        $self->$_setObjProperty('_errorMessage', ($self->{_errorMessage} && $self->{_errorMessage} . ' ') . CTM::Base::_myErrorMessage((caller 0)[3], "le champ 'ctm_daily_time' du datacenter '" . $datacenterInfos->{$dataCenter}->{data_center} . "' n'est pas correct " . '(=~ /^[\+\-]\d{4}$/).'));
                    }
                    return 0;
                }
            }
            $self->$_setObjProperty('_errorMessage', CTM::Base::_myErrorMessage((caller 0)[3], "erreur lors des jobs BIM : la methode DBI 'execute()' a echoue pour une ou plusieurs tables de l'active net : '" . join(' ', @activeNetTablesInError) . "'.")) if (@activeNetTablesInError);
            ($situation, my $servicesDatas) = $_getAllServices->($self->{_DBI}, \%jobsInformations, $datacenterInfos, exists $params{matching} ? $params{matching} : '%', exists $params{forLastNetName} ? $params{forLastNetName} : 0, exists $params{forStatus} ? $params{forStatus} : 0, $self->{verbose});
            $self->$_setObjProperty('_errorMessage', ($self->{_errorMessage} && $self->{_errorMessage} . ' ') . CTM::Base::_myErrorMessage((caller 0)[3], "la methode DBI 'execute()' a echoue pour les netnames suivants : '" . join(' ', @{$situation}) . "'.")) if (@{$situation});
            return $servicesDatas;
        } else {
            $self->$_setObjProperty('_errorMessage', CTM::Base::_myErrorMessage((caller 0)[3], "erreur lors de la recuperation des informations a propos des Control-M Server : la methode DBI 'execute()' a echoue : '" . $self->{_DBI}->errstr() . "'."));
        }
    } else {
       $self->$_setObjProperty('_errorMessage', CTM::Base::_myErrorMessage((caller 0)[3], "impossible de continuer car la connexion au SGBD n'est pas active."));
    }
    return 0;
}

sub countCurrentServices {
    Carp::croak(CTM::Base::_myErrorMessage((caller 0)[3], "la methode n'est pas correctement declaree.")) unless (@_ % 2);
    my ($self, %params) = (shift, @_);
    my $getCurrentServices = $self->getCurrentServices(%params);
    ref $getCurrentServices eq 'HASH' ? return scalar keys %{$getCurrentServices} : return undef;
}

sub workOnCurrentServices {
    my $self = shift->$_workOnBIMServicesConstructor(@_);
    Hash::Util::lock_hash(%{$self});
    return $self;
}

#-> accesseurs/mutateurs

sub getSessionIsAlive {
    my $self = shift;
    if ($self->{_DBI} && $self->getSessionIsConnected()) {
        return $self->{_DBI}->ping();
    } else {
        $self->$_setObjProperty('_errorMessage', CTM::Base::_myErrorMessage((caller 0)[3], "impossible de tester l'etat de la connexion au SGBD car celle ci n'est pas active."));
        return 0;
    }
}

sub getSessionIsConnected {
    return shift->{_sessionIsConnected};
}

#-> Perl BuiltIn

sub AUTOLOAD {
    my $self = shift;
    no strict qw/refs/;
    (my $called = $AUTOLOAD) =~ s/.*:://;
    Carp::croak("'" . $AUTOLOAD . "' : la methode '" . $called . "()' n'existe pas.") unless (exists $self->{$called});
    return $self->{$called};
}

sub DESTROY {
    my $self = shift;
    $self->disconnectFromDB();
    $_sessionsState{nbSessionsInstanced}--;
}

1;

#-> END

__END__

=pod

=head1 NOM

CTM::ReadEM

=head1 SYNOPSIS

Consultation de Control-M EM 6/7/8 via son SGBD.
Voir la section EXEMPLES.

=head1 DEPENDANCES

CTM::Base, CTM::ReadEM::_workOnBIMServices, Carp, Hash::Util, Exporter, Time::Local, POSIX, DBI, /^DBD::(Pg|mysql|Oracle|Sybase|ODBC)$/

=head1 PROPRIETES PUBLIQUES (CTM::ReadEM)

=over

=item - $session-I<{DBMSType}>

Type de SGBD du Control-M EM auquel se connecter.

Les valeurs acceptees sont "Pg", "Oracle", "mysql", "Sybase" et "ODBC". Pour une connexion a MS SQL Server, les drivers "Sybase" et "ODBC" fonctionnent.

=item - $session-I<{DBMSAddress}>

Adresse du SGBD du Control-M EM auquel se connecter.

=item - $session-I<{DBMSPort}>

Port du SGBD du Control-M EM auquel se connecter.

=item - $session-I<{DBMSInstance}>

Instance (ou base) du SGBD du Control-M EM auquel se connecter.

=item - $session-I<{DBMSUser}>

Utilisateur du SGBD du Control-M EM auquel se connecter.

=item - $session-I<{DBMSPassword}>

Mot de passe du SGBD du Control-M EM auquel se connecter.

=item - $session-I<{DBMSTimeout}>

Timeout (en seconde) de la tentavive de connexion au SGBD du Control-M EM.

La valeur 0 signifie qu aucun timeout ne sera applique.

Attention, cette propriete risque de ne pas fonctionner sous Windows (ou d'autres systemes ne gerant pas les signaux UNIX).

=item - $session->I<{verbose}>

Active la verbose du module, affiche les requetes SQL executees.

Ce parametre accepte un booleen. Faux par defaut.

=back

=head1 FONCTIONS PUBLIQUES (CTM::ReadEM)

=over

=item - (BIM) - I<getStatusColorForService()>

Cette fonction permet de convertir le champ "status_to" de la table de hachage generee par la methode getCurrentServices() (et ses derives) en un status clair et surtout comprehensible ("OK", "Completed OK", "Completed Late", "Warning", "Error").

L'entier du champ "status_to" ou la reference vers un service ($servicesHashRef->{1286} par exemple) recupere depuis la methode getCurrentServices() peuvent etres passes en parametre.

Retourne 0 si le parametre fourni n'est pas correct (nombre non repertorie).

=item - (*) - I<getNbSessionsCreated()>

Retourne le nombre d instances en cours pour le module CTM::ReadEM.

=item - (*) - I<getNbSessionsConnected()>

Retourne le nombre d instances en cours et connectees a la base du Control-M EM pour le module CTM::ReadEM.

=back

=head1 METHODES PUBLIQUES (CTM::ReadEM)

=over

=item - (*) - my $session = CTM::ReadEM->I<newSession()>

Cette methode est le constructeur du module CTM::ReadEM. C<CTM::ReadEM->new()> est un equivalent.

Les parametres disponibles sont "ctmEMVersion", "DBMSType", "DBMSAddress", "DBMSPort", "DBMSInstance", "DBMSUser", "DBMSPassword", "DBMSTimeout" et "verbose" (booleen)

Pour information, le destructeur C<DESTROY()> est appele lorsque toutes les references a l'objet instancie ont ete detruites (C<undef $session;> par exemple).

Retourne toujours un objet.

=item - (*) - $session->I<connectToDB()>

Permet de se connecter a la base du Control-M EM avec les parametres fournis au constructeur C<CTM::ReadEM-E<gt>newSession()>.

Retourne 1 si la connexion a reussi sinon 0.

=item - (*) - $session->I<disconnectFromDB()>

Permet de se deconnecter de la base du Control-M EM mais elle n'apelle pas le destructeur C<DESTROY()>.

Retourne 1 si la connexion a reussi sinon 0.

=item - (BIM) - $session->I<getCurrentServices()>

Retourne une reference de la table de hachage de la liste des services en cours dans le (BIM).

Un filtre est disponible avec le parametre "matching" (SQL C<LIKE> clause).

Le parametre "forLastNetName" accepte un booleen. Si il est vrai alors cette methode ne retournera que les services avec la derniere ODATE. Faux par defaut.

Le parametre "handleDeletedJobs" accepte un booleen. Si il est vrai alors cette methode ne retournera que les services qui n'ont pas ete supprimes du plan. Vrai par defaut.

Le parametre "forStatus" doit etre une reference d'un tableau. Si c'est le cas, la methode ne retournera que les services avec les status renseignes (status valides (sensibles a la case) : "OK", "Completed_OK", "Completed_Late", "Warning", "Error") dans ce tableau.

La cle de cette table de hachage est "log_id".

Retourne 0 si la methode a echouee.

=item - (BIM) - $session->I<countCurrentServices()>

Retourne le nombre de services actuellement en cours dans le BIM.

Derive de la methode C<$session->getCurrentServices()>, elle "herite" donc de ses parametres.

Retourne C<undef> si la methode a echouee.

=over

=item - (BIM) - my $workOnServices = $session->I<workOnCurrentServices()>

Derive de la methode C<$session->getCurrentServices()>, elle "herite" donc de ses parametres.

Retourne toujours un objet.

Fonctionne de la meme maniere que la methode C<$session->getCurrentServices()> mais elle est surtout le constructeur du module C<CTM::ReadEM::_workOnBIMServices> qui met a disposition les methodes suivantes :

=item - (BIM) - $workOnServices->I<refresh()>

Rafraichi l objet C<$workOnServices> avec les parametres passes lors de la creation de l'objet C<$workOnServices>.

Retourne 1 si le rafraichissement a fonctionne ou 0 si celui-ci a echoue.

=item - (BIM) - $workOnServices->I<getSOAPEnvelope()>

Retourne une reference vers une chaine de caractere au format XML (enveloppe SOAP de la liste des services du BIM).

Retourne 0 si la methode a echouee.

=item - (BIM) - $workOnServices->I<getProblematicsJobs()>

Retourne une reference vers une table de hachage qui contient la liste des jobs Control-M problematiques pour chaque "log_id".

Retourne 0 si la methode a echouee.

=item - (BIM) - $workOnServices->I<getAlerts()>

Retourne une reference vers une table de hachage qui contient la liste des alertes pour chaque "log_id".

Retourne 0 si la methode a echouee.

=back

=item - (*) - $session->I<getSessionIsAlive()>

Verifie et retourne l'etat (booleen) de la connexion a la base du Control-M EM.

Attention, n'est pas fiable pour tous les types de SGBD (pour plus de details, voir L<http://search.cpan.org/dist/DBI/DBI.pm#ping>).

=item - (*) - $session->I<getSessionIsConnected()>

Retourne l'etat (booleen) de la connexion a la base du Control-M EM.

=back

=head1 METHODES PUBLIQUES (*)

=over

=item - (*) - $obj->I<getProperty($propertyName)>

Retourne la valeur de la propriete C<$propertyName>.

Leve une exception (C<carp()>) si celle-ci n'existe pas et retourne 0.

=item - (*) - $obj->I<setPublicProperty($propertyName, $value)>

Remplace la valeur de la propriete publique C<$propertyName> par C<$value>.

Retourne 1 si la valeur de la propriete a ete modifiee.

Leve une exception (C<carp()>) si c'est une propriete privee ou si celle-ci n'existe pas et retourne 0.

=item - (*) - $obj->I<getError()>

Retourne la derniere erreur generee (plusieurs erreurs peuvent etre presentes dans la meme chaine de caracteres retournee).

Retourne C<undef> si il n'y a pas d'erreur ou si la derniere a ete nettoyee via la methode C<$obj->clearError()>.

Une partie des erreurs sont fatales (notamment le fait de ne pas correctement utiliser les methodes/fonctions)).

=item - (*) - $obj->I<clearError()>

Remplace la valeur de la derniere erreur generee par C<undef>.

Retourne toujours 1.

=back

=head1 EXEMPLES

=over

=item - Initialiser une session au BIM du Control-M EM, s'y connecter et afficher le nombre de services "%ERP%" courants :

    use CTM::ReadEM;

    my $err;

    my $session = CTM::ReadEM->newSession(
        ctmEMVersion => 7,
        DBMSType => "Pg",
        DBMSAddress => "127.0.0.1",
        DBMSPort => 3306,
        DBMSInstance => "ctmem",
        DBMSUser => "root",
        DBMSPassword => "root"
    );

    $session->connectToDB() || die $session->getError();

    my $nbServices = $session->countCurrentServices(
        "matching" => "%ERP%"
    );

    defined ($err = $session->getError()) ? die $err : print "Il y a " . $nbServices . " *ERP* courants .\n";

=item - Initialiser plusieurs sessions :

    use CTM::ReadEM qw/getNbSessionsCreated/;

    my %sessionParams = (
        ctmEMVersion => 7,
        DBMSType => "Pg",
        DBMSAddress => "127.0.0.1",
        DBMSPort => 3306,
        DBMSInstance => "ctmem",
        DBMSUser => "root",
        DBMSPassword => "root"
    );

    my $session1 = CTM::ReadEM->newSession(%sessionParams);
    my $session2 = CTM::ReadEM->newSession(%sessionParams);

    print getNbSessionsCreated(); # affiche "2"

=item - Recupere et affiche la liste des services actuellement en cours dans le BIM du Control-M EM :

    use CTM::ReadEM qw/getStatusColorForService/;

    # [...]

    $session->connectToDB() || die $session->getError();

    my $servicesHashRef = $session->getCurrentServices();

    unless (defined ($err = $session->getError())) {
        print $_->{service_name} . " : " . getStatusColorForService($_) . "\n" for (values %{$servicesHashRef})
    } else {
        die $err;
    }

=item - Recupere et affiche l'enveloppe SOAP des services actuellement en cours et en erreur dans le BIM du Control-M EM :

    # [...]

    $session->connectToDB() || die $session->getError();

    my $workOnServices = $session->workOnCurrentServices(
        forStatus => [qw/Warning Error/]
    );

    unless (defined ($err = $session->getError())) {
        my $xmlString = $workOnServices->getSOAPEnvelope();

        die $err if (defined ($err = $session->getError()));

        print $xmlString . "\n";
    } else {
        die $err;
    }

=back

=head1 LEXIQUE

=over

=item - CTM : BMC Control-M.

=item - Control-M EM : BMC Control-M Enterprise Manager.

=item - BIM : BMC Batch Impact Manager.

=item - GAS : BMC Global Alert Server.

=back

=head1 NOTES

=over

=item - Ce module se base en partie sur l'heure du systeme qui le charge. Si celle ci est fausse, certains resultats le seront aussi.

=item - Les elements, ... prefixes de "_" sont privees et ne doivent pas etre manipules par l'utilisateur.

=item - Certaines fonctions normalements privees sont disponibles pour l'utilisateur mais ne sont pas documentees et peuvent etre fatales (pas de prototypage, pas de gestion des exceptions, ...).

=item - Les versions < 0.20 ne permettent de ne consulter que les services du BIM du Control-M EM. Le reste (Viewpoint, GAS, ...) viendra ensuite.

=item - Base Moose prevu pour la 0.20.

=back

=head1 AUTEUR

Le Garff Yoann <weeble@cpan.org>

=head1 LICENCE

Voir licence Perl.

=cut