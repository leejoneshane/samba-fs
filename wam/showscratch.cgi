#!/usr/bin/perl -U
# 程式：秀 Scratch 程式
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
@referers = ('localhost','127.0.0.1','c4f.meps.tp.edu.tw','172.22.8.1');
##############################################################################

$| = 1;
$deny = 0;
$error = 0;
$HOST=`/bin/hostname`;
$HOST=~ s/\n//g;
$config = "/usr/libexec/wam/wam.conf";
$lang_base = "/usr/libexec/wam/lang";

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

sub get_lang {
	my($line, @lines);
	$CONFIG{'lang'}='Big-5'  if ($CONFIG{'lang'} eq '');
	open (LANG, "$lang_base/$CONFIG{'lang'}") || die;
	while ($line = <LANG>) {
		my($name, $value) = split(/:::/, $line);
		$value =~ s/\n//g;
		$SYSMSG{$name} = $value;
	}
	close(LANG);
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
&get_lang;

$home_dir=(getpwnam($DATA{'user'}))[7];
@temp = split(/\//, $DATA{'path'});
foreach $subname (@temp) {
	$file=$subname;
}
$path=$home_dir.'/'.$CONFIG{'home_dir'}.$DATA{'path'};
system("rm -f /usr/libexec/wam/test.sb");
system("cp -f $path /usr/libexec/wam/test.sb > /dev/null");

print "Content-type: text/html\n\n";
print <<HTML;
<html>
<head>
<meta http-equiv=Content-Type content="$SYSMSG{'charset'}">
<META HTTP-EQUIV="Pargma" CONTENT="no-cache">
<script type="text/javascript" src="/swfobject.js"></script>
<script type="text/javascript"> 
var flashapp;
 
function installPlayer(swfName, swfID) {
	var flashvars = {project: '/test.sb?version=1'};
	var params = {
				   allowScriptAccess: 'sameDomain',
				   allowFullScreen: true
				 };
	var attributes = {};
	swfobject.embedSWF(swfName, swfID, 482, 401, '10.0', false, flashvars, params, attributes);
	flashapp = document.getElementById(swfID);
	flashapp.style.position = 'relative';
	flashapp.style.marginLeft = '19px';
	flashapp.parentNode.parentNode.style.overflow = 'visible'; // override CSS
	flashapp.style.zIndex = 1000; // put in front
	setPlayerSize(482, 401);
}
 
function JSsetPresentationMode(fillScreen) {
	if (fillScreen) {
		var r = flashapp.getBoundingClientRect();
		flashapp.style.left = -r.left + 'px';
		flashapp.style.top = -r.top + 'px';
		var h = window.innerHeight;
		var w = window.innerWidth;
		if (typeof(w) != 'number') { // If IE:
			w = document.documentElement.clientWidth;
			h = document.documentElement.clientHeight;
		}
		setPlayerSize(w, h - 10);
	} else {
		setPlayerSize(482, 401);
		flashapp.style.left = flashapp.style.top = '0px';
	}
}
 
function setPlayerSize(w, h) {
	var isFirefox = navigator.userAgent.toLowerCase().indexOf("firefox") > 0;
	if (isFirefox) w += 1;
	if (navigator.appName == 'Microsoft Internet Explorer') {
		flashapp.style.width = w;
		flashapp.style.height = h;
	} else {
		flashapp.width = w;
		flashapp.height = h;
	}
}
</script>
</head>
<body onload="installPlayer('Scratch.swf', 'PlayerOnly');">
<div id="PlayerOnly"> 
<p>你需要安裝 Flash Player 才能執行程式，或者<a href="showscratchbyjava">按這裡使用 Java 執行程式</a>。</p> 
</div>
<!--a href="/showpic/$file?user=$DATA{'user'}&path=$DATA{'path'}">$SYSMSG{'share_download'}</a-->
</body></html>
HTML
