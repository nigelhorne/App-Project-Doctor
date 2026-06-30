package App::Project::Doctor::Check::Role;

use strict;
use warnings;
use autodie qw(:all);

use Moo::Role;
use namespace::autoclean;
use Carp qw(croak carp);

our $VERSION = '0.01';

# ---------------------------------------------------------------------------
# Required interface -- every Check:: plugin must implement these
# ---------------------------------------------------------------------------

=head2 name (required)

Short identifier for this check, e.g. C<Tests> or C<GitHub Actions>.
Used as the label in the report table.

=cut

requires 'name';

=head2 description (required)

One-sentence description of what the check verifies.

=cut

requires 'description';

=head2 check (required)

  my @findings = $check->check($context);

Runs the check against the distro described by C<$context> and returns a
list of L<App::Project::Doctor::Finding> objects (empty list on a clean
pass).

=cut

requires 'check';

# ---------------------------------------------------------------------------
# Optional interface with sensible defaults
# ---------------------------------------------------------------------------

=head2 can_fix

Returns true when this check is capable of generating fixable findings.
Defaults to 0.

=cut

sub can_fix { 0 }

=head2 category

Returns a grouping label used when presenting results.
Defaults to C<general>.

=cut

sub category { 'general' }

=head2 order

Numeric sort key controlling presentation order in the report.
Lower numbers appear first.  Defaults to 50.

=cut

sub order { 50 }

1;

__END__

=head1 NAME

App::Project::Doctor::Check::Role - Moo::Role that every check plugin must consume

=head1 VERSION

0.01

=head1 SYNOPSIS

  package App::Project::Doctor::Check::MyCheck;

  use Moo;
  use namespace::autoclean;
  with 'App::Project::Doctor::Check::Role';

  sub name        { 'My Check' }
  sub description { 'Verifies something important.' }
  sub can_fix     { 1 }

  sub check {
      my ($self, $ctx) = @_;
      # Return list of App::Project::Doctor::Finding objects
      return () if $ctx->has_file('something-good');
      return App::Project::Doctor::Finding->new(
          severity   => 'error',
          message    => 'Missing something-good',
          check_name => $self->name,
          fix        => sub { ... },
      );
  }

  1;

=head1 DESCRIPTION

Defines the interface that all C<App::Project::Doctor::Check::*> plugins
must implement.  Consuming this role via C<with 'App::Project::Doctor::Check::Role'>
will cause a compile-time error if C<name>, C<description>, or C<check> are
not implemented.

=head1 REQUIRED METHODS

=head2 name

Short identifier string.

=head2 description

One-sentence purpose string.

=head2 check( $context )

Accepts an L<App::Project::Doctor::Context> and returns a list (not arrayref)
of L<App::Project::Doctor::Finding> objects.  Return an empty list for a
clean pass.

=head3 API SPECIFICATION

=head4 Input

  $context : App::Project::Doctor::Context

=head4 Output

  List of App::Project::Doctor::Finding  (may be empty)

=head1 OPTIONAL METHODS

=head2 can_fix

Boolean; default 0.

=head2 category

String grouping label; default C<general>.

=head2 order

Numeric sort key; default 50.

=head3 MESSAGES

  Code | Trigger | Resolution
  -----|---------|----------
  (none currently defined)

=head3 FORMAL SPECIFICATION

  Check == { name : String, description : String, check : Context -> [Finding] }

  run : Check x Context -> [Finding]
  run c ctx == check c ctx

=head1 AUTHOR

Nigel Horne C<< <njh@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
