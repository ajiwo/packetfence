package pf::services::manager::haproxy;
=head1 NAME

pf::services::manager::haproxy add documentation

=cut

=head1 DESCRIPTION

pf::services::manager::haproxy

=cut

use strict;
use warnings;
use Moo;
use IPC::Cmd qw[can_run run];
use List::MoreUtils qw(uniq);
use POSIX;
use pf::config qw(
    %Config
    $OS
    @listen_ints
    @dhcplistener_ints
    $management_network
    @portal_ints
);
use pf::file_paths qw(
    $generated_conf_dir
    $install_dir
    $conf_dir
    $var_dir
);
use pf::log;
use pf::util;
use pf::cluster;
use Template;

extends 'pf::services::manager';

has '+name' => (default => sub { 'haproxy' } );

has '+launcher' => (default => sub { "sudo %1\$s -f $generated_conf_dir/haproxy.conf -D -p $var_dir/run/haproxy.pid" } );

has '+shouldCheckup' => ( default => sub { 0 }  );

sub executable {
    my ($self) = @_;
    my $service = ( $Config{'services'}{"haproxy_binary"} || "$install_dir/sbin/haproxy" );
    return $service;
}

sub _number_cpus {
    my ($self) = @_;
    open my $cpuinfo, '<', '/proc/cpuinfo';
    my $cpu_cores = 0;
    foreach my $line (<$cpuinfo>)  {
        if ($line =~ /^cpu\scores\s+:\s+(\d+)/) {
            $cpu_cores = $cpu_cores + $1;
        }
    }
    close $cpuinfo;
    return $cpu_cores;
}

sub generateConfig {
    my ($self,$quick) = @_;
    my $logger = get_logger();
    my ($package, $filename, $line) = caller();

    my %tags;
    $tags{'template'} = "$conf_dir/haproxy.conf";
    $tags{'http'} = '';
    $tags{'mysql_backend'} = '';
    $tags{'var_dir'} = $var_dir;
    $tags{'conf_dir'} = $var_dir.'/conf';
    $tags{'cpu'} = '';
    $tags{'bind-process'} = '';
    my $bind_process = '';
    if ($self->_number_cpus > 1) {
        $tags{'cpu'} .= <<"EOT";
        nbproc 2
        cpu-map 1 1
        cpu-map 2 2
EOT
        $tags{'bind-process'} = 'bind-process 1';
        $bind_process = 'bind-process 2';
    }

    if ($OS eq 'debian') {
        $tags{'os_path'} = '/etc/haproxy/errors/';
    } else {
         $tags{'os_path'} = '/usr/share/haproxy/';
    }
    my @ints = uniq(@listen_ints,@dhcplistener_ints,map { $_->{'Tint'} } @portal_ints);
    my @portal_ip;
    foreach my $interface ( @ints ) {
        my $cfg = $Config{"interface $interface"};
        next unless $cfg;
        my $i = 0;
        if ($interface eq $management_network->tag('int')) {
            $tags{'active_active_ip'} = pf::cluster::management_cluster_ip() || $cfg->{'ip'};
            my @mysql_backend = map { $_->{management_ip} } pf::cluster::mysql_servers();
            push @mysql_backend, '127.0.0.1' if !@mysql_backend;
            foreach my $mysql_back (@mysql_backend) {
                # the second server (the one without the VIP) will be the prefered MySQL server
                if ($i == 0) {
                $tags{'mysql_backend'} .= <<"EOT";
    server MySQL$i $mysql_back:3306 check
EOT
                } else {
                $tags{'mysql_backend'} .= <<"EOT";
    server MySQL$i $mysql_back:3306 check backup
EOT
                }
            $i++;
            }
            my $cluster_ip = pf::cluster::cluster_ip($interface) || $cfg->{'ip'};
            my @backend_ip = values %{pf::cluster::members_ips($interface)}
            push @backend_ip, '127.0.0.1' if !@backend_ip;
            my $backend_ip_config = '';
            foreach my $back_ip ( @backend_ip ) {

                $backend_ip_config .= <<"EOT";
        server $back_ip $back_ip:80 check
EOT
            }

            $tags{'http'} .= <<"EOT";
frontend portal-http-mgmt
        bind $cluster_ip:80
        reqadd X-Forwarded-Proto:\\ http
        default_backend portal-mgmt-backend
        $bind_process

frontend portal-https-mgmt
        bind $cluster_ip:443 ssl no-sslv3 crt /usr/local/pf/conf/ssl/server.pem
        reqadd X-Forwarded-Proto:\\ https
        default_backend portal-mgmt-backend
        $bind_process

backend portal-mgmt-backend
        balance source
        option httpclose
        option forwardfor
$backend_ip_config

EOT
        }
        if ($cfg->{'type'} =~ /internal/ || $cfg->{'type'} =~ /portal/) {
            my $cluster_ip = pf::cluster::cluster_ip($interface) || $cfg->{'ip'};
            push @portal_ip, $cluster_ip;
            my @backend_ip = values %{pf::cluster::members_ips($interface)};
            push @backend_ip, '127.0.0.1' if !@backend_ip;
            my $backend_ip_config = '';
            foreach my $back_ip ( @backend_ip ) {

                $backend_ip_config .= <<"EOT";
        server $back_ip $back_ip:80 check
EOT
            }

            $tags{'http'} .= <<"EOT";
frontend portal-http-$cluster_ip
        bind $cluster_ip:80
        reqadd X-Forwarded-Proto:\\ http
        http-request lua.select
        use_backend %[var(req.action)]
        default_backend $cluster_ip-backend
        $bind_process

frontend portal-https-$cluster_ip
        bind $cluster_ip:443 ssl no-sslv3 crt /usr/local/pf/conf/ssl/server.pem
        reqadd X-Forwarded-Proto:\\ https
        use_backend %[var(req.action)]
        default_backend $cluster_ip-backend
        $bind_process

backend $cluster_ip-backend
        balance source
        option httpclose
        option forwardfor
$backend_ip_config

EOT

        }
    }

    parse_template( \%tags, "$conf_dir/haproxy.conf", "$generated_conf_dir/haproxy.conf" );

    push @portal_ip, $Config{'general'}{'hostname'}.".".$Config{'general'}{'domain'};

    my $vars = {
        portal_host => sub { return @portal_ip},
    };

    my $config_file = "passthrough.lua";
    my $tt = Template->new(ABSOLUTE => 1);
    $tt->process("$conf_dir/$config_file.tt", $vars, "$generated_conf_dir/$config_file") or die $tt->error();

    return 1;
}

sub preStartSetup {
    my ($self,$quick) = @_;
    $self->SUPER::preStartSetup($quick);
    return 1;
}

sub stop {
    my ($self,$quick) = @_;
    my $result = $self->SUPER::stop($quick);
    return $result;
}

sub isManaged {
    my ($self) = @_;
    return $cluster_enabled;
}

=head1 AUTHOR

Inverse inc. <info@inverse.ca>



=head1 COPYRIGHT

Copyright (C) 2005-2017 Inverse inc.

=head1 LICENSE

This program is free software; you can redistribute it and::or
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
