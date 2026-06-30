package App::Project::Doctor::Check::Meta;

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

Readonly::Array my @REQUIRED_META_FIELDS => qw(name version author abstract license);
Readonly::Array my @META_FILES           => qw(META.json META.yml MYMETA.json MYMETA.yml);

# ---------------------------------------------------------------------------
# Role interface
# ---------------------------------------------------------------------------

sub name        { 'META' }
sub description { 'META.yml or META.json is present, parseable, and complete.' }
sub can_fix     { 0 }
sub order       { 30 }

sub check {
	my ($self, $ctx) = @_;
	croak 'check requires an App::Project::Doctor::Context' unless ref $ctx;

	my @findings;

	# Look for a built META file; prefer .json over .yml.
	my ($meta_file) = grep { $ctx->has_file($_) } @META_FILES;

	unless ($meta_file) {
		# META files are generated at build time, so their absence in a
		# working tree is a warning, not an error.
		push @findings, _finding(
			severity => 'warning',
			message  => 'No META.{yml,json} found. Run Makefile.PL / dist.ini to generate one.',
			detail   => 'CPAN indexers require META to discover the distribution name and version.',
		);
		# Fall back to inspecting the builder file for completeness.
		push @findings, $self->_check_builder($ctx);
		return @findings;
	}

	# Parse with CPAN::Meta.
	my $meta_obj = _parse_meta($ctx->abs_path($meta_file));
	unless ($meta_obj) {
		push @findings, _finding(
			severity => 'error',
			message  => "Failed to parse $meta_file -- file may be malformed.",
			file     => $meta_file,
		);
		return @findings;
	}

	# Check required fields.
	my %data = %{ $meta_obj->as_struct };
	for my $field (@REQUIRED_META_FIELDS) {
		next if defined $data{$field} && length $data{$field};
		push @findings, _finding(
			severity => 'error',
			message  => "META field '$field' is missing or empty in $meta_file.",
			file     => $meta_file,
		);
	}

	unless (@findings) {
		push @findings, _finding(
			severity => 'pass',
			message  => "$meta_file is present and all required fields are populated.",
		);
	}

	return @findings;
}

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

sub _finding {
	require App::Project::Doctor::Finding;
	return App::Project::Doctor::Finding->new(check_name => 'META', @_);
}

sub _parse_meta {
	my $path = shift;
	require CPAN::Meta;
	my $meta = eval { CPAN::Meta->load_file($path) };
	carp "CPAN::Meta->load_file failed: $@" if $@;
	return $meta;
}

# Inspect Makefile.PL / dist.ini as a proxy when no META is built yet.
sub _check_builder {
	my ($self, $ctx) = @_;
	my @findings;
	my $builder = $ctx->builder_file;
	unless ($builder) {
		push @findings, _finding(
			severity => 'error',
			message  => 'No Makefile.PL, Build.PL, or dist.ini found.',
		);
	}
	return @findings;
}

1;

__END__

=head1 NAME

App::Project::Doctor::Check::Meta - Check META file presence and validity

=head1 DESCRIPTION

Verifies that at least one META file is present in the distribution and that
all fields required by the CPAN Meta specification are populated.
Uses L<CPAN::Meta> for parsing.

=head3 MESSAGES

  Code | Trigger                      | Resolution
  -----|------------------------------|-------------------------------------------
  M001 | No META.* file found         | Run Makefile.PL (or dist build) to generate
  M002 | META file parse failure      | Correct malformed YAML/JSON by hand
  M003 | Required META field missing  | Add field to Makefile.PL / dist.ini

=head3 FORMAL SPECIFICATION

  check : Context -> [Finding]

  check ctx ==
    let f = first META_FILE exists in ctx
    in  if f = undef then [warning, builder_check ctx]
        else let m = parse f
             in  if parse_fails then [error]
                 else [error per missing field in REQUIRED_FIELDS]
                      ++ if all_ok then [pass] else []

=head1 AUTHOR

Nigel Horne C<< <njh@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
