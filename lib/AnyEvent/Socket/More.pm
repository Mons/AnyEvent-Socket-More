package AnyEvent::Socket::More;

use 5.008008;
use common::sense 2;m{
use strict;
use warnings;
};

=head1 NAME

AnyEvent::Socket::More - AnyEvent::Socket. Extended

=cut

our $VERSION = '0.02'; $VERSION = eval($VERSION);

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

=item $sock, [$host, $port] = udp_listen $host, $service[, $prepare_cb]

Create and bind an UDP datagram socket to the given host, and port, set the
SO_REUSEADDR flag (if applicable). Unlike the name
implies, this function can also bind on UNIX domain sockets.

Example:

    my $fh = udp_listen( '127.0.0.1', 7777 );
    

=item $guard = udp_accept $sock [, $buffersize = 65536 ], $readcb->(\$message);

Waits for messages on udp socket, reads them and invoke callback with a
reference to message buffer

Example:

    my $fh = udp_listen( '127.0.0.1', 7777 );
    # fork some times
    if ($child) {
        udp_accept $fh, 4096, sub {
            my $rmsg = shift;
            say "Received message: ".$$rmsg;
        }
    }

Also simple AE::io watcher may be used insted

    my $w = AE::io $fh, 0, sub {
        while(recv $fh, $buffersize, $flags) {
            # ...
        }
    }

=item $guard = udp_server $host, $service [, $buffersize = 65536, $prepace_cb->($fh) ], $readcb->(\$message);

Simple concatenation of udp_listen + udp_accept;

Example:

    udp_server 'localhost', 1234, 4096, sub {
        my $rmsg = shift;
        say "Received message: ".$$rmsg;
    };

=item $guard = udp_connect $host, $service, $prepare_cb, $callback

Call equivalent to tcp_connect but with SOCK_DGRAM and IPPROTO_UDP

Example:

    udp_connect localhost => 1234, sub {
        my $fh = shift;
        my $io;$io = AE::io $fh, 1, sub {
            send( $fh, "Message", 0 );
            undef $io;
        };
    };

=cut

use Carp ();
use AnyEvent ();
use AnyEvent::Util qw(fh_nonblocking AF_INET6 guard);
use AnyEvent::Socket;

BEGIN {
	our @ISA = 'AnyEvent::Socket';
	our @EXPORT = ( @AnyEvent::Socket::EXPORT, 'tcp_listen', 'tcp_accept', 'udp_listen', 'udp_server', 'udp_connect' );
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

sub udp_listen ($$;$) {
	my ($host, $service, $prepare) = @_;
	$host = $AnyEvent::PROTOCOL{ipv4} < $AnyEvent::PROTOCOL{ipv6} && AF_INET6 ? "::" : "0" unless defined $host;
	
	my $ipn = parse_address $host
		or Carp::croak "AnyEvent::Socket::More::udp_listen: cannot parse '$host' as host address";
	
	my $af = address_family $ipn;
	
	# win32 perl is too stupid to get this right :/
	Carp::croak "udp_listen/socket: address family not supported"
		if AnyEvent::WIN32 && $af == AF_UNIX;
	
	
	socket my $fh, $af, SOCK_DGRAM, getprotobyname("udp") or Carp::croak "udp_listen/socket: $!";
	
	if ($af == AF_INET || $af == AF_INET6) {
		setsockopt $fh, SOL_SOCKET, SO_REUSEADDR, 1
			or Carp::croak "udp_listen/so_reuseaddr: $!"
				unless AnyEvent::WIN32; # work around windows bug
		
		unless ($service =~ /^\d*$/) {
			$service = (getservbyname $service, "udp")[2]
				or Carp::croak "udp_listen: $service: service unknown"
		}
	} elsif ($af == AF_UNIX) {
		unlink $service;
	}
	
	bind $fh, AnyEvent::Socket::pack_sockaddr( $service, $ipn )
		or Carp::croak "udp_listen/bind: $!";
	
	fh_nonblocking $fh, 1;
	
	my $backlog;
	if ($prepare) {
		my ($service, $host) = AnyEvent::Socket::unpack_sockaddr getsockname $fh;
		$backlog = $prepare->($fh, format_address $host, $service);
	}
	
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

sub udp_accept ($$;$) { # fh, read, sub
	my $fh = shift;
	my $cb = pop;
	my $read = @_ && $_[0] > 0 ? shift : 65536;
	my %state = ( fh => $fh );
	$state{aw} = AE::io $state{fh}, 0, sub {
		while (recv $state{fh}, my $buf, $read, 0) {
			$cb->(\$buf);
		}
	};
	defined wantarray
		? guard { %state = () } # clear fh and watcher, which breaks the circular dependency
		: ()
}

sub udp_server($$$;$$) {
	my $cb = pop;
	my ($host,$port) = splice @_, 0, 2;
	my ($read, $prepare);
	if (@_ == 2) {
		($read, $prepare) = @_;
	}
	elsif ( @_ == 1 and ref $_[0] eq 'SUB') {
		$prepare = shift;
	}
	elsif ( @_ == 1 and $_[0] > 0) {
		$read = $_[0];
	}
	elsif ($_ == 1) {
		Carp::croak "udp_server: bad argument 4: $_[0]";
	}
	
	my $fh = &udp_listen($host,$port,$prepare);
	udp_accept($fh, $read, $cb);
}

sub udp_connect($$$;$) {
	my ($host, $port, $connect, $prepare) = @_;
	my %state = ( fh => undef );
	# name/service to type/sockaddr resolution
	AnyEvent::Socket::resolve_sockaddr $host, $port, "udp", 0, SOCK_DGRAM, sub {
		my @target = @_;
		$state{next} = sub {
			return unless exists $state{fh};
			my $errno = $!;
			my $target = shift @target
				or return AE::postpone {
					return unless exists $state{fh};
					%state = ();
					$! = $errno;
					$connect->();
			};
			my ($domain, $type, $proto, $sockaddr) = @$target;
			socket $state{fh}, $domain, $type, $proto
				or return $state{next}();
			fh_nonblocking $state{fh}, 1;
			my $timeout = $prepare && $prepare->($state{fh});
			$timeout ||= 30 if AnyEvent::WIN32;
			$state{to} = AE::timer $timeout, 0, sub {
				$! = Errno::ETIMEDOUT;
				$state{next}();
			} if $timeout;
			if ( (connect $state{fh}, $sockaddr)
				|| ($! == Errno::EINPROGRESS # POSIX
				|| $! == Errno::EWOULDBLOCK
				|| $! == AnyEvent::Util::WSAEINVAL # not convinced, but doesn't hurt
				|| $! == AnyEvent::Util::WSAEWOULDBLOCK)
			) {
				$state{ww} = AE::io $state{fh}, 1, sub {
					if (my $sin = getpeername $state{fh}) {
						my ($port, $host) = AnyEvent::Socket::unpack_sockaddr $sin;
						delete $state{ww}; delete $state{to};
						my $guard = guard { %state = () };
						$connect->(delete $state{fh}, AnyEvent::Socket::format_address $host, $port, sub {
							$guard->cancel;
							$state{next}();
						});
					} else {
						if ($! == Errno::ENOTCONN) {
							# maybe recv?
							sysread $state{fh}, my $buf, 1;
							$! = (unpack "l", getsockopt $state{fh}, Socket::SOL_SOCKET(), Socket::SO_ERROR()) || Errno::EAGAIN
								if AnyEvent::CYGWIN && $! == Errno::EAGAIN;
						}
						return if $! == Errno::EAGAIN; # skip spurious wake-ups
						delete $state{ww}; delete $state{to};
						$state{next}();
					}
				};
			} else {
				$state{next}();
			}
		};
		$! = Errno::ENXIO;
		$state{next}();
	};
	defined wantarray && guard { %state = () };
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
