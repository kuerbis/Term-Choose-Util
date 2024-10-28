package Term::Choose::Util;

use warnings;
use strict;
use 5.10.0;

our $VERSION = '0.143';
use Exporter 'import';
our @EXPORT_OK = qw( choose_a_directory choose_a_file choose_directories choose_a_number choose_a_subset settings_menu
                     insert_sep get_term_size get_term_width get_term_height unicode_sprintf );

use Carp                  qw( croak );
use Cwd                   qw( realpath );
use Encode                qw( decode encode );
use File::Basename        qw( basename dirname );
use File::Spec::Functions qw( catdir catfile );
use List::Util            qw( sum any );

use Encode::Locale qw();
use File::HomeDir  qw();

use Term::Choose                  qw( choose );
use Term::Choose::Constants       qw( SGR_ES );
use Term::Choose::LineFold        qw( cut_to_printwidth print_columns );
use Term::Choose::ValidateOptions qw( validate_options );


sub new {
    my $class = shift;
    my ( $opt ) = @_;
    my $instance_defaults = _defaults();
    if ( defined $opt ) {
        croak "Options have to be passed as a HASH reference." if ref $opt ne 'HASH';
        my $caller = 'new';
        validate_options( _valid_options( $caller ), $opt, $caller );
        for my $key ( keys %$opt ) {
            $instance_defaults->{$key} = $opt->{$key} if defined $opt->{$key};
        }
    }
    my $self = bless $instance_defaults, $class;
    $self->{backup_instance_defaults} = { %$instance_defaults };
    return $self;
}


sub __restore_defaults {
    my ( $self ) = @_;
    if ( exists $self->{backup_instance_defaults} ) {
        my $instance_defaults = $self->{backup_instance_defaults};
        for my $key ( keys %$self ) {
            if ( $key eq 'backup_instance_defaults' ) {
                next;
            }
            elsif ( exists $instance_defaults->{$key} ) {
                $self->{$key} = $instance_defaults->{$key};
            }
            else {
                delete $self->{$key};
            }
        }
    }
}


sub __prepare_opt {
    my ( $self, $opt, $subseq_tab ) = @_;
    if ( ! defined $opt ) {
        $opt = {};
    }
    croak "Options have to be passed as a HASH reference." if ref $opt ne 'HASH';
    if ( %$opt ) {
        my $caller = ( caller( 1 ) )[3];
        $caller =~ s/^.+::(?:__)?([^:]+)\z/$1/;
        validate_options( _valid_options( $caller ), $opt, $caller );
        my $defaults = _defaults();
        for my $key ( keys %$opt ) {
            if ( ! defined $opt->{$key} && defined $defaults->{$key} ) {
                $self->{$key} = $defaults->{$key};
            }
            else {
                $self->{$key} = $opt->{$key};
            }
        }
    }
    if ( ! defined $self->{tabs_info} ) {
        if ( defined $self->{margin} ) {
            $self->{tabs_info} = [ $self->{margin}[3] // 0, $self->{margin}[3] // 0, $self->{margin}[1] // 0 ];
        }
    }
    if ( ! defined $self->{tabs_prompt} ) {
        if ( defined $self->{margin} ) {
            $self->{tabs_prompt} = [
                $self->{margin}[3] // 0,
              ( $self->{margin}[3] // 0 ) + ( $subseq_tab // 0 ),
                $self->{margin}[1] // 0
            ];
        }
        elsif ( $subseq_tab ) {
            $self->{tabs_prompt} = [ 0, $subseq_tab, 0 ];
        }
    }
}


sub _valid_options {
    my ( $caller ) = @_;
    my %valid = (
        all_by_default      => '[ 0 1 ]',
        clear_screen        => '[ 0 1 ]',
        decoded             => '[ 0 1 ]',
        hide_cursor         => '[ 0 1 ]',
        index               => '[ 0 1 ]',
        keep_chosen         => '[ 0 1 ]',
        mouse               => '[ 0 1 ]',
        order               => '[ 0 1 ]',
        show_hidden         => '[ 0 1 ]',
        small_first         => '[ 0 1 ]',
        alignment           => '[ 0 1 2 ]',
        color               => '[ 0 1 2 ]',
        layout              => '[ 0 1 2 ]',
        page                => '[ 0 1 2 ]',       # undocumented
        keep                => '[ 1-9 ][ 0-9 ]*', # undocumented
        default_number      => '[ 0-9 ]+',
        margin              => 'Array_Int',
        mark                => 'Array_Int',
        tabs_info           => 'Array_Int',
        tabs_prompt         => 'Array_Int',
        busy_string         => 'Str',
        info                => 'Str',
        init_dir            => 'Str',
        back                => 'Str',
        filter              => 'Str',
        footer              => 'Str',           # undocumented
        confirm             => 'Str',
        prefix              => 'Str',
        prompt              => 'Str',
        prompt2             => 'Str',
        cs_begin            => 'Str',
        cs_end              => 'Str',
        cs_label            => 'Str',
        cs_separator        => 'Str',
        thousands_separator => 'Str',
    );
    my $options;
    if ( $caller eq 'new' ) {
        $options = [ keys %valid ];
    }
    else {
        $options = _routine_options( $caller );
    }
    return { map { $_ => $valid{$_} } @$options };
};


sub _defaults {
    return {
        alignment           => 0,
        all_by_default      => 0,
        back                => 'BACK',
        #busy_string        => undef,
        clear_screen        => 0,
        color               => 0,
        confirm             => 'CONFIRM',
        cs_begin            => '',
        cs_end              => '',
        #cs_label           => undef,
        cs_separator        => ', ',
        decoded             => 1,
        #default_number     => undef,
        #filter             => undef,
        #footer             => undef,
        hide_cursor         => 1,
        index               => 0,
        #info               => undef,
        #init_dir           => undef,
        keep_chosen         => 0,
        #keep               => undef,
        layout              => 1,
        #margin             => undef,
        #mark               => undef,
        mouse               => 0,
        order               => 1,
        #page               => undef,
        parent_dir          => '..',
        prefix              => '',
        prompt              => 'Your choice: ',
        #prompt2            => undef,
        show_hidden         => 1,
        small_first         => 0,
        #tabs_info          => undef,
        #tabs_prompt        => undef,
        thousands_separator => ',',

        ## intern:
        reset      => 'reset',
    };
};


sub _routine_options {
    my ( $caller ) = @_;
    my @every = ( qw( back clear_screen color confirm cs_label footer hide_cursor info keep margin mouse page prompt tabs_info tabs_prompt ) );
    my $options;
    if ( $caller eq 'choose_directories' ) {
        $options = [ @every, qw( init_dir layout order alignment show_hidden decoded prompt2 ) ];
    }
    elsif ( $caller eq 'choose_a_directory' ) {
        $options = [ @every, qw( init_dir layout order alignment show_hidden decoded ) ];
    }
    elsif ( $caller eq 'choose_a_file' ) {
        $options = [ @every, qw( init_dir layout order alignment show_hidden decoded filter prompt2 ) ];
    }
    elsif ( $caller eq 'choose_a_number' ) {
        $options = [ @every, qw( small_first reset thousands_separator default_number ) ];
    }
    elsif ( $caller eq 'choose_a_subset' ) {
        $options = [ @every, qw( layout order alignment keep_chosen index prefix all_by_default cs_begin cs_end cs_separator mark busy_string ) ];
    }
    elsif ( $caller eq 'settings_menu' ) {
        $options = [ @every, qw( cs_begin cs_end cs_separator ) ];
    }
    return $options;
}


sub __prepare_path {
    my ( $self ) = @_;
    my $init_dir_fs;
    if ( defined $self->{init_dir} ) {
        $init_dir_fs = encode( 'locale_fs', $self->{init_dir} );
        if ( ! -d $init_dir_fs ) {
            my $prompt = 'Could not find the directory "';
            $prompt .= decode 'locale_fs', $init_dir_fs;
            $prompt .= '". Falling back to the home directory.';
            # Choose
            choose(
                [ 'Press ENTER to continue' ],
                { prompt => $prompt, hide_cursor => $self->{hide_cursor}, mouse => $self->{mouse}, page => $self->{page},
                footer => $self->{footer}, keep => $self->{keep} }
            );
            $init_dir_fs = File::HomeDir->my_home();
        }
    }
    else {
        $init_dir_fs = File::HomeDir->my_home();
    }
    if ( ! -d $init_dir_fs ) {
        croak "Could not find the home directory.";
    }
    my $dir_fs = realpath $init_dir_fs;
    my $dir = decode( 'locale_fs', $dir_fs );
    return $dir;
}


sub __available_dirs {
    my ( $self, $dir ) = @_;
    my $dir_fs = encode( 'locale_fs', $dir );
    my $dh;
    if ( ! eval {
        opendir( $dh, $dir_fs ) or croak $!;
        1 }
    ) {
        print "$@";
        # Choose
        choose(
            [ 'Press Enter:' ],
            { prompt => '', hide_cursor => $self->{hide_cursor}, mouse => $self->{mouse}, page => $self->{page},
              footer => $self->{footer}, keep => $self->{keep}, margin => $self->{margin} }
        );
        return;
    }
    my @dirs;
    while ( my $file_fs = readdir $dh ) {
        next if $file_fs =~ /^\.\.?\z/;
        next if $file_fs =~ /^\./ && ! $self->{show_hidden};
        if ( -d catdir $dir_fs, $file_fs ) {
            push @dirs, decode( 'locale_fs', $file_fs );
        }
    }
    closedir $dh;
    return [ sort @dirs ];
}


sub choose_directories {
    if ( ref $_[0] ne __PACKAGE__ ) {
        my $ob = __PACKAGE__->new();
        delete $ob->{backup_instance_defaults};
        return $ob->choose_directories( @_ );
    }
    my ( $self, $opt ) = @_;
    my $subseq_tab = 2;
    $self->__prepare_opt( $opt, $subseq_tab );
    my $dir = $self->__prepare_path();
    my $chosen_dirs = [];
    my ( $confirm, $change_path, $add_dirs ) = ( $self->{confirm}, '- Change Location', '- Add Directories' );
    my @bu;

    CHOOSE_MODE: while ( 1 ) {
        my $key_dirs = $self->{cs_label} // 'Chosen Dirs: ';
        my $dirs_chosen = $key_dirs . ( @$chosen_dirs ? join( ', ', @$chosen_dirs ) : '---' );
        my $key_path = 'Location: ';
        my $path = $key_path . $dir;
        my $prompt = $dirs_chosen . "\n" . $path;
        # Choose
        my $choice = choose(
            [ undef, $confirm, $change_path, $add_dirs ],
            { info => $self->{info}, prompt => $prompt, layout => 2, mouse => $self->{mouse}, margin => $self->{margin},
              clear_screen => $self->{clear_screen}, hide_cursor => $self->{hide_cursor}, page => $self->{page},
              footer => $self->{footer}, keep => $self->{keep}, undef => $self->{back}, color => $self->{color},
              tabs_info => $self->{tabs_info}, tabs_prompt => $self->{tabs_prompt} }
        );
        if ( ! defined $choice ) {
            if ( @bu ) {
                ( $dir, $chosen_dirs ) = @{pop @bu};
                next CHOOSE_MODE;
            }
            $self->__restore_defaults(); #
            return;
        }
        elsif ( $choice eq $confirm ) {
            my $decoded = $self->{decoded};
            $self->__restore_defaults();
            return $decoded ? $chosen_dirs : [ map { encode 'locale_fs', $_ } @$chosen_dirs ];
        }
        elsif ( $choice eq $change_path ) {
            my $prompt_fmt = $key_path . "%s";
            if ( length $self->{prompt} ) {
                $prompt_fmt .= "\n" . $self->{prompt};
            }
            my $tmp_dir = $self->__choose_a_path( $dir, $prompt_fmt, '<<', 'OK' );
            if ( defined $tmp_dir ) {
               $dir = $tmp_dir;
            }
        }
        elsif ( $choice eq $add_dirs ) {
            my $avail_dirs = $self->__available_dirs( $dir );
            if ( ! defined $avail_dirs ) {
                next CHOOSE_MODE;
            }
            my %bu_opt;
            my $options = _routine_options( 'choose_directories' );
            for my $o ( @$options ) {
                $bu_opt{$o} = $self->{$o};
            }
            my $cs_label = $dirs_chosen . "\n" . $path . "\n" . 'Add: ';
            my $prompt = $self->{prompt2} // $self->{prompt};
            # choose_a_subset
            my $idxs = $self->choose_a_subset(
                [ sort @$avail_dirs ],
                { cs_label => $cs_label, back => '<<', confirm => 'OK', cs_begin => undef, index => 1, keep_chosen => 1,
                  prompt => $prompt, # $self->{option} alreday in $self:
                  #info => $self->{info}, page => $self->{page}, footer => $self->{footer}, keep => $self->{keep},
                  # margin => $self->{margin}, tabs_info => $self->{tabs_info}, tabs_prompt => $self->{tabs_prompt}
                }
            );
            for my $o ( keys %bu_opt ) {
                $self->{$o} = $bu_opt{$o};
            }
            if ( defined $idxs && @$idxs ) {
                push @bu, [ $dir, [ @$chosen_dirs ] ];
                push @$chosen_dirs, map { catdir $dir, $_ } @{$avail_dirs}[@$idxs];
            }
        }
    }
}


sub choose_a_file {
    if ( ref $_[0] ne __PACKAGE__ ) {
        my $ob = __PACKAGE__->new();
        delete $ob->{backup_instance_defaults};
        return $ob->choose_a_file( @_ );
    }
    my ( $self, $opt ) = @_;
    $self->__prepare_opt( $opt );
    my $init_dir = $self->__prepare_path();
    my $prompt_fmt = "File Directory: %s";
    if ( length $self->{prompt} ) {
        $prompt_fmt .= "\n" . $self->{prompt};
    }

    CHOOSE_DIR: while ( 1 ) {
        my $chosen_dir = $self->__choose_a_path( $init_dir, $prompt_fmt, '<<', 'OK' );
        if ( ! defined $chosen_dir ) {
            $self->__restore_defaults(); #
            return;
        }
        my $chosen_file = $self->__a_file( $chosen_dir );
        if ( ! defined $chosen_file ) {
            next CHOOSE_DIR;
        }
        my $decoded = $self->{decoded};
        $self->__restore_defaults();
        return $decoded ? $chosen_file : encode( 'locale_fs', $chosen_file );
    }
}


sub choose_a_directory {
    if ( ref $_[0] ne __PACKAGE__ ) {
        my $ob = __PACKAGE__->new();
        delete $ob->{backup_instance_defaults};
        return $ob->choose_a_directory( @_ );
    }
    my ( $self, $opt ) = @_;
    $self->__prepare_opt( $opt );
    my $init_dir = $self->__prepare_path();
    my $prompt_fmt = ( $opt->{cs_label} // 'Directory: ' ) . "%s";
    if ( length $self->{prompt} ) {
        $prompt_fmt .= "\n" . $self->{prompt};
    }
    my $chosen_dir = $self->__choose_a_path( $init_dir, $prompt_fmt, $self->{back}, $self->{confirm} );
    my $decoded = $self->{decoded};
    $self->__restore_defaults();
    if ( ! defined $chosen_dir ) {
        return;
    }
    return $decoded ? $chosen_dir : encode( 'locale_fs', $chosen_dir );
}


sub __choose_a_path {
    my ( $self, $dir, $prompt_fmt, $back, $confirm ) = @_;
    my $prev_dir = $dir;

    while ( 1 ) {
        my ( $dh, @dirs );
        my $dir_fs = encode( 'locale_fs', $dir );
        if ( ! eval {
            opendir( $dh, $dir_fs ) or croak $!;
            1 }
        ) {
            print "$@";
            # Choose
            choose(
                [ 'Press Enter:' ],
                { prompt => '', hide_cursor => $self->{hide_cursor}, mouse => $self->{mouse}, page => $self->{page},
                  footer => $self->{footer}, keep => $self->{keep}, margin => $self->{margin} }
            );
            $dir = dirname $dir;
            next;
        }
        while ( my $file_fs = readdir $dh ) {
            next if $file_fs =~ /^\.\.?\z/;
            next if $file_fs =~ /^\./ && ! $self->{show_hidden};
            if ( -d catdir $dir_fs, $file_fs ) {
                push @dirs, decode( 'locale_fs', $file_fs );
            }
        }
        closedir $dh;
        my $parent_dir = $self->{parent_dir};
        my @pre = ( undef, $confirm, $parent_dir );
        my $prompt = sprintf $prompt_fmt, $prev_dir;
        # Choose
        my $choice = choose(
            [ @pre, sort( @dirs ) ],
            { info => $self->{info}, prompt => $prompt, alignment => $self->{alignment},
              layout => $self->{layout}, order => $self->{order}, mouse => $self->{mouse},
              clear_screen => $self->{clear_screen}, hide_cursor => $self->{hide_cursor}, margin => $self->{margin},
              color => $self->{color}, tabs_info => $self->{tabs_info}, tabs_prompt => $self->{tabs_prompt},
              page => $self->{page}, footer => $self->{footer}, keep => $self->{keep}, undef => $back }
        );
        if ( ! defined $choice ) {
            return;
        }
        elsif ( $choice eq $confirm ) {
            return $prev_dir;
        }
        elsif ( $choice eq $parent_dir ) {
            $dir = dirname $dir;
        }
        else {
            $dir = catdir $dir, $choice;
        }
        $prev_dir = $dir;
    }
}


sub __a_file {
    my ( $self, $dir ) = @_;
    my $prev_dir = '';
    my $chosen_file;

    while ( 1 ) {
        my @files_fs;
        my $dir_fs = encode( 'locale_fs', $dir );
        if ( ! eval {
            if ( $self->{filter} ) {
                @files_fs = map { basename $_} grep { -e $_ } glob( encode( 'locale_fs', catfile $dir, $self->{filter} ) );
            }
            else {
                opendir( my $dh, $dir_fs ) or croak $!;
                @files_fs = readdir $dh;
                closedir $dh;
            }
        1 }
        ) {
            print "$@";
            # Choose
            choose(
                [ 'Press Enter:' ],
                { prompt => '', hide_cursor => $self->{hide_cursor}, mouse => $self->{mouse}, page => $self->{page},
                  footer => $self->{footer}, keep => $self->{keep}, margin => $self->{margin} }
            );
            return;
        }
        my @files;
        for my $file_fs ( @files_fs ) {
            next if $file_fs =~ /^\.\.?\z/;
            next if $file_fs =~ /^\./ && ! $self->{show_hidden};
            next if -d catdir $dir_fs, $file_fs;
            push @files, decode( 'locale_fs', $file_fs );
        }
        my $chosen_dir = "Directory: $dir";
        my @tmp_prompt;
        push @tmp_prompt, $chosen_dir;
        push @tmp_prompt, ( $self->{cs_label} // 'File: ' ) . ( length $prev_dir ? $prev_dir : '' );
        my $prompt2 = $self->{prompt2} // $self->{prompt};
        if ( length $prompt2 ) {
            push @tmp_prompt, $prompt2;
        }
        my $prompt = join( "\n", @tmp_prompt );
        if ( ! @files ) {
            $prompt .= "\n";
            if ( $self->{filter} ) {
                $prompt .= 'No matches for filter "' .  $self->{filter} . '".';
            }
            else {
                $prompt .= 'No files.';
            }
            # Choose
            choose(
                [ ' < ' ],
                { info => $self->{info}, prompt => $prompt, hide_cursor => $self->{hide_cursor},
                  mouse => $self->{mouse}, color => $self->{color}, page => $self->{page}, footer => $self->{footer},
                  keep => $self->{keep}, margin => $self->{margin} }
            );
            return;
        }
        my @pre = ( undef );
        if ( $chosen_file ) {
            push @pre, $self->{confirm}; ##
        }
        # Choose
        $chosen_file = choose(
            [ @pre, sort( @files ) ],
            { info => $self->{info}, prompt => $prompt, alignment => $self->{alignment}, layout => $self->{layout},
              order => $self->{order}, mouse => $self->{mouse}, clear_screen => $self->{clear_screen},
              hide_cursor => $self->{hide_cursor}, color => $self->{color}, tabs_info => $self->{tabs_info},
              tabs_prompt => $self->{tabs_prompt}, page => $self->{page}, footer => $self->{footer},
              keep => $self->{keep}, undef => $self->{back}, margin => $self->{margin} }
        );
        if ( ! length $chosen_file ) {
            if ( length $prev_dir ) {
                $prev_dir = '';
                next;
            }
            return;
        }
        elsif ( $chosen_file eq $self->{confirm} ) {
            return if ! length $prev_dir;
            return catfile $dir, $prev_dir;
        }
        else {
            $prev_dir = $chosen_file;
        }
    }
}


sub choose_a_number {
    if ( ref $_[0] ne __PACKAGE__ ) {
        my $ob = __PACKAGE__->new();
        delete $ob->{backup_instance_defaults};
        return $ob->choose_a_number( @_ );
    }
    my ( $self, $digits, $opt ) = @_;
    my $default_digits = 7;
    if ( ref $digits ) {
        $opt = $digits;
        $digits = $default_digits;
    }
    elsif ( ! $digits ) {
        $digits = $default_digits;
    }
    $self->__prepare_opt( $opt );
    my $tab   = '  -  ';
    my $tab_w = print_columns( $tab );
    my $sep_w = print_columns_ext( $self->{thousands_separator}, $self->{color} );
    my $longest = $digits + int( ( $digits - 1 ) / 3 ) * $sep_w;
    my @ranges = ();
    for my $di ( 0 .. $digits - 1 ) {
        my $begin = 1 . '0' x $di;
        $begin = 0 if $di == 0;
        $begin = insert_sep( $begin, $self->{thousands_separator} );
        ( my $end = $begin ) =~ s/^[01]/9/;
        unshift @ranges,  unicode_sprintf( $begin, $longest, { right_justify => 1, color => $self->{color} } )
                               . $tab
                               . unicode_sprintf( $end, $longest, { right_justify => 1, color => $self->{color} } );
    }
    my $back_tmp    = unicode_sprintf( $self->{back},    $longest * 2 + $tab_w + 1, { color => $self->{color} } );
    my $confirm_tmp = unicode_sprintf( $self->{confirm}, $longest * 2 + $tab_w + 1, { color => $self->{color} } );
    if ( print_columns_ext( $ranges[0], $self->{color} ) > get_term_width() ) {
        @ranges = ();
        for my $di ( 0 .. $digits - 1 ) {
            my $begin = 1 . '0' x $di;
            $begin = 0 if $di == 0;
            $begin = insert_sep( $begin, $self->{thousands_separator} );
            unshift @ranges, unicode_sprintf( $begin, $longest, { color => $self->{color} } );
        }
        $confirm_tmp = $self->{confirm};
        $back_tmp    = $self->{back};
    }
    my %numbers;
    my $result;
    if ( defined $self->{default_number} && length $self->{default_number} <= $digits ) {
        my $count_zeros = 0;
        for my $d ( reverse split '', $self->{default_number} ) {
            $numbers{$count_zeros} = $d * 10 ** $count_zeros;
            $count_zeros++;
        }
        $result = sum( @numbers{keys %numbers} );
        $result = insert_sep( $result, $self->{thousands_separator} );
    }

    NUMBER: while ( 1 ) {
        my $cs_row;
        if ( defined $self->{cs_label} || length $result ) {
            my $tmp_result = length $result ? $result : '';
            my $tmp_cs_label = $self->{cs_label} // '';
            $cs_row = sprintf(  "%s%*s", $tmp_cs_label, $longest, $tmp_result );
            if ( print_columns( $cs_row ) > get_term_width() ) {
                $cs_row = $tmp_result;
            }
        }
        my @tmp_prompt;
        if ( defined $cs_row ) {
            push @tmp_prompt, $cs_row;
        }
        if ( length $self->{prompt} ) {
            push @tmp_prompt, $self->{prompt};
        }
        my $prompt = join "\n", @tmp_prompt;
        my @pre = ( undef, $confirm_tmp ); # confirm if $result ?
        # Choose
        my $range = choose(
            $self->{small_first} ? [ @pre, reverse @ranges ] : [ @pre, @ranges ],
            { info => $self->{info}, prompt => $prompt, layout => 2, alignment => 1, mouse => $self->{mouse},
              clear_screen => $self->{clear_screen}, hide_cursor => $self->{hide_cursor}, color => $self->{color},
              tabs_info => $self->{tabs_info}, tabs_prompt => $self->{tabs_prompt}, page => $self->{page},
              footer => $self->{footer}, keep => $self->{keep}, undef => $back_tmp, margin => $self->{margin} }
        );
        if ( ! defined $range ) {
            if ( defined $result ) {
                $result = undef;
                %numbers = ();
                next NUMBER;
            }
            else {
                $self->__restore_defaults();
                return;
            }
        }
        if ( $range eq $confirm_tmp ) {
            $result = _remove_thousands_separators( $result, $self->{thousands_separator} );
            $self->__restore_defaults();
            return $result;
        }
        my $zeros = ( split /\s*-\s*/, $range )[0];
        $zeros =~ s/^\s*\d//;
        my $zeros_no_sep = _remove_thousands_separators( $zeros, $self->{thousands_separator} );
        my $count_zeros = length $zeros_no_sep;
        my @choices = $count_zeros ? map( $_ . $zeros, 1 .. 9 ) : ( 0 .. 9 );
        # Choose
        my $number = choose(
            [ undef, @choices, $self->{reset} ],
            { info => $self->{info}, prompt => $prompt, layout => 1, alignment => 2, order => 0,
              mouse => $self->{mouse}, clear_screen => $self->{clear_screen}, hide_cursor => $self->{hide_cursor},
              color => $self->{color}, tabs_info => $self->{tabs_info}, tabs_prompt => $self->{tabs_prompt},
              page => $self->{page}, footer => $self->{footer}, keep => $self->{keep}, undef => '<<',
              margin => $self->{margin} }
        );
        next if ! defined $number;
        if ( $number eq $self->{reset} ) {
            delete $numbers{$count_zeros};
        }
        else {
            $numbers{$count_zeros} = _remove_thousands_separators( $number, $self->{thousands_separator} );
        }
        $result = sum( @numbers{keys %numbers} );
        $result = insert_sep( $result, $self->{thousands_separator} );
    }
}


sub _remove_thousands_separators {
    my ( $str, $sep ) = @_;
    # https://stackoverflow.com/questions/13119241/substitution-with-empty-string-unexpected-result
    if ( defined $str && $sep ne '' ) {
        $str =~ s/\Q$sep\E//g;
    }
    return $str;
}


sub choose_a_subset {
    if ( ref $_[0] ne __PACKAGE__ ) {
        my $ob = __PACKAGE__->new();
        delete $ob->{backup_instance_defaults};
        return $ob->choose_a_subset( @_ );
    }
    my ( $self, $available, $opt ) = @_;
    #my $subseq_tab = length( $opt->{cs_label} // '.' ) ? 2 : 0; # width a default cs_label set
    my $subseq_tab = length $opt->{cs_label} ? 2 : 0;
    $self->__prepare_opt( $opt, $subseq_tab );
    my $new_idx = [];
    my $curr_avail = [ @$available ];
    my $bu = [];
    my @pre = ( undef, $self->{confirm} );

    while ( 1 ) {
        my @tmp_prompt;
        my $cs;
        if ( defined $self->{cs_label} ) {
            $cs .= $self->{cs_label};
        }
        if ( @$new_idx ) {
            $cs .= $self->{cs_begin} . join( $self->{cs_separator}, map { defined $_ ? $_ : '' } @{$available}[@$new_idx] ) . $self->{cs_end};
        }
        elsif ( $opt->{all_by_default} ) {
            $cs .= $self->{cs_begin} . '*' . $self->{cs_end};
        }
        if ( defined $cs ) {
            @tmp_prompt = ( $cs );
        }
        if ( length $self->{prompt} ) {
            push @tmp_prompt, $self->{prompt};
        }
        my $mark;
        if ( defined $self->{mark} && @{$self->{mark}} ) {
            $mark = [ map { $_ + @pre } @{$self->{mark}} ];
        }
        my $meta_items = [ 0 .. $#pre ];
        my $prompt = join "\n", @tmp_prompt;
        # Choose
        my @idx = choose(
            [ @pre, length( $self->{prefix} ) ? map { $self->{prefix} . ( defined $_ ? $_ : '' ) } @$curr_avail : @$curr_avail ],
            { info => $self->{info}, prompt => $prompt, layout => $self->{layout}, index => 1,
              alignment => $self->{alignment}, order => $self->{order}, mouse => $self->{mouse},
              meta_items => $meta_items, mark => $mark, include_highlighted => 2,
              clear_screen => $self->{clear_screen}, hide_cursor => $self->{hide_cursor},
              color => $self->{color}, tabs_info => $self->{tabs_info}, tabs_prompt => $self->{tabs_prompt},
              page => $self->{page}, footer => $self->{footer}, keep => $self->{keep}, undef => $self->{back},
              busy_string => $self->{busy_string}, margin => $self->{margin} }
        );
        $self->{mark} = $mark = undef;
        if ( ! defined $idx[0] || $idx[0] == 0 ) {
            if ( @$bu ) {
                ( $curr_avail, $new_idx ) = @{pop @$bu};
                next;
            }
            $self->__restore_defaults();
            return;
        }
        push @$bu, [ [ @$curr_avail ], [ @$new_idx ] ];
        my $ok;
        if ( $idx[0] == $#pre ) {
            $ok = shift @idx;
        }
        my @tmp_idx;
        for my $i ( reverse @idx ) {
            $i -= @pre;
            if ( ! $self->{keep_chosen} ) {
                splice( @$curr_avail, $i, 1 );
                for my $used_i ( sort { $a <=> $b } @$new_idx ) {
                    last if $used_i > $i;
                    ++$i;
                }
            }
            push @tmp_idx, $i;
        }
        push @$new_idx, reverse @tmp_idx;
        if ( $ok ) {
            if ( ! @$new_idx && $opt->{all_by_default} ) {
                $new_idx = [ 0 .. $#{$available} ];
            }
            my $return_indexes = $self->{index}; # because __restore_defaults resets $self->{index}
            $self->__restore_defaults();
            return $return_indexes ? $new_idx : [ @{$available}[@$new_idx] ];
        }
    }
}


sub settings_menu {
    if ( ref $_[0] ne __PACKAGE__ ) {
        my $ob = __PACKAGE__->new();
        delete $ob->{backup_instance_defaults};
        return $ob->settings_menu( @_ );
    }
    my ( $self, $menu, $curr, $opt ) = @_;
    $self->__prepare_opt( $opt );
    my $longest = 0;
    my $new = {};
    my $name_w = {};
    for my $sub ( @$menu ) {
        my ( $key, $name, $values ) = @$sub;
        $name_w->{$key} = print_columns_ext( $name, $self->{color} );
        if ( $name_w->{$key} > $longest ) {
            $longest = $name_w->{$key};
        }
        $curr->{$key} = 0 if ! defined $curr->{$key};
        $curr->{$key} = 0 if $curr->{$key} > $#$values;
        $curr->{$key} = 0 if ! defined $values->[$curr->{$key}];

        while ( ! defined $values->[$curr->{$key}] ) {
            ++$curr->{$key};
            if ( $curr->{$key} > $#$values ) {
                $curr->{$key} = 0;
                last;
            }
        }
        $new->{$key} = $curr->{$key};
    }
    my @print_keys;
    for my $sub ( @$menu ) {
        my ( $key, $name, $values ) = @$sub;
        my $current = $values->[$new->{$key}] // '';
        push @print_keys, $name . ( ' '  x ( $longest - $name_w->{$key} ) ) . " [$current]";
    }
    my @pre = ( undef, $self->{confirm} );
    $ENV{TC_RESET_AUTO_UP} = 0;
    my $default = 0;
    my $count = 0;

    while ( 1 ) {
        my @tmp_prompt;
        if ( defined $self->{cs_label} ) {
            push @tmp_prompt, $self->{cs_label} . $self->{cs_begin} . join( $self->{cs_separator}, map { "$_=$new->{$_}" } keys %$new ) . $self->{cs_end};
        }
        if ( length $self->{prompt} ) {
            push @tmp_prompt, $self->{prompt};
        }
        my $prompt = join( "\n", @tmp_prompt );
        # Choose
        my $idx = choose(
            [ @pre, @print_keys ],
            { info => $self->{info}, prompt => $prompt, index => 1, default => $default, layout => 2, alignment => 0,
              mouse => $self->{mouse}, clear_screen => $self->{clear_screen}, hide_cursor => $self->{hide_cursor},
              color => $self->{color}, tabs_info => $self->{tabs_info}, tabs_prompt => $self->{tabs_prompt},
              page => $self->{page}, footer => $self->{footer}, keep => $self->{keep}, undef => $self->{back},
              margin => $self->{margin} }
        );
        if ( ! $idx ) {
            $self->__restore_defaults();
            return;
        }
        elsif ( $idx == $#pre ) {
            my $change = 0;
            for my $sub ( @$menu ) {
                my $key = $sub->[0];
                if ( $curr->{$key} == $new->{$key} ) {
                    next;
                }
                $curr->{$key} = $new->{$key};
                $change++;
            }
            $self->__restore_defaults();
            return $change; #
        }
        my $i = $idx - @pre;
        my $key    = $menu->[$i][0];
        my $values = $menu->[$i][2];
        if ( $default == $idx ) {
            if ( $ENV{TC_RESET_AUTO_UP} ) {
                $count = 0;
            }
            elsif ( $count == @$values ) {
                $default = 0;
                $count = 0;
                next;
            }
        }
        else {
            $count = 0;
            $default = $idx;
        }
        my $curr_value = $values->[$new->{$key}] // '';
        my $new_value;

        while ( 1 ) {
            ++$count;
            if ( ++$new->{$key} > $#$values ) {
                $new->{$key} = 0;
            }
            $new_value = $values->[$new->{$key}];
            if ( defined $new_value ) {
                last;
            }
            if ( $count == @$values ) {
                $new_value = '';
                last;
            }
        }
        $print_keys[$i] =~ s/  \[ \Q$curr_value\E \] \z /[$new_value]/x;
    }
}



sub insert_sep {
    my ( $number, $separator ) = @_;
    return           if ! defined $number;
    return $number   if ! length $number;
    $separator = ',' if ! defined $separator;
    return $number   if $separator eq '';
    return $number   if $number =~ /\Q$separator\E/;
    $number =~ s/(^[-+]?\d+?(?=(?>(?:\d{3})+)(?!\d))|\G\d{3}(?=\d))/$1$separator/g;
    # http://perldoc.perl.org/perlfaq5.html#How-can-I-output-my-numbers-with-commas-added?
    return $number;
}


sub get_term_size {
    require Term::Choose::Screen;
    return Term::Choose::Screen::get_term_size();
}


sub get_term_width {
    require Term::Choose::Screen;
    my $term_width = ( Term::Choose::Screen::get_term_size() )[0];
    return $term_width;
}

sub get_term_height {
    require Term::Choose::Screen;
    my $term_height = ( Term::Choose::Screen::get_term_size() )[1];
    return $term_height;
}


sub unicode_sprintf {
    my ( $str, $avail_w, $opt ) = @_;
    $opt ||= {};
    my $colwidth;
    if ( $opt->{color} ) {
        ( my $tmp = $str ) =~ s/${\SGR_ES}//g;
        $colwidth = print_columns( $tmp );
    }
    else {
        $colwidth = print_columns( $str );
    }
    #my $colwidth = print_columns_ext( $str, $opt->{color} );
    if ( $colwidth > $avail_w ) {
        if ( @{$opt->{mark_if_truncated}||[]} ) {
            return cut_to_printwidth( $str, $avail_w - $opt->{mark_if_truncated}[1] ) . $opt->{mark_if_truncated}[0];
        }
        return cut_to_printwidth( $str, $avail_w );
    }
    elsif ( $colwidth < $avail_w ) {
        if ( $opt->{right_justify} ) {
            return " " x ( $avail_w - $colwidth ) . $str;
        }
        else {
            return $str . " " x ( $avail_w - $colwidth );
        }
    }
    else {
        return $str;
    }
}


sub print_columns_ext {
    my ( $str, $color ) = @_;
    if ( $color ) {
        $str =~ s/${\SGR_ES}//g;
    }
    return print_columns( $str );
}




1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Term::Choose::Util - TUI-related functions for selecting directories, files, numbers and subsets of lists.

=head1 VERSION

Version 0.143

=cut

=head1 SYNOPSIS

Functional interface:

    use Term::Choose::Util qw( choose_a_directory );

    my $chosen_directory = choose_a_directory();

Object-oriented interface:

    use Term::Choose::Util;

    my $ob = Term::Choose->new ();

    my $chosen_directory = $ob->choose_a_directory();


See L</SUBROUTINES>.

=head1 DESCRIPTION

This module provides TUI-related functions for selecting directories, files, numbers and subsets of lists.

=head1 EXPORT

Nothing by default.

=head1 SUBROUTINES

Values in brackets are default values.

Options are passed as a hash reference. The options argument is the last (or the only) argument.

=head3 Options available for all subroutines

=over

=item

back

Customize the string of the menu entry "I<back>".

Default: C<BACK>

=item

clear_screen

If enabled, the screen is cleared before the output.

Values: [0],1,2.

=item

color

Setting I<color> to C<1> enables the support for color and text formatting escape sequences except for the current
selected element. If set to C<2>, also for the current selected element the color support is enabled (inverted colors).

Values: [0],1,2.

=item

confirm

Customize the string of the menu entry "I<confirm>".

Default: C<CONFIRM>.

=item

cs_label

The value of I<cs-label> (current selection label) is a string which is placed in front of the current selection.

Defaults: C<choose_directories>: 'Chosen Dirs: ', C<choose_a_directory>: 'Directory: ', C<choose_a_file>: 'File: '. For
C<choose_a_number>, C<choose_a_subset> and C<settings_menu> the default is undefined.

The current-selection output is placed between the info string and the prompt string.

=item

hide_cursor

Hide the cursor

Values: 0,[1].

=item

info

A string placed on top of of the output.

Default: undef

=item

margin

The option I<margin> allows one to set a margin on all four sides.

I<margin> expects a reference to an array with four elements in the following order:

- top margin (number of terminal lines)

- right margin (number of terminal columns)

- bottom margin (number of terminal lines)

- left margin (number of terminal columns)

I<margin> does not affect the I<info> string. To add margins to the I<info> string see I<tabs_info>.

I<margin> changes the default values of I<tabs_prompt>.

Allowed values: 0 or greater. Elements beyond the fourth are ignored.

Default: undef

=item

mouse

Enable the mouse mode. An item can be chosen with the left mouse key, the right mouse key can be used instead of the
SpaceBar key.

Values: [0],1.

=item

prompt

A string placed on top of the available choices. I<prompt> set to the empty string means no prompt line.

Default: C<Your choice:>

=item

tabs_info

The option I<tabs_info> allows one to insert spaces at the beginning and the end of I<info> lines.

I<tabs_info> expects a reference to an array with one to three elements:

- the first element (initial tab) sets the number of spaces inserted at beginning of paragraphs

- the second element (subsequent tab) sets the number of spaces inserted at the beginning of all broken lines apart from
the beginning of paragraphs

- the third element sets the number of spaces used as a right margin.

Allowed values: 0 or greater. Elements beyond the third are ignored.

Default: undef

default: If I<margin> is defined, the initial tab and the subsequent tab are set to left-I<margin> and the right margin
is et to right-I<margin>. If I<margin> is not defined the default is undefined.

=item

tabs_prompt

The option I<tabs_prompt> allows one to insert spaces at the beginning and the end of I<prompt> lines.

I<tabs_prompt> expects a reference to an array with one to three elements:

- the first element (initial tab) sets the number of spaces inserted at beginning of paragraphs

- the second element (subsequent tab) sets the number of spaces inserted at the beginning of all broken lines apart from
the beginning of paragraphs

- the third element sets the number of spaces used as a right margin.

Allowed values: 0 or greater. Elements beyond the third are ignored.

default: If I<margin> is defined, the initial tab and the subsequent tab are set to left-I<margin> and the right margin
is set to right-I<margin>. C<choose-directories> and C<choose-a-subset>: +2 for the subsequent tab. Else the default is
undefined.

=back

=head2 new

    $ob = Term::Choose::Util->new( { mouse => 1, ... } );

Returns a new Term::Choose::Util object.

Options: all

=head2 choose_a_directory

    $chosen_directory = choose_a_directory( { layout => 1, ... } )

With C<choose_a_directory> the user can browse through the directory tree and choose a directory which is then returned.

To move around in the directory tree:

- select a directory and press C<Return> to enter in the selected directory.

- choose the "C<..>" (parent directory) menu entry to move upwards.

To return the current working-directory as the chosen directory choose the "I<confirm>" menu entry.

The "I<back>" menu entry causes C<choose_a_directory> to return nothing.

These options can be passed in a hash-reference:

=over

=item

alignment

Elements in columns are aligned to the left if set to C<0>, aligned to the right if set to C<1> and centered if set to
C<2>.

Values: [0],1,2.

=item

decoded

If enabled, the directory name is returned decoded with C<locale_fs> form L<Encode::Locale>.

Values: 0,[1].

=item

init_dir

Set the starting point directory. Defaults to the home directory.

I<init_dir> expects the directory path as a decoded string.

=item

layout

See the option I<layout> in L<Term::Choose>

Values: 0,[1],2.

=item

order

If set to C<1>, the items are ordered vertically else they are ordered horizontally.

This option has no meaning if I<layout> is set to C<2>.

Values: 0,[1].

=item

parent_dir

Customize the string of the menu entry "parent_dir".

Default: C<..>

=item

show_hidden

If enabled, hidden directories are added to the available directories.

Values: 0,[1].

=back

=head2 choose_a_file

    $chosen_file = choose_a_file( { show_hidden => 0, ... } )

Choose the file directory and then choose a file from the chosen directory. To return the chosen file select the
"I<confirm>" menu entry.

These options can be passed in a hash-reference:

=over

=item

alignment

Elements in columns are aligned to the left if set to C<0>, aligned to the right if set to C<1> and centered if set to
C<2>.

Values: [0],1,2.

=item

decoded

If enabled, the directory name is returned decoded with C<locale_fs> form L<Encode::Locale>.

Values: 0,[1].

=item

filter

If set, the value of this option is used as a glob pattern. Only files matching this pattern will be displayed.

=item

init_dir

Set the starting point directory. Defaults to the home directory.

If the option I<decoded> is enabled (default), I<init_dir> expects the directory path as a decoded string.

=item

layout

See the option I<layout> in L<Term::Choose>

Values: 0,[1],2.

=item

order

If set to C<1>, the items are ordered vertically else they are ordered horizontally.

This option has no meaning if I<layout> is set to C<2>.

Values: 0,[1].

=item

prompt2

While I<prompt> is used in the directory menu, I<prompt2> is the prompt in the menu where you select the file.

If I<prompt2> is set to the empty string, no prompt line is displayed.

Default: value of I<prompt>

=item

show_hidden

If enabled, hidden directories are added to the available directories.

Values: 0,[1].

=back

=head2 choose_directories

    $chosen_directories = choose_directories( { mouse => 1, ... } )

C<choose_directories> is similar to C<choose_a_directory> but it is possible to return multiple directories.

Options:

=over

=item

alignment

Elements in columns are aligned to the left if set to C<0>, aligned to the right if set to C<1> and centered if set to
C<2>.

Values: [0],1,2.

=item

decoded

If enabled, the directory name is returned decoded with C<locale_fs> form L<Encode::Locale>.

Values: 0,[1].

=item

init_dir

Set the starting point directory. Defaults to the home directory.

If the option I<decoded> is enabled (default), I<init_dir> expects the directory path as a decoded string.

=item

layout

See the option I<layout> in L<Term::Choose>

Values: 0,[1],2.

=item

order

If set to C<1>, the items are ordered vertically else they are ordered horizontally.

This option has no meaning if I<layout> is set to C<2>.

Values: 0,[1].

=item

prompt2

While I<prompt> is used in the "Change Location" menu, I<prompt2> is the prompt in the menu where you select the
directories.

If I<prompt2> is set to the empty string, no prompt line is displayed.

Default: value of I<prompt>

=item

show_hidden

If enabled, hidden directories are added to the available directories.

Values: 0,[1].

=back

=head2 choose_a_number

    $new = choose_a_number( 5, { cs_label => 'Number: ', ... }  );

This function lets you choose/compose a number (unsigned integer) which is returned.

The fist argument is an integer and determines the range of the available numbers. For example setting the
first argument to 4 would offer a range from 0 to 9999.

With the optional second argument (hash-reference), these options can be passed:

=over

=item

default_number

Set a default number (unsigned integer in the range of the available numbers).

Default: undef

=item

small_first

Put the small number ranges on top.

Default: off

=item

thousands_separator

Sets the thousands separator.

Default: C<,>

=back

The I<current-selection> line is shown if I<cs_label> is defined or as soon as a number has been chosen.

=head2 choose_a_subset

    $subset = choose_a_subset( \@available_items, { cs_label => 'new> ', ... } )

C<choose_a_subset> lets you choose a subset from a list.

The first argument is a reference to an array which provides the available list.

With the optional second argument (hash-reference), these options can be passed:

=over

=item

all_by_default

If enabled, all elements are selected if CONFIRM is chosen without any selected elements.

Values: [0],1.

=item

alignment

Elements in columns are aligned to the left if set to C<0>, aligned to the right if set to C<1> and centered if set to
C<2>.

Values: [0],1,2.

=item

cs_begin

Current selection: the I<cs_begin> string is placed between the I<cs_label> string and the chosen elements as soon as an
element has been chosen.

Default: empty string

=item

cs_end

Current selection: as soon as elements have been chosen the I<cs_end> string is placed at the end of the chosen elements.

Default: empty string

=item

cs_separator

Current selection: the I<cs_separator> is placed between the chosen list elements.

Default: C< ,>

=item

index

If true, the index positions in the available list of the made choices are returned.

Values: [0],1.

=item

keep_chosen

If enabled, the chosen items are not removed from the available choices.

Values: [0],1;

=item

layout

See the option I<layout> in L<Term::Choose>.

Values: 0,1,[2].

=item

mark

Expects as its value a reference to an array with indexes. Elements corresponding to these indexes are pre-selected when
C<choose_a_subset> is called.

=item

order

If set to C<1>, the items are ordered vertically else they are ordered horizontally.

This option has no meaning if I<layout> is set to 2.

Values: 0,[1].

=item

prefix

I<prefix> expects as its value a string. This string is put in front of the elements of the available list in the menu.
The chosen elements are returned without this I<prefix>.

Default: empty string.

=back

The current-selection line is shown if I<cs_label> is defined or as soon as elements have been chosen.

To return the chosen subset (as an array reference) select the "I<confirm>" menu entry.

The "I<back>" menu entry removes the last added chosen items. If the list of chosen items is empty, "I<back>" causes
C<choose_a_subset> to return nothing.

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

the unique name of the option

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

If an index is out of bonds, it is set to C<0>.

=back

With the optional third argument (hash-reference), these options can be passed:

=over

=item

cs_begin

Current selection: the I<cs_begin> string is placed between the I<cs_label> string and the chosen elements as soon as an
element has been chosen.

Default: empty string

=item

cs_end

Current selection: as soon as elements have been chosen the I<cs_end> string is placed at the end of the chosen elements.

Default: empty string

=item

cs_separator

Current selection: the I<cs_separator> is placed between the chosen list elements.

Default: C< ,>

=back

When C<settings_menu> is called, it displays for each array entry a row with the prompt string and the current value.
It is possible to scroll through the rows. If a row is selected, the set and displayed value changes to the next
(undefined values are skipped). After scrolling through the list once the cursor jumps back to the top row.

If the "I<back>" menu entry is chosen, C<settings_menu> does not apply the made changes and returns nothing. If the
"I<confirm>" menu entry is chosen, C<settings_menu> applies the made changes in place to the passed configuration
hash-reference (second argument) and returns the number of made changes.

Setting the option I<cs_label> to a defined value adds an info output line.

=head1 REQUIREMENTS

=head2 Perl version

Requires Perl version 5.10.0 or greater.

=head2 Encoding layer

Ensure the encoding layer for STDOUT, STDERR and STDIN are set to the correct value.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Term::Choose::Util

=head1 AUTHOR

Matthäus Kiem <cuer2s@gmail.com>

=head1 CREDITS

Thanks to the L<Perl-Community.de|http://www.perl-community.de> and the people form
L<stackoverflow|http://stackoverflow.com> for the help.

=head1 LICENSE AND COPYRIGHT

Copyright 2014-2024 Matthäus Kiem.

This library is free software; you can redistribute it and/or modify it under the same terms as Perl 5.10.0. For
details, see the full text of the licenses in the file LICENSE.

=cut
