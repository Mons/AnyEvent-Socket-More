#!/opt/perl/bin/perl

use common::sense;
use lib::abs '../lib';
use AnyEvent;
BEGIN { require AnyEvent::Impl::Perl unless $ENV{PERL_ANYEVENT_MODEL} }
use AnyEvent::Handle;
use AnyEvent::Socket::More;
use Test::More tests => 3;
use Test::NoWarnings;

my $lbytes;
my $rbytes;

my $cv = AnyEvent->condvar;

my $hdl;
my $port;

my $sock = tcp_listen undef, undef, sub {
   $port = $_[2];
   0
};

my $w = tcp_accept $sock,
    sub {
      my ($fh, $host, $port) = @_;

      $hdl = AnyEvent::Handle->new (fh => $fh, on_eof => sub { $cv->broadcast });

      $hdl->push_read (chunk => 6, sub {
         my ($hdl, $data) = @_;

         if ($data eq "TEST\015\012") {
            ok 1, 'server received client data';
         } else {
            ok 0, 'server received bad client data';
         }

         $hdl->push_write ("BLABLABLA\015\012");
      });
   }
;

my $clhdl; $clhdl = AnyEvent::Handle->new (
   connect => [localhost => $port],
   on_eof => sub { $cv->broadcast },
);

$clhdl->push_write ("TEST\015\012");
$clhdl->push_read (line => sub {
   my ($clhdl, $line) = @_;

   if ($line eq 'BLABLABLA') {
      ok 1, 'client received response';
   } else {
      ok 0, 'client received bad response';
   }

   $cv->send;
});

$cv->recv;
