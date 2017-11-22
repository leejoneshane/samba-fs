#!/usr/bin/perl -U

$config = "./wam.conf";
$gconfig = "./group.conf";
$tmp_index = "./index.tmp";
$tmp_passwd = "./passwd.tmp";
$tmp_shadow = "./shadow.tmp";
$tmp_group = "./group.tmp";
$tmp_gshadow = "./gshadow.tmp";
@referers = ('localhost','stuwork.meps.tp.edu.tw','163.21.228.69','172.22.1.69','127.0.0.1');
##############################################################################

$itoa64 = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
$base64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
$HOST=`/bin/hostname`;
$HOST=~ s/\n//g;
@DOMAIN = split(/./,$HOST);
$ii = 0;
foreach $DN (@DOMAIN) {
	$DOMAIN[$ii]=".$DOMAIN[$ii]" if ($DN ne '');
	$ii++;
}
$PORT="12000";
$| = 1;
$today = int(time / 86400);
$err = 0;

use MD5;

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
    my $ret = '';
    my $n = 8, $i;
    while (--$n >= 0) {
	$i = rand;
	$ret .= substr($itoa64, int($i*64), 1);
    }
    $ret;
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
	my ($uid,@uid,@addrs);

	$addr = $ENV{'REMOTE_ADDR'};
	$url = $ENV{'HTTP_REFERER'};
	if ($url =~ m|https?://([^/]*)$DOMAIN[1]$DOMAIN[2]$DOMAIN[3]/~([\w.]+)/(.*)|i) {
		$user = $2;
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
		&head($SYSMSG{'title_system_info'});
		print "<center>$SYSMSG{'msg_acl_warn'}</center>";
		exit 0;
	}
}

sub get_form_data {
	my(@parts, @pairs, $buffer, $pair, $name, $value, $bound, $getfilename, $fname, $filename, $tmp1, $tmp2, $temp, @cookies);
	if($ENV{'REQUEST_METHOD'} =~ /get/i) {
		return;
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
	open (CFG, "< $config") || &err('err_cannot_open_config');
	while ($line = <CFG>) {
		my($name, $value) = split(/:/, $line);
		$value =~ s/\n//g;
		$CONFIG{$name} = $value;
	}
	close(CFG);
}

sub read_gconf {
	return if (!(-e $gconfig));
	open (GCFG, "< $gconfig") || &err('err_cannot_open_gconfig');
	while ($line = <GCFG>) {
		my($name, $value) = split(/:/, $line);
		$value =~ s/\n//g;
		$GCONF{$name} = $value;
	}
	close(GCFG);
}

sub write_gconf {
	my($grp, $home);
	open(GCFG, "> $gconfig") || &err('err_cannot_open_gconfig');
	foreach $grp (keys %GCONF) {
		$home = $GCONF{$grp};
		print GCFG "$grp:$home\n" if ($grp ne '' && $home ne '');
	}
	close(GCFG);
}

sub read_group {
	open (GRP, "< $CONFIG{'group'}") || &err('err_cannot_open_group');

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
	open(TMPG, "> $tmp_group") || &err('err_cannot_open_temp');
	foreach $grp (keys %GNAME) {
		$gid = $GNMID{$grp};
		$gig = $GIG{$grp};
		$gu = $GUSRS{$grp};
		$gstr = join ':', $grp, $gig, $gid, $gu;
		print TMPG "$gstr";
	}
	close(TMPG);
	open(TMPG, "< $tmp_group") || &err('err_cannot_open_temp');
	open (GRP, "> $CONFIG{'group'}") || &err('err_cannot_open_group');
	flock GRP, $LOCK_EX;
	print GRP <TMPG>;
	flock GRP, $LOCK_UN;
	close(GRP);
	close(TMPG);
	unlink($tmp_group);
}

sub read_passwd {
	open (PWD, "< $CONFIG{'passwd'}") || &err('err_cannot_open_passwd');

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
	open(TMPP, "> $tmp_passwd") || &err('err_cannot_open_temp');
	foreach $uid (sort keys %UIDS) {
		$n = $UIDNM{$uid};
		$g = $UGID{$uid};
		$gec = $GECOS{$uid};
		$h = $HOME{$uid};
		$sh = $SHELL{$uid};
		$pstr = join ':', $n, 'x', $uid, $g, $gec, $h, $sh;
		print TMPP "$pstr";
	}
	close(TMPP);
	open(TMPP, "< $tmp_passwd") || &err('err_cannot_open_temp');
	open (PWD, "> $CONFIG{'passwd'}") || &err('err_cannot_open_passwd');
	flock PWD, $LOCK_EX;
	print PWD <TMPP>;
	flock PWD, $LOCK_UN;
	close(PWD);
	close(TMPP);
	unlink($tmp_passwd);
}

sub read_shadow {
	open (SHD, "< $CONFIG{'shadow'}") || &err('err_cannot_open_shadow');

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
	open(TMPS, "> $tmp_shadow") || &err('err_cannot_open_temp');
	foreach $uid (sort keys %UIDS) {
		$usr = $UIDNM{$uid};
		$p = $PASS{$usr};
		$p = unix_md5_crypt($usr,&rnd64) if ($p eq "");
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
	open(TMPS, "< $tmp_shadow") || &err('err_cannot_open_temp');
	open (SHD, "> $CONFIG{'shadow'}") || &err('err_cannot_open_shadow');
	flock SHD, $LOCK_EX;
	print SHD <TMPS>;
	flock SHD, $LOCK_UN;
	close(SHD);
	close(TMPS);
	unlink($tmp_shadow);
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
	my($usr, $grp, $pwd, $desc) = @_;
	my($lvl, @lvls, $home, $gn);
	&err('err_account_has_been_used') if (defined($UNAME{$usr}));
	&err('err_account_is_empty') if ($usr eq '');
	&err('err_group_is_empty') if ($grp eq '');
	$gn = $grp;
	$home = "$CONFIG{'base_dir'}/$grp" if ($CONFIG{'home_nest'} eq 'yes');
	&add_grp($grp,$home) if (!defined($GNAME{$grp}));
	$uid = &get_uid;
	$g = $GNMID{$gn};
	$h = $GCONF{$gn};
	$h = '/home' if ($h eq '');
	$UIDS{$uid} ++;
	$UNAME{$usr} ++;
	$UNMID{$usr} = $uid;
	$UIDNM{$uid} = $usr;
	$UGID{$uid} = $g;
	$GECOS{$uid} = '';
	$HOME{$uid} = ($CONFIG{'home_nest'} eq 'yes') ? "$h/$usr" : "$CONFIG{'base_dir'}/$usr";
	$SHELL{$uid} = $CONFIG{'shell'}."\n";
	$PASS{$usr} = unix_md5_crypt($pwd,&rnd64);
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
	$sreqt{$uid} = join ':', $usr, "x", $uid, $g, $desc, $HOME{$uid}, $SHELL{$uid};
	$sreqs{$uid} = join ':', $usr, $PASS{$usr}, $SDAY{$usr}, $SMIN{$usr}, $SMAX{$usr}, $SWARN{$usr},
				 $SINACT{$usr}, $SEXP{$usr}, $SFLAG{$usr};
}

sub add_grp {
	my($grp,$home) = @_;
	my($gid);
	$gid = &get_gid;
	$GIDS{$gid} ++;
	$GNAME{$grp} ++;
	$GNMID{$grp} = $gid;
	$GIDNM{$gid} = $grp;
	$GIG{$grp} = "";
	$GUSRS{$grp} = "\n";
	$GCONF{$grp} = $home;
}

sub smb_passwd {
	my($usr, $pwd) = @_;
	open(SMB,"|$CONFIG{'smbprog'} -a $usr")  || &err_disk("$SYSMSG{'err_cannot_open'} $CONFIG{'smbprog'} $SYSMSG{'program'}<br>");
	print SMB "$pwd\n";
	print SMB "$pwd\n";
	close(SMB);
}

sub make_index {
	open(IDX, "> $tmp_index") || &err('err_cannot_open_homepage_sample');
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
	print IDX "$SYSMSG{'msg_you_are'} <a href=http://HOSTNAME:PORT/wam.cgi?step=set_count><img align=absmiddle src=\"http://HOSTNAME:PORT/count.cgi\" border=\"0\"></a>$SYSMSG{'msg_visited'}</font>\n";
	print IDX "<p><b><a href=\"http://HOSTNAME:PORT/gbook.cgi\">$SYSMSG{'msg_my_gbook'}</a><br>\n";
	print IDX "</b><hr size=\"1\" color=\"#FF0000\"><span style=\"background-color: #007BB7\"><font size=\"5\" color=\"#FFFFFF\"><b>\n";
	print IDX "$SYSMSG{'msg_hi'}&nbsp;</b></font></span>\n";
	print IDX "<p><img src=http://HOSTNAME:PORT/img/dingdong0.gif>\n";
	print IDX "<a href=\"http://HOSTNAME:PORT/mail.cgi?user=USER\">$SYSMSG{'msg_my_email'}:USER\@HOSTNAME</a></p>\n";
	print IDX "<p><a href=\"http://HOSTNAME:PORT/\">$SYSMSG{'msg_admin'}</a></p><hr color=\"#FF0000\"><p></center></p></body></html>\n";
	close(IDX);
}

sub make_passwd {
	my($uid, $n, $gn, $g, $d, $p, $pstr, $sstr, $l, $h, @lvls, $lvl, $line, $exp);
	open(TMPP, "> $tmp_passwd") || &err('err_cannot_open_temp');
	open(TMPS, "> $tmp_shadow") || &err('err_cannot_open_temp');

	&write_group;
	&write_gconf;
	foreach $uid (sort keys %sreqn) {
		print TMPP "$sreqt{$uid}";
		print TMPS "$sreqs{$uid}";
	}
	close(TMPP);
	close(TMPS);

	open(TMPP, "< $tmp_passwd") || &err('err_cannot_open_temp');
	open (PWD, ">> $CONFIG{'passwd'}") || &err('err_cannot_open_passwd');

	flock PWD, $LOCK_EX;
	print PWD <TMPP>;
	flock PWD, $LOCK_UN;
	close(PWD);
	close(TMPP);

	open(TMPS, "< $tmp_shadow") || &err('err_cannot_open_temp');
	open (SHD, ">> $CONFIG{'shadow'}") || &err('err_cannot_open_shadow');
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
			system("mkdir -p $HOME{$uid}/$CONFIG{'home_dir'}");
			if (-e $tmp_index) {
				open(IDX, "< $tmp_index");
				my @buffer = <IDX>;
				close(IDX);
				foreach $line (@buffer) {
					$line =~ s/USER/$UIDNM{$uid}/g;
					$line =~ s/HOSTNAME/$HOST/g;
					$line =~ s/PORT/$ENV{'SERVER_PORT'}/g;
				}
				open(IDX, "> $HOME{$uid}/$CONFIG{'home_dir'}/index.htm");
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
	%sreqn = ();
	%sreqg = ();
	%sreqp = ();
	%sreqt = ();
	%sreqs = ();
}

sub err {
	my($errno) = @_;
	$err = 1;
	if ($errno eq 'err_group_is_empty') {
		$errmsg = '找不到您所隸屬的群組，因此帳號無法建立，請告知電腦老師處理！';
	}
	if ($errno eq 'err_account_is_empty') {
		$errmsg = '您的帳號尚未輸入，因此無法建立，請重新提出申請或告知電腦老師處理！';
	}
	if ($errno eq 'err_account_has_been_used') {
		$errmsg = '您的帳號與別人重複，因此無法建立，請重新提出申請或告知電腦老師處理！';
	}
	if ($errno eq 'err_cannot_open_homepage_sample') {
		$errmsg = '網頁範例檔無法讀取，因此無法為您建立首頁，請告知電腦老師處理！';
	}
	if ($errno eq 'err_cannot_open_temp') {
		$errmsg = '無法建立暫存檔案，帳號建立失敗，請告知電腦老師處理！';
	}
	if ($errno eq 'err_cannot_open_passwd') {
		$errmsg = '無法開啟系統帳號檔，帳號建立失敗，請告知電腦老師處理！';
	}
	if ($errno eq 'err_cannot_open_shadow') {
		$errmsg = '無法開啟系統密碼檔，帳號建立失敗，請告知電腦老師處理！';
	}
	if ($errno eq 'err_cannot_open_group') {
		$errmsg = '無法開啟系統群組檔，帳號建立失敗，請告知電腦老師處理！';
	}
	if ($errno eq 'err_cannot_open_gconfig') {
		$errmsg = '無法開啟群組設定檔，帳號建立失敗，請告知電腦老師處理！';
	}
	if ($errno eq 'err_cannot_open_config') {
		$errmsg = '無法開啟系統設定檔，帳號建立失敗，請告知電腦老師處理！';
	}
	print "Location: http://www2.meps.tp.edu.tw/msg.asp?msg=$errmsg\n\n";
	exit 0;
}
#***********************************************************************************
# MAIN
#***********************************************************************************
&check_referer;
&read_conf;
&read_shadow;
&read_passwd;
&read_gconf;
&read_group;
&get_form_data;
&addone($DATA{'account'}, $DATA{'group'}, $DATA{'passwd'}, $DATA{'name'});
&make_passwd;
print "Location: $DATA{'recall'}\n\n";
