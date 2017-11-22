#!/usr/bin/perl -U
# 程式：線上帳號管理程式
# 版次：1.62
# 修改日期：2001/7/18
# 程式設計：李忠憲 (hp2013@ms8.hinet.net)
# 頁面美工：黃自強 (dd@mail.ysps.tp.edu.tw)
# 特別感謝半點心工作坊林朝敏(prolin@sy3es.tnc.edu.tw)提供密碼檢查javascript程式
# 使用本程式必須遵守以下版權規定：
# 本程式遵守GPL 開放原始碼之精神，但僅授權教育用途或您個人使用
# 此檔頭為本程式版權的一部份，請勿將此檔頭移除
# program: WAM(Web-Base Accounts Manager)
# author: Shane Lee(hp2013@ms8.hinet.net)
# UI design: John Hwang(dd@mail.ysps.tp.edu.tw)
# special thanx prolin(prolin@sy3es.tnc.edu.tw) suport the passwd-checking javascript
# This Software is Open Source, but for personal use only.
# This title is a part of License. You can NOT remove it.
#
use FCGI;
use MD5;
use IO::Socket;
use Quota;
use strict;
#use utf8;
no strict 'vars';

$config = "./wam.conf";
$gconfig = "./group.conf";
$share_conf = "./share.conf";
$cgi_url = "/wam.cgi";
$cnt_url = "/count_demo.cgi";
$account = "./account.lst";
$quota_temp = "./quota.tmp";
$tmp_index = "./index.tmp";
$tmp_album = "./message.tmp";
$tmp_passwd = "./passwd.tmp";
$tmp_shadow = "./shadow.tmp";
$tmp_group = "./group.tmp";
$tmp_gshadow = "./gshadow.tmp";
$cnt_config = '.counter_conf';
$cnt_data = '.counter_data';
$cnt_dir = "/digits";
$cnt_base = "/usr/libexec/wam/digits";
$lang_base = "/usr/libexec/wam/lang";
$gb_config = '.guestbook_conf';
$gb_data = '.message_data';
$gb_reply = '.reply_data';
$gb_subscribe = '.subscribe_data';
$mailtmp = ".wam";
@referers = ('localhost','stuwork.meps.tp.edu.tw','163.21.228.69','172.22.1.69','127.0.0.1');
@special =
('shutdown','halt','operator','gdm','ftpadm','mysql','sync','samba','ftp','sendmail','adm','bin','console','daemon','dip','disk','floppy','ftp','games','gopher','kmem','lp','mail','man','mem'
,'wam','dd','nogroup','cdwriters','wnn','xgrp','root','news','nobody','popusers','postgres','pppusers','slipusers','slocate','sys','tty','utmp','uucp','wheel','xfs','ctools','ntools');
##############################################################################

$zip_test = `whereis zip`;
$zip_exist = 0;
$zip_exist = 1 if ($zip_test =~ /^zip: .+/);
$itoa64 = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
$base64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
$HOST=`/bin/hostname`;
$HOST=~ s/\n//g;

sub to64 {
    my ($v, $n) = @_;
    my $ret = '';
    while (--$n >= 0) {
	$ret .= substr($itoa64, $v & 0x3f, 1);
	$v >>= 6;
    }
    $ret;
}

sub rnd64 {
    my($range) = @_;
    my $ret = '';
    my $n = 8, $i;
    $range = $CONFIG{'passwd_range'}  if ($range=='undef');
    while (--$n >= 0) {
	$i = rand;
	if ($range eq 'num') {
		$ret .= substr($itoa64, int($i*10)+2, 1);
	} elsif ($range eq 'lcase') {
		$ret .= substr($itoa64, int($i*26)+38, 1);
	} elsif ($range eq 'ucase') {
		$ret .= substr($itoa64, int($i*26)+12, 1);
	} elsif ($range eq 'allcase') {
		$ret .= substr($itoa64, int($i*52)+12, 1);
	} elsif ($range eq 'num-lcase') {
		my $j = int($i*36);
		if ($j > 9) {
			$ret .= substr($itoa64, $j+28, 1);
		} else {
			$ret .= substr($itoa64, $j+2, 1);
		}
	} elsif ($range eq 'num-ucase') {
		$ret .= substr($itoa64, int($i*36)+2, 1);
	} elsif ($range eq 'all') {
		$ret .= substr($itoa64, int($i*64), 1);
	}
    }
    $ret;
}

sub urldecode {
	my($str) = @_;
	$str =~ s/\%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
	$str;
}

sub urlencode {
	my($str) = @_;
	$str =~ s/([\W_ -])/'%'.unpack("H2",$1)/eg;
	$str;
}

sub b64decode {
	my($str) = @_;
	my($res);
	$str =~ tr|A-Za-z0-9+=/||cd;
	$str =~ s/=+$//;
	$str =~ tr|A-Za-z0-9+/| -_|;
	while ($str =~ /(.{1,60})/gs) {
		my $len = chr(32 + length($1)*3/4);
		$res .= unpack("u", $len . $1 );
	}
	$res;
}

sub b64encode {
	my($str) = @_;
	my($res, $tail, $pre, $byte, $n, $tail);
	while ($str =~ /(.{3})/gs) {
		$tail = $';
		$pre = unpack("B32",$1);
		while ($pre =~ /(.{6})/gs) {
		    $byte = substr($base64,ord(pack("B8",'00'.$1)),1);
		    $res .= $byte;
		}
	}
	$n = length($tail);
	$pre = unpack("B32",$tail);
	for($i=0;$i<=$n;$i++) {
	    $pre =~ /(.{6})/gs;
	    $byte = substr($base64,ord(pack("B8",'00'.$1)),1);
	    $res .= $byte;
	}
	$res."=" x int(3 - $n);
}

sub qpdecode {
	my($str) = @_;
	my(@temp, $res, $line);
	@temp = split(/\n/,$str);
	foreach $line (@temp) {
		$flag = (substr($line, length($line)-1,1) eq '=')?1:0;
		$line =~ s/=([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
		if ($flag eq 1) {
			$res .= substr($line,0,length($line)-1);
			chop $res;
		} else {
			$res .= $line."\n";
		}
	}
	$res;
}

sub qpencode {
	my($str) = @_;
	my(@temp, $res, $line, $st);
	@temp = split(/\n/,$str);
	foreach $line (@temp) {
		$line =~ s/([\W_ -])/'='.unpack("H2",$1)/eg;
		while (length($line)>74) {
			$st = index($line,'=',68);
			$st = 70 if ($st>=70);
			$res .= substr($line,0,$st)."=0A=\n";
			$line = substr($line,$st);
		}
		$res .= $line."\n";
	}
	$res;
}

sub apache_md5_crypt {
	my $Magic = '$apr1$';

	unix_md5_crypt(@_);
}

sub unix_md5_crypt {
    my($pw, $salt) = @_;
    my $passwd;
    my $Magic = '$1$';

    $salt =~ s/^\Q$Magic//;
    $salt =~ s/^(.*)\$.*$/$1/;
    $salt = substr($salt, 0, 8);

    $ctx = new MD5;
    $ctx->add($pw);
    $ctx->add($Magic);
    $ctx->add($salt);

    my ($final) = new MD5;
    $final->add($pw);
    $final->add($salt);
    $final->add($pw);
    $final = $final->digest;

    for ($pl = length($pw); $pl > 0; $pl -= 16) {
	$ctx->add(substr($final, 0, $pl > 16 ? 16 : $pl));
    }

    for ($i = length($pw); $i; $i >>= 1) {
	if ($i & 1) { $ctx->add(pack("C", 0)); }
	else { $ctx->add(substr($pw, 0, 1)); }
    }

    $final = $ctx->digest;

    for ($i = 0; $i < 1000; $i++) {
	$ctx1 = new MD5;
	if ($i & 1) { $ctx1->add($pw); }
	else { $ctx1->add(substr($final, 0, 16)); }
	if ($i % 3) { $ctx1->add($salt); }
	if ($i % 7) { $ctx1->add($pw); }
	if ($i & 1) { $ctx1->add(substr($final, 0, 16)); }
	else { $ctx1->add($pw); }
	$final = $ctx1->digest;
    }

    $passwd = '';
    $passwd .= to64(int(unpack("C", (substr($final, 0, 1))) << 16)
		    | int(unpack("C", (substr($final, 6, 1))) << 8)
		    | int(unpack("C", (substr($final, 12, 1)))), 4);
    $passwd .= to64(int(unpack("C", (substr($final, 1, 1))) << 16)
		    | int(unpack("C", (substr($final, 7, 1))) << 8)
		    | int(unpack("C", (substr($final, 13, 1)))), 4);
    $passwd .= to64(int(unpack("C", (substr($final, 2, 1))) << 16)
		    | int(unpack("C", (substr($final, 8, 1))) << 8)
		    | int(unpack("C", (substr($final, 14, 1)))), 4);
    $passwd .= to64(int(unpack("C", (substr($final, 3, 1))) << 16)
		    | int(unpack("C", (substr($final, 9, 1))) << 8)
		    | int(unpack("C", (substr($final, 15, 1)))), 4);
    $passwd .= to64(int(unpack("C", (substr($final, 4, 1))) << 16)
		    | int(unpack("C", (substr($final, 10, 1))) << 8)
		    | int(unpack("C", (substr($final, 5, 1)))), 4);
    $passwd .= to64(int(unpack("C", substr($final, 11, 1))), 2);

    $final = '';
    $Magic . $salt . '$' . $passwd;
}

sub check_referer {
	my $check_referer = 0;
	my (@addrs);

	$check_referer = 1 if ($ENV{'QUERY_STRING'} eq '' || $ENV{'CONTENT_LENGTH'} == 0);
	if ($ENV{'HTTP_REFERER'}) {
		foreach $referer (@referers) {
			if ($ENV{'HTTP_REFERER'} =~ m|https?://([^/]*)$referer|i) {
				$check_referer = 1;
				last;
			}
		}
		$check_referer = 1 if ($ENV{'HTTP_REFERER'} =~ m|https?://([^/]*)$HOST|i);
		@addrs = `ifconfig | grep 'inet addr:'`;
		foreach $addr (@addrs) {
			$addr =~ /inet addr:([\w.]*)/;
			if ($ENV{'HTTP_REFERER'} =~ m|https?://([^/]*)$1|i) {
				$check_referer = 1;
				last;
			}
		}
	} else {
		$check_referer = 1;
	}

	if ($check_referer ne 1) {
		&head("$SYSMSG{'title_system_info'}");
		print "<center>$SYSMSG{'msg_acl_warn'}</center>";
		exit 0;
	}
}

sub check_acl {
	my $check_acl = $CONFIG{'acltype'};
	my @acls = split(/;/,$CONFIG{'acls'});
	my $userip;

	if (defined $ENV{'HTTP_X_FORWARDED_FOR'} &&
	   $ENV{'HTTP_X_FORWARDED_FOR'} !~ /^10\./ &&
	   $ENV{'HTTP_X_FORWARDED_FOR'} !~ /^172\.[1-2][6-9]\./ &&
	   $ENV{'HTTP_X_FORWARDED_FOR'} !~ /^192\.168\./ &&
	   $ENV{'HTTP_X_FORWARDED_FOR'} !~ /^127\.0\./ ) {
	   $userip=(split(/,/,$ENV{HTTP_X_FORWARDED_FOR}))[0];
	} else {
	   $userip=$ENV{REMOTE_ADDR};
	}

	if ($userip) {
		foreach $acl (@acls) {
			if ($userip =~ /$acl/) {
				$check_acl = 1 - $CONFIG{'acltype'};
				last;
			}
		}
	} else {
		$check_acl = $CONFIG{'acltype'};
	}

	if ($check_acl eq 1) {
		&head("$SYSMSG{'title_system_info'}");
		print "<center>$SYSMSG{'msg_acl_warn'}</center>";
		exit 0;
	}
}

sub check_special {
	my($testname)= @_;
	my $ret = 0;
	foreach $epo (@special) {
		if ($testname eq $epo) {
			$ret = 1;
			last;
		}
	}
	$ret;
}

sub get_form_data {
	my(@parts, @pairs, $buffer, $pair, $name, $value, $bound, $getfilename, $fname, $filename, $tmp1, $tmp2, $temp, @cookies);
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

	if (!defined($DATA{'step'}) && $buffer ne '') {
		$buffer =~ /^(.+)\r\n/;
		$bound = $1;
		@parts = split(/$bound/,$buffer);
		for($i=1;$i<@parts;$i++) {
			next if ($parts[$i] =~ /^--.*/);
			$parts[$i] =~ s/<!--(.|\n)*-->//g;
			$value = $parts[$i];
			@temp = split(/Content-Type.+\r\n\r\n/,$parts[$i]);
			$content_type = $value;
			$content_type =~ /Content-Type\: (.*)\r\n\r\n/;
			$content_type = $1;
			$content_type = 'application/octet-stream' if ($content_type eq '');
			$value =~ s/Content-Disposition.+\r\n//g;
			$value =~ s/Content-Type.+\r\n\r\n//g;
			$value =~ s/^\r\n//g;
			$value =~ s/^\r//g;
			$value =~ s/^\n//g;
			$value =~ s/\r\n$//;
			my($tmp1,$tmp2) = split(/\; filename=/,$temp[0]);
			$tmp1 =~ /Content-Disposition\: form-data\; name=\"(.*)\"(.*)/;
			$name = $1;
			$name =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
			$name =~ s/~!/ ~!/g;
			$name =~ s/\+/ /g;
			$tmp2 =~ /\"(.*)\"(.*)/;
			$getfilename = $1;
			if($getfilename =~ /[\\\/\:]/) {
				$fname = $getfilename;		#first ignore stuff before last backslash for Windows machines
				@a=split(/\\/,$fname);
				$totalT = @a;
				--$totalT;
				$fname=$a[$totalT];

				@a=split(/\//,$fname);		#then ignore stuff before last forwardslash for Unix machines
				$totalT = @a;
				--$totalT;
				$fname=$a[$totalT];

				@a=split(/\:/,$fname);		#then ignore stuff before last ":" for Macs?
				$totalT = @a;
				--$totalT;
				$fname=$a[$totalT];

				@a=split(/\"/,$fname);		#now we've got the real filename
				$filename = $a[0];
			} else {
				$filename = $getfilename;
			}
			if ($name =~ /digits_(.{1})/ && $value ne '') {
				$digit = $1.".gif";
				$mydir = "$cnt_base/$DATA{'folder'}";
				system("mkdir -p $mydir");
				open(REAL,"> $mydir/$digit") || &err_disk("$SYSMSG{'err_cannot_save_upload_file'} $mydir/$digit<br>");
				binmode REAL;
				print REAL $value;
				close(REAL);
			} elsif ($name eq 'upload_file' && $value ne '') {
				if ($DATA{'step'} eq 'doupload') {
					open(REAL,"> $account") || &err_disk("$SYSMSG{'err_cannot_save_upload_file'} $account<br>");
					print REAL $value;
					close(REAL);
				} elsif ($DATA{'step'} eq 'doupgrade' && $DATA{'mode'} eq 'upload') {
					system("mkdir -p /usr/libexec/wam/patch");
					$myfile = "/usr/libexec/wam/patch/$filename";
					system("rm -rf $myfile") if (-e $myfile);
					open(REAL,"> $myfile") || &err_disk("$SYSMSG{'err_cannot_save_upload_file'} $myfile<br>");
					binmode REAL;
					print REAL $value;
					close(REAL);
					&patch($myfile);
				} elsif ($DATA{'step'} eq 'sharemgr') {
					if ($DATA{'folder'} eq '/') {
						$myfile = "$DATA{'folder'}$filename";
					} else {
						$myfile = "$DATA{'folder'}/$filename";
					}
					&check_password;
					open(REAL,"> $myfile") || &err_disk("$SYSMSG{'err_cannot_save_upload_file'} $myfile<br>");
					binmode REAL;
					print REAL $value;
					close(REAL);
					system("chown -Rf $menu_id:$menu_gid $myfile");
					system("chmod 0700 $myfile");
				} elsif ($DATA{'step'} eq 'filesmgr') {
					if ($DATA{'folder'} eq '/') {
						$myfile = "$DATA{'folder'}$filename";
					} else {
						$myfile = "$DATA{'folder'}/$filename";
					}
					&check_password;
					$)=$menu_gid;
					$>=$menu_id;
					open(REAL,"> $myfile") || &err_disk("$SYSMSG{'err_cannot_save_upload_file'} $myfile<br>");
					binmode REAL;
					print REAL $value;
					close(REAL);
					$)=0;
					$>=0;
					if ($filename =~ /(.+).zip/ && $zip_exist && $DATA{'unzip'}) {
						system("unzip -uoqq $myfile -d $DATA{'folder'} > /dev/null");
						@zip_list = split(/\n/,`unzip -l $myfile`);
						foreach $item (@zip_list) {
							if ($item =~ /\d+ .+ \d\d:\d\d (.+)/) {
								if ($DATA{'folder'} eq '/') {
									system("chown -Rf $menu_id:$menu_gid /$1");
								} else {
									system("chown -Rf $menu_id:$menu_gid $DATA{'folder'}/$1");
								}
							}
						}
						unlink($myfile);
#					} elsif ($filename =~ /(.+).tar.gz/ && $DATA{'unzip'}) {
#						system("cd $DATA{'folder'}");
#						system("tar -xzvf $myfile > /dev/null");
#						unlink($myfile);
					}
				}
			} elsif ($DATA{$name} ne '') {
				$DATA{$name} .= ",$value";
			} else {
				$DATA{$name} = $value;
			}
		}
	}
}

sub empty_cookie {
	print "Set-Cookie: uid=\n";
	print "Set-Cookie: pid=\n";
}

sub check_password {
	my($name, $value, $usr, $pwd);
	 if ($DATA{'user'} ne '' && $DATA{'password'} ne '') {
		$usr = $DATA{'user'};
		$menu_id = getpwnam($usr);
		$menu_gid = (getpwnam($usr))[3];
		if (crypt($DATA{'password'},$PASS{$usr}) eq $PASS{$usr}) {
			print "Set-Cookie: uid=$menu_id\n";
			print "Set-Cookie: pid=".urlencode($PASS{$usr})."\n";
			$DATA{'flag'} = 'passed';
			$DATA{'step'}='menu' if ($DATA{'step'} eq '' || $DATA{'step'} eq 'relogon');
		} else {
			&err_account;
		}
	} else {
		@cookies = split(/; /,$ENV{'HTTP_COOKIE'});
		foreach $cookie (@cookies) {
			($name, $value) = split(/=/,$cookie);
			$menu_id = $value if ($name eq "uid");
			$pwd = urldecode($value) if ($name eq "pid");
		}
		$usr = getpwuid($menu_id);
		$menu_gid = (getpwuid($menu_id))[3];
		$DATA{'flag'}='deny' if ($pwd ne $PASS{$usr});
	}
}

sub err_disk {
	my($msg) = @_;
	&head("$SYSMSG{'title_system_info'}");
	print "<center><table border=0 style=font-size:11pt><tr><td><p><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'err_disk_failue'}</font></p>\n";
	print $msg;
	print '<ul>';
	print "<li>$SYSMSG{'msg_if_disk_busy'}<a href=\"javascript:history.go(-1)\"><img align=absmiddle src=/img/upfolder.gif border=0>  $SYSMSG{'backto_prev_page'}</a>$SYSMSG{'msg_try_later'}";
	print "<li>$SYSMSG{'msg_if_config_incorrect'}<a href=$cgi_url?step=config>$SYSMSG{'msg_setup_config'}</a>";
	print "<li>$SYSMSG{'msg_check_disk'}";
	print '</ul>';
	print '<hr color="#FF0000">';
	print "<center><a href=\"javascript:history.go(-1)\"><img align=absmiddle src=/img/upfolder.gif border=0>  $SYSMSG{'backto_prev_page'}</a></center>";
	print '</table></center></body>';
	print "</html>";
	exit 0;
}

sub err_account {
	&head("$SYSMSG{'title_system_info'}");
	print "<center><table border=0 style=font-size:11pt><tr><td><p><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'err_check_account'}</font></p>\n";
	print "$SYSMSG{'msg_please_check'}";
	print '<ul>';
	print "<li>$SYSMSG{'msg_if_misstype'}<a href=\"javascript:history.go(-1)\"><img align=absmiddle src=/img/upfolder.gif border=0>  $SYSMSG{'backto_prev_page'}</a>$SYSMSG{'msg_reinput'}";
	print "<li>$SYSMSG{'msg_just_for_user'}";
	print '</ul>';
	print '<hr color="#FF0000">';
	print "<center><a href=\"javascript:history.go(-1)\"><img align=absmiddle src=/img/upfolder.gif border=0>  $SYSMSG{'backto_prev_page'}</a></center>";
	print '</table></center></body>';
	print "</html>";
	exit 0;
}

sub get_lang_list {
	opendir (DIR, "$lang_base") || &err_disk("磁碟錯誤，語言套件目錄無法讀取。disk error! can't open language defined<br>");
	@LANGS=readdir(DIR);
	close(DIR);
}

sub get_lang {
	my($line, @lines);
	$CONFIG{'lang'}='Big-5'  if ($CONFIG{'lang'} eq '');
	open (LANG, "$lang_base/$CONFIG{'lang'}") || &err_disk("磁碟錯誤，語言套件目錄無法讀取。disk error! can't open language defined<br>");
	while ($line = <LANG>) {
		my($name, $value) = split(/:::/, $line);
		$value =~ s/\n//g;
		$SYSMSG{$name} = $value;
	}
	close(LANG);
}

sub read_conf {
	return if (!(-e $config));
	open (CFG, "< $config") || &err_disk("$SYSMSG{'err_cannot_open_config'}<br>");
	while ($line = <CFG>) {
		my($name, $value) = split(/:/, $line);
		$value =~ s/\n//g;
		$CONFIG{$name} = $value;
	}
	close(CFG);
}

sub read_gconf {
	return if (!(-e $gconfig));
	open (GCFG, "< $gconfig") || &err_disk("$SYSMSG{'err_cannot_open_gconfig'}<br>");
	while ($line = <GCFG>) {
		my($name, $value) = split(/:/, $line);
		$value =~ s/\n//g;
		$GCONF{$name} = $value;
	}
	close(GCFG);
}

sub write_gconf {
	my($grp, $home);
	open(GCFG, "> $gconfig") || &err_disk("$SYSMSG{'err_cannot_open_gconfig'}<br>");
	foreach $grp (keys %GCONF) {
		$home = $GCONF{$grp};
		$grp =~ s/[^!-~]//g;
		print GCFG "$grp:$home\n" if ($grp ne '' && $home ne '');
	}
	close(GCFG);
}

sub read_share {
	return if (!(-e $share_conf));
	open (SCFG, "< $share_conf") || &err_disk("$SYSMSG{'err_cannot_open_share'}<br>");
	while ($line = <SCFG>) {
		my($name, $desc, $value1, $value2, $value3, $value4, $value5, $grp) = split(/:/, $line);
		$grp =~ s/\n//g;
		$SHARE{$name} = $grp;
		$SDESC{$name} = $desc;
		$SPERM_DN{$name} = $value1;
		$SPERM_UP{$name} = $value2;
		$SPERM_DIR{$name} = $value3;
		$SPERM_EDIT{$name} = $value4;
		$SPERM_DEL{$name} = $value5;
	}
	close(SCFG);
}

sub write_share {
	open (SCFG, "> $share_conf") || &err_disk("$SYSMSG{'err_cannot_open_share'}<br>");
	foreach $name (keys %SHARE) {
		$str = join ':', $name, $SDESC{$name}, $SPERM_DN{$name}, $SPERM_UP{$name}, $SPERM_DIR{$name}, $SPERM_EDIT{$name}, $SPERM_DEL{$name}, $SHARE{$name}."\n";
		print SCFG $str;
	}
	close(SCFG);
}

sub read_shells {
	open (SHD, "< $CONFIG{'shells'}") || &err_disk("$SYSMSG{'err_cannot_open_shell'}<br>");
	@SHLS=<SHD>;
	close(SHD);
}

sub read_group {
	open (GRP, "< $CONFIG{'group'}") || &err_disk("$SYSMSG{'err_cannot_open_group'}<br>");

	while ($line = <GRP>) {
		my($gname, $ignore, $gid, $users) = split(/:/, $line);

		if ($gid ne '') {
			$GIDS{$gid} ++;
			$GNAME{$gname} ++;
			$GNMID{$gname} = $gid;
			$GIDNM{$gid} = $gname;
			$GIG{$gname} = $ignore;
			$GUSRS{$gname} = $users;
		}
	}
	close(GRP);
}

sub write_group {
	my($gid, $grp, $gig, $gu, $gstr);
	open(TMPG, "> $tmp_group") || &err_disk("$SYSMSG{'err_cannot_open_temp'}<br>");
	foreach $grp (keys %GNAME) {
		$gid = $GNMID{$grp};
		$gig = $GIG{$grp};
		$gu = $GUSRS{$grp};
		$grp =~ s/[^!-~]//g;
		$gstr = join ':', $grp, $gig, $gid, $gu;
		print TMPG "$gstr";
	}
	close(TMPG);
	open(TMPG, "< $tmp_group") || &err_disk("$SYSMSG{'err_cannot_open_temp'}<br>");
	open (GRP, "> $CONFIG{'group'}") || &err_disk("$SYSMSG{'err_cannot_open_group'}<br>");
	flock GRP, $LOCK_EX;
	print GRP <TMPG>;
	flock GRP, $LOCK_UN;
	close(GRP);
	close(TMPG);
	unlink($tmp_group);
}

sub read_passwd {
	open (PWD, "< $CONFIG{'passwd'}") || &err_disk("$SYSMSG{'err_cannot_open_passwd'}<br>");

	while ($line = <PWD>) {
		my($uname, $ignore, $uid, $gid, $gecos, $home, $shell) = split(/:/, $line);

		if ($uid ne '') {
			$UIDS{$uid} ++;
			$UNAME{$uname} ++;
			$UNMID{$uname} = $uid;
			$UIDNM{$uid} = $uname;
			$UGID{$uid} = $gid;
			$GECOS{$uid} = $gecos;
			$HOME{$uid} = $home;
			$SHELL{$uid} = $shell;
		}
	}
	close(PWD);
}

sub write_passwd {
	my($uid, $n, $gn, $g, $gec, $h, $pstr, $sh);
	open(TMPP, "> $tmp_passwd") || &err_disk("$SYSMSG{'err_cannot_open_temp'}<br>");
	foreach $uid (sort keys %UIDS) {
		$n = $UIDNM{$uid};
		$n =~ s/[^!-~]//g;
		$g = $UGID{$uid};
		$gec = $GECOS{$uid};
		$h = $HOME{$uid};
		$sh = $SHELL{$uid};
		$pstr = join ':', $n, "x", $uid, $g, $gec, $h, $sh;
		print TMPP "$pstr";
	}
	close(TMPP);
	open(TMPP, "< $tmp_passwd") || &err_disk("$SYSMSG{'err_cannot_open_temp'}<br>");
	open (PWD, "> $CONFIG{'passwd'}") || &err_disk("$SYSMSG{'err_cannot_open_passwd'}<br>");
	flock PWD, $LOCK_EX;
	print PWD <TMPP>;
	flock PWD, $LOCK_UN;
	close(PWD);
	close(TMPP);
	unlink($tmp_passwd);
}

sub read_shadow {
	open (SHD, "< $CONFIG{'shadow'}") || &err_disk("$SYSMSG{'err_cannot_open_shadow'}<br>");

	while ($line = <SHD>) {
		my($uname, $pwd, $sday, $smin, $smax, $swarn, $sinact, $sexp, $sflag) = split(/:/, $line);

		if ($uname ne '') {
			$PASS{$uname} = $pwd;
			$SDAY{$uname} = $sday;
			$SMIN{$uname} = $smin;
			$SMAX{$uname} = $smax;
			$SWARN{$uname} = $swarn;
			$SINACT{$uname} = $sinact;
			$SEXP{$uname} = $sexp;
			$SFLAG{$uname} = $sflag;
		}
	}
	close(SHD);
}

sub write_shadow {
	my($uid, $usr, $mi, $ma, $w, $d, $p, $i, $e, $w, $f, $sstr);
	open(TMPS, "> $tmp_shadow") || &err_disk("$SYSMSG{'err_cannot_open_temp'}<br>");
	foreach $uid (sort keys %UIDS) {
		$usr = $UIDNM{$uid};
		$p = $PASS{$usr};
		$p = crypt($usr,'$6$'.&rnd64('all')) if ($p eq "");
		$d = $SDAY{$usr};
		$d = $today if ($d eq "");
		$mi = $SMIN{$usr};
		$mi = $CONFIG{'min'} if ($mi eq "");
		$ma = $SMAX{$usr};
		$ma = $CONFIG{'max'} if ($ma eq "");
		$w = $SWARN{$usr};
		$w = $CONFIG{'pwarn'} if ($w eq "");
		$i = $SINACT{$usr};
		$i = $CONFIG{'inact'} if ($i eq "");
		$e = $SEXP{$usr};
		if ($e eq "") {
			$e = $today + $CONFIG{'expire'};
			$e = -1 if ($CONFIG{'expire'} < 30);
		}
		$f = $SFLAG{$usr};
		$f = $CONFIG{'flag'}."\n" if ($f eq "");
		$sstr = join ':', $usr, $p, $d, $mi, $ma, $w, $i, $e, $f;
		print TMPS "$sstr";
	}
	close(TMPS);
	open(TMPS, "< $tmp_shadow") || &err_disk("$SYSMSG{'err_cannot_open_temp'}<br>");
	open (SHD, "> $CONFIG{'shadow'}") || &err_disk("$SYSMSG{'err_cannot_open_shadow'}<br>");
	flock SHD, $LOCK_EX;
	print SHD <TMPS>;
	flock SHD, $LOCK_UN;
	close(SHD);
	close(TMPS);
	unlink($tmp_shadow);
}

sub check_group {
	my($grp, $f1) = @_;
	my($warning, $f2);
	$f2 = defined($GNAME{$grp});
	if ($f1 eq '1' && $f2) {
		print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5> $grp $SYSMSG{'err_group_exist'}</font></center><br>";
		$warning ++;
	}
	if ($f1 eq '0' && !$f2) {
		print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5> $grp $SYSMSG{'err_group_not_exist'}</font></center><br>";
		$warning ++;
	}
	if ($warning != 0) {
		if ($f1 eq '1') {
			print "<hr><center><table border=0 style=font-size:11pt><tr><td><p><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'err_group_exist'}</font></p>\n";
			print "$SYSMSG{'err_cannot_continue_becouse'} <b>$warning</b> $SYSMSG{'err_group_exist'}<br>";
			print '<ul>';
			print "<li>$SYSMSG{'msg_delete_group_first'}";
			print "<li>$SYSMSG{'msg_check_upload_group'}";
			print '</ul>';
		} else {
			print "<hr><center><table border=0 style=font-size:11pt><tr><td><p><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'err_group_not_exist'}</font></p>\n";
			print "$SYSMSG{'err_cannot_continue_becouse'} <b>$warning</b> $SYSMSG{'err_group_not_exist'}<br>";
			print '<ul>';
			print "<li>$SYSMSG{'msg_add_group_first'}";
			print "<li>$SYSMSG{'msg_check_upload_group'}";
			print '</ul>';
		}
		print '<hr color="#FF0000">';
		print '<center><a href="javascript:history.go(-1)"><img align=absmiddle src=/img/upfolder.gif border=0>  回上一頁</a></center>';
		print '</table></center></body>';
		print "</html>";
		exit 1;
	}
}

sub check_user {
	my($usr, $f1) = @_;
	my($warning, $f2);
	$f2 = defined($UNAME{$usr});
	if ($f1 eq '1' && $f2) {
		print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5> $usr $SYSMSG{'err_username_exist'}</font></center><br>";
		$warning ++;
	}
	if ($f1 eq '0' && !$f2) {
		print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5> $usr $SYSMSG{'err_username_not_exist'}</font></center><br>";
		$warning ++;
	}
	if ($warning != 0) {
		if ($f1 eq '1') {
			print "<hr><center><table border=0 style=font-size:11pt><tr><td><p><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'err_username_exist'}</font></p>\n";
			print "$SYSMSG{'err_cannot_continue_becouse'}<b>$warning</b>$SYSMSG{'err_username_exist'}<br>";
			print '<ul>';
			print "<li>$SYSMSG{'msg_delete_user_first'}";
			print "<li>$SYSMSG{'msg_check_upload_username'}";
			print '</ul>';
		} else {
			print "<hr><center><table border=0 style=font-size:11pt><tr><td><p><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'err_username_not_exist'}</font></p>\n";
			print "$SYSMSG{'err_cannot_continue_becouse'}<b>$warning</b>$SYSMSG{'err_username_not_exist'}<br>";
			print '<ul>';
			print "<li>$SYSMSG{'msg_add_user_first'}";
			print "<li>$SYSMSG{'msg_check_upload_username'}";
			print '</ul>';
		}
		print '<hr color="#FF0000">';
		print '<center><a href="javascript:history.go(-1)"><img align=absmiddle src=/img/upfolder.gif border=0>  回上一頁</a></center>';
		print '</table></center></body>';
		print "</html>";
		exit(1) if ($f1 ne '1');
	}
}

sub get_uid {
	my $i;
	for ($i=500;$i<65535;$i++) {
	    last if (!defined($UIDS{$i}));
	}
	$i;
}

sub get_gid {
	my $i;
	for ($i=500;$i<65535;$i++) {
	    last if (!defined($GIDS{$i}));
	}
	$i;
}

sub addone {
	my($usr, $grp, $pwd, $sub_grp) = @_;
	my($lvl, @lvls, $home, $gn);
	$gn = $grp;
	$home = $CONFIG{'base_dir'};
	$home = "$CONFIG{'base_dir'}/$grp" if ($CONFIG{'home_nest'} eq 'yes');
	&add_grp($grp,$home) if (!defined($GNAME{$grp}));
	if ($sub_grp ne '') {
		@lvls = split(/\//,$sub_grp);
		foreach $lvl (@lvls) {
			$home .= "/$lvl";
			&add_grp($lvl,$home) if (!defined($GNAME{$lvl}));
			$gn = $lvl;
		}
	}
	&check_user($usr,'1');
	$uid = &get_uid;
	$g = $GNMID{$gn};
	$h = $GCONF{$gn};
	$h = $CONFIG{'base_dir'} if ($CONFIG{'home_nest'} ne 'yes' || $h eq '');
	$UIDS{$uid} ++;
	$UNAME{$usr} ++;
	$UNMID{$usr} = $uid;
	$UIDNM{$uid} = $usr;
	$UGID{$uid} = $g;
	$GECOS{$uid} = '';
	$HOME{$uid} = "$h/$usr";
	$SHELL{$uid} = $CONFIG{'shell'}."\n";
	$PASS{$usr} = crypt($pwd,'$6$'.&rnd64('all'));
	$SDAY{$usr} = $today;
	$SMIN{$usr} = $CONFIG{'min'};
	$SMAX{$usr} = $CONFIG{'max'};
	$SWARN{$usr} = $CONFIG{'pwarn'};
	$SINACT{$usr} = $CONFIG{'inact'};
	$exp = $today + $CONFIG{'expire'};
	$exp = -1 if ($CONFIG{'expire'} < 30);
	$SEXP{$usr} = $exp;
	$SFLAG{$usr} = $CONFIG{'flag'}."\n";
	$sreqn{$uid} = $usr;
	$sreqg{$uid} = $gn;
	$sreqp{$uid} = $pwd;
	$sreqt{$uid} = join ':', $usr, "x", $uid, $g, "", $HOME{$uid}, $SHELL{$uid};
	$sreqs{$uid} = join ':', $usr, $PASS{$usr}, $SDAY{$usr}, $SMIN{$usr}, $SMAX{$usr}, $SWARN{$usr},
				 $SINACT{$usr}, $SEXP{$usr}, $SFLAG{$usr};
}

sub read_request {
	open (REQ, "< $account") || &err_disk("$account $sysmsg{'err_cannot_open'}.<br>");
	while ($line = <REQ>) {
		local($uname, $gname, $pwd) = split(/ /, $line);
		$pwd =~ s/[\n|\r]//g;
		&addone($uname, $gname, $pwd, '') if ($uname ne '' && $gname ne '' && $pwd ne '');
	}
	close(REQ);
}

sub autoadd {
	my($grp, $pre, $st, $ed, $z, $gst, $ged, $cst, $ced) = @_;
	my($u1, $u2, $u3, $i, $j, $k, $l1, $l2, $l3, $g, $p, $n, $d);
	$l1 = length($ed);
	$l2 = length($ged);
	$l3 = length($ced);
	if ($CONFIG{'nest'} eq 1) {
		for ($i=int($st); $i<=int($ed); $i++) {
			$u1 = '';
			for (1..$l1-length($i)){$u1 .= '0';}
			$n = $pre.(($z eq 'yes')?$u1:'').$i;
			$p = (($CONFIG{'passwd_form'} eq 'username')?$n:(($CONFIG{'passwd_form'} eq 'random')?&rnd64:"passwd"));
			&addone($n, $grp, $p, '');
		}
	} elsif ($CONFIG{'nest'} eq 2) {
		for ($j=int($gst); $j<=int($ged); $j++) {
			for ($i=int($st); $i<=int($ed); $i++) {
				$u1 = '';
				for (1..$l1-length($i)){$u1 .= '0';}
				$u2 = '';
				for (1..$l2-length($j)){$u2 .= '0';}
				$n = $pre.(($z eq 'yes')?$u2:'').$j.(($z eq 'yes')?$u1:'').$i;
				$p = (($CONFIG{'passwd_form'} eq 'username')?$n:(($CONFIG{'passwd_form'} eq 'random')?&rnd64:"passwd"));
				$g = $pre.(($z eq 'yes')?$u2:'').$j;
				&addone($n, $pre, $p, $g);
			}
		}
	} elsif ($CONFIG{'nest'} eq 3) {
		for ($j=int($gst); $j<=int($ged); $j++) {
			for ($k=int($cst); $k<=int($ced); $k++) {
				for ($i=int($st); $i<=int($ed); $i++) {
					$u1 = '';
					for (1..$l1-length($i)){$u1 .= '0';}
					$u2 = '';
					for (1..$l2-length($j)){$u2 .= '0';}
					$u3 = '';
					for (1..$l3-length($k)){$u3 .= '0';}
					$n = $pre.(($z eq 'yes')?$u2:'').$j.(($z eq 'yes')?$u3:'').$k.(($z eq 'yes')?$u1:'').$i;
					$p = (($CONFIG{'passwd_form'} eq 'username')?$n:(($CONFIG{'passwd_form'} eq 'random')?&rnd64:"passwd"));
					$d = $pre.(($z eq 'yes')?$u2:'').$j;
					$g = $pre.(($z eq 'yes')?$u2:'').$j.(($z eq 'yes')?$u3:'').$k;
					&addone($n, $pre, $p, "$d/$g");
				}
			}
		}
	}
}

sub add_wam {
	my($usr) = @_;
	&check_group('wam','0');
	&check_user($usr,'0');
	if ($GUSRS{'wam'} eq "\n") {
		$GUSRS{'wam'} =~ s/\n//g;
		$GUSRS{'wam'} .= "$usr\n";
	} else {
		$GUSRS{'wam'} =~ s/\n//g;
		$GUSRS{'wam'} .= ",$usr\n";
	}
}

sub del_wam {
	my($usr) = @_;
	&check_group('wam','0');
	if ($GUSRS{'wam'} ne "\n" && $usr ne "") {
		$GUSRS{'wam'} =~ s/,$usr//g;
		$GUSRS{'wam'} =~ s/$usr,//g;
	}
}

sub add_grp {
	my($grp,$home) = @_;
	my($gid);
	$home = '/home' if ($home eq '');
	&check_group($grp,'1');
	$gid = &get_gid;
	$GIDS{$gid} ++;
	$GNAME{$grp} ++;
	$GNMID{$grp} = $gid;
	$GIDNM{$gid} = $grp;
	$GIG{$grp} = "";
	$GUSRS{$grp} = "\n";
	$GCONF{$grp} = $home;
}

sub del_grp {
	my($grp) = @_;
	my($gid);
	&check_group($grp,'0');
	$gid = $GNMID{$grp};
	if (int($gid)>0) {
		delete $GIDS{$gid};
		delete $GNAME{$grp};
		delete $GCONF{$grp};
		delete $GNMID{$grp};
		delete $GIDNM{$gid};
		delete $GIG{$grp};
		delete $GUSRS{$grp};
	}
	splice @GIDS;
	splice @GNAME;
}

sub delone {
	my($uid, $usr) = @_;
	my($line, @lines);
	print "<center>$SYSMSG{'del_user_now'} $usr ，uid: $uid ....</center><br>";
	delete $UIDS{$uid};
	delete $UNAME{$usr};
	delete $UNMID{$usr};
	delete $UIDNM{$uid};
	delete $UGID{$uid};
	delete $GECOS{$uid};
	system("rm -rf $HOME{$uid}") if (-e "$HOME{$uid}" && -d _);
	system("rm -rf $mailspooldir/$usr") if (-e "$mailspooldir/$usr" && -d _);
	delete $HOME{$uid};
	delete $SHELL{$uid};
	delete $PASS{$usr};
	delete $SDAY{$usr};
	delete $SMIN{$usr};
	delete $SMAX{$usr};
	delete $SWARN{$usr};
	delete $SINACT{$usr};
	delete $SEXP{$usr};
	delete $SFLAG{$usr};
	open(SMB,"|$CONFIG{'smbprog'} -x $usr")  || &err_disk("$SYSMSG{'err_cannot_open'} $CONFIG{'smbprog'} $SYSMSG{'program'}<br>");
	close(SMB);
	splice @UIDS;
	splice @UNAME;
	splice @PASS;
}

sub delete_pw {
	my($u, $g, $w) = @_;
	my($uid, $n, $mygrp, $usr, $d);
	if ($u eq '999') {
		$g = '';
		$w = '';
		foreach $uid (keys %UIDS) {
			$usr = $UIDNM{$uid};
			&delone($uid,$usr) if (int($uid)>1000);
		}
	} elsif ($u ne '') {
		$g = '';
		$w = '';
		$uid = $UNMID{$u};
		&delone($uid,$u);
	}
	if ($g ne '') {
		$w = '';
		$mygrp = $GNMID{$g};
		return if (int($mygrp)<500);
		foreach $uid (keys %UIDS) {
			$usr = $UIDNM{$uid};
			&delone($uid,$usr) if ($UGID{$uid} eq $mygrp);
		}
		if ($CONFIG{'home_nest'} eq 'yes') {
			$d = $GCONF{$g};
			system("rmdir $d") if ($d ne '' && -e "$d" && -d _);
		}
		&del_grp($g);
	}
	if ($w ne '') {
		foreach $usr (sort keys %UNAME) {
			$uid = $UNMID{$usr};
			&delone($uid,$usr) if ($usr =~ /$w/);
		}
		foreach $mygrp (sort keys %GNAME) {
			if ($mygrp =~ /$w/) {
				if ($CONFIG{'home_nest'} eq 'yes') {
					$d = $GCONF{$mygrp};
					system("rmdir $d") if ($d ne '' && -e "$d" && -d _);
				}
				&del_grp($mygrp);
			}
		}
	}
	&write_gconf;
	&write_group;
}

sub reset_pw {
	my($u, $g, $w, $pf) = @_;
	my($uid, $usr, $p);
	if ($u eq '999') {
		$g = '';
		$w = '';
		foreach $uid (keys %UIDS) { push (@CHGPW, $UIDNM{$uid}) if (int($uid)>1000); }
	} elsif ($u ne '') {
		$g = '';
		$w = '';
		&check_user($u,'0');
		push (@CHGPW, $u);
	}
	if ($g ne '') {
		$w = '';
		return if (int($GNMID{$g})<500);


		&check_group($g,'0');
		foreach $uid (keys %UIDS) { push (@CHGPW, $UIDNM{$uid}) if ($UGID{$uid} eq $GNMID{$g}); }
	}
	if ($w ne '') {
		foreach $usr (keys %UNAME) { push (@CHGPW, $usr) if ($usr =~ /$w/); }
	}
	foreach $usr (@CHGPW) {
		if ($pf eq 'username') {
			$PASS{$usr} = crypt($usr,$PASS{$usr});
			&smb_passwd($usr,$usr) if ($CONFIG{'sync_smb'} eq 'yes');
		} elsif ($pf eq 'random') {
			$p = &rnd64;
			$UPASS{$usr} = $p;
			$PASS{$usr} = crypt($p,$PASS{$usr});
			&smb_passwd($usr,$p) if ($CONFIG{'sync_smb'} eq 'yes');
		} elsif ($pf eq 'single') {
			$PASS{$usr} = crypt('passwd',$PASS{$usr});
			&smb_passwd($usr,'passwd') if ($CONFIG{'sync_smb'} eq 'yes');
		}
	}
}

sub chg_passwd {
	my($p1, $p2) = @_;
	my $usr = getpwuid($menu_id);
	if ($p1 eq $p2) {
		$PASS{$usr} = crypt($p1,$PASS{$usr});
		print "Set-Cookie: uid=$menu_id\n";
		print "Set-Cookie: pid=".urlencode($PASS{$usr})."\n";
		&head($SYSMSG{'title_chgpw'});
		&smb_passwd($usr,$p1) if ($CONFIG{'sync_smb'} eq 'yes');
	} else {
		&head($SYSMSG{'title_chgpw'});
		print "<hr><center><table border=0 style=font-size:11pt><tr><td><p>$SYSMSG{'err_bad_passwd'}</p>\n";
		print "$SYSMSG{'err_cannot_continue_change_passwd'}.<br>";
		print '<ul>';
		print "<li>$SYSMSG{'msg_passwd_must_same'}";
		print '</ul>';
		print '<hr color="#FF0000">';
		print "<center><a href=\"javascript:history.go(-1)\"><img align=absmiddle src=/img/upfolder.gif border=0>  $SYSMSG{'backto_prev_page'}</a></center>";
		print '</table></center></body>';
		print "</html>";
		exit 1;
	}
}

sub smb_passwd {
	my($usr, $pwd) = @_;
	open(SMB,"|$CONFIG{'smbprog'} -a $usr")  || &err_disk("$SYSMSG{'err_cannot_open'} $CONFIG{'smbprog'} $SYSMSG{'program'}<br>");
	print SMB "$pwd\n";
	print SMB "$pwd\n";
	system("$CONFIG{'smbprog'} -e $usr");
	close(SMB);
}

sub sync_alluser {
	my($usr, $uid);
	foreach $uid (keys %UIDS) {
		next if ($uid ne 0 && int($uid)<500);
		$usr = $UIDNM{$uid};
		system("$CONFIG{'smbprog'} -a $usr -n");
	}
}

sub make_index {
	open(IDX, "> $tmp_index") || &err_disk("$SYSMSG{'err_cannot_open_homepage_sample'}.<br>");
	print IDX "<!--$SYSMSG{'msg_keyword'}: USER->$SYSMSG{'msg_replace_username'}-->\n";
	print IDX "<!--$SYSMSG{'msg_keyword'}: HOSTNAME->$SYSMSG{'msg_replace_hostname'}-->\n";
	print IDX "<!--$SYSMSG{'msg_keyword'}: PORT->$SYSMSG{'msg_replace_port'}-->\n";
	print IDX "<html><head><meta http-equiv=Content-Type content=\"$SYSMSG{'charset'}\">\n";
	print IDX "<title>USER$SYSMSG{'msg_homepage'}</title></head>\n";
	print IDX "<body style=\"font-size:11pt\" bgcolor=\"#ffffff\" >\n";
	print IDX "<h1 align=\"center\"><b><font color=\"#0000FF\" size=\"6\">\n";
	print IDX "<marquee behavior=\"alternate\" width=\"439\" height=\"32\">$SYSMSG{'welcome_to'}USER$SYSMSG{'msg_homepage'} </marquee>\n";
	print IDX "</font></b></h1><hr size=\"1\" color=\"#6699cc\">\n";
	print IDX "<center>\n";
	print IDX "<font color=\"#FF0000\">\n";
	print IDX "$SYSMSG{'msg_you_are'} <a href=http://HOSTNAME:PORT/wam.cgi?step=set_count><img align=absmiddle src=\"http://HOSTNAME:PORT/count\" border=\"0\"></a>$SYSMSG{'msg_visited'}</font>\n";
	print IDX "<p><b><a href=\"http://HOSTNAME:PORT/gbook?user=USER\">$SYSMSG{'msg_my_gbook'}</a> | ";
	print IDX "<a href=\"http://HOSTNAME:PORT/album?user=USER\">$SYSMSG{'msg_my_album'}</a><br>\n";
	print IDX "</b><hr size=\"1\" color=\"#FF0000\"><span style=\"background-color: #007BB7\"><font size=\"5\" color=\"#FFFFFF\"><b>\n";
	print IDX "$SYSMSG{'msg_hi'}&nbsp;</b></font></span>\n";
	print IDX "<p><img src=http://HOSTNAME:PORT/img/dingdong0.gif>\n";
	print IDX "<a href=\"http://HOSTNAME:PORT/mail.cgi?user=USER\">$SYSMSG{'msg_my_email'}:USER\@HOSTNAME</a></p>\n";
	print IDX "<p><a href=\"http://HOSTNAME:PORT/\">$SYSMSG{'msg_admin'}</a></p><hr color=\"#FF0000\"><p></center></p></body></html>\n";
	close(IDX);
}

sub make_passwd {
	my($uid, $n, $gn, $g, $d, $p, $pstr, $sstr, $l, $h, @lvls, $lvl, $line, $exp);
	open(TMPP, "> $tmp_passwd") || &err_disk("$SYSMSG{'err_cannot_open_temp'}.<br>");
	open(TMPS, "> $tmp_shadow") || &err_disk("$SYSMSG{'err_cannot_open_temp'}.<br>");

	&write_group;
	&write_gconf;
	print "<center>$SYSMSG{'autoadd_add_these'}<br>";
	foreach $uid (sort keys %sreqn) {
		print $UIDNM{$uid}."<br>";
		print TMPP "$sreqt{$uid}";
		print TMPS "$sreqs{$uid}";
	}
	close(TMPP);
	close(TMPS);

	open(TMPP, "< $tmp_passwd") || &err_disk("$SYSMSG{'err_cannot_open_temp'}.<br>");
	open (PWD, ">> $CONFIG{'passwd'}") || &err_disk("$SYSMSG{'err_cannot_open_passwd'}.<br>");

	flock PWD, $LOCK_EX;
	print PWD <TMPP>;
	flock PWD, $LOCK_UN;
	close(PWD);
	close(TMPP);

	open(TMPS, "< $tmp_shadow") || &err_disk("$SYSMSG{'err_cannot_open_temp'}.<br>");
	open (SHD, ">> $CONFIG{'shadow'}") || &err_disk("$SYSMSG{'err_cannot_open_shadow'}.<br>");
	flock SHD, $LOCK_EX;
	print SHD <TMPS>;
	flock SHD, $LOCK_UN;
	close(SHD);
	close(TMPS);
	unlink($tmp_passwd);
	unlink($tmp_shadow);

	foreach $uid (sort keys %sreqn) {
		system("mkdir -p $HOME{$uid}");
		if ($CONFIG{'add_homepage'} eq 'yes') {
			system("mkdir -p $HOME{$uid}/$CONFIG{'home_dir'}/album");
			if (-e $tmp_index) {
				open(IDX, "< $tmp_index");
				my @buffer = <IDX>;
				close(IDX);
				foreach $line (@buffer) {
					$line =~ s/USER/$UIDNM{$uid}/g;
					$line =~ s/HOSTNAME/$HOST/g;
					$line =~ s/PORT/$ENV{'SERVER_PORT'}/g;
				}
				open(IDX, "> $HOME{$uid}/$CONFIG{'home_dir'}/index.html");
				print IDX @buffer;
				close(IDX);
			}
			if (-e $tmp_album) {
				open(IDX, "< $tmp_album");
				my @buffer = <IDX>;
				close(IDX);
				foreach $line (@buffer) {
					$line =~ s/USER/$UIDNM{$uid}/g;
				}
				open(IDX, "> $HOME{$uid}/$CONFIG{'home_dir'}/album/message.htm");
				print IDX @buffer;
				close(IDX);
			}
		}
		system("cp -f $CONFIG{'skel_dir'}/local.cshrc $HOME{$uid}/.cshrc") if (-e "$CONFIG{'skel_dir'}/local.cshrc");
		system("cp -f $CONFIG{'skel_dir'}/local.login $HOME{$uid}/.login") if (-e "$CONFIG{'skel_dir'}/local.login");
		system("cp -f $CONFIG{'skel_dir'}/local.profile $HOME{$uid}/.profile") if (-e "$CONFIG{'skel_dir'}/local.profile");
		system("chown -R $uid:$UGID{$uid} $HOME{$uid}");
		system ("edquota -p $CONFIG{'quota_user'} $UIDNM{$uid}") if ($CONFIG{'quota_user'} ne '');
		&smb_passwd($UIDNM{$uid},$sreqp{$uid}) if ($CONFIG{'sync_smb'} eq 'yes');
	}
	print "</center>\n";
	%sreqn = ();
	%sreqg = ();
	%sreqp = ();
	%sreqt = ();
	%sreqs = ();
}

sub get_date {
	my($mytime) = @_;
	my($date);
	$mytime = time if ($mytime eq '');
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($mytime);

	if ($sec < 10) {
		$sec = "0$sec";
	}
	if ($min < 10) {
		$min = "0$min";
	}
	if ($hour < 10) {
		$hour = "0$hour";
	}
	if ($mon < 10) {
		$mon = "0$mon";
	}
	if ($mday < 10) {
	$mday = "$mday";
	}

	my $mm = ($mon + 1);
	$year -= 11;

	$date = "$year/$mm/$mday $hour\:$min\:$sec";
	chop($date) if ($date =~ /\n$/);
	$date;
}

sub myoct {
	my($num) = @_;
	my($perm1, $perm2, $perm3, $perm4);

	$perm1 = $num % 8;
	$num = int($num/8);
	$perm2 = $num % 8;
	$num = int($num/8);
	$perm3 = $num % 8;
	$perm4 = int($num/8);
	$perm = "$perm4$perm3$perm2$perm1";
	$perm;
}

sub err_perm {
	my($msg) = @_;
	&head("$SYSMSG{'title_system_info'}");
	print "<br><center><table border=0 style=font-size:11pt><tr><td><p>$SYSMSG{'err_perm_set'}</p>\n";
	print $msg;
	print '<ul>';
	print "<li>$SYSMSG{'msg_please_check_perm'}";
	print "<li>$SYSMSG{'msg_contact_administrator'}";
	print '</ul>';
	print '<hr color="#FF0000">';
	print "<center><a href=\"javascript:history.go(-1)\"><img align=absmiddle src=/img/upfolder.gif border=0>  $SYSMSG{'backto_prev_page'}</a></center>";
	print '</table></center></body>';
	print "</html>";
	exit 0;
}

sub check_perm {
	my($target,$flag) = @_;
	my $true = 0;
	my($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($target);
	my($perm) = &myoct($mode & 07777);
	if ($menu_id eq $uid) {
		$perm = substr($perm,1,1);
	} elsif ($menu_gid eq $gid) {
		$perm = substr($perm,2,1);
	} else {
		$perm = substr($perm,3,1);
	}
	if ($flag eq 0) {
		if ($menu_id eq $uid) {
			$true = 1;
		} else {
			$true = 0;
		}
	} else {
		$true = $perm & $flag;
	}
	$true = 1 if ($admin eq '1');
	$true;
}

sub quota_filesys {
	my(@p);
	%DEVFS = ();
	%FSDEV = ();
	open(MTAB, "/etc/mtab");
	while(<MTAB>) {
		s/\n//g;
		s/#.*$//g;
		next if (!/\S/);
		@p = split(/\s+/, $_);
		if ($p[2] =~ /ext/ && $p[3] =~ /usrquota/) {
			$DEVFS{$p[0]} = $p[1];
			$FSDEV{$p[1]} = $p[0];
		}
	}
	close(MTAB);
}

sub user_quota {
	my($uid) = @_;
	my($null,$dev, $bc, $bs, $bh, $fc, $fs, $fh);
	%filesys = ();
	%usrquota = ();
	@response = `quota $UIDNM{$uid} -v`;
	my $n=0;
	foreach $line (@response) {
		$n++;
		next if ($n <= 2);
		($null,$dev,$bc,$bs,$bh,$fc,$fs,$fh) = split(/\s+/,$line);
		$filesys{$DEVFS{$dev}} = $dev;
		$usrquota{$dev,'ublocks'} = int($bc);
		$usrquota{$dev,'sblocks'} = int($bs);
		$usrquota{$dev,'hblocks'} = int($bh);
		$usrquota{$dev,'ufiles'} = int($fc);
		$usrquota{$dev,'sfiles'} = int($fs);
		$usrquota{$dev,'hfiles'} = int($fh);
	}
}

sub edit_one_quota {
	my($u, $d, $sb, $hb, $sf, $hf) = @_;
	my(@devs, @sbs, @hbs, @sfs, @hfs, $i,$flag);
	@devs = split(/,/,$d);
	@sbs = split(/,/,$sb);
	@hbs = split(/,/,$hb);
	@sfs = split(/,/,$sf);
	@hfs = split(/,/,$hf);
	$flag = 0;
	$flag = 1 if (-f '/usr/sbin/setquota');
	$i = 0;
	foreach $dev (@devs) {
		if ($flag eq 0) {
			Quota::setqlim($dev, $u, ($sbs[$i],$hbs[$i],$sfs[$i],$hfs[$i]),1);
		} else {
			system("/usr/sbin/setquota -u $u $sbs[$i] $hbs[$i] $sfs[$i] $hfs[$i] $dev");
		}
		$i ++;
	}
}

sub edit_user_quota {
	my($u, $g, $w, $first, $temp_user);
	my($dev, @devs, $sblocks_def, $hblocks_def, $sfiles_def, $hfiles_def, $uid, $mygrp, $usr);
	$u = $DATA{'user'};
	$g = $DATA{'grp'};
	$w = $DATA{'word'};
	@devs = split(/,/,$DATA{'device'});
	foreach $dev (@devs) {
		$sblocks_def = $sblocks_def ne "" ? "$sblocks_def,$DATA{$dev.'_sb'}" : "$DATA{$dev.'_sb'}";
		$hblocks_def = $hblocks_def ne "" ? "$hblocks_def,$DATA{$dev.'_hb'}" : "$DATA{$dev.'_hb'}";
		$sfiles_def = $sfiles_def ne "" ? "$sfiles_def,0" : '0';
		$hfiles_def = $hfiles_def ne "" ? "$hfiles_def,0" : '0';
	}
	if ($u eq '999') {
		$g = '';
		$w = '';
		$first = '0';
		foreach $uid (keys %UIDS) {
			if (int($uid)>1000) {
				if ($first eq '0') {
					&edit_one_quota($uid,$DATA{'device'},$sblocks_def,$hblocks_def,$sfiles_def,$hfiles_def);
					$temp_user = $UIDNM{$uid};
					$first = '1';
				} else {
					system("edquota -p $temp_user $UIDNM{$uid}");
				}
			}
		}
	} elsif ($u ne '') {
		$g = '';
		$w = '';
		&edit_one_quota($UNMID{$u},$DATA{'device'},$sblocks_def,$hblocks_def,$sfiles_def,$hfiles_def);
	}
	if ($g ne '') {
		$w = '';
		$mygrp = $GNMID{$g};
		return if (int($mygrp)<500);
		$first = '0';
		foreach $uid (keys %UIDS) {
			if ($UGID{$uid} eq $mygrp) {
				if ($first eq '0') {
					&edit_one_quota($uid,$DATA{'device'},$sblocks_def,$hblocks_def,$sfiles_def,$hfiles_def);
					$temp_user = $UIDNM{$uid};
					$first = '1';
				} else {
					system("edquota -p $temp_user $UIDNM{$uid}");
				}
			}

		}
	}
	if ($w ne '') {
		$first = '0';
		foreach $usr (sort keys %UNAME) {
			if ($usr =~ /$w/) {
				if ($first eq '0') {
					&edit_one_quota($UNMID{$usr},$DATA{'device'},$sblocks_def,$hblocks_def,$sfiles_def,$hfiles_def);
					$temp_user = $usr;
					$first = '1';
				} else {
					system("edquota -p $temp_user $usr");
				}
			}
		}
	}
}

sub free_space {
	my($mydir) = @_;
	my($out, @rv, $dev, $u, $h);
	if ($admin eq '0') {
		&user_quota($menu_id);
		foreach $f (sort keys %filesys) {
			$dev=$filesys{$f} if ($mydir =~ /^$f/);
		}
		if ($dev) {
			$u = $usrquota{$dev,'ublocks'};
			$h = $usrquota{$dev,'hblocks'};
			push(@rv, ($h."K", $u."K", $h-$u."K", (int($u*10000/$h)/100)."%")) if ($h >= $u && $h>0 && $u>0);
		}
	}
	if (!defined $rv[0]) {
		$out = `df $mydir`;
		$out =~ /Mounted on\n\S+\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/;
		push(@rv, (int($1/1024)."M", int($2/1024)."M", int($3/1024)."M", $4."%"));
	}
	@rv;
}

$share_flag = 0;

sub get_dir {
	my($mydir) = @_;
	my($line, @lines);
	$mydir = '' if ($admin eq '0' && $mydir !~ /^$home(.+)/ );
	if ($mydir eq '') {
		$mydir = $home;
		$mydir = '/' if ($admin eq '1');
	}
	opendir (DIR, "$mydir") || &err_disk("$mydir $SYSMSG{'err_cannot_open_dir'}<br>");
	@lines=readdir(DIR);
	close(DIR);
	%FOLDS = ();
	%FILES = ();
	$filemgr_rows = -2;
	foreach $line (sort @lines) {
		if ($line !~ /^\.(\w+)/ || $admin eq '1') {
			if (-d "$mydir/$line") {
				$FOLDS{$line} ++;
				if ($SHARE{"$mydir/$line"} ne '') {
					$TYPE{$line} = $SYSMSG{'share'};
				} else {
					$TYPE{$line} = $SYSMSG{'dir'};
				}
				$IMAGE{$line} = '1folder.gif';
				$filemgr_rows ++;
			} elsif (-f _) {
				$FILES{$line} ++;
				if ($line =~ /.[G|g][I|i][F|f]$/) {
					$IMAGE{$line} = 'image.gif';
					$TYPE{$line} = 'GIF';
				} elsif ($line =~ /.[J|j][P|p][E|e]?[G|g]$/) {
					$IMAGE{$line} = 'image.gif';
					$TYPE{$line} = 'JPG';
				} elsif ($line =~ /.[P|p][N|n][G|g]$/) {
					$IMAGE{$line} = 'image.gif';
					$TYPE{$line} = 'PNG';
				} elsif ($line =~ /.[B|b][M|m][P|p]$/) {
					$IMAGE{$line} = 'image.gif';
					$TYPE{$line} = 'BMP';
				} elsif ($line =~ /.[H|h][T|t][M|m][L|l]?$/) {
					$IMAGE{$line} = 'html.gif';
					$TYPE{$line} = 'HTM';
				} elsif ($line =~ /.[T|t][X|x][T|t]$/) {
					$IMAGE{$line} = 'text.gif';
					$TYPE{$line} = 'TXT';
				} elsif ($line =~ /.[E|e][X|x][E|e]$/) {
					$IMAGE{$line} = 'exe.gif';
					$TYPE{$line} = 'EXE';
				} elsif ($line =~ /.[Z|z][I|i][P|p]$/) {
					$IMAGE{$line} = 'zip.gif';
					$TYPE{$line} = 'ZIP';
				} elsif ($line =~ /.[G|g][Z|z]$/) {
					$IMAGE{$line} = 'zip.gif';
					$TYPE{$line} = 'GZ';
				} elsif ($line =~ /.[W|w][A|a][V|v]$/) {
					$IMAGE{$line} = 'wav.gif';
					$TYPE{$line} = 'WAV';
				} elsif ($line =~ /.[M|m][P|p][G|g]$/) {
					$IMAGE{$line} = 'mpg.gif';
					$TYPE{$line} = 'MPG';
				} elsif ($line =~ /.[M|m][P|p][E|e][G|g]$/) {
					$IMAGE{$line} = 'mpg.gif';
					$TYPE{$line} = 'MPG';
				} elsif ($line =~ /.[A|a][U|u]$/) {
					$IMAGE{$line} = 'wav.gif';
					$TYPE{$line} = 'AU';
				} elsif ($line =~ /.[M|m][I|i][D|d][I|i]?$/) {
					$IMAGE{$line} = 'wav.gif';
					$TYPE{$line} = 'MID';
				} elsif ($line =~ /.[D|d][O|o][C|c|T|t]$/) {
					$IMAGE{$line} = 'doc.gif';
					$TYPE{$line} = 'DOC';
				} elsif ($line =~ /.[X|x][L|l].?$/) {
					$IMAGE{$line} = 'xls.gif';
					$TYPE{$line} = 'XLS';
				} elsif ($line =~ /.[M|m][D|d][B|b|A|a|W|w]?$/) {
					$IMAGE{$line} = 'mdb.gif';
					$TYPE{$line} = 'MDB';
				} else {
					$IMAGE{$line} = '1file.gif';
					$TYPE{$line} = $SYSMSG{'file'};
				}
				$filemgr_rows ++;
			}
		}
		($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat("$mydir/$line");
		$PERM{$line} = &myoct($mode & 07777);
		$OWNER{$line} = $uid;
		$GOWNER{$line} = $gid;
		$FSIZE{$line} = $size;
		$FTIME{$line} = $mtime;
		$MODIFY{$line} = &get_date($mtime);
	}
	$mydir;
}

sub by_perm {
	$PERM{$a} <=> $PERM{$b};
}

sub by_gowner {
	$GOWNER{$a} cmp $GOWNER{$b};
}

sub by_owner {
	$OWNER{$a} cmp $OWNER{$b};
}

sub by_type {
	$TYPE{$a} cmp $TYPE{$b};
}

sub by_size {
	$FSIZE{$a} <=> $FSIZE{$b};
}

sub by_time {
	$FTIME{$a} <=> $FTIME{$b};
}

sub get_share {
	my($mydir) = @_;
	my($line, $olddir,$check_ok);
	$share_flag = 1;
	$filemgr_rows = 0;
	$check_ok = 0;
	%FOLDS = ();
	%FILES = ();
	my($mgrp) = getgrgid($menu_gid);
	if ($mydir eq '' || $mydir eq '/') {
		foreach $line (keys %SHARE) {
			next if ($admin eq '0' && $SHARE{$line} !~ /$mgrp/);
			$FOLDS{$line} ++;
			$TYPE{$line} = $SYSMSG{'dir'};
			$IMAGE{$line} = '1folder.gif';
			$filemgr_rows ++;
		}
		$DATA{'share'} = '';
	} else {
		foreach $line (keys %SHARE) {
			next if ($admin eq '0' && $SHARE{$line} !~ /$mgrp/);
			$FOLDS{$line} ++;
			$TYPE{$line} = $SYSMSG{'dir'};
			$IMAGE{$line} = '1folder.gif';
			$filemgr_rows ++;
			$check_ok = 1 if ($mydir =~ /^$line.*/);
		}
		if ($check_ok eq 1) {
			$olddir = &get_dir($mydir);
		} else {
			$DATA{'share'} = '';
			$olddir = "/";
		}
	}
	$olddir;
}

sub chg_dir {
	my($olddir,$newdir) = @_;
	my($temp) = $olddir;
	if ($newdir eq '/') {
		$olddir = $home;
		$olddir = '/' if ($admin eq '1');
	} elsif ($newdir eq '..') {
		if ($share_flag eq 1) {
			if ($olddir eq $DATA{'share'}) {
				$DATA{'share'} = '';
				$olddir = '/';
			} else {
				my(@temp) = split(/\//, $olddir);
				pop(@temp);
				$olddir = join('/',@temp);
			}
		} elsif ($admin eq '1' || $olddir ne $home) {
				my(@temp) = split(/\//, $olddir);
				pop(@temp);
				$olddir = join('/',@temp);
		}
	} elsif ($newdir =~ /^\/.*/ && $admin eq '1') {
			$olddir = "/$newdir";
	} else {
		$newdir =~ s/\.\.\///g;
		if ($olddir eq '/') {
			$olddir .= "$newdir";
		} else {
			$olddir .= "/$newdir";
		}
	}
	if ($share_flag eq 0) {
		&err_perm("$SYSMSG{'err_cannot_read'} $olddir $SYSMSG{'err_folder_priv'}$SYSMSG{'err_so_cannot_chdir'}<br>") if ($olddir ne '/' && &check_perm($olddir,4) eq 0);
	}
	$DATA{'share'} = $olddir if ($SHARE{$olddir} ne '');
	$olddir;
}

sub make_dir {
	my($olddir,$newdir) = @_;
	$olddir if ($newdir eq '');
	if ($share_flag eq 0) {
		&err_perm("$SYSMSG{'err_cannot_write'} $olddir $SYSMSG{'err_folder_priv'}$SYSMSG{'err_so_cannot_mkdir'}<br>") if (&check_perm($olddir,2) eq 0);
	} else {
		&err_perm("$SYSMSG{'share_folder'}$olddir$SYSMSG{'err_so_cannot_mkdir'}<br>") if ($SPERM_DIR{$DATA{'share'}} ne 'yes');
	}
	if ($newdir =~ /(.*)\/(.+)/) {
		if ($olddir eq '/') {
			$olddir .= "$2";

		} else {
			$olddir .= "/$2";
		}
	} else {
		if ($olddir eq '/') {
			$olddir .= $newdir;
		} else {
			$olddir .= "/$newdir";
		}
	}
	system("mkdir -p $olddir");
	$olddir;
}

sub del_dir {
	my($olddir,$items) = @_;
	my $warning = 0;
	$olddir if ($items eq '');
	@files = split(/,/,$items);
	if ($share_flag eq 1 && $SPERM_DEL{$DATA{'share'}} ne 'yes') {
		&err_perm("$SYSMSG{'share_folder'}$olddir$SYSMSG{'err_so_cannot_delete'}<br>");
	} else {
		$olddir .= '/' if ($olddir ne '/');
		foreach $f (@files) {
			if (&check_perm("$olddir$f",0) eq 0) {
				$warning ++;
			} else {
				system("rm -rf $olddir$f/* : rmdir $olddir$f");
			}
		}
		&err_perm("<center>$warning $SYSMSG{'filemgr_cannot_del'}</center><br>") if ($warning > 0);
	}
}

sub chg_perm {
	my($perm,$olddir,$items) = @_;
	my $warning=0;
	$olddir if ($perm eq '' || $items eq '');
	@files = split(/,/,$items);
	$olddir .= '/' if ($olddir ne '/');
	foreach $f (@files) {
		if (&check_perm("$olddir$f",0) eq 0) {
			$warning ++;
		} else {
			system("chmod -R $perm $olddir$f");
		}
	}
	&err_perm("<center>$warning $SYSMSG{'filemgr_cannot_priv'}</center><br>") if ($warning > 0);
}

sub chg_owner {
	my($owner,$olddir,$items) = @_;
	my $warning=0;
	$olddir if ($owner eq '' || $items eq '');
	@files = split(/,/,$items);
	$olddir .= '/' if ($olddir ne '/');
	foreach $f (@files) {
		if (&check_perm("$olddir$f",0) eq 0) {
			$warning ++;
		} else {
			system("chown $owner $olddir$f");
		}
	}
	&err_perm("<center>$warning $SYSMSG{'filemgr_cannot_chown'}</center><br>") if ($warning > 0);
}

sub down_load {
	my($dnfile) = @_;
	my $fsize = (stat($dnfile))[7];
	open(REAL,"< $dnfile") || &err_disk("$SYSMSG{'err_cannot_open_download_file'} $dnfile<br>");
	binmode REAL;
	print "Content-length: $fsize\n";
	print "Content-type: application/octet-stream\n\n";
	while(read(REAL, $buf, 1024)) {
		print $buf;
	}
	close(REAL);
}

sub edit_file {
	my($dnfile) = @_;
	&head("$SYSMSG{'title_edit_file'} $dnfile");
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=step value=dosave>\n";
	print "<input type=hidden name=action value=>\n";
	print "<input type=hidden name=folder value=$olddir>\n";
	print "<input type=hidden name=edfile value=$dnfile>\n";
	print "<textarea name=textbody rows=17 cols=80 wrap=off>";
	open(REAL,"< $dnfile") || &err_disk("$SYSMSG{'err_cannot_open_edit_file'}$dnfile<br>");
	while(read(REAL, $buf, 1024)) {
		$buf =~ s/</&lt;/g;
		$buf =~ s/>/&gt;/g;
		print $buf;
	}
	close(REAL);
	print "</textarea>";
	print "<br><input type=button value=\" $SYSMSG{'save'} \" onclick=mysubmit('save');>";
	print "<input type=button value=\" $SYSMSG{'save_and_exit'} \" onclick=mysubmit('save_exit');>";
	print "<input type=reset value=\" $SYSMSG{'undo'} \"></center>\n";
	&foot('f');
	exit;
}

sub show_file {
	my($olddir,$dnfile) = @_;
	my $flag = 0;
	my($buf, $mydir);
	$olddir if ($dnfile eq '');
	$mydir = $olddir;
	$mydir .= '/' if ($mydir ne '/');
	&err_perm("$SYSMSG{'err_cannot_read'} $mydir$dnfile $SYSMSG{'err_file_priv'}$SYSMSG{'err_so_cannot_download'}<br>") if (&check_perm("$mydir$dnfile",4) eq 0 && $share_flag eq 0);
	if (-T "$mydir$dnfile") {
		if ($share_flag eq 1) {
			&err_perm("$SYSMSG{'share_folder'} $olddir$SYSMSG{'err_so_cannot_view'}<br>") if ($SPERM_EDIT{$DATA{'share'}} ne 'yes' && &check_perm("$mydir$dnfile",4) eq 0);
		} elsif (&check_perm("$mydir$dnfile",2) eq 0) {
			$flag = 1;
		}
		if ($flag eq 1) {
			print "Content-type: text/plain\n\n" ;
			open(REAL,"< $mydir$dnfile") || &err_disk("$SYSMSG{'err_cannot_open_download_file'}$mydir$dnfile<br>");
			while(read(REAL, $buf, 1024)) {
				print $buf;
			}
			close(REAL);
		} else { &edit_file("$mydir$dnfile"); }
	} elsif (-B _) {
		&err_perm("$SYSMSG{'share_folder'} $olddir$SYSMSG{'err_so_cannot_download'}<br>") if ($share_flag eq 1 && $SPERM_DN{$DATA{'share'}} ne 'yes');
		&down_load("$mydir$dnfile");
	}
	exit;
}

sub share {
	my($olddir,$share) = @_;
	my(@files, $file, $mydir, $i);
	$olddir if ($share eq '');
	$mydir = $olddir;
	$mydir .= '/' if ($mydir ne '/');
	@files = split(/,/,$share);
	$mydir = '' if ($files[0] =~ /^\/(.*)/);
	&head($SYSMSG{'title_sharemgr'});
	print "<center><table border=1 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
	print "<tr><td colspan=5><font size=+1 color=blue face=$SYSMSG{'variable_font'}>$SYSMSG{'share_config_these'}</font>\n";
	print "<form name=myform action=$cgi_url method=post><input type=hidden name=step value=doshare>\n";
	print "<input type=hidden name=folder value=$olddir>\n";
	print "<input type=hidden name=items value=$share>\n";
	foreach $file (@files) {
		if (-d "$mydir$file") {
			print "<tr><td colspan=5>$SYSMSG{'share_dir'}$mydir$file　$SYSMSG{'share_share_name'}<input type=text name=share-$file value=".$SDESC{"$mydir$file"}."></td>\n";
		}
	}
	$file = $files[0];
	print "<tr><td colspan=5><font size=+1 color=blue face=$SYSMSG{'variable_font'}>$SYSMSG{'share_to_what'}</font>\n";
	print "<tr><td colspan=5><input type=text name=word value=><a href=javascript:search()>$SYSMSG{'pattern_match'}</a></td>\n";
	print "<tr><td><input type=checkbox name=grp value=999>$SYSMSG{'everygrp'}</td>\n";
	my $i = 1;
	&read_group;
	foreach $gid (sort keys %GIDS) {
		$grp = $GIDNM{$gid};
		next if (int($gid)<500);
		next if (&check_special($grp) eq 1);
		print "<tr>" if (($i % 5) eq 0);
		$i ++;
		if ($SHARE{"$mydir$file"} =~ /$grp/) {
			print "<td><input type=checkbox name=grp value=$grp checked>$grp</td>\n";
		} else {
			print "<td><input type=checkbox name=grp value=$grp>$grp</td>\n";
		}
	}
	print "<tr><td colspan=5>$SYSMSG{'share_make_group'}<br>" if ($i<=0);
	print "<tr><td colspan=5><font size=+1 color=blue face=$SYSMSG{'variable_font'}>$SYSMSG{'share_grant'}</font>\n";
	if ($SPERM_DN{"$mydir$file"} eq 'yes') {
		print "<tr><td><input type=checkbox name=dn value=yes checked>$SYSMSG{'share_download'}\n";
	} else {
		print "<tr><td><input type=checkbox name=dn value=yes>$SYSMSG{'share_download'}\n";
	}
	if ($SPERM_UP{"$mydir$file"} eq 'yes') {
		print "<td><input type=checkbox name=up value=yes checked>$SYSMSG{'share_upload'}\n";
	} else {
		print "<td><input type=checkbox name=up value=yes>$SYSMSG{'share_upload'}\n";
	}
	if ($SPERM_DIR{"$mydir$file"} eq 'yes') {
		print "<td><input type=checkbox name=dir value=yes checked>$SYSMSG{'share_mkdir'}\n";
	} else {
		print "<td><input type=checkbox name=dir value=yes>$SYSMSG{'share_mkdir'}\n";
	}
	if ($SPERM_EDIT{"$mydir$file"} eq 'yes') {
		print "<td><input type=checkbox name=edit value=yes checked>$SYSMSG{'share_delete'}\n";
	} else {
		print "<td><input type=checkbox name=edit value=yes>$SYSMSG{'share_edit'}\n";
	}
	if ($SPERM_DEL{"$mydir$file"} eq 'yes') {
		print "<td><input type=checkbox name=del value=yes checked>$SYSMSG{'share_delete'}</table>\n";
	} else {
		print "<td><input type=checkbox name=del value=yes>$SYSMSG{'share_delete'}</table>\n";
	}
	if ($i <= 0) {
		print "<a href=javascript:history.go(-1)>$SYSMSG{'cancel'}</a></form>\n";
		print "<script>\nfunction search() { }\n";
	} elsif ($i>1) {
		print "<input type=button value=\" $SYSMSG{'confirm'} \" onclick=javascript:check()>　　<a href=javascript:history.go(-1)>$SYSMSG{'cancel'}</a></form>\n";
		print "<script>\nfunction check() {\nvar flag = 0;\n";
		print "for (i=0;i<$i;i++) { if (thisform.grp[i].checked) { flag = 1; } }\n";
		print "if (flag == 0) { alert('$SYSMSG{'please_select'}'); } else { thisform.submit(); } }\n";
		print "function search() { var word = thisform.word.value;\n";
		print "for (i=0;i<$i;i++) { if (thisform.grp[i].value.indexOf(word)!=-1) { thisform.grp[i].checked = 1; }\n";
		print "else { thisform.grp[i].checked = 0; } } }\n";
	} else {
		print "<input type=button value=\" $SYSMSG{'confirm'} \" onclick=javascript:check()>　　<a href=javascript:history.go(-1)>$SYSMSG{'cancel'}</a></form>\n";
		print "<script>\n function check() {\n";
		print "if (!thisform.grp.checked) { alert('$SYSMSG{'please_select'}'); } else { thisform.submit(); } }\n";
		print "function search() { var word = thisform.word.value;\n";
		print "if (thisform.grp.value.indexOf(word)!=-1) { thisform.grp.checked = 1; }\n";
		print "else { thisform.grp.checked = 0; } }\n";
	}
	print "</script></center>";
	&foot('s');
	exit;
}

sub del_share {
	my($items) = @_;
	$olddir if ($items eq '');
	@files = split(/,/,$items);
	if ($admin eq '1') {
		foreach $f (@files) {
			delete $SHARE{$f};
		}
		$DATA{'share'} = '';
		&write_share;
	}
	&head($SYSMSG{'title_sharemgr'});
	print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'share_cancel_completed'}</font>";
	&foot('s');
	exit;
}

sub many_download {
	my($olddir,$items) = @_;
	my($buf, $mydir, $tmpfolder, $dnfile);
	$olddir if ($items eq '');
	$tmpfolder = time;
	$mydir = $olddir;
	$mydir .= '/' if ($olddir ne '/');
	@files = split(/,/,$items);
	&err_perm("$SYSMSG{'share_folder'} $olddir$SYSMSG{'err_so_cannot_download'}<br>") if ($share_flag eq 1 && $SPERM_DN{$DATA{'share'}} ne 'yes');
	system("mkdir -p /tmp/$menu_id/temp/$tmpfolder");
	foreach $f (@files) {
		system("cp -Rf $mydir$f /tmp/$menu_id/temp/$tmpfolder > /dev/null") if (&check_perm("$mydir$f",4) ne 0 || $share_flag eq 1);
	}
	if ($zip_exist) {
		system("zip -rq /tmp/$menu_id/$tmpfolder /tmp/$menu_id/temp/$tmpfolder > /dev/null");
		$dnfile = "/tmp/$menu_id/$tmpfolder\.zip";
	} else {
		system("tar -zcf /tmp/$menu_id/$tmpfolder\.tar\.gz /tmp/$menu_id/temp/$tmpfolder > /dev/null");
		$dnfile = "/tmp/$menu_id/$tmpfolder\.tar\.gz";
	}
	&down_load($dnfile);
	$)=0;
	$>=0;
	system("rm -Rf /tmp/$menu_id");
	if ($admin ne '1') {
		$) = $menu_gid;
		$> = $menu_id;
	}
	exit;
}

sub ren_dir {
	my($newname,$olddir,$items) = @_;
	$olddir if ($olddor eq '' || $newname eq '' || $items eq '');
	@files = split(/,/,$items);
	$f = $files[0];
	$olddir .= '/' if ($olddir ne '/');
	if ($share_flag eq 0) {
		&err_perm("$SYSMSG{'err_cannot_change'} $olddir$f $SYSMSG{'err_name_priv'}<br>") if (&check_perm("$olddir$f",2) eq 0);
	} else {
		&err_perm("$SYSMSG{'share_folder'} $olddir $SYSMSG{'err_so_cannot_modify'}<br>") if ($SPERM_UP{$DATA{'share'}} ne 'yes');
	}
	system("mv $olddir$f $olddir$newname");
}

sub move_dir {
	my($dest,$olddir,$items) = @_;
	$olddir if ($dest eq '' || $items eq '');
	@files = split(/,/,$items);
	$f = $files[0];
	$olddir .= '/' if ($olddir ne '/');
	if ($admin eq '0') {
		if (substr($dest,0,1) eq '/') {
			$dest = substr($dest,1);
			$dest = "$olddir$dest" ;
		} else {
			$dest = "$olddir$dest" ;
		}
	} else {
		$dest = "$olddir$dest" if (substr($dest,0,1) ne '/');
	}
	if (-e "$dest") {
		&err_perm("$SYSMSG{'err_cannot_move_to_others'}<br>") if (&check_perm("$dest",2) eq 0);
	} else {
		&err_perm("$SYSMSG{'err_cannot_move_to_others'}<br>") if (&check_perm("$olddir",2) eq 0);
	}
	&err_perm("$SYSMSG{'err_cannot_move_from_others'}<br>") if (&check_perm("$olddir$f",0) eq 0);
	system("mv $olddir$f $dest");
	system("chown $menu_id:$menu_gid $dest/$f");
}

sub copy_dir {
	my($dest,$olddir,$items) = @_;
	$olddir if ($dest eq '' || $items eq '');
	@files = split(/,/,$items);
	$f = $files[0];
	$olddir .= '/' if ($olddir ne '/');
	if ($admin eq '0') {
		if (substr($dest,0,1) eq '/') {
			$dest = substr($dest,1);
			$dest = "$olddir$dest" ;
		} else {
			$dest = "$olddir$dest" ;
		}
	} else {
		$dest = "$olddir$dest" if (substr($dest,0,1) ne '/');
	}
	if (-e "$dest") {
		&err_perm("$SYSMSG{'err_cannot_copy_to_others'}<br>") if (&check_perm("$dest",2) eq 0);
	} else {
		&err_perm("$SYSMSG{'err_cannot_copy_to_others'}<br>") if (&check_perm("$olddir",2) eq 0);
	}
	&err_perm("$SYSMSG{'err_cannot_copy_from_others'}<br>") if (&check_perm("$olddir$f",0) eq 0);
	system("cp -Rf $olddir$f $dest");
	system("chown $menu_id:$menu_gid $dest/$f");
}

sub get_digits {
	opendir (DIR, "$cnt_base") || &err_disk("$SYSMSG{'err_cannot_open_counter_dir'}<br>");
	@STYLES=readdir(DIR);
	close(DIR);
}

sub new_digits {
	&head($SYSMSG{'title_add_counter'});
	print "<center>$SYSMSG{'counter_minihelp'}\n";
	print "<form name=myform ENCTYPE=\"multipart/form-data\" method=post action=\"$cgi_url\">\n";
	print "<input type=hidden name=step value=imgmgr>\n";
	print "$SYSMSG{'counter_lib_name'}<input type=text name=folder value=><br>\n";
	for ($z=0;$z<=9;++$z) { print "<img align=absmiddle src=/img/upload.gif border=0>$SYSMSG{'counter_digit'}$z：<input type=file name=\"digits_$z\"><br>\n"; }
	print "<input type=submit value=\" $SYSMSG{'counter_confirm'} \">\n";
	print "</form></center></tr>";
	&foot('');
	exit;
}

sub read_cnt_conf {
	my($conf) = @_;
	%CNTCONF = ();
	if (-e $conf) {
		open (CFG, "< $conf") || &err_disk("$SYSMSG{'err_cannot_open_counter_config'}<br>");
		while ($line = <CFG>) {
			my($name, $value) = split(/:/, $line);
			$value =~ s/\n//g;
			$CNTCONF{$name} = $value;
		}
		close(CFG);
	} else {
		$CNTCONF{'start'} = 0;
		$CNTCONF{'check_ip'} = 'yes';
		$CNTCONF{'add'} = 1;
		$CNTCONF{'digits'} = 5;
		$CNTCONF{'style'} = '01';
		open (CFG, "> $conf") || &err_disk("$SYSMSG{'err_cannot_open_counter_config'}<br>");
		foreach $name (keys %CNTCONF) {
			print CFG "$name:$CNTCONF{$name}\n";
		}
		close(CFG);
	}
}

sub read_cnt_data {
	my($data) = @_;
	%COUNT = ();
	%LASTIP = ();
	if (-e $data) {
		open (SCFG, "< $data") || &err_disk("$SYSMSG{'err_cannot_open_counter_data'}<br>");
		while ($line = <SCFG>) {
			my($urlname, $counter, $lastip) = split(/:/, $line);
			$lastip =~ s/\n//g;
			$COUNT{$urlname} = $counter;
			$LASTIP{$urlname} = $lastip;
		}
		close(SCFG);
	}
}

sub write_cnt_data {
	my($data) = @_;
	open (SCFG, "> $data") || &err_disk("$SYSMSG{'err_cannot_open_counter_data'}<br>");
	flock(SCFG,2);
	foreach $name (keys %COUNT) {
		$str = join ':', $name, $COUNT{$name}, $LASTIP{$name}."\n";
		print SCFG $str;
	}
	flock(SCFG,8);
	close(SCFG);
}

sub read_gb_conf {
	my($conf) = @_;
	%GBCONF = ();
	if (-e $conf) {
		open (SCFG, "< $conf") || &err_disk("$SYSMSG{'err_cannot_open_gbook_config'}<br>");
		while ($line = <SCFG>) {
			my($name, $value) = split(/:/, $line);
			$value =~ s/\n//g;
			$GBCONF{$name} = $value;
		}
		close(SCFG);
	} else {
		$GBCONF{'title'} = getpwuid($menu_id)."$SYSMSG{'gbook_owned'}";
		$GBCONF{'many'} = 5;
		$GBCONF{'page_jump'} = 'yes';
		$GBCONF{'sort'} = 'by_date';
		open (SCFG, "> $conf") || &err_disk("$SYSMSG{'err_cannot_open_gbook_config'}<br>");
		foreach $name (keys %GBCONF) {
			print SCFG "$name:$GBCONF{$name}\n";
		}
		close(SCFG);
	}
}

sub read_gb_data {
	my($data) = @_;
	%GBPARN = ();
	%GBDATE = ();
	%GBAUTH = ();
	%GBMAIL = ();
	%GBTITLE = ();
	%MESSAGES = ();
	%MODE = ();
	if (-e $data) {
		open (DATA, "< $data") || &err_disk("$SYSMSG{'err_cannot_open_gbook_message'}<br>");
		while ($line = <DATA>) {
			my($cnt,$parn,$gdate,$auth,$mail,$mtitle,$mlink,$mod) = split(/:::/, $line);
			if (length($mod) eq 0) {
				$mlink =~ s/\n//g;
				$GBIP{$cnt} = '0.0.0.0';
				$GBDATE{$cnt} = $parn;
				$GBAUTH{$cnt} = $gdate;
				$GBMAIL{$cnt} = $auth;
				$GBTITLE{$cnt} = $mail;
				$MESSAGES{$cnt} = $mtitle;
				$MODE{$cnt} = $mlink;
			} else {
				$mod =~ s/\n//g;
				$GBIP{$cnt} = $parn;
				$GBDATE{$cnt} = $gdate;
				$GBAUTH{$cnt} = $auth;
				$GBMAIL{$cnt} = $mail;
				$GBTITLE{$cnt} = $mtitle;
				$MESSAGES{$cnt} = $mlink;
				$MODE{$cnt} = $mod;
			}
		}
		close(DATA);
	}
}

sub read_gb_reply {
	my($data) = @_;
	%REPARN = ();
	%REDATE = ();
	%REAUTH = ();
	%REMAIL = ();
	%RETITLE = ();
	%REPLYS = ();
	%REIP = ();
	if (-e $data) {
		open (DATA, "< $data") || &err_disk("$SYSMSG{'err_cannot_open_gbook_message'}<br>");
		while ($line = <DATA>) {
			my($cnt,$parn,$gdate,$auth,$mail,$mtitle,$mlink,$ip) = split(/:::/, $line);
			$ip =~ s/\n//g;
			$REPARN{$cnt} = $parn;
			$REDATE{$cnt} = $gdate;
			$REAUTH{$cnt} = $auth;
			$REMAIL{$cnt} = $mail;
			$RETITLE{$cnt} = $mtitle;
			$REPLYS{$cnt} = $mlink;
			$REIP{$cnt} = $ip;
		}
		close(DATA);
	}
}

sub write_gb_data {
	my($data) = @_;
	open (DATA, "> $data") || &err_disk("$SYSMSG{'err_cannot_open_gbook_message'}<br>");
	foreach $cnt (keys %GBDATE) {
		$str = join ':::',$cnt,$GBIP{$cnt},$GBDATE{$cnt},$GBAUTH{$cnt},$GBMAIL{$cnt},$GBTITLE{$cnt},$MESSAGES{$cnt},$MODE{$cnt}."\n";
		print DATA $str;
	}
	close(DATA);
}

sub write_gb_reply {
	my($data) = @_;
	open (DATA, "> $data") || &err_disk("$SYSMSG{'err_cannot_open_gbook_message'}<br>");
	foreach $cnt (keys %REDATE) {
		$str = join ':::',$cnt,$REPARN{$cnt},$REDATE{$cnt},$REAUTH{$cnt},$REMAIL{$cnt},$RETITLE{$cnt},$REPLYS{$cnt},$REIP{$cnt}."\n";
		print DATA $str;
	}
	close(DATA);
}

sub read_gb_subscribe {
	my($data) = @_;
	if (-e $data) {
		open (DATA, "< $data") || &err_disk("$SYSMSG{'err_cannot_open_gbook_subscribe'}<br>");
		my $i = 0;
		while ($line = <DATA>) {
			$line =~ s/\n//g;
			$SUBSCRIBE{$i}=$line;
			$i ++;
		}
		close(DATA);
	}
}

sub write_gb_subscribe {
	my($data) = @_;
	open (DATA, "> $data") || &err_disk("$SYSMSG{'err_cannot_open_gbook_subscribe'}<br>");
	foreach $line (sort values %SUBSCRIBE) {
		print DATA "$line\n";
	}
	close(DATA);
}

sub mail2me {
	my($subject, $body) = @_;
	open(MAIL,"|$CONFIG{'mailprog'} -t")  || &err_disk("$SYSMSG{'err_cannot_open'}$CONFIG{'mailprog'}$SYSMSG{'program'}.<br>");
	print MAIL "To: $UIDNM{$menu_id}\@$HOST\n";
	print MAIL "From: $SYSMSG{'wam'}(wam\@$HOST)\n";
	print MAIL "Subject: $subject\n\n";
	print MAIL "$SYSMSG{'from_wam'}\n";
	print MAIL "-" x 75 . "\n\n";
	$body =~ s/<br>/\r\n/g;
	print MAIL "$body\n\n";
	print MAIL "-" x 75 . "\n\n";
	close (MAIL);
}

sub set_aliases {
	my($aliase,$maillist) = @_;
	open(ALIAS,"$CONFIG{'mailaliases'}")  || &err_disk("$SYSMSG{'err_cannot_open_aliases'}$CONFIG{'mailaliases'}.<br>");
	@lines=<ALIAS>;
	close (ALIAS);
	system("mv $CONFIG{'mailaliases'} $CONFIG{'mailaliases'}.org");
	open(ALIAS,">$CONFIG{'mailaliases'}")  || &err_disk("$SYSMSG{'err_cannot_open_aliases'}$CONFIG{'mailaliases'}.<br>");
	foreach $line (@lines) {
		print ALIAS $line if ($line !~ /^$aliase: /);
	}
	print ALIAS "$aliase: \":include:$maillist\"\n";
	close (ALIAS);
}

sub unset_aliases {
	my($aliase) = @_;
	open(ALIAS,"$CONFIG{'mailaliases'}")  || &err_disk("$SYSMSG{'err_cannot_open_aliases'}$CONFIG{'mailaliases'}.<br>");
	@lines=<ALIAS>;
	close (ALIAS);
	system("mv $CONFIG{'mailaliases'} $CONFIG{'mailaliases'}.org");
	open(ALIAS,">$CONFIG{'mailaliases'}")  || &err_disk("$SYSMSG{'err_cannot_open_aliases'}$CONFIG{'mailaliases'}.<br>");
	foreach $line (@lines) {
		print ALIAS $line if ($line !~ /^$aliase: /);
	}
	close (ALIAS);
}

sub gb_submailer {
	my($from, $usr, $subject, $body) = @_;
	($musr,$pwd,$muid,$mgid,$quo,$com,$gcos,$home,$shell) = getpwuid($menu_id);
	$from = $SYSMSG{'gbook_miss_from'} if ($from eq "");
	open(MAIL,"|$CONFIG{'mailprog'} -t")  || &err_disk("$SYSMSG{'err_cannot_open'} $CONFIG{'mailprog'} $SYSMSG{'program'}<br>");
	print MAIL "To: gbook-$musr\@$HOST\n";
	print MAIL "From: $from\n";
	print MAIL "Subject: $subject\n\n";
	print MAIL "$usr $SYSMSG{'gbook_post_on'}$GBCONF{'title'}$SYSMSG{'gbook_above'}\n\n";
	print MAIL "$SYSMSG{'gbook_click_here'} $GBCONF{'title'} http://$HOST:$PORT/gbook.cgi?user=$user \n";
	print MAIL "-" x 75 . "\n\n";
	$body =~ s/<br>/\r\n/g;
	print MAIL "$body\n\n";
	print MAIL "-" x 75 . "\n\n";
	close (MAIL);
}

sub get_wam_version {
	open(VERSION, "version") || return 0;
	chop($myver = <VERSION>);
	close(VERSION);
	$myver;
}

sub patch {
	my($myfile) = @_;
	if ($myfile =~ /(.+).zip/ && $zip_exist) {
		system("unzip -d /root -uoqq $myfile > /dev/null");
	} elsif ($myfile =~ /(.+).tar.gz/) {
		system("cd /root");
		system("tar -xzvf $myfile > /dev/null");
	}
	system("cp -R /root/wam/* /usr/libexec/wam");
	system("chmod 0755 /usr/libexec/wam/*.cgi");
	system("chmod 0755 /usr/libexec/wam/patch.sh");
	system("chmod 0755 /usr/libexec/wam/patch.cgi");
	system("chmod 0755 /usr/libexec/wam/install");
	system("rm -rf /root/wam");
	`/usr/libexec/wam/patch.sh` if (-f "/usr/libexec/wam/patch.sh");
	`perl /usr/libexec/wam/patch.cgi` if (-f "/usr/libexec/wam/patch.cgi");
}

sub err_socket {
	my($msg) = @_;
	&head($SYSMSG{'title_system_info'});
	print "<center><table border=0 style=font-size:11pt><tr><td><p><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'err_cannot_open_socket'}</font></p>\n";
	print $msg;
	print $SYSMSG{'msg_please_check'};
	print '<ul>';
	print "<li>$SYSMSG{'err_miss_host_or_port'}";
	print "<li>$SYSMSG{'err_request_time_out'}";
	print "<li>$SYSMSG{'err_file_too_large'}";
	print '</ul>';
	print '<hr color="#FF0000">';
	print '<a href="javascript:history.go(-1)"><img align=absmiddle src=/img/upfolder.gif border=0>  回上一頁</a></center>';
	print '</table></center></body>';
	print "</html>";
	exit 0;
}

sub open_socket {
	my($httphost,$serverport,$type) = @_;
	eval {
		local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
		alarm 5;
		$remote_sock=new IO::Socket::INET(   Proto=>$type,
							     PeerAddr=>$httphost,
								 PeerPort=>$serverport,);
		alarm 0;
	};
	&err_socket($SYSMSG{'err_connect_break'}) if ($@);
	&err_socket($SYSMSG{'err_connect_failue'}) if (!$remote_sock);
	$remote_sock->autoflush(1);
	$remote_sock;
}

sub http_download {
	my($httphost,$serverport,$pageurl,$dnfile) = @_;
	my($line, %header,$buf);
	if ($CONFIG{'http_proxy'} ne '' && $CONFIG{'proxy_port'} ne '') {
		# going through proxy
		$remote_sock = &open_socket($CONFIG{'http_proxy'},$CONFIG{'proxy_port'},'tcp');
	} else {
		# can connect directly
		$remote_sock = &open_socket($httphost,$serverport,'tcp');
	}
	print $remote_sock "GET http://$httphost:$serverport/$pageurl HTTP/1.0\r\n";
	print $remote_sock "\r\n";

	# read headers
	alarm(60);
	($line = <$remote_sock>) =~ s/\r|\n//g;
	&err_socket($SYSMSG{'err_cannot_download_file'}) if ($line !~ /\/1\..\s+200\s+/);
	while(<$remote_sock> =~ /^(\S+):\s+(.*)$/) { $header{lc($1)} = $2; }
	alarm(0);
	# read data
	open(PFILE, "> $dnfile")  || &err_disk("$SYSMSG{'err_cannot_save_upgrade'}<br>");
	while(read($remote_sock, $buf, 1024) > 0) { print PFILE $buf; }
	close(PFILE);
	close($remote_sock);
}

sub head {
	my($title) = @_;
	print "Content-type: text/html\n\n";
	print "<head><meta http-equiv='Content-Type' content='text/html; charset=UTF8'><meta http-equiv=Content-Type content=\"$SYSMSG{'charset'}\">\n";
	print '<META HTTP-EQUIV="Pargma" CONTENT="no-cache">'."\n";
	print "<title>$title</title><link rel='stylesheet' type='text/css' href='test.css'>\n";
	print "<script>\n";
	print "function init() { thisform = document.myform; }\n";
	print 'function chk_empty(item) { if ((item.value=="") || (item.value.indexOf(" ")!=-1) ) { return true; } }'."\n";
	print 'function chggrp() { thisform.grp.value = thisform.grps.options[thisform.grps.selectedIndex].value; }'."\n";
	print 'function mysubmit(myaction) { thisform.action.value = myaction;'."\n";
	print ' thisform.submit();}'."\n";
	print 'function rest(id) {'."\n";
	print 'if (id==0) { thisform.grp.value = ""; }'."\n";
	print 'if (id==1) { thisform.user.value = ""; }'."\n";
	print 'if (id==2) { thisform.grp.value = ""; thisform.user.value = ""; }'."\n";
	print 'if (id==3) { thisform.pwd.value = ""; thisform.pwd2.value = ""; } }'."\n";
	print "</script></head><body onload=init() style='font-size:11pt' bgcolor=#ffffff><center><font size=+2 face=$SYSMSG{'variable_font'} color=darkblue>$title </font><font size=2 color=darkred>Ver.</font><font size=2 color=blue> $myver</font> [ ";
	if ($admin eq '1') {
		print "<a href=/help/help_root.htm target=_blank>$SYSMSG{'root_help'}</a> ]</center>";
	} else {
		print "<a href=/help/help_user.htm target=_blank>$SYSMSG{'help'}</a> ]</center>";
	}
}

sub foot {
	my($flag) = @_;
	print "<hr color=#FF0000><center>\n";
	print "<font size=3>【<a href=\"javascript:history.go(-1)\"><img align=absmiddle src=/img/upfolder.gif border=0>$SYSMSG{'backto_prev_page'}</a>  】\n";
	print "</font></center></body></html>";
}

#***********************************************************************************
# MAIN
#***********************************************************************************
&get_wam_version;
&read_conf;
&get_lang;
&check_acl;
&read_shadow;
&read_passwd;
&read_shells;
&read_gconf;
&read_group;
&read_share;
&quota_filesys;

while (FCGI::accept()>=0) {

$| = 1;
$today = int(time / 86400);

&check_referer;
&get_form_data;
&check_password;

if ($DATA{'flag'} eq 'deny' || $DATA{'step'} eq '' || $DATA{'step'} eq 'relogon') {
	&empty_cookie;
	&head($SYSMSG{'logon'});
	print '<center><a href="javascript:onclick=alert('."'".$SYSMSG{'logon_alt'}."'".')" border=0><img align=absmiddle src=/img/wam.gif border=0></a>'."\n";
	print "<form name=login method=post>\n";
	print "<input type=hidden name=step value=$DATA{'step'}>\n";
	print "<table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
	print "<tr><th align=left>$SYSMSG{'loginname'}：\n";
	print "<td><input type=text name=user maxlength=20 size=20>\n";
	print "<th align=right>$SYSMSG{'loginpasswd'}：\n";
	print "<td><input type=password name=password size=20>\n";
	print "<td  colspan=2 align=center>\n";
	print "<input type=submit value=\" $SYSMSG{'logon'} \">\n";
	print "</table></form></center></body>\n";
	exit;
}
$admin='0';
foreach $acc (split(/,/,$GUSRS{'wam'})) {
	$admin='1' if ($acc =~ /^$UIDNM{$menu_id}$/);
}
$> = 0;
$) = 0;

if ($DATA{'step'} eq 'menu' && $menu_id ne '') {
	print "Content-type: text/html\n\n";
	print "<head><meta http-equiv=Content-Type content=\"$SYSMSG{'charset'}\">\n";
	print "<META HTTP-EQUIV=Pargma CONTENT=no-cache>\n";
	print "<title>WAM $myver</title></head>\n";
	print "<FRAMESET COLS=\"130,*\"  framespacing=0 border=0 frameborder=0>\n";
	print "<FRAME SRC=$cgi_url?step=show_left NAME=wam_left marginwidth=0 marginheight=0 noresize>\n";
	print "<FRAME SRC=$cgi_url?step=show_right NAME=wam_main>\n";
	print "</FRAMESET>\n";
} elsif ($DATA{'step'} eq 'show_left') {
	print "Content-type: text/html\n\n";
	print "<head><meta http-equiv=Content-Type content=\"$SYSMSG{'charset'}\">\n";
	print "<META HTTP-EQUIV=Pargma CONTENT=no-cache>\n";
	print "<title>WAM $myver</title>\n";
	print "<base target=wam_main></head>\n";
	print "<body link=#FFFFFF vlink=#ffffff alink=#FFCC00  style='SCROLLBAR-FACE-COLOR: #ddeeff; SCROLLBAR-HIGHLIGHT-COLOR: #ffffff; SCROLLBAR-SHADOW-COLOR: #ABDBEC; SCROLLBAR-3DLIGHT-COLOR: #A4DFEF; SCROLLBAR-ARROW-COLOR: steelblue; SCROLLBAR-TRACK-COLOR: #DDF0F6; SCROLLBAR-DARKSHADOW-COLOR: #9BD6E6'>\n";
	print "<table style=\"font-size: 11 pt; border-collapse:collapse\" height=100% width=100% border=1 cellspadding=2 bordercolorlight=#808080 bordercolordark=#C0C0C0 cellpadding=2 align=left bordercolor=#FFFFFF cellspacing=1>\n";
	print "<tr><td align=center bgcolor=#3E7BB9 width=100% height=100%><b><font color=#FFFFFF>WAM $myver</font></b></td></tr>\n";
	if ($admin eq '1') {
	print "<tr><td align=center bgColor=#6699cc width=100% height=100%><a href=/help/help_root.htm style=\"text-decoration: none\">$SYSMSG{'help'}</a></td></tr>\n";
	print "<tr><td align=center bgcolor=#FFCC00 width=100% height=100%><b>$SYSMSG{'submenu_system'}</b></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=config\" style=\"text-decoration: none\">$SYSMSG{'set_config'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=setadmin\" style=\"text-decoration: none\">$SYSMSG{'set_wam_manager'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=filesmgr\" style=\"text-decoration: none\">$SYSMSG{'file_manager'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=sharemgr\" style=\"text-decoration: none\">$SYSMSG{'share_folder'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=edquota\" style=\"text-decoration: none\">$SYSMSG{'quota_setup'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#FFCC00 width=100% height=100%><b>$SYSMSG{'submenu_account'}</b></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=addgrp\" style=\"text-decoration: none\">$SYSMSG{'group_add'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=addone\" style=\"text-decoration: none\">$SYSMSG{'account_add_one'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=delete\" style=\"text-decoration: none\">$SYSMSG{'del_group_account'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=autoadd\" style=\"text-decoration: none\">$SYSMSG{'autoadd_account'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=upload\" style=\"text-decoration: none\">$SYSMSG{'add_account_from_file'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=resetpw\" style=\"text-decoration: none\">$SYSMSG{'reset_passwd'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=chgpw\" style=\"text-decoration: none\">$SYSMSG{'change_passwd'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=struct\" style=\"text-decoration: none\">$SYSMSG{'view_struct'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=check\" style=\"text-decoration: none\">$SYSMSG{'check_account'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=trace\" style=\"text-decoration: none\">$SYSMSG{'trace_account'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#FFCC00 width=100% height=100%><b>$SYSMSG{'submenu_homepage'}</b></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=imgmgr\" style=\"text-decoration: none\">$SYSMSG{'counter_img'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=set_count\" style=\"text-decoration: none\">$SYSMSG{'set_counter'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=view_count\" style=\"text-decoration: none\">$SYSMSG{'view_counter'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=set_gb\" style=\"text-decoration: none\">$SYSMSG{'set_gbook'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=edit_gb\" style=\"text-decoration: none\">$SYSMSG{'manage_gbook'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#ffcc00 width=100% height=100%><b>$SYSMSG{'online_upgrade'}</td></tr>\n";
	print "<tr><td align=center bgColor=#6699cc width=100% height=100%><a href=\"$cgi_url?step=upgrade\" style=\"text-decoration: none\">$SYSMSG{'online_upgrade'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#ffcc00 width=100% height=100%><b>$SYSMSG{'logout'}</td></tr>\n";
	print "<tr><td align=center bgColor=#3E7BB9 width=100% height=100%><a href=\"$cgi_url?step=relogon\" target=_top style=\"text-decoration: none\">$SYSMSG{'logout'}</a></td></tr>\n";
	} else {
	print "<tr><td align=center bgColor=#FFCC00 width=100% height=100%><a href=/help/help_user.htm style=\"text-decoration: none\"><b><font color=black>$SYSMSG{'help'}</b></font></a></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=filesmgr\" style=\"text-decoration: none\">$SYSMSG{'file_manager'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=sharemgr\" style=\"text-decoration: none\">$SYSMSG{'share_folder'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=chgpw\" style=\"text-decoration: none\">$SYSMSG{'change_passwd'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=set_count\" style=\"text-decoration: none\">$SYSMSG{'set_counter'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=view_count\" style=\"text-decoration: none\">$SYSMSG{'view_counter'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=set_gb\" style=\"text-decoration: none\">$SYSMSG{'set_gbook'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#6699CC width=100% height=100%><a href=\"$cgi_url?step=edit_gb\" style=\"text-decoration: none\">$SYSMSG{'manage_gbook'}</a></td></tr>\n";
	print "<tr><td align=center bgColor=#ffcc00 width=100% height=100%><b>$SYSMSG{'logout'}</td></tr>\n";
	print "<tr><td align=center bgColor=#3E7BB9 width=100% height=100%><a href=\"$cgi_url?step=relogon\" target=_top style=\"text-decoration: none\">$SYSMSG{'logout'}</a></td></tr>\n";
	}
	print "</table></body></html>\n";
} elsif ($DATA{'step'} eq 'show_right') {
	&head($SYSMSG{'logon'});
	print "<center><a href=\"javascript:onclick=alert('$SYSMSG{'logon_alt'}')\" border=0><img align=absmiddle src=/img/wam.gif border=0></a>\n";
	print "</center></body>\n";
} elsif ($DATA{'step'} eq 'config' && $admin eq '1') {
	&head($SYSMSG{'title_setup'});
	&get_lang_list;
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=step value=doconfig>\n";
	print "<table border=6 style=font-size:11pt width=95%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
	print "<tr  style=background-color:#ffffff><th align=right>$SYSMSG{'config_language'}</th>\n";
	print "<td><select size=1 name=lang>";
	$CONFIG{'lang'} = 'Big-5' if ($CONFIG{'lang'} eq '');
	foreach $i (@LANGS) {
		next if ($i =~ /^\./);
		if ($CONFIG{'lang'} eq $i) {
			print "<option value=$i selected>$i</option>\n";
		} else {
			print "<option value=$i>$i</option>\n";
		}
	}
	print "</select></td>\n";
	print "<tr style=background-color:#6582CD><th align=right><font color=#ffffff>$SYSMSG{'config_aclcontrol'}</font></th>\n";
	if ($CONFIG{'acltype'} eq 1) {
		print "<td><input type=radio name=acltype value=1 checked><font color=#ffffff>$SYSMSG{'config_allow_ip'}　<input type=radio name=acltype value=0>$SYSMSG{'config_deny_ip'}</font></td>\n";
	} else {
		print "<td><input type=radio name=acltype value=1><font color=#ffffff>$SYSMSG{'config_allow_ip'}　<input type=radio name=acltype value=0 checked>$SYSMSG{'config_deny_ip'}</font></td>\n";
	}
	print "<tr style=background-color:#ddeeff><th align=right>$SYSMSG{'config_acl_rule'}</th>\n";
	print "<td><textarea rows=3 cols=30 name=acls>$CONFIG{'acls'}</textarea></td></tr>\n";
	print "<tr style=background-color:#FFD1BB><th align=right>$SYSMSG{'config_upgrade_proxy'}</th>\n";
	print "<td>$SYSMSG{'config_proxy_hostname'}:<input type=text name=http_proxy value=$CONFIG{'http_proxy'}>\n";
	print "$SYSMSG{'config_proxy_port'}:<input type=text size=6 name=proxy_port value=$CONFIG{'proxy_port'}></td>\n";
	print "<tr  style=background-color:#ffffff><th align=right>$SYSMSG{'config_shell_dir'}</th>\n";
	$CONFIG{'shells'} = '/etc/shells' if ($CONFIG{'shells'} eq '');
	print "<td><input type=text name=shells value=$CONFIG{'shells'}></td>\n";
	print "<tr style=background-color:#ffffff><th align=right>$SYSMSG{'config_group_file'}</th>\n";
	$CONFIG{'group'} = '/etc/group' if ($CONFIG{'group'} eq '');
	print "<td><input type=text name=group value=$CONFIG{'group'}></td>\n";
	print "<tr style=background-color:#ffffff><th align=right>$SYSMSG{'config_group_shadow'}</th>\n";
	$CONFIG{'gshadow'} = '/etc/gshadow' if ($CONFIG{'gshadow'} eq '');
	print "<td><input type=text name=gshadow value=$CONFIG{'gshadow'}></td>\n";
	print "<tr style=background-color:#ffffff><th align=right>$SYSMSG{'config_passwd_file'}</th>\n";
	$CONFIG{'passwd'} = '/etc/passwd' if ($CONFIG{'passwd'} eq '');
	print "<td><input type=text name=passwd value=$CONFIG{'passwd'}></td>\n";
	print "<tr style=background-color:#ffffff><th align=right>$SYSMSG{'config_shadow_file'}</th>\n";
	$CONFIG{'shadow'} = '/etc/shadow' if ($CONFIG{'shadow'} eq '');
	print "<td><input type=text name=shadow value=$CONFIG{'shadow'}></td>\n";
	print "<tr style=background-color:#D2FFE1><th align=right>$SYSMSG{'config_mail_prog'}</th>\n";
	$CONFIG{'mailprog'} = '/usr/bin/sendmail' if ($CONFIG{'mailprog'} eq '');
	print "<td><input type=text name=mailprog value=$CONFIG{'mailprog'}></td>\n";
	print "<tr style=background-color:#D2FFE1><th align=right>$SYSMSG{'config_mail_aliase'}</th>\n";
	$CONFIG{'mailaliases'} = '/etc/aliases' if ($CONFIG{'mailaliases'} eq '');
	print "<td><input type=text name=mailaliases value=$CONFIG{'mailaliases'}></td>\n";
	print "<tr style=background-color:#ECFFEC><th align=right>$SYSMSG{'config_samba_prog'}</th>\n";
	$CONFIG{'smbprog'} = '/usr/bin/smbpasswd' if ($CONFIG{'smbprog'} eq '');
	print "<td><input type=text name=smbprog value=$CONFIG{'smbprog'}></td>\n";
	print "<tr style=background-color:#ECFFEC><th align=right>$SYSMSG{'config_samba_passwd_file'}</th>\n";
	$CONFIG{'smbpasswd'} = '/etc/smbpasswd' if ($CONFIG{'smbpasswd'} eq '');
	print "<td><input type=text name=smbpasswd value=$CONFIG{'smbpasswd'}></td>\n";
	print "<tr style=background-color:#D7E2FF><th align=right>$SYSMSG{'config_samba_passwd_sync'}</th>";
	if ($CONFIG{'sync_smb'} eq 'yes') {
		print "<td><input type=checkbox name=sync_smb value=yes checked></td>\n";
	} else {
		print "<td><input type=checkbox name=sync_smb value=yes></td>\n";
	}
	print "<tr style=background-color:#E8EFFF><th align=right>$SYSMSG{'config_samba_use_codepage'}</th>";
	if ($CONFIG{'codepage_smb'} eq 'yes') {
		print "<td><input type=checkbox name=codepage_smb value=yes checked></td>\n";
	} else {
		print "<td><input type=checkbox name=codepage_smb value=yes></td>\n";
	}
	print "<tr style=background-color:#E8EFFF><th align=right>$SYSMSG{'config_account_nest'}</th>";
	if ($CONFIG{'home_nest'} eq 'yes') {
		print "<td><input type=checkbox name=home_nest value=yes checked></td>\n";
	} else {
		print "<td><input type=checkbox name=home_nest value=yes></td>\n";
	}
	print "<tr style=background-color:#E8EFFF><th align=right>$SYSMSG{'config_account_auto_homepage'}</th>";
	if ($CONFIG{'add_homepage'} eq 'yes') {
		print "<td><input type=checkbox name=add_homepage value=yes checked></td>\n";
	} else {
		print "<td><input type=checkbox name=add_homepage value=yes></td>\n";
	}
	print "<tr style=background-color:#E8EFFF><th align=right>$SYSMSG{'config_account_nest_level'}</th>";
	print "<td><select size=1 name=nest>\n";
	$CONFIG{'nest'} = 1 if ($CONFIG{'nest'} eq '');
	for ($i=1;$i<4;$i++) {
		if ($CONFIG{'nest'} eq $i) {
			print "<option value=$i selected>$i</option>\n";
		} else {
			print "<option value=$i>$i</option>\n";
		}
	}
	print "</select></td>\n";
	print "<tr style=background-color:#F2D7FF><th align=right>$SYSMSG{'config_account_auto_passwd_style'}</th>\n";
	print "<td><select size=1 name=passwd_form>";
	$CONFIG{'passwd_form'} = 'username' if ($CONFIG{'passwd_form'} eq '');
	if ($CONFIG{'passwd_form'} eq 'username') {
		print "<option value=username selected>$SYSMSG{'config_account_auto_passwd_style_username'}</option>\n";
	} else {
		print "<option value=username>$SYSMSG{'config_account_auto_passwd_style_username'}</option>\n";
	}
	if ($CONFIG{'passwd_form'} eq 'random') {
		print "<option value=random selected>$SYSMSG{'config_account_auto_passwd_style_random'}</option>\n";
	} else {
		print "<option value=random>$SYSMSG{'config_account_auto_passwd_style_random'}</option>\n";
	}
	if ($CONFIG{'passwd_form'} eq 'single') {
		print "<option value=single selected>$SYSMSG{'config_account_auto_passwd_style_single'}</option>\n";
	} else {
		print "<option value=single>$SYSMSG{'config_account_auto_passwd_style_single'}</option>\n";
	}
	print "</select></td>\n";
	print "<tr style=background-color:#F9ECFF><th align=right>$SYSMSG{'config_account_auto_passwd_range'}</th>\n";
	print "<td><select size=1 name=passwd_range>";
	$CONFIG{'passwd_range'} = 'num' if ($CONFIG{'passwd_range'} eq '');
	if ($CONFIG{'passwd_range'} eq 'num') {
		print "<option value=num selected>$SYSMSG{'config_account_passwd_style_no'}</option>\n";
	} else {
		print "<option value=num>$SYSMSG{'config_account_passwd_style_no'}</option>\n";
	}
	if ($CONFIG{'passwd_range'} eq 'lcase') {
		print "<option value=lcase selected>$SYSMSG{'config_account_passwd_style_LCase'}</option>\n";
	} else {
		print "<option value=lcase>$SYSMSG{'config_account_passwd_style_LCase'}</option>\n";
	}
	if ($CONFIG{'passwd_range'} eq 'ucase') {
		print "<option value=ucase selected>$SYSMSG{'config_account_passwd_style_UCase'}</option>\n";
	} else {
		print "<option value=ucase>$SYSMSG{'config_account_passwd_style_UCase'}</option>\n";
	}
	if ($CONFIG{'passwd_range'} eq 'allcase') {
		print "<option value=allcase selected>$SYSMSG{'config_account_passwd_style_U&LCase'}</option>\n";
	} else {
		print "<option value=allcase>$SYSMSG{'config_account_passwd_style_U&LCase'}</option>\n";
	}
	if ($CONFIG{'passwd_range'} eq 'num-lcase') {
		print "<option value='num-lcase' selected>$SYSMSG{'config_account_passwd_style_no&LCase'}</option>\n";
	} else {
		print "<option value='num-lcase'>$SYSMSG{'config_account_passwd_style_no&LCase'}</option>\n";
	}
	if ($CONFIG{'passwd_range'} eq 'num-ucase') {
		print "<option value='num-ucase' selected>$SYSMSG{'config_account_passwd_style_no&UCase'}</option>\n";
	} else {
		print "<option value='num-ucase'>$SYSMSG{'config_account_passwd_style_no&UCase'}</option>\n";
	}
	if ($CONFIG{'passwd_range'} eq 'all') {
		print "<option value='all' selected>$SYSMSG{'config_account_passwd_style_any_Case'}</option>\n";
	} else {
		print "<option value='all'>$SYSMSG{'config_account_passwd_style_any_Case'}</option>\n";
	}
	print "</select></td>\n";
	print "<tr style=background-color:#F9ECFF><th align=right>$SYSMSG{'config_account_passwd_change_rule'}</th>";
	if (int($CONFIG{'passwd_rule'})%2) {
		print "<td><input type=checkbox name=passwd_rule1 value=yes checked>$SYSMSG{'config_account_passwd_limit_428'}</td>\n";
	} else {
		print "<td><input type=checkbox name=passwd_rule1 value=yes>$SYSMSG{'config_account_passwd_limit_428'}</td>\n";
	}
	if (int($CONFIG{'passwd_rule'})%4 >= 2) {
		print "<tr style=background-color:#F9ECFF><td><td><input type=checkbox name=passwd_rule2 value=yes checked>$SYSMSG{'config_account_passwd_limit_no&letter'}</td>\n";
	} else {
		print "<tr style=background-color:#F9ECFF><td><td><input type=checkbox name=passwd_rule2 value=yes>$SYSMSG{'config_account_passwd_limit_no&letter'}</td>\n";
	}
	if (int($CONFIG{'passwd_rule'})%8 >= 4) {
		print "<tr style=background-color:#F9ECFF><td><td><input type=checkbox name=passwd_rule3 value=yes checked>$SYSMSG{'config_account_passwd_limit_diffrent'}</td>\n";
	} else {
		print "<tr style=background-color:#F9ECFF><td><td><input type=checkbox name=passwd_rule3 value=yes>$SYSMSG{'config_account_passwd_limit_diffrent'}</td>\n";
	}
	if (int($CONFIG{'passwd_rule'}) >= 8) {
		print "<tr style=background-color:#F9ECFF><td><td><input type=checkbox name=passwd_rule4 value=yes checked>$SYSMSG{'config_account_passwd_limit_keyboard'}</td>\n";
	} else {
		print "<tr style=background-color:#F9ECFF><td><td><input type=checkbox name=passwd_rule4 value=yes>$SYSMSG{'config_account_passwd_limit_keyboard'}</td>\n";
	}
	print "<tr style=background-color:#DFeeFF><th align=right>$SYSMSG{'config_user_home_dir'}</th>\n";
	$CONFIG{'base_dir'} = '/home' if ($CONFIG{'base_dir'} eq '');
	print "<td><input type=text name=base_dir value=$CONFIG{'base_dir'}></td>\n";
	print "<tr style=background-color:#DFFFFF><th align=right>$SYSMSG{'config_user_skel'}</th>\n";
	$CONFIG{'skel_dir'} = '/etc/skel' if ($CONFIG{'skel_dir'} eq '');
	print "<td><input type=text name=skel_dir value=$CONFIG{'skel_dir'}></td>\n";
	print "<tr style=background-color:#DFFFFF><th align=right>$SYSMSG{'config_user_shell'}</th>\n";
	$CONFIG{'shell'} = '/bin/bash' if ($CONFIG{'shell'} eq '');
	print "<td><select size=1 name=shell>";
	foreach $shls (@SHLS) {
		if ("$CONFIG{'shell'}\n" eq $shls) {
			print "<option value=$shls selected>$shls</option>\n";
		} else {
			print "<option value=$shls>$shls</option>\n";
		}
	}
	print "</select></td>\n";
	print "<tr style=background-color:#DFFFFF><th align=right>$SYSMSG{'config_user_homepage_dir'}</th>\n";
	$CONFIG{'home_dir'} = 'public_html' if ($CONFIG{'home_dir'} eq '');
	print "<td><input type=text name=home_dir value=$CONFIG{'home_dir'}></td>\n";
	&make_index if (!(-e "$tmp_index"));
	print "<tr style=background-color:#DFFFFF><td><img src=/img/home.gif align=right></td><td><a href=$cgi_url?step=edit_file&dnfile=$tmp_index>$SYSMSG{'config_edit_user_homepage_sample'}</a></td>\n";
	print "<tr style=background-color:#E8deFF><th align=right>$SYSMSG{'config_days_to_change'}</th>\n";
	print "<td><input type=text name=min value=$CONFIG{'min'}></td>\n";
	print "<tr style=background-color:#E8EFFF><th align=right>$SYSMSG{'config_days_to_force_change'}</th>\n";
	print "<td><input type=text name=max value=$CONFIG{'max'}></td>\n";
	print "<tr style=background-color:#E8EFFF><th align=right>$SYSMSG{'config_days_to_hint'}</th>\n";
	print "<td><input type=text name=pwarn value=$CONFIG{'pwarn'}></td>\n";
	print "<tr style=background-color:#E8EFFF><th align=right>$SYSMSG{'config_days_to_inact'}</th>\n";
	print "<td><input type=text name=inact value=$CONFIG{'inact'}></td>\n";
	print "<tr style=background-color:#E8EFFF><th align=right>$SYSMSG{'config_days_to_expire'}</th>\n";
	print "<td><input type=text name=expire value=$CONFIG{'expire'}></td>\n";
	print "<tr style=background-color:#E8EFFF><th align=right>$SYSMSG{'config_account_flag_status'}</th>\n";
	print "<td><input type=text name=flag value=$CONFIG{'flag'}></td>\n";
	print "<tr style=background-color:#6582CD><th align=right><font color=#FFFFFF>$SYSMSG{'config_account_quota_sample'}</font></th>\n";
	print "><td><select size=1 name=quota_user>\n";
	print "<option value=></option>\n";
	foreach $usr (sort keys %UNAME) {
		$uid = $UNMID{$usr};
		next if (int($uid)<500);
		next if (&check_special($usr) eq 1);
		if ($CONFIG{'quota_user'} eq $usr) {
			print "<option value=$usr selected>$usr</option>\n";
		} else {
			print "<option value=$usr>$usr</option>\n";
		}
	}
	print "</select></td>\n";
	print "<tr><td colspan=2 align=center><img align=absmiddle src=/img/chgpw.gif><input type=submit value=\" $SYSMSG{'config_save_config'} \"></td>\n";
	print "</table></form></center>";
	&foot('');
} elsif ($DATA{'step'} eq 'doconfig' && $admin eq '1') {
	my $myrule = 0;
	$myrule = $myrule + 1 if ($DATA{'passwd_rule1'} eq 'yes');
	$myrule = $myrule + 2 if ($DATA{'passwd_rule2'} eq 'yes');
	$myrule = $myrule + 4 if ($DATA{'passwd_rule3'} eq 'yes');
	$myrule = $myrule + 8 if ($DATA{'passwd_rule4'} eq 'yes');
	open (CFG, "> $config") || die "<font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'err_cannot_open_passwd'}</font><br>";
	print CFG "http_proxy:".$DATA{'http_proxy'}."\n";
	print CFG "proxy_port:".$DATA{'proxy_port'}."\n";
	print CFG "lang:".$DATA{'lang'}."\n";
	print CFG "shells:".$DATA{'shells'}."\n";
	print CFG "group:".$DATA{'group'}."\n";
	print CFG "gshadow:".$DATA{'gshadow'}."\n";
	print CFG "passwd:".$DATA{'passwd'}."\n";
	print CFG "shadow:".$DATA{'shadow'}."\n";
	print CFG "mailprog:".$DATA{'mailprog'}."\n";
	print CFG "mailaliases:".$DATA{'mailaliases'}."\n";
	print CFG "smbprog:".$DATA{'smbprog'}."\n";
	print CFG "smbpasswd:".$DATA{'smbpasswd'}."\n";
	print CFG "sync_smb:".$DATA{'sync_smb'}."\n";
	print CFG "codepage_smb:".$DATA{'codepage_smb'}."\n";
	print CFG "home_nest:".$DATA{'home_nest'}."\n";
	print CFG "nest:".$DATA{'nest'}."\n";
	print CFG "add_homepage:".$DATA{'add_homepage'}."\n";
	print CFG "passwd_form:".$DATA{'passwd_form'}."\n";
	print CFG "passwd_range:".$DATA{'passwd_range'}."\n";
	print CFG "passwd_rule:".$myrule."\n";
	print CFG "base_dir:".$DATA{'base_dir'}."\n";
	print CFG "home_dir:".$DATA{'home_dir'}."\n";
	print CFG "skel_dir:".$DATA{'skel_dir'}."\n";
	print CFG "shell:".$DATA{'shell'}."\n";
	print CFG "min:".$DATA{'min'}."\n";
	print CFG "max:".$DATA{'max'}."\n";
	print CFG "pwarn:".$DATA{'pwarn'}."\n";
	print CFG "inact:".$DATA{'inact'}."\n";
	print CFG "expire:".$DATA{'expire'}."\n";
	print CFG "flag:".$DATA{'flag'}."\n";
	print CFG "quota_user:".$DATA{'quota_user'}."\n";
	print CFG "acltype:".$DATA{'acltype'}."\n";
	print CFG "acls:".$DATA{'acls'}."\n";
	close(CFG);
	system("echo '' > $DATA{'smbpasswd'}") if not (-e "$DATA{'smbpasswd'}");
	&head($SYSMSG{'title_setup'});
	print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'config_completed'}</font></center>\n";
	&foot('');
} elsif ($DATA{'step'} eq 'upgrade' && $admin eq '1') {
	&head($SYSMSG{'title_upgrade'});
	print "<form name=myform method=POST ENCTYPE=\"multipart/form-data\">";
	print "<input type=hidden name=step value=doupgrade>\n";
	print "<div align=center><center>\n";
	print "<table border=6 style=font-size:11pt width=90% cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
	print "<tr><td colspan=2><img align=absmiddle src=/img/upgrade.gif><font  color=darkblue >$SYSMSG{'online_upgrade_minihelp'}</td>";
	print "<tr bgcolor=6699cc ><td colspan=2><font color=#ffffff><b>$SYSMSG{'online_upgrade_choose'}<b></font></td></tr>";
	print "<tr><td	width=5%><img align=absmiddle src=/img/computer.gif></td><td><input type=radio id=mode1 name=mode value=local><font  color=darkgreen>$SYSMSG{'online_upgrade_choose_1'}</font><input type=text name=file size=28 onclick=\"document.all['mode1'].checked=1\"></td></tr>";
	print "<tr><td	width=5%><img align=absmiddle src=/img/upload.gif></td><td><input type=radio id=mode2 name=mode value=upload><font  color=darkblue>$SYSMSG{'online_upgrade_choose_2'}</font><input type=file name=upload_file size=20 onclick=\"document.all['mode2'].checked=1\"></td></tr>";
	print "<tr><td	width=5%><img align=absmiddle src=/img/network.gif></td><td><input type=radio id=mode3 name=mode value=http checked><font color=red><b>$SYSMSG{'online_upgrade_choose_3'}</b></td></tr>";
	print "</table><hr color=#6699cc size=1><input type=submit value=\" $SYSMSG{'online_upgrade_confirm'} \">";
	print "</center></div></form>";
	&foot('');
} elsif ($DATA{'step'} eq 'doupgrade' && $admin eq '1') {
	if ($DATA{'mode'} eq 'local') {
		&patch($DATA{'file'});
	} elsif ($DATA{'mode'} eq 'http') {
		$type = 'tar.gz';
		$type = 'zip' if ($zip_exist);
		&http_download('webmail.ysps.tp.edu.tw','12000',"logon.cgi?type=$type&ver=$myver&host=$HOST",'/usr/libexec/wam/patch/upgrade.wam');
		open(PATCH, "/usr/libexec/wam/patch/upgrade.wam") || &err_disk($SYSMSG{'err_cannot_open_upgrade'}."<br>");
		chop($myfile=<PATCH>);
		close(PATCH);
		if ($myfile =~ /^wam-(.+)-upgrade\.(.*)$/) {
			&http_download('webmail.ysps.tp.edu.tw','12000',"/patch/$myfile","/usr/libexec/wam/patch/$myfile");
			&patch("/usr/libexec/wam/patch/$myfile");
		}
	}
	&get_wam_version;
	&head($SYSMSG{'title_upgrade'});
	if ($myfile =~ /^wam-(.+)-upgrade\.(.*)$/) {
		print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5><img align=absmiddle src=/img/s_wam.gif>$SYSMSG{'online_upgrade_completed'} $myver !!!</font></center>\n";
	} else {
		print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5><img align=absmiddle src=/img/upload.gif>$myfile</font></center>\n";
	}
	&foot('');
} elsif ($DATA{'step'} eq 'setadmin' && $admin eq '1') {
	&head($SYSMSG{'title_manager'});
	print "<center><div align=center><form method=POST name=aform>\n";
	print "<input type=hidden name=step value=add_wam>\n";
	print "<table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
	print "<tr><td align=center bgcolor=#6699cc><font color=white><b><img align=absmiddle src=/img/addone.gif>$SYSMSG{'wam_manager_add'}</b></font>\n";
	print "<tr><td><select size=1 name=user>\n";
	print "<option value=></option>\n";
	foreach $usr (sort keys %UNAME) {
		$uid = $UNMID{$usr};
		next if (int($uid)<500);
		next if (&check_special($usr) eq 1);
		next if ($GUSRS{'wam'} =~ /$usr/);
		print "<option value=$usr>$usr</option>\n";
	}
	print "</select>\n";
	print '<tr><td align=left><img align=absmiddle src=/img/chgpw.gif><input type=submit value="  '.$SYSMSG{'wam_manager_addnew'}.'  "></table></form><hr>'."\n";
	print "<form method=POST>\n";
	print "<input type=hidden name=step value=del_wam>\n";
	print "<table border=6 style=font-size:11pt width=65%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
	print "<tr><td colspan=5 align=left bgcolor=#6699cc><font color=white><b><img align=absmiddle src=/img/addgrp.gif>$SYSMSG{'wam_manager_now'}</b></font>\n";
	my $i = 0;
	my @name = split(/,/, $GUSRS{'wam'});
	foreach $usr (sort @name) {
		print "<tr>" if (($i % 5) eq 0);
		$i ++;
		print "<td><input type=checkbox name=$usr value=ON>$usr\n";
	}
	print '<tr><td align=center colspan=5><img align=absmiddle src=/img/del_.gif><input type=submit value="  '.$SYSMSG{'wam_manager_delete'}.'  "></table></form></div></center>',"\n";
	&foot('');
} elsif ($DATA{'step'} eq 'add_wam' && $admin eq '1') {
	&head($SYSMSG{'title_manager'});
	&add_wam($DATA{'user'});
	&write_group;
	print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'wam_manager_add_completed'} $DATA{'user'} </font></center>\n";
	&foot('');
} elsif ($DATA{'step'} eq 'del_wam' && $admin eq '1') {
	&head($SYSMSG{'title_manager'});
	print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'wam_manager_del_action'}</font><br>\n";
	foreach $usr (keys %DATA) {
		if ($DATA{$usr} eq "ON") {
			&del_wam($usr);
			print "$usr<br>\n";
		}
	}
	&write_group;
	print "<font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'wam_manager_del_completed'}</font></center>\n";
	&foot('');
} elsif ($DATA{'step'} eq 'addgrp' && $admin eq '1') {
	&head($SYSMSG{'title_addgrp'});
	print "<script>\n function check() { if (chk_empty(thisform.grp)) { alert('$SYSMSG{'group_empty_name'}'); } else { thisform.submit(); } }\n</script>\n";
	print "<script>\n function newhome() { document.myform.home.value= '/home/'+document.myform.grp.value}\n</script>\n";
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=step value=doaddgrp>\n";
	print "<table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
	print "<tr><td><img align=absmiddle  src=/img/addgrp.gif> <font  color=red><b>$SYSMSG{'groupname'}</b></font><input type=text name=grp>";
	print "<tr><td><img align=absmiddle  src=/img/home.gif> <font  color=blue><b>$SYSMSG{'group_home_dir'}</b></font><input type=text name=home value=$CONFIG{'base_dir'}/>" if ($CONFIG{'home_nest'} eq 'yes');
	print "<tr><td align=center><input type=button value=\" $SYSMSG{'group_add_this'} \" onclick=javascript:check()>\n";
	print "</table></form><hr>";
	print "<table border=6 style=font-size:11pt width=95%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
	print "<tr><td colspan=8 align=center bgcolor=#6699cc><img align=absmiddle  src=/img/addgrp.gif><font color=white><b>$SYSMSG{'group_now'}</b></font>\n";
	my $i = 0;
	foreach $gname (sort keys %GNAME) {
		print "<tr>" if (($i % 8) eq 0);
		$i ++;
		print "<td>$gname\n";
	}
	print "</table></form>";
	&foot('');
} elsif ($DATA{'step'} eq 'doaddgrp' && $admin eq '1') {
	&head($SYSMSG{'title_addgrp'});
	$DATA{'home'} .= "/$DATA{'grp'}" if ($CONFIG{'home_nest'} eq 'yes' && $DATA{'home'} eq $CONFIG{'base_dir'});
	&add_grp($DATA{'grp'},$DATA{'home'});
	&write_group;
	&write_gconf;
	print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'group_add_completed'}</font></center>\n";
	&foot('');
} elsif ($DATA{'step'} eq 'addone' && $admin eq '1') {
	&head($SYSMSG{'title_addoneuser'});
	print "<script>\n function check() { if (chk_empty(thisform.user) || chk_empty(thisform.pwd)) { alert('$SYSMSG{'err_blank_input'}'); } else { thisform.submit(); } }\n</script>\n";
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=step value=doaddone>\n";
	print "<table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
	print "<tr><th align=right><font  color=darkgreen>$SYSMSG{'username'}</font><img align=absmiddle  src=/img/addone.gif>\n";
	print "<td><input type=text name=user>\n";
	print "<tr><th align=right><font  color=darkblue>$SYSMSG{'password'}</font><img align=absmiddle  src=/img/chgpw.gif>\n";
	print "<td><input type=text name=pwd>\n";
	print "<tr><th align=right><font  color=darkred>$SYSMSG{'account_add_group'}</font><img align=absmiddle  src=/img/addgrp.gif>\n";
	print "<td><select size=1 name=grp>";
	foreach $grp (sort keys %GNAME) {
		$gid = $GNMID{$grp};
		next if (int($gid)<500 && $gid ne 0);
		next if (&check_special($grp) eq 1);
		print "<option value=$grp>$grp</option>\n";
	}
	print "</select>\n";
	print "<tr><th align=right><font  color=red>$SYSMSG{'account_add_to_manager'}</font><img align=absmiddle  src=/img/root.gif>\n";
	print "<td><input type=checkbox name=admin value=ON>";
	print "<tr><td><td><input type=button value=\" $SYSMSG{'account_add_confirm'} \" onclick=javascript:check()>\n";
	print "</table>";
	print "</form></center>";
	&foot('');
} elsif ($DATA{'step'} eq 'doaddone' && $admin eq '1') {
	&head($SYSMSG{'title_addoneuser'});
	&addone($DATA{'user'}, $DATA{'grp'}, $DATA{'pwd'}, '');
	&add_wam($DATA{'user'}) if ($DATA{'admin'} eq "ON");
	&write_group;
	&make_passwd;
	&foot('');
} elsif ($DATA{'step'} eq 'upload' && $admin eq '1') {
	&head($SYSMSG{'title_manuadd'});
	print "<script>\n function check() { if (thisform.upload_file=='') { alert('$SYSMSG{'err_file_select_not_yet'}'); } else { thisform.submit(); } }\n</script>\n";
	print '<center><form name=myform enctype="multipart/form-data" method=post>'."\n";
	print "<input type=hidden name=step value=doupload>\n";
	print "<table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
	print "<tr><td colspan=2 align=left>$SYSMSG{'manuadd_minihelp'}<br>\n";
	print "<font color=green><b>$SYSMSG{'manuadd_minihelp_1'}</b></font><br>\n";
	print "$SYSMSG{'manuadd_minihelp_2'}<br>\n";
	print "<font color=red><b>$SYSMSG{'manuadd_minihelp_3'}</b></font><br>\n";
	print "$SYSMSG{'manuadd_minihelp_4'}<br>\n";
	print "<hr><tr><th align=right><img align=absmiddle src=/img/0folder.gif>$SYSMSG{'manuadd_uploadfile'}";
	print "<td><input type=file name=\"upload_file\">\n";
	print "<tr><td><td><input type=button value=\" $SYSMSG{'manuadd_confirm'} \" onclick=javascript:check()>\n";
	print "</table>";
	print "</form></center>";
	&foot('');
} elsif ($DATA{'step'} eq 'doupload' && $admin eq '1') {
	&head($SYSMSG{'title_manuadd'});
	&read_request;
	&make_passwd;
	&foot('');
} elsif ($DATA{'step'} eq 'autoadd' && $admin eq '1') {
	&head($SYSMSG{'title_autoadd'});
	if ($CONFIG{'nest'} eq 1) {
		print "<script>\n function check() { if (chk_empty(thisform.grp) || chk_empty(thisform.num1) || chk_empty(thisform.num2)) { alert('$SYSMSG{'autoadd_blank_1'}'); } else { thisform.submit(); } }\n</script>\n";
	} elsif ($CONFIG{'nest'} eq 2) {
		print "<script>\n function check() { if (chk_empty(thisform.pre_name) || chk_empty(thisform.num1) || chk_empty(thisform.num2) || chk_empty(thisform.grade_num1) || chk_empty(thisform.grade_num2)) { alert('$SYSMSG{'autoadd_blank_2'}'); } else { thisform.submit(); } }\n</script>\n";
	} elsif ($CONFIG{'nest'} eq 3) {
		print "<script>\n function check() { if (chk_empty(thisform.pre_name) || chk_empty(thisform.num1) || chk_empty(thisform.num2) || chk_empty(thisform.grade_num1) || chk_empty(thisform.grade_num2) || chk_empty(thisform.class_num1) || chk_empty(thisform.class_num2)) { alert('$SYSMSG{'autoadd_blank_3'}'); } else { thisform.submit(); } }\n</script>\n";
	}
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=step value=doauto>\n";
	print "<table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
	if ($CONFIG{'nest'} eq 1) {
		&read_group;
		print "<tr><th align=right>$SYSMSG{'groupname'}<br>$SYSMSG{'group_hint'}\n";
		print "<td><input type=text size=12 name=grp><br>";
		print "<select size=1 name=grps onchange=chggrp();>\n";
		foreach $grp (sort keys %GNAME) {
			$gid = $GNMID{$grp};
			next if (int($gid)<500);
			next if (&check_special($grp) eq 1);
			print "<option value=$grp>$grp</option>\n";
		}
		print "</select>\n";
	}
	print "<tr><th align=right><font color=darkred>$SYSMSG{'autoadd_pre'}</font>\n";
	print "<td><input type=text name=pre_name size=8>\n";
	if ($CONFIG{'nest'} eq 2) {
		print "<tr><th align=right><font color=darkgreen>$SYSMSG{'autoadd_level_2'}</font>\n";
		print "<td>$SYSMSG{'autoadd_from'} <input type=text name=grade_num1 size=3> $SYSMSG{'autoadd_to'} <input type=text name=grade_num2 size=3> $SYSMSG{'autoadd_class'}\n";
	}
	if ($CONFIG{'nest'} eq 3) {
		print "<tr><th align=right><font color=darkgreen>$SYSMSG{'autoadd_level_2'}</font>\n";
		print "<td>$SYSMSG{'autoadd_from'} <input type=text name=grade_num1 size=3> $SYSMSG{'autoadd_to'} <input type=text name=grade_num2 size=3> $SYSMSG{'autoadd_grade'}\n";
		print "<tr><th align=right><font color=darkblue>$SYSMSG{'autoadd_level_3'}</font>\n";
		print "<td>$SYSMSG{'autoadd_from'} <input type=text name=class_num1 size=3> $SYSMSG{'autoadd_to'} <input type=text name=class_num2 size=3> $SYSMSG{'autoadd_class'}\n";
	}
	print "<tr><th align=right><font color=purple>$SYSMSG{'autoadd_level_4'}</font>\n";
	print "<td>$SYSMSG{'autoadd_from'} <input type=text name=num1 size=3> $SYSMSG{'autoadd_to'} <input type=text name=num2 size=3> $SYSMSG{'autoadd_num'}</font>\n";
	print "<tr><th align=right><font color=blue>$SYSMSG{'autoadd_addzero'}</font>";
	print "<td><input type=checkbox name=addzero value=yes checked><tr><td colspan=2><hr size=1 color=6699cc></td>\n";
	print "<tr><td colspan=2>$SYSMSG{'autoadd_hint_2'}\n" if ($CONFIG{'nest'} eq 1);
	print "<tr><td colspan=2>$SYSMSG{'autoadd_hint_3'}\n" if ($CONFIG{'nest'} eq 2);
	print "<tr><td colspan=2>$SYSMSG{'autoadd_hint_4'}\n" if ($CONFIG{'nest'} eq 3);
	print "<tr><td><td><input type=button value=\" $SYSMSG{'autoadd_confirm'} \" onclick=javascript:check()>\n";
	print "</table>";
	print "</form></center>";
	&foot('');
} elsif ($DATA{'step'} eq 'doauto' && $admin eq '1') {
	&head($SYSMSG{'title_autoadd'});
	&autoadd($DATA{'grp'},$DATA{'pre_name'},$DATA{'num1'},$DATA{'num2'},$DATA{'addzero'},$DATA{'grade_num1'},$DATA{'grade_num2'},$DATA{'class_num1'},$DATA{'class_num2'});
	&make_passwd;
	if ($CONFIG{'passwd_form'} eq 'random') {
		print "<table border=6 style=font-size:11pt width=95%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
		print "<tr><th>$SYSMSG{'username'}<th>$SYSMSG{'password'}<th>$SYSMSG{'username'}<th>$SYSMSG{'password'}<th>$SYSMSG{'username'}<th>$SYSMSG{'password'}</tr>\n";
		my $i = 0;
		foreach $uid (sort keys %sreqn) {
			print "<tr>" if (($i % 3) eq 0);
			$i ++;
			print "<td>$sreqn{$uid}<td>$sreqp{$uid}\n";
		}
	}
	print "</table>";
	&foot('');
} elsif ($DATA{'step'} eq 'resetpw' && $admin eq '1') {
	&head($SYSMSG{'title_resetpw'});
	print "<script>\n function check() { if (chk_empty(thisform.user) && chk_empty(thisform.grp) && chk_empty(thisform.word)) { alert('$SYSMSG{'reset_passwd_select_not_yet'}'); } else { thisform.submit(); } }\n</script>\n";
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=step value=checkreset>\n";
	print "<table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
	print "<tr><th align=right>$SYSMSG{'username'}\n";
	print "<td><select size=1 name=user onchange=rest(0)>\n";
	print "<option value=></option>\n";
	print "<option value=999>$SYSMSG{'everyone'}</option>\n";
	foreach $usr (sort keys %UNAME) {
		$uid = $UNMID{$usr};
		next if (int($uid)<500);
		next if (&check_special($usr) eq 1);
		print "<option value=$usr>$usr</option>\n";
	}
	print "</select>\n";
	print "<tr><th align=right><font color=darkblue>$SYSMSG{'groupname'}<br>$SYSMSG{'group_hint'}</font>\n";
	print "<td><select size=1 name=grp onchange=rest(1)>\n";
	print "<option value=></option>\n";
	foreach $grp (sort keys %GNAME) {
		$gid = $GNMID{$grp};
		next if (int($gid)<500);
		next if (&check_special($grp) eq 1);
		print "<option value=$grp>$grp</option>\n";
	}
	print "</select>\n";
	print "<tr><th align=right><font color=darkgreen>$SYSMSG{'pattern_search'}</font>\n";
	print "<td><input type=text name=word onchange=rest(2)>\n";
	print "<tr><th align=right><font color=red>$SYSMSG{'reset_passwd_setto'}</font>\n";
	print "<td><select size=1 name=passwd_form>";
	if ($CONFIG{'passwd_form'} eq 'username') {
		print "<option value=username selected>$SYSMSG{'config_account_auto_passwd_style_username'}</option>\n";
	} else {
		print "<option value=username>$SYSMSG{'config_account_auto_passwd_style_username'}</option>\n";
	}
	if ($CONFIG{'passwd_form'} eq 'random') {
		print "<option value=random selected>$SYSMSG{'config_account_auto_passwd_style_random'}</option>\n";
	} else {
		print "<option value=random>$SYSMSG{'config_account_auto_passwd_style_random'}</option>\n";
	}
	if ($CONFIG{'passwd_form'} eq 'single') {
		print "<option value=single selected>$SYSMSG{'config_account_auto_passwd_style_single'}</option>\n";
	} else {
		print "<option value=single>$SYSMSG{'config_account_auto_passwd_style_single'}</option>\n";
	}
	print "</select>\n";
	print "<tr><td><td><input type=button value=\" $SYSMSG{'reset_passwd_confirm'} \" onclick=javascript:check()>\n";
	print "</table>";
	print "</form></center>";
	&foot('');
} elsif ($DATA{'step'} eq 'checkreset' && $admin eq '1') {
	&head($SYSMSG{'title_resetpw'});
	if ($DATA{'user'} ne '') {
		&reset_pw($DATA{'user'},'','',$DATA{'passwd_form'});
		&write_shadow;
		print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'reset_passwd_completed'}</font>\n";
		if ($DATA{'passwd_form'} eq 'random') {
			print "<hr>$SYSMSG{'reset_passwd_list'}\n";
			print "<table border=6 style=font-size:11pt width=95%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
			print "<tr><th>$SYSMSG{'username'}<th>$SYSMSG{'password'}</tr>\n";
			foreach $usr (@CHGPW) {
				print "<tr><td>$usr<td>$UPASS{$usr}</tr>\n";
			}
		}
		print '</table>';
	} elsif ($DATA{'grp'} ne '') {
		print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'reset_passwd_grp_question'} $DATA{'grp'}</font>\n";
		print "<p>$SYSMSG{'reset_passwd_reset_these'}</p>\n";
		print "<hr><form method=post>\n";
		print "<input type=hidden name=step value=doreset>\n";
		print "<input type=hidden name=grp value=$DATA{'grp'}>\n";
		print "<input type=hidden name=passwd_form value=$DATA{'passwd_form'}>\n";
		print "<table border=6 style=font-size:11pt width=95%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
		print "<tr><td colspan=5 align=center bgcolor=#6699cc><b><font color=white><b>$SYSMSG{'group_member'}<b>\n";
		my $i = 0;
		$mygrp = $GNMID{$DATA{'grp'}};
		foreach $uid (sort keys %UIDS) {
			next if ($UGID{$uid} ne $mygrp);
			print "<tr>" if (($i % 5) eq 0);
			$i ++;
			print "<td>$UIDNM{$uid}</td>\n";
		}
		print "<tr><td colspan=5 ><center><input type=submit value=\" $SYSMSG{'reset_passwd_confirm'} \"></center></td></tr>\n";
		print "</table></form></center>";
	} else {
		print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'reset_passwd_search_question'} $DATA{'word'}</font>\n";
		print "<p>$SYSMSG{'reset_passwd_reset_these'}</p>\n";
		print "<hr><form method=post>\n";
		print "<input type=hidden name=step value=doreset>\n";
		print "<input type=hidden name=word value=$DATA{'word'}>\n";
		print "<input type=hidden name=passwd_form value=$DATA{'passwd_form'}>\n";
		print "<table border=6 style=font-size:11pt width=95%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
		print "<tr><td colspan=5 align=center bgcolor=#6699cc><b><font color=white><b>$SYSMSG{'user_search_result'}<b>\n";
		my $i = 0;
		foreach $usr (sort keys %UNAME) {
			next if ($usr !~ /$DATA{'word'}/);
			print "<tr>" if (($i % 5) eq 0);
			$i ++;
			print "<td>$usr</td>\n";
		}
		print "<tr><td colspan=5 ><center><input type=submit value=\" $SYSMSG{'reset_passwd_confirm'} \"></center></td></tr>\n";
		print "</table></form></center>";
	}
	&foot('');
} elsif ($DATA{'step'} eq 'doreset' && $admin eq '1') {
	&head($SYSMSG{'title_resetpw'});
	&reset_pw($DATA{'user'},$DATA{'grp'},$DATA{'word'},$DATA{'passwd_form'});
	&write_shadow;
	print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'reset_passwd_completed'}</font>\n";
	if ($DATA{'passwd_form'} eq 'random') {
		print "<hr>$SYSMSG{'reset_passwd_list'}\n";
		print "<table border=6 style=font-size:11pt width=95%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
		print "<tr><th>$SYSMSG{'username'}<th>$SYSMSG{'password'}<th>$SYSMSG{'username'}<th>$SYSMSG{'password'}<th>$SYSMSG{'username'}<th>$SYSMSG{'password'}</tr>\n";
		my $i = 0;
		foreach $usr (sort @CHGPW) {
			print "<tr>" if (($i % 3) eq 0);
			$i ++;
			print "<td>$usr<td>$UPASS{$usr}\n";
		}
	}
	print '</table>';
	&foot('');
} elsif ($DATA{'step'} eq 'chgpw' && $menu_id ne '') {
	&head($SYSMSG{'title_chgpw'});
	print "<script>\n";
	print "function chk_diff(p1,p2) { return (!(p1==p2) ) ;}";
	print "function chk_len(p1) { return (!(p1.value.length>=4 && p1.value.length<=8) ) ;}";
	print "function badpasswd(p1) {\n";
	print 'var Ap = "ABCDEFGHIJKLMNOPQRSTUVWXYZ" ; var ch = "abcdefghijklmnopqrstuvwxyz" ; var Num = "0123456789" ; var pps = "!@#$%^&*()_+|=\{}[]" ;'."\n";
	print "var c1=c2=c3=c4 = 0 ;\n";
	print "for (i=0;i<p1.length;i++) { if (Ap.indexOf(p1.substr(i,1))!=-1) { c1= 1 }\n";
	print "if (ch.indexOf(p1.substr(i,1))!=-1) { c2= 1 } ; if (Num.indexOf(p1.substr(i,1))!=-1) { c3= 1 } \n";
	print "if (pps.indexOf(p1.substr(i,1))!=-1) { c4= 1 } } return ((c1+c2+c3+c4)<2) ; } \n";
	print 'function badpasswd2(p1) { var Ap = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()QWERTYUIOPASDFGHJKLZXCVBNMZYXWVUTSRQPONMLKJIHGFEDCBA0987654321|+_)(*&^%$#@!POIUYTREWQLKJHGFDSAMNBVCXZ" ;  var chmode =oldChMode=  0 , mstr="" ;'."\n";
	print "p1 = p1.toUpperCase() ;\n";
	print "for(i=0 ; i<p1.length ; i++) { if (p1.length>=i+3) { mstr = p1.substr(i,3) ;\n";
	print "if (Ap.indexOf(mstr)!=-1) return(true ) ; }  }  }\n";
	print "function Mrepeat(p1) { var maxch=ch= 0,maxcan=2;\n";
	print "for (i=0;i<p1.length;i++) { ch = 1 ; \n";
	print "for (j=i+1;j<p1.length;j++) {\n";
	print "if (p1.substr(i,1)==p1.substr(j,1)) { ch++ } }\n";
	print "if (maxch < ch) maxch = ch ; }\n";
	print "if (p1.length > 6) maxcan =3; return (maxch > maxcan) ; }\n";
	print "function check() { var errors='' ;\n";
	print "if (chk_empty(thisform.pwd) || chk_empty(thisform.pwd2))  {  errors = '$SYSMSG{'err_blank_input'}' ; } \n";
	print "else { if (chk_diff(thisform.pwd.value,thisform.pwd2.value)) { errors = '$SYSMSG{'change_passwd_check_diffrent'}' ; }\n";
	print "else if (chk_len(thisform.pwd)) {errors = '$SYSMSG{'change_passwd_check_length'}' ;}\n" if (int($CONFIG{'passwd_rule'})%2);
	print "else if (badpasswd(thisform.pwd.value)) { errors = '$SYSMSG{'change_passwd_check_kind'}' ; }\n" if (int($CONFIG{'passwd_rule'})%4 >= 2);
	print "else if (Mrepeat(thisform.pwd.value)) { errors = '$SYSMSG{'change_passwd_check_repeat'}' ;}\n" if (int($CONFIG{'passwd_rule'})%8 >= 4);
	print "else if (badpasswd2(thisform.pwd.value)) { errors = '$SYSMSG{'change_passwd_check_arrange'}' ;}\n" if (int($CONFIG{'passwd_rule'}) >= 8);
	print "}\n";
	print "if (errors=='') { thisform.submit(); } else { alert(errors) ; rest(3);} }\n";
	print "</script>\n";
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=step value=dochgpw>\n";
	print "<table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
	print "<tr><th align=right>$SYSMSG{'change_passwd_new'}<img align=absmiddle  src=/img/chgpw.gif>\n";
	print "<td><input type=password name=pwd maxlength=12 size=16>\n";
	print "<tr><th align=right><font color=red>$SYSMSG{'change_passwd_again'}<img align=absmiddle  src=/img/mdb.gif></font>\n";
	print "<td><input type=password name=pwd2 maxlength=12 size=16>\n";
	print "<tr><td><td><input type=button value=\" $SYSMSG{'change_passwd_confirm'} \" onclick=javascript:check()>\n";
	print "</table>";
	print "<table border=6	height=112 style=font-size:11pt width=65%   cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
	print "<tr><td	align=center bgcolor=#6699cc><b><font color=white><b> $SYSMSG{'change_passwd_minihelp'}<td></tr>\n";
	print "<tr><td><p><ol><font color=darkblue>";
	print "<li>$SYSMSG{'change_passwd_rule_1'}</li>\n";
	print "<li>$SYSMSG{'change_passwd_rule_2'}</li>\n" if (int($CONFIG{'passwd_rule'})%2);
	print "<li>$SYSMSG{'change_passwd_rule_3'}</li>\n" if (int($CONFIG{'passwd_rule'})%4 >= 2);
	print "<li>$SYSMSG{'change_passwd_rule_4'}</li>\n" if (int($CONFIG{'passwd_rule'})%8 >= 4);
	print "<li>$SYSMSG{'change_passwd_rule_5'}</li>" if (int($CONFIG{'passwd_rule'}) >= 8);
	print "</font></ol></td></tr></table>\n";
	print "</form></center>";
	&foot('');
} elsif ($DATA{'step'} eq 'dochgpw' && $menu_id ne '') {
	&chg_passwd($DATA{'pwd'},$DATA{'pwd2'});
	&write_shadow;
	print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'change_passwd_completed'}</font></center>";
	&foot('');
} elsif ($DATA{'step'} eq 'delete' && $admin eq '1') {
	&head($SYSMSG{'title_delacc'});
	print "<script>\n function check() { if (chk_empty(thisform.user) && chk_empty(thisform.grp) && chk_empty(thisform.word)) { alert('$SYSMSG{'del_user_select_not_yet'}'); } else { thisform.submit(); } }\n</script>\n";
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=step value=checkdel>\n";
	print "<hr color=336699 size=1><table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
	print "<tr><th align=right>$SYSMSG{'username'}\n";
	print "<td><select size=1 name=user onchange=rest(0)>\n";
	print "<option value=></option>\n";
	print "<option value=999>$SYSMSG{'everyone'}</option>\n";
	foreach $usr (sort keys %UNAME) {
		$uid = $UNMID{$usr};
		next if (int($uid)<500);
		next if (&check_special($usr) eq 1);
		print "<option value=$usr>$usr</option>\n";
	}
	print "</select>\n";
	print "<tr><th align=right>$SYSMSG{'groupname'}<br>$SYSMSG{'group_hint'}\n";
	print "<td><select size=1 name=grp onchange=rest(1)>\n";
	print "<option value=></option>\n";
	foreach $grp (sort keys %GNAME) {
		$gid = $GNMID{$grp};
		next if (int($gid)<500);
		next if (&check_special($grp) eq 1);
		print "<option value=$grp>$grp</option>\n";
	}
	print "</select>\n";
	print "<tr><th align=right><font color=red face=$SYSMSG{'variable_font'} size=4>$SYSMSG{'pattern_search'}</font>\n";
	print "<td ><input type=text name=word onchange=rest(2)>\n";
	print "<tr><td align=right><input type=button value=\" $SYSMSG{'del_user_confirm'} \" onclick=javascript:check()><td>　　<a href=javascript:history.go(-1)>$SYSMSG{'del_user_cancel'}</a>\n";
	print "</table></form></center>";
	&foot('');
} elsif ($DATA{'step'} eq 'checkdel' && $admin eq '1') {
	&head($SYSMSG{'title_delacc'});
	if ($DATA{'user'} ne '') {
		&delete_pw($DATA{'user'},'','');
		&write_passwd;
		&write_shadow;
		print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'del_user_completed'}</font></center>\n";
	} elsif ($DATA{'grp'} ne '') {
		print "<center><h2>$SYSMSG{'del_user_grp_question'} $DATA{'grp'}</h2>\n";
		print "<p>$SYSMSG{'del_user_del_these'}</p>\n";
		print "<hr><form method=post>\n";
		print "<input type=hidden name=step value=dodelete>\n";
		print "<input type=hidden name=grp value=$DATA{'grp'}>\n";
		print "<table border=6 style=font-size:11pt width=95%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
		print "<tr><td colspan=5 align=center><b>$SYSMSG{'group_member'}<b>\n";
		my $i = 0;
		$mygrp = $GNMID{$DATA{'grp'}};
		foreach $uid (sort keys %UIDS) {
			next if ($UGID{$uid} ne $mygrp);
			print "<tr>" if (($i % 5) eq 0);
			$i ++;
			print "<td>$UIDNM{$uid}</td>\n";
		}
		print "<tr><td colspan=5 ><center><input type=submit value=\" $SYSMSG{'del_user_confirm'} \"> 　　<a href=javascript:history.go(-1)>$SYSMSG{'del_user_cancel'}</a></center></td></tr>\n";
		print "</table></form></center>";
	} else {
		print "<center><font color=red face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'del_user_search_question'} $DATA{'word'}</font>\n";
		print "<p><font color=blue face=$SYSMSG{'variable_font'} size=4><b>$SYSMSG{'del_user_del_these'}</b></font></p>\n";
		print "<form method=post>\n";
		print "<input type=hidden name=step value=dodelete>\n";
		print "<input type=hidden name=word value=$DATA{'word'}>\n";
		print "<table border=6 style=font-size:11pt width=95%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
		print "<tr><td colspan=5 align=center bgcolor=#6699cc><b><font color=white>$SYSMSG{'user_search_result'}<b></font>\n";
		my $i = 0;
		foreach $usr (sort keys %UNAME) {
			next if ($usr !~ /$DATA{'word'}/);
			print "<tr>" if (($i % 5) eq 0);
			$i ++;
			print "<td>$usr</td>\n";
		}
		print "<tr><td colspan=5 align=center bgcolor=#6699cc><b><font color=white><b>$SYSMSG{'group_search_result'}<b></font>\n";
		my $i = 0;
		foreach $grp (sort keys %GNAME) {
			next if ($grp !~ /$DATA{'word'}/);
			print "<tr>" if (($i % 5) eq 0);
			$i ++;
			print "<td>$grp</td>\n";
		}
		print "<tr><td colspan=5 ><center><input type=submit value=\" $SYSMSG{'del_user_confirm'} \">　　<a href=javascript:history.go(-1)>$SYSMSG{'del_user_cancel'}</a></center></td></tr>\n";
		print "</table></form></center>";
	}
	&foot('');
} elsif ($DATA{'step'} eq 'dodelete' && $admin eq '1') {
	&head($SYSMSG{'title_delacc'});
	&delete_pw($DATA{'user'},$DATA{'grp'},$DATA{'word'});
	&write_passwd;
	&write_shadow;
	print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'del_user_cmpleted'}</font></center>\n";
	&foot('');
} elsif ($DATA{'step'} eq 'check' && $menu_id ne '') {
	&head($SYSMSG{'title_checkacc'});
	print "<center><table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
	print "<tr><td align=center><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'check_account_group'}</font></h2>\n";
	print "<tr><td><pre>";
	print "\n";
	system("grpck");
	print @_;
	print "</pre><tr><td align=center><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'check_account_username'}</font>\n";
	print "<tr><td><pre>";
	system("pwck");
	print @_;
	print "</pre>";
	print "</table></center>\n";
	&foot('');
} elsif ($DATA{'step'} eq 'struct' && $admin eq '1') {
	&head($SYSMSG{'title_viewstruct'});
	print "<center><form method=post>\n";
	print "<input type=hidden name=step value=struct>\n";
	print "<table border=6 style=font-size:11pt width=65%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
	print "<tr><th align=right>$SYSMSG{'groupname'}<br>$SYSMSG{'group_hint'}\n";
	print "<td><select size=1 name=grp>\n";
	print "<option value=></option>\n";
	foreach $gname (sort keys %GNAME) {
		$gid = $GNMID{$gname};
		next if (int($gid)<500);
		next if (&check_special($gname) eq 1);
		next if ($GCONF{$gname} eq '');
		print "<option value=$gname>$gname</option>\n";
	}
	print "</select>\n";
	print "<tr><td align=center colspan=2><input type=submit value=\" $SYSMSG{'confirm'} \"></td></tr>\n";
	print "</table>";
	if ($DATA{'grp'} ne '') {
		print "<center><table border=0 cellpadding=1 cellspacing=1 style=font-size:11pt>\n";
		print "<tr><td><pre>";
		print `tree -d $GCONF{$DATA{'grp'}}`;
		print "</pre>";
		print "</table></center>\n";
	}
	&foot('');
} elsif ($DATA{'step'} eq 'trace' && $admin eq '1') {
	&head($SYSMSG{'title_trace'});
	print "<center><form method=post>\n";
	print "<input type=hidden name=step value=trace>\n";
	print "<table border=6 style=font-size:11pt width=65%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
	print "<tr><th align=right>$SYSMSG{'username'}\n";
	print "<td><select size=1 name=user>\n";
	print "<option value=></option>\n";
	foreach $uname (sort keys %UNAME) {
		$uid = $UNMID{$uname};
		next if (int($uid)<500);
		next if (&check_special($uname) eq 1);
		print "<option value=$uname>$uname</option>\n";
	}
	print "</select>\n";
	print "<tr><td align=center colspan=2><input type=submit value=\" $SYSMSG{'confirm'} \">\n";
	print "</table><hr>";
	if ($DATA{'user'} ne '') {
		$uid = $UNMID{$DATA{'user'}};
		if (-e "$HOME{$uid}/.bash_history") {
			open (HIS, "< $HOME{$uid}/.bash_history") || &err_disk("$SYSMSG{'err_cannot_open_history'}<br>");
			@line = <HIS>;
			close(HIS);
		} elsif (-e "$HOME{$uid}/.history") {
			open (HIS, "< $HOME{$uid}/.history") || &err_disk("$SYSMSG{'err_cannot_open_history'}<br>");
			@line = <HIS>;
			close(HIS);
		} else {
			@line = ("$SYSMSG{'trace_account_notfound'} $DATA{'user'}");
		}
		print "<center><table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
		print "<tr><td><pre>";
		print @line;
		print "</pre>";
		print "</table></center>\n";
	}
	&foot('');
} elsif ($DATA{'step'} eq 'edquota' && $admin eq '1') {
	&head($SYSMSG{'title_userquota'});
	print "<script>\n function check() { if (chk_empty(thisform.user) && chk_empty(thisform.grp) && chk_empty(thisform.word)) { alert('$SYSMSG{'quota_select_not_yet'}'); } else { thisform.submit(); } }\n</script>\n";
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=step value=chkquota>\n";

	print "<table border=6 style=font-size:11pt width=65%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
	print "<tr><th align=right>$SYSMSG{'username'}\n";
	print "<td><select size=1 name=user onchange=rest(0)>\n";
	print "<option value=></option>\n";
	print "<option value=999>$SYSMSG{'everyone'}</option>\n";
	foreach $usr (sort keys %UNAME) {
		$uid = $UNMID{$usr};
		next if (int($uid)<500);
		next if (&check_special($usr) eq 1);
		print "<option value=$usr>$usr</option>\n";
	}
	print "</select>\n";
	print "<tr><th align=right>$SYSMSG{'groupname'}<br>\n";
	print "<td><select size=1 name=grp onchange=rest(1)>\n";
	print "<option value=></option>\n";
	foreach $grp (sort keys %GNAME) {
		$gid = $GNMID{$grp};
		next if (int($gid)<500);
		next if (&check_special($grp) eq 1);
		print "<option value=$grp>$grp</option>\n";
	}
	print "</select>\n";
	print "<tr><th align=right><font color=red face=$SYSMSG{'variable_font'} size=4>$SYSMSG{'pattern_search'}</font>\n";
	print "<td ><input type=text name=word onchange=rest(2)>\n";
	print "<tr><td align=right><input type=button value=\" $SYSMSG{'confirm'} \" onclick=javascript:check()><td>　　<a href=javascript:history.go(-1)>$SYSMSG{'cancel'}</a>\n";
	print "</table></form></center>";
	&foot('');
} elsif ($DATA{'step'} eq 'chkquota' && $admin eq '1') {
	&head($SYSMSG{'title_userquota'});
	if ($DATA{'user'} ne '') {
		print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5>$DATA{'user'} $SYSMSG{'quota_status'}</font></center>\n";
		print "<hr><center><form method=post>\n";
		print "<input type=hidden name=step value=doquota>\n";
		print "<input type=hidden name=user value=$DATA{'user'}>\n";
		print "<table border=6 style=font-size:11pt width=95%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
		print "<tr><td align=center><b>$SYSMSG{'dir'}<td align=center><b>$SYSMSG{'partition'}<td align=center><b>$SYSMSG{'used'}<td align=center><b>$SYSMSG{'quota_hard_limit'}<td align=center><b>$SYSMSG{'quota_soft_limit'}\n";
		&user_quota($UNMID{$DATA{'user'}});
		foreach $f (sort keys %filesys) {
			$dev = $filesys{$f};
			print "<input type=hidden name=device value=$dev>\n";
			print "<tr><td>$f<td>$dev<td>$usrquota{$dev,'ublocks'}<td><input type=text name=\"".$dev."_hb\" value=$usrquota{$dev,'hblocks'}><td><input type=text name=\"".$dev."_sb\" value=$usrquota{$dev,'sblocks'}>\n";
		}
		print "<tr><td colspan=5 align=center><input type=submit value=\"  $SYSMSG{'quota_confirm'}  \">\n";
		print "</table></form></center>\n";
	} elsif ($DATA{'grp'} ne '') {
		print "<p align=center><font face=$SYSMSG{'variable_font'}><a href=$cgi_url?step=listquota&grp=$DATA{'grp'}>$SYSMSG{'quota_group_member_checkout'}</a></font></p>\n";
		print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5>$DATA{'user'} $SYSMSG{'quota_group_change'}</font></center>\n";
		print "<hr><center><form method=post>\n";
		print "<input type=hidden name=step value=doquota>\n";
		print "<input type=hidden name=grp value=$DATA{'grp'}>\n";
		print "<table border=6 style=font-size:11pt width=95%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
		print "<tr><td align=center><b>$SYSMSG{'dir'}<td align=center><b>$SYSMSG{'partition'}<td align=center><b>$SYSMSG{'quota_hard_limit'}<td align=center><b>$SYSMSG{'quota_soft_limit'}\n";
		foreach $dev (sort keys %DEVFS) {
			$f = $DEVFS{$dev};
			print "<input type=hidden name=device value=$dev>\n";
			print "<tr><td>$f<td>$dev<td><input type=text name=\"".$dev."_hb\" value=><td><input type=text name=\"".$dev."_sb\" value=>\n";
		}
		print "<tr><td colspan=4 align=center><input type=submit value=\"  $SYSMSG{'quota_confirm'}  \">\n";
		print "</table></form></center>\n";
	} else {
		print "<p align=center><font face=$SYSMSG{'variable_font'}><a href=$cgi_url?step=listquota&word=$DATA{'word'}>$SYSMSG{'quota_search_result_checkout'}</a></font></p>\n";
		print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'quota_user_change'}</font></center>\n";
		print "<hr><center><form method=post>\n";
		print "<input type=hidden name=step value=doquota>\n";
		print "<input type=hidden name=word value=$DATA{'word'}>\n";
		print "<table border=6 style=font-size:11pt width=95%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
		print "<tr><td align=center><b>$SYSMSG{'dir'}<td align=center><b>$SYSMSG{'partition'}<td align=center><b>$SYSMSG{'quota_hard_limit'}<td align=center><b>$SYSMSG{'quota_soft_limit'}\n";
		foreach $dev (sort keys %DEVFS) {
			$f = $DEVFS{$dev};
			print "<input type=hidden name=device value=$dev>\n";
			print "<tr><td>$f<td>$dev<td><input type=text name=\"".$dev."_hb\" value=><td><input type=text name=\"".$dev."_sb\" value=>\n";
		}
		print "<tr><td colspan=4 align=center><input type=submit value=\"  $SYSMSG{'confirm'}  \">\n";
		print "</table></form></center>\n";
	}
	&foot('');
} elsif ($DATA{'step'} eq 'listquota' && $admin eq '1') {
	&head($SYSMSG{'title_viewquota'});
	if ($DATA{'grp'} ne '') {
		print "<center><h2>$DATA{'grp'}$SYSMSG{'quota_group_member_list'}</h2>\n";
		print "<p>$SYSMSG{'quota_set_these'}</p>\n";
		print "<table border=6 style=font-size:11pt width=95%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
		print "<tr><td align=center><b>$SYSMSG{'user'}<td align=center><b>$SYSMSG{'dir'}<td align=center><b>$SYSMSG{'partition'}<td align=center><b>$SYSMSG{'used'}<td align=center><b>$SYSMSG{'quota_hard_limit'}<td align=center><b>$SYSMSG{'quota_soft_limit'}\n";
		my $mini = 0;
		my $maxi = 0;
		my $number_count = 0;
		my $nextpage = 0;
		my $mygrp = $GNMID{$DATA{'grp'}};
		@show_quota = ();
		foreach $uid (sort keys %UIDS) {
			next if ($UGID{$uid} ne $mygrp);
			$usr = $UIDNM{$uid};
			push(@show_quota,$usr);
			$maxi ++;
		}
		$number_count = $maxi;
		$DATA{'page'} = 1 if (!$DATA{'page'});
		my $prevpage = int($DATA{'page'})-1;
		$mini = $prevpage * 20;
		if ($maxi>int($DATA{'page'})*20) {
			$maxi = int($DATA{'page'})*20;
			$nextpage = int($DATA{'page'})+1;
		}
		for ($i=$mini;$i<$maxi;$i++) {
			$usr = $show_quota[$i];
			&user_quota($UNMID{$usr});
			foreach $f (sort keys %filesys) {
				$dev = $filesys{$f};
				print "<tr><td>$usr<td>$f<td>$dev<td>$usrquota{$dev,'ublocks'}<td>$usrquota{$dev,'hblocks'}<td>$usrquota{$dev,'sblocks'}\n";
			}
		}
		print "</table>\n";
		print "　<a href=$cgi_url?step=listquota&grp=$DATA{'grp'}&page=$prevpage>$SYSMSG{'prev_page'}</a>　" if ($prevpage>0);
		my $page_count = ($number_count % 20)>0 ? int($number_count/20)+1 : int($number_count/20);
		print "$SYSMSG{'page_no'} $DATA{'page'}／$page_count $SYSMSG{'total'} $number_count $SYSMSG{'records'}";
		print "　<a href=$cgi_url?step=listquota&grp=$DATA{'grp'}&page=$nextpage>$SYSMSG{'next_page'}</a>　" if ($nextpage>0);
		print "</center>\n";
	} else {
		print "<center><h2>$SYSMSG{'quota_search_result_list'}</h2>\n";
		print "<p>$SYSMSG{'quota_set_these'}</p>\n";
		print "<form method=post>\n";
		print "<input type=hidden name=step value=doquota>\n";
		print "<input type=hidden name=word value=$DATA{'word'}>\n";
		print "<table border=6 style=font-size:11pt width=95%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
		print "<tr><td align=center><b>$SYSMSG{'user'}<td align=center><b>$SYSMSG{'dir'}<td align=center><b>$SYSMSG{'partition'}<td align=center><b>$SYSMSG{'used'}<td align=center><b>$SYSMSG{'quota_hard_limit'}<td align=center><b>$SYSMSG{'quota_soft_limit'}\n";
		my $mini = 0;
		my $maxi = 0;
		my $nextpage = 0;
		@show_quota = ();
		foreach $usr (sort keys %UNAME) {
			next if ($usr !~ /$DATA{'word'}/);
			push(@show_quota,$usr);
			$maxi ++;
		}
		$DATA{'page'} = 1 if (!$DATA{'page'});
		my $prevpage = int($DATA{'page'})-1;
		$mini = $prevpage * 20;
		if ($maxi>int($DATA{'page'})*20) {
			$maxi = int($DATA{'page'})*20;
			$nextpage = int($DATA{'page'})+1;
		}
		for ($i=$mini;$i<$maxi;$i++) {
			$usr = $show_quota[$i];
			&user_quota($UNMID{$usr});
			foreach $f (sort keys %filesys) {
				$dev = $filesys{$f};
				print "<tr><td>$usr<td>$f<td>$dev<td>$usrquota{$dev,'ublocks'}<td>$usrquota{$dev,'hblocks'}<td>$usrquota{$dev,'sblocks'}\n";
			}
		}
		print "</table>\n";
		print "　<a href=$cgi_url?step=listquota&word=$DATA{'word'}&page=$prevpage>$SYSMSG{'prev_page'}</a>　" if ($prevpage>0);
		print "　<a href=$cgi_url?step=listquota&word=$DATA{'word'}&page=$nextpage>$SYSMSG{'next_page'}</a>　" if ($nextpage>0);
		print "</center>\n";
	}
	&foot('');
} elsif ($DATA{'step'} eq 'doquota' && $admin eq '1') {
	&head($SYSMSG{'title_userquota'});
	&edit_user_quota;
	print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'quota_completed'}</font></center>\n";
	&foot('');
} elsif ($DATA{'step'} eq 'filesmgr' && $menu_id ne '') {
	if ($admin ne '1') {
		$) = $menu_gid;
		$> = $menu_id;
	}
	$share_flag = 0;
	($musr,$pwd,$muid,$mgid,$quo,$com,$gcos,$home,$shell) = getpwuid($menu_id);
	my $ext = 'tar.gz';
	$ext = 'zip' if ($zip_exist);
	$DATA{'folder'} = &get_dir($DATA{'folder'});
	$DATA{'folder'} = &chg_dir($DATA{'folder'},$DATA{'chfolder'}) if ($DATA{'action'} eq 'chdir');
	&make_dir($DATA{'folder'},$DATA{'newfolder'}) if ($DATA{'action'} eq 'mkdir');
	&del_dir($DATA{'folder'},$DATA{'sel'}) if ($DATA{'action'} eq 'delete');
	&chg_perm($DATA{'newperm'},$DATA{'folder'},$DATA{'sel'}) if ($DATA{'action'} eq 'chmod');
	&chg_owner($DATA{'newowner'},$DATA{'folder'},$DATA{'sel'}) if ($DATA{'action'} eq 'chown');
	&ren_dir($DATA{'newname'},$DATA{'folder'},$DATA{'sel'}) if ($DATA{'action'} eq 'rename');
	&move_dir($DATA{'movefolder'},$DATA{'folder'},$DATA{'sel'}) if ($DATA{'action'} eq 'move');
	&copy_dir($DATA{'copypath'},$DATA{'folder'},$DATA{'sel'}) if ($DATA{'action'} eq 'copy');
	&show_file($DATA{'folder'},$DATA{'dnfile'}) if ($DATA{'action'} eq 'showfile');
	&many_download($DATA{'folder'},$DATA{'sel'}) if ($DATA{'action'} eq 'many_download');
	&share($DATA{'folder'},$DATA{'sel'}) if ($DATA{'action'} eq 'share');
	$DATA{'folder'} = &get_dir($DATA{'folder'});
	@free = &free_space($DATA{'folder'});
	my $used = int((substr($free[3],0,-1)) * 0.6);
	&head($SYSMSG{'title_filesmgr'});
	$tmpdnfile = time;
	print "<div align=center>";
	print "<table border=6 style=font-size:11pt width=95%  border-collapse: collapse  cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
	print "<tr><td colspan=9><img align=absmiddle src=/img/fm.gif>$SYSMSG{'sign_left'}<font color=red><b>$SYSMSG{'filemgr_current_dir'}</b></font><font color=blue><img align=absmiddle src=/img/0folder.gif> $DATA{'folder'} </font>$SYSMSG{'sign_right'} 　　 $SYSMSG{'sign_left'}<a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'share'}><img align=absmiddle src=/img/sharemgr.gif border=0>$SYSMSG{'filemgr_goto_sharemgr'}</a>$SYSMSG{'sign_right'}<br>\n";
	print "<tr><td colspan=9><center><font color=green>$SYSMSG{'filemgr_total_quota'}$free[0]　</font><font color=darkred>$SYSMSG{'filemgr_total_quota_used'}$free[1]　</font><font color=blue>$SYSMSG{'filemgr_total_quota_left'}$free[2]　</font><font color=red>$SYSMSG{'filemgr_total_quota_use'}<img align=absmiddle src=/img/used.jpg width=$used height=10><img align=absmiddle src=/img/unused.jpg width=".int(60-$used)." height=10>$free[3]</font></center></td></tr>\n";
	print "<tr bgcolor=#ffffff><td><a href=javascript:sfile()><img align=absmiddle src=/img/allfile.gif border=0></a>\n";
	if ($DATA{'sort'} eq 'name' || $DATA{'sort'} eq '') {
		print "<td align=center bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=name_rev><font color=white><b>$SYSMSG{'filemgr_file_name'}</b></font></a>\n";
	} else {
		print "<td align=center bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=name><font color=white><b>$SYSMSG{'filemgr_file_name'}</b></font></a>\n";
	}
	if ($DATA{'sort'} eq 'type') {
		print "<td bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=type_rev><font color=white><b>$SYSMSG{'filemgr_file_type'}</b></font></a>\n";
	} else {
		print "<td bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=type><font color=white><b>$SYSMSG{'filemgr_file_type'}</b></font></a>\n";
	}
	if ($DATA{'sort'} eq 'perm') {
		print "<td bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=perm_rev><font color=white><b>$SYSMSG{'filemgr_file_priv'}</b></font></a>\n";
	} else {
		print "<td bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=perm><font color=white><b>$SYSMSG{'filemgr_file_priv'}</b></font></a>\n";
	}
	if ($DATA{'sort'} eq 'owner') {
		print "<td bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=owner_rev><font color=white><b>$SYSMSG{'filemgr_file_owner'}</b></font></a>\n";
	} else {
		print "<td bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=owner><font color=white><b>$SYSMSG{'filemgr_file_owner'}</b></font></a>\n";
	}
	if ($DATA{'sort'} eq 'gowner') {
		print "<td bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=gowner_rev><font color=white><b>$SYSMSG{'filemgr_file_owner_group'}</b></font></a>\n";
	} else {
		print "<td bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=gowner><font color=white><b>$SYSMSG{'filemgr_file_owner_group'}</b></font></a>\n";
	}
	if ($DATA{'sort'} eq 'size') {
		print "<td align=right bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=size_rev><font color=white><b>$SYSMSG{'filemgr_file_size'}</b></font></a>\n";
	} else {
		print "<td align=right bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=size><font color=white><b>$SYSMSG{'filemgr_file_size'}</b></font></a>\n";
	}
	if ($DATA{'sort'} eq 'time') {
		print "<td align=center bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=time_rev><font color=white><b>$SYSMSG{'filemgr_file_date'}</b></font></a>\n";
	} else {
		print "<td align=center bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=time><font color=white><b>$SYSMSG{'filemgr_file_date'}</b></font></a>\n";
	}
	print "<td align=center bgcolor=#6699cc><font color=white>$SYSMSG{'filemgr_pannel'}</font></tr>\n";
	print "<tr><td bgcolor=#ffffff><a href=javascript:snone()><img align=absmiddle src=/img/allnot.gif border=0></a><td><a href=$cgi_url?step=filesmgr&action=chdir&folder=$DATA{'folder'}&chfolder=/><img align=absmiddle src=/img/home.gif border=0> 《$SYSMSG{'filemgr_gohome'}》</a>";
	print "<td align=center colspan=6>";
	print "<form method=POST><input type=hidden name=step value=fupload><input type=hidden name=title value=\"$SYSMSG{'upload_file'}\"><input type=hidden name=act value=f><input type=hidden name=folder value=$DATA{'folder'}>\n";
	print "<img align=absmiddle src=/img/upload.gif>$SYSMSG{'upload'}<input type=text name=filemany size=4 value=5>$SYSMSG{'files'}\n";
	print "<input type=submit value=\"$SYSMSG{'upload'}\"></form>";
	print "<form name=myform method=POST action=$cgi_url$DATA{'folder'}/$tmpdnfile.$ext>";
	print "<input type=hidden name=step value=filesmgr>\n";
	print "<input type=hidden name=action value=>\n";
	print "<input type=hidden name=folder value=$DATA{'folder'}>\n";
	print "<td bgcolor=#6699cc rowspan=20><p><font color=white>$SYSMSG{'filemgr_pannel_minihelp'}</p>";
	print "<p><a href=javascript:onclick=alert('$SYSMSG{'filemgr_pannel_hint_1'}') border=0><img align=absmiddle src=/img/newfd.gif border=0></a><input type=text name=chfolder size=12><input type=button value=\"$SYSMSG{'filemgr_pannel_chdir'}\" onclick=check0()></p>\n";
	print "<p><a href=javascript:onclick=alert('$SYSMSG{'filemgr_pannel_hint_2'}') border=0><img align=absmiddle src=/img/newfd.gif border=0></a><input type=text name=newfolder size=12><input type=button value=\"$SYSMSG{'filemgr_pannel_mkdir'}\" onclick=check1()></p>\n";
	print "<p><a href=javascript:onclick=alert('$SYSMSG{'filemgr_pannel_hint_3'}') border=0><img align=absmiddle src=/img/chmod.gif border=0></a><input type=text name=newperm size=4><input type=button value=\"$SYSMSG{'filemgr_pannel_chmod'}\" onclick=check2()></p>\n";
	print "<p><a href=javascript:onclick=alert('$SYSMSG{'filemgr_pannel_hint_4'}') border=0><img align=absmiddle src=/img/chown.gif border=0></a><input type=text name=newowner size=10><input type=button value=\"$SYSMSG{'filemgr_pannel_chown'}\" onclick=check3()></p>\n";
	print "<p><a href=javascript:onclick=alert('$SYSMSG{'filemgr_pannel_hint_5'}') border=0><img align=absmiddle src=/img/rename.gif border=0></a><input type=text name=newname size=16><input type=button value=\"$SYSMSG{'filemgr_pannel_rename'}\" onclick=check4()></p>\n";
	print "<p><a href=javascript:onclick=alert('$SYSMSG{'filemgr_pannel_hint_6'}') border=0><img align=absmiddle src=/img/mv.gif border=0></a><input type=text name=movefolder size=16><input type=button value=\"$SYSMSG{'filemgr_pannel_move'}\" onclick=check5()></p>\n";
	print "<p><a href=javascript:onclick=alert('$SYSMSG{'filemgr_pannel_hint_7'}') border=0><img align=absmiddle src=/img/copy.gif border=0></a><input type=text name=copypath size=16><input type=button value=\"$SYSMSG{'filemgr_pannel_copy'}\" onclick=check6()></p>\n";
	print "<p><a href=javascript:onclick=alert('$SYSMSG{'filemgr_pannel_hint_8'}') border=0><img align=absmiddle src=/img/del.gif border=0></a><input type=button value=\"$SYSMSG{'filemgr_pannel_delete'}\" onclick=check7()></p>\n";
	print "<p><a href=javascript:onclick=alert('$SYSMSG{'filemgr_pannel_hint_9'}') border=0><img align=absmiddle src=/img/fd.gif border=0></a><input type=button value=\"$SYSMSG{'filemgr_pannel_download'}\" onclick=check8()></p>\n";
	print "<p><a href=javascript:onclick=alert('$SYSMSG{'filemgr_pannel_hint_10'}') border=0><img align=absmiddle src=/img/fd.gif border=0></a><input type=button value=\"$SYSMSG{'filemgr_pannel_share'}\" onclick=check9()></p>\n" if ($admin eq '1');
	if ( $DATA{'sort'} eq 'name' || $DATA{'sort'} eq '') {
	      @myfolds = sort keys %FOLDS;
	      @myfiles = sort keys %FILES;
	} elsif ( $DATA{'sort'} eq 'name_rev' ) {
	      @myfolds = reverse(sort keys %FOLDS);
	      @myfiles = reverse(sort keys %FILES);
	} elsif ( $DATA{'sort'} eq 'time') {
	      @myfolds = sort by_time keys %FOLDS;
	      @myfiles = sort by_time keys %FILES;
	} elsif ( $DATA{'sort'} eq 'time_rev' ) {
	      @myfolds = reverse(sort by_time keys %FOLDS);
	      @myfiles = reverse(sort by_time keys %FILES);
	} elsif ( $DATA{'sort'} eq 'type' ) {
	      @myfolds = sort by_time keys %FOLDS;
	      @myfiles = sort by_time keys %FILES;
	} elsif ( $DATA{'sort'} eq 'type_rev' ) {
	      @myfolds = reverse(sort by_time keys %FOLDS);
	      @myfiles = reverse(sort by_time keys %FILES);
	} elsif ( $DATA{'sort'} eq 'perm' ) {
	      @myfolds = sort by_perm keys %FOLDS;
	      @myfiles = sort by_perm keys %FILES;
	} elsif ( $DATA{'sort'} eq 'perm_rev') {
	      @myfolds = reverse(sort by_perm keys %FOLDS);
	      @myfiles = reverse(sort by_perm keys %FILES);
	} elsif ( $DATA{'sort'} eq 'owner' ) {
	      @myfolds = sort by_owner keys %FOLDS;
	      @myfiles = sort by_owner keys %FILES;
	} elsif ( $DATA{'sort'} eq 'owner_rev') {
	      @myfolds = reverse(sort by_owner keys %FOLDS);
	      @myfiles = reverse(sort by_owner keys %FILES);
	} elsif ( $DATA{'sort'} eq 'gowner' ) {
	      @myfolds = sort by_gowner keys %FOLDS;
	      @myfiles = sort by_gowner keys %FILES;
	} elsif ( $DATA{'sort'} eq 'gowner_rev') {
	      @myfolds = reverse(sort by_gowner keys %FOLDS);
	      @myfiles = reverse(sort by_gowner keys %FILES);
	} elsif ( $DATA{'sort'} eq 'size' ) {
	      @myfolds = sort by_size keys %FOLDS;
	      @myfiles = sort by_size keys %FILES;
	} elsif ( $DATA{'sort'} eq 'size_rev') {
	      @myfolds = reverse(sort by_size keys %FOLDS);
	      @myfiles = reverse(sort by_size keys %FILES);
	}
	print "<tr><td bgcolor=#ffeeee><a href=javascript:sall()><img align=absmiddle src=/img/all.gif border=0></a><td bgcolor=#ffffee><a href=$cgi_url?step=filesmgr&action=chdir&folder=$DATA{'folder'}&chfolder=..><img align=absmiddle src=/img/upfolder.gif border=0> $SYSMSG{'parrent'}</a>";
	print "<td bgcolor=#e8f3ff><font color=darkgreen>$TYPE{'..'}</font></td>";
	print "<td bgcolor=#e8f3ff><font color=blue>$PERM{'..'}</td>";
	$fusr = getpwuid($OWNER{'..'});
	$fgrp = getgrgid($GOWNER{'..'});
	print "<td bgcolor=#e8f3ff>$fusr</td>";
	print "<td bgcolor=#e8f3ff>$fgrp</td>";
	print "<td bgcolor=#e8f3ff align=right>$FSIZE{'..'}</td>";
	print "<td bgcolor=#e8f3ff align=right>$MODIFY{'..'}</td></tr>\n";
	$folder_cnt++;
	foreach $file (@myfolds) {
		$myfile = $file;
		if ($CONFIG{'codepage_smb'} eq 'yes') {
			$myfile =~ s/\:/\=/g;
			$myfile = &qpdecode($myfile);
		}
		next if ($file eq '.' || $file eq '..');
		print "<tr><td bgcolor=#ddeeff><input type=checkbox name=sel value=$file></td>";
		print "<td bgcolor=#e8f3ff><a href=$cgi_url?step=filesmgr&action=chdir&folder=$DATA{'folder'}&chfolder=$file><img align=absmiddle src=/img/$IMAGE{$file} border=0> $myfile</a></td>";
		print "<td bgcolor=#e8f3ff><font color=darkgreen>$TYPE{$file}</font></td>";
		print "<td bgcolor=#e8f3ff><font color=blue>$PERM{$file}</td>";
		$fusr = getpwuid($OWNER{$file});
		$fgrp = getgrgid($GOWNER{$file});
		print "<td bgcolor=#e8f3ff>$fusr</td>";
		print "<td bgcolor=#e8f3ff>$fgrp</td>";
		print "<td bgcolor=#e8f3ff align=right>$FSIZE{$file}</td>";
		print "<td bgcolor=#e8f3ff align=right>$MODIFY{$file}</td></tr>\n";
		$folder_cnt++;
	}
	foreach $file (@myfiles) {
		$myfile = $file;
		if ($CONFIG{'codepage_smb'} eq 'yes') {
			$myfile =~ s/\:/\=/g;
			$myfile = &qpdecode($myfile);
		}
		print "<tr><td bgcolor=#ddeeff><input type=checkbox name=sel value=$file></td>";
		print "<td bgcolor=#ffffff><a href=$cgi_url$DATA{'folder'}/$file?step=filesmgr&action=showfile&folder=$DATA{'folder'}&dnfile=$file><img align=absmiddle src=/img/$IMAGE{$file} border=0> $myfile</a></td>";
		print "<td bgcolor=#ffffff><font color=#cd0000>$TYPE{$file}</font></td>";
		print "<td bgcolor=#ffffff><font color=red>$PERM{$file}</td>";
		$fusr = getpwuid($OWNER{$file});
		$fgrp = getgrgid($GOWNER{$file});
		print "<td bgcolor=#ffffff>$fusr</td>";
		print "<td bgcolor=#ffffff>$fgrp</td>";
		print "<td bgcolor=#ffffff align=right>$FSIZE{$file}</td>";
		print "<td bgcolor=#ffffff align=right>$MODIFY{$file}</td></tr>\n";
	}
	print "<tr><td colspan=8><center>$SYSMSG{'err_file&dir_notfound'}</center></td></tr>\n" if ($filemgr_rows le 0);
	for (1..18 - $filemgr_rows) { print "<tr><td bgcolor=#6699cc colspan=8>　</td></tr>\n"; }
	print "<tr><td colspan=9><center><font color=green>$SYSMSG{'filemgr_total_quota'}$free[0]　</font><font color=darkred>$SYSMSG{'filemgr_total_quota_used'}$free[1]　</font><font color=blue>$SYSMSG{'filemgr_total_quota_left'}$free[2]　</font><font color=red>$SYSMSG{'filemgr_total_quota_use'}<img align=absmiddle src=/img/used.jpg width=$used height=10><img align=absmiddle src=/img/unused.jpg width=".int(60-$used)." height=10>$free[3]</font></center></td></tr>\n";
	print "</table></form></div><script>\n";
	print "function check() {\n";
	if ($filemgr_rows eq 1) {
		print "if (!thisform.sel.checked) { alert('$SYSMSG{'msg_file_select_not_yet'}'); return 0; } else { return 1; } }\n";
	} else {
		print "var flag = 0;\n";
		print "for (i=0;i<$filemgr_rows;i++) {\n";
		print "if (thisform.sel[i].checked) { flag = 1; } }\n";
		print "if (flag == 0) { alert('$SYSMSG{'msg_file_select_not_yet'}'); }\n";
		print "return flag; }\n";
	}
	print "function check0() { if (chk_empty(thisform.chfolder)) { alert('$SYSMSG{'msg_blank_folder'}'); } else { mysubmit('chdir'); } }\n";
	print "function check1() { if (chk_empty(thisform.newfolder)) { alert('$SYSMSG{'msg_blank_folder'}'); } else { mysubmit('mkdir'); } }\n";
	print "function check2() { var flag = check(); if (chk_empty(thisform.newperm)) { alert('$SYSMSG{'msg_blank_perm'}'); } else { if (flag) { mysubmit('chmod'); } } }\n";
	print "function check3() { var flag = check(); if (chk_empty(thisform.newowner)) { alert('$SYSMSG{'msg_blank_owner'}'); } else { if (flag) { mysubmit('chown'); } } }\n";
	print "function check4() { var flag = check(); if (chk_empty(thisform.newname)) { alert('$SYSMSG{'msg_blank_filename'}'); } else { if (flag) { mysubmit('rename'); } } }\n";
	print "function check5() { var flag = check(); if (chk_empty(thisform.movefolder)) { alert('$SYSMSG{'msg_blank_movetarget'}'); } else { if (flag) { mysubmit('move'); } } }\n";
	print "function check6() { var flag = check(); if (chk_empty(thisform.copypath)) { alert('$SYSMSG{'msg_blank_copytarget'}'); } else { if (flag) { mysubmit('copy'); } } }\n";
	print "function check7() { if (check()) { mysubmit('delete'); } }\n";
	print "function check8() { if (check()) { mysubmit('many_download'); } }\n";
	print "function check9() { if (check()) { mysubmit('share'); } }\n";
	$folder_cnt--;
	if ($filemgr_rows == 0) {
		print "function sall(){}\n";
		print "function sfile(){}\n";
		print "function snone(){}\n";
	} elsif ($filemgr_rows == 1) {
		print "function sall(){\n";
		print "thisform.sel.checked = 1; }\n";
		print "function sfile(){\n";
		print "if ($folder_cnt < 1) { thisform.sel.checked = 0; }\n";
		print "else { thisform.sel.checked = 1; } }\n";
		print "function snone(){\n";
		print "thisform.sel.checked = 0; }\n";
	} else {
		print "function sall(){\n";
		print "for (i=0;i<$filemgr_rows;i++) { thisform.sel[i].checked = 1; } }\n";
		print "function sfile(){\n";
		print "for (i=0;i<$folder_cnt;i++) { thisform.sel[i].checked = 0; }\n";
		print "for (i=$folder_cnt;i<$filemgr_rows;i++) { thisform.sel[i].checked = 1; } }\n";
		print "function snone(){\n";
		print "for (i=0;i<$filemgr_rows;i++) { thisform.sel[i].checked = 0; } }\n";
	}
	print "</script>\n";
	&foot('f');
} elsif ($DATA{'step'} eq 'fupload' && $menu_id ne '') {
	&head($DATA{'title'});
	print "<center><p><font color=red size=4><b>$SYSMSG{'filemgr_upload_where'} </b></font><img align=absmiddle src=/img/0folder.gif><font color=blue size=4><b> $DATA{'folder'}</b></font><font color=red size=4><b> $SYSMSG{'folder'}</b></font>";
	print "<form name=myform ENCTYPE=\"multipart/form-data\" method=post>\n";
	print "<input type=checkbox name=unzip value=1 checked>$SYSMSG{'filemgr_upload_unzip'}<br>\n" if ($zip_exist);
	if ($DATA{'act'} eq 'f') {
		print "<input type=hidden name=step value=filesmgr>\n";
	} elsif ($DATA{'act'} eq 's') {
		print "<input type=hidden name=step value=sharemgr>\n";
		print "<input type=hidden name=share value=$DATA{'share'}>\n";
	}
	print "<input type=hidden name=folder value=$DATA{'folder'}>\n";
	if ($DATA{'filemany'}) {
		for ($z=1;$z<=$DATA{'filemany'};++$z) { print "<img align=absmiddle src=/img/upload.gif border=0>$SYSMSG{'file'}$z：<input type=file name=\"upload_file\"><br>\n"; }
		--$z;
	} else {
		for ($z=1;$z<6;++$z) { print "<img align=absmiddle src=/img/upload.gif border=0>$SYSMSG{'file'}$z： <input type=file name=\"uploaded_file\"><br>\n"; }
		--$z;
	}
	print "<input type=submit value=\"$SYSMSG{'filemgr_upload_confirm'}\">\n";
	print "</form></center></tr>";
	&foot($DATA{'act'});
} elsif ($DATA{'step'} eq 'edit_file' && $admin eq '1') {
	&edit_file($DATA{'dnfile'});
} elsif ($DATA{'step'} eq 'down_load' && $admin eq '1') {
	&down_load($DATA{'dnfile'});
} elsif ($DATA{'step'} eq 'dosave' && $menu_id ne '') {
	my($buf, @mydir, $edfile);
	$edfile = $DATA{'edfile'};
	@mydir = split(/\//,$edfile);
	my $totalT = @mydir;
	--$totalT;
	my $fname=$mydir[$totalT];
	$buf = $DATA{'textbody'};
	$buf =~ s/\r//g;
	open(REAL,"> $edfile") || &err_disk("$SYSMSG{'filemgr_upload_cannot_open_editfile'}$edfile<br>");
	print REAL $buf;
	close(REAL);
	if ($DATA{'action'} eq 'save') {
		print "Location: $cgi_url/$fname?step=edit_file&dnfile=$edfile\n\n";
	} else {
		&head($SYSMSG{'title_savefile'});
		print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'filemgr_upload_completed'}</font>";
		&foot('f');
	}
} elsif ($DATA{'step'} eq 'sharemgr' && $menu_id ne '') {
	$DATA{'folder'} = &get_share($DATA{'folder'});
	$DATA{'folder'} = &chg_dir($DATA{'folder'},$DATA{'chfolder'}) if ($DATA{'action'} eq 'chdir');
	&make_dir($DATA{'folder'},$DATA{'newfolder'}) if ($DATA{'action'} eq 'mkdir');
	&del_dir($DATA{'folder'},$DATA{'sel'}) if ($DATA{'action'} eq 'delete');
	&ren_dir($DATA{'newname'},$DATA{'folder'},$DATA{'sel'}) if ($DATA{'action'} eq 'rename');
	&show_file($DATA{'folder'},$DATA{'dnfile'}) if ($DATA{'action'} eq 'showfile');
	&many_download($DATA{'folder'},$DATA{'sel'}) if ($DATA{'action'} eq 'many_download');
	&del_share($DATA{'sel'}) if ($DATA{'action'} eq 'del_share');
	&share('',$DATA{'sel'}) if ($DATA{'action'} eq 'share');
	$DATA{'folder'} = &get_share($DATA{'folder'});
	$tmpdnfile = time;
	&head($SYSMSG{'title_sharemgr'});
	print "<div align=center>\n";
	print "<table border=6 style=font-size:11pt width=95%  border-collapse: collapse  cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
	print "<tr><td colspan=7><img align=absmiddle src=/img/sharemgr.gif>$SYSMSG{'sign_left'}<font color=red><b>$SYSMSG{'share_current_dir'}</b></font><font color=blue><img align=absmiddle src=/img/0folder.gif> $DATA{'folder'} </font>$SYSMSG{'sign_right'}\n";
	if ($SPERM_UP{$DATA{'share'}} eq 'yes') {
		print "<td colspan=2><form method=POST><input type=hidden name=step value=fupload><input type=hidden name=title value=\"$SYSMSG{'share_title'}\"><input type=hidden name=act value=s><input type=hidden name=share value=$DATA{'share'}><input type=hidden name=folder value=$DATA{'folder'}>\n";
		print "<img align=absmiddle src=/img/upload.gif>$SYSMSG{'upload'}<input type=text name=filemany size=2 value=5>$SYSMSG{'files'}\n";
		print "<input type=submit value=\"$SYSMSG{'upload'}\">　<a href=$cgi_url?step=filesmgr&share=$DATA{'share'}&folder=$DATA{'folder'}>$SYSMSG{'share_backto_filemgr'}</a></font></form>";
	} else {
		print "<td colspan=2><font color=red>$SYSMSG{'share_readonly'}	<a href=$cgi_url?step=filesmgr&share=$DATA{'share'}&folder=$DATA{'folder'}>$SYSMSG{'share_backto_filemgr'}</a></font></td>\n";
	}

	if ($DATA{'share'} eq '') {
		print "<tr bgcolor=ffeeee><td><a href=javascript:sall()><img align=absmiddle src=/img/all.gif border=0></a><td align=center bgcolor=#6699cc><font color=white>$SYSMSG{'share_name'}<td	bgcolor=#6699cc><font color=white>$SYSMSG{'share_download'}<td bgcolor=#6699cc><font color=white>$SYSMSG{'share_upload'}<td bgcolor=#6699cc><font color=white>$SYSMSG{'share_mkdir'}<td  bgcolor=#6699cc><font color=white>$SYSMSG{'share_edit'}<td	bgcolor=#6699cc><font color=white>$SYSMSG{'share_delete'}";
		print "<td align=center bgcolor=#6699cc><font color=white>$SYSMSG{'share_realpath'}";
	} else {
		print "<tr bgcolor=ffeeee><td><a href=javascript:sfile()><img align=absmiddle src=/img/allfile.gif border=0></a>\n";
		if ($DATA{'sort'} eq 'name' || $DATA{'sort'} eq '') {
			print "<td align=center bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=name_rev><font color=white>$SYSMSG{'filemgr_file_name'}</font></a>\n";
		} else {
			print "<td align=center bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=name><font color=white>$SYSMSG{'filemgr_file_name'}</font></a>\n";
		}
		if ($DATA{'sort'} eq 'type') {
			print "<td bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=type_rev><font color=white>$SYSMSG{'filemgr_file_type'}</font></a>\n";
		} else {
			print "<td bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=type><font color=white>$SYSMSG{'filemgr_file_type'}</font></a>\n";
		}
		if ($DATA{'sort'} eq 'perm') {
			print "<td bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=perm_rev><font color=white>$SYSMSG{'filemgr_file_priv'}</font></a>\n";
		} else {
			print "<td bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=perm><font color=white>$SYSMSG{'filemgr_file_priv'}</font></a>\n";
		}
		if ($DATA{'sort'} eq 'owner') {
			print "<td bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=owner_rev><font color=white>$SYSMSG{'filemgr_file_owner'}</font></a>\n";
		} else {
			print "<td bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=owner><font color=white>$SYSMSG{'filemgr_file_owner'}</font></a>\n";
		}
		if ($DATA{'sort'} eq 'gowner') {
			print "<td bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=gowner_rev><font color=white>$SYSMSG{'filemgr_file_owner_group'}</font></a>\n";
		} else {
			print "<td bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=gowner><font color=white>$SYSMSG{'filemgr_file_owner_group'}</font></a>\n";
		}
		if ($DATA{'sort'} eq 'size') {
			print "<td align=right bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=size_rev><font color=white>$SYSMSG{'filemgr_file_size'}</font></a>\n";
		} else {
			print "<td align=right bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=size><font color=white>$SYSMSG{'filemgr_file_size'}</font></a>\n";
		}
		if ($DATA{'sort'} eq 'time') {
			print "<td align=center bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=time_rev><font color=white>$SYSMSG{'filemgr_file_date'}</font></a>\n";
		} else {
			print "<td align=center bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=time><font color=white>$SYSMSG{'filemgr_file_date'}</font></a>\n";
		}
	}
	print "<form name=myform method=POST action=$cgi_url$DATA{'folder'}/$tmpdnfile.zip>";
	print "<input type=hidden name=step value=sharemgr>\n";
	print "<input type=hidden name=action value=>\n";
	print "<input type=hidden name=folder value=$DATA{'folder'}>\n";
	print "<input type=hidden name=share value=$DATA{'share'}>\n";
	print "<td bgcolor=#6699cc rowspan=10><p><font color=white>$SYSMSG{'share_pannel_minihelp'}</p>";
	if ($DATA{'share'} eq '') {
		print "<p><a href=javascript:onclick=alert('$SYSMSG{'share_pannel_hint_1'}') border=0><img align=absmiddle src=/img/fd.gif border=0></a><input type=button value=\"$SYSMSG{'share_cancel_share'}\" onclick=check9()></p>" if ($admin eq '1');
		print "<p><a href=javascript:onclick=alert('$SYSMSG{'share_pannel_hint_2'}') border=0><img align=absmiddle src=/img/fd.gif border=0></a><input type=button value=\"$SYSMSG{'share_config_share'}\" onclick=check2()></p>" if ($admin eq '1');
		print "<tr><td bgcolor=#ffeeee><td colspan=7 bgcolor=#eedfcc>";
	} else {
		print "<p><a href=javascript:onclick=alert('$SYSMSG{'share_pannel_hint_3'}') border=0><img align=absmiddle src=/img/newfd.gif border=0></a><input type=text name=newfolder size=12><input type=button value=\"$SYSMSG{'share_mkdir'}\" onclick=check1()></p>";
		print "<p><a href=javascript:onclick=alert('$SYSMSG{'share_pannel_hint_4'}') border=0><img align=absmiddle src=/img/rename.gif border=0></a><input type=text name=newname size=16><input type=button value=\"$SYSMSG{'share_rename'}\" onclick=check4()></p>";
		print "<p><a href=javascript:onclick=alert('$SYSMSG{'share_pannel_hint_5'}') border=0><img align=absmiddle src=/img/del.gif border=0></a><input type=button value=\"$SYSMSG{'share_delete'}\" onclick=check7()></p>";
		print "<p><a href=javascript:onclick=alert('$SYSMSG{'share_pannel_hint_6'}') border=0><img align=absmiddle src=/img/fd.gif border=0></a><input type=button value=\"$SYSMSG{'share_download'}\" onclick=check8()></p>";
	}
	$folder_cnt = 0;
	if ($DATA{'share'}) {
		print "<tr><td bgcolor=#ffeeee><a href=javascript:sall()><img align=absmiddle src=/img/all.gif border=0></a><td bgcolor=#ffffee><a href=$cgi_url?step=filesmgr&action=chdir&folder=$DATA{'folder'}&chfolder=..><img align=absmiddle src=/img/upfolder.gif border=0> $SYSMSG{'parrent'}</a>";
		print "<td bgcolor=#e8f3ff><font color=darkgreen>$TYPE{'..'}</font></td>";
		print "<td bgcolor=#e8f3ff><font color=blue>$PERM{'..'}</td>";
		$fusr = getpwuid($OWNER{'..'});
		$fgrp = getgrgid($GOWNER{'..'});
		print "<td bgcolor=#e8f3ff>$fusr</td>";
		print "<td bgcolor=#e8f3ff>$fgrp</td>";
		print "<td bgcolor=#e8f3ff align=right>$FSIZE{'..'}</td>";
		print "<td bgcolor=#e8f3ff align=right>$MODIFY{'..'}</td></tr>\n";
	}
	if ( $DATA{'sort'} eq 'name' || $DATA{'sort'} eq '') {
	      @myfolds = sort keys %FOLDS;
	      @myfiles = sort keys %FILES;
	} elsif ( $DATA{'sort'} eq 'name_rev' ) {
	      @myfolds = reverse(sort keys %FOLDS);
	      @myfiles = reverse(sort keys %FILES);
	} elsif ( $DATA{'sort'} eq 'time') {
	      @myfolds = sort by_time keys %FOLDS;
	      @myfiles = sort by_time keys %FILES;
	} elsif ( $DATA{'sort'} eq 'time_rev' ) {
	      @myfolds = reverse(sort by_time keys %FOLDS);
	      @myfiles = reverse(sort by_time keys %FILES);
	} elsif ( $DATA{'sort'} eq 'type' ) {
	      @myfolds = sort by_time keys %FOLDS;
	      @myfiles = sort by_time keys %FILES;
	} elsif ( $DATA{'sort'} eq 'type_rev' ) {
	      @myfolds = reverse(sort by_time keys %FOLDS);
	      @myfiles = reverse(sort by_time keys %FILES);
	} elsif ( $DATA{'sort'} eq 'perm' ) {
	      @myfolds = sort by_perm keys %FOLDS;
	      @myfiles = sort by_perm keys %FILES;
	} elsif ( $DATA{'sort'} eq 'perm_rev') {
	      @myfolds = reverse(sort by_perm keys %FOLDS);
	      @myfiles = reverse(sort by_perm keys %FILES);
	} elsif ( $DATA{'sort'} eq 'owner' ) {
	      @myfolds = sort by_owner keys %FOLDS;
	      @myfiles = sort by_owner keys %FILES;
	} elsif ( $DATA{'sort'} eq 'owner_rev') {
	      @myfolds = reverse(sort by_owner keys %FOLDS);
	      @myfiles = reverse(sort by_owner keys %FILES);
	} elsif ( $DATA{'sort'} eq 'gowner' ) {
	      @myfolds = sort by_gowner keys %FOLDS;
	      @myfiles = sort by_gowner keys %FILES;
	} elsif ( $DATA{'sort'} eq 'gowner_rev') {
	      @myfolds = reverse(sort by_gowner keys %FOLDS);
	      @myfiles = reverse(sort by_gowner keys %FILES);
	} elsif ( $DATA{'sort'} eq 'size' ) {
	      @myfolds = sort by_size keys %FOLDS;
	      @myfiles = sort by_size keys %FILES;
	} elsif ( $DATA{'sort'} eq 'size_rev') {
	      @myfolds = reverse(sort by_size keys %FOLDS);
	      @myfiles = reverse(sort by_size keys %FILES);
	}
	foreach $file (@myfolds) {
		$myfile = $file;
		if ($CONFIG{'codepage_smb'} eq 'yes') {
			$myfile =~ s/\:/\=/g;
			$myfile = &qpdecode($myfile);
		}
		next if ($file eq '.' || $file eq '..');
		if ($DATA{'share'} eq '') {
			$sfile = substr($file,1);
			print "<tr><td bgcolor=#ddeeff><input type=checkbox name=sel value=$file></td><td bgcolor=#e8f3ff><a href=$cgi_url?step=sharemgr&action=chdir&share=$DATA{'share'}&folder=/&chfolder=$sfile><img align=absmiddle src=/img/$IMAGE{$file} border=0>$SDESC{$file}</a></td>";
			print "<td bgcolor=#e8f3ff>".(($SPERM_DN{$file} eq 'yes') ? "<font color=red><b>ˇ<font>" : 'ㄨ')."</font></td>";
			print "<td bgcolor=#e8f3ff>".(($SPERM_UP{$file} eq 'yes') ? "<font color=red><b>ˇ<font>" : 'ㄨ')."</td>";
			print "<td bgcolor=#e8f3ff>".(($SPERM_DIR{$file} eq 'yes') ? "<font color=red><b>ˇ<font>" : 'ㄨ')."</td>";
			print "<td bgcolor=#e8f3ff>".(($SPERM_EDIT{$file} eq 'yes') ? "<font color=red><b>ˇ<font>" : 'ㄨ')."</td>";
			print "<td bgcolor=#e8f3ff>".(($SPERM_DEL{$file} eq 'yes') ? "<font color=red><b>ˇ<font>" : 'ㄨ')."</td>";
			print "<td bgcolor=#e8f3ff>$myfile</td></tr>\n";
		} else {
			print "<tr><td bgcolor=#ddeeff><input type=checkbox name=sel value=$file></td>";
			print "<td bgcolor=#e8f3ff><a href=$cgi_url?step=sharemgr&action=chdir&share=$DATA{'share'}&folder=$DATA{'folder'}&chfolder=$file><img align=absmiddle src=/img/$IMAGE{$file} border=0> $myfile</a></td>";
			print "<td bgcolor=#e8f3ff><font color=darkgreen>$TYPE{$file}</font></td>";
			print "<td bgcolor=#e8f3ff><font color=blue>$PERM{$file}</td>";
			$fusr = getpwuid($OWNER{$file});
			$fgrp = getgrgid($GOWNER{$file});
			print "<td bgcolor=#e8f3ff>$fusr</td>";
			print "<td bgcolor=#e8f3ff>$fgrp</td>";
			print "<td bgcolor=#e8f3ff align=right>$FSIZE{$file}</td>";
			print "<td bgcolor=#e8f3ff align=right>$MODIFY{$file}</td></tr>\n";
		}
		$folder_cnt++;
	}
	foreach $file (@myfiles) {
		$myfile = $file;
		if ($CONFIG{'codepage_smb'} eq 'yes') {
			$myfile =~ s/\:/\=/g;
			$myfile = &qpdecode($myfile);
		}
		print "<tr><td bgcolor=#ddeeff><input type=checkbox name=sel value=$file></td>";
		print "<td bgcolor=#ffffff><a href=$cgi_url$DATA{'folder'}/$file?step=sharemgr&action=showfile&folder=$DATA{'folder'}&dnfile=$file&share=$DATA{'share'}><img align=absmiddle src=/img/$IMAGE{$file} border=0> $myfile</a></td>";
		print "<td bgcolor=#ffffff><font color=#cd0000>$TYPE{$file}</font></td>";
		print "<td bgcolor=#ffffff><font color=red>$PERM{$file}</td>";
		$fusr = getpwuid($OWNER{$file});
		$fgrp = getgrgid($GOWNER{$file});
		print "<td bgcolor=#ffffff>$fusr</td>";
		print "<td bgcolor=#ffffff>$fgrp</td>";
		print "<td bgcolor=#ffffff align=right>$FSIZE{$file}</td>";
		print "<td bgcolor=#ffffff align=right>$MODIFY{$file}</td></tr>\n";
	}
	print "<tr><td colspan=8><center>$SYSMSG{'err_file&dir_notfound'}</center></td></tr>\n" if ($filemgr_rows le 0);
	for (1..6 - $filemgr_rows) { print "<tr><td bgcolor=#6699cc colspan=8> </td></tr>\n"; }
	print "</table></form></div><script>\n";
	print "function check() {\n";
	if ($filemgr_rows == 1) {
		print "if (!thisform.sel.checked) { alert('$SYSMSG{'msg_file_select_not_yet'}'); return 0; } else { return 1; } }\n";
	} elsif ($filemgr_rows > 1) {
		print "var flag = 0;\n";
		print "for (i=0;i<$filemgr_rows;i++) {\n";
		print "if (thisform.sel[i].checked) { flag = 1; } }\n";
		print "if (flag == 0) { alert('$SYSMSG{'msg_file_select_not_yet'}'); }\n";
		print "return flag; }\n";
	} else { print "}\n"; }
	print "function check1() { if (chk_empty(thisform.newfolder)) { alert('$SYSMSG{'msg_blank_folder'}'); } else { mysubmit('mkdir'); } }\n";
	print "function check4() { var flag = check(); if (chk_empty(thisform.newname)) { alert('$SYSMSG{'msg_blank_filename'}'); } else { if (flag) { mysubmit('rename'); } } }\n";
	print "function check7() { if (check()) { mysubmit('delete'); } }\n";
	print "function check8() { if (check()) { mysubmit('many_download'); } }\n";
	print "function check9() { if (check()) { mysubmit('del_share'); } }\n";
	print "function check2() { if (check()) { mysubmit('share'); } }\n";
	if ($filemgr_rows == 0) {
		print "function sall(){}\n";
		print "function sfile(){}\n";
		print "function snone(){}\n";
	} elsif ($filemgr_rows == 1) {
		print "function sall(){\n";
		print "thisform.sel.checked = 1; }\n";
		print "function sfile(){\n";
		print "if ($folder_cnt < 1) { thisform.sel.checked = 0; }\n";
		print "else { thisform.sel.checked = 1; } }\n";
		print "function snone(){\n";
		print "thisform.sel.checked = 0; }\n";
	} else {
		print "function sall(){\n";
		print "for (i=0;i<$filemgr_rows;i++) { thisform.sel[i].checked = 1; } }\n";
		print "function sfile(){\n";
		print "for (i=0;i<$folder_cnt;i++) { thisform.sel[i].checked = 0; }\n";
		print "for (i=$folder_cnt;i<$filemgr_rows;i++) { thisform.sel[i].checked = 1; } }\n";
		print "function snone(){\n";
		print "for (i=0;i<$filemgr_rows;i++) { thisform.sel[i].checked = 0; } }\n";
	}
	print "</script>\n";
	&foot('s');
} elsif ($DATA{'step'} eq 'doshare' && $admin eq '1') {
	if ($DATA{'folder'} eq '') {
		$mydir = '';
	} else{
		$mydir = $DATA{'folder'};
		$mydir .= '/' if ($mydir ne '/');
	}
	if ($DATA{'grp'} =~ /999/) {
		$DATA{'grp'} = 'root';
		foreach $gid (sort keys %GIDS) {
			$grp = $GIDNM{$gid};
			next if (int($gid)<500);
			next if (&check_special($grp) eq 1);
			$DATA{'grp'} .= ','.$grp;
		}
	}
	@items = split(/,/,$DATA{'items'});
	foreach $item (@items) {
		$SHARE{"$mydir$item"} = $DATA{'grp'};
		$SDESC{"$mydir$item"} = $DATA{"share-$item"};
		$SDESC{"$mydir$item"} = "$mydir$item" if ($SDESC{"$mydir$item"} eq '');
		$SPERM_DN{"$mydir$item"} = $DATA{'dn'};
		$SPERM_UP{"$mydir$item"} = $DATA{'up'};
		$SPERM_DIR{"$mydir$item"} = $DATA{'dir'};
		$SPERM_EDIT{"$mydir$item"} = $DATA{'edit'};
		$SPERM_DEL{"$mydir$item"} = $DATA{'del'};
	}
	&write_share;
	&head($SYSMSG{'title_sharemgr'});
	print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'share_completed'}</font>";
	&foot('s');
} elsif ($DATA{'step'} eq 'imgmgr' && $admin eq '1') {
	&new_digits if ($DATA{'action'} eq 'new_digits');
	&del_dir($cnt_base,$DATA{'style'}) if ($DATA{'action'} eq 'delete');
	&get_digits;
	&head($SYSMSG{'title_digitsmgr'});
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=step value=imgmgr>\n";
	print "<input type=hidden name=action value=>\n";
	print "<table border=6 style=font-size:11pt width=95%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
	print "<tr><td colspan=3 align=center><input type=button value=\"$SYSMSG{'counter_new'}\" onclick=mysubmit('new_digits')><input type=button value=\"$SYSMSG{'counter_delete'}\" onclick=check1()>";
	$digits_rows = $#STYLES - 4;
	print "<tr><th>$SYSMSG{'counter_choose'}<th align=center>$SYSMSG{'counter_img_lib'}<th align=right>$SYSMSG{'counter_name'}\n";
	foreach $file (sort @STYLES) {
		next if (!(-d "$cnt_base/$file"));
		next if ($file eq '.' || $file eq '..');
		print "<tr><td><input type=checkbox name=style value=$file><td>";
		print "<img align=absmiddle src=$cnt_url?style=$file>";
		print "<td>$file";
	}
	print "</table></form></center><script>";
	print "function check() {\n";
	if ($digits_rows == 1) {
		print "if (!thisform.style.checked) { alert('$SYSMSG{'counter_select_not_yet'}'); return 0; } else { return 1; } }\n";
	} elsif ($digits_rows > 1) {
		print "var flag = 0;\n";
		print "for (i=0;i<$digits_rows;i++) {\n";
		print "if (thisform.style[i].checked) { flag = 1; } }\n";
		print "if (flag == 0) { alert('$SYSMSG{'counter_select_not_yet'}'); }\n";
		print "return flag; }\n";
	} else { print "}\n"; }
	print "function check1() { if (check()) { mysubmit('delete'); } }\n";
	print "</script>";
	&foot('');
} elsif ($DATA{'step'} eq 'set_count' && $menu_id ne '') {
	($musr,$pwd,$muid,$mgid,$quo,$com,$gcos,$home,$shell) = getpwuid($menu_id);
	&read_cnt_conf("$home/$cnt_config");
	&get_digits;
	&head($SYSMSG{'title_setcnt'});
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=step value=cnt_conf>\n";
	print "<table border=0 style=font-size:11pt width=80% >\n";
	print "<tr><th align=right>$SYSMSG{'set_counter_start'}\n";
	print "<td><input type=text name=start value=$CNTCONF{'start'}>\n";
	print "<tr><th align=right>$SYSMSG{'set_counter_incream'}\n";
	print "<td><input type=text name=add value=$CNTCONF{'add'}>\n";
	print "<tr><th align=right>$SYSMSG{'set_counter_digits'}\n";
	print "<td><input type=text name=digits value=$CNTCONF{'digits'}>\n";
	print "<tr><th align=right>$SYSMSG{'set_counter_check_ip'}\n";
	if ($CNTCONF{'check_ip'} eq 'yes') {
		print "<td><input type=checkbox name=check_ip value=yes checked>\n";
	} else {
		print "<td><input type=checkbox name=check_ip value=yes>\n";
	}
	print "<tr bgcolor=#6699cc><td colspan=2 align=center><font color=#ffffff size=4><b>$SYSMSG{'set_counter_style'}</b></font><tr><hr>\n";
	foreach $file (sort @STYLES) {
		next if (!(-d "$cnt_base/$file"));
		next if ($file eq '.' || $file eq '..');
		if ($CNTCONF{'style'} eq $file) {
			print "<tr><td colspan=2><input type=radio name=style value=$file checked>";
		} else {
			print "<tr><td colspan=2><input type=radio name=style value=$file>";
		}
		print "<img align=absmiddle src=$cnt_url?style=$file>";
	}
	print "<tr bgcolor=#6699cc><td colspan=2 align=center><input type=submit value=\" $SYSMSG{'set_counter_confirm'} \">\n";
	print "</table></form></center>";
	&foot('');
} elsif ($DATA{'step'} eq 'cnt_conf' && $menu_id ne '') {
	($musr,$pwd,$muid,$mgid,$quo,$com,$gcos,$home,$shell) = getpwuid($menu_id);
	$CNTCONF{'start'} = $DATA{'start'};
	$CNTCONF{'check_ip'} = $DATA{'check_ip'};
	$CNTCONF{'add'} = $DATA{'add'};
	$CNTCONF{'digits'} = $DATA{'digits'};
	$CNTCONF{'style'} = $DATA{'style'};
	open (CFG, "> $home/$cnt_config") || &err_disk("$SYSMSG{'err_cannot_open_counter_config'}<br>");
	flock(CFG,2);
	foreach $name (keys %CNTCONF) {
		print CFG "$name:$CNTCONF{$name}\n";
	}
	flock(CFG,8);
	close(CFG);
	&head($SYSMSG{'title_setcnt'});
	print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'cset_counter_completed'}</font></center>\n";
	&foot('');
} elsif ($DATA{'step'} eq 'view_count' && $menu_id ne '') {
	($musr,$pwd,$muid,$mgid,$quo,$com,$gcos,$home,$shell) = getpwuid($menu_id);
	&read_cnt_data("$home/$cnt_data");
	&head($SYSMSG{'title_viewcnt'});
	print "<center><table border=6 style=font-size:11pt width=75%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
	print "<tr><th><th>$SYSMSG{'view_counter_pagename'}<th align=right>$SYSMSG{'view_counter_total'}<th align=right>$SYSMSG{'view_counter_last_ip'}\n";
	foreach $cnt (keys %COUNT) {
		print "<tr><td><a href=$cgi_url?step=del_count&cnt=$cnt>$SYSMSG{'view_counter_delete'}</a><td>$cnt<td>$COUNT{$cnt}<td>$LASTIP{$cnt}\n";
	}
	print "</table></center><center>";
	print "<form name=myform method=post>\n";
	print "<input type=hidden name=step value=reset_cnt>\n";
	print "<center><font color=red>$SYSMSG{'view_counter_hint'}</font></center>";
	print "<input type=submit value=\" $SYSMSG{'view_counter_reset'} \"></center><br>\n";
	if ($menu_id eq 0) {
		print "<center><img src=/img/home.gif border=0 align=absmiddle><a href=http://$HOST target=_blank>$SYSMSG{'view_counter_jumpto_rootpage'}</a></center>\n";
	} else {
		print "<center><img src=/img/home.gif border=0 align=absmiddle><a href=http://$HOST/~$musr target=_blank>$SYSMSG{'view_counter_jumpto_homepage'}</a></center>\n";
	}
	&foot('');
} elsif ($DATA{'step'} eq 'del_count' && $menu_id ne '') {
	($musr,$pwd,$muid,$mgid,$quo,$com,$gcos,$home,$shell) = getpwuid($menu_id);
	&read_cnt_conf("$home/$cnt_config");
	&read_cnt_data("$home/$cnt_data");
	$cnt = $DATA{'cnt'};
	delete $COUNT{$cnt};
	&write_cnt_data("$home/$cnt_data");
	&head($SYSMSG{'title_delcnt'});
	print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'view_counter_page'} $cnt $SYSMSG{'view_counter_delete_completed'}</font></center>\n";
	&foot('');
} elsif ($DATA{'step'} eq 'reset_cnt' && $menu_id ne '') {
	($musr,$pwd,$muid,$mgid,$quo,$com,$gcos,$home,$shell) = getpwuid($menu_id);
	&read_cnt_conf("$home/$cnt_config");
	&read_cnt_data("$home/$cnt_data");
	foreach $cnt (keys %COUNT) {
		$COUNT{$cnt} = $CNTCONF{'start'};
	}
	&write_cnt_data("$home/$cnt_data");
	&head($SYSMSG{'title_resetcnt'});
	print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'view_counter_reset_all_become'}$CNTCONF{'start'}</font></center>\n";
	&foot('');
} elsif ($DATA{'step'} eq 'set_gb' && $menu_id ne '') {
	($musr,$pwd,$muid,$mgid,$quo,$com,$gcos,$home,$shell) = getpwuid($menu_id);
	&read_gb_conf("$home/$gb_config");
	&head($SYSMSG{'title_setgb'});
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=step value=gb_conf>\n";
	print "<table border=6 style=font-size:11pt width=75%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
	print "<tr bgcolor=#6699cc><th align=right><font color=#ffffff>$SYSMSG{'set_gbook_title'}</font>\n";
	print "<td><input type=text name=title value=$GBCONF{'title'}>\n";
	print "<tr><th align=right><font color=darkgreen>$SYSMSG{'set_gbook_per_page'}</font>\n";
	print "<td><input type=text size=3 name=many value=$GBCONF{'many'}>$SYSMSG{'set_gbook_msg_no'}\n";
	print "<tr><th align=right><font color=red>$SYSMSG{'set_gbook_page_yes'}</font><td>\n";
	if ($GBCONF{'page_jump'} eq 'no') {
		print "<input type=checkbox name=page_jump value=no checked>$SYSMSG{'set_gbook_page_no'}\n";
	} else {
		print "<input type=checkbox name=page_jump value=no>$SYSMSG{'set_gbook_page_no'}\n";
	}
	print "<tr><th align=right><font color=purple>$SYSMSG{'set_gbook_sort_mode'}</font><td>\n";
	if ($GBCONF{'sort'} eq 'by_name') {
		print "<input type=radio name=sort value=by_name checked><font color=blue>$SYSMSG{'set_gbook_sort_by_name'}</font>\n";
	} else {
		print "<input type=radio name=sort value=by_name><font color=blue>$SYSMSG{'set_gbook_sort_by_name'}</font>\n";
	}
	if ($GBCONF{'sort'} eq 'by_date') {
		print "<input type=radio name=sort value=by_date checked><font color=darkred>$SYSMSG{'set_gbook_sort_by_date'}</font>\n";
	} else {
		print "<input type=radio name=sort value=by_date><font color=dardred>$SYSMSG{'set_gbook_sort_by_date'}</font>\n";
	}
	print "<tr><th align=right><font color=darkblue>$SYSMSG{'set_gbook_mailto_owner'}</font><td>\n";
	if ($GBCONF{'email'} eq 'yes') {
		print "<input type=checkbox name=email value=yes checked>$SYSMSG{'set_gbook_mailto_owner_yes'}\n";
	} else {
		print "<input type=checkbox name=email value=yes>$SYSMSG{'set_gbook_mailto_owner_yes'}\n";
	}
	print "<tr><th align=right><font color=darkblue>$SYSMSG{'set_gbook_subscribe_mode'}</font><td>\n";
	if ($GBCONF{'subscribe'} eq 'yes') {
		print "<input type=checkbox name=subscribe value=yes checked>$SYSMSG{'set_gbook_subscribe_mode_yes'}\n";
	} else {
		print "<input type=checkbox name=subscribe value=yes>$SYSMSG{'set_gbook_subscribe_mode_yes'}\n";
	}
	print "<tr><td><td><input type=submit value=\" $SYSMSG{'set_gbook_confirm'} \">\n";
	print "</table></form></center>";
	&foot('');
} elsif ($DATA{'step'} eq 'gb_conf' && $menu_id ne '') {
	($musr,$pwd,$muid,$mgid,$quo,$com,$gcos,$home,$shell) = getpwuid($menu_id);
	$GBCONF{'title'} = $DATA{'title'};
	$GBCONF{'many'} = $DATA{'many'};
	$GBCONF{'page_jump'} = $DATA{'page_jump'};
	$GBCONF{'email'} = $DATA{'email'};
	$GBCONF{'subscribe'} = $DATA{'subscribe'};
	$GBCONF{'sort'} = $DATA{'sort'};
	open (CFG, "> $home/$gb_config") || &err_disk("$SYSMSG{'err_cannot_open_gbook_config'}<br>");
	flock(CFG,2);
	foreach $name (keys %GBCONF) {
		print CFG "$name:$GBCONF{$name}\n";
	}
	flock(CFG,8);
	close(CFG);
	if ($GBCONF{'subscribe'} eq 'yes') {
		&set_aliases('gbook-'.$musr,"$home/$gb_subscribe");
	} else {
		&unset_aliases('gbook-'.$musr);
	}
	system("$CONFIG{'mailprog'} -bi");
	&head($SYSMSG{'title_setgb'});
	print "<center><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'set_gbook_completed'}</font></center>\n";
	&foot('');
} elsif ($DATA{'step'} eq 'edit_gb' && $menu_id ne '') {
	my @GB = ();
	($musr,$pwd,$muid,$mgid,$quo,$com,$gcos,$home,$shell) = getpwuid($menu_id);
	&read_gb_conf("$home/$gb_config");
	&read_gb_data("$home/$gb_data");
	&read_gb_reply("$home/$gb_reply");
	&head($SYSMSG{'title_gbmgr'});

	sub byredate {
		$REDATE{$a} <=> $REDATE{$b};
	}

	sub bydate {
		$GBDATE{$b} <=> $GBDATE{$a};
	}

	sub byname {
		$GBAUTH{$a} cmp $GBAUTH{$b};
	}

	print "<BR><CENTER><h2><font color=6699cc>$SYSMSG{'sign_left'}$SYSMSG{'gbook_manage'} $GBCONF{'title'}$SYSMSG{'sign_right'}</font></h2>";
	print "<a href=$cgi_url?step=gb_subscribe><img align=absmiddle src=/img/chgpw.gif border=0>$SYSMSG{'gbook_user'}</a></CENTER>" if ($GBCONF{'subscribe'} eq 'yes');
	print "<hr size=1 color=red width=90%>\n";
	@GB = sort byname keys %GBAUTH if ($GBCONF{'sort'} eq 'by_name');
	@GB = sort bydate keys %GBDATE if ($GBCONF{'sort'} eq 'by_date');
	@REPLY = sort byredate keys %REDATE;
	$DATA{'page'} = 1 if ($DATA{'page'} eq '');
	$DATA{'startpage'} = 1 if ($DATA{'startpage'} eq '');
	if ($GBCONF{'page_jump'} ne 'no') {
		if ($DATA{'page'} == 1) {
			$start = 0;
			$end = $GBCONF{'many'}-1;
		} else {
			$start = $GBCONF{'many'} * ($DATA{'page'}-1);
			$end = $start + $GBCONF{'many'} - 1;
		}
	} else {
		$start = 0;
		$end = $#GB;
	}
	$end = $#GB if ($end > $#GB);
	print "\n";
	if ($end < 0) {
		print "<center><font color=3699cc face=$SYSMSG{'variable_font'}><h2>$SYSMSG{'gbook_no_msg'}</h2></font><img align=absmiddle src=/img/dingdong0.gif height=160></center>\n";
	} else {
		print "<center><form method=post><input type=hidden name='step' value='del_all_gb'><font color=3699cc><b><input type=checkbox name=del_all value='yes'>$SYSMSG{'gbook_del_all_msg'}<b></font>　<input type=submit value=\" $SYSMSG{'gbook_del_confirm'} \"></form>\n";
		print "<center><form method=post><input type=hidden name='step' value='del_checked_gb'><input type=submit value=\" $SYSMSG{'gbook_del_checked_msg'} \"><br>\n";

		print "<center><fieldset><legend align=center><font color=red><b>$SYSMSG{'quick_jump'}</b></font></legend>";
		if ($GBCONF{'page_jump'} ne 'no') {
			$num = $DATA{'startpage'}-10;
			print "<a href=$cgi_url?step=edit_gb&page=$num&startpage=$num>$SYSMSG{'ten_up'}</a>\n" if ($DATA{'startpage'} > 10);
			$num = $DATA{'page'}-1;
			print "<a href=$cgi_url?step=edit_gb&page=$num&startpage=$DATA{'startpage'}>$SYSMSG{'sign_up'}</a>\n" if ($DATA{'page'} > 1);
			$pagecnt = $DATA{'startpage'}+9;
			$pagecnt = int($#GB/$GBCONF{'many'}+1) if (int($#GB/$GBCONF{'many'}+1) < $pagecnt);
			foreach ($DATA{'startpage'}..$pagecnt) {
				if ($DATA{'page'} == $_) {
					print "$_ ";
				} else {
					print "&nbsp;<a href=$cgi_url?step=edit_gb&page=$_&startpage=$DATA{'startpage'}> $_ </a>";
				}
			}
			$num = $DATA{'page'}+1;
			print "<a href=$cgi_url?step=edit_gb&page=$num&startpage=$DATA{'startpage'}>$SYSMSG{'sign_down'}</a>\n" if ($end < $#GB);
			$num = $DATA{'startpage'}+10;
			print "<a href=$cgi_url?step=edit_gb&page=$num&startpage=$num>$SYSMSG{'ten_down'}</a>\n" if ($DATA{'startpage'}+9 < int($#GB/$GBCONF{'many'}+1));
		}
		print "</center></fieldset><br>";

		for ($start..$end) {
			$cnt = $GB[$_];
			$mydate = &get_date($GBDATE{$cnt});
			if ($GBMAIL{$cnt} eq "") {
				print "<fieldset><legend> $GBAUTH{$cnt} 　 <font color= 6699cc>$SYSMSG{'gbook_msg_date'}$mydate</font> （$GBIP{$cnt}） \n";
				print "<a href=$cgi_url?step=reply_gb&page=$DATA{'page'}&startpage=$DATA{'startpage'}&id=$cnt>$SYSMSG{'gbook_msg_reply'}</a> \n";
				print "<a href=$cgi_url?step=modify_gb&page=$DATA{'page'}&startpage=$DATA{'startpage'}&id=$cnt>$SYSMSG{'gbook_msg_edit'}</a> \n";
				print "<input type=checkbox name=id value=$cnt><a href=$cgi_url?step=del_gb&page=$DATA{'page'}&startpage=$DATA{'startpage'}&id=$cnt>$SYSMSG{'gbook_msg_del'}</a> </legend>\n";
			} else {
				print "<fieldset><legend> <img align=absmiddle src=/img/fwmail.gif border=0><a href=mail.cgi?step=mailto&to=$GBMAIL{$cnt}&user=$user> $GBAUTH{$cnt}</a> 　 <font color= 6699cc> $SYSMSG{'gbook_msg_date'}$mydate</font> （$GBIP{$cnt}） \n";
				print "<a href=$cgi_url?step=reply_gb&page=$DATA{'page'}&startpage=$DATA{'startpage'}&id=$cnt>$SYSMSG{'gbook_msg_reply'}</a> \n";
				print "<a href=$cgi_url?step=modify_gb&page=$DATA{'page'}&startpage=$DATA{'startpage'}&id=$cnt>$SYSMSG{'gbook_msg_edit'}</a> \n";
				print "<input type=checkbox name=id value=$cnt> <a href=$cgi_url?step=del_gb&page=$DATA{'page'}&startpage=$DATA{'startpage'}&id=$cnt>$SYSMSG{'gbook_msg_del'}</a> </legend>\n";
			}
			if ($MODE{$cnt} eq '1') {
				print "<div align=right><table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt width=90%><tr><td bgcolor=#6699cc width=15%><font color=white><b>$SYSMSG{'gbook_msg_subject'}</font></td><td bgcolor=#6699cc><font color=white>$GBTITLE{$cnt}</font></td>\n";
				print "<tr><td bgcolor=#ffcccc width=15%><font color=darkred><b>$SYSMSG{'gbook_msg_content'}</b></font></td><td  bgcolor=#ffdcdc><font color=darkblue>$MESSAGES{$cnt}</font></td></tr>";
			} else {
				print "<div align=right><table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt width=90%><tr><td bgcolor=#6699cc width=15%><font color=white><b>$SYSMSG{'gbook_msg_subject'}</font></td><td bgcolor=#6699cc><font color=white>$GBTITLE{$cnt}</font></td>\n";
				print "<tr><td bgcolor=#aaefff width=15%><font color=darkred><b>$SYSMSG{'gbook_msg_content'}</b></font></td><td  bgcolor=#ccffee><font color=darkblue>$MESSAGES{$cnt}</font></td></tr>";
			}
			print "<tr><td colspan=2><div align=right><table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt width=90%>\n";
			for (0..$#REPLY) {
				$parn = $REPLY[$_];
				if ($REPARN{$parn} eq $cnt) {
					$mydate = &get_date($REDATE{$parn});
					if ($REMAIL{$cnt} eq "") {
						print "<tr><td colspan=2> $REAUTH{$parn} 　 <font color= 6699cc> $SYSMSG{'gbook_msg_date'}$mydate</font> （$REIP{$parn}） <input type=checkbox name=reply value=$cnt><a href=$cgi_url?step=del_reply&page=$DATA{'page'}&startpage=$DATA{'startpage'}&id=$parn>$SYSMSG{'gbook_msg_del'}</a> </td></tr>\n";
					} else {
						print "<tr><td colspan=2><img align=absmiddle src=/img/fwmail.gif border=0><a href=mail.cgi?step=mailto&to=$REMAIL{$parn}&user=$musr> $REAUTH{$parn}</a><font color= 6699cc> $SYSMSG{'gbook_msg_date'}$mydate</font> （$REIP{$parn}） <input type=checkbox name=reply value=$cnt><a href=$cgi_url?step=del_reply&page=$DATA{'page'}&startpage=$DATA{'startpage'}&id=$parn>$SYSMSG{'gbook_msg_del'}</a> </td></tr>\n";
					}
					print "<tr><td bgcolor=#6699cc width=15%><font color=white><b>$SYSMSG{'gbook_msg_subject'}</font></td><td bgcolor=#6699cc><font color=white>$RETITLE{$parn}</font></td></tr>\n";
					print "<tr><td bgcolor=#aaefff width=15%><font color=darkred><b>$SYSMSG{'gbook_msg_content'}</b></font></td><td  bgcolor=#ccffee><font color=darkblue>$REPLYS{$parn}</font></td></tr>";
				}
			}
			print "</table></div></td></tr></table></div></fieldset><br>\n";
		}

		print "<center><fieldset><legend align=center><font color=red><b>$SYSMSG{'quick_jump'}</b></font></legend>";
		if ($GBCONF{'page_jump'} ne 'no') {
			$num = $DATA{'startpage'}-10;
			print "<a href=$cgi_url?step=edit_gb&page=$num&startpage=$num>$SYSMSG{'ten_up'}</a>\n" if ($DATA{'startpage'} > 10);
			$num = $DATA{'page'}-1;
			print "<a href=$cgi_url?step=edit_gb&page=$num&startpage=$DATA{'startpage'}>$SYSMSG{'sign_up'}</a>\n" if ($DATA{'page'} > 1);
			$pagecnt = $DATA{'startpage'}+9;
			$pagecnt = int($#GB/$GBCONF{'many'}+1) if (int($#GB/$GBCONF{'many'}+1) < $pagecnt);
			foreach ($DATA{'startpage'}..$pagecnt) {
				if ($DATA{'page'} == $_) {
					print "$_ ";
				} else {
					print "&nbsp;<a href=$cgi_url?step=edit_gb&page=$_&startpage=$DATA{'startpage'}> $_ </a>";
				}
			}
			$num = $DATA{'page'}+1;
			print "<a href=$cgi_url?step=edit_gb&page=$num&startpage=$DATA{'startpage'}>$SYSMSG{'sign_down'}</a>\n" if ($end < $#GB);
			$num = $DATA{'startpage'}+10;
			print "<a href=$cgi_url?step=edit_gb&page=$num&startpage=$num>$SYSMSG{'ten_down'}</a>\n" if ($DATA{'startpage'}+9 < int($#GB/$GBCONF{'many'}+1));
		}
		print "</center></fieldset><br>";
	}
	print "</form></BODY></HTML>";
	&foot('');
} elsif ($DATA{'step'} eq 'modify_gb' && $menu_id ne '') {
	($musr,$pwd,$muid,$mgid,$quo,$com,$gcos,$home,$shell) = getpwuid($menu_id);
	&read_gb_data("$home/$gb_data");
	&head($SYSMSG{'title_gbmgr'});
	print "<BR><CENTER>$SYSMSG{'gbook_title_edit'}</CENTER><hr size=1 color=red width=90%>\n";
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=step value=save_gb>\n";
	print "<input type=hidden name=page value=$DATA{'page'}>\n";
	print "<input type=hidden name=startpage value=$DATA{'startpage'}>\n";
	print "<input type=hidden name=id value=$DATA{'id'}>\n";
	print "<table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
	print "<tr><th align=right><font color=darkblue>$SYSMSG{'gbook_input_name'}</font>\n";
	print "<td><input type=text name=auth value=$GBAUTH{$DATA{'id'}}>\n";
	print "<tr><th align=right><font color=darkgreen>$SYSMSG{'gbook_input_email'}</font>\n";
	print "<td><input type=text name=email value=$GBMAIL{$DATA{'id'}}>\n";
	print "<tr><th align=right><font color=darkred>$SYSMSG{'gbook_input_mode'}</font><td>\n";
	if ($MODE{$DATA{'id'}} eq '1') {
		print "<input type=radio name=mode value=0 >$SYSMSG{'gbook_mode_public'}\n";
		print "<input type=radio name=mode value=1 checked>$SYSMSG{'gbook_mode_private'}\n";
	} else {
		print "<input type=radio name=mode value=0 checked>$SYSMSG{'gbook_mode_public'}\n";
		print "<input type=radio name=mode value=1>$SYSMSG{'gbook_mode_private'}\n";
	}
	print "<tr><th align=right><font color=red>$SYSMSG{'gbook_msg_subject'}</font>：\n";
	print "<td><input type=text name=subject value=$GBTITLE{$DATA{'id'}}>\n";
	print "<tr><th align=right><font color=blue>$SYSMSG{'gbook_msg_content'}</font>\n";
	print "<td><textarea rows=10 cols=50 name=body>$MESSAGES{$DATA{'id'}}</textarea>\n";
	print "<tr><td><td><input type=submit value=\" $SYSMSG{'gbook_edit_confirm'} \">\n";
	print "</table></form></center>";
	&foot('');
} elsif ($DATA{'step'} eq 'reply_gb' && $menu_id ne '') {
	($musr,$pwd,$muid,$mgid,$quo,$com,$gcos,$home,$shell) = getpwuid($menu_id);
	&read_gb_data("$home/$gb_data");
	&head($SYSMSG{'title_gbmgr'});
	print "<BR><CENTER>$SYSMSG{'gbook_title_reply'}</CENTER><hr size=1 color=red width=90%>\n";
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=step value=save_gb>\n";
	print "<input type=hidden name=page value=$DATA{'page'}>\n";
	print "<input type=hidden name=startpage value=$DATA{'startpage'}>\n";
	print "<input type=hidden name=parn value=$DATA{'id'}>\n";
	print "<input type=hidden name=auth value=\"$SYSMSG{'gbook_msg_owner_reply'}\">\n";
	print "<input type=hidden name=email value=\"$musr\@$HOST\">\n";
	print "<input type=hidden name=mode value=0>\n";
	print "<table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
	print "<tr><th align=right><font color=red>$SYSMSG{'gbook_msg_subject'}</font>：\n";
	print "<td><input type=text name=subject value=\"$SYSMSG{'gbook_msg_reply_subject'}$GBTITLE{$DATA{'id'}}\">\n";
	print "<tr><th align=right><font color=blue>$SYSMSG{'gbook_msg_content'}</font>\n";
	my $body = $MESSAGES{$DATA{'id'}};
	$body =~ s/<br>/\r\n>/g;
	print "<td><textarea rows=10 cols=50 name=body>>$body</textarea>\n";
	print "<tr><td><td><input type=submit value=\" $SYSMSG{'gbook_reply_confirm'} \">\n";
	print "</table></form></center>";
	&foot('');
} elsif ($DATA{'step'} eq 'save_gb' && $menu_id ne '') {
	($musr,$pwd,$muid,$mgid,$quo,$com,$gcos,$home,$shell) = getpwuid($menu_id);
	&read_gb_conf("$home/$gb_config");
	if ($DATA{'parn'} eq '') {
		&read_gb_data("$home/$gb_data");
		$cnt = $DATA{'id'};
		$GBDATE{$cnt} = time;
		$GBAUTH{$cnt} = $DATA{'auth'};
		$GBMAIL{$cnt} = $DATA{'email'};
		$GBTITLE{$cnt} = $DATA{'subject'};
		$DATA{'body'} =~ s/\r\n/<br>/g;
		$MESSAGES{$cnt} = $DATA{'body'};
		$MODE{$cnt} = $DATA{'mode'};
		&write_gb_data("$home/$gb_data");
	} else {
		&read_gb_reply("$home/$gb_reply");
		for ($cnt=1;$cnt<65535;$cnt++) {
			last if (!defined($REDATE{$cnt}));
		}
		$REIP{$cnt} = '0.0.0.0';
		$REPARN{$cnt} = $DATA{'parn'};
		$REDATE{$cnt} = time;
		$REAUTH{$cnt} = $DATA{'auth'};
		$REMAIL{$cnt} = $DATA{'email'};
		$RETITLE{$cnt} = $DATA{'subject'};
		$DATA{'body'} =~ s/\r\n/<br>/g;
		$REPLYS{$cnt} = $DATA{'body'};
		&write_gb_reply("$home/$gb_reply");
	}
	&gb_submailer($DATA{'email'},$DATA{'auth'},$DATA{'subject'},$DATA{'body'}) if ($GBCONF{'subscribe'} eq 'yes');
	print "Location: $cgi_url?step=edit_gb&page=$DATA{'page'}&startpage=$DATA{'startpage'}\n\n";
} elsif ($DATA{'step'} eq 'del_all_gb' && $menu_id ne '') {
	($musr,$pwd,$muid,$mgid,$quo,$com,$gcos,$home,$shell) = getpwuid($menu_id);
	if ($DATA{'del_all'} eq 'yes') {
		open (DATA, "> $home/$gb_data");
		close(DATA);
		open (DATA, "> $home/$gb_reply");
		close(DATA);
	}
	print "Location: $cgi_url?step=edit_gb\n\n";
} elsif ($DATA{'step'} eq 'del_checked_gb' && $menu_id ne '') {
	($musr,$pwd,$muid,$mgid,$quo,$com,$gcos,$home,$shell) = getpwuid($menu_id);
	&read_gb_data("$home/$gb_data");
	&read_gb_reply("$home/$gb_reply");
	@chkid=split(/,/,$DATA{'id'});
	foreach $myid (@chkid) {
		delete $GBDATE{$myid};
		foreach $cnt (keys %REDATE) {
				delete $REDATE{$cnt} if ($REPARN{$cnt} eq $myid);
		}
	}
	@chkid=split(/,/,$DATA{'reply'});
	foreach $myid (@chkid) {
		next if (!defined($REDATE{$myid}));
		delete $REDATE{$myid};
	}
	&write_gb_data("$home/$gb_data");
	&write_gb_reply("$home/$gb_reply");
	print "Location: $cgi_url?step=edit_gb&page=$DATA{'page'}&startpage=$DATA{'startpage'}\n\n";
} elsif ($DATA{'step'} eq 'del_gb' && $menu_id ne '') {
	($musr,$pwd,$muid,$mgid,$quo,$com,$gcos,$home,$shell) = getpwuid($menu_id);
	&read_gb_data("$home/$gb_data");
	delete $GBDATE{$DATA{'id'}};
	&write_gb_data("$home/$gb_data");
	&read_gb_reply("$home/$gb_reply");
	foreach $cnt (keys %REDATE) {
			delete $REDATE{$cnt} if ($REPARN{$cnt} eq $DATA{'id'});
	}
	&write_gb_reply("$home/$gb_reply");
	print "Location: $cgi_url?step=edit_gb&page=$DATA{'page'}&startpage=$DATA{'startpage'}\n\n";
} elsif ($DATA{'step'} eq 'del_reply' && $menu_id ne '') {
	($musr,$pwd,$muid,$mgid,$quo,$com,$gcos,$home,$shell) = getpwuid($menu_id);
	&read_gb_reply("$home/$gb_reply");
	delete $REDATE{$DATA{'id'}};
	&write_gb_reply("$home/$gb_reply");
	print "Location: $cgi_url?step=edit_gb&page=$DATA{'page'}&startpage=$DATA{'startpage'}\n\n";
} elsif ($DATA{'step'} eq 'gb_subscribe' && $menu_id ne '') {
	($musr,$pwd,$muid,$mgid,$quo,$com,$gcos,$home,$shell) = getpwuid($menu_id);
	&read_gb_conf("$home/$gb_config");
	&read_gb_subscribe("$home/$gb_subscribe");
	&head($SYSMSG{'title_gbsubmgr'});
	print "<BR><CENTER>$SYSMSG{'sign_left'}<a href=$cgi_url?step=edit_gb>$GBCONF{'title'}</a>$SYSMSG{'sign_right'}</CENTER><hr size=1 color=red width=90%>\n";
	print "<CENTER><form method=post>\n";
	print "<input type=hidden name=step value=gb_addnew>\n";
	print "<input type=text name=email><input type=submit value=\" $SYSMSG{'gbook_add_user_confirm'} \"></form></center>";
	if (defined $SUBSCRIBE{'0'}) {
		print "<center><form method=post>\n";
		print "<input type=hidden name=step value=gb_unsubscribe>\n";
		print "<table border=6 style=font-size:11pt cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
		print "<tr><th align=right><font color=red>$SYSMSG{'gbook_del_user'}</font>\n";
		print "<th align=center><font color=red>$SYSMSG{'gbook_user_email'}</font>\n";
		foreach $cnt (sort values %SUBSCRIBE) {
			print "<tr><td align=right><input type=checkbox name=email value=$cnt>\n";
			print "<td align=left>$cnt</tr>\n";
		}
		print "<tr><td colspan=2><center><input type=submit value=\" $SYSMSG{'gbook_del_user_confirm'} \"></center>\n";
		print "</table></form></center>";
	}
	&foot('');
} elsif ($DATA{'step'} eq 'gb_addnew' && $menu_id ne '') {
	($musr,$pwd,$muid,$mgid,$quo,$com,$gcos,$home,$shell) = getpwuid($menu_id);
	if ($DATA{'email'} ne '') {
		&read_gb_subscribe("$home/$gb_subscribe");
		$SUBSCRIBE{'new'} = $DATA{'email'};
		&write_gb_subscribe("$home/$gb_subscribe");
	}
	print "Location: $cgi_url?step=gb_subscribe\n\n";
} elsif ($DATA{'step'} eq 'gb_unsubscribe' && $menu_id ne '') {
	($musr,$pwd,$muid,$mgid,$quo,$com,$gcos,$home,$shell) = getpwuid($menu_id);
	if ($DATA{'email'} ne '') {
		&read_gb_subscribe("$home/$gb_subscribe");
		@email = split(/,/,$DATA{'email'});
		foreach $line (@email) {
			foreach $i (keys %SUBSCRIBE) {
				delete $SUBSCRIBE{$i} if ($SUBSCRIBE{$i} eq $line);
			}
		}
		&write_gb_subscribe("$home/$gb_subscribe");
	}
	print "Location: $cgi_url?step=gb_subscribe\n\n";
}

}
