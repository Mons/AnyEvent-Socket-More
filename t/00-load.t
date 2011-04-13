#!/usr/bin/env perl -w

use common::sense;
use lib::abs '../lib';
use Test::More tests => 2;
use Test::NoWarnings;

BEGIN {
	use_ok( 'AnyEvent::Socket::More' );
}

diag( "Testing AnyEvent::Socket::More $AnyEvent::Socket::More::VERSION, Perl $], $^X" );
