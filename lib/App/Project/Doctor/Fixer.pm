package App::Project::Doctor::Fixer;

use strict;
use warnings;
use autodie qw(:all);

use Carp qw(croak carp);
use Scalar::Util qw(blessed);
use Params::Validate::Strict qw(validate_strict);

our $VERSION = '0.01';

# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

sub new {
	my $class = shift;
	my $args = validate_strict(
		schema => {
			report          => { type => 'object'                          },
			context         => { type => 'object'                          },
			non_interactive => { type => 'scalar', optional => 1, default => 0 },
		},
		args => {@_},
	) or croak $@;
	croak "report must be an App::Project::Doctor::Report"
		unless blessed($args->{report}) && $args->{report}->isa('App::Project::Doctor::Report');
	croak "context must be an App::Project::Doctor::Context"
		unless blessed($args->{context}) && $args->{context}->isa('App::Project::Doctor::Context');
	return bless $args, $class;
}

# ---------------------------------------------------------------------------
# Accessors
# ---------------------------------------------------------------------------

sub report          { $_[0]->{report}          }
sub context         { $_[0]->{context}         }
sub non_interactive { $_[0]->{non_interactive} }

# ---------------------------------------------------------------------------
# Public interface
# ---------------------------------------------------------------------------

=head2 run

Presents fixable findings, prompts (or auto-applies in non-interactive mode),
and calls each selected C<fix> coderef.  Returns the count of fixes applied.

=cut

sub run {
	my $self    = shift;
	my @fixable = $self->report->fixable;
	return 0 unless @fixable;
	return $self->non_interactive
		? $self->_apply_all(\@fixable)
		: $self->_interactive_loop(\@fixable);
}

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

sub _interactive_loop {
	my ($self, $fixable) = @_;

	_print_fix_list($fixable);
	print "\nWould you like me to apply them? [Y/n/1,3] ";

	my $answer = <STDIN>;
	return 0 unless defined $answer;
	chomp $answer;

	return $self->_apply_all($fixable)
		if $answer eq '' || $answer =~ /^y(?:es)?$/i;

	if ($answer =~ /^n(?:o)?$/i) {
		print "No fixes applied.\n";
		return 0;
	}

	if ($answer =~ /^[\d,\s]+$/) {
		my $max = scalar @{$fixable};
		my %seen;
		my @indices  = grep { $_ >= 1 && $_ <= $max && !$seen{$_}++ }
		               map  { int($_) }
		               split /[\s,]+/, $answer;
		my @selected = map { $fixable->[$_ - 1] } @indices;
		return $self->_apply_all(\@selected);
	}

	print "Unrecognised input -- no fixes applied.\n";
	return 0;
}

sub _print_fix_list {
	my $fixable = shift;
	print "\nSuggested fixes:\n";
	my $i = 0;
	printf "  [%d] %s\n", ++$i, $_->message for @{$fixable};
}

sub _apply_all {
	my ($self, $fixable) = @_;
	my $count = 0;
	for my $f (@{$fixable}) {
		my $ok = eval { $f->fix->($self->context); 1 };
		if ($ok) {
			printf "  Applied: %s\n", $f->message;
			$count++;
		} else {
			carp "Fix failed for '" . $f->message . "': $@";
		}
	}
	printf "\n%d fix(es) applied.\n", $count;
	return $count;
}

1;

__END__

=head1 NAME

App::Project::Doctor::Fixer - Interactive fix application loop

=head1 VERSION

0.01

=head1 SYNOPSIS

  use App::Project::Doctor::Fixer;

  my $fixer = App::Project::Doctor::Fixer->new(
      report  => $report,
      context => $ctx,
  );
  my $count = $fixer->run;

=head1 DESCRIPTION

Presents fixable findings from a report, reads the user's choice from STDIN
(C<Y> all, C<n> none, or C<1,3> index list), and calls each selected
finding's C<fix> coderef with the current context.

Set C<non_interactive =E<gt> 1> to apply all fixes without prompting
(C<--fix> mode).

=head1 CONSTRUCTOR

=head2 new( %args )

=head3 API SPECIFICATION

=head4 Input

  report          : App::Project::Doctor::Report   required
  context         : App::Project::Doctor::Context  required
  non_interactive : Bool                           default 0

=head4 Output

Blessed hashref of type C<App::Project::Doctor::Fixer>.

=head1 ACCESSORS

C<report>, C<context>, C<non_interactive> -- read-only.

=head1 METHODS

=head2 run

=head3 API SPECIFICATION

=head4 Input

None.

=head4 Output

Integer -- number of fixes successfully applied.

=head3 MESSAGES

  Code | Trigger               | Resolution
  -----|-----------------------|---------------------------------------
  F001 | A fix coderef throws  | Fix skipped; error logged via carp

=head3 FORMAL SPECIFICATION

  run : Fixer -> N
  run fixer ==
    let fixable = { f in findings (report fixer) | is_fixable f }
    in  if non_interactive fixer
        then apply_all fixable
        else apply_chosen fixable (prompt fixable)

=head1 LIMITATIONS

Reads from STDIN; use C<non_interactive =E<gt> 1> in automated pipelines.

=head1 AUTHOR

Nigel Horne C<< <njh@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
