package App::Project::Doctor;

use strict;
use warnings;
use autodie qw(:all);

use Moo;
use namespace::autoclean;
use Carp qw(croak carp);
use Readonly;
use File::Spec;
use Scalar::Util qw(blessed);

our $VERSION = '0.01';

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Ordered list of all check class names (short suffix form).
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

# Files that mark a distribution root when walking up the directory tree.
Readonly::Array my @ROOT_MARKERS => qw(
	Makefile.PL
	Build.PL
	dist.ini
	cpanfile
);

# ---------------------------------------------------------------------------
# Attributes
# ---------------------------------------------------------------------------

has path => (
	is      => 'ro',
	default => sub { '.' },
);

has checks => (
	is      => 'ro',
	default => sub { [@DEFAULT_CHECKS] },
);

has skip => (
	is      => 'ro',
	default => sub { [] },
);

has verbose => (
	is      => 'ro',
	default => 0,
);

# ---------------------------------------------------------------------------
# Public interface
# ---------------------------------------------------------------------------

=head2 run

Detects the distro root, instantiates all enabled checks, runs them in
order, and returns an L<App::Project::Doctor::Report>.

=cut

sub run {
	my $self = shift;

	my $root = $self->_detect_root($self->path);
	croak "Cannot detect a distribution root from '" . $self->path . "'"
		unless defined $root;

	my $ctx = $self->_build_context($root);
	my $report = $self->_build_report;
	my @checks = $self->_build_checks;

	for my $check (@checks) {
		if ($self->verbose) {
			printf "  Running check: %s ...\n", $check->name;
		}
		my @findings = eval { $check->check($ctx) };
		if ($@) {
			carp sprintf("Check '%s' threw an exception: %s", $check->name, $@);
			next;
		}
		$report->add_findings(@findings);
	}

	return $report;
}

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

# Walk up from $start_dir until we find a directory containing a ROOT_MARKER.
# Returns the directory path, or undef if none found.
sub _detect_root {
	my ($self, $start) = @_;
	my $dir = File::Spec->rel2abs($start);

	while (1) {
		for my $marker (@ROOT_MARKERS) {
			return $dir if -e File::Spec->catfile($dir, $marker);
		}
		my $parent = File::Spec->catdir($dir, File::Spec->updir);
		last if $parent eq $dir;    # reached filesystem root
		$dir = $parent;
	}
	return undef;
}

sub _build_context {
	my ($self, $root) = @_;
	require App::Project::Doctor::Context;
	return App::Project::Doctor::Context->new(
		root    => $root,
		verbose => $self->verbose,
	);
}

sub _build_report {
	require App::Project::Doctor::Report;
	return App::Project::Doctor::Report->new;
}

# Instantiate check objects, filtering out skipped ones.
sub _build_checks {
	my $self = shift;

	my %skip = map { lc($_) => 1 } @{ $self->skip };
	my @enabled;

	for my $name (@{ $self->checks }) {
		next if $skip{ lc($name) };
		my $class = "App::Project::Doctor::Check::$name";
		eval "require $class";    ## no critic
		if ($@) {
			carp "Could not load check '$class': $@";
			next;
		}
		push @enabled, $class->new;
	}

	# Sort by each check's declared order.
	return sort { $a->order <=> $b->order } @enabled;
}

1;

__END__

=head1 NAME

App::Project::Doctor - Unified pre-release health check for Perl distributions

=head1 VERSION

0.01

=head1 SYNOPSIS

  # Command line
  project-doctor [--check=Tests,CI] [--skip=Meta] [--fix] [PATH]

  # Programmatic
  use App::Project::Doctor;

  my $doctor = App::Project::Doctor->new(
      path    => '/path/to/my-dist',
      verbose => 1,
  );
  my $report = $doctor->run;
  print $report->render_text;
  exit $report->exit_code;

=head1 DESCRIPTION

C<App::Project::Doctor> orchestrates a suite of diagnostic checks against a
Perl CPAN distribution.  It combines the functionality of:

=over 4

=item * L<App::Workflow::Lint>  -- GitHub Actions workflow validation

=item * L<App::GHGen>  -- GitHub Actions workflow generation

=item * L<App::makefilepl2cpanfile>  -- dependency extraction

=item * L<App::Test::Generator>  -- test scaffolding

=back

into a single interactive tool designed to be run before every CPAN upload.
Each check produces a list of L<App::Project::Doctor::Finding> objects.
Findings with associated fix coderefs are offered interactively.

=head1 ATTRIBUTES

=head2 path

Path from which to detect the distribution root.  Defaults to C<.>
(current working directory).  The root is the nearest ancestor directory
containing C<Makefile.PL>, C<Build.PL>, C<dist.ini>, or C<cpanfile>.

=head2 checks

ArrayRef of check class name suffixes to run.  Defaults to all checks in
the canonical order:

  Tests CI GitHubActions Meta Pod Dependencies License Security CpanReadiness

=head2 skip

ArrayRef of check names to exclude (case-insensitive).  Takes precedence
over C<checks>.

=head2 verbose

Boolean.  When true, each check's name is printed as it starts.  Default 0.

=head1 METHODS

=head2 run

Runs all enabled checks and returns an L<App::Project::Doctor::Report>.

=head3 API SPECIFICATION

=head4 Input

None (configuration via constructor attributes).

=head4 Output

L<App::Project::Doctor::Report> instance.

=head3 MESSAGES

  Code | Trigger                          | Resolution
  -----|----------------------------------|---------------------------------------
  DR01 | Cannot detect distribution root  | Run from within a distribution directory
  DR02 | A check module cannot be loaded  | Install the check's prerequisites

=head3 FORMAL SPECIFICATION

  Doctor == { path : Path, checks : [CheckName], skip : [CheckName], verbose : Bool }

  run : Doctor -> Report
  run d ==
    let root     = detect_root (path d)
        ctx      = Context { root, verbose = verbose d }
        enabled  = sort_by_order (checks d \\ skip d)
        findings = concat [ check c ctx | c <- enabled ]
    in  Report { findings }

  detect_root : Path -> Path | undefined
  detect_root p == nearest ancestor of p containing a ROOT_MARKER file

=head1 LIMITATIONS

Check execution is sequential.  No parallelism is implemented.
The distro root detection halts at the filesystem root; very deep directory
trees may cause a perceptible delay.

=head1 AUTHOR

Nigel Horne C<< <njh@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
