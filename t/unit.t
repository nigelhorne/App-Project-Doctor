use strict;
use warnings;

use Test::More;
use Test::Exception;
use File::Temp qw(tempdir);
use File::Spec;

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

sub make_distro {
	my (%files) = @_;
	my $dir = tempdir(CLEANUP => 1);
	for my $rel (keys %files) {
		my $abs = File::Spec->catfile($dir, $rel);
		(my $parent = $abs) =~ s{/[^/]+$}{};
		unless (-d $parent) {
			require File::Path;
			File::Path::make_path($parent);
		}
		open my $fh, '>', $abs;
		print {$fh} $files{$rel};
		close $fh;
	}
	return $dir;
}

# ---------------------------------------------------------------------------
# App::Project::Doctor::Finding
# ---------------------------------------------------------------------------

require_ok 'App::Project::Doctor::Finding';

subtest 'Finding -- basic construction' => sub {
	my $f = App::Project::Doctor::Finding->new(
		severity   => 'error',
		message    => 'Something is broken',
		check_name => 'Tests',
	);
	is $f->severity,   'error',               'severity';
	is $f->message,    'Something is broken', 'message';
	is $f->check_name, 'Tests',               'check_name';
	is $f->icon,       'X',                   'error icon';
	ok !$f->is_fixable,                       'not fixable without coderef';
};

subtest 'Finding -- fixable' => sub {
	my $called = 0;
	my $f = App::Project::Doctor::Finding->new(
		severity => 'warning',
		message  => 'Missing file',
		fix      => sub { $called++ },
	);
	ok $f->is_fixable, 'is_fixable when fix present';
	$f->fix->();
	is $called, 1, 'fix coderef was called';
};

subtest 'Finding -- invalid severity croaks' => sub {
	throws_ok {
		App::Project::Doctor::Finding->new(
			severity => 'critical',
			message  => 'x',
		);
	} qr/Invalid severity/i, 'croaks on bad severity';
};

subtest 'Finding -- missing message croaks' => sub {
	throws_ok {
		App::Project::Doctor::Finding->new(severity => 'info', message => '');
	} qr/message must be/i, 'croaks on empty message';
};

subtest 'Finding -- to_hash excludes fix' => sub {
	my $f = App::Project::Doctor::Finding->new(
		severity   => 'info',
		message    => 'All good',
		fix        => sub {},
	);
	my $h = $f->to_hash;
	ok !exists $h->{fix}, 'fix coderef not in hash';
	is $h->{severity}, 'info', 'severity in hash';
};

# ---------------------------------------------------------------------------
# App::Project::Doctor::Context
# ---------------------------------------------------------------------------

require_ok 'App::Project::Doctor::Context';

subtest 'Context -- has_file' => sub {
	my $dir = make_distro('Makefile.PL' => 'content');
	my $ctx = App::Project::Doctor::Context->new(root => $dir);
	ok  $ctx->has_file('Makefile.PL'), 'detects existing file';
	ok !$ctx->has_file('nonexistent'), 'returns false for missing file';
};

subtest 'Context -- slurp' => sub {
	my $dir = make_distro('README' => "hello world\n");
	my $ctx = App::Project::Doctor::Context->new(root => $dir);
	is $ctx->slurp('README'), "hello world\n", 'slurp returns content';
};

subtest 'Context -- perl_files collects .pm' => sub {
	my $dir = make_distro(
		'lib/Foo.pm' => 'package Foo; 1;',
		'lib/Bar.pm' => 'package Bar; 1;',
	);
	my $ctx  = App::Project::Doctor::Context->new(root => $dir);
	my $mods = $ctx->lib_modules;
	is scalar @{$mods}, 2, 'finds both modules';
};

subtest 'Context -- invalid root croaks' => sub {
	throws_ok {
		App::Project::Doctor::Context->new(root => '/no/such/directory/xyzzy');
	} qr/must be a directory/i, 'croaks on non-directory root';
};

# ---------------------------------------------------------------------------
# App::Project::Doctor::Report
# ---------------------------------------------------------------------------

require_ok 'App::Project::Doctor::Report';

subtest 'Report -- exit_code reflects errors' => sub {
	my $report = App::Project::Doctor::Report->new;
	is $report->exit_code, 0, 'clean report exits 0';

	$report->add_findings(
		App::Project::Doctor::Finding->new(severity => 'error', message => 'bad', check_name => 'X'),
	);
	is $report->exit_code, 1, 'report with error exits 1';
};

subtest 'Report -- render_text returns string' => sub {
	my $report = App::Project::Doctor::Report->new;
	$report->add_findings(
		App::Project::Doctor::Finding->new(severity => 'pass', message => 'All ok', check_name => 'Tests'),
	);
	my $text = $report->render_text;
	like $text, qr/Tests/, 'check name appears in output';
};

subtest 'Report -- render_json is valid JSON' => sub {
	my $report = App::Project::Doctor::Report->new;
	$report->add_findings(
		App::Project::Doctor::Finding->new(severity => 'info', message => 'note', check_name => 'Meta'),
	);
	my $json = $report->render_json;
	like $json, qr/\{/, 'looks like JSON';
	require JSON::MaybeXS;
	my $decoded = JSON::MaybeXS->new->decode($json);
	is ref $decoded, 'ARRAY', 'decodes to array';
};

subtest 'Report -- add_findings rejects non-Finding' => sub {
	my $report = App::Project::Doctor::Report->new;
	throws_ok { $report->add_findings('not a finding') } qr/App::Project::Doctor::Finding/i, 'rejects scalar';
};

# ---------------------------------------------------------------------------
# Check::Role (via a minimal anonymous class)
# ---------------------------------------------------------------------------

{
	package My::TestCheck;
	use Moo;
	with 'App::Project::Doctor::Check::Role';
	sub name        { 'TestCheck' }
	sub description { 'A test check.' }
	sub check       { () }
}

subtest 'Check::Role -- defaults' => sub {
	my $c = My::TestCheck->new;
	is $c->can_fix,  0,         'can_fix defaults to 0';
	is $c->category, 'general', 'category defaults to general';
	is $c->order,    50,        'order defaults to 50';
};

# ---------------------------------------------------------------------------
# App::Project::Doctor -- integration (minimal)
# ---------------------------------------------------------------------------

require_ok 'App::Project::Doctor';

subtest 'Doctor -- run returns a Report' => sub {
	my $dir = make_distro('Makefile.PL' => "use ExtUtils::MakeMaker;\nWriteMakefile(NAME=>'Foo');\n");
	my $doctor = App::Project::Doctor->new(
		path   => $dir,
		checks => ['CpanReadiness'],  # run just one check to keep test fast
	);
	my $report = $doctor->run;
	isa_ok $report, 'App::Project::Doctor::Report';
};

subtest 'Doctor -- unknown root croaks' => sub {
	my $dir = tempdir(CLEANUP => 1);   # no builder file present
	my $doctor = App::Project::Doctor->new(path => $dir);
	throws_ok { $doctor->run } qr/Cannot detect/i, 'croaks when no root found';
};

done_testing;
