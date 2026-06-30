package App::Project::Doctor::Finding;

use strict;
use warnings;
use autodie qw(:all);

use Carp qw(croak carp);
use Readonly;

use Params::Validate::Strict qw(validate_strict);

our $VERSION = '0.01';

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

Readonly::Hash my %SEVERITY_ICON => (
	error   => '[X]',
	warning => '[!]',
	pass    => '[v]',
	info    => '[i]',
);

Readonly::Hash my %VALID_SEVERITY => map { $_ => 1 } qw(error warning pass info);

# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

sub new {
	my $class = shift;
	# Validate message first so the documented error fires for undef and empty,
	# before Params::Validate can emit its own generic type error.
	my %raw = @_;
	croak 'message must be a non-empty string'
		unless defined $raw{message} && length $raw{message};
	my $args = validate_strict(
		schema => {
			severity   => { type => 'scalar',  optional => 1, default => 'info'    },
			message    => { type => 'scalar'                                        },
			detail     => { type => 'scalar',  optional => 1, default => ''        },
			fix        => { type => 'coderef', optional => 1                       },
			check_name => { type => 'scalar',  optional => 1, default => 'Unknown' },
			file       => { type => 'scalar',  optional => 1, default => ''        },
			line       => { type => 'integer', optional => 1, min => 1             },
		},
		args => {@_},
	) or croak $@;

	croak "Invalid severity '$args->{severity}'"
		unless $VALID_SEVERITY{ $args->{severity} };

	croak 'message must be a non-empty string'
		unless defined $args->{message} && length $args->{message};

	return bless $args, $class;
}

# ---------------------------------------------------------------------------
# Accessors
# ---------------------------------------------------------------------------

sub severity   { $_[0]->{severity}   }
sub message    { $_[0]->{message}    }
sub detail     { $_[0]->{detail}     }
sub fix        { $_[0]->{fix}        }
sub check_name { $_[0]->{check_name} }
sub file       { $_[0]->{file}       }
sub line       { $_[0]->{line}       }
sub has_fix    { defined $_[0]->{fix} }

# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

=head2 is_fixable

Returns 1 when this finding carries an automated fix coderef, 0 otherwise.

=cut

sub is_fixable {
	my $self = shift;
	return $self->has_fix ? 1 : 0;
}

=head2 icon

Returns the bracketed ASCII status icon for this finding's severity.

=cut

sub icon {
	my $self = shift;
	return $SEVERITY_ICON{ $self->severity } // '[?]';
}

=head2 to_hash

Serialises the finding to a plain hashref for JSON encoding.
The C<fix> coderef is omitted.

=cut

sub to_hash {
	my $self = shift;
	my %h = (
		severity   => $self->severity,
		message    => $self->message,
		detail     => $self->detail,
		check_name => $self->check_name,
		file       => $self->file,
	);
	$h{line} = $self->line if defined $self->line;
	return \%h;
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

  printf "%s %s\n", $f->icon, $f->message;
  $f->fix->($ctx) if $f->is_fixable;

=head1 DESCRIPTION

A value object representing one diagnostic item emitted by an
C<App::Project::Doctor::Check::*> plugin.  Each finding carries a severity
level, a human-readable message, an optional file/line location, and an
optional automated fix coderef.

=head1 CONSTRUCTOR

=head2 new( %args )

  my $finding = App::Project::Doctor::Finding->new(
      severity   => 'error',   # required: error|warning|pass|info
      message    => 'text',    # required non-empty string
      detail     => '...',     # optional extended explanation
      fix        => sub {...}, # optional coderef ($ctx) -> 1
      check_name => 'Tests',   # optional, default 'Unknown'
      file       => 'lib/F.pm',# optional
      line       => 42,        # optional positive integer
  );

Croaks on invalid severity or empty message.

=head3 API SPECIFICATION

=head4 Input

  severity   : 'error' | 'warning' | 'pass' | 'info'   default 'info'
  message    : non-empty String
  detail     : String                                    default ''
  fix        : CodeRef ($ctx) -> 1                       optional
  check_name : String                                    default 'Unknown'
  file       : String                                    default ''
  line       : positive Integer                          optional

=head4 Output

Blessed hashref of type C<App::Project::Doctor::Finding>.

=head1 ACCESSORS

C<severity>, C<message>, C<detail>, C<fix>, C<check_name>, C<file>, C<line>,
C<has_fix> -- all read-only.

=head1 METHODS

=head2 is_fixable

Returns 1 when C<fix> is defined, 0 otherwise.

=head3 API SPECIFICATION

=head4 Input

None.

=head4 Output

Integer 1 or 0.

=head2 icon

Returns the severity icon string: C<[v]> pass, C<[X]> error, C<[!]> warning,
C<[i]> info.

=head3 API SPECIFICATION

=head4 Input

None.

=head4 Output

String.

=head2 to_hash

Returns a plain hashref suitable for JSON encoding.  C<fix> is excluded.

=head3 API SPECIFICATION

=head4 Input

None.

=head4 Output

HashRef with keys: severity, message, detail, check_name, file, line (if set).

=head3 MESSAGES

  Code | Trigger                       | Resolution
  -----|-------------------------------|----------------------------
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
