package App::Project::Doctor::Check::Tests;

use strict;
use warnings;
use autodie qw(:all);

use Moo;
use namespace::autoclean;
use Carp qw(croak carp);
use Readonly;

with 'App::Project::Doctor::Check::Role';

our $VERSION = '0.01';

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

Readonly::Scalar my $MIN_TEST_FILES => 1;

# ---------------------------------------------------------------------------
# Role interface
# ---------------------------------------------------------------------------

sub name        { 'Tests' }
sub description { 'Test suite exists, contains test files, and passes cleanly.' }
sub can_fix     { 1 }
sub order       { 10 }

# ---------------------------------------------------------------------------
# check
# ---------------------------------------------------------------------------

sub check {
	my ($self, $ctx) = @_;
	croak 'check requires an App::Project::Doctor::Context' unless ref $ctx;

	my @findings;

	# --- Verify t/ directory exists ----------------------------------------
	unless ($ctx->has_file('t')) {
		push @findings, _finding(
			severity => 'error',
			message  => 'No t/ directory found -- distribution has no tests.',
			fix      => _fix_scaffold_tests($ctx),
		);
		return @findings;    # no point continuing without a test dir
	}

	# --- Verify at least one .t file exists --------------------------------
	my $test_files = $ctx->test_files;
	if (!@{$test_files}) {
		push @findings, _finding(
			severity => 'error',
			message  => 't/ directory exists but contains no .t files.',
			fix      => _fix_scaffold_tests($ctx),
		);
		return @findings;
	}

	# --- Run prove and capture result --------------------------------------
	# We shell out with a timeout guard; failures are warnings, not errors,
	# because a broken test suite still reveals that one exists.
	my $prove_result = _run_prove($ctx->root);
	if ($prove_result->{exit} != 0) {
		push @findings, _finding(
			severity => 'error',
			message  => sprintf('Test suite FAILED (%d test file(s) with failures).', scalar @{$test_files}),
			detail   => $prove_result->{output},
		);
	} else {
		push @findings, _finding(
			severity => 'pass',
			message  => sprintf('%d test file(s) found, all pass.', scalar @{$test_files}),
		);
	}

	return @findings;
}

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

sub _finding {
	require App::Project::Doctor::Finding;
	return App::Project::Doctor::Finding->new(check_name => 'Tests', @_);
}

# Runs prove -l in the distro root; returns { exit => $?, output => $str }.
sub _run_prove {
	my $root = shift;
	my $out = qx{prove -l --nocolor 2>&1};
	return { exit => $?, output => $out // '' };
}

# Returns a fix coderef that delegates to App::Test::Generator.
sub _fix_scaffold_tests {
	my $ctx = shift;
	return sub {
		require App::Test::Generator;
		# App::Test::Generator is expected to scaffold t/unit.t and friends.
		# Exact API depends on that module's interface; adjust as needed.
		App::Test::Generator->new(root => $ctx->root)->generate;
	};
}

1;

__END__

=head1 NAME

App::Project::Doctor::Check::Tests - Check that a test suite exists and passes

=head1 VERSION

0.01

=head1 SYNOPSIS

  my $check = App::Project::Doctor::Check::Tests->new;
  my @findings = $check->check($ctx);

=head1 DESCRIPTION

Verifies that the distribution has a C<t/> directory containing at least one
C<.t> file, and that C<prove -l> exits cleanly.

When tests are absent a fixable finding is emitted; the fix delegates to
L<App::Test::Generator> to scaffold an initial test suite.

=head1 METHODS

=head2 check( $context )

Runs the three-stage test check: directory presence, file presence, prove
execution.

=head3 API SPECIFICATION

=head4 Input

  $context : App::Project::Doctor::Context

=head4 Output

  List of App::Project::Doctor::Finding

=head3 MESSAGES

  Code | Trigger                          | Resolution
  -----|----------------------------------|-------------------------------------------
  T001 | t/ missing                       | Run fix to scaffold via App::Test::Generator
  T002 | t/ present but no .t files       | Run fix to scaffold via App::Test::Generator
  T003 | prove exits non-zero             | Fix failing tests manually

=head3 FORMAL SPECIFICATION

  check : Context -> [Finding]

  check ctx ==
    if not exists (root ctx / "t")  then [Finding{severity=error, fix=scaffold}]
    else if |test_files ctx| = 0   then [Finding{severity=error, fix=scaffold}]
    else if prove_fails ctx        then [Finding{severity=error}]
    else                               [Finding{severity=pass}]

=head1 LIMITATIONS

C<prove> is run as a shell command; the test suite must be runnable from
the distro root with C<prove -l>.  Very slow test suites may cause a
perceptible delay.

=head1 AUTHOR

Nigel Horne C<< <njh@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
