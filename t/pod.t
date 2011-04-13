#!/usr/bin/env perl -w

use common::sense;
use Test::More;
use lib::abs "../lib";
BEGIN {
	my $lib = lib::abs::path( ".." );
	chdir $lib or plan skip_all => "Can't chdir to dist $lib";
}

eval "use Test::Pod 1.22; 1"
	or plan skip_all => "Test::Pod 1.22 required for testing POD";

all_pod_files_ok();

exit 0;
require Test::NoWarnings;
