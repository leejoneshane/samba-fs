#!/usr/bin/perl -U

$tmp_passwd='passwd.tmp';

sub read_passwd {
	open (PWD, "< $CONFIG{'passwd'}");

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

sub read_group {
	open (GRP, "< $CONFIG{'group'}");

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

sub write_passwd {
	my($uid, $n, $gn, $g, $gec, $h, $pstr, $sh);
	open(TMPP, "> $tmp_passwd");
	foreach $uid (sort keys %UIDS) {
		$n = $UIDNM{$uid};
		$g = $UGID{$uid};
		$gec = $GECOS{$uid};
		$h = $HOME{$uid};
		$sh = $SHELL{$uid};
		$pstr = join ':', $n, "x", $uid, $g, $gec, $h, $sh;
		print TMPP "$pstr";
	}
	close(TMPP);
	open(TMPP, "< $tmp_passwd");
	open (PWD, "> $CONFIG{'passwd'}");
	flock PWD, $LOCK_EX;
	print PWD <TMPP>;
	flock PWD, $LOCK_UN;
	close(PWD);
	close(TMPP);
	unlink($tmp_passwd);
}

#***********************************************************************************
# MAIN
#***********************************************************************************

$CONFIG{'passwd'} = '/etc/passwd';
$CONFIG{'group'} = '/etc/group';
&read_group;
&read_passwd;
foreach $uid (sort keys %UIDS) {
	$usr = $UIDNM{$uid};
	$gid = $UGID{$uid};
	$grp = $GIDNM{$gid};
	if (-T '/var/spool/mail/'.$usr) {
		system('chown '.$usr.':mail '.'/var/spool/mail/'.$usr);
	}
}
#&write_passwd;
