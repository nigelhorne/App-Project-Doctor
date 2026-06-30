package App::Project::Doctor::Check::Pod;

use strict;
use warnings;
use autodie qw(:all);

use Moo;
use namespace::autoclean;
use Carp qw(croak carp);

with 'App::Project::Doctor::Check::Role';

our $VERSION = '0.01';

sub name        { 'POD' }
sub description { 'Every .pm file contains valid, parseable POD documentation.' }
sub can_fix     { 1 }
sub order       { 40 }

sub check {
	my ($self, $ctx) = @_;
	croak 'check requires an App::Project::Doctor::Context' unless ref $ctx;

	my @findings;
	my $modules = $ctx->lib_modules;

	unless (@{$modules}) {
		return _finding(
			severity => 'info',
			message  => 'No .pm files found under lib/ -- nothing to check.',
		);
	}

	for my $mod (@{$modules}) {
		my @errors = _check_pod($ctx->abs_path($mod));
		for my $err (@errors) {
			push @findings, _finding(
				severity => 'error',
				message  => "POD error in $mod: $err->{message}",
				file     => $mod,
				defined $err->{line} ? (line => $err->{line}) : (),
			);
		}

		# Treat a module with no POD at all as an error.
		my $content = $ctx->slurp($mod);
		unless ($content =~ /^=\w/m) {
			push @findings, _finding(
				severity => 'error',
				message  => "No POD found in $mod.",
				file     => $mod,
				fix      => _fix_scaffold_pod($ctx, $mod),
			);
		}
	}

	unless (@findings) {
		push @findings, _finding(
			severity => 'pass',
			message  => sprintf('%d module(s) checked -- all have valid POD.', scalar @{$modules}),
		);
	}

	return @findings;
}

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

sub _finding {
	require App::Project::Doctor::Finding;
	return App::Project::Doctor::Finding->new(check_name => 'POD', @_);
}

# Run Pod::Checker and return a list of { message, line } hashrefs.
sub _check_pod {
	my $abs_path = shift;
	require Pod::Checker;

	my @errors;
	my $checker = Pod::Checker->new;

	# Pod::Checker writes to a filehandle; capture via a tied scalar.
	open my $out_fh, '>', \my $captured;
	$checker->parse_file($abs_path);
	close $out_fh;

	my $num_errors = $checker->num_errors;
	return () if $num_errors == 0;

	# Parse the captured output for structured data.
	for my $line (split /\n/, ($captured // '')) {
		next unless $line =~ /\S/;
		my ($lineno) = $line =~ /line\s+(\d+)/i;
		push @errors, {
			message => $line,
			defined $lineno ? (line => $lineno) : (),
		};
	}

	return @errors;
}

# Returns a fix coderef that appends a minimal POD skeleton to the module.
sub _fix_scaffold_pod {
	my ($ctx, $rel_path) = @_;
	return sub {
		my $abs = $ctx->abs_path($rel_path);

		# Derive package name from path for use in generated POD.
		(my $pkg = $rel_path) =~ s{lib/}{}; $pkg =~ s{/}{::}g; $pkg =~ s{\.pm$}{};

		open my $fh, '>>', $abs;
		print {$fh} <<"END_POD";

1;

__END__

=head1 NAME

$pkg - (description goes here)

=head1 SYNOPSIS

  use $pkg;

=head1 DESCRIPTION

(description goes here)

=head1 AUTHOR

Nigel Horne C<< <njh\@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
END_POD
		close $fh;
	};
}

1;

__END__

=head1 NAME

App::Project::Doctor::Check::Pod - Check POD presence and validity in all modules

=head1 DESCRIPTION

Uses L<Pod::Checker> to validate every C<.pm> file found under C<lib/>.
Also reports modules that have no POD at all.  A fix is offered that appends
a minimal POD skeleton so the author can fill it in.

=head3 MESSAGES

  Code | Trigger                    | Resolution
  -----|----------------------------|----------------------------------------------
  P001 | No POD in a .pm file       | Fix appends a skeleton; fill in manually
  P002 | Pod::Checker reports error  | Correct the malformed POD by hand

=head3 FORMAL SPECIFICATION

  check : Context -> [Finding]

  check ctx ==
    let mods = lib_modules ctx
    in  concat [ check_one m | m <- mods ]
        where check_one m ==
                pod_errors m ++ (if no_pod m then [error + fix] else [])

=head1 AUTHOR

Nigel Horne C<< <njh@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
