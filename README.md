## run

Detects the distro root, instantiates all enabled checks, runs them in
order, and returns an [App::Project::Doctor::Report](https://metacpan.org/pod/App%3A%3AProject%3A%3ADoctor%3A%3AReport).

# NAME

App::Project::Doctor - Unified pre-release health check for Perl distributions

# VERSION

0.01

# SYNOPSIS

    # Command line
    project-doctor [--check=Tests,CI] [--skip=Meta] [--fix] [PATH]

    # Programmatic
    use App::Project::Doctor;

    my $doctor = App::Project::Doctor->new(
        path    => '/path/to/my-dist',
        verbose => 1,
    );
    my $report = $doctor->run;
    print $report->render_text;
    exit $report->exit_code;

# DESCRIPTION

`App::Project::Doctor` orchestrates a suite of diagnostic checks against a
Perl CPAN distribution.  It combines the functionality of:

- [App::Workflow::Lint](https://metacpan.org/pod/App%3A%3AWorkflow%3A%3ALint)  -- GitHub Actions workflow validation
- [App::GHGen](https://metacpan.org/pod/App%3A%3AGHGen)  -- GitHub Actions workflow generation
- [App::makefilepl2cpanfile](https://metacpan.org/pod/App%3A%3Amakefilepl2cpanfile)  -- dependency extraction
- [App::Test::Generator](https://metacpan.org/pod/App%3A%3ATest%3A%3AGenerator)  -- test scaffolding

into a single interactive tool designed to be run before every CPAN upload.
Each check produces a list of [App::Project::Doctor::Finding](https://metacpan.org/pod/App%3A%3AProject%3A%3ADoctor%3A%3AFinding) objects.
Findings with associated fix coderefs are offered interactively.

# ATTRIBUTES

## path

Path from which to detect the distribution root.  Defaults to `.`
(current working directory).  The root is the nearest ancestor directory
containing `Makefile.PL`, `Build.PL`, `dist.ini`, or `cpanfile`.

## checks

ArrayRef of check class name suffixes to run.  Defaults to all checks in
the canonical order:

    Tests CI GitHubActions Meta Pod Dependencies License Security CpanReadiness

## skip

ArrayRef of check names to exclude (case-insensitive).  Takes precedence
over `checks`.

## verbose

Boolean.  When true, each check's name is printed as it starts.  Default 0.

# METHODS

## run

Runs all enabled checks and returns an [App::Project::Doctor::Report](https://metacpan.org/pod/App%3A%3AProject%3A%3ADoctor%3A%3AReport).

### API SPECIFICATION

#### Input

None (configuration via constructor attributes).

#### Output

[App::Project::Doctor::Report](https://metacpan.org/pod/App%3A%3AProject%3A%3ADoctor%3A%3AReport) instance.

### MESSAGES

    Code | Trigger                          | Resolution
    -----|----------------------------------|---------------------------------------
    DR01 | Cannot detect distribution root  | Run from within a distribution directory
    DR02 | A check module cannot be loaded  | Install the check's prerequisites

### FORMAL SPECIFICATION

    Doctor == { path : Path, checks : [CheckName], skip : [CheckName], verbose : Bool }

    run : Doctor -> Report
    run d ==
      let root     = detect_root (path d)
          ctx      = Context { root, verbose = verbose d }
          enabled  = sort_by_order (checks d \\ skip d)
          findings = concat [ check c ctx | c <- enabled ]
      in  Report { findings }

    detect_root : Path -> Path | undefined
    detect_root p == nearest ancestor of p containing a ROOT_MARKER file

# LIMITATIONS

Check execution is sequential.  No parallelism is implemented.
The distro root detection halts at the filesystem root; very deep directory
trees may cause a perceptible delay.

# AUTHOR

Nigel Horne `<njh@bandsman.co.uk>`

# LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
