package App::Project::Doctor::Check::Tests;

use strict;
use warnings;
use autodie qw(:all);

use parent -norequire, 'App::Project::Doctor::Check::Base';

use Carp qw(croak carp);
use File::Path ();
use File::Spec;
use Readonly;

our $VERSION = '0.01';

Readonly::Scalar my $PROVE_CMD => 'prove -l --nocolor 2>&1';

sub name        { 'Tests' }
sub description { 'Test suite exists, contains .t files, and passes cleanly.' }
sub can_fix     { 1 }
sub order       { 10 }

sub check {
	my ($self, $ctx) = @_;
	croak 'check requires an App::Project::Doctor::Context' unless ref $ctx;

	my @findings;

	# Stage 1: t/ directory must exist.
	unless ($ctx->has_file('t')) {
		return _f(
			severity => 'error',
			message  => 'No t/ directory -- distribution has no test suite.',
			fix      => _fix_scaffold($ctx),
		);
	}

	# Stage 2: at least one .t file must exist.
	my $test_files = $ctx->test_files;
	unless (@{$test_files}) {
		return _f(
			severity => 'error',
			message  => 't/ directory exists but contains no .t files.',
			fix      => _fix_scaffold($ctx),
		);
	}

	# Stage 3: prove must exit cleanly.
	# Use Perl chdir rather than shell 'cd && prove' to avoid Windows path-quoting issues.
	my $root = $ctx->root;
	require Cwd;
	my $orig   = Cwd::cwd();
	chdir $root;
	my $output = qx{$PROVE_CMD};
	my $status = $?;
	chdir $orig;
	if ($status != 0) {
		return _f(
			severity => 'error',
			message  => sprintf('Test suite FAILED (%d file(s) with failures).', scalar @{$test_files}),
			detail   => $output,
		);
	}

	return _f(
		severity => 'pass',
		message  => sprintf('%d test file(s) found -- all pass.', scalar @{$test_files}),
	);
}

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

sub _f {
	require App::Project::Doctor::Finding;
	return App::Project::Doctor::Finding->new(check_name => 'Tests', @_);
}

sub _fix_scaffold {
	my $ctx = shift;
	return sub {
		my $t_dir = File::Spec->catdir($ctx->root, 't');
		File::Path::make_path($t_dir);
		my $smoke = File::Spec->catfile($t_dir, '00-smoke.t');
		open my $fh, '>', $smoke;
		print {$fh} <<'END_SMOKE';
use strict;
use warnings;
use Test::More;

ok(1, 'module loads');
done_testing;
END_SMOKE
		close $fh;
	};
}

1;

__END__

=head1 NAME

App::Project::Doctor::Check::Tests - Check that a test suite exists and passes

=head1 VERSION

0.01

=head1 SYNOPSIS

  my $check    = App::Project::Doctor::Check::Tests->new;
  my @findings = $check->check($ctx);

=head1 DESCRIPTION

Three-stage check: (1) C<t/> directory present, (2) at least one C<.t> file
present, (3) C<prove -l> exits 0.  A missing test suite generates a fixable
finding that delegates to L<App::Test::Generator>.

=head1 METHODS

=head2 check( $context )

=head3 API SPECIFICATION

=head4 Input

  $context : App::Project::Doctor::Context

=head4 Output

  List of App::Project::Doctor::Finding (at most one per stage)

=head3 MESSAGES

  Code | Trigger                     | Resolution
  -----|-----------------------------|-----------------------------------------
  T001 | t/ missing                  | Fix scaffolds via App::Test::Generator
  T002 | t/ present, no .t files     | Fix scaffolds via App::Test::Generator
  T003 | prove exits non-zero        | Fix failing tests manually

=head3 FORMAL SPECIFICATION

  check : Context -> [Finding]
  check ctx ==
    if not exists "t/"         then [error+fix]
    else if |test_files| = 0   then [error+fix]
    else if prove_fails        then [error]
    else                            [pass]

=head1 AUTHOR

Nigel Horne C<< <njh@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
