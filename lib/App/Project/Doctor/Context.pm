package App::Project::Doctor::Context;

use strict;
use warnings;
use autodie qw(:all);

use Moo;
use namespace::autoclean;
use Carp qw(croak carp);
use Readonly;
use File::Spec;
use File::Find ();

our $VERSION = '0.01';

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

Readonly::Array my @PERL_EXTENSIONS => qw(.pm .pl .t .PL);
Readonly::Array my @BUILDER_FILES   => qw(Makefile.PL Build.PL dist.ini);

# ---------------------------------------------------------------------------
# Attributes
# ---------------------------------------------------------------------------

has root => (
	is      => 'ro',
	isa     => sub { croak "root must be a directory" unless -d $_[0] },
	default => sub { '.' },
);

has verbose => (
	is      => 'ro',
	default => 0,
);

# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

=head2 has_file

Returns true when the given path (relative to distro root) exists on disk.

=cut

sub has_file {
	my ($self, $rel_path) = @_;
	croak 'has_file requires a relative path' unless defined $rel_path;
	return -e File::Spec->catfile($self->root, $rel_path);
}

=head2 abs_path

Returns the absolute path for a path relative to distro root.

=cut

sub abs_path {
	my ($self, $rel_path) = @_;
	croak 'abs_path requires a relative path' unless defined $rel_path;
	return File::Spec->catfile($self->root, $rel_path);
}

=head2 slurp

Reads and returns the entire content of a file relative to distro root.

=cut

sub slurp {
	my ($self, $rel_path) = @_;
	croak 'slurp requires a relative path' unless defined $rel_path;
	my $abs = $self->abs_path($rel_path);
	croak "File not found: $abs" unless -f $abs;
	open my $fh, '<:encoding(UTF-8)', $abs;
	local $/;
	my $content = <$fh>;
	close $fh;
	return $content;
}

=head2 perl_files

Returns an arrayref of paths (relative to distro root) for all Perl source
files found under the given directories (default: lib/, script/, t/).

=cut

sub perl_files {
	my ($self, @dirs) = @_;
	@dirs = ('lib', 'script', 'bin', 't') unless @dirs;

	my @found;
	for my $dir (@dirs) {
		my $abs_dir = $self->abs_path($dir);
		next unless -d $abs_dir;

		File::Find::find(
			{
				no_chdir => 1,
				wanted   => sub {
					return unless -f $_;
					my ($ext) = $_ =~ /(\.[^.]+)$/;
					return unless defined $ext;
					return unless grep { $ext eq $_ } @PERL_EXTENSIONS;
					# Store relative to distro root
					my $rel = File::Spec->abs2rel($_, $self->root);
					push @found, $rel;
				},
			},
			$abs_dir,
		);
	}

	return \@found;
}

=head2 lib_modules

Returns an arrayref of .pm paths (relative to root) under lib/.

=cut

sub lib_modules {
	my $self = shift;
	return $self->perl_files('lib');
}

=head2 test_files

Returns an arrayref of .t paths (relative to root) under t/.

=cut

sub test_files {
	my $self = shift;
	return $self->perl_files('t');
}

=head2 git_root

Returns the git repository root directory, or undef if not inside a git repo.

=cut

sub git_root {
	my $self = shift;
	# Probe without using autodie since we check the exit code manually
	my $result = do {
		local $@;
		eval {
			my $out = qx{git -C \Q${\$self->root}\E rev-parse --show-toplevel 2>/dev/null};
			chomp $out;
			$out;
		};
	};
	return ($result && length $result) ? $result : undef;
}

=head2 builder_file

Returns the name (relative to root) of the first found builder file
(Makefile.PL, Build.PL, dist.ini), or undef if none.

=cut

sub builder_file {
	my $self = shift;
	for my $f (@BUILDER_FILES) {
		return $f if $self->has_file($f);
	}
	return undef;
}

=head2 find_files

Returns an arrayref of all files under C<$dir> (relative to root) matching
the given extension or filename pattern (a plain string or qr// regex).

=cut

sub find_files {
	my ($self, $dir, $pattern) = @_;
	croak 'find_files requires a directory' unless defined $dir;

	my $abs_dir = $self->abs_path($dir);
	return [] unless -d $abs_dir;

	my @found;
	File::Find::find(
		{
			no_chdir => 1,
			wanted   => sub {
				return unless -f $_;
				my $rel = File::Spec->abs2rel($_, $self->root);
				if (ref $pattern eq 'Regexp') {
					push @found, $rel if $rel =~ $pattern;
				} elsif (defined $pattern) {
					push @found, $rel if $rel =~ /\Q$pattern\E$/;
				} else {
					push @found, $rel;
				}
			},
		},
		$abs_dir,
	);

	return \@found;
}

1;

__END__

=head1 NAME

App::Project::Doctor::Context - Distro filesystem context passed to all checks

=head1 VERSION

0.01

=head1 SYNOPSIS

  use App::Project::Doctor::Context;

  my $ctx = App::Project::Doctor::Context->new(
      root    => '/path/to/my-dist',
      verbose => 1,
  );

  my $modules = $ctx->lib_modules;
  my $content = $ctx->slurp('lib/My/Module.pm') if $ctx->has_file('lib/My/Module.pm');

=head1 DESCRIPTION

Encapsulates the path to the distribution root and provides a set of helper
methods for filesystem inspection.  All C<Check::*> plugins receive an
instance of this class; they must not access the filesystem directly.

=head1 ATTRIBUTES

=head2 root

Absolute or relative path to the distribution root directory.  Must be an
existing directory.  Defaults to C<.> (current working directory).

=head2 verbose

Boolean.  When true, checks may emit diagnostic output.  Defaults to 0.

=head1 METHODS

=head2 has_file( $rel_path )

Returns true when C<$rel_path> (relative to C<root>) exists on disk.

=head3 API SPECIFICATION

=head4 Input

  $rel_path : String -- path relative to distro root

=head4 Output

Boolean.

=head2 abs_path( $rel_path )

Returns the absolute filesystem path for C<$rel_path>.

=head3 API SPECIFICATION

=head4 Input

  $rel_path : String

=head4 Output

String -- absolute path.

=head2 slurp( $rel_path )

Reads and returns the entire UTF-8 content of C<$rel_path>.
Croaks if the file does not exist.

=head3 API SPECIFICATION

=head4 Input

  $rel_path : String

=head4 Output

String -- file content.

=head2 perl_files( @dirs )

Recursively collects all Perl source files (.pm, .pl, .t, .PL) under the
given directories.  Defaults to lib/, script/, bin/, t/.

=head3 API SPECIFICATION

=head4 Input

  @dirs : List of String -- directory names relative to root

=head4 Output

ArrayRef[String] -- relative paths.

=head2 lib_modules

Convenience wrapper: returns .pm files under lib/.

=head2 test_files

Convenience wrapper: returns .t files under t/.

=head2 git_root

Returns the git repository root or undef.

=head3 API SPECIFICATION

=head4 Input

None.

=head4 Output

String | undef.

=head2 builder_file

Returns the name of the first found Makefile.PL / Build.PL / dist.ini, or
undef.

=head3 API SPECIFICATION

=head4 Input

None.

=head4 Output

String | undef.

=head2 find_files( $dir, $pattern )

Returns all files under C<$dir> matching C<$pattern> (string suffix or qr//).

=head3 API SPECIFICATION

=head4 Input

  $dir     : String
  $pattern : String | Regexp | undef

=head4 Output

ArrayRef[String] -- relative paths.

=head3 MESSAGES

  Code | Trigger | Resolution
  -----|---------|----------
  (none currently defined)

=head3 FORMAL SPECIFICATION

  Context == [root : Path, verbose : Bool]

  has_file : Context x RelPath -> Bool
  has_file ctx p == exists (root ctx / p)

  slurp : Context x RelPath -> String
  dom slurp == { (ctx, p) | has_file ctx p }

=head1 LIMITATIONS

C<git_root> shells out to C<git>; it returns C<undef> when git is not
installed rather than croaking.

=head1 AUTHOR

Nigel Horne C<< <njh@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
