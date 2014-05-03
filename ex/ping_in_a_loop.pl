#!/usr/bin/perl
use strict;
use warnings;

use FindBin;
use lib
	"$FindBin::Bin/../lib",
	glob("$FindBin::Bin/../libs/*/lib"),
	glob("$FindBin::Bin/../libs/*/blib/lib"),
	glob("$FindBin::Bin/../libs/*/blib/arch"),
;
use EV;
use AnyEvent;
use AnyEvent::DBD::mysql;
use AnyEvent::DBD::mysql::Cluster;
use Data::Dumper;
use Time::HiRes qw(time);


my $timeout=0.1;
my %config= (
	servers=> [
		{ dsn=> { qw(database aetest host 127.0.0.1 port 4492 mysql_connect_timeout 1 mysql_read_timeout 2 mysql_write_timeout 2)}, user=>'aetester', password=>'passwd', weight=>1 },
		{ dsn=> { qw(database aetest host 127.0.0.1 port 3308 mysql_connect_timeout 1 mysql_read_timeout 2 mysql_write_timeout 2)}, user=>'aetester', password=>'passwd', weight=>1 },
	]
);

sub debug {
	use feature 'state'; state $start; $start//=time;
	my $msg = sprintf (shift @_, @_);
	my $now = time;
	printf "[%.6f] [+%.6f] %s\n", $now, $now - $start, $msg;
	$start=$now;
}

sub fatal{ debug @_; die @_; }

{
	no warnings 'once';
	*AnyEvent::DBD::mysql::ping_async = sub {
		my ($self, $cb) = (shift, pop);
		my $t;$t= AE::timer $timeout, 0, sub { debug 'timeout';undef $t; $cb->(0)};
		$self->execute('select 1', sub { 
			return unless $t; undef $t;
			$cb->(0) unless (@_);
			my ($count, $sth) = (shift, shift);
			$cb->( $count ? 1 : 0 );
		});
	};
}

my $cluster = AnyEvent::DBD::mysql::Cluster->new(%config);
$cluster->connect;

$cluster->connected or fatal "Can not connect to mysql cluster";

my $ping_result;
my $next_ping; $next_ping = sub {
	my $db = $cluster->any;
	debug 'Send ping';
	$db->ping_async(sub {
		$ping_result = shift;
		debug "ping result: %s", $ping_result ? 'success' : 'fail';
		my $delay; $delay = AE::timer 1, 0, sub {
			undef $delay;
			$next_ping->();
		};
	});
};
$next_ping->();

EV::loop;
