package App::Project::Doctor::Fixer;

use strict;
use warnings;
use autodie qw(:all);

use Moo;
use namespace::autoclean;
use Carp qw(croak carp);
use Scalar::Util qw(blessed);

our $VERSION = '0.01';

# ---------------------------------------------------------------------------
# Attributes
# ---------------------------------------------------------------------------

has report => (
	is       => 'ro',
	required => 1,
	isa      => sub {
		croak 'report must be an App::Project::Doctor::Report'
			unless blessed($_[0]) && $_[0]->isa('App::Project::Doctor::Report');
	},
);

has context => (
	is       => 'ro',
	required => 1,
	isa      => sub {
		croak 'context must be an App::Project::Doctor::Context'
			unless blessed($_[0]) && $_[0]->isa('App::Project::Doctor::Context');
	},
);

# When true, apply all fixes without prompting.
has non_interactive => (
	is      => 'ro',
	default => 0,
);

# ---------------------------------------------------------------------------
# Public interface
# ---------------------------------------------------------------------------

=head2 run

Presents the numbered list of fixable findings, prompts the user, and
applies the chosen fixes.  Returns the count of fixes applied.

=cut

sub run {
	my $self = shift;

	my @fixable = $self->report->fixable;
	return 0 unless @fixable;

	if ($self->non_interactive) {
		return $self->_apply_all(\@fixable);
	}

	return $self->_interactive_loop(\@fixable);
}

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

# Prompts the user and dispatches based on their answer.
# Accepts: Y / y (all), N / n (none), or a comma-separated index list.
sub _interactive_loop {
	my ($self, $fixable) = @_;

	$self->_print_fix_list($fixable);

	print "\nWould you like me to apply them? [Y/n/1,3] ";
	my $answer = <STDIN>;
	return 0 unless defined $answer;
	chomp $answer;

	if ($answer eq '' || $answer =~ /^y(?:es)?$/i) {
		return $self->_apply_all($fixable);
	}

	if ($answer =~ /^n(?:o)?$/i) {
		print "No fixes applied.\n";
		return 0;
	}

	# Parse comma-separated indices (1-based).
	if ($answer =~ /^[\d,\s]+$/) {
		my @chosen = grep { defined && $_ >= 1 && $_ <= scalar @{$fixable} }
		             map  { int($_) }
		             split /[\s,]+/, $answer;
		my @selected = map { $fixable->[$_ - 1] } @chosen;
		return $self->_apply_all(\@selected);
	}

	print "Unrecognised input -- no fixes applied.\n";
	return 0;
}

sub _print_fix_list {
	my ($self, $fixable) = @_;
	print "\nSuggested fixes:\n";
	my $i = 0;
	for my $f (@{$fixable}) {
		printf "  [%d] %s\n", ++$i, $f->message;
	}
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
  my $applied = $fixer->run;

=head1 DESCRIPTION

Presents the user with a numbered list of fixable findings from the report,
reads their choice from STDIN, and applies the selected fixes by calling each
finding's C<fix> coderef with the current context.

Passing C<non_interactive =E<gt> 1> applies all fixes without prompting,
suitable for C<--fix> mode.

=head1 ATTRIBUTES

=head2 report

Required L<App::Project::Doctor::Report>.

=head2 context

Required L<App::Project::Doctor::Context>.

=head2 non_interactive

Boolean.  When true, all fixes are applied without prompting.  Default 0.

=head1 METHODS

=head2 run

Drives the fix loop.

=head3 API SPECIFICATION

=head4 Input

None (attributes set at construction).

=head4 Output

Integer -- number of fixes successfully applied.

=head3 MESSAGES

  Code | Trigger                   | Resolution
  -----|---------------------------|---------------------------------------
  F001 | A fix coderef throws      | Fix is skipped; error logged via carp

=head3 FORMAL SPECIFICATION

  run : Fixer -> N
  run fixer ==
    let fixable = { f in findings (report fixer) | is_fixable f }
    in  if non_interactive fixer
        then apply_all fixable
        else apply_chosen fixable (prompt fixable)

  apply_all   : [Finding] x Context -> N
  apply_chosen : [Finding] x Context x [Index] -> N

=head1 LIMITATIONS

Reads from STDIN; not suitable for non-interactive use without setting
C<non_interactive =E<gt> 1>.

=head1 AUTHOR

Nigel Horne C<< <njh@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
