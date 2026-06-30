package App::Project::Doctor::Check::CI;

use strict;
use warnings;
use autodie qw(:all);

use Moo;
use namespace::autoclean;
use Carp qw(croak carp);

with 'App::Project::Doctor::Check::Role';

our $VERSION = '0.01';

sub name        { 'CI' }
sub description { 'Continuous integration configuration is present.' }
sub can_fix     { 1 }
sub order       { 20 }

sub check {
	my ($self, $ctx) = @_;
	croak 'check requires an App::Project::Doctor::Context' unless ref $ctx;

	# Detect any supported CI system before reporting failure.
	# GitHub Actions is checked in depth by Check::GitHubActions.
	my %ci_paths = (
		'GitHub Actions' => '.github/workflows',
		'Travis CI'      => '.travis.yml',
		'Circle CI'      => '.circleci/config.yml',
		'AppVeyor'       => 'appveyor.yml',
	);

	my @found = grep { $ctx->has_file($_) } values %ci_paths;

	if (@found) {
		return _finding(
			severity => 'pass',
			message  => 'CI configuration found.',
		);
	}

	return _finding(
		severity => 'error',
		message  => 'No CI configuration found (GitHub Actions, Travis, CircleCI, or AppVeyor).',
		fix      => _fix_create_workflow($ctx),
	);
}

sub _finding {
	require App::Project::Doctor::Finding;
	return App::Project::Doctor::Finding->new(check_name => 'CI', @_);
}

sub _fix_create_workflow {
	my $ctx = shift;
	return sub {
		require App::GHGen;
		App::GHGen->new(root => $ctx->root)->generate;
	};
}

1;

__END__

=head1 NAME

App::Project::Doctor::Check::CI - Check that a CI configuration exists

=head1 DESCRIPTION

Verifies that at least one supported CI configuration file is present.
Detailed validation of GitHub Actions workflow syntax is handled by
L<App::Project::Doctor::Check::GitHubActions>.

=head3 MESSAGES

  Code | Trigger              | Resolution
  -----|----------------------|----------------------------------
  C001 | No CI config found   | Fix creates .github/workflows/ via App::GHGen

=head3 FORMAL SPECIFICATION

  check : Context -> [Finding]
  check ctx == if (exists any ci_path in ctx) then [pass] else [error + fix]

=head1 AUTHOR

Nigel Horne C<< <njh@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
