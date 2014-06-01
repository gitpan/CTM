#------------------------------------------------------------------------------------------------------
# OBJET : Consultation de Control-M EM 6/7/8 via son SGBD
#------------------------------------------------------------------------------------------------------
# APPLICATION : Control-M EM
#------------------------------------------------------------------------------------------------------
# AUTEUR : Yoann Le Garff
# DATE DE CREATION : 17/03/2014
# ETAT : STABLE
#------------------------------------------------------------------------------------------------------
# USAGE / AIDE
#   perldoc CTM::ReadEM
#------------------------------------------------------------------------------------------------------
# DEPENDANCES OBLIGATOIRES
#   - CTM::Base
#   - CTM::ReadEM::_workOnBIMServices
#   - CTM::ReadEM::_workOnAlarms
#   - CTM::ReadEM::_workOnExceptionAlerts
#   - Carp
#   - Hash::Util
#   - Exporter
#   - POSIX
#   - DBI
#   - DBD::?
#------------------------------------------------------------------------------------------------------

#-> BEGIN

#----> ** initialisation **

package CTM::ReadEM;

use strict;
use warnings;

use base qw/
    Exporter
    CTM::Base
/;

use CTM::ReadEM::_workOnBIMServices 0.173;
use CTM::ReadEM::_workOnAlarms 0.173;
use CTM::ReadEM::_workOnExceptionAlerts 0.173;

use Carp qw/
    carp
    croak
/;
use Hash::Util qw/
    lock_hash
    lock_value
    unlock_value
/;
use POSIX qw/
    :signal_h
    strftime
/;
use DBI;

#----> ** variables de classe **

our $VERSION = 0.173;
our @EXPORT_OK = qw/
    $VERSION
    getStatusColorForService
    getSeverityForAlarms
    getSeverityForExceptionAlerts
    getNbSessionsCreated
    getNbSessionsConnected
/;
our %EXPORT_TAGS = (
    all => \@EXPORT_OK
);

my %_sessionsState = (
    nbSessionsInstanced => 0,
    nbSessionsConnected => 0
);

#----> ** fonctions privees (mais accessibles a l'utilisateur pour celles qui ne sont pas des references) **

sub _calculStartEndDayTimeInPosixTimestamp($$) {
    my ($time, $ctmDailyTime) = @_;
    if ($ctmDailyTime =~ /[\+\-]\d{4}$/) {
        my ($ctmDailyPreviousOrNext, $ctmDailyHour, $ctmDailyMin) = ((substr $ctmDailyTime, 0, 1), unpack '(a2)*', substr $ctmDailyTime, 1, 4);
        # $ctmDailyPreviousOrNext : a utiliser pour la gestion du '+-' du champ 'DAYTIME'
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
        return (defined $startDayTimeInPosixTimestamp && defined $endDayTimeInPosixTimestamp) ? (1, $startDayTimeInPosixTimestamp, $endDayTimeInPosixTimestamp) : (0, 1);
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
            return 0, $dbh->errstr();
        }
    }
    return 1, \@inexistingSQLTables;
};

my $_getDatasCentersInfos = sub {
    my ($dbh, $deleteFlag, $verbose) = @_;
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
    print "VERBOSE - \$_getDatasCentersInfos->() :\n\n" . $sqlRequest . "\n" if ($verbose);
    my $sth = $dbh->prepare($sqlRequest);
    if ($sth->execute()) {
        my $hashRef = $sth->fetchall_hashref('data_center');
        for (values %{$hashRef}) {
            ($_->{active_net_table_name} = $_->{netname}) =~ s/[^\d]//g;
            $_->{active_net_table_name} = 'a' . $_->{active_net_table_name} . '_ajob';
            if ($deleteFlag) {
                $sqlRequest .= "AND delete_flag = '0';";
            } else {
                chomp $sqlRequest;
                $sqlRequest .= ';';
            }
        }
        return 1, $hashRef;
    } else {
        return 0, $dbh->errstr();
    }
};

my $_getBIMServices = sub {
    my ($dbh, $datacenterInfos, $matching, $forLastNetName, $serviceStatus, $forDataCenters, $verbose) = @_;
    if (%{$datacenterInfos}) {
        my $sqlRequest = <<SQL;
SELECT *, TO_CHAR(order_time, 'YYYY/MM/DD HH:MI:SS') AS order_time_to_char
FROM bim_log
WHERE log_id IN (
    SELECT MAX(log_id)
    FROM bim_log
    GROUP BY order_id
)
AND service_name LIKE '$matching'
AND order_id IN (
SQL
        $sqlRequest .= (join "\n    UNION\n", map { '    SELECT order_id FROM ' . $_->{active_net_table_name} . " WHERE appl_type = 'BIM'" } values %{$datacenterInfos}) . "\n)\n";
        if ($forLastNetName) {
            $sqlRequest .= "AND active_net_name IN ('" . (join "', '", map { $_->{netname} } values %{$datacenterInfos}) . "')\n";
        }
        if (ref $serviceStatus eq 'ARRAY' && @{$serviceStatus}) {
            $sqlRequest .= 'AND (' . (join ' OR ', map {
                if ($_ eq 'OK') {
                    "status_to = '4'";
                } elsif ($_ eq 'Completed_OK') {
                    "status_to = '8'";
                } elsif ($_ eq 'Error') {
                    "(status_to >= '16' AND status_to < '128')";
                } elsif ($_ eq 'Warning') {
                    "(status_to >= '128' AND status_to < '256')";
                } elsif ($_ eq 'Completed_Late') {
                    "status_to >= '256'";
                }
            } @{CTM::Base::_uniqItemsArrayRef($serviceStatus)}) . ")\n";
        }
        if (ref $forDataCenters eq 'ARRAY' && @{$forDataCenters}) {
            $sqlRequest .= 'AND (' . (join ' OR ', map { "data_center = '" . $_ . "'" } @{CTM::Base::_uniqItemsArrayRef($forDataCenters)}) . ")\nORDER BY service_name;\n";
        }
        print "VERBOSE - \$_getBIMServices->() :\n\n" . $sqlRequest if ($verbose);
        my $sth = $dbh->prepare($sqlRequest);
        if ($sth->execute()) {
            return 1, $sth->fetchall_hashref('log_id');
        } else {
            return 0, $sth->errstr();
        }
    }
    return 0, undef;
};

my $_getAlarms = sub {
    my ($dbh, $matching, $severity, $limit, $timeSort, $verbose) = @_;
    my $sqlRequest = <<SQL;
SELECT *, TO_CHAR(upd_time, 'YYYY/MM/DD HH:MI:SS') AS upd_time_to_char
FROM alarm
WHERE message LIKE '$matching'
SQL
    if (ref $severity eq 'ARRAY' && @{$severity}) {
        $sqlRequest .= 'AND (' . (join ' OR ', map {
            if ($_ eq 'Regular') {
                "severity = 'R'";
            } elsif ($_ eq 'Urgent') {
                "severity = 'U'";
            } elsif ($_ eq 'Very_Urgent') {
                "severity = 'V'";
            }
        } @{CTM::Base::_uniqItemsArrayRef($severity)}) . ")\nORDER BY upd_time " . $timeSort;
    }
    $sqlRequest .= $limit ? "\nLIMIT " . $limit . ";\n" : ";\n";
    print "VERBOSE - \$getAlarms->() :\n\n" . $sqlRequest if ($verbose);
    my $sth = $dbh->prepare($sqlRequest);
    if ($sth->execute()) {
        my $hashRef = $sth->fetchall_hashref('serial');
        return 1, $hashRef;
    } else {
        return 0, $dbh->errstr();
    }
};

my $_getExceptionAlerts = sub {
    my ($dbh, $matching, $severity, $limit, $timeSort, $verbose) = @_;
    my $sqlRequest = <<SQL;
SELECT *, TO_CHAR(xtime, 'YYYY/MM/DD HH:MI:SS') AS xtime_to_char, TO_CHAR(xtime_of_last, 'YYYY/MM/DD HH:MI:SS') AS xtime_of_last_to_char
FROM exception_alerts
WHERE message LIKE '$matching'
SQL
    if (ref $severity eq 'ARRAY' && @{$severity}) {
        $sqlRequest .= 'AND (' . (join ' OR ', map {
            if ($_ eq 'Warning') {
                "xseverity = '3'";
            } elsif ($_ eq 'Error') {
                "xseverity = '2'";
            } elsif ($_ eq 'Severe') {
                "xseverity = '1'";
            }
        } @{CTM::Base::_uniqItemsArrayRef($severity)}) . ")\nORDER BY xtime " . $timeSort;
    }
    $sqlRequest .= $limit ? "\nLIMIT " . $limit . ";\n" : ";\n";
    print "VERBOSE - \$getExceptionAlerts->() :\n\n" . $sqlRequest if ($verbose);
    my $sth = $dbh->prepare($sqlRequest);
    if ($sth->execute()) {
        my $hashRef = $sth->fetchall_hashref('serial');
        return 1, $hashRef;
    } else {
        return 0, $dbh->errstr();
    }
};

#----> ** fonctions publiques **

sub getStatusColorForService($) {
    my $statusTo = shift;
    $statusTo = $statusTo->{status_to} if (ref $statusTo eq 'HASH');
    if (defined $statusTo && $statusTo =~ /^\d+$/) {
        for ($statusTo) {
            $_ == 4 && return 'OK';
            $_ == 8 && return 'Completed OK';
            ($_ >= 16 && $_ < 128) && return 'Error';
            ($_ >= 128 && $_ < 256) && return 'Warning';
            ($_ >= 256) && return 'Completed Late';
        }
    }
    return 0;
}

sub getSeverityForAlarms($) {
    my $severity = shift;
    $severity = $severity->{severity} if (ref $severity eq 'HASH');
    if (defined $severity) {
        for ($severity) {
            $_ eq 'R' && return 'Regular';
            $_ eq 'U' && return 'Urgent';
            $_ eq 'V' && return 'Very Urgent';
        }
    }
    return 0;
}

sub getSeverityForExceptionAlerts($) {
    my $xSeverity = shift;
    $xSeverity = $xSeverity->{xseverity} if (ref $xSeverity eq 'HASH');
    if (defined $xSeverity && $xSeverity =~ /^\d+$/) {
        for ($xSeverity) {
            $_ == 3 && return 'Warning';
            $_ == 2 && return 'Error';
            $_ == 1 && return 'Severe';
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

#-> constructeurs/destructeurs (methode privee)

my $_newSessionConstructor = sub {
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
        $self->{DBMSTimeout} = $params{DBMSTimeout} || 0;
        $self->{verbose} = $params{verbose} || 0;
    } else {
        croak(CTM::Base::_myErrorMessage('newSession', "un ou plusieurs parametres obligatoires n'ont pas ete renseignes."));
    }
    $self->{_errors} = [];
    $self->{_DBI} = undef;
    $self->{_sessionIsConnected} = 0;
    $class = ref $class || $class;
    $_sessionsState{nbSessionsInstanced}++;
    return bless $self, $class;
};

my $_subClassConstructor = sub {
    my ($self, $SubClass, $baseMethod, %params) = (shift, @_);
    my $subSelf = {};
    $subSelf->{'_CTM::ReadEM'} = $self;
    $subSelf->{_working} = 0;
    $subSelf->{_errors} = [];
    $subSelf->{_params} = \%params;
    $subSelf->{_datas} = $self->$baseMethod(%params);
    return bless $subSelf, $SubClass;
};

my $_connectToDB = sub {
    my $self = shift;
    $self->unshiftError();
    if (exists $self->{_ctmEMVersion} && exists $self->{DBMSType} && exists $self->{DBMSAddress} && exists $self->{DBMSPort} && exists $self->{DBMSInstance} && exists $self->{DBMSUser} && exists $self->{DBMSTimeout}) {
        if (($self->{_ctmEMVersion} eq '6' || $self->{_ctmEMVersion} eq '7' || $self->{_ctmEMVersion} eq '8') && ($self->{DBMSType} eq 'Pg' || $self->{DBMSType} eq 'Oracle' || $self->{DBMSType} eq 'mysql' || $self->{DBMSType} eq 'Sybase' || $self->{DBMSType} eq 'ODBC') && $self->{DBMSAddress} ne '' && $self->{DBMSPort} =~ /^\d+$/ && $self->{DBMSPort} >= 0 && $self->{DBMSPort} <= 65535 && $self->{DBMSInstance} ne '' && $self->{DBMSUser} ne '' && $self->{DBMSTimeout} =~ /^\d+$/) {
            unless ($self->getSessionIsConnected()) {
                if (eval 'require DBD::' . $self->{DBMSType}) {
                    my $myOSIsUnix = CTM::Base::_isUnix();
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
                    eval {
                        my $connectionString = 'dbi:' . $self->{DBMSType};
                        if ($self->{DBMSType} eq 'ODBC') {
                            $connectionString .= ':driver={SQL Server};server=' . $self->{DBMSAddress} . ',' . $self->{DBMSPort} . ';database=' . $self->{DBMSInstance};
                        } else {
                            $connectionString .= ':host=' . $self->{DBMSAddress} . ';database=' . $self->{DBMSInstance} . ';port=' . $self->{DBMSPort};
                        }
                        alarm $self->{DBMSTimeout};
                        $self->{_DBI} = DBI->connect(
                            $connectionString,
                            $self->{DBMSUser},
                            $self->{DBMSPassword},
                            {
                                RaiseError => 0,
                                PrintError => 0,
                                AutoCommit => 1
                            }
                        ) || do {
                            (my $errorMessage = "'DBI' : '" . $DBI::errstr . "'.") =~ s/\s+/ /g;
                            $self->_addError($errorMessage);
                        };
                    };
                    alarm 0;
                    sigaction(SIGALRM, $oldaction) if ($myOSIsUnix);
                    return 0 if ($self->getError());
                    if ($@) {
                        $self->_addError(CTM::Base::_myErrorMessage('connectToDB', $@));
                        return 0;
                    }
                    my ($situation, $inexistingSQLTables) = $_doesTablesExists->($self->{_DBI}, qw/bim_log bim_prob_jobs bim_alert comm download alarm exception_alerts/);
                    if ($situation) {
                        unless (@{$inexistingSQLTables}) {
                            $self->_setObjProperty('_sessionIsConnected', 1);
                            $_sessionsState{nbSessionsConnected}++;
                            return 1;
                        } else {
                            $self->_addError(CTM::Base::_myErrorMessage('connectToDB', "la connexion au SGBD est etablie mais il manque une ou plusieurs tables ('" . (join "', '", @{$inexistingSQLTables}) . "') qui sont requises ."));
                        }
                    } else {
                        $self->_addError(CTM::Base::_myErrorMessage('connectToDB', "la connexion est etablie mais la ou les methodes DBI 'execute()' ont echouees : '" . $inexistingSQLTables . "'."));
                    }
                } else {
                    $@ =~ s/\s+/ /g;
                    $self->_addError(CTM::Base::_myErrorMessage('connectToDB', "impossible de charger le module 'DBD::" . $self->{DBMSType} . "' : '" . $@ . "'."));
                }
            } else {
                $self->_addError(CTM::Base::_myErrorMessage('connectToDB', "impossible de se connecter car cette instance est deja connectee."));
            }
        } else {
            croak(CTM::Base::_myErrorMessage('connectToDB', "un ou plusieurs parametres ne sont pas valides."));
        }
    } else {
        croak(CTM::Base::_myErrorMessage('connectToDB', "un ou plusieurs parametres ne sont pas valides."));
    }
    return 0;
};

my $_disconnectFromDB = sub {
    my $self = shift;
    $self->unshiftError();
    if ($self->{_sessionIsConnected}) {
        if ($self->{_DBI}->disconnect()) {
            $self->_setObjProperty('_sessionIsConnected', 0);
            $_sessionsState{nbSessionsConnected}--;
            return 1;
        } else {
            $self->_addError(CTM::Base::_myErrorMessage('disconnectFromDB', 'DBI : ' . $self->{_DBI}->errstr()));
        }
    } else {
        $self->_addError(CTM::Base::_myErrorMessage('disconnectFromDB', "impossible de clore la connexion car cette instance n'est pas connectee."));
    }
    return 0;
};

#----> ** methodes publiques **

#-> wrappers de constructeurs/destructeurs

sub newSession {
    croak(CTM::Base::_myErrorMessage('newSession', "usage : la methode n'est pas correctement declaree (une cle, une valeur).")) unless (@_ % 2);
    my $self = shift->$_newSessionConstructor(@_);
    lock_hash(%{$self});
    return $self;
}

*new = \&newSession;

sub connectToDB {
    my $self = shift;
    unlock_value(%{$self}, '_DBI');
    my $return = $self->$_connectToDB(@_);
    lock_value(%{$self}, '_DBI');
    return $return;
}

sub disconnectFromDB {
    my $self = shift;
    unlock_value(%{$self}, '_DBI');
    my $return = $self->$_disconnectFromDB(@_);
    lock_value(%{$self}, '_DBI');
    return $return;
}

#-> methodes liees aux services du BIM

sub getCurrentServices {
    croak(CTM::Base::_myErrorMessage('getCurrentServices', "usage : la methode n'est pas correctement declaree (une cle, une valeur).")) unless (@_ % 2);
    my ($self, %params) = (shift, @_);
    $self->unshiftError();
    if ($self->getSessionIsConnected()) {
        my ($situation, $datacenterInfos) = $_getDatasCentersInfos->($self->{_DBI}, exists $params{handleDeletedJobs} ? $params{handleDeletedJobs} : 0, $self->{verbose});
        if ($situation) {
            my $time = time;
            for my $datacenter (keys %{$datacenterInfos}) {
                ($situation, my $datacenterOdateStart, my $datacenterOdateEnd) = _calculStartEndDayTimeInPosixTimestamp($time, $datacenterInfos->{$datacenter}->{ctm_daily_time});
                if ($situation) {
                    if (defined (my $downloadTimeInTimestamp = CTM::Base::_dateToPosixTimestamp($datacenterInfos->{$datacenter}->{download_time_to_char}))) {
                        delete $datacenterInfos->{$datacenter} unless ($downloadTimeInTimestamp >= $datacenterOdateStart && $downloadTimeInTimestamp <= $datacenterOdateEnd);
                    } else {
                        $self->_addError(CTM::Base::_myErrorMessage('getCurrentServices', "le champ 'download_time_to_char' qui derive de la cle 'download_time' (DATETIME) via la fonction SQL TO_CHAR() (Control-M '" . $datacenterInfos->{$datacenter}->{service_name} . "') n'est pas correct ou n'est pas gere par le module. Il est possible que la base de donnees du Control-M EM soit corrompue ou que la version renseignee (version '" . $self->{_ctmEMVersion} . "') ne soit pas correcte."));
                        return 0;
                    }
                } else {
                    if ($datacenterOdateStart) {
                        $self->_addError(CTM::Base::_myErrorMessage('getCurrentServices', "une erreur a eu lieu lors de la generation du timestamp POSIX pour la date de debut et de fin de la derniere montee au plan."));
                    } else {
                        $self->_addError(CTM::Base::_myErrorMessage('getCurrentServices', "le champ 'ctm_daily_time' du datacenter '" . $datacenterInfos->{$datacenter}->{data_center} . "' n'est pas correct " . '(=~ /^[\+\-]\d{4}$/).'));
                    }
                    return 0;
                }
            }
            ($situation, my $servicesDatas) = $_getBIMServices->($self->{_DBI}, $datacenterInfos, exists $params{matching} && defined $params{matching} ? $params{matching} : '%', exists $params{forLastNetName} ? $params{forLastNetName} : 0, exists $params{forStatus} ? $params{forStatus} : 0, exists $params{forDataCenters} ? $params{forDataCenters} : 0, $self->{verbose});
            unless ($situation) {
                if (defined $servicesDatas) {
                    $self->_addError(CTM::Base::_myErrorMessage('getCurrentServices', "erreur lors de la recuperation des services du BIM : la methode DBI 'execute()' a echoue : '" . $servicesDatas . "'."));
                    return 0;
                } else {
                    return {};
                }
            }
            return $servicesDatas;
        } else {
            $self->_addError(CTM::Base::_myErrorMessage('getCurrentServices', "erreur lors de la recuperation des informations a propos des Control-M Server : la methode DBI 'execute()' a echoue : '" . $datacenterInfos . "'."));
        }
    } else {
       $self->_addError(CTM::Base::_myErrorMessage('getCurrentServices', "impossible de continuer car la connexion au SGBD n'est pas active."));
    }
    return 0;
}

sub workOnCurrentServices {
    croak(CTM::Base::_myErrorMessage('workOnCurrentServices', "usage : la methode n'est pas correctement declaree (une cle, une valeur).")) unless (@_ % 2);
    my $self = shift->$_subClassConstructor('CTM::ReadEM::_workOnBIMServices', 'getCurrentServices', @_);
    lock_hash(%{$self});
    return $self;
}

#-> methodes liees aux alarmes

sub getAlarms {
    croak(CTM::Base::_myErrorMessage('getAlarms', "usage : la methode n'est pas correctement declaree (une cle, une valeur).")) unless (@_ % 2);
    my ($self, %params) = (shift, @_);
    $self->unshiftError();
    if ($self->getSessionIsConnected()) {
        my ($situation, $alarmsData) = $_getAlarms->($self->{_DBI}, exists $params{matching} && defined $params{matching} ? $params{matching} : '%', exists $params{severity} ? $params{severity} : 0, exists $params{limit} && defined $params{limit} && $params{limit} =~ /^\d+$/ ? $params{limit} : 0, exists $params{timeSort} && defined $params{timeSort} && $params{timeSort} =~ /^ASC|DESC$/i ? $params{timeSort} : 'ASC', $self->{verbose});
        if ($situation) {
            return $alarmsData;
        } else {
            $self->_addError(CTM::Base::_myErrorMessage('getAlarms', "erreur lors de la recuperation des informations a propos des exceptions : la methode DBI 'execute()' a echoue : '" . $alarmsData . "'."));
        }
    } else {
        $self->_addError(CTM::Base::_myErrorMessage('getAlarms', "impossible de continuer car la connexion au SGBD n'est pas active."));
    }
    return 0;
}

sub workOnAlarms {
    croak(CTM::Base::_myErrorMessage('workOnAlarms', "usage : la methode n'est pas correctement declaree (une cle, une valeur).")) unless (@_ % 2);
    my $self = shift->$_subClassConstructor('CTM::ReadEM::_workOnAlarms', 'getAlarms', @_);
    lock_hash(%{$self});
    return $self;
}

#-> methodes liees aux exceptions

sub getExceptionAlerts {
    croak(CTM::Base::_myErrorMessage('getExceptionAlerts', "usage : la methode n'est pas correctement declaree (une cle, une valeur).")) unless (@_ % 2);
    my ($self, %params) = (shift, @_);
    $self->unshiftError();
    if ($self->getSessionIsConnected()) {
        my ($situation, $exceptionAlertsDatas) = $_getExceptionAlerts->($self->{_DBI}, exists $params{matching} && defined $params{matching} ? $params{matching} : '%', exists $params{severity} ? $params{severity} : 0, exists $params{limit} && defined $params{limit} && $params{limit} =~ /^\d+$/ ? $params{limit} : 0, exists $params{timeSort} && defined $params{timeSort} && $params{timeSort} =~ /^ASC|DESC$/i ? $params{timeSort} : 'ASC', $self->{verbose});
        if ($situation) {
            return $exceptionAlertsDatas;
        } else {
            $self->_addError(CTM::Base::_myErrorMessage('getExceptionAlerts', "erreur lors de la recuperation des informations a propos des exceptions : la methode DBI 'execute()' a echoue : '" . $exceptionAlertsDatas . "'."));
        }
    } else {
        $self->_addError(CTM::Base::_myErrorMessage('getExceptionAlerts', "impossible de continuer car la connexion au SGBD n'est pas active."));
    }
    return 0;
}

sub workOnExceptionAlerts {
    croak(CTM::Base::_myErrorMessage('workOnExceptionAlerts', "usage : la methode n'est pas correctement declaree (une cle, une valeur).")) unless (@_ % 2);
    my $self = shift->$_subClassConstructor('CTM::ReadEM::_workOnExceptionAlerts', 'getExceptionAlerts', @_);
    lock_hash(%{$self});
    return $self;
}

#-> accesseurs/mutateurs

sub getSessionIsAlive {
    my $self = shift;
    $self->unshiftError();
    if ($self->{_DBI} && $self->getSessionIsConnected()) {
        return $self->{_DBI}->ping();
    } else {
        $self->_addError(CTM::Base::_myErrorMessage('getSessionIsAlive', "impossible de tester l'etat de la connexion au SGBD car celle ci n'est pas active."));
    }
    return 0;
}

sub getSessionIsConnected {
    return shift->{_sessionIsConnected};
}

#-> Perl BuiltIn

BEGIN {
    *AUTOLOAD = \&CTM::Base::AUTOLOAD;
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

C<CTM::Base>, C<CTM::ReadEM::_workOnBIMServices>, C<CTM::ReadEM::_workOnAlarms>, C<CTM::ReadEM::_workOnExceptionAlerts>, C<Carp>, C<Hash::Util>, C<Exporter>, C<Time::Local>, C<POSIX>, C<DBI>, C<DBD::?>

=head1 PROPRIETES PUBLIQUES (C<CTM::ReadEM>)

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

=head1 FONCTIONS PUBLIQUES (importables depuis C<CTM::ReadEM>)

=over

=item - (BIM) - I<getStatusColorForService()>

Cette fonction permet de convertir le champ "status_to" de la table de hachage generee par la methode C<getCurrentServices()> (et ses derives) en un status lisible ("OK", "Completed OK", "Completed Late", "Warning", "Error").

Retourne 0 si la valeur du parametre fourni n'est pas reconnu.

=item - (GAS) - I<getSeverityForAlarms()>

Cette fonction permet de convertir le champ "status_to" de la table de hachage generee par la methode C<getAlarms()> (et ses derives) en un status lisible ("Regular", "Urgent", "Very_Urgent").

Retourne 0 si la valeur du parametre fourni n'est pas reconnu.

=item - (EA) - I<getSeverityForExceptionAlerts()>

Cette fonction permet de convertir le champ "status_to" de la table de hachage generee par la methode C<getExceptionAlerts()> (et ses derives) en un status lisible ("Warning", "Error", "Severe").

Retourne 0 si la valeur du parametre fourni n'est pas reconnu.

=item - (*) - I<getNbSessionsCreated()>

Retourne le nombre d instances en cours pour le module C<CTM::ReadEM>.

=item - (*) - I<getNbSessionsConnected()>

Retourne le nombre d instances en cours et connectees a la base du Control-M EM pour le module C<CTM::ReadEM>.

=back

=head1 METHODES PUBLIQUES (C<CTM::ReadEM>)

=over

=item - (*) - my $session = CTM::ReadEM->I<newSession()>

Cette methode est le constructeur du module C<CTM::ReadEM>. C<CTM::ReadEM-E<gt>new()> est un equivalent.

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

Retourne une reference de la table de hachage de la liste des services en cours dans le BIM.

Un filtre est disponible avec le parametre "matching" (SQL C<LIKE> clause).

Le parametre "forLastNetName" accepte un booleen. Si il est vrai alors cette methode ne retournera que les services avec la derniere ODATE. Faux par defaut.

Le parametre "handleDeletedJobs" accepte un booleen. Si il est vrai alors cette methode ne retournera que les services qui n'ont pas ete supprimes du plan. Vrai par defaut.

Le parametre "forStatus" doit etre une reference d'un tableau. Si c'est le cas, la methode ne retournera que les services avec les status renseignes (status valides (sensibles a la case) : "OK", "Completed_OK", "Completed_Late", "Warning", "Error") dans ce tableau.

Le parametre "forDataCenters" doit etre une reference d'un tableau. Si c'est le cas, la methode ne retournera que les services pour les datacenters renseignes.

La cle de cette table de hachage est "log_id".

Retourne 0 si la methode a echouee.

=item - (BIM) - my $workOnServices = $session->I<workOnCurrentServices()>

Derive de la methode C<$session-E<gt>getCurrentServices()>, elle "herite" donc de ses parametres.

Retourne toujours un objet.

Fonctionne de la meme maniere que la methode C<$session-E<gt>getCurrentServices()> mais elle est surtout le constructeur du module C<CTM::ReadEM::_workOnBIMServices> qui met a disposition les methodes suivantes :

=over

=item - (BIM) - $workOnServices->I<countItems()>

Retourne le nombre de services pour l'objet C<$workOnServices>.

=item - (BIM) - $workOnServices->I<getItems()>

Retourne une reference de la table de hachage de la liste des services de l'objet C<$workOnServices>.

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

=item - (GAS) - $session->I<getAlarms()>

Retourne une reference de la table de hachage de la liste des alarmes en cours dans le GAS.

Un filtre est disponible sur le message des alarmes avec le parametre "matching" (SQL C<LIKE> clause).

Le parametre "severity" doit etre une reference d'un tableau. Si c'est le cas, la methode ne retournera que les alarmes avec les pour les severites renseignees (severites valides (sensibles a la case) : "Regular", "Urgent", "Very_Urgent") dans ce tableau.

Le parametre "timeSort" : SQL C<ORDER BY> . Il trie les donnees renvoyees de maniere ascendante (SQL C<ASC> (insensible a la case)) ou descendante (SQL C<DESC> (insensible a la case)) sur la date de l'alerte.

Le parametre "limit" : SQL C<LIMIT>. Il prend un entier comme valeur (pas d'interval "n,n").

La cle de cette table de hachage est "serial".

Retourne 0 si la methode a echouee.

=item - (GAS) - my $workOnAlarms = $session->I<workOnAlarms()>

Derive de la methode C<$session-E<gt>getAlarms()>, elle "herite" donc de ses parametres.

Retourne toujours un objet.

Fonctionne de la meme maniere que la methode C<$session-E<gt>getAlarms()> mais elle est surtout le constructeur du module C<CTM::ReadEM::_workOnAlarms> qui met a disposition les methodes suivantes :

=over

=item - (GAS) - $workOnAlarms->I<countItems()>

Retourne le nombre d'alarmes pour l'objet C<$workOnAlarms>.

=item - (GAS) - $workOnAlarms->I<getItems()>

Retourne une reference de la table de hachage de la liste des alarmes de l'objet C<$workOnAlarms>.

=item - (GAS) - $workOnAlarms->I<refresh()>

Rafraichi l objet C<$workOnAlarms> avec les parametres passes lors de la creation de l'objet C<$workOnAlarms>.

Retourne 1 si le rafraichissement a fonctionne ou 0 si celui-ci a echoue.

=back

=item - (EA) - $session->I<getExceptionAlerts()>

Retourne une reference de la table de hachage de la liste des alertes en cours dans l'EA.

Un filtre est disponible sur le message des alertes avec le parametre "matching" (SQL C<LIKE> clause).

Le parametre "severity" doit etre une reference d'un tableau. Si c'est le cas, la methode ne retournera que les alertes avec les pour les severites renseignees (severites valides (sensibles a la case) : "Warning", "Error", "Severe") dans ce tableau.

Le parametre "timeSort" : SQL C<ORDER BY> . Il trie les donnees renvoyees de maniere ascendante (SQL C<ASC> (insensible a la case)) ou descendante (SQL C<DESC> (insensible a la case)) sur la date de l'alerte.

Le parametre "limit" : SQL C<LIMIT>. Il prend un entier comme valeur (pas d'interval "n,n").

La cle de cette table de hachage est "serial".

Retourne 0 si la methode a echouee.

=item - (EA) - my $workOnExceptionAlerts = $session->I<workOnExceptionAlerts()>

Derive de la methode C<$session-E<gt>getExceptionAlerts()>, elle "herite" donc de ses parametres.

Retourne toujours un objet.

Fonctionne de la meme maniere que la methode C<$session-E<gt>getExceptionAlerts()> mais elle est surtout le constructeur du module C<CTM::ReadEM::_workOnExceptionAlerts> qui met a disposition les methodes suivantes :

=over

=item - (EA) - $workOnExceptionAlerts->I<countItems()>

Retourne le nombre d'alertes pour l'objet C<$workOnExceptionAlerts>.

=item - (EA) - $workOnExceptionAlerts->I<getItems()>

Retourne une reference de la table de hachage de la liste des alertes de l'objet C<$workOnExceptionAlerts>.

=item - (EA) - $workOnExceptionAlerts->I<refresh()>

Rafraichi l objet C<$workOnExceptionAlerts> avec les parametres passes lors de la creation de l'objet C<$workOnExceptionAlerts>.

Retourne 1 si le rafraichissement a fonctionne ou 0 si celui-ci a echoue.

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

=item - (*) - $obj->I<getError($item)>

Retourne l'erreur a l'element C<$item> (0 par defaut, donc la derniere erreur generee) du tableau de la reference '_errors'.

Retourne C<undef> si il n'y a pas d'erreur ou si la derniere a ete decalee via la methode C<$obj-E<gt>unshiftError()>.

Une partie des erreurs sont gerees via le module Carp et ses deux fonctions C<croak> et C<carp> (notamment le fait de ne pas correctement utiliser les methodes/fonctions)).

=item - (*) - $obj->I<unshiftError()>

Decale la valeur de la derniere erreur et la remplace par C<undef>.

Retourne toujours 1.

Cette methode est appelee avant l'execution des methodes C<connectToDB()>, C<disconnectFromDB()>, C<getCurrentServices()>, C<getAlarms()>, C<getExceptionAlerts()>, C<getSessionIsAlive()>, C<getProperty()> et C<setPublicProperty()>.

=item - (*) - $obj->I<clearErrors()>

Nettoie toutes les erreurs.

Retourne toujours 1.

=back

=head1 EXEMPLES

=over

=item - Initialiser plusieurs sessions :

    use CTM::ReadEM qw/:all/;

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
        print "J'ai " . $workOnServices->countItems() . " services avec le status 'qw/Warning Error/' en cours dont voici l'enveloppe SOAP :\n"
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

=item - Control-M CM : BMC Control-M Configuration Manager.

=item - BIM : BMC Batch Impact Manager.

=item - GAS : BMC Global Alert Server.

=item - EA : Control-M CM Exception Alerts.

=back

=head1 NOTES

=over

=item - Ce module se base en partie sur l'heure du systeme qui le charge. Si celle ci est fausse, certains resultats le seront aussi.

=item - Les elements prefixes de "_" sont proteges ou prives et ne doivent pas etre manipules par l'utilisateur.

=item - Certaines fonctions normalements privees sont disponibles pour l'utilisateur mais ne sont pas documentees et peuvent etre fatales (pas forcement de prototypage, pas de gestion des exceptions, etc, ...).

=item - Base Moose prevu pour la 0.20.

=back

=head1 AUTEUR

Le Garff Yoann <weeble@cpan.org>

=head1 LICENCE

Voir licence Perl.

=cut