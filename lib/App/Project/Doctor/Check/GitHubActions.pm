package App::Project::Doctor::Check::GitHubActions;

use strict;
use warnings;
use autodie qw(:all);

use Moo;
use namespace::autoclean;
use Carp qw(croak carp);

with 'App::Project::Doctor::Check::Role';

our $VERSION = '0.01';

sub name        { 'GitHub Actions' }
sub description { 'Workflow files are valid and follow best practices.' }
sub can_fix     { 1 }
sub order       { 25 }

sub check {
	my ($self, $ctx) = @_;
	croak 'check requires an App::Project::Doctor::Context' unless ref $ctx;

	my @findings;

	my $workflow_dir = '.github/workflows';
	unless ($ctx->has_file($workflow_dir)) {
		# No workflows at all -- CI check already covers the error case,
		# so here we just emit a pass-through info.
		return _finding(
			severity => 'info',
			message  => 'No .github/workflows/ directory -- skipping GitHub Actions validation.',
		);
	}

	my $workflow_files = $ctx->find_files($workflow_dir, qr/\.ya?ml$/i);

	unless (@{$workflow_files}) {
		push @findings, _finding(
			severity => 'warning',
			message  => '.github/workflows/ exists but contains no YAML workflow files.',
			fix      => _fix_generate($ctx),
		);
		return @findings;
	}

	# Delegate syntax validation to App::Workflow::Lint.
	for my $wf (@{$workflow_files}) {
		my @lint_errors = _lint_workflow($ctx->abs_path($wf));
		for my $err (@lint_errors) {
			push @findings, _finding(
				severity => 'error',
				message  => "Workflow '$wf': $err->{message}",
				file     => $wf,
				defined $err->{line} ? (line => $err->{line}) : (),
			);
		}
	}

	unless (@findings) {
		push @findings, _finding(
			severity => 'pass',
			message  => sprintf('%d workflow file(s) validated OK.', scalar @{$workflow_files}),
		);
	}

	return @findings;
}

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

sub _finding {
	require App::Project::Doctor::Finding;
	return App::Project::Doctor::Finding->new(check_name => 'GitHub Actions', @_);
}

# Calls App::Workflow::Lint and normalises its findings into a plain list of
# hashrefs { message => $str, line => $n|undef }.
sub _lint_workflow {
	my $abs_path = shift;
	require App::Workflow::Lint;
	my $linter   = App::Workflow::Lint->new;
	my @errors   = $linter->lint($abs_path);
	# Normalise -- actual return shape depends on App::Workflow::Lint's API;
	# adjust the mapping below to match that module's real interface.
	return map {
		ref $_ eq 'HASH'
			? { message => $_->{message} // "$_", line => $_->{line} }
			: { message => "$_" }
	} @errors;
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

App::Project::Doctor::Check::GitHubActions - Validate GitHub Actions workflow files

=head1 DESCRIPTION

Uses L<App::Workflow::Lint> to validate every C<.yml>/C<.yaml> file found
under C<.github/workflows/>.  When no workflow exists, a fix via
L<App::GHGen> is offered.

=head3 MESSAGES

  Code | Trigger                          | Resolution
  -----|----------------------------------|-------------------------------------
  G001 | workflows/ has no YAML files     | Fix generates a workflow via App::GHGen
  G002 | Lint error in a workflow file    | Edit the file to fix the syntax error

=head3 FORMAL SPECIFICATION

  check : Context -> [Finding]

  check ctx ==
    if not exists ".github/workflows" in ctx then [info]
    else if |workflow_files ctx| = 0         then [warning + fix]
    else union { lint_file f | f <- workflow_files ctx }
         where lint_file f == if lint_ok f then [] else [error per violation]

=head1 AUTHOR

Nigel Horne C<< <njh@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
