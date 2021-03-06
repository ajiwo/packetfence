package pf::services::manager::suricata;
=head1 NAME

pf::services::manager::suricata add documentation

=cut

=head1 DESCRIPTION

pf::services::manager::suricata

=cut

use strict;
use warnings;
use pf::log;
use pf::file_paths qw(
    $install_dir
    $conf_dir
    $generated_conf_dir
);
use pf::constants;
use pf::config qw(%Config $monitor_int);
use Moo;
use pf::util qw(parse_template);
extends 'pf::services::manager';
with 'pf::services::manager::roles::pf_conf_trapping_engine';

has '+name' => ( default => sub { 'suricata' } );

sub _cmdLine {
    my $self = shift;
    $self->executable . " -c $install_dir/var/conf/suricata.yaml -i $monitor_int " . "-l $install_dir/var ";
}

sub generateConfig {
    require pf::violation_config;
    my $logger = get_logger();
    my %tags;
    $tags{'template'}      = "$conf_dir/suricata.yaml";
    $tags{'trapping-range'} = $Config{'trapping'}{'range'};
    $tags{'install_dir'}   = $install_dir;

    my @rules;
    if (exists $pf::violation_config::Violation_Config{'defaults'}{'snort_rules'}) {
        foreach my $rule ( split( /\s*,\s*/, $pf::violation_config::Violation_Config{'defaults'}{'snort_rules'} ) ) {

            #append install_dir if the path doesn't start with /
            $rule = " - $rule" if ( $rule !~ /^\// );
            push @rules, "$rule";
        }
    }
    $tags{'suricata_rules'} = join( "\n", @rules );
    $logger->info("generating $conf_dir/suricata.yaml");
    parse_template( \%tags, "$conf_dir/suricata.yaml", "$generated_conf_dir/suricata.yaml" );
    return $TRUE;
}

=head1 AUTHOR

Inverse inc. <info@inverse.ca>


=head1 COPYRIGHT

Copyright (C) 2005-2017 Inverse inc.

=head1 LICENSE

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
USA.

=cut

1;

