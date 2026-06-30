package App::Project::Doctor::Report;

use strict;
use warnings;
use autodie qw(:all);

use Moo;
use namespace::autoclean;
use Carp qw(croak carp);
use Readonly;
use Scalar::Util qw(blessed);

our $VERSION = '0.01';

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

Readonly::Hash my %ICON => (
	pass    => '[v]',
	error   => '[X]',
	warning => '[!]',
	info    => '[i]',
);

Readonly::Scalar my $LABEL_WIDTH => 18;

# ---------------------------------------------------------------------------
# Attributes
# ---------------------------------------------------------------------------

has _findings => (
	is      => 'ro',
	default => sub { [] },
);

# ---------------------------------------------------------------------------
# Public mutator
# ---------------------------------------------------------------------------

=head2 add_findings( @findings )

Appends one or more L<App::Project::Doctor::Finding> objects to the report.

=cut

sub add_findings {
	my ($self, @findings) = @_;
	for my $f (@findings) {
		croak 'Expected an App::Project::Doctor::Finding'
			unless blessed($f) && $f->isa('App::Project::Doctor::Finding');
		push @{ $self->_findings }, $f;
	}
	return $self;
}

# ---------------------------------------------------------------------------
# Accessors / filters
# ---------------------------------------------------------------------------

sub all_findings    { @{ $_[0]->_findings } }
sub errors          { grep { $_->severity eq 'error'   } @{ $_[0]->_findings } }
sub warnings        { grep { $_->severity eq 'warning' } @{ $_[0]->_findings } }
sub passes          { grep { $_->severity eq 'pass'    } @{ $_[0]->_findings } }
sub fixable         { grep { $_->is_fixable            } @{ $_[0]->_findings } }

sub has_errors      { scalar($_[0]->errors)   > 0 }
sub has_warnings    { scalar($_[0]->warnings) > 0 }

=head2 exit_code

Returns 0 when there are no errors, 1 otherwise.
Suitable for use as a process exit code.

=cut

sub exit_code { $_[0]->has_errors ? 1 : 0 }

# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

=head2 render_text( %opts )

Returns the full text report as a string.
Accepted options: C<verbose> (bool), C<color> (bool, default 1).

=cut

sub render_text {
	my ($self, %opts) = @_;
	my $verbose = $opts{verbose} // 0;
	my $color   = $opts{color}   // 1;

	my %by_check;
	my @order;
	for my $f ($self->all_findings) {
		my $name = $f->check_name;
		unless (exists $by_check{$name}) {
			push @order, $name;
			$by_check{$name} = [];
		}
		push @{ $by_check{$name} }, $f;
	}

	my @lines;
	for my $name (@order) {
		my @group = @{ $by_check{$name} };

		# The representative severity for the group is the worst finding.
		my $sev = _worst_severity(\@group);
		my $icon = $ICON{$sev} // '[?]';
		my $summary = _group_summary(\@group, $sev);

		push @lines, sprintf("  %-*s %s  %s", $LABEL_WIDTH, $icon, $name, $summary);

		if ($verbose) {
			for my $f (@group) {
				next if $f->severity eq 'pass';
				push @lines, sprintf("      -> %s", $f->message);
				push @lines, sprintf("         %s", $f->detail) if $f->detail;
			}
		}
	}

	my $error_count   = scalar($self->errors);
	my $warning_count = scalar($self->warnings);

	push @lines, '';
	push @lines, _summary_line($error_count, $warning_count);

	my @fixable = $self->fixable;
	if (@fixable) {
		push @lines, '';
		push @lines, 'Suggested fixes:';
		my $i = 0;
		for my $f (@fixable) {
			push @lines, sprintf("  [%d] %s", ++$i, $f->message);
		}
		push @lines, '';
		push @lines, 'Would you like me to apply them? [Y/n]';
	}

	return join("\n", @lines) . "\n";
}

=head2 render_json

Returns the findings serialised as a JSON string (requires JSON::MaybeXS).

=cut

sub render_json {
	my $self = shift;
	require JSON::MaybeXS;
	my $json = JSON::MaybeXS->new(utf8 => 1, pretty => 1, canonical => 1);
	return $json->encode([ map { $_->to_hash } $self->all_findings ]);
}

=head2 render_tap

Returns a TAP-format string for use in CI pipelines.

=cut

sub render_tap {
	my $self = shift;
	my @findings = $self->all_findings;
	my @lines    = ('1..' . scalar @findings);
	my $n        = 0;
	for my $f (@findings) {
		$n++;
		my $ok = $f->severity =~ /^(?:pass|info)$/ ? 'ok' : 'not ok';
		push @lines, sprintf("%s %d - [%s] %s", $ok, $n, $f->check_name, $f->message);
	}
	return join("\n", @lines) . "\n";
}

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

my %SEV_RANK = (error => 3, warning => 2, info => 1, pass => 0);

sub _worst_severity {
	my $group = shift;
	return (sort { $SEV_RANK{$b} <=> $SEV_RANK{$a} } map { $_->severity } @{$group})[0];
}

sub _group_summary {
	my ($group, $worst) = @_;
	# If any findings are not passes, show the first non-pass message.
	my ($first_bad) = grep { $_->severity ne 'pass' } @{$group};
	return $first_bad ? $first_bad->message : $group->[0]->message;
}

sub _summary_line {
	my ($errors, $warnings) = @_;
	my @parts;
	push @parts, "$errors error(s)"   if $errors;
	push @parts, "$warnings warning(s)" if $warnings;
	return @parts ? join(' - ', @parts) : 'No errors or warnings.';
}

1;

__END__

=head1 NAME

App::Project::Doctor::Report - Aggregate and render diagnostic findings

=head1 VERSION

0.01

=head1 SYNOPSIS

  use App::Project::Doctor::Report;

  my $report = App::Project::Doctor::Report->new;
  $report->add_findings(@findings);
  print $report->render_text(verbose => 1);
  exit $report->exit_code;

=head1 DESCRIPTION

Collects L<App::Project::Doctor::Finding> objects from all checks and
renders them in text, JSON, or TAP format.

=head1 METHODS

=head2 add_findings( @findings )

Appends findings.  Croaks if a non-Finding object is passed.

=head3 API SPECIFICATION

=head4 Input

  @findings : List of App::Project::Doctor::Finding

=head4 Output

Returns C<$self> for chaining.

=head2 render_text( %opts )

Renders a human-readable report.

=head3 API SPECIFICATION

=head4 Input

  verbose => Bool  (default 0)
  color   => Bool  (default 1)

=head4 Output

String.

=head2 render_json

=head3 API SPECIFICATION

=head4 Input

None.

=head4 Output

UTF-8 JSON string.

=head2 render_tap

=head3 API SPECIFICATION

=head4 Input

None.

=head4 Output

TAP-format string.

=head2 exit_code

Returns 0 (clean) or 1 (errors present).

=head3 API SPECIFICATION

=head4 Input

None.

=head4 Output

Integer 0 or 1.

=head3 MESSAGES

  Code | Trigger | Resolution
  -----|---------|----------
  (none currently defined)

=head3 FORMAL SPECIFICATION

  Report == { findings : [Finding] }

  has_errors : Report -> Bool
  has_errors r == exists f in findings r such that severity f = error

  exit_code : Report -> {0, 1}
  exit_code r == if has_errors r then 1 else 0

=head1 AUTHOR

Nigel Horne C<< <njh@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
