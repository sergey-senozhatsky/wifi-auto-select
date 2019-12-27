#!/usr/bin/perl

# Sergey Senozhatsky
# GPLv2

use strict;

my $scan_file = "/tmp/scan-log";
my %channels;

sub __my_exec($)
{
	my $c = shift;

	print "Run $c\n";
	`$c`;
	return $?;
}

sub my_exec($)
{
	my $c = shift;
	my $r = __my_exec($c);
	die("ERROR") if ($r != 0);
}

sub parse_cell($$)
{
	my $fh = shift;
	my $es = shift;

	my $current_cell = 1;
	my $channel = undef;
	my $signal;
	my $ok = 0;

	while (my $rln = <$fh>) {
		chomp $rln;

		my $line = $rln;
		$line =~ s/^\s+//;

		if ($line =~ m/Cell /) {
			if (defined $channel && $ok) {
				print "Channel: $channel, Q: $signal for $es\n";

				$ok = 0;
				$channels{$channel} = $signal;
				$channel = undef;
			}
			next;
		}

		if ($line =~ m/Channel:(\d+)/) {
			$channel = $1;
			next;
		}

		if ($line =~ m/Quality=(\d+)\/(\d+) .+/) {
			$signal = $1 / $2;
			next;
		}

		if (($line cmp "ESSID:\"$es\"") == 0) {
			$ok = 1;
			next;
		}
	}

	if (defined $channel && $ok) {
		print "Channel: $channel, Q: $signal for $es\n";
		$channels{$channel} = $signal;
	}
}

sub generate_channels_map($$)
{
	my $if = shift;
	my $es = shift;

	print "Scanning for $es\n";

	__my_exec("ip link set $if down");
	my_exec("ip link set $if up");
	my_exec("iwlist $if scan > $scan_file");

	my $fh = open(my $fh, "<", $scan_file) or die("ERROR");

	parse_cell($fh, $es);
	unlink("/tmp/scan-log");
}

sub dhcp($)
{
	my $if = shift;
	my $cnt = 0;
	my $r;

	__my_exec("rm /var/lib/dhclient/dhclient.leases");

	while ($cnt < 3) {
		__my_exec("killall dhclient");
		$r = __my_exec("dhclient $if");
		return 1 if ($r == 0);
		$cnt++;
		my_exec("dhclient -r -v $if");
		sleep(3);
	}
	return 0;
}

sub try_channels($$$)
{
	my $if = shift;
	my $es = shift;
	my $cf = shift;

	chomp $es;
	chomp $if;
	chomp $cf if (defined $cf);

	foreach my $c (sort { $channels{$b} <=> $channels{$a} } keys %channels) {
		my_exec("ip link set $if down");
		my_exec("ip link set $if up");

		my_exec("iwconfig $if essid $es mode managed channel $c");
		my_exec("wpa_supplicant -B -D wext -i wlp2s0 -c $cf") if (defined $cf);
		if (dhcp($if)) {
			my_exec("ntpdate asia.pool.ntp.org");
			return 0;
		}
	}
	return -1;
}

sub main()
{
	my $ifname = $ARGV[0];
	my $essid = $ARGV[1];
	my $config = $ARGV[2];

	print "$ifname $essid\n";

	generate_channels_map($ifname, $essid);
	return try_channels($ifname, $essid, $config);
}

main();
exit 0;
