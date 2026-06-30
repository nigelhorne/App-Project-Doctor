package App::Project::Doctor::Check::Dependencies;

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

# Core modules that do not need to appear in prerequisites.
Readonly::Hash my %CORE_MODULES => map { $_ => 1 } qw(
	strict warnings autodie Carp Scalar::Util List::Util
	File::Spec File::Find File::Path File::Temp
	Data::Dumper POSIX Storable Exporter base parent
	overload constant vars utf8 feature
);

# ---------------------------------------------------------------------------
# Role interface
# ---------------------------------------------------------------------------

sub name        { 'Dependencies' }
sub description { 'All used modules are declared in build prerequisites.' }
sub can_fix     { 1 }
sub order       { 50 }

sub check {
	my ($self, $ctx) = @_;
	croak 'check requires an App::Project::Doctor::Context' unless ref $ctx;

	my @findings;

	# Collect all 'use' / 'require' statements from Perl source files.
	my $used = _collect_used_modules($ctx);

	# Collect declared prerequisites from the builder file.
	my $declared = _collect_declared_modules($ctx);

	unless (defined $declared) {
		push @findings, _finding(
			severity => 'warning',
			message  => 'No Makefile.PL, Build.PL, or cpanfile found -- cannot check prerequisites.',
		);
		return @findings;
	}

	# Report modules used but not declared (excluding core).
	for my $mod (sort keys %{$used}) {
		next if $CORE_MODULES{$mod};
		next if $declared->{$mod};
		push @findings, _finding(
			severity   => 'error',
			message    => "Module '$mod' is used in source but not declared as a prerequisite.",
			detail     => "Found in: " . join(', ', @{ $used->{$mod} }),
			fix        => _fix_add_prereq($ctx, $mod),
		);
	}

	unless (@findings) {
		push @findings, _finding(
			severity => 'pass',
			message  => 'All non-core used modules are declared as prerequisites.',
		);
	}

	return @findings;
}

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

sub _finding {
	require App::Project::Doctor::Finding;
	return App::Project::Doctor::Finding->new(check_name => 'Dependencies', @_);
}

# Scans all Perl files and returns { ModuleName => [$file1, $file2, ...] }.
sub _collect_used_modules {
	my $ctx = shift;
	my %used;
	my $files = $ctx->perl_files('lib', 'script', 'bin');
	for my $rel (@{$files}) {
		my $content = eval { $ctx->slurp($rel) } // next;
		while ($content =~ /^\s*(?:use|require)\s+([\w:]+)/mg) {
			my $mod = $1;
			next if $mod =~ /^\d/;    # version number, not a module
			push @{ $used{$mod} }, $rel;
		}
	}
	return \%used;
}

# Parses Makefile.PL or cpanfile and returns { ModuleName => version }.
# Delegates to App::makefilepl2cpanfile for Makefile.PL parsing.
sub _collect_declared_modules {
	my $ctx = shift;

	if ($ctx->has_file('cpanfile')) {
		return _parse_cpanfile($ctx->abs_path('cpanfile'));
	}

	if ($ctx->has_file('Makefile.PL')) {
		require App::makefilepl2cpanfile;
		my $data = eval {
			App::makefilepl2cpanfile->new->parse($ctx->abs_path('Makefile.PL'))
		};
		carp "App::makefilepl2cpanfile parse failed: $@" if $@;
		return $data;
	}

	return undef;
}

sub _parse_cpanfile {
	my $path = shift;
	my %mods;
	open my $fh, '<', $path;
	while (<$fh>) {
		if (/^requires\s+['"]?([\w:]+)['"]?/) {
			$mods{$1} = 0;
		}
	}
	close $fh;
	return \%mods;
}

# Fix: append a 'requires' line to cpanfile or Makefile.PL.
sub _fix_add_prereq {
	my ($ctx, $mod) = @_;
	return sub {
		if ($ctx->has_file('cpanfile')) {
			open my $fh, '>>', $ctx->abs_path('cpanfile');
			print {$fh} "requires '$mod';\n";
			close $fh;
		} elsif ($ctx->has_file('Makefile.PL')) {
			carp "Auto-fix for Makefile.PL not yet implemented; add '$mod' manually.";
		}
	};
}

1;

__END__

=head1 NAME

App::Project::Doctor::Check::Dependencies - Check that all used modules are declared

=head1 DESCRIPTION

Scans every C<.pm>, C<.pl>, and script file for C<use> and C<require>
statements, then compares the list against the declared prerequisites in
C<Makefile.PL> or C<cpanfile> (via L<App::makefilepl2cpanfile>).
Core modules are excluded automatically.

=head3 MESSAGES

  Code | Trigger                       | Resolution
  -----|-------------------------------|-------------------------------------------
  D001 | No builder file found         | Add a Makefile.PL or cpanfile
  D002 | Module used but not declared  | Fix appends 'requires' to cpanfile

=head3 FORMAL SPECIFICATION

  check : Context -> [Finding]

  used     = { mod | (use mod) in source_files ctx }
  declared = parse_prereqs (builder_file ctx)
  missing  = used \\ (declared union CORE_MODULES)

  check ctx ==
    if declared = undef then [warning]
    else [error + fix per m in missing] ++ (if missing = {} then [pass] else [])

=head1 AUTHOR

Nigel Horne C<< <njh@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
