#!/usr/bin/perl -U
# 程式：多人計數伺服器
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
# 使用方法：
# 1. 使用 wam.cgi 來設定計數器
# 　在網頁上加入<img src=http://xxx.edu.tw:12000/count.cgi>
# 2. 想要直接指定風格，並且迴避 wam.cgi 對計數器的設定值
# 　在網頁上加入<img src=http://xxx.edu.tw:12000/count.cgi?page=aaa&style=bbb&check_ip=ccc&digits=ddd>
# 　xxx的位置填入提供計數器的主機名稱
# 　aaa的位置填入計數器所在的網頁
# 　bbb的位置填入計數器的圖檔所在的目錄名稱
# 　ccc的位置填入是否檢查 IP  是=yes 否=不填或其他字串
# 　ddd的位置填入計數器顯示位數
#
$config = '.counter_conf';
$counter_data = '.counter_data';
$cntdir = "/usr/libexec/wam/digits";
$deny_image = "/digits/deny.gif";
$error_image = "/digits/error.gif";
@referers = ('localhost','127.0.0.1');
##############################################################################

$| = 1;
$deny = 0;
$error = 0;
$HOST=`/bin/hostname`;
$HOST=~ s/\n//g;
require "./gifcat.pl";

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

sub err {
	$error ++;
}

sub read_conf {
	my($conf) = @_;
	if (-e $conf) {
		open (CFG, "< $conf") || &err;
		while ($line = <CFG>) {
			my($name, $value) = split(/:/, $line);
			$value =~ s/\n//g;
			$CONFIG{$name} = $value;
		}
		close(CFG);
	} else {
		$CONFIG{'start'} = 0;
		$CONFIG{'check_ip'} = 'yes';
		$CONFIG{'add'} = 1;
		$CONFIG{'digits'} = 5;
		$CONFIG{'style'} = '01';
		open (CFG, "> $conf") || &err;
		foreach $name (keys %CONFIG) {
			print CFG "$name:$CONFIG{$name}\n";
		}
		close(CFG);
	}
}

sub read_data {
	my($data) = @_;
	return if (!(-e $data));
	open (SCFG, "< $data") || &err;
	while ($line = <SCFG>) {
		my($urlname, $counter, $lastip) = split(/:/, $line);
		$lastip =~ s/\n//g;
		$COUNT{$urlname} = $counter;
		$LASTIP{$urlname} = $lastip;
	}
	close(SCFG);
}

sub write_data {
	my($data) = @_;
	open (SCFG, "> $data") || &err;
	flock(SCFG,2);
	foreach $name (keys %COUNT) {
		$str = join ':', $name, $COUNT{$name}, $LASTIP{$name}."\n";
		print SCFG $str;
	}
	flock(SCFG,8);
	close(SCFG);
}

#***********************************************************************************
# MAIN
#***********************************************************************************
&check_referer;
&get_form_data;
$home = (getpwnam($user))[7];
&read_conf("$home/$config");
&read_data("$home/$counter_data");
$page=$DATA{'page'} if (defined($DATA{'page'}));
$CONFIG{'style'}=$DATA{'style'} if (defined($DATA{'style'}));
$CONFIG{'digits'}=$DATA{'digits'} if (defined($DATA{'digits'}));
$CONFIG{'check_ip'}=$DATA{'check_ip'} if (defined($DATA{'check_ip'}));
if ($COUNT{$page} eq '') {
	$COUNT{$page} = $CONFIG{'start'} + 1;
	$LASTIP{$page} = $addr;
} else {
	if ($CONFIG{'check_ip'} eq 'yes') {
		if ($LASTIP{$page} ne $addr) {
			$COUNT{$page} += $CONFIG{'add'};
			$LASTIP{$page} = $addr;
		}
	} else {
		$COUNT{$page} += $CONFIG{'add'};
		$LASTIP{$page} = $addr;
	}
}
&write_data("$home/$counter_data");
if ($deny eq 1) {
	print "Location: $deny_image\n\n";
} elsif ($error != 0) {
	print "Location: $error_image\n\n";
} else {
	$style_path = "$cntdir/$CONFIG{'style'}";
	$count = $COUNT{$page};
	while (length($count) < $CONFIG{'digits'}) { $count = '0'.$count; }
	$length = length($count);
	@GIF=();
	foreach (0 .. $length-1) {
		$n = substr($count,$_,1);
		push(@GIF,"$style_path/$n\.gif");
	}
	print "Content-type: image/gif\n\n";
	binmode(STDOUT);
	print &gifcat(@GIF);
}
