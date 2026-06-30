package App::Project::Doctor::Check::CpanReadiness;

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

# Acceptable version formats for CPAN.
Readonly::Scalar my $VERSION_RE => qr/^\d+\.\d+(?:\.\d+)?(?:_\d+)?$/;

# Files expected in a release-ready distribution.
Readonly::Array my @EXPECTED_FILES => qw(
	Changes
	MANIFEST
	README
);

# ---------------------------------------------------------------------------
# Role interface
# ---------------------------------------------------------------------------

sub name        { 'CPAN Readiness' }
sub description { 'Distribution is ready for CPAN upload (version, Changes, MANIFEST, README).' }
sub can_fix     { 0 }
sub order       { 90 }

sub check {
	my ($self, $ctx) = @_;
	croak 'check requires an App::Project::Doctor::Context' unless ref $ctx;

	my @findings;

	# --- Version format -------------------------------------------------------
	my $version = _read_version($ctx);
	if (defined $version) {
		if ($version !~ $VERSION_RE) {
			push @findings, _finding(
				severity => 'error',
				message  => "Version '$version' does not match CPAN version format (X.YY or X.YY.ZZ).",
			);
		}
	} else {
		push @findings, _finding(
			severity => 'warning',
			message  => 'Could not determine distribution version from main module.',
		);
	}

	# --- Required release files -----------------------------------------------
	for my $file (@EXPECTED_FILES) {
		unless ($ctx->has_file($file)) {
			push @findings, _finding(
				severity => 'error',
				message  => "'$file' is missing from the distribution root.",
				detail   => "CPAN indexers and users expect this file to be present.",
			);
		}
	}

	# --- Changes file has at least one entry ----------------------------------
	if ($ctx->has_file('Changes')) {
		my $content = $ctx->slurp('Changes');
		unless ($content =~ /^\d+\.\d+/m || $content =~ /^v\d+/m) {
			push @findings, _finding(
				severity => 'warning',
				message  => 'Changes file appears to have no version entries.',
				file     => 'Changes',
			);
		}
	}

	# --- MANIFEST is not stale (basic: file must exist, detail check skipped)
	# Full stale-MANIFEST detection requires running 'make manifest' which is
	# too invasive for a read-only check; flag it as info only.
	if ($ctx->has_file('MANIFEST')) {
		push @findings, _finding(
			severity => 'info',
			message  => 'MANIFEST present -- run `make manifest` to verify it is not stale.',
		);
	}

	unless (grep { $_->severity =~ /^(?:error|warning)$/ } @findings) {
		push @findings, _finding(
			severity => 'pass',
			message  => 'Distribution meets basic CPAN readiness requirements.',
		);
	}

	return @findings;
}

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

sub _finding {
	require App::Project::Doctor::Finding;
	return App::Project::Doctor::Finding->new(check_name => 'CPAN Readiness', @_);
}

# Reads $VERSION from the main module (the one whose path matches the dist name).
sub _read_version {
	my $ctx = shift;
	my $modules = $ctx->lib_modules;
	for my $mod (@{$modules}) {
		my $content = eval { $ctx->slurp($mod) } // next;
		if (my ($v) = $content =~ /^\s*our\s+\$VERSION\s*=\s*['"]?([\d._]+)['"]?/m) {
			return $v;
		}
	}
	return undef;
}

1;

__END__

=head1 NAME

App::Project::Doctor::Check::CpanReadiness - Check distribution is ready for CPAN upload

=head1 DESCRIPTION

Performs a final pre-flight check covering the items that would cause a CPAN
upload to fail or produce a poor user experience: version format, presence of
C<Changes>, C<MANIFEST>, and C<README>, and basic C<Changes> content.

=head3 MESSAGES

  Code | Trigger                         | Resolution
  -----|----------------------------------|-------------------------------------------
  R001 | Version format invalid           | Change to X.YY or X.YY.ZZ format
  R002 | Changes / MANIFEST / README missing | Create the missing file
  R003 | Changes has no version entries   | Add a changelog entry for the current version

=head3 FORMAL SPECIFICATION

  check : Context -> [Finding]

  check ctx ==
    version_check ctx
    ++ concat [file_check f | f <- EXPECTED_FILES]
    ++ changes_entry_check ctx
    where
      version_check ctx  == if not VERSION_RE matches (read_version ctx) then [error] else []
      file_check f       == if not exists f in ctx then [error] else []
      changes_entry_check == if Changes has no version line then [warning] else []

=head1 AUTHOR

Nigel Horne C<< <njh@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
