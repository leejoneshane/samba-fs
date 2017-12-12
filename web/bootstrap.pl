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
use Digest::SHA1;
use Mojolicious::Sessions;

my $app = shift;
my $s = Mojolicious::Sessions->new;
$s->default_expiration(3600);
my $c = $app->plugin('Config');
$c->{admin} => 'admin' unless defined $c->{admin};
my %admins = map { $_ => 1 } split(/,/, $c->{admin});
$app->plugin('I18N')->languages('tw');
my $share_conf = "/etc/samba/example.conf";
my $lang_base = "/web";
##############################################################################
my $zip_exist = 0;
$zip_exist = 1 if (`whereis zip` =~ /^zip: .+/);
my $itoa64 = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
my $today = int(time / 86400);
my %DATA = {};
my %CONFIG = {};
my %SYSMSG = {};
my @LANGS = [];

sub ldap_ssha {
  my $pw = @_;
  '{SSHA}' . sha1_base64($pw . rnd64('all'));
}

sub rnd64 {
  my $range = @_;
  my $ret = '';
  my $n = 8;
  my $i;
  $range = $CONFIG{'passwd_range'}  unless defined $range;
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

sub err_disk {
	my($msg) = @_;
	&head("$app->l('title_system_info')");
	print "<center><table border=0 style=font-size:11pt><tr><td><p><font color=blue face=$app->l('variable_font') size=5>$app->l('err_disk_failue'}</font></p>\n";
	print $msg;
	print '<ul>';
	print "<li>$app->l('msg_if_disk_busy')<a href=\"javascript:history.go(-1)\"><img align=absmiddle src=/img/upfolder.gif border=0>  $app->l('backto_prev_page'}</a>$app->l('msg_try_later')";
	print "<li>$app->l('msg_if_config_incorrect')<a href='/config'>$app->l('msg_setup_config')</a>";
	print "<li>$app->l('msg_check_disk')";
	print '</ul>';
	print '<hr color="#FF0000">';
	print "<center><a href=\"javascript:history.go(-1)\"><img align=absmiddle src=/img/upfolder.gif border=0>  $app->l('backto_prev_page')</a></center>";
	print '</table></center></body>';
	print "</html>";
	exit 0;
}

sub err_account {
	&head("$app->l('title_system_info')");
	print "<center><table border=0 style=font-size:11pt><tr><td><p><font color=blue face=$app->l('variable_font') size=5>$app->l('err_check_account')</font></p>\n";
	print "$app->l('msg_please_check'}";
	print '<ul>';
	print "<li>$app->l('msg_if_misstype')<a href=\"javascript:history.go(-1)\"><img align=absmiddle src=/img/upfolder.gif border=0>  $app->l('backto_prev_page')</a>$app->l('msg_reinput')";
	print "<li>$app->l('msg_just_for_user')";
	print '</ul>';
	print '<hr color="#FF0000">';
	print "<center><a href=\"javascript:history.go(-1)\"><img align=absmiddle src=/img/upfolder.gif border=0>  $app->l('backto_prev_page')</a></center>";
	print '</table></center></body>';
	print "</html>";
	exit 0;
}

sub get_lang_list {
	opendir (DIR, "$lang_base") || &err_disk("磁碟錯誤，語言套件目錄無法讀取。disk error! can't open language defined<br>");
	@LANGS=readdir(DIR);
	close(DIR);
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

sub check_group {
	my($grp, $f1) = @_;
	my($warning, $f2);
	$f2 = defined($GNAME{$grp});
	if ($f1 eq '1' && $f2) {
		print "<center><font color=blue face=$app->l('variable_font') size=5> $grp $app->l('err_group_exist')</font></center><br>";
		$warning ++;
	}
	if ($f1 eq '0' && !$f2) {
		print "<center><font color=blue face=$app->l('variable_font') size=5> $grp $app->l('err_group_not_exist')</font></center><br>";
		$warning ++;
	}
	if ($warning != 0) {
		if ($f1 eq '1') {
			print "<hr><center><table border=0 style=font-size:11pt><tr><td><p><font color=blue face=$app->l('variable_font') size=5>$app->l('err_group_exist')</font></p>\n";
			print "$app->l('err_cannot_continue_becouse') <b>$warning</b> $app->l('err_group_exist')<br>";
			print '<ul>';
			print "<li>$app->l('msg_delete_group_first')";
			print "<li>$app->l('msg_check_upload_group')";
			print '</ul>';
		} else {
			print "<hr><center><table border=0 style=font-size:11pt><tr><td><p><font color=blue face=$app->l('variable_font') size=5>$app->l('err_group_not_exist')</font></p>\n";
			print "$app->l('err_cannot_continue_becouse') <b>$warning</b> $app->l('err_group_not_exist')<br>";
			print '<ul>';
			print "<li>$app->l('msg_add_group_first')";
			print "<li>$app->l('msg_check_upload_group')";
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
		print "<center><font color=blue face=$app->l('variable_font') size=5> $usr $app->l('err_username_exist')</font></center><br>";
		$warning ++;
	}
	if ($f1 eq '0' && !$f2) {
		print "<center><font color=blue face=$app->l('variable_font') size=5> $usr $app->l('err_username_not_exist')</font></center><br>";
		$warning ++;
	}
	if ($warning != 0) {
		if ($f1 eq '1') {
			print "<hr><center><table border=0 style=font-size:11pt><tr><td><p><font color=blue face=$app->l('variable_font') size=5>$app->l('err_username_exist')</font></p>\n";
			print "$app->l('err_cannot_continue_becouse'}<b>$warning</b>$app->l('err_username_exist')<br>";
			print '<ul>';
			print "<li>$app->l('msg_delete_user_first')";
			print "<li>$app->l('msg_check_upload_username')";
			print '</ul>';
		} else {
			print "<hr><center><table border=0 style=font-size:11pt><tr><td><p><font color=blue face=$app->l('variable_font') size=5>$app->l('err_username_not_exist')</font></p>\n";
			print "$app->l('err_cannot_continue_becouse')<b>$warning</b>$app->l('err_username_not_exist')<br>";
			print '<ul>';
			print "<li>$app->l('msg_add_user_first')";
			print "<li>$app->l('msg_check_upload_username')";
			print '</ul>';
		}
		print '<hr color="#FF0000">';
		print "<center><a href="javascript:history.go(-1)"><img align=absmiddle src=/img/upfolder.gif border=0>  $app->l('BACK')</a></center>";
		print '</table></center></body>';
		print "</html>";
		exit(1) if ($f1 ne '1');
	}
}

sub addone {

}

sub read_request {
	open (REQ, "< $account") || &err_disk("$account $app->l('err_cannot_open').<br>");
	while ($line = <REQ>) {
		local($uname, $gname, $pwd) = split(/ /, $line);
		$pwd =~ s/[\n|\r]//g;
		&addone($uname, $gname, $pwd, '') if ($uname ne '' && $gname ne '' && $pwd ne '');
	}
	close(REQ);
}

sub autoadd {

}

sub add_wam {
	my $usr = @_;
	return if ($usr eq 'admin');
	$admins{$usr} = 1 unless exists($admins{$usr});
	$c->{admin} => join( /,/, keys %admins);
}

sub del_wam {
	my $usr = @_;
	return if ($usr eq 'admin');
	delete $admins{$usr} if exists($admins{$usr});
	$c->{admin} => join( /,/, keys %admins);
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
	print "<center>$app->l('del_user_now'} $usr ，uid: $uid ....</center><br>";
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
	open(SMB,"|$c->{smbprog} -x $usr")  || &err_disk("$app->l('err_cannot_open') $c->{smbprog} $app->l('program')<br>");
	close(SMB);
	splice @UIDS;
	splice @UNAME;
	splice @PASS;
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
		&head($app->l('title_chgpw'));
		&smb_passwd($usr,$p1);
	} else {
		&head($app->l('title_chgpw'));
		print "<hr><center><table border=0 style=font-size:11pt><tr><td><p>$app->l('err_bad_passwd')</p>\n";
		print "$app->l('err_cannot_continue_change_passwd').<br>";
		print '<ul>';
		print "<li>$app->l('msg_passwd_must_same')";
		print '</ul>';
		print '<hr color="#FF0000">';
		print "<center><a href=\"javascript:history.go(-1)\"><img align=absmiddle src=/img/upfolder.gif border=0>  $app->l('backto_prev_page')</a></center>";
		print '</table></center></body>';
		print "</html>";
		exit 1;
	}
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
	&head("$app->l('title_system_info')");
	print "<br><center><table border=0 style=font-size:11pt><tr><td><p>$app->l('err_perm_set')</p>\n";
	print $msg;
	print '<ul>';
	print "<li>$app->l('msg_please_check_perm')";
	print "<li>$app->l('msg_contact_administrator')";
	print '</ul>';
	print '<hr color="#FF0000">';
	print "<center><a href=\"javascript:history.go(-1)\"><img align=absmiddle src=/img/upfolder.gif border=0>  $app->l('backto_prev_page')</a></center>";
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

my $share_flag = 0;

sub get_dir {
	my($mydir) = @_;
	my($line, @lines);
	$mydir = '' if ($admin eq '0' && $mydir !~ /^$home(.+)/ );
	if ($mydir eq '') {
		$mydir = $home;
		$mydir = '/' if ($admin eq '1');
	}
	opendir (DIR, "$mydir") || &err_disk("$mydir $app->l('err_cannot_open_dir')<br>");
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
					$TYPE{$line} = $app->l('share');
				} else {
					$TYPE{$line} = $app->l('dir');
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
					$TYPE{$line} = $app->l('file');
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
		&err_perm("$app->l('err_cannot_read'} $olddir $app->l('err_folder_priv'}$app->l('err_so_cannot_chdir')<br>") if ($olddir ne '/' && &check_perm($olddir,4) eq 0);
	}
	$DATA{'share'} = $olddir if ($SHARE{$olddir} ne '');
	$olddir;
}

sub make_dir {
	my($olddir,$newdir) = @_;
	$olddir if ($newdir eq '');
	if ($share_flag eq 0) {
		&err_perm("$app->l('err_cannot_write') $olddir $app->l('err_folder_priv'}$app->l('err_so_cannot_mkdir')<br>") if (&check_perm($olddir,2) eq 0);
	} else {
		&err_perm("$app->l('share_folder')$olddir$app->l('err_so_cannot_mkdir')<br>") if ($SPERM_DIR{$DATA{'share'}} ne 'yes');
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
		&err_perm("$app->l('share_folder')$olddir$app->l('err_so_cannot_delete')<br>");
	} else {
		$olddir .= '/' if ($olddir ne '/');
		foreach $f (@files) {
			if (&check_perm("$olddir$f",0) eq 0) {
				$warning ++;
			} else {
				system("rm -rf $olddir$f/* : rmdir $olddir$f");
			}
		}
		&err_perm("<center>$warning $app->l('filemgr_cannot_del')</center><br>") if ($warning > 0);
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
	&err_perm("<center>$warning $app->l('filemgr_cannot_priv')</center><br>") if ($warning > 0);
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
	&err_perm("<center>$warning $app->l('filemgr_cannot_chown')</center><br>") if ($warning > 0);
}

sub down_load {
	my($dnfile) = @_;
	my $fsize = (stat($dnfile))[7];
	open(REAL,"< $dnfile") || &err_disk("$app->l('err_cannot_open_download_file') $dnfile<br>");
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
	&head("$app->l('title_edit_file') $dnfile");
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=step value=dosave>\n";
	print "<input type=hidden name=action value=>\n";
	print "<input type=hidden name=folder value=$olddir>\n";
	print "<input type=hidden name=edfile value=$dnfile>\n";
	print "<textarea name=textbody rows=17 cols=80 wrap=off>";
	open(REAL,"< $dnfile") || &err_disk("$app->l('err_cannot_open_edit_file')$dnfile<br>");
	while(read(REAL, $buf, 1024)) {
		$buf =~ s/</&lt;/g;
		$buf =~ s/>/&gt;/g;
		print $buf;
	}
	close(REAL);
	print "</textarea>";
	print "<br><input type=button value=\" $app->l('save') \" onclick=mysubmit('save');>";
	print "<input type=button value=\" $app->l('save_and_exit') \" onclick=mysubmit('save_exit');>";
	print "<input type=reset value=\" $app->l('undo') \"></center>\n";
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
	&err_perm("$app->l('err_cannot_read') $mydir$dnfile $app->l('err_file_priv'}$app->l('err_so_cannot_download')<br>") if (&check_perm("$mydir$dnfile",4) eq 0 && $share_flag eq 0);
	if (-T "$mydir$dnfile") {
		if ($share_flag eq 1) {
			&err_perm("$app->l('share_folder') $olddir$app->l('err_so_cannot_view')<br>") if ($SPERM_EDIT{$DATA{'share'}} ne 'yes' && &check_perm("$mydir$dnfile",4) eq 0);
		} elsif (&check_perm("$mydir$dnfile",2) eq 0) {
			$flag = 1;
		}
		if ($flag eq 1) {
			print "Content-type: text/plain\n\n" ;
			open(REAL,"< $mydir$dnfile") || &err_disk("$app->l('err_cannot_open_download_file')$mydir$dnfile<br>");
			while(read(REAL, $buf, 1024)) {
				print $buf;
			}
			close(REAL);
		} else { &edit_file("$mydir$dnfile"); }
	} elsif (-B _) {
		&err_perm("$app->l('share_folder'} $olddir$app->l('err_so_cannot_download')<br>") if ($share_flag eq 1 && $SPERM_DN{$DATA{'share'}} ne 'yes');
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
	&head($app->l('title_sharemgr'));
	print "<center><table border=1 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
	print "<tr><td colspan=5><font size=+1 color=blue face=$app->l('variable_font'}>$app->l('share_config_these')</font>\n";
	print "<form name=myform action=$cgi_url method=post><input type=hidden name=step value=doshare>\n";
	print "<input type=hidden name=folder value=$olddir>\n";
	print "<input type=hidden name=items value=$share>\n";
	foreach $file (@files) {
		if (-d "$mydir$file") {
			print "<tr><td colspan=5>$app->l('share_dir'}$mydir$file　$app->l('share_share_name')<input type=text name=share-$file value=".$SDESC{"$mydir$file"}."></td>\n";
		}
	}
	$file = $files[0];
	print "<tr><td colspan=5><font size=+1 color=blue face=$app->l('variable_font')>$app->l('share_to_what')</font>\n";
	print "<tr><td colspan=5><input type=text name=word value=><a href=javascript:search()>$app->l('pattern_match')</a></td>\n";
	print "<tr><td><input type=checkbox name=grp value=999>$app->l('everygrp')</td>\n";
  $i = 1;
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
	print "<tr><td colspan=5>$app->l('share_make_group')<br>" if ($i<=0);
	print "<tr><td colspan=5><font size=+1 color=blue face=$app->l('variable_font'}>$app->l('share_grant')</font>\n";
	if ($SPERM_DN{"$mydir$file"} eq 'yes') {
		print "<tr><td><input type=checkbox name=dn value=yes checked>$app->l('share_download')\n";
	} else {
		print "<tr><td><input type=checkbox name=dn value=yes>$app->l('share_download')\n";
	}
	if ($SPERM_UP{"$mydir$file"} eq 'yes') {
		print "<td><input type=checkbox name=up value=yes checked>$app->l('share_upload')\n";
	} else {
		print "<td><input type=checkbox name=up value=yes>$app->l('share_upload')\n";
	}
	if ($SPERM_DIR{"$mydir$file"} eq 'yes') {
		print "<td><input type=checkbox name=dir value=yes checked>$app->l('share_mkdir')\n";
	} else {
		print "<td><input type=checkbox name=dir value=yes>$app->l('share_mkdir')\n";
	}
	if ($SPERM_EDIT{"$mydir$file"} eq 'yes') {
		print "<td><input type=checkbox name=edit value=yes checked>$app->l('share_delete')\n";
	} else {
		print "<td><input type=checkbox name=edit value=yes>$app->l('share_edit')\n";
	}
	if ($SPERM_DEL{"$mydir$file"} eq 'yes') {
		print "<td><input type=checkbox name=del value=yes checked>$app->l('share_delete')</table>\n";
	} else {
		print "<td><input type=checkbox name=del value=yes>$app->l('share_delete')</table>\n";
	}
	if ($i <= 0) {
		print "<a href=javascript:history.go(-1)>$app->l('cancel')</a></form>\n";
		print "<script>\nfunction search() { }\n";
	} elsif ($i>1) {
		print "<input type=button value=\" $app->l('confirm') \" onclick=javascript:check()>　　<a href=javascript:history.go(-1)>$app->l('cancel'}</a></form>\n";
		print "<script>\nfunction check() {\nvar flag = 0;\n";
		print "for (i=0;i<$i;i++) { if (thisform.grp[i].checked) { flag = 1; } }\n";
		print "if (flag == 0) { alert('$app->l('please_select'}'); } else { thisform.submit(); } }\n";
		print "function search() { var word = thisform.word.value;\n";
		print "for (i=0;i<$i;i++) { if (thisform.grp[i].value.indexOf(word)!=-1) { thisform.grp[i].checked = 1; }\n";
		print "else { thisform.grp[i].checked = 0; } } }\n";
	} else {
		print "<input type=button value=\" $app->l('confirm') \" onclick=javascript:check()>　　<a href=javascript:history.go(-1)>$app->l('cancel'}</a></form>\n";
		print "<script>\n function check() {\n";
		print "if (!thisform.grp.checked) { alert('$app->l('please_select')'); } else { thisform.submit(); } }\n";
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
	&head($app->l('title_sharemgr'));
	print "<center><font color=blue face=$app->l('variable_font'} size=5>$app->l('share_cancel_completed')</font>";
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
	&err_perm("$app->l('share_folder'} $olddir$app->l('err_so_cannot_download')<br>") if ($share_flag eq 1 && $SPERM_DN{$DATA{'share'}} ne 'yes');
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
		&err_perm("$app->l('err_cannot_change') $olddir$f $app->l('err_name_priv')<br>") if (&check_perm("$olddir$f",2) eq 0);
	} else {
		&err_perm("$app->l('share_folder') $olddir $app->l('err_so_cannot_modify')<br>") if ($SPERM_UP{$DATA{'share'}} ne 'yes');
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
		&err_perm("$app->l('err_cannot_move_to_others')<br>") if (&check_perm("$dest",2) eq 0);
	} else {
		&err_perm("$app->l('err_cannot_move_to_others')<br>") if (&check_perm("$olddir",2) eq 0);
	}
	&err_perm("$app->l('err_cannot_move_from_others')<br>") if (&check_perm("$olddir$f",0) eq 0);
	system("mv $olddir$f $dest");
	system("chown $menu_id:$menu_gid $dest/$f");
}

sub copy_dir {
	my($dest,$olddir,$items) = @_;
	$olddir if ($dest eq '' || $items eq '');
	my @files = split(/,/,$items);
	my $f = $files[0];
	$olddir .= '/' if ($olddir ne '/');
	if (is_admin) {
		$dest = "$olddir$dest" if (substr($dest,0,1) ne '/');
	} else {
		if (substr($dest,0,1) eq '/') {
			$dest = substr($dest,1);
			$dest = "$olddir$dest" ;
		} else {
			$dest = "$olddir$dest" ;
		}
	}
	if (-e "$dest") {
		&err_perm("$app->l('err_cannot_copy_to_others')<br>") if (&check_perm("$dest",2) eq 0);
	} else {
		&err_perm("$app->l('err_cannot_copy_to_others')<br>") if (&check_perm("$olddir",2) eq 0);
	}
	&err_perm("$app->l('err_cannot_copy_from_others')<br>") if (&check_perm("$olddir$f",0) eq 0);
	system("cp -Rf $olddir$f $dest");
	system("chown $menu_id:$menu_gid $dest/$f");
}

#***********************************************************************************
# MAIN
#***********************************************************************************
$> = 0;
$) = 0;

&get_lang;
&check_acl;

$app->helper(is_admin) => sub {
  return exists($admins{$s->{user_id}});
};

get '/relogon' => sub {
  $s->{expires} => 1;
} => 'logon_form';

post '/logon' => sub {
  # Check CSRF token
  my $v = $app->validation;
  return $app->render(text => 'Bad CSRF token!', status => 403) if $v->csrf_protect->has_error('csrf_token');

  if ($app->basic_auth(
    "WAM" => {
      host => '127.0.0.1',
      basedn => 'dc=cc,dc=tp,dc=edu,dc=tw',
      binddn => "uid=$c->req->param('user'),ou=People,dc=cc,dc=tp,dc=edu,dc=tw",
      bindpw => "$c->req->param('password')",
      filter => 'objectClass=sambaSamAccount'
    }
  )) {
    $s->{user_id} => $app->req->param('user'));
    $s->{passed} => 1;
    $s->store();
    $app->redirect_to('/');
  } else {
    &err_account;
    $app->redirect_to('/relogon');
  }
}

under sub {
  return 1 if $s->{passed'};
  $app->render(text => 'You Must login first!', status => 403);
}

get '/' = 'frames';
get '/show_left' = 'left';
get '/show_right' = 'right';

if ($DATA{'step'} eq 'config' && $admin eq '1') {
	&head($app->l('title_setup'});
	&get_lang_list;
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=step value=doconfig>\n";
	print "<table border=6 style=font-size:11pt width=95%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
	print "<tr  style=background-color:#ffffff><th align=right>$app->l('config_language')</th>\n";
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
	print "<tr style=background-color:#6582CD><th align=right><font color=#ffffff>$app->l('config_aclcontrol'}</font></th>\n";
	if ($CONFIG{'acltype'} eq 1) {
		print "<td><input type=radio name=acltype value=1 checked><font color=#ffffff>$app->l('config_allow_ip'}　<input type=radio name=acltype value=0>$app->l('config_deny_ip'}</font></td>\n";
	} else {
		print "<td><input type=radio name=acltype value=1><font color=#ffffff>$app->l('config_allow_ip'}　<input type=radio name=acltype value=0 checked>$app->l('config_deny_ip'}</font></td>\n";
	}
	print "<tr style=background-color:#ddeeff><th align=right>$app->l('config_acl_rule'}</th>\n";
	print "<td><textarea rows=3 cols=30 name=acls>$CONFIG{'acls'}</textarea></td></tr>\n";
	print "<tr style=background-color:#FFD1BB><th align=right>$app->l('config_upgrade_proxy'}</th>\n";
	print "<td>$app->l('config_proxy_hostname'}:<input type=text name=http_proxy value=$CONFIG{'http_proxy'}>\n";
	print "$app->l('config_proxy_port'}:<input type=text size=6 name=proxy_port value=$CONFIG{'proxy_port'}></td>\n";
	print "<tr  style=background-color:#ffffff><th align=right>$app->l('config_shell_dir'}</th>\n";
	$CONFIG{'shells'} = '/etc/shells' if ($CONFIG{'shells'} eq '');
	print "<td><input type=text name=shells value=$CONFIG{'shells'}></td>\n";
	print "<tr style=background-color:#ffffff><th align=right>$app->l('config_group_file'}</th>\n";
	$CONFIG{'group'} = '/etc/group' if ($CONFIG{'group'} eq '');
	print "<td><input type=text name=group value=$CONFIG{'group'}></td>\n";
	print "<tr style=background-color:#ffffff><th align=right>$app->l('config_group_shadow'}</th>\n";
	$CONFIG{'gshadow'} = '/etc/gshadow' if ($CONFIG{'gshadow'} eq '');
	print "<td><input type=text name=gshadow value=$CONFIG{'gshadow'}></td>\n";
	print "<tr style=background-color:#ffffff><th align=right>$app->l('config_passwd_file'}</th>\n";
	$CONFIG{'passwd'} = '/etc/passwd' if ($CONFIG{'passwd'} eq '');
	print "<td><input type=text name=passwd value=$CONFIG{'passwd'}></td>\n";
	print "<tr style=background-color:#ffffff><th align=right>$app->l('config_shadow_file'}</th>\n";
	$CONFIG{'shadow'} = '/etc/shadow' if ($CONFIG{'shadow'} eq '');
	print "<td><input type=text name=shadow value=$CONFIG{'shadow'}></td>\n";
	print "<tr style=background-color:#D2FFE1><th align=right>$app->l('config_mail_prog'}</th>\n";
	$CONFIG{'mailprog'} = '/usr/bin/sendmail' if ($CONFIG{'mailprog'} eq '');
	print "<td><input type=text name=mailprog value=$CONFIG{'mailprog'}></td>\n";
	print "<tr style=background-color:#D2FFE1><th align=right>$app->l('config_mail_aliase'}</th>\n";
	$CONFIG{'mailaliases'} = '/etc/aliases' if ($CONFIG{'mailaliases'} eq '');
	print "<td><input type=text name=mailaliases value=$CONFIG{'mailaliases'}></td>\n";
	print "<tr style=background-color:#ECFFEC><th align=right>$app->l('config_samba_prog'}</th>\n";
	$CONFIG{'smbprog'} = '/usr/bin/smbpasswd' if ($CONFIG{'smbprog'} eq '');
	print "<td><input type=text name=smbprog value=$CONFIG{'smbprog'}></td>\n";
	print "<tr style=background-color:#ECFFEC><th align=right>$app->l('config_samba_passwd_file'}</th>\n";
	$CONFIG{'smbpasswd'} = '/etc/smbpasswd' if ($CONFIG{'smbpasswd'} eq '');
	print "<td><input type=text name=smbpasswd value=$CONFIG{'smbpasswd'}></td>\n";
	print "<tr style=background-color:#D7E2FF><th align=right>$app->l('config_samba_passwd_sync'}</th>";
	if ($CONFIG{'sync_smb'} eq 'yes') {
		print "<td><input type=checkbox name=sync_smb value=yes checked></td>\n";
	} else {
		print "<td><input type=checkbox name=sync_smb value=yes></td>\n";
	}
	print "<tr style=background-color:#E8EFFF><th align=right>$app->l('config_samba_use_codepage'}</th>";
	if ($CONFIG{'codepage_smb'} eq 'yes') {
		print "<td><input type=checkbox name=codepage_smb value=yes checked></td>\n";
	} else {
		print "<td><input type=checkbox name=codepage_smb value=yes></td>\n";
	}
	print "<tr style=background-color:#E8EFFF><th align=right>$app->l('config_account_nest'}</th>";
	if ($CONFIG{'home_nest'} eq 'yes') {
		print "<td><input type=checkbox name=home_nest value=yes checked></td>\n";
	} else {
		print "<td><input type=checkbox name=home_nest value=yes></td>\n";
	}
	print "<tr style=background-color:#E8EFFF><th align=right>$app->l('config_account_auto_homepage'}</th>";
	if ($CONFIG{'add_homepage'} eq 'yes') {
		print "<td><input type=checkbox name=add_homepage value=yes checked></td>\n";
	} else {
		print "<td><input type=checkbox name=add_homepage value=yes></td>\n";
	}
	print "<tr style=background-color:#E8EFFF><th align=right>$app->l('config_account_nest_level'}</th>";
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
	print "<tr style=background-color:#F2D7FF><th align=right>$app->l('config_account_auto_passwd_style'}</th>\n";
	print "<td><select size=1 name=passwd_form>";
	$CONFIG{'passwd_form'} = 'username' if ($CONFIG{'passwd_form'} eq '');
	if ($CONFIG{'passwd_form'} eq 'username') {
		print "<option value=username selected>$app->l('config_account_auto_passwd_style_username'}</option>\n";
	} else {
		print "<option value=username>$app->l('config_account_auto_passwd_style_username'}</option>\n";
	}
	if ($CONFIG{'passwd_form'} eq 'random') {
		print "<option value=random selected>$app->l('config_account_auto_passwd_style_random'}</option>\n";
	} else {
		print "<option value=random>$app->l('config_account_auto_passwd_style_random'}</option>\n";
	}
	if ($CONFIG{'passwd_form'} eq 'single') {
		print "<option value=single selected>$app->l('config_account_auto_passwd_style_single'}</option>\n";
	} else {
		print "<option value=single>$app->l('config_account_auto_passwd_style_single'}</option>\n";
	}
	print "</select></td>\n";
	print "<tr style=background-color:#F9ECFF><th align=right>$app->l('config_account_auto_passwd_range'}</th>\n";
	print "<td><select size=1 name=passwd_range>";
	$CONFIG{'passwd_range'} = 'num' if ($CONFIG{'passwd_range'} eq '');
	if ($CONFIG{'passwd_range'} eq 'num') {
		print "<option value=num selected>$app->l('config_account_passwd_style_no'}</option>\n";
	} else {
		print "<option value=num>$app->l('config_account_passwd_style_no'}</option>\n";
	}
	if ($CONFIG{'passwd_range'} eq 'lcase') {
		print "<option value=lcase selected>$app->l('config_account_passwd_style_LCase'}</option>\n";
	} else {
		print "<option value=lcase>$app->l('config_account_passwd_style_LCase'}</option>\n";
	}
	if ($CONFIG{'passwd_range'} eq 'ucase') {
		print "<option value=ucase selected>$app->l('config_account_passwd_style_UCase'}</option>\n";
	} else {
		print "<option value=ucase>$app->l('config_account_passwd_style_UCase'}</option>\n";
	}
	if ($CONFIG{'passwd_range'} eq 'allcase') {
		print "<option value=allcase selected>$app->l('config_account_passwd_style_U&LCase'}</option>\n";
	} else {
		print "<option value=allcase>$app->l('config_account_passwd_style_U&LCase'}</option>\n";
	}
	if ($CONFIG{'passwd_range'} eq 'num-lcase') {
		print "<option value='num-lcase' selected>$app->l('config_account_passwd_style_no&LCase'}</option>\n";
	} else {
		print "<option value='num-lcase'>$app->l('config_account_passwd_style_no&LCase'}</option>\n";
	}
	if ($CONFIG{'passwd_range'} eq 'num-ucase') {
		print "<option value='num-ucase' selected>$app->l('config_account_passwd_style_no&UCase'}</option>\n";
	} else {
		print "<option value='num-ucase'>$app->l('config_account_passwd_style_no&UCase'}</option>\n";
	}
	if ($CONFIG{'passwd_range'} eq 'all') {
		print "<option value='all' selected>$app->l('config_account_passwd_style_any_Case'}</option>\n";
	} else {
		print "<option value='all'>$app->l('config_account_passwd_style_any_Case'}</option>\n";
	}
	print "</select></td>\n";
	print "<tr style=background-color:#F9ECFF><th align=right>$app->l('config_account_passwd_change_rule'}</th>";
	if (int($CONFIG{'passwd_rule'})%2) {
		print "<td><input type=checkbox name=passwd_rule1 value=yes checked>$app->l('config_account_passwd_limit_428'}</td>\n";
	} else {
		print "<td><input type=checkbox name=passwd_rule1 value=yes>$app->l('config_account_passwd_limit_428'}</td>\n";
	}
	if (int($CONFIG{'passwd_rule'})%4 >= 2) {
		print "<tr style=background-color:#F9ECFF><td><td><input type=checkbox name=passwd_rule2 value=yes checked>$app->l('config_account_passwd_limit_no&letter'}</td>\n";
	} else {
		print "<tr style=background-color:#F9ECFF><td><td><input type=checkbox name=passwd_rule2 value=yes>$app->l('config_account_passwd_limit_no&letter'}</td>\n";
	}
	if (int($CONFIG{'passwd_rule'})%8 >= 4) {
		print "<tr style=background-color:#F9ECFF><td><td><input type=checkbox name=passwd_rule3 value=yes checked>$app->l('config_account_passwd_limit_diffrent'}</td>\n";
	} else {
		print "<tr style=background-color:#F9ECFF><td><td><input type=checkbox name=passwd_rule3 value=yes>$app->l('config_account_passwd_limit_diffrent'}</td>\n";
	}
	if (int($CONFIG{'passwd_rule'}) >= 8) {
		print "<tr style=background-color:#F9ECFF><td><td><input type=checkbox name=passwd_rule4 value=yes checked>$app->l('config_account_passwd_limit_keyboard'}</td>\n";
	} else {
		print "<tr style=background-color:#F9ECFF><td><td><input type=checkbox name=passwd_rule4 value=yes>$app->l('config_account_passwd_limit_keyboard'}</td>\n";
	}
	print "<tr style=background-color:#DFeeFF><th align=right>$app->l('config_user_home_dir'}</th>\n";
	$CONFIG{'base_dir'} = '/home' if ($CONFIG{'base_dir'} eq '');
	print "<td><input type=text name=base_dir value=$CONFIG{'base_dir'}></td>\n";
	print "<tr style=background-color:#DFFFFF><th align=right>$app->l('config_user_skel'}</th>\n";
	$CONFIG{'skel_dir'} = '/etc/skel' if ($CONFIG{'skel_dir'} eq '');
	print "<td><input type=text name=skel_dir value=$CONFIG{'skel_dir'}></td>\n";
	print "<tr style=background-color:#DFFFFF><th align=right>$app->l('config_user_shell'}</th>\n";
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
	print "<tr style=background-color:#DFFFFF><th align=right>$app->l('config_user_homepage_dir'}</th>\n";
	$CONFIG{'home_dir'} = 'public_html' if ($CONFIG{'home_dir'} eq '');
	print "<td><input type=text name=home_dir value=$CONFIG{'home_dir'}></td>\n";
	&make_index if (!(-e "$tmp_index"));
	print "<tr style=background-color:#DFFFFF><td><img src=/img/home.gif align=right></td><td><a href=$cgi_url?step=edit_file&dnfile=$tmp_index>$app->l('config_edit_user_homepage_sample'}</a></td>\n";
	print "<tr style=background-color:#E8deFF><th align=right>$app->l('config_days_to_change'}</th>\n";
	print "<td><input type=text name=min value=$CONFIG{'min'}></td>\n";
	print "<tr style=background-color:#E8EFFF><th align=right>$app->l('config_days_to_force_change'}</th>\n";
	print "<td><input type=text name=max value=$CONFIG{'max'}></td>\n";
	print "<tr style=background-color:#E8EFFF><th align=right>$app->l('config_days_to_hint'}</th>\n";
	print "<td><input type=text name=pwarn value=$CONFIG{'pwarn'}></td>\n";
	print "<tr style=background-color:#E8EFFF><th align=right>$app->l('config_days_to_inact'}</th>\n";
	print "<td><input type=text name=inact value=$CONFIG{'inact'}></td>\n";
	print "<tr style=background-color:#E8EFFF><th align=right>$app->l('config_days_to_expire'}</th>\n";
	print "<td><input type=text name=expire value=$CONFIG{'expire'}></td>\n";
	print "<tr style=background-color:#E8EFFF><th align=right>$app->l('config_account_flag_status'}</th>\n";
	print "<td><input type=text name=flag value=$CONFIG{'flag'}></td>\n";
	print "<tr style=background-color:#6582CD><th align=right><font color=#FFFFFF>$app->l('config_account_quota_sample'}</font></th>\n";
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
	print "<tr><td colspan=2 align=center><img align=absmiddle src=/img/chgpw.gif><input type=submit value=\" $app->l('config_save_config'} \"></td>\n";
	print "</table></form></center>";
	&foot('');
} elsif ($DATA{'step'} eq 'doconfig' && $admin eq '1') {
	my $myrule = 0;
	$myrule = $myrule + 1 if ($DATA{'passwd_rule1'} eq 'yes');
	$myrule = $myrule + 2 if ($DATA{'passwd_rule2'} eq 'yes');
	$myrule = $myrule + 4 if ($DATA{'passwd_rule3'} eq 'yes');
	$myrule = $myrule + 8 if ($DATA{'passwd_rule4'} eq 'yes');
	open (CFG, "> $config") || die "<font color=blue face=$app->l('variable_font'} size=5>$app->l('err_cannot_open_passwd'}</font><br>";
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
	&head($app->l('title_setup'});
	print "<center><font color=blue face=$app->l('variable_font'} size=5>$app->l('config_completed'}</font></center>\n";
	&foot('');
} elsif ($DATA{'step'} eq 'upgrade' && $admin eq '1') {
	&head($app->l('title_upgrade'});
	print "<form name=myform method=POST ENCTYPE=\"multipart/form-data\">";
	print "<input type=hidden name=step value=doupgrade>\n";
	print "<div align=center><center>\n";
	print "<table border=6 style=font-size:11pt width=90% cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
	print "<tr><td colspan=2><img align=absmiddle src=/img/upgrade.gif><font  color=darkblue >$app->l('online_upgrade_minihelp'}</td>";
	print "<tr bgcolor=6699cc ><td colspan=2><font color=#ffffff><b>$app->l('online_upgrade_choose'}<b></font></td></tr>";
	print "<tr><td	width=5%><img align=absmiddle src=/img/computer.gif></td><td><input type=radio id=mode1 name=mode value=local><font  color=darkgreen>$app->l('online_upgrade_choose_1'}</font><input type=text name=file size=28 onclick=\"document.all['mode1'].checked=1\"></td></tr>";
	print "<tr><td	width=5%><img align=absmiddle src=/img/upload.gif></td><td><input type=radio id=mode2 name=mode value=upload><font  color=darkblue>$app->l('online_upgrade_choose_2'}</font><input type=file name=upload_file size=20 onclick=\"document.all['mode2'].checked=1\"></td></tr>";
	print "<tr><td	width=5%><img align=absmiddle src=/img/network.gif></td><td><input type=radio id=mode3 name=mode value=http checked><font color=red><b>$app->l('online_upgrade_choose_3'}</b></td></tr>";
	print "</table><hr color=#6699cc size=1><input type=submit value=\" $app->l('online_upgrade_confirm'} \">";
	print "</center></div></form>";
	&foot('');
} elsif ($DATA{'step'} eq 'setadmin' && $admin eq '1') {
	&head($app->l('title_manager'});
	print "<center><div align=center><form method=POST name=aform>\n";
	print "<input type=hidden name=step value=add_wam>\n";
	print "<table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
	print "<tr><td align=center bgcolor=#6699cc><font color=white><b><img align=absmiddle src=/img/addone.gif>$app->l('wam_manager_add'}</b></font>\n";
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
	print '<tr><td align=left><img align=absmiddle src=/img/chgpw.gif><input type=submit value="  '.$app->l('wam_manager_addnew'}.'  "></table></form><hr>'."\n";
	print "<form method=POST>\n";
	print "<input type=hidden name=step value=del_wam>\n";
	print "<table border=6 style=font-size:11pt width=65%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
	print "<tr><td colspan=5 align=left bgcolor=#6699cc><font color=white><b><img align=absmiddle src=/img/addgrp.gif>$app->l('wam_manager_now'}</b></font>\n";
	my $i = 0;
	my @name = split(/,/, $GUSRS{'wam'});
	foreach $usr (sort @name) {
		print "<tr>" if (($i % 5) eq 0);
		$i ++;
		print "<td><input type=checkbox name=$usr value=ON>$usr\n";
	}
	print '<tr><td align=center colspan=5><img align=absmiddle src=/img/del_.gif><input type=submit value="  '.$app->l('wam_manager_delete'}.'  "></table></form></div></center>',"\n";
	&foot('');
} elsif ($DATA{'step'} eq 'add_wam' && $admin eq '1') {
	&head($app->l('title_manager'});
	&add_wam($DATA{'user'});
	&write_group;
	print "<center><font color=blue face=$app->l('variable_font'} size=5>$app->l('wam_manager_add_completed'} $DATA{'user'} </font></center>\n";
	&foot('');
} elsif ($DATA{'step'} eq 'del_wam' && $admin eq '1') {
	&head($app->l('title_manager'});
	print "<center><font color=blue face=$app->l('variable_font'} size=5>$app->l('wam_manager_del_action'}</font><br>\n";
	foreach $usr (keys %DATA) {
		if ($DATA{$usr} eq "ON") {
			&del_wam($usr);
			print "$usr<br>\n";
		}
	}
	&write_group;
	print "<font color=blue face=$app->l('variable_font'} size=5>$app->l('wam_manager_del_completed'}</font></center>\n";
	&foot('');
} elsif ($DATA{'step'} eq 'addgrp' && $admin eq '1') {
	&head($app->l('title_addgrp'});
	print "<script>\n function check() { if (chk_empty(thisform.grp)) { alert('$app->l('group_empty_name'}'); } else { thisform.submit(); } }\n</script>\n";
	print "<script>\n function newhome() { document.myform.home.value= '/home/'+document.myform.grp.value}\n</script>\n";
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=step value=doaddgrp>\n";
	print "<table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
	print "<tr><td><img align=absmiddle  src=/img/addgrp.gif> <font  color=red><b>$app->l('groupname'}</b></font><input type=text name=grp>";
	print "<tr><td><img align=absmiddle  src=/img/home.gif> <font  color=blue><b>$app->l('group_home_dir'}</b></font><input type=text name=home value=$CONFIG{'base_dir'}/>" if ($CONFIG{'home_nest'} eq 'yes');
	print "<tr><td align=center><input type=button value=\" $app->l('group_add_this'} \" onclick=javascript:check()>\n";
	print "</table></form><hr>";
	print "<table border=6 style=font-size:11pt width=95%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
	print "<tr><td colspan=8 align=center bgcolor=#6699cc><img align=absmiddle  src=/img/addgrp.gif><font color=white><b>$app->l('group_now'}</b></font>\n";
	my $i = 0;
	foreach $gname (sort keys %GNAME) {
		print "<tr>" if (($i % 8) eq 0);
		$i ++;
		print "<td>$gname\n";
	}
	print "</table></form>";
	&foot('');
} elsif ($DATA{'step'} eq 'doaddgrp' && $admin eq '1') {
	&head($app->l('title_addgrp'});
	$DATA{'home'} .= "/$DATA{'grp'}" if ($CONFIG{'home_nest'} eq 'yes' && $DATA{'home'} eq $CONFIG{'base_dir'});
	&add_grp($DATA{'grp'},$DATA{'home'});
	&write_group;
	&write_gconf;
	print "<center><font color=blue face=$app->l('variable_font'} size=5>$app->l('group_add_completed'}</font></center>\n";
	&foot('');
} elsif ($DATA{'step'} eq 'addone' && $admin eq '1') {
	&head($app->l('title_addoneuser'});
	print "<script>\n function check() { if (chk_empty(thisform.user) || chk_empty(thisform.pwd)) { alert('$app->l('err_blank_input'}'); } else { thisform.submit(); } }\n</script>\n";
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=step value=doaddone>\n";
	print "<table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
	print "<tr><th align=right><font  color=darkgreen>$app->l('username'}</font><img align=absmiddle  src=/img/addone.gif>\n";
	print "<td><input type=text name=user>\n";
	print "<tr><th align=right><font  color=darkblue>$app->l('password'}</font><img align=absmiddle  src=/img/chgpw.gif>\n";
	print "<td><input type=text name=pwd>\n";
	print "<tr><th align=right><font  color=darkred>$app->l('account_add_group'}</font><img align=absmiddle  src=/img/addgrp.gif>\n";
	print "<td><select size=1 name=grp>";
	foreach $grp (sort keys %GNAME) {
		$gid = $GNMID{$grp};
		next if (int($gid)<500 && $gid ne 0);
		next if (&check_special($grp) eq 1);
		print "<option value=$grp>$grp</option>\n";
	}
	print "</select>\n";
	print "<tr><th align=right><font  color=red>$app->l('account_add_to_manager'}</font><img align=absmiddle  src=/img/root.gif>\n";
	print "<td><input type=checkbox name=admin value=ON>";
	print "<tr><td><td><input type=button value=\" $app->l('account_add_confirm'} \" onclick=javascript:check()>\n";
	print "</table>";
	print "</form></center>";
	&foot('');
} elsif ($DATA{'step'} eq 'doaddone' && $admin eq '1') {
	&head($app->l('title_addoneuser'});
	&addone($DATA{'user'}, $DATA{'grp'}, $DATA{'pwd'}, '');
	&add_wam($DATA{'user'}) if ($DATA{'admin'} eq "ON");
	&write_group;
	&make_passwd;
	&foot('');
} elsif ($DATA{'step'} eq 'upload' && $admin eq '1') {
	&head($app->l('title_manuadd'});
	print "<script>\n function check() { if (thisform.upload_file=='') { alert('$app->l('err_file_select_not_yet'}'); } else { thisform.submit(); } }\n</script>\n";
	print '<center><form name=myform enctype="multipart/form-data" method=post>'."\n";
	print "<input type=hidden name=step value=doupload>\n";
	print "<table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
	print "<tr><td colspan=2 align=left>$app->l('manuadd_minihelp'}<br>\n";
	print "<font color=green><b>$app->l('manuadd_minihelp_1'}</b></font><br>\n";
	print "$app->l('manuadd_minihelp_2'}<br>\n";
	print "<font color=red><b>$app->l('manuadd_minihelp_3'}</b></font><br>\n";
	print "$app->l('manuadd_minihelp_4'}<br>\n";
	print "<hr><tr><th align=right><img align=absmiddle src=/img/0folder.gif>$app->l('manuadd_uploadfile'}";
	print "<td><input type=file name=\"upload_file\">\n";
	print "<tr><td><td><input type=button value=\" $app->l('manuadd_confirm'} \" onclick=javascript:check()>\n";
	print "</table>";
	print "</form></center>";
	&foot('');
} elsif ($DATA{'step'} eq 'doupload' && $admin eq '1') {
	&head($app->l('title_manuadd'});
	&read_request;
	&make_passwd;
	&foot('');
} elsif ($DATA{'step'} eq 'autoadd' && $admin eq '1') {
	&head($app->l('title_autoadd'});
	if ($CONFIG{'nest'} eq 1) {
		print "<script>\n function check() { if (chk_empty(thisform.grp) || chk_empty(thisform.num1) || chk_empty(thisform.num2)) { alert('$app->l('autoadd_blank_1'}'); } else { thisform.submit(); } }\n</script>\n";
	} elsif ($CONFIG{'nest'} eq 2) {
		print "<script>\n function check() { if (chk_empty(thisform.pre_name) || chk_empty(thisform.num1) || chk_empty(thisform.num2) || chk_empty(thisform.grade_num1) || chk_empty(thisform.grade_num2)) { alert('$app->l('autoadd_blank_2'}'); } else { thisform.submit(); } }\n</script>\n";
	} elsif ($CONFIG{'nest'} eq 3) {
		print "<script>\n function check() { if (chk_empty(thisform.pre_name) || chk_empty(thisform.num1) || chk_empty(thisform.num2) || chk_empty(thisform.grade_num1) || chk_empty(thisform.grade_num2) || chk_empty(thisform.class_num1) || chk_empty(thisform.class_num2)) { alert('$app->l('autoadd_blank_3'}'); } else { thisform.submit(); } }\n</script>\n";
	}
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=step value=doauto>\n";
	print "<table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
	if ($CONFIG{'nest'} eq 1) {
		&read_group;
		print "<tr><th align=right>$app->l('groupname'}<br>$app->l('group_hint'}\n";
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
	print "<tr><th align=right><font color=darkred>$app->l('autoadd_pre'}</font>\n";
	print "<td><input type=text name=pre_name size=8>\n";
	if ($CONFIG{'nest'} eq 2) {
		print "<tr><th align=right><font color=darkgreen>$app->l('autoadd_level_2'}</font>\n";
		print "<td>$app->l('autoadd_from'} <input type=text name=grade_num1 size=3> $app->l('autoadd_to'} <input type=text name=grade_num2 size=3> $app->l('autoadd_class'}\n";
	}
	if ($CONFIG{'nest'} eq 3) {
		print "<tr><th align=right><font color=darkgreen>$app->l('autoadd_level_2'}</font>\n";
		print "<td>$app->l('autoadd_from'} <input type=text name=grade_num1 size=3> $app->l('autoadd_to'} <input type=text name=grade_num2 size=3> $app->l('autoadd_grade'}\n";
		print "<tr><th align=right><font color=darkblue>$app->l('autoadd_level_3'}</font>\n";
		print "<td>$app->l('autoadd_from'} <input type=text name=class_num1 size=3> $app->l('autoadd_to'} <input type=text name=class_num2 size=3> $app->l('autoadd_class'}\n";
	}
	print "<tr><th align=right><font color=purple>$app->l('autoadd_level_4'}</font>\n";
	print "<td>$app->l('autoadd_from'} <input type=text name=num1 size=3> $app->l('autoadd_to'} <input type=text name=num2 size=3> $app->l('autoadd_num'}</font>\n";
	print "<tr><th align=right><font color=blue>$app->l('autoadd_addzero'}</font>";
	print "<td><input type=checkbox name=addzero value=yes checked><tr><td colspan=2><hr size=1 color=6699cc></td>\n";
	print "<tr><td colspan=2>$app->l('autoadd_hint_2'}\n" if ($CONFIG{'nest'} eq 1);
	print "<tr><td colspan=2>$app->l('autoadd_hint_3'}\n" if ($CONFIG{'nest'} eq 2);
	print "<tr><td colspan=2>$app->l('autoadd_hint_4'}\n" if ($CONFIG{'nest'} eq 3);
	print "<tr><td><td><input type=button value=\" $app->l('autoadd_confirm'} \" onclick=javascript:check()>\n";
	print "</table>";
	print "</form></center>";
	&foot('');
} elsif ($DATA{'step'} eq 'doauto' && $admin eq '1') {
	&head($app->l('title_autoadd'});
	&autoadd($DATA{'grp'},$DATA{'pre_name'},$DATA{'num1'},$DATA{'num2'},$DATA{'addzero'},$DATA{'grade_num1'},$DATA{'grade_num2'},$DATA{'class_num1'},$DATA{'class_num2'});
	&make_passwd;
	if ($CONFIG{'passwd_form'} eq 'random') {
		print "<table border=6 style=font-size:11pt width=95%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
		print "<tr><th>$app->l('username'}<th>$app->l('password'}<th>$app->l('username'}<th>$app->l('password'}<th>$app->l('username'}<th>$app->l('password'}</tr>\n";
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
	&head($app->l('title_resetpw'});
	print "<script>\n function check() { if (chk_empty(thisform.user) && chk_empty(thisform.grp) && chk_empty(thisform.word)) { alert('$app->l('reset_passwd_select_not_yet'}'); } else { thisform.submit(); } }\n</script>\n";
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=step value=checkreset>\n";
	print "<table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
	print "<tr><th align=right>$app->l('username'}\n";
	print "<td><select size=1 name=user onchange=rest(0)>\n";
	print "<option value=></option>\n";
	print "<option value=999>$app->l('everyone'}</option>\n";
	foreach $usr (sort keys %UNAME) {
		$uid = $UNMID{$usr};
		next if (int($uid)<500);
		next if (&check_special($usr) eq 1);
		print "<option value=$usr>$usr</option>\n";
	}
	print "</select>\n";
	print "<tr><th align=right><font color=darkblue>$app->l('groupname'}<br>$app->l('group_hint'}</font>\n";
	print "<td><select size=1 name=grp onchange=rest(1)>\n";
	print "<option value=></option>\n";
	foreach $grp (sort keys %GNAME) {
		$gid = $GNMID{$grp};
		next if (int($gid)<500);
		next if (&check_special($grp) eq 1);
		print "<option value=$grp>$grp</option>\n";
	}
	print "</select>\n";
	print "<tr><th align=right><font color=darkgreen>$app->l('pattern_search'}</font>\n";
	print "<td><input type=text name=word onchange=rest(2)>\n";
	print "<tr><th align=right><font color=red>$app->l('reset_passwd_setto'}</font>\n";
	print "<td><select size=1 name=passwd_form>";
	if ($CONFIG{'passwd_form'} eq 'username') {
		print "<option value=username selected>$app->l('config_account_auto_passwd_style_username'}</option>\n";
	} else {
		print "<option value=username>$app->l('config_account_auto_passwd_style_username'}</option>\n";
	}
	if ($CONFIG{'passwd_form'} eq 'random') {
		print "<option value=random selected>$app->l('config_account_auto_passwd_style_random'}</option>\n";
	} else {
		print "<option value=random>$app->l('config_account_auto_passwd_style_random'}</option>\n";
	}
	if ($CONFIG{'passwd_form'} eq 'single') {
		print "<option value=single selected>$app->l('config_account_auto_passwd_style_single'}</option>\n";
	} else {
		print "<option value=single>$app->l('config_account_auto_passwd_style_single'}</option>\n";
	}
	print "</select>\n";
	print "<tr><td><td><input type=button value=\" $app->l('reset_passwd_confirm'} \" onclick=javascript:check()>\n";
	print "</table>";
	print "</form></center>";
	&foot('');
} elsif ($DATA{'step'} eq 'checkreset' && $admin eq '1') {
	&head($app->l('title_resetpw'});
	if ($DATA{'user'} ne '') {
		&reset_pw($DATA{'user'},'','',$DATA{'passwd_form'});
		&write_shadow;
		print "<center><font color=blue face=$app->l('variable_font'} size=5>$app->l('reset_passwd_completed'}</font>\n";
		if ($DATA{'passwd_form'} eq 'random') {
			print "<hr>$app->l('reset_passwd_list'}\n";
			print "<table border=6 style=font-size:11pt width=95%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
			print "<tr><th>$app->l('username'}<th>$app->l('password'}</tr>\n";
			foreach $usr (@CHGPW) {
				print "<tr><td>$usr<td>$UPASS{$usr}</tr>\n";
			}
		}
		print '</table>';
	} elsif ($DATA{'grp'} ne '') {
		print "<center><font color=blue face=$app->l('variable_font'} size=5>$app->l('reset_passwd_grp_question'} $DATA{'grp'}</font>\n";
		print "<p>$app->l('reset_passwd_reset_these'}</p>\n";
		print "<hr><form method=post>\n";
		print "<input type=hidden name=step value=doreset>\n";
		print "<input type=hidden name=grp value=$DATA{'grp'}>\n";
		print "<input type=hidden name=passwd_form value=$DATA{'passwd_form'}>\n";
		print "<table border=6 style=font-size:11pt width=95%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
		print "<tr><td colspan=5 align=center bgcolor=#6699cc><b><font color=white><b>$app->l('group_member'}<b>\n";
		my $i = 0;
		$mygrp = $GNMID{$DATA{'grp'}};
		foreach $uid (sort keys %UIDS) {
			next if ($UGID{$uid} ne $mygrp);
			print "<tr>" if (($i % 5) eq 0);
			$i ++;
			print "<td>$UIDNM{$uid}</td>\n";
		}
		print "<tr><td colspan=5 ><center><input type=submit value=\" $app->l('reset_passwd_confirm'} \"></center></td></tr>\n";
		print "</table></form></center>";
	} else {
		print "<center><font color=blue face=$app->l('variable_font'} size=5>$app->l('reset_passwd_search_question'} $DATA{'word'}</font>\n";
		print "<p>$app->l('reset_passwd_reset_these'}</p>\n";
		print "<hr><form method=post>\n";
		print "<input type=hidden name=step value=doreset>\n";
		print "<input type=hidden name=word value=$DATA{'word'}>\n";
		print "<input type=hidden name=passwd_form value=$DATA{'passwd_form'}>\n";
		print "<table border=6 style=font-size:11pt width=95%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
		print "<tr><td colspan=5 align=center bgcolor=#6699cc><b><font color=white><b>$app->l('user_search_result'}<b>\n";
		my $i = 0;
		foreach $usr (sort keys %UNAME) {
			next if ($usr !~ /$DATA{'word'}/);
			print "<tr>" if (($i % 5) eq 0);
			$i ++;
			print "<td>$usr</td>\n";
		}
		print "<tr><td colspan=5 ><center><input type=submit value=\" $app->l('reset_passwd_confirm'} \"></center></td></tr>\n";
		print "</table></form></center>";
	}
	&foot('');
} elsif ($DATA{'step'} eq 'doreset' && $admin eq '1') {
	&head($app->l('title_resetpw'});
	&reset_pw($DATA{'user'},$DATA{'grp'},$DATA{'word'},$DATA{'passwd_form'});
	&write_shadow;
	print "<center><font color=blue face=$app->l('variable_font'} size=5>$app->l('reset_passwd_completed'}</font>\n";
	if ($DATA{'passwd_form'} eq 'random') {
		print "<hr>$app->l('reset_passwd_list'}\n";
		print "<table border=6 style=font-size:11pt width=95%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
		print "<tr><th>$app->l('username'}<th>$app->l('password'}<th>$app->l('username'}<th>$app->l('password'}<th>$app->l('username'}<th>$app->l('password'}</tr>\n";
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
	&head($app->l('title_chgpw'});
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
	print "if (chk_empty(thisform.pwd) || chk_empty(thisform.pwd2))  {  errors = '$app->l('err_blank_input'}' ; } \n";
	print "else { if (chk_diff(thisform.pwd.value,thisform.pwd2.value)) { errors = '$app->l('change_passwd_check_diffrent'}' ; }\n";
	print "else if (chk_len(thisform.pwd)) {errors = '$app->l('change_passwd_check_length'}' ;}\n" if (int($CONFIG{'passwd_rule'})%2);
	print "else if (badpasswd(thisform.pwd.value)) { errors = '$app->l('change_passwd_check_kind'}' ; }\n" if (int($CONFIG{'passwd_rule'})%4 >= 2);
	print "else if (Mrepeat(thisform.pwd.value)) { errors = '$app->l('change_passwd_check_repeat'}' ;}\n" if (int($CONFIG{'passwd_rule'})%8 >= 4);
	print "else if (badpasswd2(thisform.pwd.value)) { errors = '$app->l('change_passwd_check_arrange'}' ;}\n" if (int($CONFIG{'passwd_rule'}) >= 8);
	print "}\n";
	print "if (errors=='') { thisform.submit(); } else { alert(errors) ; rest(3);} }\n";
	print "</script>\n";
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=step value=dochgpw>\n";
	print "<table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
	print "<tr><th align=right>$app->l('change_passwd_new'}<img align=absmiddle  src=/img/chgpw.gif>\n";
	print "<td><input type=password name=pwd maxlength=12 size=16>\n";
	print "<tr><th align=right><font color=red>$app->l('change_passwd_again'}<img align=absmiddle  src=/img/mdb.gif></font>\n";
	print "<td><input type=password name=pwd2 maxlength=12 size=16>\n";
	print "<tr><td><td><input type=button value=\" $app->l('change_passwd_confirm'} \" onclick=javascript:check()>\n";
	print "</table>";
	print "<table border=6	height=112 style=font-size:11pt width=65%   cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
	print "<tr><td	align=center bgcolor=#6699cc><b><font color=white><b> $app->l('change_passwd_minihelp'}<td></tr>\n";
	print "<tr><td><p><ol><font color=darkblue>";
	print "<li>$app->l('change_passwd_rule_1'}</li>\n";
	print "<li>$app->l('change_passwd_rule_2'}</li>\n" if (int($CONFIG{'passwd_rule'})%2);
	print "<li>$app->l('change_passwd_rule_3'}</li>\n" if (int($CONFIG{'passwd_rule'})%4 >= 2);
	print "<li>$app->l('change_passwd_rule_4'}</li>\n" if (int($CONFIG{'passwd_rule'})%8 >= 4);
	print "<li>$app->l('change_passwd_rule_5'}</li>" if (int($CONFIG{'passwd_rule'}) >= 8);
	print "</font></ol></td></tr></table>\n";
	print "</form></center>";
	&foot('');
} elsif ($DATA{'step'} eq 'dochgpw' && $menu_id ne '') {
	&chg_passwd($DATA{'pwd'},$DATA{'pwd2'});
	&write_shadow;
	print "<center><font color=blue face=$app->l('variable_font'} size=5>$app->l('change_passwd_completed'}</font></center>";
	&foot('');
} elsif ($DATA{'step'} eq 'delete' && $admin eq '1') {
	&head($app->l('title_delacc'});
	print "<script>\n function check() { if (chk_empty(thisform.user) && chk_empty(thisform.grp) && chk_empty(thisform.word)) { alert('$app->l('del_user_select_not_yet'}'); } else { thisform.submit(); } }\n</script>\n";
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=step value=checkdel>\n";
	print "<hr color=336699 size=1><table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
	print "<tr><th align=right>$app->l('username'}\n";
	print "<td><select size=1 name=user onchange=rest(0)>\n";
	print "<option value=></option>\n";
	print "<option value=999>$app->l('everyone'}</option>\n";
	foreach $usr (sort keys %UNAME) {
		$uid = $UNMID{$usr};
		next if (int($uid)<500);
		next if (&check_special($usr) eq 1);
		print "<option value=$usr>$usr</option>\n";
	}
	print "</select>\n";
	print "<tr><th align=right>$app->l('groupname'}<br>$app->l('group_hint'}\n";
	print "<td><select size=1 name=grp onchange=rest(1)>\n";
	print "<option value=></option>\n";
	foreach $grp (sort keys %GNAME) {
		$gid = $GNMID{$grp};
		next if (int($gid)<500);
		next if (&check_special($grp) eq 1);
		print "<option value=$grp>$grp</option>\n";
	}
	print "</select>\n";
	print "<tr><th align=right><font color=red face=$app->l('variable_font'} size=4>$app->l('pattern_search'}</font>\n";
	print "<td ><input type=text name=word onchange=rest(2)>\n";
	print "<tr><td align=right><input type=button value=\" $app->l('del_user_confirm'} \" onclick=javascript:check()><td>　　<a href=javascript:history.go(-1)>$app->l('del_user_cancel'}</a>\n";
	print "</table></form></center>";
	&foot('');
} elsif ($DATA{'step'} eq 'checkdel' && $admin eq '1') {
	&head($app->l('title_delacc'});
	if ($DATA{'user'} ne '') {
		&delete_pw($DATA{'user'},'','');
		&write_passwd;
		&write_shadow;
		print "<center><font color=blue face=$app->l('variable_font'} size=5>$app->l('del_user_completed'}</font></center>\n";
	} elsif ($DATA{'grp'} ne '') {
		print "<center><h2>$app->l('del_user_grp_question'} $DATA{'grp'}</h2>\n";
		print "<p>$app->l('del_user_del_these'}</p>\n";
		print "<hr><form method=post>\n";
		print "<input type=hidden name=step value=dodelete>\n";
		print "<input type=hidden name=grp value=$DATA{'grp'}>\n";
		print "<table border=6 style=font-size:11pt width=95%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
		print "<tr><td colspan=5 align=center><b>$app->l('group_member'}<b>\n";
		my $i = 0;
		$mygrp = $GNMID{$DATA{'grp'}};
		foreach $uid (sort keys %UIDS) {
			next if ($UGID{$uid} ne $mygrp);
			print "<tr>" if (($i % 5) eq 0);
			$i ++;
			print "<td>$UIDNM{$uid}</td>\n";
		}
		print "<tr><td colspan=5 ><center><input type=submit value=\" $app->l('del_user_confirm'} \"> 　　<a href=javascript:history.go(-1)>$app->l('del_user_cancel'}</a></center></td></tr>\n";
		print "</table></form></center>";
	} else {
		print "<center><font color=red face=$app->l('variable_font'} size=5>$app->l('del_user_search_question'} $DATA{'word'}</font>\n";
		print "<p><font color=blue face=$app->l('variable_font'} size=4><b>$app->l('del_user_del_these'}</b></font></p>\n";
		print "<form method=post>\n";
		print "<input type=hidden name=step value=dodelete>\n";
		print "<input type=hidden name=word value=$DATA{'word'}>\n";
		print "<table border=6 style=font-size:11pt width=95%	cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
		print "<tr><td colspan=5 align=center bgcolor=#6699cc><b><font color=white>$app->l('user_search_result'}<b></font>\n";
		my $i = 0;
		foreach $usr (sort keys %UNAME) {
			next if ($usr !~ /$DATA{'word'}/);
			print "<tr>" if (($i % 5) eq 0);
			$i ++;
			print "<td>$usr</td>\n";
		}
		print "<tr><td colspan=5 align=center bgcolor=#6699cc><b><font color=white><b>$app->l('group_search_result'}<b></font>\n";
		my $i = 0;
		foreach $grp (sort keys %GNAME) {
			next if ($grp !~ /$DATA{'word'}/);
			print "<tr>" if (($i % 5) eq 0);
			$i ++;
			print "<td>$grp</td>\n";
		}
		print "<tr><td colspan=5 ><center><input type=submit value=\" $app->l('del_user_confirm'} \">　　<a href=javascript:history.go(-1)>$app->l('del_user_cancel'}</a></center></td></tr>\n";
		print "</table></form></center>";
	}
	&foot('');
} elsif ($DATA{'step'} eq 'dodelete' && $admin eq '1') {
	&head($app->l('title_delacc'});
	&delete_pw($DATA{'user'},$DATA{'grp'},$DATA{'word'});
	&write_passwd;
	&write_shadow;
	print "<center><font color=blue face=$app->l('variable_font'} size=5>$app->l('del_user_cmpleted'}</font></center>\n";
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
	&head($app->l('title_filesmgr'});
	$tmpdnfile = time;
	print "<div align=center>";
	print "<table border=6 style=font-size:11pt width=95%  border-collapse: collapse  cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
	print "<tr><td colspan=9><img align=absmiddle src=/img/fm.gif>$app->l('sign_left'}<font color=red><b>$app->l('filemgr_current_dir'}</b></font><font color=blue><img align=absmiddle src=/img/0folder.gif> $DATA{'folder'} </font>$app->l('sign_right'} 　　 $app->l('sign_left'}<a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'share'}><img align=absmiddle src=/img/sharemgr.gif border=0>$app->l('filemgr_goto_sharemgr'}</a>$app->l('sign_right'}<br>\n";
	print "<tr><td colspan=9><center><font color=green>$app->l('filemgr_total_quota'}$free[0]　</font><font color=darkred>$app->l('filemgr_total_quota_used'}$free[1]　</font><font color=blue>$app->l('filemgr_total_quota_left'}$free[2]　</font><font color=red>$app->l('filemgr_total_quota_use'}<img align=absmiddle src=/img/used.jpg width=$used height=10><img align=absmiddle src=/img/unused.jpg width=".int(60-$used)." height=10>$free[3]</font></center></td></tr>\n";
	print "<tr bgcolor=#ffffff><td><a href=javascript:sfile()><img align=absmiddle src=/img/allfile.gif border=0></a>\n";
	if ($DATA{'sort'} eq 'name' || $DATA{'sort'} eq '') {
		print "<td align=center bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=name_rev><font color=white><b>$app->l('filemgr_file_name'}</b></font></a>\n";
	} else {
		print "<td align=center bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=name><font color=white><b>$app->l('filemgr_file_name'}</b></font></a>\n";
	}
	if ($DATA{'sort'} eq 'type') {
		print "<td bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=type_rev><font color=white><b>$app->l('filemgr_file_type'}</b></font></a>\n";
	} else {
		print "<td bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=type><font color=white><b>$app->l('filemgr_file_type'}</b></font></a>\n";
	}
	if ($DATA{'sort'} eq 'perm') {
		print "<td bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=perm_rev><font color=white><b>$app->l('filemgr_file_priv'}</b></font></a>\n";
	} else {
		print "<td bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=perm><font color=white><b>$app->l('filemgr_file_priv'}</b></font></a>\n";
	}
	if ($DATA{'sort'} eq 'owner') {
		print "<td bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=owner_rev><font color=white><b>$app->l('filemgr_file_owner'}</b></font></a>\n";
	} else {
		print "<td bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=owner><font color=white><b>$app->l('filemgr_file_owner'}</b></font></a>\n";
	}
	if ($DATA{'sort'} eq 'gowner') {
		print "<td bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=gowner_rev><font color=white><b>$app->l('filemgr_file_owner_group'}</b></font></a>\n";
	} else {
		print "<td bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=gowner><font color=white><b>$app->l('filemgr_file_owner_group'}</b></font></a>\n";
	}
	if ($DATA{'sort'} eq 'size') {
		print "<td align=right bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=size_rev><font color=white><b>$app->l('filemgr_file_size'}</b></font></a>\n";
	} else {
		print "<td align=right bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=size><font color=white><b>$app->l('filemgr_file_size'}</b></font></a>\n";
	}
	if ($DATA{'sort'} eq 'time') {
		print "<td align=center bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=time_rev><font color=white><b>$app->l('filemgr_file_date'}</b></font></a>\n";
	} else {
		print "<td align=center bgcolor=#6699cc><a href=$cgi_url?step=filesmgr&folder=$DATA{'folder'}&sort=time><font color=white><b>$app->l('filemgr_file_date'}</b></font></a>\n";
	}
	print "<td align=center bgcolor=#6699cc><font color=white>$app->l('filemgr_pannel'}</font></tr>\n";
	print "<tr><td bgcolor=#ffffff><a href=javascript:snone()><img align=absmiddle src=/img/allnot.gif border=0></a><td><a href=$cgi_url?step=filesmgr&action=chdir&folder=$DATA{'folder'}&chfolder=/><img align=absmiddle src=/img/home.gif border=0> 《$app->l('filemgr_gohome'}》</a>";
	print "<td align=center colspan=6>";
	print "<form method=POST><input type=hidden name=step value=fupload><input type=hidden name=title value=\"$app->l('upload_file'}\"><input type=hidden name=act value=f><input type=hidden name=folder value=$DATA{'folder'}>\n";
	print "<img align=absmiddle src=/img/upload.gif>$app->l('upload'}<input type=text name=filemany size=4 value=5>$app->l('files'}\n";
	print "<input type=submit value=\"$app->l('upload'}\"></form>";
	print "<form name=myform method=POST action=$cgi_url$DATA{'folder'}/$tmpdnfile.$ext>";
	print "<input type=hidden name=step value=filesmgr>\n";
	print "<input type=hidden name=action value=>\n";
	print "<input type=hidden name=folder value=$DATA{'folder'}>\n";
	print "<td bgcolor=#6699cc rowspan=20><p><font color=white>$app->l('filemgr_pannel_minihelp'}</p>";
	print "<p><a href=javascript:onclick=alert('$app->l('filemgr_pannel_hint_1'}') border=0><img align=absmiddle src=/img/newfd.gif border=0></a><input type=text name=chfolder size=12><input type=button value=\"$app->l('filemgr_pannel_chdir'}\" onclick=check0()></p>\n";
	print "<p><a href=javascript:onclick=alert('$app->l('filemgr_pannel_hint_2'}') border=0><img align=absmiddle src=/img/newfd.gif border=0></a><input type=text name=newfolder size=12><input type=button value=\"$app->l('filemgr_pannel_mkdir'}\" onclick=check1()></p>\n";
	print "<p><a href=javascript:onclick=alert('$app->l('filemgr_pannel_hint_3'}') border=0><img align=absmiddle src=/img/chmod.gif border=0></a><input type=text name=newperm size=4><input type=button value=\"$app->l('filemgr_pannel_chmod'}\" onclick=check2()></p>\n";
	print "<p><a href=javascript:onclick=alert('$app->l('filemgr_pannel_hint_4'}') border=0><img align=absmiddle src=/img/chown.gif border=0></a><input type=text name=newowner size=10><input type=button value=\"$app->l('filemgr_pannel_chown'}\" onclick=check3()></p>\n";
	print "<p><a href=javascript:onclick=alert('$app->l('filemgr_pannel_hint_5'}') border=0><img align=absmiddle src=/img/rename.gif border=0></a><input type=text name=newname size=16><input type=button value=\"$app->l('filemgr_pannel_rename'}\" onclick=check4()></p>\n";
	print "<p><a href=javascript:onclick=alert('$app->l('filemgr_pannel_hint_6'}') border=0><img align=absmiddle src=/img/mv.gif border=0></a><input type=text name=movefolder size=16><input type=button value=\"$app->l('filemgr_pannel_move'}\" onclick=check5()></p>\n";
	print "<p><a href=javascript:onclick=alert('$app->l('filemgr_pannel_hint_7'}') border=0><img align=absmiddle src=/img/copy.gif border=0></a><input type=text name=copypath size=16><input type=button value=\"$app->l('filemgr_pannel_copy'}\" onclick=check6()></p>\n";
	print "<p><a href=javascript:onclick=alert('$app->l('filemgr_pannel_hint_8'}') border=0><img align=absmiddle src=/img/del.gif border=0></a><input type=button value=\"$app->l('filemgr_pannel_delete'}\" onclick=check7()></p>\n";
	print "<p><a href=javascript:onclick=alert('$app->l('filemgr_pannel_hint_9'}') border=0><img align=absmiddle src=/img/fd.gif border=0></a><input type=button value=\"$app->l('filemgr_pannel_download'}\" onclick=check8()></p>\n";
	print "<p><a href=javascript:onclick=alert('$app->l('filemgr_pannel_hint_10'}') border=0><img align=absmiddle src=/img/fd.gif border=0></a><input type=button value=\"$app->l('filemgr_pannel_share'}\" onclick=check9()></p>\n" if ($admin eq '1');
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
	print "<tr><td bgcolor=#ffeeee><a href=javascript:sall()><img align=absmiddle src=/img/all.gif border=0></a><td bgcolor=#ffffee><a href=$cgi_url?step=filesmgr&action=chdir&folder=$DATA{'folder'}&chfolder=..><img align=absmiddle src=/img/upfolder.gif border=0> $app->l('parrent'}</a>";
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
	print "<tr><td colspan=8><center>$app->l('err_file&dir_notfound'}</center></td></tr>\n" if ($filemgr_rows le 0);
	for (1..18 - $filemgr_rows) { print "<tr><td bgcolor=#6699cc colspan=8>　</td></tr>\n"; }
	print "<tr><td colspan=9><center><font color=green>$app->l('filemgr_total_quota'}$free[0]　</font><font color=darkred>$app->l('filemgr_total_quota_used'}$free[1]　</font><font color=blue>$app->l('filemgr_total_quota_left'}$free[2]　</font><font color=red>$app->l('filemgr_total_quota_use'}<img align=absmiddle src=/img/used.jpg width=$used height=10><img align=absmiddle src=/img/unused.jpg width=".int(60-$used)." height=10>$free[3]</font></center></td></tr>\n";
	print "</table></form></div><script>\n";
	print "function check() {\n";
	if ($filemgr_rows eq 1) {
		print "if (!thisform.sel.checked) { alert('$app->l('msg_file_select_not_yet'}'); return 0; } else { return 1; } }\n";
	} else {
		print "var flag = 0;\n";
		print "for (i=0;i<$filemgr_rows;i++) {\n";
		print "if (thisform.sel[i].checked) { flag = 1; } }\n";
		print "if (flag == 0) { alert('$app->l('msg_file_select_not_yet'}'); }\n";
		print "return flag; }\n";
	}
	print "function check0() { if (chk_empty(thisform.chfolder)) { alert('$app->l('msg_blank_folder'}'); } else { mysubmit('chdir'); } }\n";
	print "function check1() { if (chk_empty(thisform.newfolder)) { alert('$app->l('msg_blank_folder'}'); } else { mysubmit('mkdir'); } }\n";
	print "function check2() { var flag = check(); if (chk_empty(thisform.newperm)) { alert('$app->l('msg_blank_perm'}'); } else { if (flag) { mysubmit('chmod'); } } }\n";
	print "function check3() { var flag = check(); if (chk_empty(thisform.newowner)) { alert('$app->l('msg_blank_owner'}'); } else { if (flag) { mysubmit('chown'); } } }\n";
	print "function check4() { var flag = check(); if (chk_empty(thisform.newname)) { alert('$app->l('msg_blank_filename'}'); } else { if (flag) { mysubmit('rename'); } } }\n";
	print "function check5() { var flag = check(); if (chk_empty(thisform.movefolder)) { alert('$app->l('msg_blank_movetarget'}'); } else { if (flag) { mysubmit('move'); } } }\n";
	print "function check6() { var flag = check(); if (chk_empty(thisform.copypath)) { alert('$app->l('msg_blank_copytarget'}'); } else { if (flag) { mysubmit('copy'); } } }\n";
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
	print "<center><p><font color=red size=4><b>$app->l('filemgr_upload_where'} </b></font><img align=absmiddle src=/img/0folder.gif><font color=blue size=4><b> $DATA{'folder'}</b></font><font color=red size=4><b> $app->l('folder'}</b></font>";
	print "<form name=myform ENCTYPE=\"multipart/form-data\" method=post>\n";
	print "<input type=checkbox name=unzip value=1 checked>$app->l('filemgr_upload_unzip'}<br>\n" if ($zip_exist);
	if ($DATA{'act'} eq 'f') {
		print "<input type=hidden name=step value=filesmgr>\n";
	} elsif ($DATA{'act'} eq 's') {
		print "<input type=hidden name=step value=sharemgr>\n";
		print "<input type=hidden name=share value=$DATA{'share'}>\n";
	}
	print "<input type=hidden name=folder value=$DATA{'folder'}>\n";
	if ($DATA{'filemany'}) {
		for ($z=1;$z<=$DATA{'filemany'};++$z) { print "<img align=absmiddle src=/img/upload.gif border=0>$app->l('file'}$z：<input type=file name=\"upload_file\"><br>\n"; }
		--$z;
	} else {
		for ($z=1;$z<6;++$z) { print "<img align=absmiddle src=/img/upload.gif border=0>$app->l('file'}$z： <input type=file name=\"uploaded_file\"><br>\n"; }
		--$z;
	}
	print "<input type=submit value=\"$app->l('filemgr_upload_confirm'}\">\n";
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
	open(REAL,"> $edfile") || &err_disk("$app->l('filemgr_upload_cannot_open_editfile'}$edfile<br>");
	print REAL $buf;
	close(REAL);
	if ($DATA{'action'} eq 'save') {
		print "Location: $cgi_url/$fname?step=edit_file&dnfile=$edfile\n\n";
	} else {
		&head($app->l('title_savefile'});
		print "<center><font color=blue face=$app->l('variable_font'} size=5>$app->l('filemgr_upload_completed'}</font>";
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
	&head($app->l('title_sharemgr'});
	print "<div align=center>\n";
	print "<table border=6 style=font-size:11pt width=95%  border-collapse: collapse  cellspacing=1 cellspadding=1 bordercolor=#6699cc>\n";
	print "<tr><td colspan=7><img align=absmiddle src=/img/sharemgr.gif>$app->l('sign_left'}<font color=red><b>$app->l('share_current_dir'}</b></font><font color=blue><img align=absmiddle src=/img/0folder.gif> $DATA{'folder'} </font>$app->l('sign_right'}\n";
	if ($SPERM_UP{$DATA{'share'}} eq 'yes') {
		print "<td colspan=2><form method=POST><input type=hidden name=step value=fupload><input type=hidden name=title value=\"$app->l('share_title'}\"><input type=hidden name=act value=s><input type=hidden name=share value=$DATA{'share'}><input type=hidden name=folder value=$DATA{'folder'}>\n";
		print "<img align=absmiddle src=/img/upload.gif>$app->l('upload'}<input type=text name=filemany size=2 value=5>$app->l('files'}\n";
		print "<input type=submit value=\"$app->l('upload'}\">　<a href=$cgi_url?step=filesmgr&share=$DATA{'share'}&folder=$DATA{'folder'}>$app->l('share_backto_filemgr'}</a></font></form>";
	} else {
		print "<td colspan=2><font color=red>$app->l('share_readonly'}	<a href=$cgi_url?step=filesmgr&share=$DATA{'share'}&folder=$DATA{'folder'}>$app->l('share_backto_filemgr'}</a></font></td>\n";
	}

	if ($DATA{'share'} eq '') {
		print "<tr bgcolor=ffeeee><td><a href=javascript:sall()><img align=absmiddle src=/img/all.gif border=0></a><td align=center bgcolor=#6699cc><font color=white>$app->l('share_name'}<td	bgcolor=#6699cc><font color=white>$app->l('share_download'}<td bgcolor=#6699cc><font color=white>$app->l('share_upload'}<td bgcolor=#6699cc><font color=white>$app->l('share_mkdir'}<td  bgcolor=#6699cc><font color=white>$app->l('share_edit'}<td	bgcolor=#6699cc><font color=white>$app->l('share_delete'}";
		print "<td align=center bgcolor=#6699cc><font color=white>$app->l('share_realpath'}";
	} else {
		print "<tr bgcolor=ffeeee><td><a href=javascript:sfile()><img align=absmiddle src=/img/allfile.gif border=0></a>\n";
		if ($DATA{'sort'} eq 'name' || $DATA{'sort'} eq '') {
			print "<td align=center bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=name_rev><font color=white>$app->l('filemgr_file_name'}</font></a>\n";
		} else {
			print "<td align=center bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=name><font color=white>$app->l('filemgr_file_name'}</font></a>\n";
		}
		if ($DATA{'sort'} eq 'type') {
			print "<td bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=type_rev><font color=white>$app->l('filemgr_file_type'}</font></a>\n";
		} else {
			print "<td bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=type><font color=white>$app->l('filemgr_file_type'}</font></a>\n";
		}
		if ($DATA{'sort'} eq 'perm') {
			print "<td bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=perm_rev><font color=white>$app->l('filemgr_file_priv'}</font></a>\n";
		} else {
			print "<td bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=perm><font color=white>$app->l('filemgr_file_priv'}</font></a>\n";
		}
		if ($DATA{'sort'} eq 'owner') {
			print "<td bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=owner_rev><font color=white>$app->l('filemgr_file_owner'}</font></a>\n";
		} else {
			print "<td bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=owner><font color=white>$app->l('filemgr_file_owner'}</font></a>\n";
		}
		if ($DATA{'sort'} eq 'gowner') {
			print "<td bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=gowner_rev><font color=white>$app->l('filemgr_file_owner_group'}</font></a>\n";
		} else {
			print "<td bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=gowner><font color=white>$app->l('filemgr_file_owner_group'}</font></a>\n";
		}
		if ($DATA{'sort'} eq 'size') {
			print "<td align=right bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=size_rev><font color=white>$app->l('filemgr_file_size'}</font></a>\n";
		} else {
			print "<td align=right bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=size><font color=white>$app->l('filemgr_file_size'}</font></a>\n";
		}
		if ($DATA{'sort'} eq 'time') {
			print "<td align=center bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=time_rev><font color=white>$app->l('filemgr_file_date'}</font></a>\n";
		} else {
			print "<td align=center bgcolor=#6699cc><a href=$cgi_url?step=sharemgr&share=$DATA{'share'}&folder=$DATA{'folder'}&sort=time><font color=white>$app->l('filemgr_file_date'}</font></a>\n";
		}
	}
	print "<form name=myform method=POST action=$cgi_url$DATA{'folder'}/$tmpdnfile.zip>";
	print "<input type=hidden name=step value=sharemgr>\n";
	print "<input type=hidden name=action value=>\n";
	print "<input type=hidden name=folder value=$DATA{'folder'}>\n";
	print "<input type=hidden name=share value=$DATA{'share'}>\n";
	print "<td bgcolor=#6699cc rowspan=10><p><font color=white>$app->l('share_pannel_minihelp'}</p>";
	if ($DATA{'share'} eq '') {
		print "<p><a href=javascript:onclick=alert('$app->l('share_pannel_hint_1'}') border=0><img align=absmiddle src=/img/fd.gif border=0></a><input type=button value=\"$app->l('share_cancel_share'}\" onclick=check9()></p>" if ($admin eq '1');
		print "<p><a href=javascript:onclick=alert('$app->l('share_pannel_hint_2'}') border=0><img align=absmiddle src=/img/fd.gif border=0></a><input type=button value=\"$app->l('share_config_share'}\" onclick=check2()></p>" if ($admin eq '1');
		print "<tr><td bgcolor=#ffeeee><td colspan=7 bgcolor=#eedfcc>";
	} else {
		print "<p><a href=javascript:onclick=alert('$app->l('share_pannel_hint_3'}') border=0><img align=absmiddle src=/img/newfd.gif border=0></a><input type=text name=newfolder size=12><input type=button value=\"$app->l('share_mkdir'}\" onclick=check1()></p>";
		print "<p><a href=javascript:onclick=alert('$app->l('share_pannel_hint_4'}') border=0><img align=absmiddle src=/img/rename.gif border=0></a><input type=text name=newname size=16><input type=button value=\"$app->l('share_rename'}\" onclick=check4()></p>";
		print "<p><a href=javascript:onclick=alert('$app->l('share_pannel_hint_5'}') border=0><img align=absmiddle src=/img/del.gif border=0></a><input type=button value=\"$app->l('share_delete'}\" onclick=check7()></p>";
		print "<p><a href=javascript:onclick=alert('$app->l('share_pannel_hint_6'}') border=0><img align=absmiddle src=/img/fd.gif border=0></a><input type=button value=\"$app->l('share_download'}\" onclick=check8()></p>";
	}
	$folder_cnt = 0;
	if ($DATA{'share'}) {
		print "<tr><td bgcolor=#ffeeee><a href=javascript:sall()><img align=absmiddle src=/img/all.gif border=0></a><td bgcolor=#ffffee><a href=$cgi_url?step=filesmgr&action=chdir&folder=$DATA{'folder'}&chfolder=..><img align=absmiddle src=/img/upfolder.gif border=0> $app->l('parrent'}</a>";
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
	print "<tr><td colspan=8><center>$app->l('err_file&dir_notfound'}</center></td></tr>\n" if ($filemgr_rows le 0);
	for (1..6 - $filemgr_rows) { print "<tr><td bgcolor=#6699cc colspan=8> </td></tr>\n"; }
	print "</table></form></div><script>\n";
	print "function check() {\n";
	if ($filemgr_rows == 1) {
		print "if (!thisform.sel.checked) { alert('$app->l('msg_file_select_not_yet'}'); return 0; } else { return 1; } }\n";
	} elsif ($filemgr_rows > 1) {
		print "var flag = 0;\n";
		print "for (i=0;i<$filemgr_rows;i++) {\n";
		print "if (thisform.sel[i].checked) { flag = 1; } }\n";
		print "if (flag == 0) { alert('$app->l('msg_file_select_not_yet'}'); }\n";
		print "return flag; }\n";
	} else { print "}\n"; }
	print "function check1() { if (chk_empty(thisform.newfolder)) { alert('$app->l('msg_blank_folder'}'); } else { mysubmit('mkdir'); } }\n";
	print "function check4() { var flag = check(); if (chk_empty(thisform.newname)) { alert('$app->l('msg_blank_filename'}'); } else { if (flag) { mysubmit('rename'); } } }\n";
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
	&head($app->l('title_sharemgr'});
	print "<center><font color=blue face=$app->l('variable_font'} size=5>$app->l('share_completed'}</font>";
	&foot('s');
}

app->secrets(['WAM is meaning Web-base Account Management']);
app->start;

__DATA__

@@ frames.html.ep
% charset $app->l('charset'}
<head><meta http-equiv=Content-Type content="<%= charset %>">
<META HTTP-EQUIV=Pargma CONTENT=no-cache>
<title>WAM</title></head>
<FRAMESET COLS="130,*"  framespacing=0 border=0 frameborder=0>
<FRAME SRC=/show_left NAME=wam_left marginwidth=0 marginheight=0 noresize>
<FRAME SRC=/show_right NAME=wam_main>
</FRAMESET>

@@ left.html.ep
% charset $app->l('charset'}
% help_root $app->l('help_root'}
% help $app->l('help'}
% config $app->l('set_config'}
% set_admin $app->l('set_wam_manager'}
% filemanager $app->l('file_manager'}
% sharemanager $app->l('share_folder'}
% group $app->l('group_add'}
% account $app->l('account_add_one'}
% delete $app->l('del_group_account'}
% autoadd $app->l('autoadd_account'}
% upload $app->l('add_account_from_file'}
% resetpw $app->l('reset_passwd'}
% chgpw $app->l('change_passwd'}
% struct $app->l('view_struct'}
% check $app->l('check_account'}
% trace $app->l('trace_account'}
% logout $app->l('logout'}
<head><meta http-equiv=Content-Type content="<%= charset %>">
<META HTTP-EQUIV=Pargma CONTENT=no-cache>
<title>WAM</title>
<base target=wam_main></head>
<body link=#FFFFFF vlink=#ffffff alink=#FFCC00  style="SCROLLBAR-FACE-COLOR: #ddeeff; SCROLLBAR-HIGHLIGHT-COLOR: #ffffff; SCROLLBAR-SHADOW-COLOR: #ABDBEC; SCROLLBAR-3DLIGHT-COLOR: #A4DFEF; SCROLLBAR-ARROW-COLOR: steelblue; SCROLLBAR-TRACK-COLOR: #DDF0F6; SCROLLBAR-DARKSHADOW-COLOR: #9BD6E6">
<table style="font-size: 11 pt; border-collapse:collapse" height=100% width=100% border=1 cellspadding=2 bordercolorlight=#808080 bordercolordark=#C0C0C0 cellpadding=2 align=left bordercolor=#FFFFFF cellspacing=1>;
<tr><td align=center bgcolor=#3E7BB9 width=100% height=100%><b><font color=#FFFFFF>WAM</font></b></td></tr>
% if (is_admin) {
<tr><td align=center bgColor=#6699cc width=100% height=100%><a href="/help/help_root.htm" style="text-decoration: none"><%= help_root %></a></td></tr>
<tr><td align=center bgcolor=#FFCC00 width=100% height=100%><b>$app->l('submenu_system'}</b></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/config" style="text-decoration: none"><%= config %></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/setadmin" style="text-decoration: none"><%= set_admin %></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/filesmgr" style="text-decoration: none"><%= filemanager %></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/sharemgr" style="text-decoration: none"><%= sharemanager %></a></td></tr>
<tr><td align=center bgColor=#FFCC00 width=100% height=100%><b>$app->l('submenu_account'}</b></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/addgrp" style="text-decoration: none"><%= group %></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/addone" style="text-decoration: none"><%= account %></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/delete" style="text-decoration: none"><%= delete %></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/autoadd" style="text-decoration: none"><%= autoadd %></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/upload" style="text-decoration: none"><%= upload %></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/res$app->l(etpw" style="text-decoration: none"><%= resetpw %></a></td></tr>
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
% title $app->l('logon'}
% charset $app->l('charset'}
% logon_alt $app->l('logon_alt'}
% layout 'default'
<center><a href="javascript:onclick=alert('<%= logon_alt %>')" border=0><img align=absmiddle src=/img/wam.gif border=0></a>

@@ logon_form.html.ep
% title $app->l('logon'}
% charset $app->l('charset'}
% font $app->l('variable_font'}
% help_root $app->l('help_root'}
% help $app->l('help'}
% logon_alt $app->l('logon_alt'}
% logon_name $app->l('loginname'}
% logon_pass $app->l('loginpasswd'}
% logon $app->l('logon'}
% prev_page $app->l('backto_prev_page'}
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
R0lGODlhswEhAeYAAP///+Xq9FuDuj9vsPP1+tPc7E15tLrI40Nxsert9GWJu1N9tnmXyK3B3YilzJar1d3k8puz1fT09KS62Y2l0+3x92qGxm2Sws3a6kl2s8TS5uzs7Nvh7OTk5Nzc3Kq83Pf4+8zV67fE29PT08vT5MzMzOPl68TExLy8vMbS6m+Rv7S0tMzS3IaZyKysrKqzyJenyKSkpOHm85ubm62yupOTk6esuKO51YuLi52xzH2SrsbL2Nrd5JWcqYeYuYaGhs7Y5qOmq+bo7Vd7qtXa5IiVqJmkuqy703mGmEdzrsPN5ZOeuXmTuqaprV95nba7x2l+m2eEqoyhvXiLpnWLub3ByJOXnJuirGyBnl6AroaMk6Sy1bW4u7K1un+FjcPFy9bY3Y6Tm2N+pMfIzNne60Bvr9HW4oaIjNLV3IKOoIOHi5ebn9fe8LG+4qy74XSMyHyT0Vp4xevu+GJ9xYeb0qi226Ky3LK92aGv1KOtxqq109DX6pGfw2V+vwAAAAAAACwAAAAAswEhAQAH/4AAgoOEhYaHiImKi4yNjo+QkZKTlJWWl5iZmpucnZ6foKGio6SlpqeoqaqrrK2ur7CxsrO0tba3uLm6u7y9vr/AwcLDxMXGx8jJysvMzc7P0NHS09TV1tfY2drb3N3e3+Dh4uPk5ebn6Onq6+zt7u/w8fLz9PX29/j5+vv8/f7/AAMKHEiwoMGDCBMqXMiwocOHECNKnEixosWLGDNq3Mixo8ePIEOKHEmypMmTKFOqXMmypcuXMGPKnEmzps2bOHPq3Mmzp8+fQIMKHUq0qNGjSJMqXcq0qdOnUKNKnUq1qtWrWLMeDCBgAAGtVAsYGDAA7NQDCMgiMAs1QVeyA/8MsHXKFS5ZBXOZBlhglyyDvBAbOHhwC8LYvgMiAHboAO5fWmIRkz1gSILly4vvHZhAoVAFC3Yv0MKQQTLZAoQuq7aceR4E0GQDDCrA1y6GWRrSmh6QAIDqDcCDY279LoJushwEoe37WNZxyRl8Ww6+oYN14MOJqzvw1q7sCH0RKJ5VYbff6dWte1hvvcMG1trRfagdHkSDvgtCIFqNCrx5ERKkt54HIxTInnvwxUdOAM/ZZcBycCGQXGWrJUjKYbuRIGCBI5TgoYEISqBgORPshkCDhIkoSIXCWRgKCA0iZkIH63VYwgk4nlDCCOy9NyI5B5iHXwIVokfdeyqOAoH/kBmo1yGOKKCA44ceIPgjOQwICZcIRx7Z3nVIkpKCkALQ+GSUaEq5Y5U+XilOlloy0F6VX855IHajBADnbioQeCMKKwS6QpQ68milm+HsuZsBLBDI4YCQEnini5wUECNiLZy5ggucBqqmoW0i+g1sJr5QoIeocqjqoyGGIoKWA8Dw56YxxNDpp2wmuRMHDCgw4TEcHABBJiAEYCwBX33SnWmZ3ngCoVOimiqolG7in5AwPEtrrbYOWqgHYfb0lgITyDAMCB8wUBpZGTAQwa+LyBCCCBG0YAGGdiEgGif0SSYAC7MKCm20O1KrayeNafkCoC7EMMPD3aqZ68E4Belg/7LAaGCeAA808AADAgjAgAMROGBBv0IugBon65omq7acdjqolAQbHIqiu9FA68MQu+CtzTph4ADKEwhDwAWwwoqAABYwQMEEIogwQQQPpOAJBJfClS3D3NrqM7RUThxKiVrq3PAMNfQ86JqtekJABCtflLBdC4AADAEBKJC0aQtowEEAGJ9Cqstc81zrrZ+CGuonBLS8mw1n1yD5DN1+2zYnnw2AgN0X4UtWA8BcuzdiApjLygda2oBCww7zTPnXOrKNHcWcEKC3eQjY0LrkaVcuO+2XQNBd3BEVQPXgZAkADAdZM6nAyDcQqSLwoCTQPFw27Mx7774rXq0mvF5P1v8CkdeAQ+8uSOze4plo4PgHFC3bF2WDFFkLzklfwMHsRfbvvyVkExLkdse713lrR9f5niYekDQFOIx353udlICWCQjczi4OmIjo+qK8FV2GfwpUhcZ20y7dLOBEOahOl1ZIHf9VSBIXNM8A0bY9A05QbKJ4m/gGoIMH4uCH6EPB76gXCQhxUCKW2g39jAQm/r0iAA9AmmQWEAEi7UAEPOgADxoVqUjVqT0sPBJ/HLEkWOnugQWUYKHWR0RO3EdIPYiB5H4YwRisjYKWYJBpopOaEAJEfnbBi3SAQ6MDsdGPoqgAIMfXgA8KyFEdWpUkvfjFL4kxO4kAAfJMg4DynQ//fT/DISleZZ4M+JCOvbtjAjFBgAPgDy6E8eAYC/JG02hgkE4yEJ1m1woOOC5Ct0FPIU/lrBzFTloF02UX6WRJJy7ilZLpJBo/SbkDjuByo2CekByINjrWcQU6EiUlSIM72fwGSYjURwz7Ihph+ulDhjpkKzAQI8W481RQSlOajHnMSS4TjM48RASkCKsMeFJyERtiKfaiJR847Ic/AGI1T4DHSSzSLn9xZAvTeY8ymgYI03FSMakkT0JowAEOYMAtR2ExuLQzQNV557MAJSiBocmY03rUP5uISUIEMGkGcMHD5hjEcLKxFLbTEgKC0E0cRDSCPqOoOCUxt92AFKbp/wFTT/3BQNMoIKRm+hOhZBeuCkygXwsI3CcqcBwJfTCsUApUzGTmqZv2U1XLZGaLaJeb0Q1gAWg0XxAVSgpo4keo5nNqRNMW1Yo+4gAo85cwCzmpNuIjsnD5QIDgqq2xek8CHGjBpWL5iQBoYHAvjemZaDpXuto1djrt4hf3ioiqJg2wTf2mEB17tR0OQAGIhehiZ5A+qeJpEl3VUgQIaSa8TpUfI4ymEFQbMJ+FMkQfaJ6EPOGASwFosx3Q1KZa61qawZZHhqzkJasVAOP4dQg0ROVES8Am9oGCAknzQXB/wF+o7habjqgAQYWEACLEVKaW4+U/DMsA6sIsZtfdgP8JDAsXC3jiUga4p7bG21qb0gye6Q0jCIGXRL9qrgiJlagdjRquHP5yN0bwYX/9S18AM4IDmDWNAKgrVlzZOB8w2s0ONuAnmHELdoYSQY7D04no9sUBIfUTw1jnNQ9HS5lNRKcLFbHJvQ3Bm9+U6o87gTql0UDGT2WsEHNVRN9qDa5REtgaW9yPdcJlxzSaFZUTes0juHkAQvifJEJwqQKAl0APPpx17TqtO43YfoxoaV8sAFkhIQGiKgYnbztxUcSQT46JTbOt1nwoR+B3dAholHghvFtwcVQeXUbAkMNbAq51Lar0fcGfERDoLm21EZ4bgACi/CS5HtlTOWr0LgP/SokSI4YwSyZLEhQ73BVvehM/3WbD5ujUH1aT1BwlQJe3WeQpK/qGpeYHNBuc52ftOWIUhcGfB9DgrAL01YLggGQ0S0gpy7VhsDsvevWqZUwY9gN6NE8S+NvfVIqZzp7oa36D602H8wjiiaDwbmCgKU4dubgXx7c7oFlgIncIULWCWEK761cRqIeSGFdEtgeQgQpsttwchh2IQ8zsSmxQLcFUgpaGwPBqa/q5m/Dl6JZwSvlae8yFmDmsFqBn1lHucBOEOj1saxcYqNbdKT/cCmzAhGjruEb+1HohZPBsYldX5yAC6Igz4V7EZHA6O4g20Rke5mtfogJmD08Tmv7J/1FTNN2JoCd+YLW1bbnOa/+NeT24DpcFCAGuO7t6EQK/G1PZCKe/g0S/ECCDkK62pndc9qM3Qfm/2twydkaME4red6RnQuOIMQDh65g+BNq3ECJwgOcskIAQBDtfTyic62zoe8vCIwT/+TrDDFeEBglAAQpwgCtNBIMnZGumNw29I0SAr4w6OM51XeMhVdMJSc9vkJ2GCxRob3HbX4IA8x5AFAg/OTuS+veDMHMMMCyCcD0LMF6BlTYGxGLO9w6vhAAO4HWYdzYPU319oQItdlEOMAJd4QM0JWfNZ1kaAEj6cXNiVVM+JnmbcFEZtVkGgAAwIAW7gQT0N1/2ZwnuB/8rUxBfTodrbIYIAfBLC1ABg4ABQkIFVrc9Cuh/xgWA85BwffEAxGZkFZgEHLQ/CZJjCOADZEEFOYdkrtZGbIUYeDEdOJd+hBUKOUgWF/BWHfACL/AEzUODM+ZwNXZcnYB7iFEEuUVNlRNywMNyDnIbg/BzfVEEBAREoBR5DegOyWUXw3ZzZ2J1U2CFDsIC6LQiO7R/XeM7P5gIaygCviF9KJiCjVgJScUcX0FsVRBtUIBpuuV7TkgJBKCH4WEF3KaI32ZcwIM/GVQIA4YYCNADPNiD6jOL8aB44XFLkmhkMRAFz7EAMLA/WiYBCQAr8PV4X3OHbfSIZGFho9hucoX/bGm4VgfgAL/0GG4Xe3bxihX3beWICfG3G0mQiyq2jdf0e/jTHPVzPfBlj7yXeohXDxDwYgNwd5s1iS5wBUOQLz5gMKphAoFXjzU0as33TIgxLKb3YOTod5cwAQapjpJ4I2+RBFMwBVFgiWSBBWCWSq2mdpBgiNiYYmm2gBdZCN74W2olAUJnHlMAkLz3KTDpDl1mAK9HigvZkBFiBHdYjcFhdvWoi4aXj22EMh1kGWbibjKTYCIHCWNIOqsIU+2GArWRBdyilGQRBSkWix75CNZjYmlJR3WoRtxYCMpYeb3RR+yoFrgol04nkCoID2WGGJRherNSBCqpOUz5WVjV/wEsACtagEo18IcDSQhcNx4meAIcZk0JdIqR4GRwkQET4naAUhtJEAQNEwVoqZbv6H/xWAmtByuXRm2Zhm6hQgAP0CCi2UcSsAVCMgTcxndQBU7idw9BKBn21IyAogPPkQE2YFTrQx3q8QKyKZnEpWlQF1moEWW1tpm22ZUxKYxLNJLa0jI6wCkMCRdqmWIu+ZqT4Gy5JySRSXs4wHzUIggBEGwIsFIetAFEID47SJOKOJU36ICSgZAOxgVR0BcG8JxkFRwv5wHUqSWzSU2NNWakBIm45G+sJovgSUaRhZmHNgIwY4lJkD028BzrmVjt2ZaN0GUK0AAcEJsDMG1FV/9tuAaIgoA/CCCK9QNTOSAkSUCMAsqWq4QPa7gAjpSVXSA/C0ADOBJP0jlMI/AE1amLjRWGhiBuyDmKSMkpx/ihjRACLyaS/dZxuqEAaMKF6klDBbRiCFSZklBLdCMiN/Cb1NZwdEmVIgKamgM/stRv17N/uVWTcFqg7UAA+smMI0kD+IIATGBN9ZVVjuIhVkqhkvmHnzgIObgASrChHYdshiKmjCBxkEiEoKpnQaAbCMAFJ1AFRnAcUeCmCpijR3UJg/l++Skkr3ijuvVwrCE/CACo/RlTE7ob+lWMEgVyiMoOlIegYRWrdjEEVyCpzDQnHGKpV2qhRzeQXNeCGxL/MIEyZ6S6CJG1Xak6U4FSBHbBBCWgAAhAH7PqpjZZX55pCBVwfBkFBGZHhzWIjxPjjcPaRxvCBEKiX7s3mb3Hp/hAaJ4mIsQmb3YRBXCXXlRqIyVgBNvaf8Q5VcEGrnD2gWE6NpIxnoT0JBu2AlTQriPwAi2AIYSqjceIjItwAC+GAAxgThJgAvHnBTc6XDnKJiYQjAP7o2e6A+LDBJHTmmvTrOsASPsJqhKrFuc5MxQ1cBGqKqgCA9saZtyoK0aIGObHWSLbanhIZjHSAsUKZzXVLzAgoc8xBSmnchFGs4qAPxcgG7jUPDZKnwp7jOTHoPTTnyLFtdrWdBzLgPhA/wAHuiInO7VkUbXWGilamypyiKl/+X8WkpP0NoXqGn5UCQqca5SEe4aCorFb0gGGCxeI2IlgeKuUIKwEGFIZKhkL56vnQ6AdIIiwFDj35CF7WXkrgLgKi52B6Q4F8LAbCrn6B4IDNyCrAk8GYrCWBmYS5KGEsEgMAFPlRlOetaksU7KlK14Cg7pksQMdEKR2YQR7ditk9aH4xxxru7rRlKeLNZmphz/jYbQOVgU7hADDS6uDxbD2YBjL6LjVwbwU25HPC0nIpEy1axqzWZPMyksFAE2NFFMniGzkeq+OoE0YRbhhhX6w8wXHgYlH0BeQA3C3kmDHiwgVgD83ULrBO/8AwqWnrrkD64QARUOwDnYC5rtNCdie4CsPCRBZvzgdYEC941MEizYlyuTAOXUgPCA+UQCLagasIpJjBkAk1UG+kjqUkhAAwSgARPi7KWu1I4AhBla7AExeYaxgkIABSDy+VRB/N5xpJ/AFwgo6Ptxcf0IDXhYGNXSdilsPBABIQzhIO4AvScBqiQMp2SotunQd9GsaYoDFhmwzGqic4+hjcmoJCcC7yZOXbqeuznscPBAg9HGAHRbGYhyADbI5RksjY1DDkalYy7oCL+A5PVoI7lRkM2WQppEESPCmPiin9iEABvA8T2M64xCMZLFSEsADwkc3TSAzapJMkqRsy3b/fH3xZd02nFoMALGHAAVwsn/CalzpwYoAhXChAKh6ymmMK8dBBAGyJ648Vx25S/i2hgKQLMTGxLuRy+PMWEbwSwgwuGtbqc4iJTWMGFrQfxVsGQRQACLQABqdLsRMPN8QAI3rGyAczzTAztIrSZFUyYeUABMwLkSAMtOmy4zVrWEizQPQhl/6umcLPoiRAaYsliiLfpJKBHYBUhvgOOzLz7D8woSwSRTQN4P0xe+qJYTckjNggfnyqX9cqfx0Amy6N0kQ1kMwBNfHBEwQgQ4gAH/2i+KQq2pxxmSAMl44XgwcvSftaNmRJRYAWgRdBpqcpa3ySlyCed7pnpZgfIgh/6LkWbZRWiVmYBcaIAFEHUivDMpMjZ8N0hy/S8x2UdUVNwWzzJ8NjU/8VALHCpeoPT6kJQ6b9IuRESEeOI7WZNfKplXwgQEWAK+/FSAegC/zucvlPNLjc6ZG5r5O+wjHyaACvdgoCFtVYgJEkDCRHcEIkM0QttSv5o0BXctFFnieTUcL2hcZQAK6ck8oi1MFIlqp7VcGwAAfAC9tLYwckAAR8KhG8IFPzM0Yu3O2nSSSlgEBwgLPcWkUTNM8eY6JfX4e1ymHzAl2ttAijGgf6C1cqdsDcAASEMED4MTXnYKXbVsGoLe4BFddIK27gWLehJZ2EQHwsaQ14iGlDSKBu//eG/MABwA4vNk/2SDcd/EAv+ScE46GtB02/U0IX0kWJrABKWwXLClfgP0eBimaGpxoYMqL7pwInOujXsq2Ql5fg8kARKJv4azUHs5RKCNIUQ1nTCA+KGY+Z6DijhFoq9FvCJZscSdhPEAEEa00IuMA5O1CRgJC1kAbt5V8QW6100LJ6GXbh7AsGrABl5zJTt6x7vGWiDHYOMc6VR66nGCq8czdp9fP6xPXby0d16yeZO7CHBUj80yeJ9AFO4TiWpCYagEDIeLixAR6d44kG7ADvzQE4W0XSTAEOmAENPAEVbADLIAGPOBrGtUlcvdrzjCP8VwFmrmZVkswio7XgWj/Fx+wASJg4QMAnJPOYkIgGds75ebGZ6E8CQmgnytDbKFOM1/wBDngABeg1qERAC0tADkwtT2Q6u/LCCEgAJEV4uk6U0FczGFN6zT3AhPzu8V0ZT3ilCxQG1sYA1NAFkOABEmABYu4JgQXRl9kSD3nDDKJKVWnzeZ1TMnE7YkgOg7wxTIobYVsqx2g4WackHp2bA2eCTbN1iP6J13ABApg8JydL0rPLhye396zCPHLoCIQlj+MJl2Q9ObxpE0plmE18fz9aNWBBjDABGZTBGN9aZG5hLNtsZUUobJ18ssAz5xkKt254F8zMMlWMBUv7YIwOArwxf3ykxRNnCMABjyK/wHcS6Lm1sJ1qQmGuAA/HVNVMPYKAM5wGa8Br82qDvWABI6pqk8oQNB7Q7H/B6FdH+NSyn4bqmdDVXGLWChRnFfQm3Zy7Ay4twA70HGKln66vuhwPwhHrjkzUgXhrIB0mXddmpmLD7CXzQh3CReDOx0scOo07i+VrepERMd2N74nSCgrOzomSVwv+SV1DsWp7yIjWTi5ODk2JHCxP/vRW8m1zwwpf2dowKG3xvt57/uZqAgVUHeAMDAg0uGhIIiYNjMT47KCclICg0h5ASAhsVFYcrLi8tn4GDnSsSEBgJqqusq6SrBAiaiBKmGyJRCbq7s7YBABS8n0ObwiWjLiUf9qetoKEICQe0FwmdmxeYKCUpx9csibm4RUM+MCiWxd6DFSwol9EnmcvLHMrFqtzqkdEzNT44/jb1woUfCOjTiIMCFCduwOepC3rJnEiRQrWryIigC0bwqI4MMGalEjR9zeNUQGEVM9igwowSjEJNaQfaEglfBGCUEAaprWaXMxctuJc6YwUnTAC4EACxu/Oc11ZMMkSkaGfRIaz1pEiRWQChLgAARPax+1YY35VNAQNQDJrRj1UN26du9MniulshUmTWVDBvQnsiakgicVGk6YDC8mo4wbO5Z4wKkCDmU98QvsiODJxPPyXgQmaAEPD6AFIegxENKXppREqCw0AiT/0Ks2zy1+rAoD67RJFzCBIUKDBhLESYhoSmSDiJw2rGauTfQ2KwzUcQk6kCoT33XYzHIr4XXXkCJakCD5gaNtjEcnGdat25CzZ1Z7YeezfHnROEZBSxJmWJhhD2m1FW4GHkgRARZ8w4AJ1/yUn0jPwYMSgfNZREEsKuygSxS0QTJVLh/Up45stMGlGIIAWMdbLggsQIUUL7DAGT17hcdCBxzm1INzj9SWUist5RIBLfdw192Po4QYCwJUuNBPej+g508jg7n3zmAUyiedXkdyB+E+i2D2nJYAAihgXBaupGKbCFaAky4KbFcChGOO2R9cKXV5UQUZxMJiTlcI1c0u/xpod40nxACZ4oEftDgAAgpMSkURRhhT4TyaboqjOrv1ONKEWXXGZgGANiAABrTQmWU23yFzhC4ZwIAClDVIiV5bJL3n6ndZNUoRog+BqShNxl71o5lnGoSQmsoU6Ga0BsaZiwAm9MQJfnfyt6tBe7KJ0QO8KZDsCbsJYoApdP504qh8OhaAAS0q8IJZi45yFzr6doDTDgcFOkARNCHLKLCoDGkaBPYcmU+vdnmwXCwK7FAnULfiMGV6ApXTq8MoKgaul/OkA6a9Pm5T0rJp1kiPtC7jpsQ3BiQHGzaWbcstpnsaOIHEUpyLgA2uGrHLDSM/qOiud0HrmAbypkWvzf9Ji4pSXFY/1NQX61Ar8MDdZtolB6w1sIp2ZWWjZFYc4CKpA4R4UHEMF2esHkkdv8plyM3sxddH3ZlVDMrKMrQyOqS++3LiFV2QlBKs3rztPl/vbOABDGykANznDkCuDQhsLsDRlVEtD+JGPbA5Igg4sIUI/trsXLvMHlbFRghUwQnAXUs+uVYrgcA4IhaUzTDarn68gRAFqMRXnSvILWV6dQtu5tIXWsQ3WQex8173hCl0dWIE2qh4+RdxkFQDmiAt5p2S66yM6Y1Zh4AIJRixORXUUhKV9vd5IhSiMA0jH1jAn3ghgAfQDB/sOpbdTIKl7j2NCVnazRSMVRPk1QP/TjlR2MKwJTXNRKcemNiEPmYgPeltDGXw+VXLGsM8sgxreypr1tX2ZbjD6c18PFRFeIg0MgZCDk8ZHNUAHxMCl3ACf5BSADrOFjj4HbEiBdgfJQzgABKQCEygcKDgWnU3FBzQB9mwQS6KEJgiCpAZAQBYkT5oH6nhLX4fLNHzoqTCFabMW76TX0WYd7R0hM9qOHzWpnTYw0RyJXUMYFgngKIfPPXuhSr6YQtiY8VvECKOgGPhCBvTldT14gBiyV6J9JEf3gXOVVFs5QpsRwMUEC0WaMSMFIsCAA0AinhB/N8tu1Sf2NzxHwDZj2DwNSBSqUgl2tFUIQ8JTRsxc4eK/0xkBHSxgBGxyk7um+T1DhQZSMkpLiUrBukMZhGnfQMB2OHJ44CSyqAIzpWrBA0VUECDXPQgjZPEpUZUx4EPbtNh7gJXNWJTq8sEREJpc8iaojVNvkEzohRlZjUv2oynqe4BMTzlEBnKqCka6J/izMkTFiI1YhijdNRsRQAOyAsHGCmIXIwQI1SaLHpuAycCkKU++fnLVIDmjTPdTsnmSMnsYIubtsTbt8xXUT9idKoSuSYlGOBBs3GnWN2UolRxg7CSLsAGBcnS1LzKGBAALBcKIAAgOflRVSYrjP7xASIWcAK0qA41XgsqAB4VKZnCUS50udIaQ3aPbE3tQ1t6Kv9VHwvZdDZlAe0cC9xg176berWlBgKsOJMwhV21qljtsg1nV/HDXRzgraPL7E3L5L0WMiRECCgBTAWRBAyWNkgVkBcCPJidL9EFgofdWyYY2Mm08TF+X42sczGagKchIAJimak1fIKfY222fASYgEafAto1pAZt2aVNQY3SgKcgIAH1gau2JPTA760sB5TYAbUQEATtBtUrC+Alq1roUGVK5EhgJG6FmHva5ypYkcETwE4Gi9Au5iykzUVQanWBgCFMATCvjSI830fhBAcgrAwSHbGy29eU2dBZ+ooVIo5wnFhc4WQhFYEDHLARBvAyju+JB+UGbNQzOUR8h1uwkZ//2zNBENW6HynWwLbbQxI4JQlo/At8h6FbUazxIs9wSgYi4AAGOKBv5cSyXK/kLfEZUlMxFsRLqNUjqzQ0GSzYTX+Duz6/PezHA/7Sisdn0SMLmqpiixR1dyzELqqRpYrssnj2GZBiptFYOUORSFnhgAtoekFNco2Jyxw7FiKTZdJUSQBuAAsGSCUWPvDRHFWgi3aaci4A5nOfg0jINVV40Lx2GS4Y8GAI38fVlt51m4hQmrvmtx8XkzR/MJjBLTumArvhKE2RRF45l2szLJsmK0gAAKSErs6U0IGrgbSjWDCgAta1D12MuOvs6UtTge61vRVZAAbMQi80/R9jz4tR/yEEL1Kco4FCU1jM/RDxEyF+jFURIYAE5BnbgcPpHocM6G+iAgIIWNsAVL2B785Y20ASwQIYkAGlMOADeA4yJ+LTR8ZIdFP1vrfNIbtF7pHXGPBOsLQkkIAbHMFf9XoeP5qdR/eBGOCO+S4CaOZeGtskzTkkn0Q0AgwFkIAITTkNjS19AZ3QB9c03Aw6LxJVn9987YnLORidenZF5txOSE96UyPB6MdEDBHWhqui/31gmtdcIiTORQbgea+s8CCB9KkGbMoeYFw6JqJsrzzO+x1bF16ah8LKFiSJaXdVAknAjqGfAhxQgW06+X3wQ7DGJYKBB8geBg5Ya37ljO4tQP9r1nNhFpcsD/zgW1bPxM1bZLcIkqODfqGiL7baV/HwB1h22NDu5+tlLoELjzzxI3gBNI4gnY7ig3DWe77wz49zx48fTYc1v8vai11IMpv5eXI+bjiOLg7wrbXaLdjmMcIBtHcu2ycqMAANHRd+6td7y0V66OeAvNZecgE+tpZ+zWMz7aNw9cdHnTEtpqEqyNdAKWZ/bYIUCHA5sRBnBHMCdiUIY7YYrIUkyMRczTANGcEGzdAGBTARNYgKASADLhVsbqAibxACFKEElSURbAAHBOBWDwhDwiKBztKAzjV3TsYtosWA/ycR4SF90wc7H7ZbdOQmAiAAJLABANNqKoX/ArUjCBmQHBFFZu9Wfs1wABYAAQEQAXEQB+zFCnIQBwQgA2+AhKgQAhaQAACgIHPAg6rwBkIoAXCggwfyBhZgAasVMgfwBhMRAgdAB3HwAHVgBxzlfsH3VoJEZEmlYCTib7NBNUujhVUFcaXkeFtFWmE4hQfSAIfSZojgA0mzDbNUPzokLDE4gqsQAhRgAXZQBxagBA/wBpnAJ5B4ACHAUatQh3ZgB5s4B/WWAnDwBvr3AErgfiHgBg8wB3FAByRwLZKXCgUwBw9gAW7QJWxAB9QYBwywBS1AB0RwfU7Ycs+EikbmSCGEFZrXjxVxALYTiW5nTmqoQaMoEagTdmzl/4uP4A0vATKI4m7FF3eo8AB0IARzcAdv4DjxU4My0IlxcAdbcQB2QImy9wCYSHPl+JLLE5OIkwAPIAc0SAehGAd2cAc7UDoZcQDwaAEF0IkmIB0UUAABQAFx0AI0QoH+uDDNVHUHeXwM0zDH42MIdiCONgBExZAV6X9YyRgOkGyIQAUN6QhdAA1MMEKmNH5b0pEA4AboiAYtMActAAYD0gESwIkWEAdvwAA1cgqc2JJE0AJ4gAaU+BCm0Abh2AYfYA0weQd8cgBxsFoS4ZJvgAeU+AQeIHlw4AYQQJIqOZQAUIQJwABQCQMv8ElUaVwzR28QWU1Q2HsU4opmOREgkP8hgqAAwkaQczSD74djEmMyjsCCGSCUzCU6hBUfqekKmEiJO/AET9ACLeAv0fEBB0AGG/AGGFcUEGABdOABLfAELzAHuEMKpsCaFrADItACg+kAFIAXq7A87wIBdEAHPPAGLTAY7ckMdsCfetgCnNCeqJAAdcCfDwAD2Qmb0imbjQdIAQmBGjlDNuSV4NQUAsBueOZeKmaYthksSnABAgANC1AFybkCoPECe/KcExh3CvIG7ugAMKCHc/AFPrYBAFABHEAHW/CaAXYKBWABc2Cdb6CHeRAPpsABrdkCedACbxChvqMKbsWOiFiPLgkDc2AE2ZCgCtqTLXBZKFAConn/CgRwAB9AmHPwn6PwlyRaeRU1p1b5RPNmoYzxUpQQiSB6Nr5SfnIaLCPDAjqXNEVwV67oTIP0e1zRmk+wAj7gAxaAO00qAYJJByywA2/ADiwFAXawBSwgpTYwBzaBpjLwiXrACQwAA+6SCiEQB47zLhLwATvAAC2wDaRQD0y4AVtQAnmAAm8AA2jqkSYgrG+ArG9xpsbmj4JKVcwUTVaHIHFiCVX5X/ARebxpIG7HLi4AGkZgRM+Za7e4CndJASXQBYK5nkPWoxWAjTtgqzOyA/dZlBbwoJTYAvCApgdwBxTwBlVwAqwKF5LHBjWKOJiABsjqA2Q1ArikBG7wBh0A/wNU+gIMUJi4FAJ2QAFCugRGQEbL6qwTem9px6wT8XAGsG8CtZF2UVw9FIHD5gJBkARfYWnOZIojipA70KooYANx8Jr+Ig8AkAB0YAF4ADHweQelgApw8AHweQJ5YKBjcKamQKAfkK8o4ANGgCJs8nouyQBu+gYn4AG3EQf7aQYv8AQwkAdDgaaH+QA8oAf/Sao+ILYhK7Jz+jIhsBEZEFD+5T/sN5WKM4zOMwxFQAVCU7PrY4oP9Ucb8AC2eo5HOgdN2okMMK/q0AIWsAX3CQd3QAcvMIloawEMMBSlAJSW+w4t8AKuWpV0uAF48AZP8A7ESgDbSATC+qBQGR1ucP8ASvABInAHUUoDq0usd2u8+AYMCJCycPR4c9EsxSl3jsQuLPQrpSBDfkmue2MHHqC2IroBSvCdJLOpLaAYBSAEPDACHQOgJVAKHGACo8EJMFAFyMCBxKM31GivddGwzFAAEocGE/ufsEkUdIAJdnCrbzAHT2Cpx8vA5vNw9SMy2pMm0Bu9NJVShNKV+jKuzCoBPNapSrtFHoAGSRsRmRAb3iOg84APWtOR1JQAdwA3nSp5fva8PboXPCACrmMQ99nAPSwtDxeWImNUMpq9nCe93jF1B/ZEUliyHTx+DnUKEXiKUbwBMXwmEIFrEuoYHbA9xXsJeWY1ROFOJJNMduv/ww0MxDrWeNe2Ds9LwRc1a1tpWEp8vYxrFO1lOAkYrVHseDh0OIckp1U8IMCkkfPGDFKcd2esyA5HCQKwiEVFMs67m2b8hEHWY2mmZmSRx3KaYMyTgFHVdvR2a7X5j4WgFYuMyo4BxL+1xhPXe5nyiuUTx0KGcYVkx4mkrYLbj5RnrTSXyr98EeKiOoM4xpGsoUUMx7iJGCwGkLEMzJcwEbz8zNPMChAQCxPQysaMGH1Eybghbzdky3jqzNRMzuXMGMIsCBSQzRmqoSBzZBLlx9EKyCVrzvVsz6ygUWqssuxcy8j8WNAqz3ucy/dM0AX9AQiQAfpcyhLYzv6clWk3/1GDV9ATTdGt8KF++3jkh7PAR7L0XNEffc9yuRDHPM6CBsogjdIpPXZkRkPimad1KtEqLdMVvUUt7dIDPdM5rdODlnPkF6g7DdRBPaf9ptG3LNRHjdQCGYdm98ZJ7dRPPVU17cYODdVVbdUQdQ9ygb0lfdVd7dVoB4Vb7dFfTdZlvWP7QtVmrdZrLVDz3M1sDddBXaEvHdd1Ddd0atd5rdfUENN77dd/DdiBLdiDTdiFbdiHjdiJrdiLzdiN7diPDdmRLdmTTdmVbdmXjdmZrdmbzdmd7dmfDdqhLdqjTdqlbdqnjdqprdqrzdqt7dqvDduxLduzTdu1bdu3jdu5rf/bu83bve3bvw3cbXKIkDXcj1XcNhdsyP3bdsAYx90MIfDIE8HcFcGEjUEHP0gR090mKYAb0c0K2m1zS0ZVOdjVBJACdmCJE8G71S3dfE2HPFij6d0KblCJH+DcrcDc1+eS+ocJCUDMZROZfpTfOGkHe/BVcNCT7HUA960KSlAASqAEcKCZ8hMB/UgByU0RBWAHEHB9N3g6foTdjCED5UgGzQABN+gGRGsHWbrTMmAB01AH5/gGomiMb0AHhKiHXciZzRQydKDOIaAEgmgBZMAnIEAADzCY8Ijh383j1QwHFqBAG3AHJCCY4A0AcuAGRYgKRVm/+N3krIDk/C204NL/jFDOACJABHWQia1wAN7oicxYtFNkbaZzl6vl37LXt60AAgicp+WYChDL4LTwAF3+3ercgwfgBt4NACOupBYAB3bwLsh4ACkQB3PAAGZI5h4UAAT6ACHw1g9IAHHAARtQB/hIB0n7l6mQAg8eB/OgBPBpBuQK6aLMChQw6HSArC0Aw22bCs0YBxYwAlOKBqneDLNO6IgYAiTwjg/AApT4lCuJSwGghwFg4HZAmVNk7CxeAEgOA2ggAp04BwcgeQ/wterqOhbA4pXojHdgAfM57Ec06Dx8pfDoOETQibIHcsBEAp2YnbfKA/UQAdhRlJjwAe+olHsz6CyOChVwpNeC/4wP4JJEngoJMIl6aAdEkEMroaSW3gF3EAf+Iu9IGQcUYAIiQIk8sANxwAIKT80SoIciAANH+gZa07CpQAdW+wBoQARbMAeU+AZaDACQjg4GNYk78AJ60O5TypeSx59dOonDuwMsL/TWwCYh0AZQCgM74AAv8KAosQyZKQIbwIy4/gDyvgpTT+xbbsC/DgNPAOVbEAd6oLQAgOuZ6wNv8AgPavZBL5gtQAN72QJVIJQKH+8sngAWQAId8AZEQAQWwAItAAO2IbScOAd08ABb8AJcDwNHEKcAkJkSQAdKIAKXzwNWSh9ln/aqkABwwAAc0AF64DpbYAZzoAeSR41s2v+leRAdqkABJMDu2ckHsru/qAAC8PjxMKCp9GkBU/vpwOffLqkHt8oAgskHkUDsSA6fODqJ2HlJXpwKaM8mdQiVeTC6Dxrzb0AIReHiQS6YeqiHUVHsHUz1+Anlx4qdMa/ApkWYHe/+9gr0QQ8IEh2DEgCGAHYWD3cwTyglIw4MIx4bhgQmLXM+Pi4rFjAtLRuFhhIcDyJzRjYrKFVvdx2lh4YPG5W0tR9beIotMF9xX5QdGwkWb0ocIi1vfCcnJR6zhSlvD3FbOwweHjvUuocSD4S1hiFzcXTfX6AWOxZPxrQbFBbyw8W0ARIsMBbivGnBwEIVY+NIzPGQB2AcTTD/Towgda6ixYsYM2rcyLFjrQRx5jB44cwHEx+sTngoVYCBHhhj5uQJaERauIp2NgxCaCiBuoBPLBix4MyCqxL0JBzAJ3ROkRguqqChiFPnIEsf4eBRJxDYG3mQjNmJAy5eizh5njzZQa/qTqyHNpx902XFCwdow0rYW+esgj5UfMQRCIMHVQm4XsRRwBhfHrbibHW4eU4ChTlvRgDM8+aNtBEIZex9EHAgikfhCoXoPOlJCxEM4typZHFDOZ61QhCV7fXNnBYWXuSKywDGiydxnkzD/YHOVxislgS0kKuQ7Tk7XvBR7GPO0Vkew4sfT75jiDh1iAKkoiBk8JUSyNCJ/8OgRZ6QcWDYsEm1Vs63tbTxABoC+WDDb3EY8d0GiTzAw1mDUdGDCxKB59ZVuQUEwxucrPCGEV1YwMdyStCHxg4jxDPYijv0d8h/GNaygSpv2PCGQHl8oRcACbwRDxWbxEGFBXksR9EBD6jDIRVxLAEDDKDtVVE5lNVCDnYkjREbDTaBt5dOd7zUAgoVwpXCA0dUUQIMg/FBFm0V2RbjORsQlUdRoKBAZJRxWTBHcHG8YOQhdCjRgTPqGNgFMfQkEFugJQAn5BKu8FnepZhmupEdb6gSh2BUFEEFFSuotIEJFtDRwgs22DCmn1TwFxmMuAEgCJuduPAQSgtyQIIJW/9oMkcPVPRBIWguGkIrXAAQcAeRcwzrgmkwTFKJCQw8wIBrceDjQxClWuqfVbVKQEJAY9oQxwgjQGIpHbBaEIQLLliw3zRHJtLCCSusIJ1yyEZGpYVWmiCCa1+pYwMkw+2lBAVd2aeSlIYooWocNjDBxxdPzBFWbbcxe0lsDdW4xJ82CIVUPaAYBymyhgQQBwc8zPGEEQmexjApZNhB2g47fMHHJjFUmqymSCdN3gNoEhRQEOyBa6oEyCRDxRJGgMhErMvNSi6zCWTzxgo0GKFOUY8kZe4deQDJ2H5VjguglbFtAm5ng7XQ9QbPBlVkC3yEO9w5y55jghkvzPFCHt3/eOPBVKVssIUFTI4qWLhtkcMAx5Se/FAV4h4ycGS2igKDzSiIFNZhB9CxQxUwUNHF1Ie4QVRTbzzJwMdxhlwRAb/NgUKNmygolLgbDMbAfcpRg1UFb5iL2UNkMtzWAfRB6RDGqB2t9PfgXyRBAVuQBMMKCSY6O3wBbAEGcDV+1RkKT8St7NcfPfQGCjbS8NsScUgbKQqxlM5YoAdXgJv3CmclIZxuVF14Bg1aMDtkzcgzJcggMFbQNYsw8BAWAwgfgEENYzxgLwlww42AExhixaEL+NpLAOAlLD/Fxk9vwNeUJkMwK8HjUYKpSWri8gYGTI8JKJgILR7wgRGMzQI0/7gRDHhHJ99VhAd3OgHxaHI8giVPTMMY1CUkoITg3KlIlNgAVcigDhQ9iT6PCF345kjHcXTgCERCAcau1q0vwAcxHhCKQd5hAxS0AGaEw984yIAGz+hpLj7YH1LWSARGvOFkS5jkRT4IABnAIWJMYBwMyBTHWWzgA7tz15PKtElFHgJ7O0jOqkrIgTkYJmwieMgcggCV9hgkNQEgQ+7yMAcqGEExVTiBAHdoP1NYAA1s6gLOODg4Z0YEgIVU4iEsQIR4RJIGBXlIlMQhp1oR8QVaXNwLGgEKbRqiTvnpTAadZ6UyMgUtATvEYGaTIjaNsArNrKNAlSaIXD7hBETxAf//5gCDakggWJ0xjkFWYTZwiAwRrjRFB3KoReTwITACLAUc6IAHZ6zARpr0YEYBcIACeKAEyoxUHqLRJcTcQW+U8MAD9JBPlc4NhHR4gN74oIgtkIYs9DBDNtSxBCrUSEOG+ZIoEhqQOERjmecYnUXI8YAbWUABRtGhDwkipFINDkkbcGIoiPIFxbSgmu+04jlIQJYSPEFHJUhccqrJAXkacYppPIcZGLADhL6BURQDQKcmk43B4OMNAR2oZDMlAVS1SzHoLAHQkkKETs00D4KCkAX8eFE7CMIcVpLAITVDn7PQIIkEs4AJdvCbaDwBkTg5bQ81yi5ILIJdadxLZUX/UMIO3IEt3lOWbsVBgBAQgQXtCgUD6gMDNFADFblbAYjIFA1nwCAXpwRFHlL2ArzGcEq48F5lgfECnC0BtiK7UguM4AOb0EIGCcDFDjIIiQwmznm6IAdqzyGEbuSUGh7Qg8eGE4AGtStScRhDYGtRAQsYsUmyGodViJAKmH5mt5MNMaZOMZkUMayEA1TjS4HbLppCorTLtQgPSpxB/hmtFJXVyQ7u0FsAezDGqcWFNzogAg6gmBaISUoIEpDYH++EdEIuhgcebL3JlKB6/fWwXhADXWUe1Hreu0VbKpLkESizkBJJVmULG1NxfWkQjgNuCYgxznHchnSnBTBiZtTT/zbwYMr8TcuEd2EcGqC5mrpVMUxLmVwRO9ojSZ4MitUopb1IeidTZhc9z3GAPavXKt4wcwarMY5IXzq5nVbj0b6kak+rWbjj0EiqKb3VnRhD0kM2hoo1jeBQe8MSb850McZckQPoJLllbhe7SF2ZEhcjvq7GdK5dJIEP0JrMqh6grZJMbZ04bsir7kCL92GlVgNyyj5+tLrLI1xKCzexrG53ttX7bvGx2tavZrW2MfJuPNe73kjrt73fPW+C63reukYyt83Nb8Q0uTJqfMvDTeHqVfe74vmeOMUfDuvKVFzjAAB1UjyO44hfe90oHw/A7V3qlZMZ5C13OMy3TbqX1/98sh3n98ZzTvOL87znP9/qzIE+c4Fz5OJCv3lGau5zfmd76EBPudQfzYYQKEEJU8+61ke89a5jJABWVwIEvE52pIEgAQFIAEcgMPaBgoDtECiAuhMA97Z/nQ0BKHsn2a72SxGADWxng0YqAHi9V6QCaCfARghQgLwb/vHkYYMcLnEATlfgEASwu0ATIIPc/E4GbEiB3L8neRBiPgS1KMABBB8AJSj+0QFgw+trQYDOGyIFBxDQA9og+L2z3fYVkYHj936IFNQCAkowfgVCMPyyVwACIDBE4TFf+UMEoPmQz/7isV6L1R9C9YeoAPbpKIe+o2P0zQoBGwpg+9kjTfb/tXiAIUDghssb4gAhAD4AUC/Q1hcAAsLHBjJgf7TXdzLQefwnB0rwAHDwBnagBCFQAMZXEWnnH6/nfbenfp6nd9MnOvFHgBDgfto3ghcBAtV3fZdXAHZgCDJAB/aXAOb3dxmBfuSheYjQEweAdUs2R7VHYZUHdickAQTQUhN4CDb4PQTwgBSmBGxgfhVhd9wHAHsgGqcQAgdQfRXRey8CAEAIQhDQBucgByL4aDt4DgXQexDgeBRge0jyfbMHAZN3KfxHgurmBocABymgdgvII60TM833AFhYEW0QAX7nhCAQAhAQAg8wdkpAg99zhOqXAnWQagcQABRQEU74PSBA/wfm13qVJwdvZxGaB4YA0AZUqGotoASRkQAiGIEa0Ib7lwB0IIIEuG4y8AaHV30yMAc8AgBwUAASsAcPgHUSEAIUU2Fj6BGwSIeOlojnkHcP4AbmAog8wgEUUwB0gBE9kowdwYqYp3YzJBpkIH90pHmvx3hvYAIboARCQAFkIGJ20HaoUIkhQHiGYIMVMHtVBwBuYIynoEbNsG+HoH+vR0YUYIwcIAMfEIjrFoeEMoe1Q4EgEAfBRAQWQAoFsG/DOB4EEH0E8AbcyIx1ZIfPCAAWwAFKYAJzIAQVAIwU8wbDJw50wH+R0XgbwX8B0HkVQAeiAT0mAHUcQQHm2HsBYP9/y8AAEsADZkAC2UhzAyV/SgEHQhACdTA+0AcAIXh8h0B/AFAAa1gAQvAGOvEGaDByGwiDFcMBFoB4IYAqQRdibCB/MwQAD8NzpIh5FaAEUqkEzbEBZKCOUhICTal0FSGUAACIbymSc3SXhpCPFkMCPHBT60gKJtB5bmAHVJhzISCUwsV53rh/34gRbNeRLch+qHALfvmCszd8l0cAr3d5+QgAJjiL55B5dhd3duAGCUACG/AGLikEPGAC9qd4oFgLAeCa1kcABOiNHcmF5/AB5iKWB2ACdyAEHAAAvQeRvUcAbhBMFsCXv8JkdrAFO0EEyTKalFeXSmAPd4AYCUD/Bp/Zmu53nMtJAOZXAcPpnOGneGoXh2oniwfQIwXwk7AWd+fQeYVyABslAmhgBmrEAfnom0xWWVQDm/OJnMoJABwAB0inmAIVhSwIAAxwAGbQAQxwXB3AAw9QAA8gAxZQAI3IcCCgDBxwBwzSiBYAjnlXAZi5ghqxiWMXHxYABjvgIEqQAJiJeuAHjWAIB2NXAQ/AivL3kX33lnZoAQHAm3dAB1RjB0BjAUIghFGahPd3AARgAWNXAG5AABRQeSqIpJnnBhvZfRJAByIgBDZaB0SwF/wXiCDABvtIAA9gB9NpkRVgAm+QX3hwB3egihlhhxSgBCQgBOeiRh9QZGjK/yNRCqWGoKa++IN2kEJyaQcB8AAgAKUH4KMAUGHLBwcBAAcslY0WIwE+gwrmJgOaJ4ZkAAcpyQIWkCIeIAKkepkP0GAboFSNV6yCWqZnKni+6Yu8+XSE6aGYQoOMuKIb4Ks7cCLf+QFMaaOpkHDKIn8igAcMIAIbQAd3kACdVolvYIX+yIUMaQiGiRgnugM+8gZEwAAsmoMUQA4QIEwEICCngI0VgCTkAJ0V4HKGsKZeSQanwk3Ysp4tYKMcsJn8aFqDKgF1IH+tMz7R0zoh8AHwOagFsLD8IJjAKQJEAJ3s94P8l4l0aQEyALHnmq7GxgAfcAcf8JMYcQAh+AY0s/8BDLCeD0CeTFNZt5gAs/qxIQCrqwGDWFoA79oGL/sA/lgIuycBb9AzAXqSdUIGPMBNIgBZM0YRc0gAk0cHByAEtoEHxCVUfFkAOdqbRAAGFsADJMAA7MqlG/sB8ge4SiFmEketAgUBaOd4dACMtqEH4OASHDAjdJCt1PENw4h40RMAilAOZWsP0MkAbcpk1sinhEh7xWorp1QOnXIieMClRDC2kcuJvokqJvCXb0ACZGABZFBGGxC5pHAAuNh9Y/cAe5BfaKJT5XAHDLAB5im0EACmB7C8ZpCjahkAvakENTOpG6C3t2sCUUULUCqpD2ACJrAHapp3JKm5Tvi8ZID/GM3QAajEIHRgniYQpp3Ei7lhfFdoAkTGuQzQAb5KvjiLKiRgkfX7okJgAbxJB3WAKiKgjkSAKkeakSBLq7dwByZAATlBAeRJB1sQSDxWlgOEdom3f8VaWT7iAdp6DIVymA/gAS2gusvATUrwBh1gwLlbu3nLA382J4YrWVZrCCbwAGDgDf/LvA/wuoQFboVwdXW6gCyABhSwAzywnh9AAVz6j5RGBu7HBm0QfbaiBLKwr5OxA1sgApVlBnTQARxgAiyaAHVwBxzAAYArOXaACkWWcMy3lZWIlZ1GRrKwAy0ABmjgOkTQAUxjG9NZByLAA3hQB5R6QnZABzxABGts/wLNO6mGcXK28sA3zAH9yq6OJwfNJ5idhxgtEMUtQMUP0CJtLCVpWAtM2Cz1JwFmQJ5EYAeNfLRt3DozUg5FOiMU4JfLKwI7PArMm8EWq2oP8CsM4L08bMNmYMNl6wE3pWnEhnmhalMiMAhF2gG1y6VIEqyQtQUUAL8OYgd3wANbsAUm8AE9ewflMGNXMa0/jDT5dwg9C2dAYwaYTAKz4ThJkQCqp45AwwI7wAI8wALCStAFEMHiGngFkM90CaMkYAbmSQII7Q1Fxr8M6rsHwAFEgL2IPGMIzQM7QNJJUQAFQAYsPX9ssLskUMAs0AFAgwYiAJmIbAySysMiEMU78P+TJAoP1PDTJUoCOXFsnGwrGk0CVmif2IerLg2BGiYCOwAGP83DO2AGkUsLcDfRr4d3LbUDRODPs2UGOG0YScy8jUxkNd3IM7K3ekANCV3THDZvG4C7cU3Pd1DTfe24KnwEKJJu3ad4p2CjVpHThjHTGsBYcUsNDA0GPGDUjby7Pk3P4nrPA7WcCxtxb6Fq+OZz5IJvlPY1Rddvnp0UeJ1tB2drB+duSydvqe3atO1utkEl07bakfElQycO+jbaVyGQS/d0q83apA0mjVNcn21ub4ZrtI1renYO5vePso1wlwZnuRbcpIBwsK3ZIlZpplbcA4Ta5FJcoA1uZOZxpfb/dDQn3qztPNIaazZXCPdWXL6m3YjB0nnr3GojcwNnJSSncDK3Z6691LaSdARX3M9dwCmc3ccN3qDm4LXdaNs23hVu3a4t0AdH3q3m3VLnaT4X4tXN3EptzwEObyKe4OOdmLGNcZ8tXK+cCt7GxC23dEcX4O0d35CW4ir+oBkpz3Cm3cwdYO5dcL3dZD1e5DwOlB4uUEbnlAPXoQwbHjfn2zGHZJcS4ivOI5cXAqY149nsaE0XcAFeAaIhA1Hqbf095USX4iO25E++VU0+53QuPtLNhcSY2hdV58bJh6hb4nwe6II+6M1ynBTH3oReC2dHgNxm4on+6JCufR0a6S8nmdyUfumYnn1M/ugsnume/umgXnaOHuqkXuqmfuqonuqqvuqs3uqu/uqwHuuyPuu0Xuu2fuu4nuu6vuu83uu+/uvAHuzCPuzEXuzGfuzInuzKvuzM3uzO/uzQHu3SPu3UXu3Wfu3Ynu3avu3c3u3e/u3gHu7iPu7kXu7mfu7onu7qvu7s3u7u/u7wHu/yPu/0Xu/2fu/4PnWBAAA7

@@ img/upfolder.gif (base64)
R0lGODlhFwAWAKIAAAcHB///B4d/h8e/x////wAAAAAAAAAAACwAAAAAFwAWAAADYki63E6AjEmrtSLevbPk4ORVQFmGwzgBwdAGQKiadH1Ss6u/+xCLGh8vxnv9UkGi71T04ZKtWg/2/ChhzWh1NZy6jjmjVAu0ZqfgpLeZttrebRRIJb/Q6xWPYM/v+/9wgW8JADs=
