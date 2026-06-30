use strict;
use warnings;

use Test::More;
use Test::Exception;
use File::Temp qw(tempdir);
use File::Spec;
use File::Path qw(make_path);

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

sub make_distro {
	my (%files) = @_;
	my $dir = tempdir(CLEANUP => 1);
	for my $rel (keys %files) {
		my $abs    = File::Spec->catfile($dir, split m{/}, $rel);
		(my $parent = $abs) =~ s{[/\\][^/\\]+$}{};
		make_path($parent) unless -d $parent;
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

subtest 'Finding -- construction and accessors' => sub {
	my $f = App::Project::Doctor::Finding->new(
		severity   => 'error',
		message    => 'Something is broken',
		check_name => 'Tests',
		detail     => 'More detail',
	);
	is $f->severity,   'error',           'severity';
	is $f->message,    'Something is broken', 'message';
	is $f->check_name, 'Tests',           'check_name';
	is $f->detail,     'More detail',     'detail';
	is $f->icon,       '[X]',             'error icon';
	ok !$f->is_fixable,                   'not fixable without coderef';
};

subtest 'Finding -- fixable coderef' => sub {
	my $called = 0;
	my $f = App::Project::Doctor::Finding->new(
		severity => 'warning',
		message  => 'Missing file',
		fix      => sub { $called++ },
	);
	ok $f->is_fixable, 'is_fixable when fix present';
	ok $f->has_fix,    'has_fix';
	$f->fix->();
	is $called, 1, 'fix coderef was called';
};

subtest 'Finding -- invalid severity croaks' => sub {
	throws_ok {
		App::Project::Doctor::Finding->new(severity => 'critical', message => 'x');
	} qr/Invalid severity/i, 'croaks on unknown severity';
};

subtest 'Finding -- empty message croaks' => sub {
	throws_ok {
		App::Project::Doctor::Finding->new(severity => 'info', message => '');
	} qr/message must be/i, 'croaks on empty message';
};

subtest 'Finding -- to_hash excludes fix coderef' => sub {
	my $f = App::Project::Doctor::Finding->new(
		severity => 'info',
		message  => 'All good',
		fix      => sub {},
	);
	my $h = $f->to_hash;
	ok !exists $h->{fix}, 'fix not in hash';
	is $h->{severity}, 'info', 'severity in hash';
	is $h->{message},  'All good', 'message in hash';
};

subtest 'Finding -- all severity icons' => sub {
	for my $sev (qw(error warning pass info)) {
		my $f = App::Project::Doctor::Finding->new(severity => $sev, message => 'x');
		like $f->icon, qr/^\[.\]$/, "icon for $sev is bracketed";
	}
};

# ---------------------------------------------------------------------------
# App::Project::Doctor::Context
# ---------------------------------------------------------------------------

require_ok 'App::Project::Doctor::Context';

subtest 'Context -- has_file' => sub {
	my $dir = make_distro('Makefile.PL' => "use ExtUtils::MakeMaker;\n");
	my $ctx = App::Project::Doctor::Context->new(root => $dir);
	ok  $ctx->has_file('Makefile.PL'), 'detects present file';
	ok !$ctx->has_file('nonexistent'), 'returns false for absent file';
};

subtest 'Context -- slurp' => sub {
	my $dir = make_distro('README' => "hello world\n");
	my $ctx = App::Project::Doctor::Context->new(root => $dir);
	is $ctx->slurp('README'), "hello world\n", 'slurp returns content';
};

subtest 'Context -- lib_modules' => sub {
	my $dir = make_distro(
		'lib/Foo.pm' => 'package Foo; 1;',
		'lib/Bar.pm' => 'package Bar; 1;',
	);
	my $ctx  = App::Project::Doctor::Context->new(root => $dir);
	my $mods = $ctx->lib_modules;
	is scalar @{$mods}, 2, 'finds both .pm files';
};

subtest 'Context -- invalid root croaks' => sub {
	throws_ok {
		App::Project::Doctor::Context->new(root => '/no/such/dir/xyzzy123');
	} qr/not a directory/i, 'croaks on non-directory root';
};

subtest 'Context -- root is made absolute' => sub {
	my $dir = make_distro('Makefile.PL' => '');
	my $ctx = App::Project::Doctor::Context->new(root => $dir);
	ok File::Spec->file_name_is_absolute($ctx->root), 'root is absolute';
};

# ---------------------------------------------------------------------------
# App::Project::Doctor::Check::Base
# ---------------------------------------------------------------------------

require_ok 'App::Project::Doctor::Check::Base';

subtest 'Check::Base -- required methods croak' => sub {
	my $base = App::Project::Doctor::Check::Base->new;
	throws_ok { $base->name }        qr/must implement name/,        'name croaks';
	throws_ok { $base->description } qr/must implement description/, 'description croaks';
	throws_ok { $base->check('x') }  qr/must implement check/,       'check croaks';
};

subtest 'Check::Base -- defaults' => sub {
	my $base = App::Project::Doctor::Check::Base->new;
	is $base->can_fix,  0,         'can_fix default 0';
	is $base->category, 'general', 'category default general';
	is $base->order,    50,        'order default 50';
};

{
	package My::TestCheck;
	use strict; use warnings;
	use parent -norequire, 'App::Project::Doctor::Check::Base';
	sub name        { 'TestCheck' }
	sub description { 'A test check.' }
	sub check       { () }
}

subtest 'Check::Base -- subclass works' => sub {
	my $c = My::TestCheck->new;
	is $c->name,        'TestCheck',     'name';
	is $c->description, 'A test check.', 'description';
	is $c->can_fix,     0,               'inherited can_fix';
};

# ---------------------------------------------------------------------------
# App::Project::Doctor::Report
# ---------------------------------------------------------------------------

require_ok 'App::Project::Doctor::Report';

subtest 'Report -- starts clean' => sub {
	my $r = App::Project::Doctor::Report->new;
	is $r->exit_code,    0, 'exit_code 0 on empty report';
	ok !$r->has_errors,     'no errors initially';
	ok !$r->has_warnings,   'no warnings initially';
};

subtest 'Report -- exit_code reflects errors' => sub {
	my $r = App::Project::Doctor::Report->new;
	$r->add_findings(
		App::Project::Doctor::Finding->new(severity => 'error', message => 'bad', check_name => 'X'),
	);
	is $r->exit_code, 1, 'exit_code 1 with error finding';
	ok $r->has_errors,   'has_errors true';
};

subtest 'Report -- add_findings chaining' => sub {
	my $r = App::Project::Doctor::Report->new;
	my $ret = $r->add_findings(
		App::Project::Doctor::Finding->new(severity => 'pass', message => 'ok', check_name => 'A'),
	);
	is $ret, $r, 'add_findings returns $self';
};

subtest 'Report -- add_findings rejects non-Finding' => sub {
	my $r = App::Project::Doctor::Report->new;
	throws_ok { $r->add_findings('not a finding') }
		qr/App::Project::Doctor::Finding/i, 'rejects plain string';
};

subtest 'Report -- render_text contains check name' => sub {
	my $r = App::Project::Doctor::Report->new;
	$r->add_findings(
		App::Project::Doctor::Finding->new(severity => 'pass', message => 'All ok', check_name => 'Tests'),
	);
	like $r->render_text, qr/Tests/, 'check name in output';
};

subtest 'Report -- render_json is parseable' => sub {
	my $r = App::Project::Doctor::Report->new;
	$r->add_findings(
		App::Project::Doctor::Finding->new(severity => 'info', message => 'note', check_name => 'Meta'),
	);
	my $json = $r->render_json;
	require JSON::MaybeXS;
	my $decoded = JSON::MaybeXS->new->decode($json);
	is ref $decoded, 'ARRAY', 'decodes to arrayref';
	is $decoded->[0]{check_name}, 'Meta', 'check_name in JSON';
};

subtest 'Report -- render_tap has TAP header' => sub {
	my $r = App::Project::Doctor::Report->new;
	$r->add_findings(
		App::Project::Doctor::Finding->new(severity => 'pass', message => 'ok', check_name => 'A'),
		App::Project::Doctor::Finding->new(severity => 'error', message => 'fail', check_name => 'B'),
	);
	my $tap = $r->render_tap;
	like $tap, qr/^1\.\.2/,    'TAP plan line';
	like $tap, qr/^ok 1/m,     'passing finding is ok';
	like $tap, qr/^not ok 2/m, 'error finding is not ok';
};

# ---------------------------------------------------------------------------
# App::Project::Doctor (integration, minimal)
# ---------------------------------------------------------------------------

require_ok 'App::Project::Doctor';

subtest 'Doctor -- run returns a Report' => sub {
	my $dir = make_distro('Makefile.PL' => "use ExtUtils::MakeMaker;\nWriteMakefile(NAME=>'Foo');\n");
	my $doc = App::Project::Doctor->new(
		path   => $dir,
		checks => ['CpanReadiness'],
	);
	my $report = $doc->run;
	isa_ok $report, 'App::Project::Doctor::Report';
};

subtest 'Doctor -- unknown root croaks' => sub {
	my $dir = tempdir(CLEANUP => 1);    # no builder file
	throws_ok { App::Project::Doctor->new(path => $dir)->run }
		qr/Cannot detect/i, 'croaks when no distribution root found';
};

subtest 'Doctor -- skip excludes checks' => sub {
	my $dir = make_distro('Makefile.PL' => '');
	my $doc = App::Project::Doctor->new(
		path  => $dir,
		skip  => ['CpanReadiness'],
		checks => ['CpanReadiness'],
	);
	my $report = $doc->run;
	my @names = map { $_->check_name } $report->all_findings;
	ok !grep { $_ eq 'CPAN Readiness' } @names, 'skipped check produces no findings';
};

done_testing;
