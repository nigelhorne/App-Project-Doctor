package App::Project::Doctor::Check::GitHubActions;

use strict;
use warnings;
use autodie qw(:all);

use parent -norequire, 'App::Project::Doctor::Check::Base';

use Carp qw(croak carp);
use Readonly;

our $VERSION = '0.01';

Readonly::Scalar my $WORKFLOW_DIR => '.github/workflows';

sub name        { 'GitHub Actions' }
sub description { 'Workflow files are present and lint cleanly.' }
sub can_fix     { 1 }
sub order       { 25 }

sub check {
	my ($self, $ctx) = @_;
	croak 'check requires an App::Project::Doctor::Context' unless ref $ctx;

	my @findings;

	# No .github/workflows/ -- CI check covers the error; emit info only.
	unless ($ctx->has_file($WORKFLOW_DIR)) {
		return _f(
			severity => 'info',
			message  => 'No .github/workflows/ -- skipping GitHub Actions validation.',
		);
	}

	my $workflow_files = $ctx->find_files($WORKFLOW_DIR, qr/\.ya?ml$/i);

	unless (@{$workflow_files}) {
		return _f(
			severity => 'warning',
			message  => '.github/workflows/ exists but contains no YAML files.',
			fix      => _fix_generate($ctx),
		);
	}

	# Delegate syntax validation to App::Workflow::Lint.
	for my $wf (@{$workflow_files}) {
		my @errors = _lint_workflow($ctx->abs_path($wf));
		for my $err (@errors) {
			push @findings, _f(
				severity => 'error',
				message  => "Workflow '$wf': $err->{message}",
				file     => $wf,
				defined $err->{line} ? (line => $err->{line}) : (),
			);
		}
	}

	unless (@findings) {
		push @findings, _f(
			severity => 'pass',
			message  => sprintf('%d workflow file(s) validated OK.', scalar @{$workflow_files}),
		);
	}

	return @findings;
}

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

sub _f {
	require App::Project::Doctor::Finding;
	return App::Project::Doctor::Finding->new(check_name => 'GitHub Actions', @_);
}

sub _lint_workflow {
	my $abs_path = shift;
	require App::Workflow::Lint;
	my $linter = App::Workflow::Lint->new;
	my @raw    = $linter->lint($abs_path);
	return map {
		ref $_ eq 'HASH'
			? { message => $_->{message} // "$_", line => $_->{line} }
			: { message => "$_" }
	} @raw;
}

sub _fix_generate {
	my $ctx = shift;
	return sub {
		require App::GHGen;
		App::GHGen->new(root => $ctx->root)->generate;
	};
}

1;

__END__

=head1 NAME

App::Project::Doctor::Check::GitHubActions - Validate GitHub Actions workflows

=head1 DESCRIPTION

Uses L<App::Workflow::Lint> to validate every C<.yml>/C<.yaml> file under
C<.github/workflows/>.  A fix via L<App::GHGen> is offered when no files exist.

=head3 MESSAGES

  Code | Trigger                       | Resolution
  -----|-------------------------------|-------------------------------------
  G001 | workflows/ has no YAML files  | Fix generates a workflow via App::GHGen
  G002 | Lint error in a workflow file | Edit the file to correct syntax

=head3 FORMAL SPECIFICATION

  check : Context -> [Finding]
  check ctx ==
    if not exists WORKFLOW_DIR then [info]
    else if |workflow_files| = 0 then [warning+fix]
    else concat { lint_errors f | f <- workflow_files }
         ++ (if all clean then [pass] else [])

=head1 AUTHOR

Nigel Horne C<< <njh@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
