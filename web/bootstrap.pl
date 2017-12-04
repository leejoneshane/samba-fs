#!/usr/bin/perl -U
# 程式：線上帳號管理程式
# 版次：3
# 修改日期：2017/11/27
# 程式設計：李忠憲 (hp2013@ms8.hinet.net)
# 使用本程式必須遵守以下版權規定：
# 本程式遵守GPL 開放原始碼之精神，但僅授權教育用途或您個人使用
# 此檔頭為本程式版權的一部份，請勿將此檔頭移除
# program: WAM(Web-Base Accounts Manager)
# author: Shane Lee(hp2013@ms8.hinet.net)
# This Software is Open Source, but for personal use only.
# This title is a part of License. You can NOT remove it.
#
use strict;
use warnings;
use utf8;
use feature ':5.10';
use Mojolicious;

$config = "./wam.conf";
$gconfig = "./group.conf";
$share_conf = "./share.conf";
$tmp_album = "./message.tmp";
$lang_base = "/web/lang";
##############################################################################

$zip_test = `whereis zip`;
$zip_exist = 0;
$zip_exist = 1 if ($zip_test =~ /^zip: .+/);
$itoa64 = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
$base64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

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

sub read_smbconf {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = {};
  $self->{_global} = {};
  $self->{_section} = {};
  eval
  {
    while(<DATA>)
    {
      chomp;
      next if /^#/;
      my ($st,$vers,$cmd) = split(/:/);
      if($cmd && $vers && $st)
      {
        chomp($cmd);
        $self->{_VALID}->{$st}->{"v$vers"}->{$cmd} = "1";
      }
      last if /__END__/;
    }
  };

  bless ($self, $class);
  if(@_)
  {
      $self->load(shift);
  }

  return $self;
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

#***********************************************************************************
# MAIN
#***********************************************************************************
$today = int(time / 86400);
$> = 0;
$) = 0;

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
&check_referer;
&get_form_data;
&check_password;

helper is_admin => sub {
  my $c = shift;
  $admin='0';
  foreach $acc (split(/,/,$GUSRS{'admin'})) {
  	$admin='1' if ($acc =~ /^$c->session('user_id')$/);
  }
  return $admin;
}

get '/relogon' => sub {
  my $c = shift;
  $c->session(expires => 1);
} => 'logon_form';

post '/logon' => sub {
  my $c = shift;
  # Check CSRF token
  my $validation = $c->validation;
  return $c->render(text => 'Bad CSRF token!', status => 403)
  if $validation->csrf_protect->has_error('csrf_token');

  if ($c->basic_auth(
    "WAM" => {
      host => '127.0.0.1',
      basedn => 'dc=cc,dc=tp,dc=edu,dc=tw',
      binddn => "uid=$c->req->param('user'),ou=People,dc=cc,dc=tp,dc=edu,dc=tw",
      bindpw => "$c->req->param('password')",
      filter => 'objectClass=sambaSamAccount'
    }
  )) {
    $c->session('user_id' => $c->req->param('user'));
    $c->session('passed' => 1);
    $c->session->store();
    $c->redirect_to('/');
  } else {
    &err_account;
    $c->redirect_to('/relogon');
  }
}

under sub {
  my $c = shift;
  return 1 if ($c->session('passed'));
  $c->render(text => 'You Must login first!', status => 403);
}

get '/' = 'frames';
get '/show_left' = 'left';
get '/show_right' = 'right';

if ($DATA{'step'} eq 'config' && $admin eq '1') {
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
}

__DATA__

@@ frames.html.ep
% charset $SYSMSG{'charset'}
<head><meta http-equiv=Content-Type content="<%= charset %>">
<META HTTP-EQUIV=Pargma CONTENT=no-cache>
<title>WAM</title></head>
<FRAMESET COLS="130,*"  framespacing=0 border=0 frameborder=0>
<FRAME SRC=/show_left NAME=wam_left marginwidth=0 marginheight=0 noresize>
<FRAME SRC=/show_right NAME=wam_main>
</FRAMESET>

@@ left.html.ep
% charset $SYSMSG{'charset'}
% help_root $SYSMSG{'help_root'}
% help $SYSMSG{'help'}
% config $SYSMSG{'set_config'}
% set_admin $SYSMSG{'set_wam_manager'}
% filemanager $SYSMSG{'file_manager'}
% sharemanager $SYSMSG{'share_folder'}
% group $SYSMSG{'group_add'}
% account $SYSMSG{'account_add_one'}
% delete $SYSMSG{'del_group_account'}
% autoadd $SYSMSG{'autoadd_account'}
% upload $SYSMSG{'add_account_from_file'}
% resetpw $SYSMSG{'reset_passwd'}
% chgpw $SYSMSG{'change_passwd'}
% struct $SYSMSG{'view_struct'}
% check $SYSMSG{'check_account'}
% trace $SYSMSG{'trace_account'}
% logout $SYSMSG{'logout'}
<head><meta http-equiv=Content-Type content="<%= charset %>">
<META HTTP-EQUIV=Pargma CONTENT=no-cache>
<title>WAM</title>
<base target=wam_main></head>
<body link=#FFFFFF vlink=#ffffff alink=#FFCC00  style="SCROLLBAR-FACE-COLOR: #ddeeff; SCROLLBAR-HIGHLIGHT-COLOR: #ffffff; SCROLLBAR-SHADOW-COLOR: #ABDBEC; SCROLLBAR-3DLIGHT-COLOR: #A4DFEF; SCROLLBAR-ARROW-COLOR: steelblue; SCROLLBAR-TRACK-COLOR: #DDF0F6; SCROLLBAR-DARKSHADOW-COLOR: #9BD6E6">
<table style="font-size: 11 pt; border-collapse:collapse" height=100% width=100% border=1 cellspadding=2 bordercolorlight=#808080 bordercolordark=#C0C0C0 cellpadding=2 align=left bordercolor=#FFFFFF cellspacing=1>;
<tr><td align=center bgcolor=#3E7BB9 width=100% height=100%><b><font color=#FFFFFF>WAM</font></b></td></tr>
% if (is_admin()) {
<tr><td align=center bgColor=#6699cc width=100% height=100%><a href="/help/help_root.htm" style="text-decoration: none"><%= help_root %></a></td></tr>
<tr><td align=center bgcolor=#FFCC00 width=100% height=100%><b>$SYSMSG{'submenu_system'}</b></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/config" style="text-decoration: none"><%= config %></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/setadmin" style="text-decoration: none"><%= set_admin %></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/filesmgr" style="text-decoration: none"><%= filemanager %></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/sharemgr" style="text-decoration: none"><%= sharemanager %></a></td></tr>
<tr><td align=center bgColor=#FFCC00 width=100% height=100%><b>$SYSMSG{'submenu_account'}</b></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/addgrp" style="text-decoration: none"><%= group %></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/addone" style="text-decoration: none"><%= account %></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/delete" style="text-decoration: none"><%= delete %></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/autoadd" style="text-decoration: none"><%= autoadd %></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/upload" style="text-decoration: none"><%= upload %></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/resetpw" style="text-decoration: none"><%= resetpw %></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/chgpw" style="text-decoration: none"><%= chgpw %></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/struct" style="text-decoration: none"><%= struct %></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/check" style="text-decoration: none"><%= check %></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/trace" style="text-decoration: none"><%= trace %></a></td></tr>
<tr><td align=center bgColor=#ffcc00 width=100% height=100%><b><%= logout %></td></tr>
<tr><td align=center bgColor=#3E7BB9 width=100% height=100%><a href="/relogon" target=_top style="text-decoration: none"><%= logout %></a></td></tr>
% } else {
<tr><td align=center bgColor=#FFCC00 width=100% height=100%><a href="/help/help_user.htm" style="text-decoration: none"><b><font color=black><%= help %></b></font></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/filesmgr" style="text-decoration: none"><%= filemanager %></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/chgpw" style="text-decoration: none"><%= chgpw %></a></td></tr>
<tr><td align=center bgColor=#ffcc00 width=100% height=100%><b><%= logout %></td></tr>\n";
<tr><td align=center bgColor=#3E7BB9 width=100% height=100%><a href="/relogon" target=_top style="text-decoration: none"><%= logout %></a></td></tr>
% }
</table></body></html>

@@ right.html.ep
% title $SYSMSG{'logon'}
% charset $SYSMSG{'charset'}
% logon_alt $SYSMSG{'logon_alt'}
% layout 'default'
<center><a href="javascript:onclick=alert('<%= logon_alt %>')" border=0><img align=absmiddle src=/img/wam.gif border=0></a>

@@ logon_form.html.ep
% title $SYSMSG{'logon'}
% charset $SYSMSG{'charset'}
% font $SYSMSG{'variable_font'}
% help_root $SYSMSG{'help_root'}
% help $SYSMSG{'help'}
% logon_alt $SYSMSG{'logon_alt'}
% logon_name $SYSMSG{'loginname'}
% logon_pass $SYSMSG{'loginpasswd'}
% logon $SYSMSG{'logon'}
% prev_page $SYSMSG{'backto_prev_page'}
% layout 'default'
<center><a href="javascript:onclick=alert('<%= logon_alt %>')" border=0><img align=absmiddle src=/img/wam.gif border=0></a>
%= form_for logon => begin
%= csrf_field
<table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>
<tr><th align=left>
%= label_for user => logon_name
：<td>
%= test_field 'user', maxlength => 20, size => 20
<th align=right>
%= label_for password => logon_pass
：<td>
%= password_field 'password', size => 20
<td  colspan=2 align=center>
%= submit_button, value => logon
</table>
% end
</center>

@@ layouts/default.html.ep
<html>
<head>
<meta http-equiv="Content-Type" content="<%= charset %>">
<META HTTP-EQUIV="Pargma" CONTENT="no-cache">
<title><%= title %></title>
<link rel='stylesheet' type='text/css' href='test.css'>
<script>
  function init() { thisform = document.myform; }
  function chk_empty(item) { if ((item.value=="") || (item.value.indexOf(" ")!=-1) ) { return true; } }
  function chggrp() { thisform.grp.value = thisform.grps.options[thisform.grps.selectedIndex].value; }
  function mysubmit(myaction) { thisform.action.value = myaction; thisform.submit();}
  function rest(id) {
    if (id==0) { thisform.grp.value = ""; }
    if (id==1) { thisform.user.value = ""; }
    if (id==2) { thisform.grp.value = ""; thisform.user.value = ""; }
    if (id==3) { thisform.pwd.value = ""; thisform.pwd2.value = ""; }
  }
</script>
</head>
<body onload=init() style='font-size:11pt' bgcolor=#ffffff><center>
<font size=+2 face="<%= font %>" color=darkblue><%= title %> </font> [
% if (is_admin) {
<a href=/help/help_root.htm target=_blank><%= help_root %></a>
% } else {
<a href=/help/help_user.htm target=_blank><%= help %></a>
% }
 ]</center>]
<%= content %>
<hr color=#FF0000><center><font size=3>
【<a href="javascript:history.go(-1)"><img align=absmiddle src=/img/upfolder.gif border=0><%= prev_page %></a>  】
</font></center>
</body>
</html>

@@ img/wam.gif (base64)
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

@@ img/upfolder.gif (base64)
R0lGODlhFwAWAKIAAAcHB///B4d/h8e/x////wAAAAAAAAAAACwAAAAAFwAWAAADYki63E6AjEmrtSLevbPk4ORVQFmGwzgBwdAGQKiadH1Ss6u/+xCLGh8vxnv9UkGi71T04ZKtWg/2/ChhzWh1NZy6jjmjVAu0ZqfgpLeZttrebRRIJb/Q6xWPYM/v+/9wgW8JADs=
