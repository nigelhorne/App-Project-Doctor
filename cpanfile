# Generated from Makefile.PL using makefilepl2cpanfile

requires 'perl', '5.016';

requires 'App::GHGen';
requires 'App::Test::Generator';
requires 'App::Workflow::Lint';
requires 'App::makefilepl2cpanfile';
requires 'CPAN::Meta';
requires 'Carp';
requires 'File::Find';
requires 'File::Spec';
requires 'Getopt::Long', '2.50';
requires 'JSON::MaybeXS';
requires 'Params::Get';
requires 'Params::Validate', '1.29';
requires 'Pod::Checker';
requires 'Pod::Usage';
requires 'Readonly', '2.05';
requires 'Scalar::Util';
requires 'Term::ANSIColor';
requires 'autodie';

on 'test' => sub {
	requires 'File::Path';
	requires 'File::Temp';
	requires 'Test::Exception';
	requires 'Test::Memory::Cycle';
	requires 'Test::Mockingbird';
	requires 'Test::More', '1.30';
	requires 'Test::Most';
	requires 'Test::Returns';
};

on 'develop' => sub {
	requires 'Devel::Cover';
	requires 'Perl::Critic';
	requires 'Test::Pod';
	requires 'Test::Pod::Coverage';
};
