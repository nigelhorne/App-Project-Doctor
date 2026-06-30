package App::Project::Doctor;

use strict;
use warnings;
use autodie qw(:all);

use Carp qw(croak carp);
use Readonly;
use File::Spec;
use Params::Validate qw(:all);

our $VERSION = '0.01';

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

Readonly::Array my @DEFAULT_CHECKS => qw(
	Tests
	CI
	GitHubActions
	Meta
	Pod
	Dependencies
	License
	Security
	CpanReadiness
);

Readonly::Array my @ROOT_MARKERS => qw(
	Makefile.PL
	Build.PL
	dist.ini
	cpanfile
);

# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

sub new {
	my $class = shift;
	my %args  = validate(@_, {
		path    => { type => SCALAR,   default  => '.'             },
		checks  => { type => ARRAYREF, default  => [@DEFAULT_CHECKS] },
		skip    => { type => ARRAYREF, default  => sub { [] }      },
		verbose => { type => SCALAR,   default  => 0               },
	});
	return bless \%args, $class;
}

# ---------------------------------------------------------------------------
# Accessors
# ---------------------------------------------------------------------------

sub path    { $_[0]->{path}    }
sub checks  { $_[0]->{checks}  }
sub skip    { $_[0]->{skip}    }
sub verbose { $_[0]->{verbose} }

# ---------------------------------------------------------------------------
# Public interface
# ---------------------------------------------------------------------------

=head2 run

Detects the distro root, instantiates all enabled checks, runs them in order,
and returns an L<App::Project::Doctor::Report>.

=cut

sub run {
	my $self = shift;

	my $root = $self->_detect_root($self->path)
		or croak "Cannot detect a distribution root from '" . $self->path . "'";

	my $ctx    = $self->_build_context($root);
	my $report = $self->_build_report;

	for my $check ($self->_build_checks) {
		printf "  Running: %s ...\n", $check->name if $self->verbose;
		my @findings = eval { $check->check($ctx) };
		if ($@) {
			carp sprintf("Check '%s' threw: %s", $check->name, $@);
			next;
		}
		$report->add_findings(@findings);
	}

	return $report;
}

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

# Walk up from $start until a ROOT_MARKER is found; return that directory
# or undef when we hit the filesystem root without finding one.
sub _detect_root {
	my ($self, $start) = @_;
	my $dir = File::Spec->rel2abs($start);
	while (1) {
		for my $marker (@ROOT_MARKERS) {
			return $dir if -e File::Spec->catfile($dir, $marker);
		}
		my $parent = File::Spec->catdir($dir, File::Spec->updir);
		last if $parent eq $dir;
		$dir = $parent;
	}
	return undef;
}

sub _build_context {
	my ($self, $root) = @_;
	require App::Project::Doctor::Context;
	return App::Project::Doctor::Context->new(root => $root, verbose => $self->verbose);
}

sub _build_report {
	require App::Project::Doctor::Report;
	return App::Project::Doctor::Report->new;
}

# Instantiate and sort check objects, excluding those listed in skip.
sub _build_checks {
	my $self  = shift;
	my %skip  = map { lc($_) => 1 } @{ $self->skip };
	my @built;

	require App::Project::Doctor::Check::Base;

	for my $name (@{ $self->checks }) {
		next if $skip{ lc($name) };
		my $class = "App::Project::Doctor::Check::$name";
		eval "require $class";    ## no critic (ProhibitStringyEval)
		if ($@) {
			carp "Could not load '$class': $@";
			next;
		}
		push @built, $class->new;
	}

	return sort { $a->order <=> $b->order } @built;
}

1;

__END__

=head1 NAME

App::Project::Doctor - Unified pre-release health check for Perl CPAN distributions

=head1 VERSION

0.01

=head1 SYNOPSIS

  # Command line
  project-doctor [--check=Tests,CI] [--skip=Meta] [--fix] [PATH]

  # Programmatic
  use App::Project::Doctor;

  my $doctor = App::Project::Doctor->new(path => '/path/to/my-dist');
  my $report = $doctor->run;
  print $report->render_text;
  exit $report->exit_code;

=head1 DESCRIPTION

Orchestrates a suite of diagnostic checks against a Perl CPAN distribution,
combining L<App::Workflow::Lint>, L<App::GHGen>, L<App::makefilepl2cpanfile>,
and L<App::Test::Generator> into a single interactive pre-upload tool.

Each enabled C<App::Project::Doctor::Check::*> plugin receives an
L<App::Project::Doctor::Context> and returns a list of
L<App::Project::Doctor::Finding> objects which are collected into an
L<App::Project::Doctor::Report>.

=head1 CONSTRUCTOR

=head2 new( %args )

=head3 API SPECIFICATION

=head4 Input

  path    : String    -- start path for root detection    default '.'
  checks  : ArrayRef  -- check name suffixes to run       default all
  skip    : ArrayRef  -- check names to exclude           default []
  verbose : Bool                                          default 0

=head4 Output

Blessed hashref of type C<App::Project::Doctor>.

=head1 ACCESSORS

C<path>, C<checks>, C<skip>, C<verbose> -- read-only.

=head1 METHODS

=head2 run

=head3 API SPECIFICATION

=head4 Input

None.

=head4 Output

L<App::Project::Doctor::Report>.

=head3 MESSAGES

  Code | Trigger                         | Resolution
  -----|----------------------------------|----------------------------------------
  DR01 | Cannot detect distribution root  | Run from within a distribution directory
  DR02 | A check class cannot be loaded   | Install the check's prerequisites

=head3 FORMAL SPECIFICATION

  Doctor == { path : Path, checks : [Name], skip : [Name], verbose : Bool }

  run : Doctor -> Report
  run d ==
    let root    = detect_root (path d)
        ctx     = Context { root, verbose = verbose d }
        enabled = sort_by_order (checks d \\ skip d)
    in  Report { concat [ check c ctx | c <- enabled ] }

  detect_root : Path -> Path | undefined
  detect_root p == nearest ancestor of p containing a ROOT_MARKER

=head1 CHECKS

In default execution order:

  Tests           t/ exists, .t files present, prove passes
  CI              At least one CI configuration present
  GitHubActions   Workflow YAML validates via App::Workflow::Lint
  Meta            META.yml/json parsed and complete
  Pod             All .pm files have valid POD
  Dependencies    Used modules declared as prerequisites
  License         LICENSE file present and consistent with META
  Security        strict/warnings everywhere; no hardcoded secrets
  CpanReadiness   Version format, Changes, MANIFEST, README

=head1 LIMITATIONS

Checks run sequentially; no parallelism.

=head1 AUTHOR

Nigel Horne C<< <njh@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
