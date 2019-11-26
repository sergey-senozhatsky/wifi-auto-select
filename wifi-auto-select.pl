#!/usr/bin/perl

# Sergey Senozhatsky
# GPLv2

use strict;

my $scan_file = "/tmp/scan-log";
my %channels;

sub __exec($)
{
	my $c = shift;

	print "Run $c\n";
	`$c`;
	die("ERROR") if ($? != 0);
}

sub parse_cell($$)
{
	my $fh = shift;
	my $es = shift;

	my $current_cell = 1;
	my $channel;
	my $signal;
	my $ok = 0;

	while (my $rln = <$fh>) {
		chomp $rln;

		my $line = $rln;
		$line =~ s/^\s+//;

		if ($line =~ m/Cell /) {
			last if ($current_cell != 1);
			$current_cell = 0;
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

	if ($ok) {
		print "Found channel $channel, Q: $signal for $es\n";
		$channels{$channel} = $signal;
	}
}

sub generate_channels_map($$)
{
	my $if = shift;
	my $es = shift;

	print "Scanning for $es\n";

	__exec("ip link set $if up");
	__exec("iwlist $if scan > $scan_file");

	my $fh = open(my $fh, "<", $scan_file) or die("ERROR");

	while (my $rln = <$fh>) {
		chomp $rln;

		my $line = $rln;

		if ($line =~ m/Cell /) {
			parse_cell($fh, $es);
			next;
		}
	}

	unlink("/tmp/scan-log");
}

sub wait_for_packets($)
{
	my $if = shift;
	my $cnt = 0;

	my $rx = `ifconfig $if`;
	__exec("killall dhclient; echo");
	while ($rx =~ m/RX packets 0/ && $cnt < 5) {
		sleep(2);
		$cnt++;
		print "Waiting for packets\n";
	}

	if ($cnt < 5) {
		__exec("dhclient $if");
		return 1;
	}
	return 0;
}

sub try_channels($$)
{
	my $if = shift;
	my $es = shift;

	chomp $es;
	chomp $if;

	foreach my $c (sort { $channels{$b} <=> $channels{$a} } keys %channels) {
		__exec("ip link set $if down");
		__exec("ip link set $if up");

		__exec("iwconfig $if essid $es channel $c");
		return 0 if (wait_for_packets($if));
	}
	return -1;
}

sub main()
{
	my $ifname = $ARGV[0];
	my $essid = $ARGV[1];

	print "$ifname $essid\n";

	generate_channels_map($ifname, $essid);
	return try_channels($ifname, $essid);
}

main();
exit 0;
