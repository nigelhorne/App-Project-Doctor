package App::Project::Doctor::Check::Pod;

use strict;
use warnings;
use autodie qw(:all);

use parent -norequire, 'App::Project::Doctor::Check::Base';

use Carp qw(croak carp);

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
		return _f(
			severity => 'info',
			message  => 'No .pm files under lib/ -- nothing to check.',
		);
	}

	for my $mod (@{$modules}) {
		# Check for any POD at all.
		my $content = eval { $ctx->slurp($mod) } // do { carp "Cannot slurp $mod: $@"; next };
		unless ($content =~ /^=\w/m) {
			push @findings, _f(
				severity => 'error',
				message  => "No POD found in $mod.",
				file     => $mod,
				fix      => _fix_scaffold_pod($ctx, $mod),
			);
			next;
		}

		# Validate existing POD.
		for my $err (_check_pod($ctx->abs_path($mod))) {
			push @findings, _f(
				severity => 'error',
				message  => "POD error in $mod: $err->{message}",
				file     => $mod,
				defined $err->{line} ? (line => $err->{line}) : (),
			);
		}
	}

	unless (@findings) {
		push @findings, _f(
			severity => 'pass',
			message  => sprintf('%d module(s) checked -- all have valid POD.', scalar @{$modules}),
		);
	}

	return @findings;
}

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

sub _f {
	require App::Project::Doctor::Finding;
	return App::Project::Doctor::Finding->new(check_name => 'POD', @_);
}

sub _check_pod {
	my $abs_path = shift;
	require Pod::Checker;

	my $captured = '';
	open my $out_fh, '>', \$captured;
	my $checker = Pod::Checker->new;
	$checker->parse_from_file($abs_path, $out_fh);
	close $out_fh;

	return () if ($checker->num_errors // 0) == 0;

	my @errors;
	for my $line (split /\n/, $captured) {
		next unless $line =~ /\S/;
		my ($lineno) = $line =~ /line\s+(\d+)/i;
		push @errors, {
			message => $line,
			defined $lineno ? (line => $lineno) : (),
		};
	}
	return @errors;
}

sub _fix_scaffold_pod {
	my ($ctx, $rel_path) = @_;
	return sub {
		my $abs = $ctx->abs_path($rel_path);
		(my $pkg = $rel_path) =~ s{^lib/}{}; $pkg =~ s{/}{::}g; $pkg =~ s{\.pm$}{};
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

Uses L<Pod::Checker> to validate every C<.pm> under C<lib/>.  Modules with no
POD at all get a fixable finding that appends a minimal skeleton.

=head3 MESSAGES

  Code | Trigger                  | Resolution
  -----|--------------------------|-----------------------------------------------
  P001 | No POD in a .pm file     | Fix appends a skeleton; fill in by hand
  P002 | Pod::Checker error       | Correct the malformed POD

=head3 FORMAL SPECIFICATION

  check : Context -> [Finding]
  check ctx ==
    concat [ check_one m | m <- lib_modules ctx ]
    where check_one m ==
            (if no_pod m then [error+fix] else [])
            ++ pod_errors m

=head1 AUTHOR

Nigel Horne C<< <njh@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
