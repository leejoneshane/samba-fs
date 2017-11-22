#!/usr/bin/perl -U

$config = "./wam.conf";
$gconfig = "./group.conf";
@special =
('shutdown','halt','operator','gdm','ftpadm','mysql','sync','samba','ftp','sendmail','adm','bin','console','daemon','dip','disk','floppy','ftp','games','gopher','kmem','lp','mail','man','mem'
,'news','nobody','popusers','postgres','pppusers','slipusers','slocate','sys','tty','utmp','uucp','wheel','xfs');
##############################################################################

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

sub read_conf {
	return if (!(-e $config));
	open (CFG, "< $config") || &err_disk("無法開啟帳號組態檔<br>");
	while ($line = <CFG>) {
		my($name, $value) = split(/:/, $line);
		$value =~ s/\n//g;
		$CONFIG{$name} = $value;
	}
	close(CFG);
}

sub write_gconf {
	my($grp, $home);
	open(GCFG, "> $gconfig") || &err_disk("群組組態檔無法開啟.<br>");
	foreach $grp (keys %GCONF) {
		$home = $GCONF{$grp};
		print GCFG "$grp:$home\n" if ($grp ne '' && $home ne '');
	}
	close(GCFG);
}

sub read_group {
	open (GRP, "< $CONFIG{'group'}") || &err_disk("無法開啟系統群組檔<br>");

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

sub read_passwd {
	open (PWD, "< $CONFIG{'passwd'}") || &err_disk("無法開啟系統密碼檔.<br>");

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

#***********************************************************************************
# MAIN
#***********************************************************************************

&read_conf;
&read_passwd;
&read_group;

	foreach $uid (sort keys %UIDS) {
		$usr = $UIDNM{$uid};
		next if (int($uid)<500);
		next if (&check_special($usr) eq 1);
		$gid = $UGID{$uid};
		$grp = $GIDNM{$gid};
		if ($GCONF{$grp} eq '') {
			my(@temp) = split(/\//,$HOME{$uid});
			pop(@temp);
			$home = join('/',@temp);
			$GCONF{$grp} = $home;
		}
	}

&write_gconf;
