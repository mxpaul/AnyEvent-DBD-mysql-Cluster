#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'AnyEvent::DBD::mysql::Cluster' ) || print "Bail out!\n";
}

diag( "Testing AnyEvent::DBD::mysql::Cluster $AnyEvent::DBD::mysql::Cluster::VERSION, Perl $], $^X" );
