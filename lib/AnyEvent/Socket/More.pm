package AnyEvent::Socket::More;

use 5.008008;
use common::sense 2;m{
use strict;
use warnings;
};

=head1 NAME

AnyEvent::Socket::More - AnyEvent::Socket. Extended

=cut

our $VERSION = '0.01'; $VERSION = eval($VERSION);

=head1 SYNOPSIS

    package Sample;
    use AnyEvent::Socket::More;

    my ($sock,$host,$port) = tcp_listen localhost => 80;
    
    # fork, fork ...
    
    tcp_accept($sock, sub {
        ...
    });

=head1 DESCRIPTION

This module contain 2 additional functions: C<tcp_listen> (that creates listen socket) and C<tcp_accept> (that accepts connections on listen socket)
They both are the same as L<AnyEvent::Socket/tcp_server>, but splitted in 2 parts.

=over 4

=item $sock, [$host, $port] = tcp_listen $host, $service[, $prepare_cb]

Create and bind a stream socket to the given host, and port, set the
SO_REUSEADDR flag (if applicable) and call C<listen>. Unlike the name
implies, this function can also bind on UNIX domain sockets.

For internet sockets, C<$host> must be an IPv4 or IPv6 address (or
C<undef>, in which case it binds either to C<0> or to C<::>, depending
on whether IPv4 or IPv6 is the preferred protocol, and maybe to both in
future versions, as applicable).

To bind to the IPv4 wildcard address, use C<0>, to bind to the IPv6
wildcard address, use C<::>.

The port is specified by C<$service>, which must be either a service name or
a numeric port number (or C<0> or C<undef>, in which case an ephemeral
port will be used).

For UNIX domain sockets, C<$host> must be C<unix/> and C<$service> must be
the absolute pathname of the socket. This function will try to C<unlink>
the socket before it tries to bind to it. See SECURITY CONSIDERATIONS,
below.

Croaks on any errors it can detect before the listen.

If you need more control over the listening socket, you can provide a
C<< $prepare_cb->($fh, $host, $port) >>, which is called just before the
C<listen ()> call, with the listen file handle as first argument, and IP
address and port number of the local socket endpoint as second and third
arguments.

It should return the length of the listen queue (or C<0> for the default (128)).

Note to IPv6 users: RFC-compliant behaviour for IPv6 sockets listening on
C<::> is to bind to both IPv6 and IPv4 addresses by default on dual-stack
hosts. Unfortunately, only GNU/Linux seems to implement this properly, so
if you want both IPv4 and IPv6 listening sockets you should create the
IPv6 socket first and then attempt to bind on the IPv4 socket, but ignore
any C<EADDRINUSE> errors.

Example: bind on some TCP port on the local machine and tell each client
to go away.

   my $sock = tcp_listen undef, undef, sub {
      my ($fh, $thishost, $thisport) = @_;
      warn "bound to $thishost, port $thisport\n";
      return 0;
   };

=item $guard = tcp_accept $sock, $accept_cb;

For each new connection that could be C<accept>ed, call the C<<
$accept_cb->($fh, $host, $port) >> with the file handle (in non-blocking
mode) as first, and the peer host and port as second and third arguments
(see C<tcp_connect> for details).

If called in non-void context, then this function returns a guard object
whose lifetime it tied to the TCP server: If the object gets destroyed,
the server will be stopped (but existing accepted connections will
not be affected).

Example: Accept connections on listen socket

   tcp_accept $sock, sub {
      my ($fh, $host, $port) = @_;

      syswrite $fh, "The internet is full, $host:$port. Go away!\015\012";
   };

=cut

use Carp ();
use AnyEvent ();
use AnyEvent::Util qw(fh_nonblocking AF_INET6 guard);
use AnyEvent::Socket;

BEGIN {
	our @ISA = 'AnyEvent::Socket';
	our @EXPORT = ( @AnyEvent::Socket::EXPORT, 'tcp_listen', 'tcp_accept' );
}

use Errno ();
use Socket qw(AF_INET AF_UNIX SOCK_STREAM SOCK_DGRAM SOL_SOCKET SO_REUSEADDR);


sub tcp_listen ($$;$) {
	my ($host, $service, $prepare) = @_;
	$host = $AnyEvent::PROTOCOL{ipv4} < $AnyEvent::PROTOCOL{ipv6} && AF_INET6 ? "::" : "0" unless defined $host;
	
	my $ipn = parse_address $host
		or Carp::croak "AnyEvent::Socket::More::tcp_listen: cannot parse '$host' as host address";
	
	my $af = address_family $ipn;
	
	# win32 perl is too stupid to get this right :/
	Carp::croak "tcp_listen/socket: address family not supported"
		if AnyEvent::WIN32 && $af == AF_UNIX;
	
	socket my $fh, $af, SOCK_STREAM, 0 or Carp::croak "tcp_listen/socket: $!";
	
	if ($af == AF_INET || $af == AF_INET6) {
		setsockopt $fh, SOL_SOCKET, SO_REUSEADDR, 1
			or Carp::croak "tcp_listen/so_reuseaddr: $!"
				unless AnyEvent::WIN32; # work around windows bug
		
		unless ($service =~ /^\d*$/) {
			$service = (getservbyname $service, "tcp")[2]
				or Carp::croak "tcp_listen: $service: service unknown"
		}
	} elsif ($af == AF_UNIX) {
		unlink $service;
	}
	
	bind $fh, AnyEvent::Socket::pack_sockaddr( $service, $ipn )
		or Carp::croak "tcp_listen/bind: $!";
	
	fh_nonblocking $fh, 1;
	
	my $backlog;
	if ($prepare) {
		my ($service, $host) = AnyEvent::Socket::unpack_sockaddr getsockname $fh;
		$backlog = $prepare->($fh, format_address $host, $service);
	}
	
	listen $fh, $backlog || 128
		or Carp::croak "tcp_listen/listen: $!";
	
	return wantarray ? do {
		my ($service, $host) = AnyEvent::Socket::unpack_sockaddr( getsockname $fh );
		($fh, format_address $host, $service);
	} : $fh;
}

sub tcp_accept ($$) {
	my ($fh, $accept) = @_;
	
	my %state = ( fh => $fh );
	$state{aw} = AE::io $state{fh}, 0, sub {
		# this closure keeps $state alive
		while ($state{fh} && (my $peer = accept my $fh, $state{fh})) {
			fh_nonblocking $fh, 1; # POSIX requires inheritance, the outside world does not
			
			my ($service, $host) = AnyEvent::Socket::unpack_sockaddr $peer;
			$accept->($fh, format_address $host, $service);
		}
	};
	
	defined wantarray
		? guard { %state = () } # clear fh and watcher, which breaks the circular dependency
		: ()
}

=back

=head1 AUTHOR

Mons Anderson, C<< <mons@cpan.org> >>

Based on Marc Lehmann's L<AnyEvent::Socket>

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

=cut

1;
