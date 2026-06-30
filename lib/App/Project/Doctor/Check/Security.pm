package App::Project::Doctor::Check::Security;

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

# Patterns that indicate hardcoded credentials.
Readonly::Array my @SECRET_PATTERNS => (
	qr/(?:password|passwd|secret|api_?key|token)\s*=\s*['"][^'"]{4,}['"]/i,
	qr/-----BEGIN (?:RSA |EC )?PRIVATE KEY-----/,
	qr/(?:AKIA|ASIA)[A-Z0-9]{16}/,    # AWS access key prefix
);

# ---------------------------------------------------------------------------
# Role interface
# ---------------------------------------------------------------------------

sub name        { 'Security' }
sub description { 'All modules use strict/warnings; no hardcoded credentials.' }
sub can_fix     { 1 }
sub order       { 60 }

sub check {
	my ($self, $ctx) = @_;
	croak 'check requires an App::Project::Doctor::Context' unless ref $ctx;

	my @findings;
	my $files = $ctx->perl_files('lib', 'script', 'bin');

	for my $rel (@{$files}) {
		my $content = eval { $ctx->slurp($rel) } // next;

		# --- strict / warnings -----------------------------------------------
		# Only flag .pm files and scripts; .t files are exempt.
		unless ($rel =~ /\.t$/) {
			unless ($content =~ /^\s*use\s+strict\b/m) {
				push @findings, _finding(
					severity => 'error',
					message  => "Missing 'use strict' in $rel.",
					file     => $rel,
					fix      => _fix_add_pragma($ctx, $rel, 'strict'),
				);
			}
			unless ($content =~ /^\s*use\s+warnings\b/m) {
				push @findings, _finding(
					severity => 'error',
					message  => "Missing 'use warnings' in $rel.",
					file     => $rel,
					fix      => _fix_add_pragma($ctx, $rel, 'warnings'),
				);
			}
		}

		# --- hardcoded credentials -------------------------------------------
		my @lines = split /\n/, $content;
		for my $i (0 .. $#lines) {
			for my $pat (@SECRET_PATTERNS) {
				if ($lines[$i] =~ $pat) {
					push @findings, _finding(
						severity => 'error',
						message  => "Possible hardcoded credential in $rel at line " . ($i + 1) . '.',
						file     => $rel,
						line     => $i + 1,
						detail   => 'Move secrets to environment variables or a config file.',
					);
					last;    # one finding per line is enough
				}
			}
		}
	}

	unless (@findings) {
		push @findings, _finding(
			severity => 'pass',
			message  => 'All checked files use strict/warnings; no credential patterns found.',
		);
	}

	return @findings;
}

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

sub _finding {
	require App::Project::Doctor::Finding;
	return App::Project::Doctor::Finding->new(check_name => 'Security', @_);
}

# Prepends 'use strict;' or 'use warnings;' after the package declaration.
sub _fix_add_pragma {
	my ($ctx, $rel, $pragma) = @_;
	return sub {
		my $abs = $ctx->abs_path($rel);
		open my $fh, '<', $abs;
		my @lines = <$fh>;
		close $fh;

		# Insert after the first 'package' line, or at the top if none.
		my $insert_after = 0;
		for my $i (0 .. $#lines) {
			if ($lines[$i] =~ /^\s*package\s+\S+/) {
				$insert_after = $i + 1;
				last;
			}
		}

		splice @lines, $insert_after, 0, "use $pragma;\n";

		open my $out, '>', $abs;
		print {$out} @lines;
		close $out;
	};
}

1;

__END__

=head1 NAME

App::Project::Doctor::Check::Security - Check for missing pragmas and hardcoded secrets

=head1 DESCRIPTION

Performs two security checks across all Perl source files:

=over 4

=item 1.

Verifies that C<use strict> and C<use warnings> are present in every C<.pm>
and script file.

=item 2.

Scans for common hardcoded credential patterns (passwords, API keys, AWS
access keys, private key headers).

=back

Fixes for missing pragmas are offered; credential findings must be resolved
manually.

=head3 MESSAGES

  Code | Trigger                       | Resolution
  -----|-------------------------------|-------------------------------------------
  S001 | Missing 'use strict'          | Fix inserts pragma after package declaration
  S002 | Missing 'use warnings'        | Fix inserts pragma after package declaration
  S003 | Possible hardcoded credential | Move to env var / config; manual fix required

=head3 FORMAL SPECIFICATION

  check : Context -> [Finding]

  check ctx ==
    concat [ check_file f | f <- perl_files ctx ]
    where
      check_file f ==
        strict_check f ++ warnings_check f ++ credential_check f
      strict_check f    == if not (use strict in f)    then [error+fix] else []
      warnings_check f  == if not (use warnings in f)  then [error+fix] else []
      credential_check f == [error per line matching SECRET_PATTERNS in f]

=head1 AUTHOR

Nigel Horne C<< <njh@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
