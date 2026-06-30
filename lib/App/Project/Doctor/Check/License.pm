package App::Project::Doctor::Check::License;

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

# Map of CPAN Meta license IDs to patterns we look for in a LICENSE file.
Readonly::Hash my %LICENSE_KEYWORDS => (
	perl_5  => qr/same terms as perl/i,
	gpl_2   => qr/GNU GENERAL PUBLIC LICENSE.*Version 2/si,
	gpl_3   => qr/GNU GENERAL PUBLIC LICENSE.*Version 3/si,
	lgpl_2  => qr/GNU LESSER GENERAL PUBLIC LICENSE.*Version 2/si,
	mit     => qr/Permission is hereby granted, free of charge/i,
	bsd     => qr/Redistribution and use in source and binary forms/i,
	artistic => qr/The Artistic License/i,
);

# ---------------------------------------------------------------------------
# Role interface
# ---------------------------------------------------------------------------

sub name        { 'Licensing' }
sub description { 'A LICENSE file is present and agrees with the META declaration.' }
sub can_fix     { 0 }
sub order       { 45 }

sub check {
	my ($self, $ctx) = @_;
	croak 'check requires an App::Project::Doctor::Context' unless ref $ctx;

	my @findings;

	# 1. LICENSE file must exist.
	unless ($ctx->has_file('LICENSE') || $ctx->has_file('LICENCE')) {
		push @findings, _finding(
			severity => 'error',
			message  => 'No LICENSE (or LICENCE) file found.',
			detail   => 'CPAN requires a license file for all distributions.',
		);
	}

	# 2. Cross-check META license field if a META file is available.
	my ($meta_file) = grep { $ctx->has_file($_) } qw(META.json META.yml MYMETA.json MYMETA.yml);
	if ($meta_file) {
		my $meta_license = _read_meta_license($ctx->abs_path($meta_file));
		if ($meta_license && $meta_license ne 'unknown') {
			my $pattern = $LICENSE_KEYWORDS{$meta_license};
			if ($pattern && $ctx->has_file('LICENSE')) {
				my $content = $ctx->slurp('LICENSE');
				unless ($content =~ $pattern) {
					push @findings, _finding(
						severity => 'warning',
						message  => "LICENSE file content does not match declared license '$meta_license' in $meta_file.",
					);
				}
			}
		}
	}

	unless (@findings) {
		push @findings, _finding(
			severity => 'pass',
			message  => 'LICENSE file present' . ($meta_file ? ' and consistent with META.' : '.'),
		);
	}

	return @findings;
}

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

sub _finding {
	require App::Project::Doctor::Finding;
	return App::Project::Doctor::Finding->new(check_name => 'Licensing', @_);
}

sub _read_meta_license {
	my $path = shift;
	require CPAN::Meta;
	my $meta = eval { CPAN::Meta->load_file($path) };
	return undef if $@;
	return $meta ? $meta->license : undef;
}

1;

__END__

=head1 NAME

App::Project::Doctor::Check::License - Check that a LICENSE file exists and matches META

=head1 DESCRIPTION

Verifies that a C<LICENSE> or C<LICENCE> file is present and, when a META
file is available, that the file content is consistent with the declared
license identifier.

=head3 MESSAGES

  Code | Trigger                        | Resolution
  -----|--------------------------------|--------------------------------------------
  L001 | LICENSE file absent            | Add a LICENSE file matching your META license
  L002 | LICENSE content != META value  | Ensure file matches the declared license ID

=head3 FORMAL SPECIFICATION

  check : Context -> [Finding]

  check ctx ==
    let has_lic  = exists "LICENSE" in ctx
        meta_lic = read_license (meta_file ctx)
        mismatch = has_lic /\ (meta_lic /= undef) /\ not matches meta_lic ctx
    in  (if not has_lic  then [error]        else [])
        ++ (if mismatch  then [warning]      else [])
        ++ (if has_lic /\ not mismatch then [pass] else [])

=head1 AUTHOR

Nigel Horne C<< <njh@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
