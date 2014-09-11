CTM
===

Consultation de Control-M Enterprise Manager 6/7/8 via son SGBD.

### Installation :

``` shell
perl Makefile.PL
make
make test
make install
make clean
```
    
### Exemple :

``` perl
use CTM::ReadEM qw/:all/;

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

my $servicesHashRef = $session->getCurrentServices();

unless (defined ($err = $session->getError())) {
    print $_->{service_name} . " : " . getStatusColorForService($_) . "\n" for (values %{$servicesHashRef});
} else {
    die $err;
}
```
    
Pour toutes autres informations :

``` shell
man CTM::ReadEM || perldoc CTM::ReadEM # ou CTM::Base, CTM::Base::SubClass, etc, ...
```

### Sources disponibles sur :

- [CPAN](http://search.cpan.org/dist/CTM)
- [GitHub](http://github.com/le-garff-yoann/CTM)