use 5.006;
use strict;
use warnings FATAL => 'all';
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'AnyEvent::DBD::mysql::Cluster',
    AUTHOR           => q{Maxim Polyakov <mmonk@cpan.org>},
    VERSION_FROM     => 'lib/AnyEvent/DBD/mysql/Cluster.pm',
    ABSTRACT_FROM    => 'lib/AnyEvent/DBD/mysql/Cluster.pm',
    LICENSE          => 'Proprietary',
    PL_FILES         => {},
    MIN_PERL_VERSION => 5.006,
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },
    BUILD_REQUIRES => {
        'Test::More' => 0,
        'AnyEvent::DBD::mysql' => 0,
        'Data::Dumper' => 0,
        'AnyEvent' => 0,
    },
    PREREQ_PM => {
        'AnyEvent::DBD::mysql' => 0,
        'AnyEvent' => 0,
        #'ABC'              => 1.6,
        #'Foo::Bar::Module' => 5.0401,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'AnyEvent-DBD-mysql-Cluster-*' },
);
