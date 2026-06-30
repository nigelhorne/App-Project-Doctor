package App::Project::Doctor::Finding;

use strict;
use warnings;
use autodie qw(:all);

use Moo;
use namespace::autoclean;
use Carp qw(croak carp);
use Readonly;
use Scalar::Util qw(looks_like_number);

our $VERSION = '0.01';

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

Readonly::Hash my %SEVERITY_ICON => (
	error   => 'X',
	warning => '!',
	pass    => 'v',
	info    => 'i',
);

Readonly::Array my @VALID_SEVERITIES => qw(error warning pass info);

# ---------------------------------------------------------------------------
# Attributes
# ---------------------------------------------------------------------------

has severity => (
	is      => 'ro',
	isa     => sub {
		my $s = $_[0];
		croak "Invalid severity '$s'"
			unless grep { $_ eq $s } @VALID_SEVERITIES;
	},
	default => 'info',
);

has message => (
	is       => 'ro',
	isa      => sub { croak 'message must be a non-empty string' unless length $_[0] },
	required => 1,
);

has detail => (
	is      => 'ro',
	default => '',
);

# Coderef ($context) -> 1 on success, croaks on failure.
has fix => (
	is        => 'ro',
	predicate => 'has_fix',
);

has check_name => (
	is      => 'ro',
	default => 'Unknown',
);

has file => (
	is      => 'ro',
	default => '',
);

has line => (
	is  => 'ro',
	isa => sub { croak 'line must be a positive integer' if defined $_[0] && (!looks_like_number($_[0]) || $_[0] < 1) },
);

# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

=head2 is_fixable

Returns true when this finding carries an automated fix coderef.

=cut

sub is_fixable {
	my $self = shift;
	return $self->has_fix ? 1 : 0;
}

=head2 icon

Returns the single-ASCII-character status icon for this finding's severity.

=cut

sub icon {
	my $self = shift;
	return $SEVERITY_ICON{ $self->severity } // '?';
}

=head2 to_hash

Serialises the finding to a plain hash suitable for JSON encoding.
The C<fix> coderef is omitted.

=cut

sub to_hash {
	my $self = shift;
	return {
		severity   => $self->severity,
		message    => $self->message,
		detail     => $self->detail,
		check_name => $self->check_name,
		file       => $self->file,
		defined $self->line ? (line => $self->line) : (),
	};
}

1;

__END__

=head1 NAME

App::Project::Doctor::Finding - A single diagnostic finding produced by a check

=head1 VERSION

0.01

=head1 SYNOPSIS

  use App::Project::Doctor::Finding;

  my $f = App::Project::Doctor::Finding->new(
      severity   => 'error',
      message    => 'No test files found under t/',
      check_name => 'Tests',
      fix        => sub {
          my $ctx = shift;
          # scaffold a basic test file
      },
  );

  printf "[%s] %s\n", $f->icon, $f->message;
  $f->fix->($ctx) if $f->is_fixable;

=head1 DESCRIPTION

A value object representing one diagnostic item emitted by an
C<App::Project::Doctor::Check::*> plugin.  Each finding carries a severity
level, a human-readable message, an optional file/line location, and an
optional automated fix coderef.

=head1 ATTRIBUTES

=head2 severity

One of C<error>, C<warning>, C<pass>, or C<info>.  Defaults to C<info>.

=head2 message

Mandatory non-empty string.  Describes what was found.

=head2 detail

Optional extended explanation (multi-line is fine).

=head2 fix

Optional coderef C<($context) -E<gt> 1>.  When present, the finding is
considered fixable and the Fixer will offer to call it.

=head2 check_name

String identifying which C<Check::*> module produced this finding.

=head2 file

Path (relative to distro root) of the file the finding relates to, if any.

=head2 line

1-based line number within C<file>, if applicable.

=head1 METHODS

=head2 is_fixable

  my $bool = $finding->is_fixable;

Returns 1 when a C<fix> coderef is present, 0 otherwise.

=head3 API SPECIFICATION

=head4 Input

None (instance method, no arguments).

=head4 Output

Boolean integer: 1 or 0.

=head2 icon

  my $char = $finding->icon;

Returns a single ASCII character representing the severity:
C<v> (pass), C<X> (error), C<!> (warning), C<i> (info).

=head3 API SPECIFICATION

=head4 Input

None.

=head4 Output

Single ASCII character string.

=head2 to_hash

  my $href = $finding->to_hash;

Returns a plain hashref for JSON/TAP serialisation.  The C<fix> coderef is
excluded.

=head3 API SPECIFICATION

=head4 Input

None.

=head4 Output

Hashref with keys: C<severity>, C<message>, C<detail>, C<check_name>,
C<file>, and (if set) C<line>.

=head3 MESSAGES

  Code | Trigger | Resolution
  -----|---------|----------
  (none currently defined)

=head3 FORMAL SPECIFICATION

  Finding == [
    severity   : SEVERITY,
    message    : String,
    detail     : String,
    fix        : (Context -> Bool) | undefined,
    check_name : String,
    file       : String,
    line       : N | undefined
  ]

  SEVERITY ::= error | warning | pass | info

  is_fixable : Finding -> Bool
  is_fixable f == (fix f /= undefined)

=head1 LIMITATIONS

The C<fix> coderef is not serialisable and is omitted from C<to_hash>.

=head1 AUTHOR

Nigel Horne C<< <njh@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
