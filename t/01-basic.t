#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

use AnyEvent;
use AnyEvent::DBD::mysql::Cluster;

sub healthy_cluster_master_replica {
	my %conf = (
		servers=> [
			{dsn => { database=>'ignored', socket=>'ignored'} , user=>'ignored', password => 'ignored', role=>'master' },
			{dsn => { database=>'ignored', socket=>'ignored'} , user=>'ignored', password => 'ignored', role=>'slave' },
		],
		node_class => 'Test::AE::Mysql::Healthy',
	);
	my $cluster = AnyEvent::DBD::mysql::Cluster->new(%conf);
	return $cluster;
	
}


{
	my $cluster = healthy_cluster_master_replica;
	isa_ok($cluster, 'AnyEvent::DBD::mysql::Cluster');

	ok (!$cluster->connected, 'Cluster is not connected before connect() call');

	$cluster->connect;
	ok ($cluster->connected, 'connected() returns true when all nodes are connected');
	ok (!$cluster->readonly, 'Master-Slave pair have one connected master, readonly returns false');

	my $master = $cluster->master;
	isa_ok($master, 'Test::AE::Mysql::Healthy', 'have master node and it is a database object of the class we requested in constructor');
	my $another_master = $cluster->master;
	isa_ok($another_master, 'Test::AE::Mysql::Healthy', 'We can peek master database object even when there is only one master');

	my $slave = $cluster->slave;
	isa_ok($slave, 'Test::AE::Mysql::Healthy', 'have slave node and it is a database object of the class we requested in constructor');

	ok(\$master != \$slave, 'Master and slave are different objects') || warn Dumper $master;

	my $db = $cluster->any;
	isa_ok($db, 'Test::AE::Mysql::Healthy', 'we have cluster nodes connected, so any() should return something');

	my @cluster_nodes = $cluster->nodes;
	is (scalar @cluster_nodes,2, 'nodes return all servers regardless of are they connected or not');
}

done_testing();




package Test::AE::Mysql;
use parent 'AnyEvent::DBD::mysql'; use strict; use warnings FATAL => 'all';

our $normal_mysql_duration = 0.4;

sub new { my $pkg=shift; bless {}, $pkg};
sub connect { 1 };
sub ping { 1 };




package Test::AE::Mysql::Healthy;
use parent -norequire,'Test::AE::Mysql'; use strict; use warnings FATAL => 'all';


sub execute {  
	my ($self, $cb ) = (shift,pop);
	my $t;$t = AE::timer $normal_mysql_duration,0, sub {
		$cb->(1,{})
	}
};


1;
