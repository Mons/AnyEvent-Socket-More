#!/usr/bin/env perl

use lib::abs '../..';
use AnyEvent::Socket::More;
$| = 1;

my ($sock,$host,$port) = tcp_listen_socket undef,undef;
warn "$host:$port\n";

my $server = sub {
	my $n = shift;
	my $cv = AE::cv;
	$cv->begin for 1..$n;
	tcp_accept_listen($sock,sub {
		shift;
		warn "$$: incoming connection (@_), left: @{[ --$n ]}";
		$cv->end;
	});
	$cv->recv;
	exit;
};
my $client = sub {
	my $cv = AE::cv;
	tcp_connect $host,$port,sub {
		shift;
		warn "$$ client connected to @_";
		$cv->send;
	};
	$cv->recv;
	exit;
};

my @pids;
my $N = 3;

if (my $srv = fork) {
	push @pids, $srv;
} else {
	$server->($N);
	exit;
}
for (1..$N) {
	if (my $cln = fork) {
		push @pids, $cln;
	}
	else {
		$client->();
	}

}
#$SIG{CHLD} = sub { warn "@_"; };
waitpid $_,0 for @pids;
sleep 1;
