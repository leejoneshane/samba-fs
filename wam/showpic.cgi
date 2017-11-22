#!/usr/bin/perl -U
# 程式：秀圖程式
# 版次：0.2
# 修改日期：2000/11/24
# 程式設計：李忠憲 (hp2013@ms8.hinet.net)
# 頁面美工：黃自強 (DD@mail.ysps.tp.edu.tw)
# 使用本程式必須遵守以下版權規定：
# 本程式遵守GPL 開放原始碼之精神，但僅授權您個人使用
# 此檔頭為本程式版權的一部份，請勿將此檔頭移除
# program: MCS(Muitl-users Counter Server)
# author: Shane Lee(hp2013@ms8.hinet.net)
# UI design: John Hwang(DD@mail.ysps.tp.edu.tw)
# This Software is Open Source, but for personal use only.
# This title is a part of License. You can NOT remove it.
#
@referers = ('localhost','127.0.0.1','eclass.meps.tp.edu.tw','172.22.1.26','163.21.228.26');
##############################################################################

$| = 1;
$deny = 0;
$error = 0;
$HOST=`/bin/hostname`;
$HOST=~ s/\n//g;
$config = "./wam.conf";

sub check_referer {
	my $check_referer = 0;
	my (@addrs);

	$addr = $ENV{'REMOTE_ADDR'};
	$url = $ENV{'HTTP_REFERER'};
	if ($url =~ m|https?://([^/]*)/~([\w.]+)/(.*)|i) {
		$user = $2;
		$page = $3;
	} else {
		$url =~ m|https?://([^/]*)/(.*)|i;
		$page = $2;
		$user = 'root';
	}
	foreach $referer (@referers) {
		if ($url =~ m|https?://([^/]*)$referer|i) {
			$check_referer = 1;
			last;
		}
	}
	$check_referer = 1 if ($url =~ m|https?://([^/]*)$HOST|i);
	@addrs = `ifconfig | grep 'inet addr:'`;
	foreach $addr (@addrs) {
		$addr =~ /inet addr:([\w.]*)/;
		if ($url =~ m|https?://([^/]*)$1|i) {
			$check_referer = 1;
			last;
		}
	}
	$check_referer = 1 if ($url eq '');
	if ($check_referer ne 1) {
		$deny = 1;
	}
}

sub get_form_data {
	my(@pairs, $pair, $name, $value);
	if($ENV{'REQUEST_METHOD'} =~ /get/i) {
		@pairs=split(/&/,$ENV{'QUERY_STRING'});
	} else {
		read(STDIN, $buffer, $ENV{'CONTENT_LENGTH'});
		@pairs=split(/&/,$buffer);
	}

	%DATA = ();
	foreach $pair (@pairs) {
		($name,$value) = split(/\=/,$pair);

		$name =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
		$name =~ s/~!/ ~!/g;
		$name =~ s/\+/ /g;
		$value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
		$value =~ s/~!/ ~!/g;
		$value =~ s/\+/ /g;

		if ($DATA{$name} ne '') {
			$DATA{$name} .= ",$value";
		} else {
			$DATA{$name} = $value;
		}
	}
}

sub read_conf {
	return if (!(-e $config));
	open (CFG, "< $config") || die;
	while ($line = <CFG>) {
		my($name, $value) = split(/:/, $line);
		$value =~ s/\n//g;
		$CONFIG{$name} = $value;
	}
	close(CFG);
}

sub err {
	$error ++;
}
#***********************************************************************************
# MAIN
#***********************************************************************************
&check_referer;
&get_form_data;
&read_conf;

$home_dir=(getpwnam($DATA{'user'}))[7];
$path=$home_dir.'/'.$CONFIG{'home_dir'}.$DATA{'path'};
#print $path;
#if ($DATA{'path'} =~ /(.+).jpg/) {
#	open (IMG, "< $path") || die;
#	print "Content-type: image/jpeg\n\n";
#	binmode(STDOUT);
#	print <IMG>;
#	close(IMG);
#} else {
	my $fsize = (stat($path))[7];
	open(REAL,"< $path") || die;
	binmode REAL;
	print "Content-length: $fsize\n";
	print "Content-type: application/octet-stream\n\n";
	while(read(REAL, $buf, 1024)) {
		print $buf;
	}
	close(REAL);
#}