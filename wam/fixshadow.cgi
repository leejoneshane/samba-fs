#!/usr/bin/perl -U

$tmp_shadow='shadow.tmp';

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

sub read_shadow {
	open (SHD, "< $CONFIG{'shadow'}");

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
	my($usr, $mi, $ma, $w, $d, $p, $i, $e, $w, $f, $sstr);
	open(TMPS, "> $tmp_shadow");
	foreach $usr (keys %UNAME) {
		$p = $PASS{$usr};
		$d = $SDAY{$usr};
		$mi = $SMIN{$usr};
		$ma = $SMAX{$usr};
		$w = $SWARN{$usr};
		$i = $SINACT{$usr};
		$e = $SEXP{$usr};
		$f = $SFLAG{$usr};
		$sstr = join ':', $usr, $p, $d, $mi, $ma, $w, $i, $e, $f;
		print TMPS "$sstr";
	}
	close(TMPS);
}

#***********************************************************************************
# MAIN
#***********************************************************************************

$CONFIG{'shadow'} = '/etc/shadow';
$CONFIG{'passwd'} = '/etc/passwd';
&read_shadow;
&read_passwd;
foreach $usr (sort keys %UNAME) {
    $SEXP{$usr} = '-1';
}
&write_shadow;
