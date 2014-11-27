package MTW::IPCalc;

use 5.008008;
use strict;
use warnings;

=head1

MTW::IPCalc - IP calculator, thanks for usefull tool IPCalc.

=head1 SYNOPSIS

Using example:

	use MTW::IPCalc;

	my ($address, $cidr) = @ARGV;

	print "Data: $address/$cidr\n";
	print "inet_aton: ". is_ia ($address). "\n";
	print "inet_ntoa: ". is_na (is_ia ($address)). "\n";
	print "cidr2netmask: " . cidr2netmask ($cidr) . "\n";
	print "netmask2cidr: " . netmask2cidr ( cidr2netmask ($cidr) ) . "\n";
	print "is_network: " . is_network ($address, $cidr) . "\n";
	print "is_broadcast: " . is_broadcast ($address, $cidr) . "\n";
	print "host_min: " . host_min (is_network ($address, $cidr)) . "\n";
	print "host_max: " . host_max ($address, $cidr) . "\n";
	print "addrcount: " . addrcount ($cidr). "\n";

=head1 FUNCTIONS
	bin2addr($bin_ip) - convert dotted address into binary
	addr2bin($dot_ip) - convert from binary address into dotted notation

	is_ia($dot_ip) - inet_aton analog, return int value for IP
	is_na($int_ip) - inet_ntoa analog, return dotted notation for IP

	cidr2bin($cidr) - convert cidr into binary
	cidr2netmask($cidr) - convert cidr into dotted notation address
	netmask2cidr($dot_netmask) - convert dotted notation netmask into cidr

	is_network($dot_ip, $cidr) - searched for network from address and cidr
	is_broadcast($dot_ip, $cidr) - broadcast for network with cidr

	host_min($dot_network) - minimal IP address for network
	host_max($dot_ip, $cidr) - maximum IP address for network/cidr

	addrcount($cidr) - calculate how many addresses available for usage into network

=head1 DESCRIPTION

MTW::IPCalc - perl fast extension for IP conversions and calculation networks. Library includes functions for manipulate with cidr/netmask, counting hosts and other.

=head1 AUTHOR
Petrovich S Konstantin, kp@mtw.ru

=head1 END
=cut

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(
	bin2addr
	addr2bin
	is_ia
	is_na
	cidr2bin
	cidr2netmask
	netmask2cidr
	is_network
	is_broadcast
	host_min
	host_max
	addrcount
);
our $VERSION = '0.4';

# Binary conv for x.x.x.x
sub bin2addr {
	return join '.', unpack 'C4', $_[0];
}

sub addr2bin {
	return pack 'C4', split /\./, $_[0], 4;
}

# inet_aton
sub is_ia {
	return unpack 'N', pack 'C4', split /\./, $_[0];
}

# inet_ntoa
sub is_na {
	return join '.', unpack 'C4', pack 'N', $_[0];
}

sub cidr2bin {
	return pack 'B*',(1 x $_[ 0 ]) . (0 x (32 - $_[ 0 ]));
}

sub cidr2netmask {
	return bin2addr (
		cidr2bin ($_[0])
	);
}

sub netmask2cidr {
	my $nb = unpack 'B32', addr2bin ($_[0]);
	my @c = split /1/, $nb;
	my $c = @c - 1;
	return 32 if $c == -1;
	return $c;
}

sub is_network {
	return bin2addr (
		addr2bin ($_[0]) & cidr2bin ($_[1])
	);
}

sub is_broadcast {
	my ($network, $cidr) = @_;

	my $n = addr2bin (is_network ($network, $cidr));
	my $bb = $n | ~cidr2bin ($cidr);

	return bin2addr ($bb);
}

sub host_min {
	return bin2addr (
		pack ('B*', ('0'x31) . '1') | addr2bin ($_[0])
	);
}

sub host_max {
	my $n = addr2bin ($_[0]);
	my $c = $_[1];
	return bin2addr (
		pack ('B*', ('0' x $c) . ('1' x (31 - $c)) . '0') | $n
	);
}

sub addrcount {
	return 2 ** (32 - $_[0]) - 2;
}

1;
