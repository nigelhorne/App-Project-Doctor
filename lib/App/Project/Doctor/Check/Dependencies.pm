package App::Project::Doctor::Check::Dependencies;

use strict;
use warnings;
use autodie qw(:all);

use parent -norequire, 'App::Project::Doctor::Check::Base';

use Carp qw(croak carp);
use Readonly;

our $VERSION = '0.01';

# Modules that ship with Perl core and need no prereq declaration.
Readonly::Hash my %CORE => map { $_ => 1 } qw(
	strict warnings autodie Carp Scalar::Util List::Util POSIX Storable
	File::Spec File::Find File::Path File::Temp File::Basename
	Data::Dumper Exporter base parent overload constant vars utf8 feature
	Getopt::Long Pod::Usage Params::Validate Params::Get Readonly
);

sub name        { 'Dependencies' }
sub description { 'All used modules are declared as build prerequisites.' }
sub can_fix     { 1 }
sub order       { 50 }

sub check {
	my ($self, $ctx) = @_;
	croak 'check requires an App::Project::Doctor::Context' unless ref $ctx;

	my @findings;

	my $declared = _collect_declared($ctx);
	unless (defined $declared) {
		return _f(
			severity => 'warning',
			message  => 'No Makefile.PL, Build.PL, or cpanfile -- cannot check prerequisites.',
		);
	}

	my $used = _collect_used($ctx);

	for my $mod (sort keys %{$used}) {
		next if $CORE{$mod};
		next if $declared->{$mod};
		push @findings, _f(
			severity => 'error',
			message  => "Module '$mod' used in source but not declared as a prerequisite.",
			detail   => 'Found in: ' . join(', ', @{ $used->{$mod} }),
			fix      => _fix_add_prereq($ctx, $mod),
		);
	}

	unless (@findings) {
		push @findings, _f(
			severity => 'pass',
			message  => 'All non-core used modules are declared as prerequisites.',
		);
	}

	return @findings;
}

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

sub _f {
	require App::Project::Doctor::Finding;
	return App::Project::Doctor::Finding->new(check_name => 'Dependencies', @_);
}

sub _collect_used {
	my $ctx = shift;
	my %used;
	my $files = $ctx->perl_files('lib', 'script', 'bin');
	for my $rel (@{$files}) {
		my $content = eval { $ctx->slurp($rel) } // next;
		while ($content =~ /^\s*(?:use|require)\s+([\w:]+)/mg) {
			my $mod = $1;
			next if $mod =~ /^\d/;    # bare version number
			push @{ $used{$mod} }, $rel;
		}
	}
	return \%used;
}

sub _collect_declared {
	my $ctx = shift;

	if ($ctx->has_file('cpanfile')) {
		return _parse_cpanfile($ctx->abs_path('cpanfile'));
	}

	if ($ctx->has_file('Makefile.PL')) {
		require App::makefilepl2cpanfile;
		my $text = eval {
			App::makefilepl2cpanfile::generate(makefile => $ctx->abs_path('Makefile.PL'))
		};
		carp "App::makefilepl2cpanfile failed: $@" if $@;
		return defined $text ? _parse_cpanfile_text($text) : undef;
	}

	return undef;
}

sub _parse_cpanfile {
	my $path = shift;
	my %mods;
	open my $fh, '<', $path;
	while (<$fh>) {
		$mods{$1} = 1 if /^requires\s+['"]?([\w:]+)['"]?/;
	}
	close $fh;
	return \%mods;
}

sub _parse_cpanfile_text {
	my $text = shift;
	my %mods;
	for my $line (split /\n/, $text) {
		$mods{$1} = 1 if $line =~ /^requires\s+['"]?([\w:]+)['"]?/;
	}
	return \%mods;
}

sub _fix_add_prereq {
	my ($ctx, $mod) = @_;
	return sub {
		if ($ctx->has_file('cpanfile')) {
			open my $fh, '>>', $ctx->abs_path('cpanfile');
			print {$fh} "requires '$mod';\n";
			close $fh;
		} else {
			carp "Auto-fix for Makefile.PL not implemented; add '$mod' manually.";
		}
	};
}

1;

__END__

=head1 NAME

App::Project::Doctor::Check::Dependencies - Check that used modules are declared

=head1 DESCRIPTION

Scans all C<.pm>, C<.pl>, and script files for C<use>/C<require> statements
and compares against C<cpanfile> or C<Makefile.PL> prerequisites
(via L<App::makefilepl2cpanfile>).  Core modules are excluded.

=head3 MESSAGES

  Code | Trigger                      | Resolution
  -----|------------------------------|-------------------------------------------
  D001 | No builder or cpanfile found | Add a Makefile.PL or cpanfile
  D002 | Module used but not declared | Fix appends a 'requires' line to cpanfile

=head3 FORMAL SPECIFICATION

  used     = { mod | (use|require mod) in source_files ctx }
  declared = parse_prereqs (builder_file ctx)
  missing  = used \\ (declared union CORE)

  check ctx ==
    if declared = undef then [warning]
    else [error+fix per m in missing] ++ (if missing = {} then [pass] else [])

=head1 AUTHOR

Nigel Horne C<< <njh@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
