package App::Project::Doctor::Check::CI;

use strict;
use warnings;
use autodie qw(:all);

use parent -norequire, 'App::Project::Doctor::Check::Base';

use Carp qw(croak);
use Readonly;

our $VERSION = '0.01';

Readonly::Hash my %CI_PATHS => (
	'GitHub Actions' => '.github/workflows',
	'Travis CI'      => '.travis.yml',
	'CircleCI'       => '.circleci/config.yml',
	'AppVeyor'       => 'appveyor.yml',
);

sub name        { 'CI' }
sub description { 'At least one CI configuration is present.' }
sub can_fix     { 1 }
sub order       { 20 }

sub check {
	my ($self, $ctx) = @_;
	croak 'check requires an App::Project::Doctor::Context' unless ref $ctx;

	for my $label (sort keys %CI_PATHS) {
		if ($ctx->has_file($CI_PATHS{$label})) {
			return _f(
				severity => 'pass',
				message  => "CI configuration found ($label).",
			);
		}
	}

	return _f(
		severity => 'error',
		message  => 'No CI configuration found (GitHub Actions, Travis, CircleCI, AppVeyor).',
		fix      => sub {
			require App::GHGen;
			App::GHGen->new(root => $_[0]->root)->generate;
		},
	);
}

sub _f {
	require App::Project::Doctor::Finding;
	return App::Project::Doctor::Finding->new(check_name => 'CI', @_);
}

1;

__END__

=head1 NAME

App::Project::Doctor::Check::CI - Check that a CI configuration exists

=head1 DESCRIPTION

Reports an error when no supported CI configuration is found.  Detailed
GitHub Actions validation is handled by L<App::Project::Doctor::Check::GitHubActions>.

=head3 MESSAGES

  Code | Trigger           | Resolution
  -----|-------------------|------------------------------------
  C001 | No CI config      | Fix generates a workflow via App::GHGen

=head3 FORMAL SPECIFICATION

  check : Context -> [Finding]
  check ctx == if exists any CI_PATH in ctx then [pass] else [error+fix]

=head1 AUTHOR

Nigel Horne C<< <njh@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
