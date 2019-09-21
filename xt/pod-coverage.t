use 5.010000;
use strict;
use warnings;
use Test::More;

use Test::Pod::Coverage;
use Pod::Coverage;


all_pod_coverage_ok( {
    private => [ qr/^\p{Lu}/, qr/^_/ ],
    trustme => [ qr/^(insert_sep|get_term_size|get_term_width|unicode_sprintf|choose_a_dir|choose_dirs)$/ ]  # 21.09.2019  after transition remove choose_a_dir and choose_dirs
});
