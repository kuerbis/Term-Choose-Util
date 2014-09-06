use 5.008000;
use strict;
use warnings;
use Test::More tests => 1;


BEGIN {
    use_ok( 'Term::Choose::Util' ) || print "Bail out!\n";
}

diag( "Testing Term::Choose::Util $Term::Choose::Util::VERSION, Perl $], $^X" );
