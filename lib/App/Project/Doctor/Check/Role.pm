package App::Project::Doctor::Check::Role;

# Compatibility shim -- the role has been replaced by the traditional OO
# base class App::Project::Doctor::Check::Base.
# This file exists only to avoid breaking any code that loaded it by name.

use parent -norequire, 'App::Project::Doctor::Check::Base';

our $VERSION = '0.01';

1;

__END__

=head1 NAME

App::Project::Doctor::Check::Role - Deprecated shim; use Check::Base instead

=head1 DESCRIPTION

Inherits from L<App::Project::Doctor::Check::Base>.  Present for backward
compatibility only.  New code should C<use parent 'App::Project::Doctor::Check::Base'>.

=head1 AUTHOR

Nigel Horne C<< <njh@bandsman.co.uk> >>

=head1 LICENSE

Copyright (C) 2026 Nigel Horne.
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
