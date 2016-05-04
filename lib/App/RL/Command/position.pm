package App::RL::Command::position;
use strict;
use warnings;
use autodie;

use App::RL -command;
use App::RL::Common qw(:all);

use constant abstract => 'compare runlists against positions';

sub opt_spec {
    return (
        [ "outfile|o=s", "Output filename. [stdout] for screen." ],
        [   "op=s",
            "operations: overlap, non-overlap or superset. Default is [overlap]",
            { default => "overlap" }
        ],
        [ "remove|r", "Remove 'chr0' from chromosome names." ],
    );
}

sub usage_desc {
    my $self = shift;
    my $desc = $self->SUPER::usage_desc;    # "%c COMMAND %o"
    $desc .= " <runlist file> <position files>";
    return $desc;
}

sub description {
    my $desc;
    $desc .= ucfirst(abstract) . ".\n";
    $desc .= " " x 4 . "Genome positions:\n";
    $desc .= " " x 4 . "I:1-100\tPreferred format;\n";
    $desc .= " " x 4 . "I(+):90-150\tStrand will be ommitted;\n";
    $desc .= " " x 4 . "S288c.I(-):190-200\tSpecies names will be omitted\.n";
    return $desc;
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    $self->usage_error("This command need two or more input files.") unless @$args >= 2;
    for ( @{$args} ) {
        if ( !Path::Tiny::path($_)->is_file ) {
            $self->usage_error("The input file [$_] doesn't exist.");
        }
    }

    if ( $opt->{op} =~ /^overlap/i ) {
        $opt->{op} = 'overlap';
    }
    elsif ( $opt->{op} =~ /^non/i ) {
        $opt->{op} = 'non-overlap';
    }
    elsif ( $opt->{op} =~ /^superset/i ) {
        $opt->{op} = 'superset';
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

    my $set_single = runlist2set( YAML::Syck::LoadFile( $args->[0] ), $opt->{remove} );
    $chrs->insert( keys %{$set_single} );

    #----------------------------#
    # Reading and Output
    #----------------------------#
    my $in_fh = IO::Zlib->new( $args->[1], "rb" );

    my $out_fh;
    if ( lc( $opt->{outfile} ) eq "stdout" ) {
        $out_fh = *STDOUT;
    }
    else {
        open $out_fh, ">", $opt->{outfile};
    }

    while ( !$in_fh->eof ) {
        my $line = $in_fh->getline;
        next if substr( $line, 0, 1 ) eq "#";
        chomp $line;

        my $info = decode_header($line);

        next unless defined $info->{chr_name};
        next unless defined $info->{chr_start};
        next unless defined $info->{chr_end};

        $info->{chr_name} =~ s/chr0?//i if $opt->{remove};
        my $cur_positions = new_set();
        $cur_positions->add_pair( $info->{chr_start}, $info->{chr_end} );

        if ( $opt->{op} eq "overlap" ) {
            if ( $chrs->has( $info->{chr_name} ) ) {
                my $chr_single = $set_single->{ $info->{chr_name} };
                if ( $chr_single->intersect($cur_positions)->is_not_empty ) {
                    printf {$out_fh} "%s\n", encode_header($info);
                }
            }
        }

        if ( $opt->{op} eq "non-overlap" ) {
            if ( $chrs->has( $info->{chr_name} ) ) {
                my $chr_single = $set_single->{ $info->{chr_name} };
                if ( $chr_single->intersect($cur_positions)->is_empty ) {
                    printf {$out_fh} "%s\n", encode_header($info);
                }
            }
            else {
                printf {$out_fh} "%s\n", encode_header($info);
            }
        }

        if ( $opt->{op} eq "superset" ) {
            if ( $chrs->has( $info->{chr_name} ) ) {
                my $chr_single = $set_single->{ $info->{chr_name} };
                if ( $chr_single->superset($cur_positions) ) {
                    printf {$out_fh} "%s\n", encode_header($info);
                }
            }
        }
    }

    $in_fh->close;
    close $out_fh;
}

1;