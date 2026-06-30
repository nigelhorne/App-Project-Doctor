use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
	NAME             => 'App::Project::Doctor',
	AUTHOR           => 'Nigel Horne <njh@bandsman.co.uk>',
	VERSION_FROM     => 'lib/App/Project/Doctor.pm',
	ABSTRACT_FROM    => 'lib/App/Project/Doctor.pm',
	LICENSE          => 'gpl_2',
	MIN_PERL_VERSION => '5.016',
	EXE_FILES        => ['script/project-doctor'],
	PREREQ_PM        => {
		'autodie'                   => 0,
		'Carp'                      => 0,
		'Getopt::Long'              => '2.50',
		'Moo'                       => '2.0',
		'Moo::Role'                 => '2.0',
		'namespace::autoclean'      => 0,
		'Params::Get'               => 0,
		'Params::Validate'          => '1.29',
		'Pod::Checker'              => 0,
		'Readonly'                  => '2.05',
		'Scalar::Util'              => 0,
		'Term::ANSIColor'           => 0,
		'CPAN::Meta'                => 0,
		'File::Find'                => 0,
		'File::Spec'                => 0,
		'JSON::MaybeXS'             => 0,
		'App::Workflow::Lint'       => 0,
		'App::GHGen'                => 0,
		'App::makefilepl2cpanfile'  => 0,
		'App::Test::Generator'      => 0,
	},
	TEST_REQUIRES => {
		'Test::More'       => '1.30',
		'Test::Exception'  => 0,
		'File::Temp'       => 0,
	},
	META_MERGE => {
		'meta-spec' => { version => 2 },
		resources   => {
			repository => {
				type => 'git',
				url  => 'https://github.com/nigelhorne/App-Project-Doctor.git',
				web  => 'https://github.com/nigelhorne/App-Project-Doctor',
			},
			bugtracker => {
				web => 'https://github.com/nigelhorne/App-Project-Doctor/issues',
			},
		},
	},
	dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz' },
	clean => { FILES    => 'App-Project-Doctor-*' },
);
