package App::Project::Doctor::Check::CpanReadiness;

use strict;
use warnings;
use autodie qw(:all);

use parent -norequire, 'App::Project::Doctor::Check::Base';

use Carp qw(croak carp);
use Readonly;

our $VERSION = '0.01';

Readonly::Scalar my $VERSION_RE    => qr/^\d+\.\d+(?:\.\d+)?(?:_\d+)?$/;
Readonly::Array  my @REQUIRED_FILES => qw(Changes MANIFEST README);

sub name        { 'CPAN Readiness' }
sub description { 'Version format, Changes, MANIFEST, and README are present.' }
sub can_fix     { 0 }
sub order       { 90 }

sub check {
	my ($self, $ctx) = @_;
	croak 'check requires an App::Project::Doctor::Context' unless ref $ctx;

	my @findings;

	# Version format check.
	my $version = _read_version($ctx);
	if (defined $version) {
		if ($version !~ $VERSION_RE) {
			push @findings, _f(
				severity => 'error',
				message  => "Version '$version' does not match CPAN format (X.YY or X.YY.ZZ).",
			);
		}
	} else {
		push @findings, _f(
			severity => 'warning',
			message  => 'Could not determine distribution version from any module.',
		);
	}

	# Required release files.
	for my $file (@REQUIRED_FILES) {
		unless ($ctx->has_file($file)) {
			push @findings, _f(
				severity => 'error',
				message  => "'$file' is missing from the distribution root.",
			);
		}
	}

	# Changes file must have at least one version entry.
	if ($ctx->has_file('Changes')) {
		my $content = $ctx->slurp('Changes');
		unless ($content =~ /^\d+\.\d+/m || $content =~ /^v\d+/m) {
			push @findings, _f(
				severity => 'warning',
				message  => 'Changes file has no version entries.',
				file     => 'Changes',
			);
		}
	}

	# MANIFEST stale-check requires 'make manifest' -- too invasive; just advise.
	if ($ctx->has_file('MANIFEST')) {
		push @findings, _f(
			severity => 'info',
			message  => "MANIFEST present -- run 'make manifest' to verify it is not stale.",
		);
	}

	# Emit a pass only when there are no errors or warnings.
	my $has_problem = grep { $_->severity =~ /^(?:error|warning)$/ } @findings;
	unless ($has_problem) {
		push @findings, _f(
			severity => 'pass',
			message  => 'Distribution meets basic CPAN readiness requirements.',
		);
	}

	return @findings;
}

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

sub _f {
	require App::Project::Doctor::Finding;
	return App::Project::Doctor::Finding->new(check_name => 'CPAN Readiness', @_);
}

sub _read_version {
	my $ctx = shift;
	for my $mod (@{ $ctx->lib_modules }) {
		my $content = eval { $ctx->slurp($mod) } // next;
		if (my ($v) = $content =~ /^\s*our\s+\$VERSION\s*=\s*['"]?([^'";\s]+)['"]?/m) {
			return $v;
		}
	}
	return undef;
}

1;

__END__

=head1 NAME

App::Project::Doctor::Check::CpanReadiness - Pre-upload CPAN readiness check

=head1 DESCRIPTION

Performs a final pre-flight sweep: version format, C<Changes>, C<MANIFEST>,
C<README> presence, and basic C<Changes> content.

=head3 MESSAGES

  Code | Trigger                          | Resolution
  -----|----------------------------------|-------------------------------------------
  R001 | Version format invalid           | Use X.YY or X.YY.ZZ
  R002 | Changes/MANIFEST/README missing  | Create the file
  R003 | Changes has no version entries   | Add a changelog entry

=head3 FORMAL SPECIFICATION

  check : Context -> [Finding]
  check ctx ==
    version_check ctx
    ++ [file_check f | f <- REQUIRED_FILES]
    ++ changes_check ctx
    ++ (if no problems then [pass] else [])

=head1 AUTHOR

Nigel Horne C<< <njh@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
