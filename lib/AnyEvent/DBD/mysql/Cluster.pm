package AnyEvent::DBD::mysql::Cluster;

use 5.006;
use strict;
use warnings FATAL => 'all';
use Data::Dumper;
use List::Util 'shuffle';

=head1 NAME

AnyEvent::DBD::mysql::Cluster - Maintain cluster with number of master and replica AnyEvent::DBD::mysql instances

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

    # This is untested draft for now

    use AnyEvent::DBD::mysql::Cluster;
    my %config = (
      servers => [
        { dsn=> { database=>'dbname', host=> '127.0.0.1', port=>3307 }, master=> 1, user=>'username', password=>'tricky_password'},
        { dsn=> { database=>'dbname', host=> '127.0.0.1', port=>3308 }, master=> 0, user=>'username', password=>'tricky_password'},
      ],
      node_class => 'AnyEvent::DBD::mysql',
    );
    my $cluster_ok;

    my $cluster = AnyEvent::DBD::mysql::Cluster->new( %config, 
      one_connected       => sub { $cluster_ok=1},
      all_disconnected    => sub { $cluster_ok=0},
    );
    $cluster->connect;
    ...

    # Insert data if there is master connection available
    if (my $db = $cluster->master) {
      $db->execute('insert into table values (1)', sub { warn 'Insert returned'} );	
    }
    # Select data from any cluster node
    if (my $db = $cluster->any) {
      $db->execute('select * from table limit 10', sub { my $cnt=shift; warn "Select returned $cnt rows"} );	
    }

=head1 SUBROUTINES/METHODS

=head2 new

  Cluster constructor. Takes a parameter=>value pairs as it's input.
  Parameters:
    
    servers
    Array reference, holding configuration for every node in the cluster.
    Every node represented as a hash reference, holding required dsn, user, password keys.
    Every dsn is also a hash, with at least two keys: database, socket. 
    Or, three keys for network connection: database, host, port.
    Other parameters may be specified, such as mysql_connect_timeout.
    All dsn keys will be joined before passing them to DBD::mysql, for example:
      'database=dbname;host=127.0.0.1;port=3306'

    Optional integer weight parameter may be passed for a node. The heavier node weight,
    the more frequently it will be used for query ( by increasing probability of that node
    to be returned by any(), slave(), or master() calls)

    Server description may also include boolean 'role' key, specifying if this 
    node is a master or slave node. Default is master.

    node_class
    Optional class name, used to create database connection. Default is 'AnyEvent::DBD::mysql'
    node_class may also be redefined on a per node basis.

    one_connected => sub { my ($self, $node_number, $db_object) = @_}
      Coderef to be called for every cluster node when connected. 

    all_disconnected => sub { my ($self) = @_}
      Coderef to be called when there is no more connected nodes in the cluster

    ping_timeout
      Fractoinal number of seconds. Mysql ping should return before this number of seconds,
      otherwise node considered disconnected. This value should not be less then 20ms. Default is 20ms.

    check_interval
      Fractional number of seconds. The preriod of time after which cluster watchdog will
      try to ping every node in the cluster, checking it's availability. Default is 2 seconds.

=cut

sub new {
  my $class = shift;
  my $self = bless {
    master_class      => 'AnyEvent::DBD::mysql',
    slave_class       => 'AnyEvent::DBD::mysql',
    connected_nodes   => [],
    master_nodes      => [],
    slave_nodes       => [],
    @_,
  }, $class;
  for my $srv ( @{$self->{servers}} ) {
    $self->{expected_servers} ++;
    my $node_class = $srv->{node_class} // $self->{node_class} // 'AnyEvent::DBD::mysql';
    $srv->{weight} ||=1;
    $srv->{role} //= 'master';
    my $dsn = 'DBI:mysql:'. join( ';', map { join ('=', $_, $srv->{dsn}{$_})} keys %{$srv->{dsn}});
    my $db; $db = $node_class->new( $dsn, $srv->{user}, $srv->{password});
    $srv->{db} = $db;
  }
  $self;
}

=head2 connect

  Make persistent connection to every node in a cluster
  $cluster->connect;

  By the nature of AnyEvent::DBD::mysql this call will block untill every node gets conected.

=cut

sub connect{
  my $self = shift;
  for my $srv (@{$self->{servers}}) {
    if ( $srv->{db}->connect) {
      $self->_db_online($srv);
    }
  }
}

sub _db_online{
  my ($self, $node) = (shift,shift,shift);
  $self->_node_insert('connected_nodes', $node);
  $self->_node_insert($node->{role}.'_nodes', $node);
  
}

sub _db_offline{
}

sub _node_insert{
  my ($self, $list_name, $node) = (shift, shift, shift);
  $self->{$list_name} = [ shuffle @{ $self->{$list_name} }, ($node->{db}) x ($node->{weight}//1)];
}

=head2 disconnect

  Disconnect from all cluster nodes
  $cluster->disconnect;

=cut


=head2 any

  Peek any node in the cluster
  my $db = $cluster->any;

=cut

sub any {
  my $self=shift;
  $self->_next_db_object('connected_nodes');
}

=head2 master

  Peek any master node in the cluster
  my $db = $cluster->master;

=cut
sub master {
  my $self=shift;
  $self->_next_db_object('master_nodes');
}

=head2 slave

  Peek any slave node in the cluster
  my $db = $cluster->slave;

=cut
sub slave {
  my $self=shift;
  $self->_next_db_object('slave_nodes');
}

sub _next_db_object{
  my ($self, $list) = (shift, shift);
  return unless $list && @{$self->{$list}};
  push @{ $self->{$list} }, ( my $one = shift @{ $self->{$list} } );
  return $one;
}

=head2 readonly
  
  Returns false if there is any number of connected masters, otherwise return false
  my $may_insert = ! $cluster->readonly;

=cut
sub readonly {
  my $self = shift;
  return scalar @{$self->{master_nodes}} ? 0: 1;
}

=head2 connected
  
  Returns true if there is any connected node in the cluster
  my $cluster_ok = $cluster->connected;

=cut

sub connected {
  my $self = shift;
  return scalar @{$self->{connected_nodes}} ? 1: 0;
}

=head2 nodes

  Return all nodes passed to constructor.
  NOTICE: This function returns internal structure for each node, where database object itself 
  can be reached as $node->{db}
  for my $node ( $cluster->nodes) {
    $node->{db}->execute('select 1', sub { warn 'select returned'});
  };

  By the nature of AnyEvent::DBD::mysql this call will block untill every node gets conected.

=cut
sub nodes {
  my $self = shift;
  return @{$self->{servers}};
}


=head1 AUTHOR

Maxim Polyakov, C<< <mmonk at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-anyevent-dbd-mysql-cluster at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=AnyEvent-DBD-mysql-Cluster>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc AnyEvent::DBD::mysql::Cluster


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=AnyEvent-DBD-mysql-Cluster>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/AnyEvent-DBD-mysql-Cluster>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/AnyEvent-DBD-mysql-Cluster>

=item * Search CPAN

L<http://search.cpan.org/dist/AnyEvent-DBD-mysql-Cluster/>

=back


=head1 ACKNOWLEDGEMENTS

Thanks to Mons Anderson for great ideas found in his code for AnyEvent::Tarantool::Cluster


=head1 LICENSE AND COPYRIGHT

Copyright 2014 Maxim Polyakov.

This program is released under the following license: Proprietary


=cut

1; # End of AnyEvent::DBD::mysql::Cluster
