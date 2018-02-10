package Term::Choose::Util;

use warnings;
use strict;
use 5.008003;

our $VERSION = '0.056';
use Exporter 'import';
our @EXPORT_OK = qw( choose_a_dir choose_a_file choose_dirs choose_a_number choose_a_subset settings_menu insert_sep
                     length_longest print_hash term_size term_width unicode_sprintf unicode_trim );

use Cwd                   qw( realpath );
use Encode                qw( decode encode );
use File::Basename        qw( dirname );
use File::Spec::Functions qw( catdir catfile );
use List::Util            qw( sum );

use Encode::Locale         qw();
use File::HomeDir          qw();
use List::MoreUtils        qw( first_index );
use Term::Choose           qw( choose );
use Term::Choose::LineFold qw( line_fold cut_to_printwidth print_columns );
use Term::ReadKey          qw( GetTerminalSize ReadKey ReadMode );

use if $^O eq 'MSWin32', 'Win32::Console';
use if $^O eq 'MSWin32', 'Win32::Console::ANSI';



sub _stringify_array { join( ', ', map { "\"$_\"" } @_ ) }

sub choose_dirs {
    my ( $opt ) = @_;
    my ( $o, $start_dir ) = _prepare_opt_choose_path( $opt );
    my $new         = [];
    my $dir         = realpath $start_dir;
    my $previous    = $dir;
    my @pre         = ( undef, $o->{confirm}, $o->{add_dir}, $o->{up} );
    my $default_idx = $o->{enchanted}  ? $#pre : 0;

    while ( 1 ) {
        my ( $dh, @dirs );
        if ( ! eval {
            opendir( $dh, $dir ) or die $!;
            1 }
        ) {
            print "$@";
            choose( [ 'Press Enter:' ], { prompt => '' } );
            $dir = dirname $dir;
            next;
        }
        while ( my $file = readdir $dh ) {
            next if $file =~ /^\.\.?\z/;
            next if $file =~ /^\./ && ! $o->{show_hidden};
            push @dirs, decode( 'locale_fs', $file ) if -d catdir $dir, $file;
        }
        closedir $dh;
        my $lines;
        my $key_w;
        if ( defined $o->{current} ) {
            $key_w = 9;
            $lines .= sprintf "current: %s\n", _stringify_array( @{$o->{current}} );
            $lines .= sprintf "    new: %s",   _stringify_array( @$new );
        }
        else {
            $key_w = 5;
            $lines .= sprintf "new: %s", _stringify_array( @$new );
        }
        my $key_cwd = "\n     ==>  ";
        $lines  = line_fold( $lines,                                          term_width(), '' , ' ' x $key_w );
        $lines .= "\n";
        $lines .= line_fold( $key_cwd . decode( 'locale_fs', "[$previous]" ), term_width(), '' , ' ' x length $key_cwd );
        if ( length $o->{info} ) {
            $lines = $o->{info} . "\n" . $lines;
        }
        if ( ! defined $o->{prompt} ) {
            $o->{prompt} = ' ';
        }
        $lines .= "\n" if length $o->{prompt};
        $lines .= $o->{prompt};
        my $choice = choose(
            [ @pre, sort( @dirs ) ],
            { prompt => $lines, undef => $o->{back}, default => $default_idx, mouse => $o->{mouse},
              justify => $o->{justify}, layout => $o->{layout}, order => $o->{order}, clear_screen => $o->{clear_screen} }
        );
        if ( ! defined $choice ) {
            return if ! @$new;
            $new = [];
            next;
        }
        $default_idx = $o->{enchanted}  ? $#pre : 0;
        if ( $choice eq $o->{confirm} ) {
            return $new;
        }
        elsif ( $choice eq $o->{add_dir} ) {
            if ( $o->{decoded} ) {
                push @$new, decode( 'locale_fs', $previous );
            }
            else {
                push @$new, $previous;
            }
            $dir = dirname $dir;
            $default_idx = 0 if $previous eq $dir;
            $previous = $dir;
            next;
        }
        $dir = $choice eq $o->{up} ? dirname( $dir ) : catdir( $dir, encode 'locale_fs', $choice );
        $default_idx = 0 if $previous eq $dir;
        $previous = $dir;
    }
}

sub _prepare_opt_choose_path {
    my ( $opt ) = @_;
    $opt = {} if ! defined $opt;
    my $dir = encode( 'locale_fs', $opt->{dir} );
    if ( defined $dir && ! -d $dir ) {
        my $prompt = "Could not find the directory \"$dir\". Falling back to the home directory.";
        choose( [ 'Press ENTER to continue' ], { prompt => $prompt } );
        $dir = File::HomeDir->my_home();
    }
    $dir = File::HomeDir->my_home()                  if ! defined $dir;
    die "Could not find the home directory \"$dir\"" if ! -d $dir;
    my $defaults =  {
        show_hidden  => 1,
        clear_screen => 1,
        mouse        => 0,
        layout       => 1,
        order        => 1,
        info         => '',
        justify      => 0,
        enchanted    => 1,
        confirm      => ' = ',
        add_dir      => ' . ',
        up           => ' .. ',
        file         => ' >F ',
        back         => ' < ',
        decoded      => 1,
        current      => undef,
        prompt       => undef,
    };
    #for my $opt ( keys %$opt ) {
    #    die "$opt: invalid option!" if ! exists $defaults->{$opt};
    #}
    my $o = {};
    for my $key ( keys %$defaults ) {
        $o->{$key} = defined $opt->{$key} ? $opt->{$key} : $defaults->{$key};
    }
    return $o, $dir;
}


sub _prepare_string { '"' . decode( 'locale_fs', shift ) . '"' }


sub choose_a_dir {
    my ( $opt ) = @_;
    return _choose_a_path( $opt, 0 );
}

sub choose_a_file {
    my ( $opt ) = @_;
    return _choose_a_path( $opt, 1 );
}

sub _choose_a_path {
    my ( $opt, $a_file ) = @_;
    my ( $o, $dir ) = _prepare_opt_choose_path( $opt );
    my @pre = ( undef, ( $a_file ? $o->{file} : $o->{confirm} ), $o->{up} );
    my $default_idx = $o->{enchanted}  ? 2 : 0;
    my $curr     = encode 'locale_fs', $o->{current};
    my $previous = $dir;
    my $wildcard = ' ? ';

    while ( 1 ) {
        my ( $dh, @dirs );
        if ( ! eval {
            opendir( $dh, $dir ) or die $!;
            1 }
        ) {
            print "$@";
            choose( [ 'Press Enter:' ], { prompt => '' } );
            $dir = dirname $dir;
            next;
        }
        while ( my $file = readdir $dh ) {
            next if $file =~ /^\.\.?\z/;
            next if $file =~ /^\./ && ! $o->{show_hidden};
            push @dirs, decode( 'locale_fs', $file ) if -d catdir $dir, $file;
        }
        closedir $dh;
        my $lines = $o->{info};
        $lines .= "\n" if length $lines;
        if ( $a_file ) {
            if ( $curr ) {
                $lines .= sprintf "Current file: %s\n", _prepare_string( $curr );
                $lines .= sprintf "    New file: %s", _prepare_string( catfile $dir, $wildcard );
            }
            else {
                $lines .= sprintf "New file: %s", _prepare_string( catfile $dir, $wildcard );
            }
        }
        else {
            if ( $curr ) {
                $lines .= sprintf "Current dir: %s\n", _prepare_string( $curr );
                $lines .= sprintf "    New dir: %s", _prepare_string( $dir );
            }
            else {
                $lines .= sprintf "New dir: %s", _prepare_string( $dir );
            }
        }
        if ( defined $o->{prompt} ) {
            $lines .= "\n" if length $lines && length $o->{prompt};
            $lines .= $o->{prompt};
        }
        my $choice = choose(
            [ @pre, sort( @dirs ) ],
            { prompt => $lines, undef => $o->{back}, default => $default_idx, mouse => $o->{mouse},
              justify => $o->{justify}, layout => $o->{layout}, order => $o->{order}, clear_screen => $o->{clear_screen} }
        );
        if ( ! defined $choice ) {
            return;
        }
        elsif ( $choice eq $o->{confirm} ) {
            return decode 'locale_fs', $previous if $o->{decoded};
            return $previous;
        }
        elsif ( $choice eq $o->{file} ) {
            my $file = _a_file( $o, $dir, $curr, $wildcard );
            next if ! length $file;
            return decode 'locale_fs', $file if $o->{decoded};
            return $file;
        }
        $choice = encode( 'locale_fs', $choice );
        if ( $choice eq $o->{up} ) {
            $dir = dirname $dir;
        }
        else {
            $dir = catdir $dir, $choice;
        }
        if ( $previous eq $dir ) {
            $default_idx = 0;
        }
        else {
            $default_idx = $o->{enchanted}  ? 2 : 0;
        }
        $previous = $dir;
    }
}

sub _a_file {
    my ( $o, $dir, $curr, $wildcard ) = @_;
    my $previous;

    while ( 1 ) {
        my ( $dh, @files );
        if ( ! eval {
            opendir( $dh, $dir ) or die $!;
            1 }
        ) {
            print "$@";
            choose( [ 'Press Enter:' ], { prompt => '' } );
            return;
        }
        while ( my $file = readdir $dh ) {
            next if $file =~ /^\.\.?\z/;
            next if $file =~ /^\./ && ! $o->{show_hidden};
            push @files, decode( 'locale_fs', $file ) if -f catdir $dir, $file;
        }
        closedir $dh;
        if ( ! @files ) {
            my $prompt =  sprintf "No files in %s.", _prepare_string( $dir );
            choose( [ ' < ' ], { prompt => $prompt } );
            return;
        }
        my $lines = $o->{info};
        $lines .= "\n" if length $lines;
        if ( $curr ) {
            $lines .= sprintf "Current file: %s\n", _prepare_string( $curr );
            $lines .= sprintf "    New file: %s", _prepare_string( catfile $dir, $previous // $wildcard );
        }
        else {
            $lines .= sprintf "New file: %s", _prepare_string( catfile $dir, $previous // $wildcard );
        }
        if ( defined $o->{prompt} ) {
            $lines .= "\n" if length $lines && length $o->{prompt};
            $lines .= $o->{prompt};
        }
        my @pre = ( undef, $o->{confirm} );
        my $choice = choose(
            [ @pre, sort( @files ) ],
            { prompt => $lines, undef => $o->{back}, mouse => $o->{mouse}, justify => $o->{justify},
            layout => $o->{layout}, order => $o->{order}, clear_screen => $o->{clear_screen} }
        );
        if ( ! length $choice ) {
            return;
        }
        elsif ( $choice eq $o->{confirm} ) {
            return if ! length $previous;
            return catfile $dir, encode 'locale_fs', $previous;
        }
        else {
            $previous = $choice;
        }
    }
}


sub choose_a_number {
    my ( $digits, $opt ) = @_;
    if ( ref $digits ) {
        $opt = $digits;
        $digits = 7;
    }
    $opt = {} if ! defined $opt;
    my $prompt = $opt->{prompt};
    my $info =         defined $opt->{info}         ? $opt->{info}         : '';
    my $current;
    if ( exists $opt->{current} ) {
       $current      = defined $opt->{current}      ? $opt->{current}      : '';
    }
    my $thsd_sep     = defined $opt->{thsd_sep}     ? $opt->{thsd_sep}     : ',';
    my $name         = defined $opt->{name}         ? $opt->{name}         : '';
    my $clear        = defined $opt->{clear_screen} ? $opt->{clear_screen} : 1;
    my $mouse        = defined $opt->{mouse}        ? $opt->{mouse}        : 0;
    my $small_on_top = defined $opt->{small_on_top} ? $opt->{small_on_top} : 0;     # experimental
    #-------------------------------------------#
    my $back       = defined $opt->{back}         ? $opt->{back}         : 'BACK';
    my $back_short = defined $opt->{back_short}   ? $opt->{back_short}   : '<<';
    my $confirm    = defined $opt->{confirm}      ? $opt->{confirm}      : 'CONFIRM';
    my $reset      = defined $opt->{reset}        ? $opt->{reset}        : 'reset';
    my $tab        = '  -  ';
    my $len_tab = print_columns( $tab ); #
    my $longest    = $digits;
    $longest += int( ( $digits - 1 ) / 3 ) if $thsd_sep ne '';
    my @choices_range = ();
    for my $di ( 0 .. $digits - 1 ) {
        my $begin = 1 . '0' x $di;
        $begin = 0 if $di == 0;
        $begin = insert_sep( $begin, $thsd_sep );
        ( my $end = $begin ) =~ s/^[01]/9/;
        unshift @choices_range, sprintf " %*s%s%*s", $longest, $begin, $tab, $longest, $end;
    }
    my $confirm_tmp = sprintf "%-*s", $longest * 2 + $len_tab, $confirm;
    my $back_tmp    = sprintf "%-*s", $longest * 2 + $len_tab, $back;
    if ( print_columns( "$choices_range[0]" ) > term_width() ) {
        @choices_range = ();
        for my $di ( 0 .. $digits - 1 ) {
            my $begin = 1 . '0' x $di;
            $begin = 0 if $di == 0;
            $begin = insert_sep( $begin, $thsd_sep );
            unshift @choices_range, sprintf "%*s", $longest, $begin;
        }
        $confirm_tmp = $confirm;
        $back_tmp    = $back;
    }
    my %numbers;
    my $result;
    $name = $name . ' ' if length $name;
    my $empty = '-';

    NUMBER: while ( 1 ) {
        my $lines = $info;
        $lines .= "\n" if length $lines;
        my $new_result = length $result ? $result : $empty;
        my $str_w = print_columns( "$choices_range[0]" );
        my $term_w = term_width();
        if ( defined $current ) {
            $current = insert_sep( $current, $thsd_sep );
            my $tmp1 = sprintf " current ${name}%*s", $longest, $current;
            my $tmp2 = sprintf "     new ${name}%*s", $longest, $new_result;
            if ( $str_w > $term_w ) {
                $lines .= sprintf "%*s", $term_w, $new_result;
            }
            else {
                $lines .= sprintf "%*s\n", $str_w, $tmp1;
                $lines .= sprintf "%*s",   $str_w, $tmp2;
            }
        }
        else {
            my $tmp = sprintf "${name}%s", $new_result;
            $lines .= sprintf "%*s", ( $str_w > $term_w ? $term_w : $str_w ), $tmp;
        }
        if ( defined $prompt ) {
            $lines .= "\n" if length $lines && length $prompt;
            $lines .= $prompt;
        }
        my @pre = ( undef, $confirm_tmp );
        # Choose
        my $range = choose(
            $small_on_top ? [ @pre, reverse @choices_range ] : [ @pre, @choices_range ],
            { prompt => $lines, layout => 3, justify => 1, mouse => $mouse,
              clear_screen => $clear, undef => $back_tmp }
        );
        if ( ! defined $range ) {
            if ( defined $result ) {
                $result = undef;
                %numbers = ();
                next NUMBER;
            }
            else {
                return;
            }
        }
        if ( $range eq $confirm_tmp ) {
            return if ! defined $result;
            $result =~ s/\Q$thsd_sep\E//g if $thsd_sep ne '';
            return $result;
        }
        my $zeros = ( split /\s*-\s*/, $range )[0];
        $zeros =~ s/^\s*\d//;
        my $zeros_no_sep;
        if ( $thsd_sep eq '' ) {
            $zeros_no_sep = $zeros;
        }
        else {
            ( $zeros_no_sep = $zeros ) =~ s/\Q$thsd_sep\E//g;
        }
        my $count_zeros = length $zeros_no_sep;
        my @choices = $count_zeros ? map( $_ . $zeros, 1 .. 9 ) : ( 0 .. 9 );
        # Choose
        my $number = choose(
            [ undef, @choices, $reset ],
            { prompt => $lines, layout => 1, justify => 2, order => 0,
              mouse => $mouse, clear_screen => $clear, undef => $back_short }
        );
        next if ! defined $number;
        if ( $number eq $reset ) {
            delete $numbers{$count_zeros};
        }
        else {
            $number =~ s/\Q$thsd_sep\E//g if $thsd_sep ne '';
            $numbers{$count_zeros} = $number;
        }
        $result = sum( @numbers{keys %numbers} );
        $result = insert_sep( $result, $thsd_sep );
    }
}


sub choose_a_subset {
    my ( $available, $opt ) = @_;
    $opt = {} if ! defined $opt; # check ?
    my $current = $opt->{current};
    my $show_fmt    = defined $opt->{show_fmt}     ? $opt->{show_fmt}     : 1;      # experimental
    my $keep_chosen = defined $opt->{keep_chosen}  ? $opt->{keep_chosen}  : 1;      # experimental
    my $mark        = $opt->{mark};                                                 # experimental
    my $info        = defined $opt->{info}         ? $opt->{info}         : '';
    my $index       = defined $opt->{index}        ? $opt->{index}        : 0;
    my $clear       = defined $opt->{clear_screen} ? $opt->{clear_screen} : 1;
    my $mouse       = defined $opt->{mouse}        ? $opt->{mouse}        : 0;
    my $layout      = defined $opt->{layout}       ? $opt->{layout}       : 3;
    my $order       = defined $opt->{order}        ? $opt->{order}        : 1;
    my $prefix      = defined $opt->{prefix}       ? $opt->{prefix}       : ( $layout == 3 ? '- ' : '' );
    my $justify     = defined $opt->{justify}      ? $opt->{justify}      : 0;
    my $prompt      = defined $opt->{prompt}       ? $opt->{prompt}       : ''; #
    #--------------------------------------#
    my $confirm     = defined $opt->{confirm}     ? $opt->{confirm}     : 'CONFIRM';    # layout 0|1|2  [OK] [<<]
    my $back        = defined $opt->{back}        ? $opt->{back}        : 'BACK';
    my $key_cur     = defined $opt->{p_curr}      ? $opt->{p_curr}      : 'Current: '; #
    my $key_new     = defined $opt->{p_new}       ? $opt->{p_new}       : ( defined $current ? '    New: ' : 'Chosen: ' ); #
    if ( $layout == 3 && $prefix ) {
        my $len_prefix = print_columns( "$prefix" );
        $confirm = ( ' ' x $len_prefix ) . $confirm;
        $back    = ( ' ' x $len_prefix ) . $back;
    }
    my $key_cur_w = print_columns( "$key_cur" );
    my $key_new_w = print_columns( "$key_new" );
    my $key_w = $key_cur_w > $key_new_w ? $key_cur_w : $key_new_w;
    my @new_idx;

    my @cur_avail = @$available;

    while ( 1 ) {
        my $lines = $info;
        $lines .= "\n" if length $lines;
        if ( $show_fmt == 0 ) {
            $lines .= join( ', ', @{$opt->{current}} ) . "\n" if defined $current;
            my $tmp = join( ', ', @{$available}[@new_idx] );
            $lines .= ! length $tmp  ? '--' : $tmp;
        }
        elsif ( $show_fmt == 1 ) {
            $lines .= $key_cur . join( ', ', map { "\"$_\"" } @{$opt->{current}} ) . "\n" if defined $current;
            $lines .= $key_new . join( ', ', map { "\"$_\"" } @{$available}[@new_idx] );
        }
        else {
            $lines .= join( "\n", @{$available}[@new_idx] );
        }
        if ( defined $prompt ) {
            $lines .= "\n" if length $lines && length $prompt;
            $lines .= $prompt;
        }
        my @pre = ( undef, $confirm );
        if ( defined $mark && @$mark ) {
            $mark = [ map { $_ + @pre } @$mark ];
        }
        my @avail_with_prefix = map { $prefix . $_ } @cur_avail;
        # Choose
        my @idx = choose(
            [ @pre, @avail_with_prefix  ],
            { prompt => $lines, layout => $layout, mouse => $mouse, clear_screen => $clear, justify => $justify,
              index => 1, lf => [ 0, $key_w ], order => $order, no_spacebar => [ 0 .. $#pre ], undef => $back,
              mark => $mark }
        );
        $mark = undef;
        if ( ! defined $idx[0] || $idx[0] == 0 ) {
            if ( @new_idx ) {
                @new_idx = ();
                @cur_avail = @$available;
                next;
            }
            return;
        }
        if ( $idx[0] == 1 ) {
            shift @idx;
            my @tmp_idx;
            for my $i ( reverse @idx ) {
                $i -= @pre;
                my $str = $keep_chosen ? $cur_avail[$i] : splice( @cur_avail, $i, 1 );
                push @tmp_idx, first_index { $str eq $_ } @$available;
            }
            push @new_idx, reverse( @tmp_idx );
            return $index ? \@new_idx : [ @{$available}[@new_idx] ];
        }
        my @tmp_idx;
        for my $i ( reverse @idx ) {
            $i -= @pre;
            my $str = $keep_chosen ? $cur_avail[$i] : splice( @cur_avail, $i, 1 );
            push @tmp_idx, first_index { $str eq $_ } @$available;
        }
        push @new_idx, reverse( @tmp_idx );
    }
}


sub settings_menu {
    my ( $menu, $curr, $opt ) = @_;
    $opt = {} if ! defined $opt;
    my $prompt   = defined $opt->{prompt}       ? $opt->{prompt}       : 'Choose:';
    my $info     = defined $opt->{info}         ? $opt->{info}         : '';
    my $in_place =         $opt->{in_place}; # DEPRECATED
    my $clear    = defined $opt->{clear_screen} ? $opt->{clear_screen} : 1;
    my $mouse    = defined $opt->{mouse}        ? $opt->{mouse}        : 0;
    #---------------------------------------#
    my $confirm = defined $opt->{confirm} ? $opt->{confirm} : 'CONFIRM';
    my $back    = defined $opt->{back}    ? $opt->{back}    : 'BACK';
    $back    = '  ' . $back;
    $confirm = '  ' . $confirm;
    # ### # DEPRECATED
    if ( defined $in_place ) {
        my $m = 'Please remove the option "in_place". In the next release the option "in-place" will be removed and "settings_menu" will always do an in-place edit of the configuration %hash.';
        choose(
            [ 'Close with ENTER' ],
            { prompt => $m, clear_screen => 1 }
        );
    }
    else {
        $in_place = 1;
    }
    # ###
    my $longest = 0;
    my $new     = {};
    for my $sub ( @$menu ) {
        my ( $key, $name ) = @$sub;
        my $name_w = print_columns( "$name" );
        $longest      = $name_w if $name_w > $longest;
        $curr->{$key} = 0       if ! defined $curr->{$key};
        $new->{$key}  = $curr->{$key};
    }
    my $lines = $info;
    if ( defined $prompt ) {
        $lines .= "\n" if length $lines;
        $lines .= $prompt;
    }
    ###########################
    my $count = 0; # DEPRECATED
    ###########################

    while ( 1 ) {
        my @print_keys;
        for my $sub ( @$menu ) {
            my ( $key, $name, $values ) = @$sub;
            my $current = $values->[$new->{$key}];
            push @print_keys, sprintf "%-*s [%s]", $longest, $name, $current;
        }
        my @pre = ( undef, $confirm );
        my $choices = [ @pre, @print_keys ];
        # Choose
        my $idx = choose(
            $choices,
            { prompt => $lines, index => 1, layout => 3, justify => 0,
              mouse => $mouse, clear_screen => $clear, undef => $back }
        );
        return if ! defined $idx;
        my $choice = $choices->[$idx];
        return if ! defined $choice;
        if ( $choice eq $confirm ) {
            my $change = 0;

            #for my $sub ( @$menu ) {                    # NEW
            #    my $key = $sub->[0];
            #    next if $curr->{$key} == $new->{$key};
            #    $curr->{$key} = $new->{$key};
            #    $change++;
            #}
            #return $change; #

            ###################################################
            if ( $count ) {                        # DEPRECATED
                for my $sub ( @$menu ) {
                    my $key = $sub->[0];
                    next if $curr->{$key} == $new->{$key};
                    if ( $in_place ) {
                        $curr->{$key} = $new->{$key};
                    }
                    $change++;
                }
            }
            return if ! $change;
            return 1 if $in_place;
            return $new;
            ###################################################
        }
        my $key    = $menu->[$idx-@pre][0];
        my $values = $menu->[$idx-@pre][2];
        $new->{$key}++;
        $new->{$key} = 0 if $new->{$key} == @$values;
        ######################
        $count++; # DEPRECATED
        ######################
    }
}



# Removed documentation 08.02.2018:

sub insert_sep {
    my ( $number, $separator ) = @_;
    return           if ! defined $number;
    return $number   if ! length $number;
    $separator = ',' if ! defined $separator;
    return $number   if $number =~ /\Q$separator\E/;
    $number =~ s/(^[-+]?\d+?(?=(?>(?:\d{3})+)(?!\d))|\G\d{3}(?=\d))/$1$separator/g;
    # http://perldoc.perl.org/perlfaq5.html#How-can-I-output-my-numbers-with-commas-added?
    return $number;
}


sub length_longest {
    my ( $list ) = @_;
    my $len = [];
    my $longest = 0;
    for my $i ( 0 .. $#$list ) {
        $len->[$i] = print_columns( "$list->[$i]" );
        $longest = $len->[$i] if $len->[$i] > $longest;
    }
    return wantarray ? ( $longest, $len ) : $longest;
}


sub print_hash {
    my ( $hash, $opt ) = @_;
    $opt = {} if ! defined $opt;
    my $left_margin  = defined $opt->{left_margin}  ? $opt->{left_margin}  : 1;
    my $right_margin = defined $opt->{right_margin} ? $opt->{right_margin} : 2;
    my $keys         = defined $opt->{keys}         ? $opt->{keys}         : [ sort keys %$hash ];
    my $key_w        = defined $opt->{len_key}      ? $opt->{len_key}      : length_longest( $keys );
    my $maxcols      = $opt->{maxcols};
    my $clear        = defined $opt->{clear_screen} ? $opt->{clear_screen} : 1;
    my $mouse        = defined $opt->{mouse}        ? $opt->{mouse}        : 0;
    my $prompt       = defined $opt->{prompt}       ? $opt->{prompt}       : ( defined $opt->{preface} ? '' : 'Close with ENTER' );
    my $preface      = $opt->{preface};
    #-----------------------------------------------------------------#
    my $line_fold = defined $opt->{lf} ? $opt->{lf} : { Charset => 'utf-8', Newline => "\n", OutputCharset => '_UNICODE_', Urgent => 'FORCE' };
    my $term_width = term_width();
    if ( ! $maxcols || $maxcols > $term_width  ) {
        $maxcols = $term_width - $right_margin;
    }
    $key_w += $left_margin;
    my $sep = ' : ';
    my $len_sep = print_columns( "$sep" );
    if ( $key_w + $len_sep > int( $maxcols / 3 * 2 ) ) {
        $key_w = int( $maxcols / 3 * 2 ) - $len_sep;
    }
    my @vals = ();
    if ( defined $preface ) {
        for my $line ( split "\n", $preface ) {
            push @vals, split "\n", line_fold( $line, $maxcols, '', '' );
        }
    }
    for my $key ( @$keys ) {
        next if ! exists $hash->{$key};
        my $val;
        if ( ! defined $hash->{$key} ) {
            $val = '';
        }
        elsif ( ref $hash->{$key} eq 'ARRAY' ) {
            $val = '[ ' . join( ', ', map { defined $_ ? "\"$_\"" : '' } @{$hash->{$key}} ) . ' ]';
        }
        else {
            $val = $hash->{$key};
        }
        my $pr_key = sprintf "%*.*s%*s", $key_w, $key_w, $key, $len_sep, $sep;
        my $text = line_fold( $pr_key . $val, $maxcols, '' , ' ' x ( $key_w + $len_sep ) );
        $text =~ s/\n+\z//;
        for my $val ( split /\n+/, $text ) {
            push @vals, $val;
        }
    }
    return join "\n", @vals if defined wantarray;
    choose(
        [ @vals ],
        { prompt => $prompt, layout => 3, justify => 0, mouse => $mouse, clear_screen => $clear }
    );
}


sub term_size {
    my ( $handle_out ) = defined $_[0] ? $_[0] : \*STDOUT;
    if ( $^O eq 'MSWin32' ) {
        my ( $width, $height ) = Win32::Console->new()->Size();
        return $width - 1, $height;
    }
    return( ( GetTerminalSize( $handle_out ) )[ 0, 1 ] );
}


sub term_width {
    return( ( term_size( $_[0] ) )[0] );
}



sub unicode_sprintf {
    my ( $unicode, $avail_width, $right_justify ) = @_;
    my $colwidth = print_columns( "$unicode" );
    if ( $colwidth > $avail_width ) {
        return cut_to_printwidth( $unicode, $avail_width );
    }
    elsif ( $colwidth < $avail_width ) {
        if ( $right_justify ) {
            $unicode = " " x ( $avail_width - $colwidth ) . $unicode;
        }
        else {
            $unicode = $unicode . " " x ( $avail_width - $colwidth );
        }
    }
    return $unicode;
}



sub unicode_trim {
    my ( $unicode, $len ) = @_;
    return '' if $len <= 0;
    cut_to_printwidth( $unicode, $len );
}



1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Term::Choose::Util - CLI related functions.

=head1 VERSION

Version 0.056

=cut

=head1 SYNOPSIS

See L</SUBROUTINES>.

=head1 DESCRIPTION

This module provides some CLI related functions required by L<App::DBBrowser>, L<App::YTDL> and L<Term::TablePrint>.

=head1 EXPORT

Nothing by default.

=head1 SUBROUTINES

Values in brackets are default values.

Unknown option names are ignored.

Options available for all functions:

=over

=item

clear_screen

If enabled, the screen is cleared before the output.

Values: 0,[1]. Default may change in a future release.

=item

info

A string placed on top of of the output.

=item

prompt

A string placed on top of the available choices.

=item

mouse

See the option I<mouse> in L<Term::Choose>

Values: [0],1,2,3,4.

=back

=head2 choose_a_dir

    $chosen_directory = choose_a_dir( { layout => 1, ... } )

With C<choose_a_dir> the user can browse through the directory tree (as far as the granted rights permit it) and
choose a directory which is returned.

To move around in the directory tree:

- select a directory and press C<Return> to enter in the selected directory.

- choose the "up"-menu-entry ("C< .. >") to move upwards.

To return the current working-directory as the chosen directory choose "C< = >".

The "back"-menu-entry ("C< < >") causes C<choose_a_dir> to return nothing.

As an argument it can be passed a reference to a hash. With this hash the user can set the different options:

=over

=item

current

If set, C<choose_a_dir> shows I<current> as the current directory.

=item

decoded

If enabled, the directory name is returned decoded with C<locale_fs> form L<Encode::Locale>.

=item

dir

Set the starting point directory. Defaults to the home directory or the current working directory if the home directory
cannot be found.

=item

enchanted

If set to 1, the default cursor position is on the "up" menu entry. If the directory name remains the same after an
user input, the default cursor position changes to "back".

If set to 0, the default cursor position is on the "back" menu entry.

Values: 0,[1].

=item

justify

Elements in columns are left justified if set to 0, right justified if set to 1 and centered if set to 2.

Values: [0],1,2.

=item

layout

See the option I<layout> in L<Term::Choose>

Values: 0,[1],2,3.

=item

order

If set to 1, the items are ordered vertically else they are ordered horizontally.

This option has no meaning if I<layout> is set to 3.

Values: 0,[1].

=item

show_hidden

If enabled, hidden directories are added to the available directories.

Values: 0,[1].

=back

=head2 choose_a_file

    $chosen_file = choose_a_file( { layout => 1, ... } )

Browse the directory tree the same way as described for C<choose_a_dir>. Select "C<E<gt>F>" to get the files of the
current directory. To return the chosen file select "=".

The options are passed as a reference to a hash. See L</choose_a_dir> for the different options. C<choose_a_file> has no
option I<current>.

=head2 choose_dirs

    $chosen_directories = choose_dirs( { layout => 1, ... } )

C<choose_dirs> is similar to C<choose_a_dir> but it is possible to return multiple directories.

Different to C<choose_a_dir>:

"C< . >" adds the current directory to the list of chosen directories.

To return the chosen list of directories (as an array reference) select the "confirm"-menu-entry "C< = >".

The "back"-menu-entry ( "C< < >" ) resets the list of chosen directories if any. If the list of chosen directories is
empty, "C< < >" causes C<choose_dirs> to return nothing.

C<choose_dirs> uses the same option as C<choose_a_dir>. The option I<current> expects as its value a reference to an
array (directories shown as the current directories).

=over

=back

=head2 choose_a_number

    for ( 1 .. 5 ) {
        $current = $new
        $new = choose_a_number( 5, { current => $current, name => 'Testnumber' }  );
    }

This function lets you choose/compose a number (unsigned integer) which is returned.

The fist argument - "digits" - is an integer and determines the range of the available numbers. For example setting the
first argument to 6 would offer a range from 0 to 999999.

The second and optional argument is a reference to a hash with these keys (options):

=over

=item

current

The current value. If set, two prompt lines are displayed - one for the current number and one for the new number.

=item

name

If set, the value of I<name> is put in front of the composed number in the info-output.

Default: empty string ("");

=item

thsd_sep

Sets the thousands separator.

Default: comma (,).

=back

=head2 choose_a_subset

    $subset = choose_a_subset( \@available_items, { current => \@current_subset } )

C<choose_a_subset> lets you choose a subset from a list.

As a first argument it is required a reference to an array which provides the available list.

The optional second argument is a hash reference. The following options are available:

=over

=item

current

This option expects as its value the current subset of the available list (a reference to an array). If set, two prompt
lines are displayed - one for the current subset and one for the new subset. Even if the option I<index> is true the
passed current subset is made of values and not of indexes.

The subset is returned as an array reference.

=item

index

If true, the index positions in the available list of the made choices is returned.

=item

justify

Elements in columns are left justified if set to 0, right justified if set to 1 and centered if set to 2.

Values: [0],1,2.

=item

layout

See the option I<layout> in L<Term::Choose>.

Values: 0,1,2,[3].

=item

order

If set to 1, the items are ordered vertically else they are ordered horizontally.

This option has no meaning if I<layout> is set to 3.

Values: 0,[1].

=item

prefix

I<prefix> expects as its value a string. This string is put in front of the elements of the available list before
printing. The chosen elements are returned without this I<prefix>.

The default value is "- " if the I<layout> is 3 else the default is the empty string ("").

=back

=head2 settings_menu

    $menu = [
        [ 'enable_logging', "- Enable logging", [ 'NO', 'YES' ]   ],
        [ 'case_sensitive', "- Case sensitive", [ 'NO', 'YES' ]   ],
        [ 'attempts',       "- Attempts"      , [ '1', '2', '3' ] ]
    ];

    $config = {
        'enable_logging' => 1,
        'case_sensitive' => 1,
        'attempts'       => 2
    };

    settings_menu( $menu, $config );

The first argument is a reference to an array of arrays. These arrays have three elements:

=over

=item

the name of the option

=item

the prompt string

=item

an array reference with the available values of the option.

=back

The second argument is a hash reference:

=over

=item

the keys are the option names

=item

the values (C<0> if not defined) are the indexes of the current value of the respective key/option.

=back

With the optional third argument can be passed the options.

When C<settings_menu> is called, it displays for each array entry a row with the prompt string and the current value.
It is possible to scroll through the rows. If a row is selected, the set and displayed value changes to the next. If the
end of the list of the values is reached, it begins from the beginning of the list.

C<settings_menu> returns true if changes were made else false.

=head1 REQUIREMENTS

=head2 Perl version

Requires Perl version 5.8.3 or greater.

=head2 Encoding layer

Ensure the encoding layer for STDOUT, STDERR and STDIN are set to the correct value.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Term::TablePrint

=head1 AUTHOR

Matthäus Kiem <cuer2s@gmail.com>

=head1 CREDITS

Thanks to the L<Perl-Community.de|http://www.perl-community.de> and the people form
L<stackoverflow|http://stackoverflow.com> for the help.

=head1 LICENSE AND COPYRIGHT

Copyright 2014-2018 Matthäus Kiem.

This library is free software; you can redistribute it and/or modify it under the same terms as Perl 5.10.0. For
details, see the full text of the licenses in the file LICENSE.

=cut
