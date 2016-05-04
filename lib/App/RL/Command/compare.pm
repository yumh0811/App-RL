package App::RL::Command::compare;
use strict;
use warnings;
use autodie;

use App::RL -command;
use App::RL::Common qw(:all);

use constant abstract => 'compare 2 chromosome runlists';

sub opt_spec {
    return (
        [ "outfile|o=s", "Output filename. [stdout] for screen." ],
        [   "op=s",
            "operations: intersect, union, diff or xor. Default is [intersect]",
            { default => "intersect" }
        ],
        [ "remove|r", "Remove 'chr0' from chromosome names." ],
        [ "mk",       "*Fisrt* YAML file contains multiple sets of runlists." ],
    );
}

sub usage_desc {
    my $self = shift;
    my $desc = $self->SUPER::usage_desc;    # "%c COMMAND %o"
    $desc .= " <infile1> <infile2>";
    return $desc;
}

sub description {
    my $desc;
    $desc .= "Coverage statistics.\n";
    return $desc;
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    #print YAML::Syck::Dump {
    #    opt  => $opt,
    #    args => $args,
    #};

    $self->usage_error("This command need two input files.") unless @$args == 2;
    $self->usage_error("The first input file [@{[$args->[0]]}] doesn't exist.")
        unless -e $args->[0];
    $self->usage_error("The second input file [@{[$args->[1]]}] doesn't exist.")
        unless -e $args->[1];

    if ( $opt->{op} =~ /^dif/i ) {
        $opt->{op} = 'diff';
    }
    elsif ( $opt->{op} =~ /^uni/i ) {
        $opt->{op} = 'union';
    }
    elsif ( $opt->{op} =~ /^int/i ) {
        $opt->{op} = 'intersect';
    }
    elsif ( $opt->{op} =~ /^xor/i ) {
        $opt->{op} = 'xor';
    }
    else {
        Carp::confess "[@{[$opt->{op}]}] invalid\n";
    }

    if ( !exists $opt->{outfile} ) {
        $opt->{outfile} = Path::Tiny::path( $args->[0] )->absolute . "." . $opt->{op} . ".yml";
    }
}

sub execute {
    my ( $self, $opt, $args ) = @_;

    #----------------------------#
    # Loading
    #----------------------------#
    my $chrs = Set::Scalar->new;

    # file1
    my $set_of = {};
    my @names;
    if ( $opt->{mk} ) {
        my $yml = YAML::Syck::LoadFile( $args->[0] );
        @names = sort keys %{$yml};

        for my $name (@names) {
            $set_of->{$name} = runlist2set( $yml->{$name}, $opt->{remove} );
            $chrs->insert( keys %{ $set_of->{$name} } );
        }
    }
    else {
        @names = ("__single");
        $set_of->{__single}
            = runlist2set( YAML::Syck::LoadFile( $args->[0] ), $opt->{remove} );
        $chrs->insert( keys %{ $set_of->{__single} } );
    }

    # file2
    my $set_single;
    {
        $set_single = runlist2set( YAML::Syck::LoadFile( $args->[1] ), $opt->{remove} );
        $chrs->insert( keys %{$set_single} );
    }

    #----------------------------#
    # Operating
    #----------------------------#
    my $op_result_of = { map { $_ => {} } @names };

    for my $name (@names) {
        my $set_one = $set_of->{$name};

        # give empty set to non-existing chrs
        for my $s ( $set_one, $set_single ) {
            for my $chr ( sort $chrs->members ) {
                if ( !exists $s->{$chr} ) {
                    $s->{$chr} = new_set();
                }
            }
        }

        # operate on each chr
        for my $chr ( sort $chrs->members ) {
            my $op     = $opt->{op};
            my $op_set = $set_one->{$chr}->$op( $set_single->{$chr} );
            $op_result_of->{$name}{$chr} = $op_set->runlist;
        }
    }

    #----------------------------#
    # Output
    #----------------------------#
    my $out_fh;
    if ( lc( $opt->{outfile} ) eq "stdout" ) {
        $out_fh = *STDOUT;
    }
    else {
        open $out_fh, ">", $opt->{outfile};
    }

    if ( $opt->{mk} ) {
        print {$out_fh} YAML::Syck::Dump($op_result_of);
    }
    else {
        print {$out_fh} YAML::Syck::Dump( $op_result_of->{__single} );
    }

    close $out_fh;
    return;
}

1;
