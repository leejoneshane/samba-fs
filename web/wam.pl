#!/usr/bin/env perl
# 程式：線上帳號管理程式
# 版次：3
# 修改日期：2017/11/27
# 程式設計：李忠憲 (leejoneshane@gmail.com)
# 使用本程式必須遵守以下版權規定：
# 本程式遵守GPL 開放原始碼之精神，但僅授權教育用途或您個人使用
# 此檔頭為本程式版權的一部份，請勿將此檔頭移除
# program: WAM(Web-Base Accounts Manager)
# author: Sean Lee(leejoneshane@gmail.com)
# This Software is Open Source, but for personal use only.
# This title is a part of License. You can NOT remove it.
#
####################### Localization ##########################################
package WAM::I18N;
use base 'Locale::Maketext';
use Locale::Maketext::Lexicon {
    _auto => 1,
    _decode => 1,
    _preload => 1,
    _style => 'gettext',
    '*' => [Gettext => '/web/*.po'],
};

####################### Include Packages ######################################
package main;
use strict;
use warnings;
use utf8;
use feature ':5.10';
use Mojolicious::Lite;
use Mojolicious::Sessions;
use Mojolicious::Static;
use Mojo::Util;
use Mojo::File;
use Mojo::Date;
use Net::LDAP;
use Encode;
use File::Basename;
use Cwd qw(abs_path);

####################### initialzing ###########################################
my $c = plugin Config => {file => '/web/wam.conf'};
&init_conf unless defined $c->{language};
my $lh = WAM::I18N->get_handle($c->{language}) || die "What language?";
my $ldap = Net::LDAP->new("ldap://127.0.0.1") || die "openLDAP Down?";
my $base_dn = "dc=cc,dc=tp,dc=edu,dc=tw";
my $ldap_result = $ldap->bind("cn=Manager,$base_dn", password => $ENV{'SAMBA_ADMIN_PASSWORD'}, version =>3);
die $ldap_result->error_text unless ($ldap_result->code eq 0);
my %ADMINS = map { $_ => 1 } split(/,/, $c->{admin});
my $lang_base = "/web";
my $itoa64 = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
my $today = int(time / 86400);
my(@MESSAGES,%RESERVED,%AVALU,%AVALG,%USERS,%UNAME,%GROUPS,%GNAME,%FOLDS,%FILES,%SMB,%REQN);
&get_accounts;

####################### My Library ############################################
sub init_conf {    
	$c->{language} = 'tw' unless defined $c->{language};
	$c->{admin} = 'admin' unless defined $c->{admin};
	$c->{passwd_range} = 'all' unless defined $c->{passwd_range};
	$c->{passwd_form} = 'username' unless defined $c->{passwd_form};
	$c->{passwd_rule} = 0 unless defined $c->{passwd_rule};
	$c->{passwd_length} = 5 unless defined $c->{passwd_length};
	$c->{passwd_age} = -1 unless defined $c->{passwd_age};
	$c->{passwd_lock} = 0 unless defined $c->{passwd_lock};
	$c->{passwd_release} = 30 unless defined $c->{passwd_release};
	$c->{nest} = 1 unless defined $c->{nest};
	$c->{acltype} = 0 unless defined $c->{acltype};
	$c->{acls} = '' unless defined $c->{acls};
	if (!defined($c->{domain})) {
	    my $domain = $ENV{'HOSTNAME'};
    	$domain =~ tr/a-z/A-Z/;
    	$c->{domain} = $domain;
	}
	$c->{album_title} = app->l('Album') unless defined $c->{album_title};
	$c->{album_notice} = '' unless defined $c->{album_notice};
	$c->{album_showdate} = 1 unless defined $c->{album_showdate};
	$c->{album_showsize} = 0 unless defined $c->{album_showsize};
	$c->{album_shownew} = 0 unless defined $c->{album_shownew};
	$c->{album_bgcolor} = '#000000' unless defined $c->{album_bgcolor};
	$c->{album_bgimg} = '' unless defined $c->{album_bgimg};
	$c->{album_rowcount} = 8 unless defined $c->{album_rowcount};
	$c->{album_imgwidth} = 64 unless defined $c->{album_imgwidth};
	$c->{album_imgheight} = 'auto' unless defined $c->{album_imgheight};
	&write_conf;
}

sub write_conf {
    my $conf = app->dumper($c);
	my $path = Mojo::File->new('/web/wam.conf');
    $path->spurt($conf);
}

sub get_accounts {
	%RESERVED = ();
	%USERS = ();
	%UNAME = ();
	%GROUPS = ();
	%GNAME = ();	
    my($name,$pw,$uid,$gid,$gcos,$dir,$shell);
	while(($name,$pw,$uid,$gid,$gcos,$dir,$shell) = getpwent()) {
		$USERS{$name} = { uid => $uid, gid => $gid };
		$UNAME{$uid} = $name;
		if ($name ne 'nobody' && $uid > 1000) {
			$AVALU{$name} ++;
		} else {
			$RESERVED{$name} ++;
		}
	}
	endpwent();
	while(my ($name,$pw,$gid,$members) = getgrent()) {
		$GROUPS{$name} = { gid => $gid, users => $members };
		$GNAME{$gid} = $name;
		if ($name ne 'nobody' && $name ne 'nogroup' && $gid > 1000) {
			$AVALG{$name} ++;
		} else {
			$RESERVED{$name} ++;
		}
	}
	endgrent();
}

sub ldap_ssha {
  my($pw) = @_;
  system("slappasswd -s \"$pw\" -n");
}

sub rnd64 {
  my($range) = @_;
  my($n,$i,$ret);
  $n=8;
  $range = $c->{passwd_range}  unless defined $range;
  for (1..$n) {
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

sub get_lang {
	opendir (DIR, "$lang_base") || die "磁碟錯誤，語言套件目錄無法讀取。disk error! can't open language defined<br>";
	my @LANGS = grep { s/(.*)\.po$/$1/g } readdir(DIR);
	close(DIR);
	return @LANGS;
}

sub read_smbconf {
	open(SMB, '<:encoding(UTF-8)', '/etc/samba/smb.conf');
	my($sec,$k,$v);
	while(<SMB>) {
		chomp;
		next if /^#/;
		if (/^\[(.*)\]/) {
			$sec=$1;
			next;
		}
		if (/^([^=]+)=(.*)$/) {
			$k=$1;
			$v=$2;
		}
		$k =~ s/^\s+|\s+$//g;
		$v =~ s/^[\"\s]+|[\"\s]+$//g;
		$SMB{$sec}->{$k} = $v;
	}
	close(SMB);
}

sub write_smbconf {
	$) = 0;
	$> = 0;
	my($sec,$pairs,$k);
	open(SMB, '>:encoding(UTF-8)', '/etc/samba/smb.conf');
	print SMB "[global]\n";
	$pairs = $SMB{global};
	for $k (keys %$pairs) {
		print SMB "\t$k = ".$pairs->{$k}."\n";
	}
	for $sec (keys %SMB) {
		next if ($sec eq 'global');
		print SMB "\n[$sec]\n";
		$pairs = $SMB{$sec};
		for $k (keys %$pairs) {
			print SMB "\t$k = ".$pairs->{$k}."\n";
		}
	}
	close(SMB);
}

sub addone {
	my($usr,$grp,$pw) = @_;
	if (!exists($USERS{$usr}) && !exists($RESERVED{$usr}) && !exists($RESERVED{$grp})) {
	    &add_grp($grp) if (!exists($GROUPS{$grp}));
		system("adduser -D -H -s /sbin/onlogin -G $grp $usr");
		system("echo -e \"$pw\\n$pw\" | smbpasswd -as $usr");
		push @MESSAGES, "$usr ".app->l('New User Created!');
		my @users = split(/,/, $GROUPS{$grp}->{users});
		push @users, $usr;
		$GROUPS{$grp}->{users} = join(',', @users);
		my ($name,$pw,$uid,$gid,$gcos,$dir,$shell) = getpwnam($usr);
		$USERS{$usr} = { uid => $uid, gid => $gid };
		$UNAME{$uid} = $usr;
		$AVALU{$usr} ++;
	}
}

sub delone {
	my($usr) = @_;
	if (exists($USERS{$usr})) {
		my $uid = $USERS{$usr}->{uid};
		push @MESSAGES, app->l('Deleting User:')." $usr ，uid: $uid ....";
		system("smbpasswd -x $usr || deluser $usr");
		delete $USERS{$usr};
		delete $UNAME{$uid};
		delete $AVALU{$usr};
		&del_wam($usr);
		push @MESSAGES, "$usr ".app->l('User Deleted!');
	}
}

sub autoadd {
	my($grp, $pre, $st, $ed, $z, $gst, $ged, $cst, $ced) = @_;
	my($u1, $u2, $u3, $i, $j, $k, $l1, $l2, $l3, $p, $n);
	%REQN = ();
	$l1 = length($ed);
	$l2 = length($ged);
	$l3 = length($ced);
	if ($c->{nest} == 1) {
		for ($i=int($st); $i<=int($ed); $i++) {
			$u1 = '';
			for (1..$l1-length($i)){$u1 .= '0';}
			$n = $pre.(($z eq 'yes') ? $u1 : '').$i;
			$p = (($c->{passwd_form} eq 'username') ? $n : (($c->{passwd_form} eq 'random') ? &rnd64() : 'passwd'));
			&addone($n, $grp, $p);
			$REQN{$n} = $p;
		}
	} elsif ($c->{nest} == 2) {
		for ($j=int($gst); $j<=int($ged); $j++) {
			for ($i=int($st); $i<=int($ed); $i++) {
				$u1 = '';
				for (1..$l1-length($i)){$u1 .= '0';}
				$u2 = '';
				for (1..$l2-length($j)){$u2 .= '0';}
				$n = $pre.(($z eq 'yes') ? $u2 : '').$j.(($z eq 'yes') ? $u1 : '').$i;
				$p = (($c->{passwd_form} eq 'username') ? $n : (($c->{passwd_form} eq 'random') ? &rnd64() : 'passwd'));
				&addone($n, $grp, $p);
				$REQN{$n} = $p;
			}
		}
	} elsif ($c->{nest} == 3) {
		for ($j=int($gst); $j<=int($ged); $j++) {
			for ($k=int($cst); $k<=int($ced); $k++) {
				for ($i=int($st); $i<=int($ed); $i++) {
					$u1 = '';
					for (1..$l1-length($i)){$u1 .= '0';}
					$u2 = '';
					for (1..$l2-length($j)){$u2 .= '0';}
					$u3 = '';
					for (1..$l3-length($k)){$u3 .= '0';}
					$n = $pre.(($z eq 'yes') ? $u2 : '').$j.(($z eq 'yes') ? $u3 : '').$k.(($z eq 'yes') ? $u1 : '').$i;
					$p = (($c->{passwd_form} eq 'username') ? $n : (($c->{passwd_form} eq 'random') ? &rnd64() : 'passwd'));
					&addone($n, $grp, $p);
					$REQN{$n} = $p;
				}
			}
		}
	}
}

sub add_wam {
	my($usr) = @_;
	$ADMINS{$usr} = 1 unless exists($ADMINS{$usr});
	$c->{admin} = join( ",", keys %ADMINS);
	&write_conf;
}

sub del_wam {
	my($usr) = @_;
	return if ($usr eq 'admin');
	if (exists($ADMINS{$usr})) {
		delete $ADMINS{$usr};
		$c->{admin} = join( ",", keys %ADMINS);
		&write_conf;
	}
	return $usr;
}

sub add_grp {
	my($grp) = @_;
	if (!exists($GROUPS{$grp})) {
		system("addgroup $grp");
		my $gid = getgrnam($grp);
		push @MESSAGES, "$grp ".app->l('New Group Created!');
		$GROUPS{$grp} = { gid => $gid, users => '' };
		$GNAME{$gid} = $grp;
		$AVALG{$grp} ++;
	}
}

sub del_grp {
	my($grp) = @_;
	if (exists($GROUPS{$grp})) {
		my $gid = $GROUPS{$grp}->{gid};
		my @users = split(/,/, $GROUPS{$grp}->{users});
		push @MESSAGES, app->l('Deleting Group:')." $grp ，gid: $gid ....";
		for my $usr (sort @users) {
			&delone($usr);
		}
		push @MESSAGES, app->l('All Users In Group Was Deleted!');
		system("delgroup $grp");
		delete $GROUPS{$grp};
		delete $GNAME{$gid};
		delete $AVALG{$grp};
		push @MESSAGES, "$grp ".app->l('Group Deleted!');
	}
}

sub chgpw {
	my($usr, $pw) = @_;
	return if (!exists($USERS{$usr}) || exists($RESERVED{$usr}));
	exec("echo -e \"$pw\\n$pw\" | smbpasswd -as $usr");
}

sub reset_pw {
	my($usr, $grp, $ww, $pf) = @_;
	my($pw, @users);
	@users = ();
	%REQN = ();
	if ($usr) {
		push @users, $usr; 
	}
	if ($grp) {
		@users = split(/,/, $GROUPS{$grp}->{users}); 
	}
	if ($ww) {
		for my $u (sort keys %AVALU) {
			next if ($u !~ /$ww/);
			push @users, $u;
		}
	}
	for my $uu (sort @users) {
		if ($pf eq 'username') {
			$pw = $uu;
		} elsif ($pf eq 'random') {
			$pw = &rnd64();
			$REQN{$uu} = $pw;
		} elsif ($pf eq 'single') {
			$pw = 'password';
		}
		&chgpw($uu, $pw);
	}
}

sub account_flag {
    my($ac) = @_;
    my($result,$entry,$flags,@state);
	$result = $ldap->search(base => "ou=People,$base_dn", filter => "uid=$ac");
	$entry = $result->pop_entry();
	if (defined($entry)) {
		$flags = $entry->get_value('sambaAcctFlags');
		if ($flags) {
			if ($flags =~ /D/) {
				push @state, app->l('Account disabled');
			} else {
				push @state, app->l('Account enabled');
			}
			push @state, app->l('No password required') if ($flags =~ /N/);
			push @state, app->l('Password does not expire') if ($flags =~ /X/);
			push @state, app->l('Account has been locked') if ($flags =~ /L/);
		}
		push @state, app->l('Account enabled') if (!@state);
		return join(',',@state);
	}
}

sub get_dir {
	my($mydir) = @_;
	my($line, @lines);
	$mydir = abs_path($mydir);
	app->dumper($mydir);
	$mydir = '/mnt' unless defined($mydir);
	$mydir = '/mnt' if $mydir eq '/';
	opendir (DIR, "$mydir") || return 0;
#	@lines = grep { /^[^\.]\w+/ } readdir(DIR);
	@lines = map { decode('utf8', $_) } readdir(DIR);
	close(DIR);
	%FOLDS = ();
	%FILES = ();
	for $line (sort @lines) {
		my($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat("$mydir/$line");
		if (-d _) {
			$FOLDS{$line} = { type => app->l('Directory'), image => '1folder.gif', perm => &myoct($mode & 07777), owner => $UNAME{$uid}, group => $GNAME{$gid}, size => $size, ftime => $mtime, modify => &get_date($mtime)};
		}
		if (-f _) {
			$FILES{$line} = { type => app->l('File'), image => '1file.gif', perm => &myoct($mode & 07777), owner => $UNAME{$uid}, group => $GNAME{$gid}, size => $size, ftime => $mtime, modify => &get_date($mtime)};
			if ($line =~ /.[G|g][I|i][F|f]$/) {
				$FILES{$line}->{type} = 'gif';
				$FILES{$line}->{image} = 'image.gif';
			} elsif ($line =~ /.[J|j][P|p][E|e]?[G|g]$/) {
				$FILES{$line}->{type} = 'jpg';
				$FILES{$line}->{image} = 'image.gif';
			} elsif ($line =~ /.[P|p][N|n][G|g]$/) {
				$FILES{$line}->{type} = 'png';
				$FILES{$line}->{image} = 'image.gif';
			} elsif ($line =~ /.[B|b][M|m][P|p]$/) {
				$FILES{$line}->{type} = 'bmp';
				$FILES{$line}->{image} = 'image.gif';
			} elsif ($line =~ /.[H|h][T|t][M|m][L|l]?$/) {
				$FILES{$line}->{type} = 'html';
				$FILES{$line}->{image} = 'html.gif';
			} elsif ($line =~ /.[T|t][X|x][T|t]$/) {
				$FILES{$line}->{type} = 'txt';
				$FILES{$line}->{image} = 'text.gif';
			} elsif ($line =~ /.[Z|z][I|i][P|p]$/) {
				$FILES{$line}->{type} = 'zip';
				$FILES{$line}->{image} = 'zip.gif';
			} elsif ($line =~ /.[T|t]?[G|g][Z|z]$/) {
				$FILES{$line}->{type} = 'tgz';
				$FILES{$line}->{image} = 'zip.gif';
			} elsif ($line =~ /.[W|w][A|a][V|v]$/) {
				$FILES{$line}->{type} = 'wav';
				$FILES{$line}->{image} = 'wave.gif';
			} elsif ($line =~ /.[A|a][U|u]$/) {
				$FILES{$line}->{type} = 'au';
				$FILES{$line}->{image} = 'wave.gif';
			} elsif ($line =~ /.[M|m][I|i][D|d][I|i]?$/) {
				$FILES{$line}->{type} = 'mid';
				$FILES{$line}->{image} = 'wave.gif';
			} elsif ($line =~ /.[M|m][P|p][E|e]?[G|g]$/) {
				$FILES{$line}->{type} = 'mpg';
				$FILES{$line}->{image} = 'video.gif';
			} elsif ($line =~ /.[D|d][O|o][C|c|T|t][X|x]?$/) {
				$FILES{$line}->{type} = 'doc';
				$FILES{$line}->{image} = 'doc.gif';
			} elsif ($line =~ /.[X|x][L|l].+$/) {
				$FILES{$line}->{type} = 'xls';
				$FILES{$line}->{image} = 'xls.gif';
			} elsif ($line =~ /.[M|m][D|d][B|b|A|a|W|w].+$/) {
				$FILES{$line}->{type} = 'mdb';
				$FILES{$line}->{image} = 'mdb.gif';
			}
		}
	}
	return $mydir;
}

sub chg_dir {
	my($olddir,$newdir) = @_;
	my $tempdir;
	my $parent = $olddir;
	if ($olddir ne '/mnt') {
		my(@temp) = split(/\//, $olddir);
		pop(@temp);
		$parent = join('/',@temp);
	}
	return '/mnt' unless defined($newdir);
	return $olddir if ($newdir eq '.');
	return $parent if ($newdir eq '..');
	$tempdir = "/mnt/$1" if ($newdir =~ /^\/(.*)/);
	$tempdir = "$parent/$1" if ($newdir =~ /^\.\.\/(.*)/);
	$tempdir = "$olddir/$newdir";
	return $tempdir if (-d $tempdir);
}

sub make_dir {
	my($olddir,$newdir) = @_;
	return $olddir unless defined($newdir);
	push @MESSAGES, app->l('you have no privileges to creat this Directory!') unless (&check_perm($olddir,2));
	if ($newdir =~ /(.*)\/(.+)/) {
		$olddir .= "/$2";
	} else {
		$olddir .= "/$newdir";
	}
	system("mkdir -p $olddir");
	return $olddir;
}

sub del_dir {
	my($olddir,$items) = @_;
	return unless defined($items);
	my @files = split(/,/,$items);
	for my $f (@files) {
		if (&check_perm("$olddir/$f",0) eq 0) {
			push @MESSAGES, "$olddir/$f".app->l('files or folder are not belongs to you, you cannot delete them!');
		} else {
			system("rm -Rf $olddir/$f");
		}
	}
}

sub ren_dir {
	my($newname,$olddir,$items) = @_;
	return unless defined($newname) && defined($items);
	my @files = split(/,/,$items);
	my $f = $files[0];
	push @MESSAGES, app->l('you have no privileges to modify') unless (&check_perm("$olddir/$f",2));
	system("mv $olddir/$f $olddir/$newname");
}

sub move_dir {
	my($dest,$olddir,$items) = @_;
	return unless defined($dest) && defined($items);
	my @files = split(/,/,$items);
	my $f = $files[0];
	$dest = "$olddir/$dest" ;
	if (-e "$dest") {
		push @MESSAGES, app->l('Can not move Directory or files to others Directory!') unless (&check_perm("$dest",2));
	} else {
		push @MESSAGES, app->l('Can not move Directory or files to others Directory!') unless (&check_perm("$olddir",2));
	}
	push @MESSAGES, app->l('Can not move file from others Directory!') unless (&check_perm("$olddir/$f",0));
	system("mv $olddir/$f $dest");
}

sub copy_dir {
	my($dest,$olddir,$items) = @_;
	return unless defined($dest) && defined($items);
	my @files = split(/,/,$items);
	my $f = $files[0];
	$dest = "$olddir/$dest" ;
	if (-e "$dest") {
		push @MESSAGES, app->l('Can not copy file to others Directory!') unless (&check_perm("$dest",2));
	} else {
		push @MESSAGES, app->l('Can not copy file to others Directory!') unless (&check_perm("$olddir",2));
	}
	push @MESSAGES, app->l('Can not copy file from others Directory!') unless (&check_perm("$olddir/$f",0));
	system("cp -Rf $olddir/$f $dest");
}

sub chg_perm {
	my($perm,$olddir,$items) = @_;
	return unless defined($perm) && defined($items);
	my @files = split(/,/,$items);
	for my $f (@files) {
		if (&check_perm("$olddir/$f",0) eq 0) {
			push @MESSAGES, "$olddir/$f".app->l('files or folder are not belongs to you, you cannot change mode for them!');
		} else {
			system("chmod -R $perm $olddir/$f");
		}
	}
}

sub chg_owner {
	my($owner,$olddir,$items) = @_;
	return unless defined($owner) && defined($items);
	my @files = split(/,/,$items);
	for my $f (@files) {
		if (&check_perm("$olddir/$f",0) eq 0) {
			push @MESSAGES, "$olddir/$f".app->l('files or folder are not belongs to you, you cannot change owner for them!');
		} else {
			system("chown $owner $olddir/$f");
		}
	}
}

sub create_zip {
	my($target,$olddir,$items) = @_;
	return unless defined($items);
	my @files = split(/,/,$items);
	my $tmpfolder = time;
	system("mkdir -p /tmp/$target/temp/$tmpfolder");
	for my $f (@files) {
		system("cp -Rf $olddir/$f /tmp/$target/temp/$tmpfolder > /dev/null") if (&check_perm("$olddir/$f",4));
	}
	system("zip -rq /tmp/$target/$tmpfolder /tmp/$target/temp/$tmpfolder > /dev/null");
	return "/tmp/$target/$tmpfolder\.zip";
}

sub	clean_zip {
	my($target) = @_;
	my @path = split('/', $target);
	system("rm -Rf /tmp/$path[@path - 2]");
}

sub free_space {
	my($mydir) = @_;
	my @rv = ();
	my $out = `df -m $mydir`;
	$out =~ /Mounted on\n\S+\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/;
	push(@rv, (int($1), int($2), int($3), int($4)));
	return @rv;
}

sub get_date {
	my($mytime) = @_;
	my $dt = Mojo::Date->new;
	$mytime = time if ($mytime eq '');
	my $date = $dt->parse($mytime)->to_datetime;
	return $date;
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
	return "$perm4$perm3$perm2$perm1";
}

sub check_perm {
	my($target,$flag) = @_;
	my($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($target);
	my($perm) = &myoct($mode & 07777);
	if ($> eq $uid) {
		$perm = substr($perm,1,1);
	} elsif ($) eq $gid) {
		$perm = substr($perm,2,1);
	} else {
		$perm = substr($perm,3,1);
	}
	if ($flag eq 0) {
		return 1 if ($> eq $uid);
		return 0;
	} else {
		return ($perm & $flag);
	}
}

####################### Web Services ##########################################
$> = 0;
$) = 0;

helper l => sub {
	my $ca = shift;
	my $key = shift;
	return $lh->maketext($key, @_);
};

helper is_admin => sub {
	my $ca = shift;
	my $usr = shift;
	$usr = $ca->session->{user} unless defined($usr);
	return 0 unless defined($usr);
	return exists($ADMINS{$usr});
};

helper smb_auth => sub {
	my $ca = shift;
	my ($usr, $pwd) = @_;
	my $ret = `smbclient -U $usr%$pwd -L localhost`;
	return 0 if ($ret =~ /NT_STATUS_LOGON_FAILURE/);
	return 1;
};

get '/relogon' => 'logon_form';

post '/logon' => sub {
	my $ca = shift;
    @MESSAGES = ();
	# Check CSRF token
	my $v = $ca->validation;
	if ($v->csrf_protect->has_error('csrf_token')) {
	  	push @MESSAGES, app->l('Bad CSRF token!');
  		$ca->stash(messages => [@MESSAGES]);	  	
  		return $ca->render(template => 'warning', status => 500); 
	}
	my($usr) = $ca->req->param('user');
	my($pwd) = $ca->req->param('password');
	my $result = $ldap->search( base => "ou=People,dc=cc,dc=tp,dc=edu,dc=tw", filter => "(uid=$usr)");
	if ($result->entries && app->smb_auth($usr, $pwd)) {
    	$ca->session->{user} = $usr;
    	$ca->session->{uid} = $USERS{$usr}->{uid};
    	$ca->session->{gid} = $USERS{$usr}->{gid};
    	$ca->session->{passed} = 1;
    	$ca->redirect_to('/');
  	} else {
    	$ca->session->{passed} = 0;
	    push @MESSAGES, app->l('Username or Password Wrong!');
  		$ca->stash(messages =>[@MESSAGES]);
    	$ca->render(template => 'warning', status => 500);
	}
};

under sub {
	my $ca = shift;
	my $check_acl = $c->{acltype};
	my @acls = split(/;/,$c->{acls});
	my($userip,$acl);

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
		for $acl (@acls) {
			if ($userip =~ /$acl/) {
				$check_acl = 1 - $c->{acltype};
				last;
			}
		}
	} else {
		$check_acl = $c->{acltype};
	}

	if ($check_acl eq 1) {
	    @MESSAGES = ();
		push @MESSAGES, app->l('You can Not use this links!');
  		$ca->stash(messages => [@MESSAGES]);
  		return $ca->render(template => 'warning', status => 403);
	} else {
		return 1 if $ca->session->{passed};
	}
  	$ca->redirect_to('/relogon');
};

get '/' => 'frames';

get '/left' => 'left';

get '/right' => 'right';

get '/config' => sub {
	my $ca = shift;
	my @langs = &get_lang;
	$ca->stash(langs => @langs);
} => 'config_form';

post '/do_config' => sub {
	my $ca = shift;
	@MESSAGES = ();
	# Check CSRF token
	my $v = $ca->validation;
  	if ($v->csrf_protect->has_error('csrf_token')) {
  		push @MESSAGES, app->l('Bad CSRF token!');
  		$ca->stash(messages => [@MESSAGES]);  		
  		$ca->render(template => 'warning', status => 500); 
	}
	$c->{language} = $ca->req->param('language');
	$c->{acltype} = $ca->req->param('acltype');
	$c->{acls} = $ca->req->param('acls');
	$c->{nest} = $ca->req->param('nest');
	$c->{passwd_form} = $ca->req->param('passwd_form');
	$c->{passwd_range} = $ca->req->param('passwd_range');
	$c->{passwd_rule} = $ca->req->param('passwd_rule1') + $ca->req->param('passwd_rule2')*2 + $ca->req->param('passwd_rule3')*4 + $ca->req->param('passwd_rule4')*8;
	$c->{passwd_length} = $ca->req->param('passwd_length');
	$c->{passwd_age} = $ca->req->param('passwd_age');
	$c->{passwd_lock} = $ca->req->param('passwd_lock');
	$c->{passwd_release} = $ca->req->param('passwd_release');
	my $dn = "sambaDomainName=$c->{domain},$base_dn";
	my $result = $ldap->modify( $dn, 
	                            replace => { sambaMinPwdLength => $c->{passwd_length}, 
											 sambaMaxPwdAge => $c->{passwd_age},
											 sambaLockoutThreshold => $c->{passwd_lock},
										     sambaLockoutObservationWindow => $c->{passwd_release}
										   }
							  );
	&write_conf;
	push @MESSAGES, app->l('Configuration Saved!');
	$ca->stash(messages => [@MESSAGES]);
} => 'notice';

get '/setadmin' => sub {
	my $ca = shift;
	my(@not_admins) = grep { !exists($ADMINS{$_}) } keys %AVALU;
	@MESSAGES = ();
	$ca->stash(messages => [@MESSAGES]);
	$ca->stash(users => [@not_admins]);
	$ca->stash(admins => [keys %ADMINS]);
} => 'admin_form';

post '/add_admin' => sub {
	my $ca = shift;
	my(@not_admins) = grep { !exists($ADMINS{$_}) } keys %AVALU;
	@MESSAGES = ();
	# Check CSRF token
	my $v = $ca->validation;
  	if ($v->csrf_protect->has_error('csrf_token')) {
  		push @MESSAGES, app->l('Bad CSRF token!');
  		$ca->stash(messages => [@MESSAGES]);
  		return $ca->render(template => 'warning', status => 500); 
	}
	&add_wam($ca->req->param('user'));
	&write_conf;
   	push @MESSAGES, app->l('WAM Manager Added Successfully!');
	$ca->stash(messages => [@MESSAGES]);
	$ca->stash(users => [@not_admins]);
	$ca->stash(admins => [keys %ADMINS]);
} => 'admin_form';

post '/del_admin' => sub {
	my $ca = shift;
	my(@not_admins) = grep { !exists($ADMINS{$_}) } keys %AVALU;
	@MESSAGES = ();
	# Check CSRF token
	my $v = $ca->validation;
  	if ($v->csrf_protect->has_error('csrf_token')) {
  		push @MESSAGES, app->l('Bad CSRF token!');
  		$ca->stash(messages => [@MESSAGES]);
  		return $ca->render(template => 'warning', status => 500); 
	}
	push @MESSAGES, app->l('Remove Below Wam Managers:');
	for my $usr (@{$ca->req->every_param('user')}) {
		push @MESSAGES, $usr if ($usr eq &del_wam($usr));
	}
	&write_conf;
  	push @MESSAGES, app->l('Remove Completed!');
	$ca->stash(messages => [@MESSAGES]);
	$ca->stash(users => [@not_admins]);
	$ca->stash(admins => [keys %ADMINS]);
} => 'admin_form';

get '/filesmgr' => sub {
	my $ca = shift;
	if (!$ca->is_admin()) {
		$) = $ca->session->{gid};
		$> = $ca->session->{uid};
	}
	@MESSAGES = ();
	my $folder = $ca->req->param('folder') || '/mnt';
	$folder = &get_dir($folder);
	my @sorted_dir = sort keys %FOLDS;
	my @sorted_file = sort keys %FILES;
	$ca->stash(folder => $folder);
	$ca->stash(free => [&free_space($folder)]);
	$ca->stash(sort_key => 'name');
	$ca->stash(folds => {%FOLDS});
	$ca->stash(files => {%FILES});
	$ca->stash(sorted_folds => [@sorted_dir]);
	$ca->stash(sorted_files => [@sorted_file]);
	$ca->stash(messages => [@MESSAGES]);
	$) = 0;
	$> = 0;
} => 'filesmgr';

post '/filesmgr' => sub {
	my $ca = shift;
	if (!$ca->is_admin()) {
		$) = $ca->session->{gid};
		$> = $ca->session->{uid};
	}
	@MESSAGES = ();
	my $v = $ca->validation;
  	if ($v->csrf_protect->has_error('csrf_token')) {
  		push @MESSAGES, app->l('Bad CSRF token!');
  		$ca->stash(messages => [@MESSAGES]);
  		return $ca->render(template => 'warning', status => 500); 
	}
	my $folder = $ca->req->param('folder');
	my $action = $ca->req->param('action');
	my $sel = join(',', @{$ca->req->every_param('sel')});
	if (defined($action)) {
		$folder = &chg_dir($folder,$ca->req->param('chfolder')) if ($action eq 'chdir');
		$folder = &make_dir($folder,$ca->req->param('newfolder')) if ($action eq 'mkdir');
		&del_dir($folder,$sel) if ($action eq 'delete');
		&ren_dir($ca->req->param('newname'),$sel) if ($action eq 'rename');
		&move_dir($ca->req->param('movefolder'),$folder,$sel) if ($action eq 'move');
		&copy_dir($ca->req->param('copypath'),$folder,$sel) if ($action eq 'copy');
		&chg_perm($ca->req->param('newperm'),$folder,$sel) if ($action eq 'chmod');
		&chg_owner($ca->req->param('newowner'),$folder,$sel) if ($action eq 'chown');
		if ($action eq 'many_download') {
			my $dnfile = &create_zip($>, $folder, $sel);
			$ca->render_file(filepath => $dnfile);
			&clean_zip($dnfile);
		}
	}
	$folder = &get_dir($folder);
	my $sort_key ='';
	my(@sorted_dir,@sorted_file);
	$sort_key=$ca->req->param('sort') if (defined($ca->req->param('sort')));
	if ($sort_key eq '' || $sort_key eq 'name') {
	    @sorted_dir = sort keys %FOLDS;
	    @sorted_file = sort keys %FILES;
	} elsif ( $sort_key eq 'name_rev' ) {
	    @sorted_dir = reverse(sort keys %FOLDS);
	    @sorted_file = reverse(sort keys %FILES);
	} elsif ( $sort_key eq 'time') {
	    @sorted_dir = sort { $FOLDS{$a}->{ftime} <=> $FOLDS{$b}->{ftime} } keys %FOLDS;
	    @sorted_file = sort { $FILES{$a}->{ftime} <=> $FILES{$b}->{ftime} } keys %FILES;
	} elsif ( $sort_key eq 'time_rev' ) {
	    @sorted_dir = reverse(sort { $FOLDS{$a}->{ftime} <=> $FOLDS{$b}->{ftime} } keys %FOLDS);
	    @sorted_file = reverse(sort { $FILES{$a}->{ftime} <=> $FILES{$b}->{ftime} } keys %FILES);
	} elsif ( $sort_key eq 'type' ) {
	    @sorted_dir = sort { $FOLDS{$a}->{type} <=> $FOLDS{$b}->{type} } keys %FOLDS;
	    @sorted_file = sort { $FILES{$a}->{type} <=> $FILES{$b}->{type} } keys %FILES;
	} elsif ( $sort_key eq 'type_rev' ) {
	    @sorted_dir = reverse(sort { $FOLDS{$a}->{type} <=> $FOLDS{$b}->{type} } keys %FOLDS);
	    @sorted_file = reverse(sort { $FILES{$a}->{type} <=> $FILES{$b}->{type} } keys %FILES);
	} elsif ( $sort_key eq 'perm' ) {
	    @sorted_dir = sort { $FOLDS{$a}->{perm} <=> $FOLDS{$b}->{perm} } keys %FOLDS;
	    @sorted_file = sort { $FILES{$a}->{perm} <=> $FILES{$b}->{perm} } keys %FILES;
	} elsif ( $sort_key eq 'perm_rev') {
	    @sorted_dir = reverse(sort { $FOLDS{$a}->{perm} <=> $FOLDS{$b}->{perm} } keys %FOLDS);
	    @sorted_file = reverse(sort { $FILES{$a}->{perm} <=> $FILES{$b}->{perm} } keys %FILES);
	} elsif ( $sort_key eq 'owner' ) {
	    @sorted_dir = sort { $FOLDS{$a}->{owner} <=> $FOLDS{$b}->{owner} } keys %FOLDS;
	    @sorted_file = sort { $FILES{$a}->{owner} <=> $FILES{$b}->{owner} } keys %FILES;
	} elsif ( $sort_key eq 'owner_rev') {
	    @sorted_dir = reverse(sort { $FOLDS{$a}->{owner} <=> $FOLDS{$b}->{owner} } keys %FOLDS);
	    @sorted_file = reverse(sort { $FILES{$a}->{owner} <=> $FILES{$b}->{owner} } keys %FILES);
	} elsif ( $sort_key eq 'gowner' ) {
	    @sorted_dir = sort { $FOLDS{$a}->{group} <=> $FOLDS{$b}->{group} } keys %FOLDS;
	    @sorted_file = sort { $FILES{$a}->{group} <=> $FILES{$b}->{group} } keys %FILES;
	} elsif ( $sort_key eq 'gowner_rev') {
	    @sorted_dir = reverse(sort { $FOLDS{$a}->{group} <=> $FOLDS{$b}->{group} } keys %FOLDS);
	    @sorted_file = reverse(sort { $FILES{$a}->{group} <=> $FILES{$b}->{group} } keys %FILES);
	} elsif ( $sort_key eq 'size' ) {
	    @sorted_dir = sort { $FOLDS{$a}->{size} <=> $FOLDS{$b}->{size} } keys %FOLDS;
	    @sorted_file = sort { $FILES{$a}->{size} <=> $FILES{$b}->{size} } keys %FILES;
	} elsif ( $sort_key eq 'size_rev') {
	    @sorted_dir = reverse(sort { $FOLDS{$a}->{size} <=> $FOLDS{$b}->{size} } keys %FOLDS);
	    @sorted_file = reverse(sort { $FILES{$a}->{size} <=> $FILES{$b}->{size} } keys %FILES);
	}
	$ca->stash(folder => $folder);
	$ca->stash(free => [&free_space($folder)]);
	$ca->stash(sort_key => $sort_key);
	$ca->stash(folds => {%FOLDS});
	$ca->stash(files => {%FILES});
	$ca->stash(sorted_folds => [@sorted_dir]);
	$ca->stash(sorted_files => [@sorted_file]);
	$ca->stash(messages => [@MESSAGES]);
	$) = 0;
	$> = 0;
} => 'filesmgr';

get '/upload' => sub {
	my $ca = shift;
	my $v = $ca->validation;
    @MESSAGES = ();
  	if ($v->csrf_protect->has_error('csrf_token')) {
  		push @MESSAGES, app->l('Bad CSRF token!');
  		$ca->stash(messages => [@MESSAGES]);
  		return $ca->render(template => 'warning', status => 500); 
	}
	my $filemany = $ca->req->param('filemany');
	my $folder =  $ca->req->param('folder');
	$ca->stash(filemany => $filemany);
	$ca->stash(folder => $folder);
} => 'upload';

post '/upload' => sub {
	my $ca = shift;
	my $v = $ca->validation;
    @MESSAGES = ();
  	if ($v->csrf_protect->has_error('csrf_token')) {
  		push @MESSAGES, app->l('Bad CSRF token!');
  		$ca->stash(messages => [@MESSAGES]);
  		return $ca->render(template => 'warning', status => 500); 
	}
	my $folder =  $ca->req->param('folder');
	if ($ca->req->is_limit_exceeded) {
  		push @MESSAGES, app->l('File was too big to upload.');
  		$ca->stash(messages => [@MESSAGES]);
  		return $ca->render(template => 'warning', status => 500);
	} 
	if (!$ca->is_admin()) {
		$) = $ca->session->{gid};
		$> = $ca->session->{uid};
	}
	for my $f (@{ $ca->req->uploads('upload_file') }) {
		my $fn = $f->filename;
		$f = $f->move_to("$folder/$fn") if $fn;
	}
	$) = 0;
	$> = 0;
	$ca->redirect_to('/filesmgr?folder='.$folder);
};

get '/edit_file' => sub {
	my $ca = shift;
	if (!$ca->is_admin()) {
		$) = $ca->session->{gid};
		$> = $ca->session->{uid};
	}
	@MESSAGES = ();
	my $file = $ca->req->param('file');
	if (!open(REAL,"< $file")) {
		push @MESSAGES, app->l('Cannot open file for edit!').$file;
  		$ca->stash(messages => [@MESSAGES]);
  		return $ca->render(template => 'warning', status => 500); 
	}
	my($buf,$context);
	while(read(REAL, $buf, 1024)) {
		$context .= $buf;
	}
	close(REAL);
	$ca->stash(file => $file);
	$ca->stash(context => $context);
	$) = 0;
	$> = 0;
} => 'edit_file';

post '/edit_file' => sub {
	my $ca = shift;
	if (!$ca->is_admin()) {
		$) = $ca->session->{gid};
		$> = $ca->session->{uid};
	}
	my $v = $ca->validation;
    @MESSAGES = ();
  	if ($v->csrf_protect->has_error('csrf_token')) {
  		push @MESSAGES, app->l('Bad CSRF token!');
  		$ca->stash(messages => [@MESSAGES]);
  		return $ca->render(template => 'warning', status => 500); 
	}
	my $file = $ca->req->param('file');
	my $folder = dirname($file);
	my $context = $ca->req->param('context');
	$context =~ s/\r//g;
	my $submit = $ca->req->param('save');
	if (!open(REAL,"> $file")) {
		push @MESSAGES, app->l('Cannot open file for edit!').$file;
  		$ca->stash(messages => [@MESSAGES]);
  		return $ca->render(template => 'warning', status => 500); 
	}
	print REAL $context;
	close REAL;
	if ($submit eq app->l('SAVE')) {
		$ca->redirect_to('/edit_file?file='.$file);
	} else {
		$ca->redirect_to('/filesmgr?folder='.$folder);
	}
};

get '/show_file' => sub {
	my $ca = shift;
	if (!$ca->is_admin()) {
		$) = $ca->session->{gid};
		$> = $ca->session->{uid};
	}
	@MESSAGES = ();
	my $file = $ca->req->param('file');
	my $fsize = stat($file)->size;
	$file =~ /.*\.(.*)$/;
	if (!open(REAL,"< $file")) {
		push @MESSAGES, $file.app->l('Can not read the file!');
	}
	read(REAL, my $bytes, $fsize);
	$ca->render(data => $bytes, format => $1);
	close(REAL);
};

get '/show_pic' => sub {
	my $ca = shift;
	$) = 0;
	$> = 0;
	@MESSAGES = ();
	my $file = $ca->req->param('file');
	my $fsize = stat($file)->size;
	$file =~ /.*\.(.*)$/;
	if (!open(REAL,"<:raw $file")) {
		push @MESSAGES, $file.app->l('Can not read the file!');
	}
	read(REAL, my $bytes, $fsize);
	$ca->render(data => $bytes, format => $1);
	close(REAL);
};

get '/show_scratch' => sub {
	my $ca = shift;
	$) = 0;
	$> = 0;
	@MESSAGES = ();
	my $file = $ca->req->param('file');
  	$ca->stash(file => $file);
	$file =~ /.*\.sb(.?)$/;
  	return $ca->render(template => 'show_scratch2') if ($1 eq '2');
  	return $ca->render(template => 'show_scratch3') if ($1 eq '3');
  	return $ca->render(template => 'show_scratch');
};

get '/sharemgr' => sub {
	my $ca = shift;
	@MESSAGES = ();
	&read_smbconf;
	$ca->stash(messages => [@MESSAGES]);
	$ca->stash(samba => {%SMB});
	$ca->stash(groups => [keys %AVALG]);
	$ca->stash(admins => [keys %ADMINS]);
} => 'sharemgr';

get '/view_share' => sub {
	my $ca = shift;
	my $sec = $ca->req->param('section');
 	@MESSAGES = ();
	my $pairs = $SMB{$sec};
	for my $k (keys %$pairs) {
		push @MESSAGES, $k.' = '.$SMB{$sec}->{$k};
	}
  	$ca->stash(messages => [@MESSAGES]);
  	$ca->render(template => 'notice', status => 200);
};

get '/edit_share' => sub {
	my $ca = shift;
	my $sec = $ca->req->param('section');
	$ca->stash(section => $sec);
	$ca->stash(samba => {%SMB});
	$ca->stash(groups => [keys %AVALG]);
	$ca->stash(admins => [keys %ADMINS]);
} => 'share_form';

post '/add_share' =>sub {
	$) = 0;
	$> = 0;
	my $ca = shift;
	my $v = $ca->validation;
    @MESSAGES = ();
  	if ($v->csrf_protect->has_error('csrf_token')) {
  		push @MESSAGES, app->l('Bad CSRF token!');
  		$ca->stash(messages => [@MESSAGES]);
  		return $ca->render(template => 'warning', status => 500); 
	}
	my $sec = $ca->req->param('section');
	&make_dir('/mnt', $ca->req->param('real_path')) unless (-d '/mnt/'.$ca->req->param('real_path'));
	$SMB{$sec}->{path} = '/mnt/'.$ca->req->param('real_path');
	if (defined($ca->req->param('browse')) && $ca->req->param('browse') eq '1') {
		$SMB{$sec}->{browseable} = 'yes';
	} else {
		$SMB{$sec}->{browseable} = 'no';
	}
	if (defined($ca->req->param('readonly')) && $ca->req->param('readonly') eq '1') {
		$SMB{$sec}->{writeable} = 'no';
		&chg_perm('2755','/mnt',$ca->req->param('real_path'));
	} else {
		$SMB{$sec}->{writeable} = 'yes';
		&chg_perm('2777','/mnt',$ca->req->param('real_path'));
	}
	my $admins = $ca->req->every_param('admin');
	$SMB{$sec}->{'admin users'} = $admins if (ref($admins) eq 'SCALAR');
	$SMB{$sec}->{'admin users'} = join(',', @$admins) if (ref($admins) eq 'ARRAY');
	my $users = $ca->req->every_param('valid');
	$SMB{$sec}->{'valid users'} = $users if (ref($users) eq 'SCALAR');
	$SMB{$sec}->{'valid users'} = join(',', map { '+'.$_ } @$users) if (ref($users) eq 'ARRAY');
	$SMB{$sec}->{'valid users'} = $SMB{$sec}->{'admin users'}.','.$SMB{$sec}->{'valid users'};
	$SMB{$sec}->{'veto files'} = $ca->req->param('veto');
	if (defined($ca->req->param('delete_veto')) && $ca->req->param('delete_veto') eq '1') {
		$SMB{$sec}->{'delete veto files'} = 'yes';
	} else {
		$SMB{$sec}->{'delete_veto_files'} = 'no';
	}
	$SMB{$sec}->{'force create mode'} = $ca->req->param('file_force');
	my $s = '0';
	$s = '1' if (defined($ca->req->param('owner_del')) && $ca->req->param('owner_del') eq '1');
	if (defined($ca->req->param('can_write')) && $ca->req->param('can_write') eq '1') {
		$SMB{$sec}->{'force directory mode'} = $s.'777';
	} else {
		$SMB{$sec}->{'force directory mode'} = $s.'755';
	}
	if (defined($ca->req->param('recycle')) && $ca->req->param('recycle') eq '1') {
		$SMB{$sec}->{'vfs object'} = 'recycle';
		$SMB{$sec}->{'recycle:keeptree'} = 'yes';
		$SMB{$sec}->{'recycle:version'} = 'yes';
		$SMB{$sec}->{'recycle:repository'} = '/mnt/recycle/%u';
	}
	&write_smbconf;
	system('kill -1 $(pidof smbd) && kill -1 $(pidof nmbd)');
  	push @MESSAGES, app->l('Share Folder Configure Completed!');
  	$ca->stash(messages => [@MESSAGES]);
	$ca->stash(samba => {%SMB});
	$ca->stash(groups => [keys %AVALG]);
	$ca->stash(admins => [keys %ADMINS]);
} => 'sharemgr';

post '/del_share' =>sub {
	$) = 0;
	$> = 0;
	my $ca = shift;
	my $v = $ca->validation;
	@MESSAGES = ();
  	if ($v->csrf_protect->has_error('csrf_token')) {
  		push @MESSAGES, app->l('Bad CSRF token!');
  		$ca->stash(messages => [@MESSAGES]);
  		return $ca->render(template => 'warning', status => 500); 
	}
	my $sec = $ca->req->param('section');
	delete $SMB{$sec};
	&write_smbconf;
	system('kill -1 $(pidof smbd) && kill -1 $(pidof nmbd)');
  	push @MESSAGES, app->l('Share Folder Cancled!');
  	$ca->stash(messages => [@MESSAGES]);
	$ca->stash(samba => {%SMB});
	$ca->stash(groups => [keys %AVALG]);
	$ca->stash(admins => [keys %ADMINS]);
} => 'sharemgr';

get '/set_album' => 'set_album';

post '/set_album' => sub {
	my $ca = shift;
	@MESSAGES = ();
	# Check CSRF token
	my $v = $ca->validation;
  	if ($v->csrf_protect->has_error('csrf_token')) {
  		push @MESSAGES, app->l('Bad CSRF token!');
  		$ca->stash(messages => [@MESSAGES]);  		
  		$ca->render(template => 'warning', status => 500); 
	}
	$c->{album_title} = $ca->req->param('title');
	$c->{album_notice} = $ca->req->param('notice');
	$c->{album_showdate} = $ca->req->param('showdate');
	$c->{album_showsize} = $ca->req->param('showsize');
	$c->{album_shownew} = $ca->req->param('shownew');
	$c->{album_bgcolor} = $ca->req->param('bgcolor');
	$c->{album_bgimg} = $ca->req->param('bgimg');
	$c->{album_rowcount} = $ca->req->param('rowcount');
	$c->{album_imgwidth} = $ca->req->param('imgwidth');
	$c->{album_imgheight} = $ca->req->param('imgheight');
	&write_conf;
	push @MESSAGES, app->l('Configuration Saved!');
	$ca->stash(messages => [@MESSAGES]);
} => 'notice';

get '/album' => sub {
	my $ca = shift;
} => 'album';

get '/add_group' => sub {
	my $ca = shift;
	@MESSAGES = ();
	$ca->stash(messages => [@MESSAGES]);
	$ca->stash(groups => [keys %AVALG]);
} => 'add_group';

post '/add_group' => sub {
	$) = 0;
	$> = 0;
	my $ca = shift;
	my $v = $ca->validation;
	@MESSAGES = ();
  	if ($v->csrf_protect->has_error('csrf_token')) {
  		push @MESSAGES, app->l('Bad CSRF token!');
  		$ca->stash(messages => [@MESSAGES]);
  		return $ca->render(template => 'warning', status => 500); 
	}
	my $grp = $ca->req->param('grp');
	&add_grp($grp);
	push @MESSAGES, app->l('New Group Created!') if (exists($GROUPS{$grp}));
	$ca->stash(messages => [@MESSAGES]);
	$ca->stash(groups => [keys %AVALG]);
} => 'add_group';

get '/add_one' => sub {
	my $ca = shift;
	@MESSAGES = ();
	$ca->stash(messages => [@MESSAGES]);
	$ca->stash(groups => [keys %AVALG]);
} => 'add_one';

post '/add_one' => sub {
	$) = 0;
	$> = 0;
	my $ca = shift;
	my $v = $ca->validation;
	@MESSAGES = ();
  	if ($v->csrf_protect->has_error('csrf_token')) {
  		push @MESSAGES, app->l('Bad CSRF token!');
  		$ca->stash(messages => [@MESSAGES]);
  		return $ca->render(template => 'warning', status => 500); 
	}
	my $usr = $ca->req->param('user');
	my $pwd = $ca->req->param('pass');
	my $grp = $ca->req->param('grp');
	my $aa = $ca->req->param('admin');
	&addone($usr,$grp,$pwd);
	&add_wam($usr) if ($aa eq 'ON');
	$ca->stash(messages => [@MESSAGES]);
	$ca->stash(groups => [keys %AVALG]);
} => 'add_one';

get '/delete' => sub {
	my $ca = shift;
	@MESSAGES = ();
	$ca->stash(messages => [@MESSAGES]);
	$ca->stash(users => [keys %AVALU]);
	$ca->stash(groups => [keys %AVALG]);
} => 'delete';

post '/delete' => sub {
	$) = 0;
	$> = 0;
	my $ca = shift;
	my $v = $ca->validation;
	@MESSAGES = ();
  	if ($v->csrf_protect->has_error('csrf_token')) {
  		push @MESSAGES, app->l('Bad CSRF token!');
  		$ca->stash(messages => [@MESSAGES]);
  		return $ca->render(template => 'warning', status => 500); 
	}
	my $usr = $ca->req->param('user');
	my $grp = $ca->req->param('grp');
	my $ww = $ca->req->param('words');
	if ($usr ne '') {
		if ($usr eq '999') {
			for my $u (keys %AVALU) {
				&delone($u);
			}
		} else {
			&delone($usr);
		}
  		$ca->stash(messages => [@MESSAGES]);
  		return $ca->render(template => 'notice');
	}
	if ($grp ne '') {
		$ca->stash(grp => $grp);
		$ca->stash(users => [sort split(/,/, $GROUPS{$grp}->{users})]);
		return $ca->render(template => 'del_members');
	}
	if ($ww ne '') {
		my @users = ();
		for my $u (sort keys %AVALU) {
			next if ($u !~ /$ww/);
			push @users, $u;
		}
		my @groups = ();
		for my $g (sort keys %AVALG) {
			next if ($g !~ /$ww/);
			push @groups, $g;
		}
		$ca->stash(words => $ww);
		$ca->stash(users => [@users]);
		$ca->stash(groups => [@groups]);
		return $ca->render(template => 'del_pattern');
	}
	return $ca->redirect_to('/delete');
};

post '/do_delete' => sub {
	$) = 0;
	$> = 0;
	my $ca = shift;
	my $v = $ca->validation;
	@MESSAGES = ();
  	if ($v->csrf_protect->has_error('csrf_token')) {
  		push @MESSAGES, app->l('Bad CSRF token!');
  		$ca->stash(messages => [@MESSAGES]);
  		return $ca->render(template => 'warning', status => 500); 
	}
	if (defined($ca->req->param('grp'))) {
		my $grp = $ca->req->param('grp');
		if ($grp eq '999') {
			for my $g (keys %AVALG) {
				&del_grp($g);
			}
		} else {
			&del_grp($grp);
		}
	}
	if (defined($ca->req->param('words'))) {
		my $ww = $ca->req->param('words');
		for my $g (sort keys %AVALG) {
			next if ($g !~ /$ww/);
			&del_grp($g);
		}
		push @MESSAGES, app->l('Groups Deleted!');
		for my $u (sort keys %AVALU) {
			next if ($u !~ /$ww/);
			&delone($u);
		}
		push @MESSAGES, app->l('Users Deleted!');
	}
	$ca->stash(messages => [@MESSAGES]);
} => 'notice';

get '/autoadd' => sub {
	my $ca = shift;
	$ca->stash(groups => [keys %AVALG]);
} => 'autoadd';

post '/do_autoadd' => sub {
	$) = 0;
	$> = 0;
	my $ca = shift;
	my $v = $ca->validation;
	@MESSAGES = ();
  	if ($v->csrf_protect->has_error('csrf_token')) {
  		push @MESSAGES, app->l('Bad CSRF token!');
  		$ca->stash(messages => [@MESSAGES]);
  		return $ca->render(template => 'warning', status => 500); 
	}
	my $grp = $ca->req->param('grp');
	my $pre = $ca->req->param('pre');
	my $grade1 = $ca->req->param('grade1');
	my $grade2 = $ca->req->param('grade2');
	my $class1 = $ca->req->param('class1');
	my $class2 = $ca->req->param('class2');
	my $num1 = $ca->req->param('num1');
	my $num2 = $ca->req->param('num2');
	my $addzero = $ca->req->param('addzero');
	&autoadd($grp, $pre, $num1, $num2, $addzero, $grade1, $grade2, $class1, $class2);	
	if ($c->{passwd_form} eq 'random') {
		$ca->stash(show => 'yes');
	} else {
		$ca->stash(show => 'no');
	}
	$ca->stash(messages => [@MESSAGES]);
	$ca->stash(reqn => {%REQN});
} => 'pwd_table';

get '/manuadd' => 'manuadd';

post '/do_manuadd' => sub {
	$) = 0;
	$> = 0;
	my $ca = shift;
	my $v = $ca->validation;
	@MESSAGES = ();
  	if ($v->csrf_protect->has_error('csrf_token')) {
  		push @MESSAGES, app->l('Bad CSRF token!');
  		$ca->stash(messages => [@MESSAGES]);
  		return $ca->render(template => 'warning', status => 500); 
	}
	my $file = $ca->req->upload('upload_file');
	if (!$file) {
  		push @MESSAGES, app->l('Can not read the file!').$file;
	} else {
		$file->move_to('/tmp/account_list.txt');
		open (REQ, '< /tmp/account_list.txt');
		while (my $line = <REQ>) {
			my($uname, $gname, $pwd) = split(/ /, $line);
			$pwd =~ s/[\n|\r]//g;
			&addone($uname, $gname, $pwd) if ($uname && $gname && $pwd);
		}
		close(REQ);
	}
	$ca->stash(messages => [@MESSAGES]);
} => 'notice';

get '/resetpw' => sub {
	my $ca = shift;
	@MESSAGES = ();
	$ca->stash(messages => [@MESSAGES]);
	$ca->stash(users => [keys %AVALU]);
	$ca->stash(groups => [keys %AVALG]);
} => 'resetpw';

post '/resetpw' => sub {
	$) = 0;
	$> = 0;
	my $ca = shift;
	my $v = $ca->validation;
	@MESSAGES = ();
  	if ($v->csrf_protect->has_error('csrf_token')) {
  		push @MESSAGES, app->l('Bad CSRF token!');
  		$ca->stash(messages => [@MESSAGES]);
  		return $ca->render(template => 'warning', status => 500); 
	}
	my $usr = $ca->req->param('user');
	my $grp = $ca->req->param('grp');
	my $ww = $ca->req->param('words');
	my $pf = $ca->req->param('passwd_form');
	if (defined($ca->req->param('usr'))) {
		&reset_pw($usr,'','',$pf);
  		push @MESSAGES, app->l('Password Reset Completed!');
		if ($pf eq 'random') {
			$ca->stash(reqn => {%REQN});
  			$ca->stash(messages => [@MESSAGES]);
	  		return $ca->render(template => 'pwd_table');
		} else {
  			$ca->stash(messages => [@MESSAGES]);
	  		return $ca->render(template => 'notice');
		}
	}
	if (defined($ca->req->param('grp'))) {
		$ca->stash(pf => $pf);
		$ca->stash(grp => $grp);
		$ca->stash(users => [sort split(/,/, $GROUPS{$grp}->{users})]);
		return $ca->render(template => 'reset_members');
	}
	if (defined($ca->req->param('words'))) {
		my @users = ();
		for my $u (sort keys %AVALU) {
			next if ($u !~ /$ww/);
			push @users, $u;
		}
		$ca->stash(pf => $pf);
		$ca->stash(words => $ww);
		$ca->stash(users => [@users]);
		return $ca->render(template => 'reset_pattern');
	}
#	return $ca->redirect_to('/resetpw');
};

post '/do_resetpw' => sub {
	$) = 0;
	$> = 0;
	my $ca = shift;
	my $v = $ca->validation;
	@MESSAGES = ();
  	if ($v->csrf_protect->has_error('csrf_token')) {
  		push @MESSAGES, app->l('Bad CSRF token!');
  		$ca->stash(messages => [@MESSAGES]);
  		return $ca->render(template => 'warning', status => 500); 
	}
	my $pf = $ca->req->param('passwd_form');
	if (defined($ca->req->param('grp'))) {
		my $grp = $ca->req->param('grp');
		&reset_pw('',$grp,'',$pf);
	}
	if (defined($ca->req->param('words'))) {
		my $ww = $ca->req->param('words');
		&reset_pw('','',$ww,$pf);
	}
	push @MESSAGES, app->l('Password Reset Completed!');
	if ($pf eq 'random') {
		$ca->stash(reqn => {%REQN});
		$ca->stash(messages => [@MESSAGES]);
  		return $ca->render(template => 'pwd_table');
	} else {
		$ca->stash(messages => [@MESSAGES]);
  		return $ca->render(template => 'notice');
	}
};

get '/chgpw' => 'chgpw';

post '/chgpw' => sub {
	my $ca = shift;
	my $v = $ca->validation;
	@MESSAGES = ();
  	if ($v->csrf_protect->has_error('csrf_token')) {
  		push @MESSAGES, app->l('Bad CSRF token!');
  		$ca->stash(messages => [@MESSAGES]);
  		return $ca->render(template => 'warning', status => 500); 
	}
	my $usr = $ca->session->{user};
	my $pwd = $ca->req->param('pwd');
	&chgpw($usr, $pwd);
	push @MESSAGES, app->l('Password changed successfully.');
	$ca->stash(messages => [@MESSAGES]);
} => 'notice';

get '/state' => sub {
	my $ca = shift;
	%REQN = ();
	if ($ca->is_admin()) {
		for my $u (keys %AVALU) {
			$REQN{$u} = &account_flag($u);
		}
	} else {
		$REQN{$ca->session->{user}} = &account_flag($ca->session->{user});
	}
	$ca->stash(reqn => {%REQN});
} => 'state_table';

app->secrets(['WAM is meaning Web-base Account Management']);
app->sessions->default_expiration(3600);
#app->sessions->secure('true');
app->static->paths(['/web/static']);
app->start;

__DATA__

@@ warning.html.ep
% title l('WARNING');
% layout 'default';
<center><table><tr><td><ul>
<% for my $msg (@$messages) { %>
<li><%= $msg %>
<% } %>
</ul></td></tr></table></center>

@@ notice.html.ep
% title l('NOTICE');
% layout 'default';
<center><table><tr><td><ul>
<% for my $msg (@$messages) { %>
<li><%= $msg %>
<% } %>
</ul></td></tr></table></center>

@@ frames.html.ep
<head><meta http-equiv=Content-Type content="<%=l('text/html; charset=utf-8')%>">
<META HTTP-EQUIV=Pargma CONTENT=no-cache>
<title>WAM</title>
<script type="text/javascript">
if (window.top.location != window.location) {
  window.top.location = window.location;
}
</script>
</head>
<FRAMESET COLS="130,*"  framespacing=0 frameborder=0>
<FRAME SRC=/left NAME=wam_left marginwidth=0 marginheight=0 noresize>
<FRAME SRC=/right NAME=wam_main>
</FRAMESET>

@@ left.html.ep
<head><meta http-equiv=Content-Type content="<%=l('text/html; charset=utf-8')%>">
<base target=wam_main>
%= stylesheet '/left.css'
</head><body>
<table class="menu">
<tr><td class="title nav">WAM</td></tr>
% if (is_admin) {
<tr><td class="item"><a href="/help/help_root.htm"><%=l('Admin User Manual')%></a></td></tr>
<tr><td class="cap"><%=l('System Management')%></td></tr>
<tr><td class="item"><a href="/config"><%=l('Config Your System')%></a></td></tr>
<tr><td class="item"><a href="/setadmin"><%=l('Setup WAM Manager')%></a></td></tr>
<tr><td class="item"><a href="/filesmgr"><%=l('File Manager')%></a></td></tr>
<tr><td class="item"><a href="/sharemgr"><%=l('Share Folders')%></a></td></tr>
<tr><td class="item"><a href="/set_album"><%=l('Configure Album')%></a></td></tr>
<tr><td class="item"><a href="/album"><%=l('Album')%></a></td></tr>
<tr><td class="cap"><%=l('Account Management')%></td></tr>
<tr><td class="item"><a href="/add_group"><%=l('Add Group')%></a></td></tr>
<tr><td class="item"><a href="/add_one"><%=l('Creat an Account')%></a></td></tr>
<tr><td class="item"><a href="/delete"><%=l('Delete User or Group')%></a></td></tr>
<tr><td class="item"><a href="/autoadd"><%=l('Auto Create User Account')%></a></td></tr>
<tr><td class="item"><a href="/manuadd"><%=l('Creat User Account from File')%></a></td></tr>
<tr><td class="item"><a href="/resetpw"><%=l('Reset Password')%></a></td></tr>
<tr><td class="item"><a href="/chgpw"><%=l('Change My Password')%></a></td></tr>
<tr><td class="item"><a href="/state"><%=l('Account Flags')%></a></td></tr>
<tr><td class="cap"><%=l('Log Out')%></td></tr>
<tr><td class="nav"><a href="/relogon" target="_top"><%=l('Log Out')%></a></td></tr>
% } else {
<tr><td class="item"><a href="/help/help_user.htm"><%=l('User Manual')%></a></td></tr>
<tr><td class="item"><a href="/filesmgr"><%=l('File Manager')%></a></td></tr>
<tr><td class="item"><a href="/chgpw"><%=l('Change My Password')%></a></td></tr>
<tr><td class="item"><a href="/state"><%=l('Account Flags')%></a></td></tr>
<tr><td class="cap"><%=l('Log Out')%></td></tr>
<tr><td class="nav"><a href="/relogon" target="_top"><%=l('Log Out')%></a></td></tr>
% }
</table></body></html>

@@ right.html.ep
% title l('Login WAM');
% layout 'default';
<center><a href="javascript:onclick=alert('<%=l('Please type your Account & Password below first!!')%>')"><img src=/img/wam.gif></a>

@@ logon_form.html.ep
% title l('Login WAM');
% layout 'default';
<center><a href="javascript:onclick=alert('<%=l('Please type your Account & Password below first!!')%>')"><img src=/img/wam.gif></a>
%= form_for logon => (method => 'POST') => begin
%= csrf_field
<table>
<tr><th align=left><%= label_for user => l('Account') %>：<td>
%= text_field 'user', maxlength => 20, size => 20
<td align=right><%= label_for password => l('Password') %>：<td>
%= password_field 'password', size => 20
<td colspan=2 align=center>
%= submit_button l('Login WAM')
</table>
% end
</center>

@@ config_form.html.ep
% title l('Config Your System');
% layout 'default';
<center>
%= form_for do_config => (method => 'POST') => begin
%= csrf_field
<table width=80%>
<tr class="cell"><th align=right>
%= label_for language => l('Choose Language')
</th><td>
%= t 'select', (name => 'language') => begin
% for my $lang ($langs) {
%= t 'option', value => $lang, selected => (config('language') eq $lang) ? 'selected' : undef, $lang
% }
% end
</td></tr>
<tr class="nav"><th align=right>
%= label_for acltype => l('ACL Control')
</th><td>
% if (config('acltype') eq 1) {
<%= radio_button acltype => 1, checked => 'checked' %><%=l('Allow IP')%>
<%= radio_button acltype => 0, checked => undef %><%=l('Deny IP')%>
% } else {
<%= radio_button acltype => 1, checked => undef %><%=l('Allow IP')%>
<%= radio_button acltype => 0, checked => 'checked' %><%=l('Deny IP')%>
% }
<br>
%= text_area acls => config('acls'), rows => 3, cols => 50
</td></tr>
<tr class="cell"><th align=right>
%= label_for nest => l('Account Hierarchy')
</th><td>
%= t 'select', (name => 'nest') => begin
% for my $i (1..3) {
% if ((config('nest') == $i)) {
%= t 'option', value => $i, selected => undef, $i
% } else {
%= t 'option', value => $i, $i
% }
% }
% end
</td></tr>
<tr class="cell"><th align=right>
%= label_for passwd_form => l('Password Specified As')
</th><td>
%= t 'select', (name => 'passwd_form') => begin
% if (config('passwd_form') eq "username") {
%= t 'option', value => 'username', selected => undef, l('Same as Account')
% } else {
%= t 'option', value => 'username', l('Same as Account')
% }
% if (config('passwd_form') eq "random") {
%= t 'option', value => 'random', selected => undef, l('Random')
% } else {
%= t 'option', value => 'random', l('Random')
% }
% if (config('passwd_form') eq "single") {
%= t 'option', value => 'single', selected => undef, l("All set to 'passwd'")
% } else {
%= t 'option', value => 'single', l("All set to 'passwd'")
% }
% end
</td></tr>
<tr class="cell"><th align=right>
%= label_for passwd_range => l('Set Random Range')
</th><td>
%= t 'select', (name => 'passwd_range') => begin
% if (config('passwd_range') eq "num") {
%= t 'option', value => 'num', selected => undef, l('Number')
% } else {
%= t 'option', value => 'num', l('Number')
% }
% if (config('passwd_range') eq "lcase") {
%= t 'option', value => 'lcase', selected => undef, l('Lower Case')
% } else {
%= t 'option', value => 'lcase', l('Lower Case')
% }
% if (config('passwd_range') eq "ucase") {
%= t 'option', value => 'ucase', selected => undef, l('Upper Case')
% } else {
%= t 'option', value => 'ucase', l('Upper Case')
% }
% if (config('passwd_range') eq "allcase") {
%= t 'option', value => 'allcase', selected => undef, l('Upper & Lower Case')
% } else {
%= t 'option', value => 'allcase', l('Upper & Lower Case')
% }
% if (config('passwd_range') eq "num-lcase") {
%= t 'option', value => 'num-lcase', selected => undef, l('Number & Lower Case')
% } else {
%= t 'option', value => 'num-lcase', l('Number & Lower Case')
% }
% if (config('passwd_range') eq "num-ucase") {
%= t 'option', value => 'num-ucase', selected => undef, l('Number & Upper Case')
% } else {
%= t 'option', value => 'num-ucase', l('Number & Upper Case')
% }
% if (config('passwd_range') eq "all") {
%= t 'option', value => 'all', selected => undef, l('Any Number & Any Case')
% } else {
%= t 'option', value => 'all', l('Any Number & Any Case')
% }
% end
</td></tr>
<tr class="cell"><th align=right>
%= label_for passwd_rule => l('Password Changing Rule')
</th><td>
% if (int(config('passwd_rule')) % 2) {
%= check_box passwd_rule1 => 1, checked => 'checked'
% } else {
%= check_box passwd_rule1 => 1
% }
<%=l('Lenght Limit 4-8')%></td>
<tr class="cell"><th></th><td>
% if (int(config('passwd_rule')) % 4 >= 2) {
%= check_box passwd_rule2 => 1, checked => 'checked'
% } else {
%= check_box passwd_rule2 => 1
% }
<%=l('Only Number & Letter')%></td>
<tr class="cell"><th></th><td>
% if (int(config('passwd_rule')) % 8 >= 4) {
%= check_box passwd_rule3 => 1, checked => 'checked'
% } else {
%= check_box passwd_rule3 => 1
% }
<%=l('Limit Diffrent Letter')%></td>
<tr class="cell"><th></th><td>
% if (int(config('passwd_rule')) >= 8) {
%= check_box passwd_rule4 => 1, checked => 'checked'
% } else {
%= check_box passwd_rule4 => 1
% }
%= l('Not Allow Keyboard Sequence')
</td><tr class="cell"><th align=right>
%= label_for passwd_length => l('Minimum Password Length')
</th><td>
%= text_field passwd_length => config('passwd_length')
</td><tr class="cell"><th align=right>
%= label_for passwd_age => l('Maximum Password Age(seconds,unlimited by -1)')
</th><td>
%= text_field passwd_age => config('passwd_age')
</td><tr class="cell"><th align=right>
%= label_for passwd_lock => l('Lockout after bad logon attempts')
</th><td>
%= text_field passwd_lock => config('passwd_lock')
</td><tr class="cell"><th align=right>
%= label_for passwd_release => l('Reset lockout count after minutes(default:30)')
</th><td>
%= text_field passwd_release => config('passwd_release')
</td><tr><td colspan=2 align=center><img src=/img/chgpw.gif>
%= submit_button l('Save All Configuration')
</td></tr></table>
% end
</center>

@@ admin_form.html.ep
% title l('Setup WAM Manager');
% layout 'default';
<div align=center>
<table><tr><td><ul>
<% for my $msg (@$messages) { %>
<li><%= $msg %>
<% } %>
</ul></td></tr></table>
%= form_for add_admin => (method => 'POST') => begin
%= csrf_field
<table>
<tr><td class="item"><img src=/img/addone.gif><%=l('Choose New WAM Manager')%></td></tr>
<tr><td class="cell">
%= t 'select', (size => 1, name => 'user') => begin
%= t 'option', value => undef
% for my $user (sort @$users) {
%= t 'option', value => $user, $user
% }
% end
<tr><td align=left><img src=/img/chgpw.gif>
%= submit_button l('Add New WAM Manager')
</table>
% end
<hr>
%= form_for del_admin => (method => 'POST') => begin
%= csrf_field
<table width=65%>
<tr><td colspan=5 class="item"><img src=/img/addgrp.gif><%=l('Wam Manager')%></td></tr><tr>
% my $i=0;
% for my $user (sort @$admins) {
% if (($i % 5) eq 0) {
<tr>
% }
% $i ++;
<td class="cell">
%= check_box user => $user
%= label_for user => $user
% }
<tr><td align=center colspan=5><img src=/img/del.gif>
%= submit_button l('Remove WAM Manager')
</table>
% end
</div></center>

@@ filesmgr.html.ep
% title l('File Manager');
% layout 'default';
%= javascript begin
var rows = <%=int(keys %$folds) + int(keys %$files) %>;
var dirs = <%=keys %$folds%>;
function mysubmit(myaction) { $('#action').val(myaction); $('#filesmgr').submit(); }
function showdesc(memo) {
	$('#description').text(memo);
}
function check() {
	var n = $('#sel:checked').length;
	if (n == 0) { alert('<%=l('Please select one file or Directory!')%>'); }
	return n;
}
function check0() { if (!$('#chfolder').val()) { alert('<%=l('Please input Folder name!')%>'); } else { mysubmit('chdir'); } }
function check1() { if (!$('#newfolder').val()) { alert('<%=l('Please input Folder name!')%>'); } else { mysubmit('mkdir'); } }
function check2() { var flag = check(); if (!$('#newperm').val()) { alert('<%=l('Please assign new privilege!')%>'); } else { if (flag) { mysubmit('chmod'); } } }
function check3() { var flag = check(); if (!$('#newowner').val()) { alert('<%=l('Please assign new owner!')%>'); } else { if (flag) { mysubmit('chown'); } } }
function check4() { var flag = check(); if (!$('#newname').val()) { alert('<%=l('Please inpug new name!')%>'); } else { if (flag) { mysubmit('rename'); } } }
function check5() { var flag = check(); if (!$('#movefolder').val()) { alert('<%=l('Where to move?')%>'); } else { if (flag) { mysubmit('move'); } } }
function check6() { var flag = check(); if (!$('#copypath').val()) { alert('<%=l('Where to copy to?')%>'); } else { if (flag) { mysubmit('copy'); } } }
function check7() { if (check()) { mysubmit('delete'); } }
function check8() { if (check()) { mysubmit('many_download'); } }
function check9() { if (check()) { mysubmit('share'); } }
function sall() {
	if (!$('#sel')) return;
	$('#sel').each(function () {
		$(this).prop('checked', true);
	});
}
function sfile(){
	if (!$('#sel')) return;
	$('#sel').each(function (index) {
		if (index < dirs) {
			$(this).prop('checked', false);
		} else {
			$(this).prop('checked', true);
		}
	});
}	
function snone() {
	if (!$('#sel')) return;
	$('#sel').each(function () {
		$(this).prop('checked', false);
	});
}
% end
<div align=center>
<table><tr><td><ul>
<% for my $msg (@$messages) { %>
<li><%= $msg %>
<% } %>
</ul></td></tr></table>
<table width=95%>
% my $used = $$free[3]*0.6;
<tr><td colspan=9 align=center><span class="green"><%=l('Total Spaces:')%><%=$$free[0]%>M</span> <span class="darkred"><%=l('Used:')%><%=$$free[1]%>M</span> <span class="blue"><%=l('Free:')%><%=$$free[2]%>M</span> <span class="red"><%=l('Usage:')%><img src=/img/used.jpg width=<%=$used%> height=10><img src=/img/unused.jpg width=<%=int(60-$used)%> height=10><%=$$free[3]%>%<span></td></tr>
<tr><td align=center class="item" width="25px"><%=l('Select')%></td>
<td align=center class="item">
% if ($sort_key eq 'name' || $sort_key eq '') {
%= link_to l('Name') => url_with->query([folder => $folder, sort => "name_rev"])
% } else {
%= link_to l('Name') => url_with->query([folder => $folder, sort => "name"])
% }
</td><td align=center class="item">
% if ($sort_key eq 'type') {
%= link_to l('Type') => url_with->query([folder => $folder, sort => "type_rev"])
% } else {
%= link_to l('Type') => url_with->query([folder => $folder, sort => "type"])
% }
</td><td align=center class="item">
% if ($sort_key eq 'perm') {
%= link_to l('Mode') => url_with->query([folder => $folder, sort => "perm_rev"])
% } else {
%= link_to l('Mode') => url_with->query([folder => $folder, sort => "perm"])
% }
</td><td align=center class="item">
% if ($sort_key eq 'owner') {
%= link_to l('Owner') => url_with->query([folder => $folder, sort => "owner_rev"])
% } else {
%= link_to l('Owner') => url_with->query([folder => $folder, sort => "owner"])
% }
</td><td align=center class="item">
% if ($sort_key eq 'gowner') {
%= link_to l('Group') => url_with->query([folder => $folder, sort => "gowner_rev"])
% } else {
%= link_to l('Group') => url_with->query([folder => $folder, sort => "gowner"])
% }
</td><td align=center class="item">
% if ($sort_key eq 'size') {
%= link_to l('Size') => url_with->query([folder => $folder, sort => "size_rev"])
% } else {
%= link_to l('Size') => url_with->query([folder => $folder, sort => "size"])
% }
</td><td align=center class="item">
% if ($sort_key eq 'time') {
%= link_to l('Update') => url_with->query([folder => $folder, sort => "time_rev"])
% } else {
%= link_to l('Update') => url_with->query([folder => $folder, sort => "time"])
% }
</td><td align=center class="item"><%=l('Pannel')%></td></tr>
<tr><td width="25px"><a href=javascript:sfile()><img src=/img/allfile.gif></a></td>
<td><a href="<%=url_with->query([folder => "/mnt"])%>"><img src=/img/home.gif><%=l('Root')%></a></td>
<td align=center colspan=6>
%= form_for upload => (method => 'GET') => begin
%= csrf_field
%= hidden_field folder => $folder
<img src=/img/upload.gif><%=l('Upload')%><%= text_field filemany => 5, size => 4 %><%=l('Files')%>
%= submit_button l('Select Files')
% end
%= form_for filesmgr => (id => 'filesmgr', method => 'POST') => begin
%= csrf_field
%= hidden_field action => '', id => 'action'
%= hidden_field folder => $folder
<td class="item" rowspan=20><p><%=l('Please read the description first:')%></p>
<div id="description" class="desc"></div>
<p onmouseover="showdesc('<%=l('Please input dir name')%>')"><img src=/img/newfd.gif>
%= text_field chfolder => '', id => 'chfolder', size => 12
%= t 'button', onclick => 'check0()', l('Change Dir')
</p>
<p onmouseover="showdesc('<%=l('Please input new dir name')%>')"><img src=/img/newfd.gif>
%= text_field newfolder => '', id => 'newfolder', size => 12
%= t 'button', onclick => 'check1()', l('Create Dir')
</p>
<p onmouseover="showdesc('<%=l('Please check files then input priv, such as 755.')%>')"><img src=/img/chmod.gif>
%= text_field newperm => '', id => 'newperm', size => 4
%= t 'button', onclick => 'check2()', l('Change Mode')
</p>
<p onmouseover="showdesc('<%=l('Please check files then input owner name.')%>')"><img src=/img/chown.gif>
%= text_field newowner => '', id => 'newowner', size => 10
%= t 'button', onclick => 'check3()', l('Change Owner')
</p>
<p onmouseover="showdesc('<%=l('Please check single file then input new file name.')%>')"><img src=/img/rename.gif>
%= text_field newname => '', id => 'newname', size => 16
%= t 'button', onclick => 'check4()', l('Rename')
</p>
<p onmouseover="showdesc('<%=l('Please check one file then input new filename or folder to move into.')%>')"><img src=/img/mv.gif>
%= text_field movefolder => '', id => 'movefolder', size => 16
%= t 'button', onclick => 'check5()', l('Move')
</p>
<p onmouseover="showdesc('<%=l('Please check one file then input the filename you want to copy to.')%>')"><img src=/img/copy.gif>
%= text_field copypath => '', id => 'copypath', size => 16
%= t 'button', onclick => 'check6()', l('Copy')
</p>
<p onmouseover="showdesc('<%=l('Please check files these you want to delete then click delete.')%>')"><img src=/img/del.gif>
%= t 'button', onclick => 'check7()', l('Delete')
</p>
<p onmouseover="showdesc('<%=l('please check files these you want to download then click download.')%>')"><img src=/img/fd.gif>
%= t 'button', onclick => 'check8()', l('Download')
</p>
<tr class="cell"><td width="25px"><a href=javascript:snone()><img src=/img/allnot.gif></a></td>
<td><img src=/img/fm.gif><span class="red"><%=l('Current Folder:')%></span><span class="blue"><%=$folder%></span></td>
<td align=center><%=$$folds{'.'}->{type}%></td><td align=center class="blue"><%=$$folds{'.'}->{perm}%></td><td align=right><%=$$folds{'.'}->{owner}%></td><td align=right><%=$$folds{'.'}->{group}%></td><td align=right><%=$$folds{'.'}->{size}%></td><td align=right><%=$$folds{'.'}->{modify}%></td></tr>
<tr class="cell"><td width="25px"><a href=javascript:sall()><img src=/img/all.gif></a></td>
<td><a href="<%=url_with->query([folder => "$folder/.."])%>"><img src=/img/upfolder.gif><%=l('Up to Parent')%></a></td>
<td align=center><%=$$folds{'..'}->{type}%></td><td align=center class="blue"><%=$$folds{'.'}->{perm}%></td><td align=right><%=$$folds{'..'}->{owner}%></td><td align=right><%=$$folds{'..'}->{group}%></td><td align=right><%=$$folds{'..'}->{size}%></td><td align=right><%=$$folds{'..'}->{modify}%></td></tr>
% for my $k (@$sorted_folds) {
% next if ($k eq '.' || $k eq '..');
<tr class="folder"><td><input type=checkbox name=sel id=sel value=<%=$k%>></td>
<td><a href="<%=url_with->query([folder => "$folder/$k"])%>"><img src="/img/<%=$$folds{$k}->{image}%>"><%=$k%></a></td>
<td align=center class="darkgreen"><%=$$folds{$k}->{type}%></td><td class="blue"><%=$$folds{$k}->{perm}%></td><td align=right><%=$$folds{$k}->{owner}%></td><td align=right><%=$$folds{$k}->{group}%></td><td align=right><%=$$folds{$k}->{size}%></td><td align=right><%=$$folds{$k}->{modify}%></td></tr>
% }
% for my $k (@$sorted_files) {
<tr class="cell"><td><input type=checkbox name=sel id=sel value=<%=$k%>></td>
% $k =~ /.*\.(.*)$/;
% if (app->types->type($1) =~ /text\/.*/) {
	<td><a href="<%=url_for('/edit_file')->query([file => "$folder/$k"])%>"><img src="/img/<%=$$files{$k}->{image}%>"><%=$k%></a></td>
% } else {
	<td><a target=_blank href="<%=url_for('/show_file')->query([file => "$folder/$k"])%>"><img src="/img/<%=$$files{$k}->{image}%>"><%=$k%></a></td>
%}
<td align=center class="darkgreen"><%=$$files{$k}->{type}%></td><td align=center class="blue"><%=$$files{$k}->{perm}%></td><td align=right><%=$$files{$k}->{owner}%></td><td align=right><%=$$files{$k}->{group}%></td><td align=right><%=$$files{$k}->{size}%></td><td align=right><%=$$files{$k}->{modify}%></td></tr>
% }
% for (1..18 - int(keys %$folds) - int(keys %$files)) {
<tr class="item"><td colspan=8>　</td></tr>
% }
</table>
% end
</div>

@@ upload.html.ep
% title l('Upload Files');
% layout 'default';
<center>
<p class="red"><%=l('Upload files to')%><img src=/img/0folder.gif>
<span class="blue"><%=$folder%></span>
<span class="red"><%=l('Folder')%></span>
%= form_for upload => (method => 'POST', enctype => 'multipart/form-data') => begin
%= csrf_field
%= hidden_field folder => $folder
%= check_box unzip => 1, checked => undef
%= label_for unzip => l('Please unpack Winzip file')
<br>
% if ($filemany) {
%	for my $z (1..$filemany) {
		<img src=/img/upload.gif><%=l('File').$z%>：
		%= file_field 'upload_file'
		<br>
%	}
% } else {
	<img src=/img/upload.gif><%=l('File')%>：
	%= file_field 'upload_file'
	<br>
% }
%= submit_button l('Upload!')
% end
</p></center>

@@ edit_file.html.ep
% title l('Edit File');
% layout 'default';
<center>
%= form_for edit_file => (method => 'POST') => begin
%= csrf_field
%= hidden_field file => $file
%= text_area context => $context, cols => 80, rows => 30, wrap => 'off'
<br>
%= input_tag save => l('SAVE'), type => 'submit'
%= input_tag save => l('Save And Exit'), type => 'submit'
%= input_tag undo => l('UNDO'), type => 'reset'
% end
</center>

@@ sharemgr.html.ep
% title l('Share Folders');
% layout 'default';
<center>
<table><tr><td><ul>
<% for my $msg (@$messages) { %>
<li><%= $msg %>
<% } %>
</ul></td></tr></table>
<table width=60%>
<tr class="item"><td width="50%"><%=l('Share Folders List')%></td><td colspan=3><%=l('Sharing Management')%></td></tr>
% for my $sec (keys %$samba) {
% next if ($sec eq 'global');
<tr><td><%=$sec%></td><td>
%= form_for '/view_share' => begin
%= hidden_field section => $sec
%= submit_button l('View Configuration')
% end
</td><td>
%= form_for '/edit_share' => begin
%= hidden_field section => $sec
%= submit_button l('Configure Sharing')
% end
</td><td>
%= form_for del_share => (method => 'POST') => begin
%= csrf_field
%= hidden_field section => $sec
%= submit_button l('Cancle Sharing')
% end
</td></tr>
% }
</table>
<table width=60%>
<tr class="item"><td colspan=2><%=l('Create a share folder')%></td></tr>
%= form_for add_share => (id => 'sharemgr', method => 'POST') => begin
%= csrf_field
<tr class="cell"><th align=right width="50%"><%= label_for section => l('Share Name') %></th><td>
%= text_field 'section'
</td></tr><tr class="cell"><th align=right><%= label_for real_path => l('Real Path') %></th><td>/mnt/
%= text_field 'real_path'
</td></tr><tr class="cell"><th align=right><%= label_for browse => l('Browserable') %></th><td>
%= check_box 'browse' => 1
</td></tr><tr class="cell"><th align=right><%= label_for readonly => l('Read Only') %></th><td>
%= check_box 'readonly' => 1
</td></tr><tr class="cell"><th align=right><%= label_for users => l('Sharing to which Groups') %></th><td>
% for my $group (sort @$groups) {
<%= check_box valid => $group %><%= label_for valid => $group %>
% }
</td></tr><tr class="cell"><th align=right><%= label_for users => l('Who want to Administration') %></th><td>
% for my $admin (sort @$admins) {
<%= check_box admin => $admin %><%= label_for admin => $admin %>
% }
</td></tr><tr class="cell"><th align=right><%= label_for veto => l('Veto Files') %></th><td>
%= text_area veto => '/*.exe/*.com/*.pif/*.lnk/*.eml/*.bat/*.vbs/*.inf/.DS_Store/_.DS_Store', rows => 3, cols => 30
</td></tr><tr class="cell"><th align=right><%= label_for delete_veto => l('Delete Veto Files') %></th><td>
%= check_box delete_veto => 1
</td></tr><tr class="cell"><th align=right><%= label_for file_force => l('Grant Folder Permission') %></th><td>
%= t 'select', (name => 'file_force') => begin 
%= t 'option', value => '700', l('Only Owner Can Access')
%= t 'option', value => '755', l('Allow Valid Users to Read')
%= t 'option', value => '777', l('Allow Valid Users to Write')
% end
</td></tr><tr class="cell"><th align=right><%= label_for folder_force => l('Grant Folder Permission') %></th><td>
<%= check_box owner_del => 1 %><%= label_for owner_del => l('Only Owner Can Delete') %><br>
<%= check_box can_write => 1 %><%= label_for can_write => l('Allow Valid Users to Create and Delete') %>
</td></tr>
<tr class="cell"><th align=right>
%= label_for recycle => l('Allow Recycle')
</th><td>
%= check_box 'recycle' => 1
</td></tr>
<tr><td colspan=2 align=center>
%= submit_button l('SAVE')
</td></tr>
% end
</table>
</center>

@@ share_form.html.ep
% title l('Configure Sharing');
% layout 'default';
<center>
<table width=60%>
<tr class="item"><td colspan=2><%=l('Create a share folder')%></td></tr>
%= form_for add_share => (id => 'sharemgr', method => 'POST') => begin
%= csrf_field
%= hidden_field section => $section
</td></tr><tr class="cell"><th align=right width="50%"><%= label_for real_path => l('Real Path') %></th><td>/mnt/
%= text_field 'real_path' => %$samba{$section}->{path} =~ m/\/mnt\/(.*)/
</td></tr><tr class="cell"><th align=right><%= label_for browse => l('Browserable') %></th><td>
% if (defined(%$samba{$section}->{browseable}) && %$samba{$section}->{browseable} eq 'yes') {
%= check_box 'browse' => 1, checked => undef
% } else {
%= check_box 'browse' => 1
% }
</td></tr><tr class="cell"><th align=right><%= label_for readonly => l('Read Only') %></th><td>
% if (defined(%$samba{$section}->{writeable}) && %$samba{$section}->{writeable} eq 'yes') {
%= check_box 'readonly' => 1
% } else {
%= check_box 'readonly' => 1, checked => undef
% }
</td></tr><tr class="cell"><th align=right><%= label_for users => l('Sharing to which Groups') %></th><td>
% my @users = grep { $_ =~ m/\+(.*)/ } split(',', %$samba{$section}->{'valid users'});
% @users = grep { $_ =~ s/\+// } @users;
% for my $group (sort @$groups) {
% if (grep { $group eq $_ } @users) {
<%= check_box valid => $group, checked => undef %><%= label_for valid => $group %>
% } else {
<%= check_box valid => $group %><%= label_for valid => $group %>
% }
% }
</td></tr><tr class="cell"><th align=right><%= label_for users => l('Who want to Administration') %></th><td>
% @users = split(',', %$samba{$section}->{'admin users'});
% for my $admin (sort @$admins) {
% if (grep { $admin eq $_ } @users) {
<%= check_box admin => $admin, checked => undef %><%= label_for admin => $admin %>
% } else {
<%= check_box admin => $admin %><%= label_for admin => $admin %>
% }
% }
</td></tr><tr class="cell"><th align=right><%= label_for veto => l('Veto Files') %></th><td>
%= text_area veto => defined(%$samba{$section}->{'veto files'}) ? %$samba{$section}->{'veto files'} : '', rows => 3, cols => 30
</td></tr><tr class="cell"><th align=right><%= label_for delete_veto => l('Delete Veto Files') %></th><td>
% if (defined(%$samba{$section}->{'delete veto files'}) && %$samba{$section}->{'delete veto files'} eq 'yes') {
%= check_box delete_veto => 1, checked => undef
% } else {
%= check_box delete_veto => 1
% }
</td></tr><tr class="cell"><th align=right><%= label_for file_force => l('Grant Folder Permission') %></th><td>
%= t 'select', (name => 'file_force') => begin 
%= t 'option', value => '700', selected => (defined(%$samba{$section}->{'force create mode'}) && %$samba{$section}->{'force create mode'} eq '700') ? 'selected' : undef, l('Only Owner Can Access')
%= t 'option', value => '755', selected => (defined(%$samba{$section}->{'force create mode'}) && %$samba{$section}->{'force create mode'} eq '755') ? 'selected' : undef, l('Allow Valid Users to Read')
%= t 'option', value => '777', selected => (defined(%$samba{$section}->{'force create mode'}) && %$samba{$section}->{'force create mode'} eq '777') ? 'selected' : undef, l('Allow Valid Users to Write')
% end
</td></tr><tr cxlass="cell"><th align=right><%= label_for folder_force => l('Grant Folder Permission') %></th><td>
% if (defined(%$samba{$section}->{'force directory mode'}) && %$samba{$section}->{'force directory mode'} =~ /1[0-9]{3}/) {
<%= check_box owner_del => 1, checked => undef %><%= label_for owner_del => l('Only Owner Can Delete') %><br>
% } else {
<%= check_box owner_del => 1 %><%= label_for owner_del => l('Only Owner Can Delete') %><br>
% }
% if (defined(%$samba{$section}->{'force directory mode'}) && %$samba{$section}->{'force directory mode'} =~ /[0-1]777/) {
<%= check_box can_write => 1, checked => undef %><%= label_for can_write => l('Allow Valid Users to Create and Delete') %>
% } else {
<%= check_box can_write => 1 %><%= label_for can_write => l('Allow Valid Users to Create and Delete') %>
% }
</td></tr><tr class="cell"><th align=right><%= label_for recycle => l('Allow Recycle') %></th><td>
% if (defined(%$samba{$section}->{'vfs object'}) && %$samba{$section}->{'vfs object'} eq 'recycle') {
%= check_box 'recycle' => 1, checked => undef
% } else {
%= check_box 'recycle' => 1
%}
</td></tr><tr><td colspan=2 align=center><%= submit_button l('SAVE') %></td></tr>
% end
</table>
</div>

@@ add_group.html.ep
% title l('Add Group');
% layout 'default';
%= javascript begin
function check() {
	if (!$('#grp').val()) {
		alert('<%=l('Cannot Creat Empty Group')%>');
	} else {
		$('#myform').submit();
	}
}
% end
<center><table><tr><td><ul>
<% for my $msg (@$messages) { %>
<li><%= $msg %>
<% } %>
</ul></td></tr></table>
%= form_for add_group => (id => 'myform', method => 'POST') => begin
%= csrf_field
<table>
<tr><td class="item"><img src=/img/addgrp.gif> <%=l('Group Name')%></td><td class="cell">
%= text_field 'grp' => (id => 'grp')
</td></tr>
<tr><td colspan=2 align=center>
%= input_tag create => l('Creat this group'), type => 'button', onclick => 'check()'
</td></tr></table>
% end
<table width=95%>
<tr class="item"><th colspan=8 align=center><%=l('Created Groups')%></th>
<tr class="cell">
% my $i = 0;
% for my $gname (@$groups) {
% if ($i % 8 == 0) {
</tr><tr class="cell">
% }
% $i ++;
<td><%=$gname%></td>
% }
</table>

@@ add_one.html.ep
% title l('Creat an Account');
% layout 'default';
%= javascript begin
function check() {
	if (!$('#user').val() || !$('#pass').val()) {
		alert('<%=l('Account & Password Cannot blank')%>');
	} else {
		$('#myform').submit();
	}
}
% end
<center><table><tr><td><ul>
<% for my $msg (@$messages) { %>
<li><%= $msg %>
<% } %>
</ul></td></tr></table>
%= form_for add_one => (id => 'myform', method => 'POST') => begin
%= csrf_field
<table>
<tr><td class="item"><img src=/img/addone.gif> <%=l('User Name')%></td><td class="cell">
%= text_field 'user' => (id => 'user')
</td></tr>
<tr><td class="item"><img src=/img/password.gif> <%=l('Password')%><td class="cell">
%= text_field 'pass' => (id => 'pass')
</td></tr>
<tr><td class="item"><img src=/img/addgrp.gif> <%=l('Add This One To Group:')%><td class="cell">
%= select_field 'grp' => $groups 
</td></tr>
<tr><td colspan=2 class="red cell"><img src=/img/chgpw.gif> <%=l('Join WAM Manager Group')%>
%= check_box 'admin' => 'ON'
</td></tr><tr><td colspan=2 align=center>
%= input_tag create => l('Confirm Creat new User'), type => 'button', onclick => 'check()'
</td></tr></table>
% end

@@ delete.html.ep
% title l('Delete User or Group');
% layout 'default';
%= javascript begin
function rest(id) {
	if (id==0) { $('#grp').val(''); $('#words').val(''); }
	if (id==1) { $('#user').val(''); $('#words').val(''); }
	if (id==2) { $('#user').val(''); $('#grp').val(''); }
}
function check() {
	if (!$('#user').val() && !$('#grp').val() && !$('#words').val()) {
		alert('<%=l('You Have Not Select Any Yet!')%>');
		return false;
	} else {
		return true;
	}
}
% end
<center><table><tr><td><ul>
<% for my $msg (@$messages) { %>
<li><%= $msg %>
<% } %>
</ul></td></tr></table>
%= form_for delete => (id => 'myform', onsubmit => 'return check();', method => 'POST') => begin
%= csrf_field
<table>
<tr><td class="item"><%= l('User Name') %></td><td class="cell">
%= t 'select', (id => 'user', size => 1, name => 'user', onchange => 'rest(0)') => begin
%= t 'option', value => undef
%= t 'option', value => '999', l('All Users')
% for my $u (sort @$users) {
%= t 'option', value => $u, $u
% }
% end
</td></tr><tr><td class="item">
%= l('Group Name')
<br>
%= l('(Orgnization Unit)')
</td><td class="cell">
%= t 'select', (id => 'grp', size => 1, name => 'grp', onchange => 'rest(1)') => begin
%= t 'option', value => undef
%= t 'option', value => '999', l('All Groups')
% for my $g (sort @$groups) {
%= t 'option', value => $g, $g
% }
% end
</td></tr><tr><td class="red cell">
%= l('Pattern Match')
</td><td class="cell">
%= text_field 'words' => (id => 'words', onchange => 'rest(2)')
</td></tr><tr><td colspan=2 align=center>
%= submit_button l('Delete these users or groups')
</td></tr></table>
% end
</center>

@@ del_members.html.ep
% title l('Delete User or Group');
% layout 'default';
<center>
%= form_for do_delete => (method => 'POST') => begin
%= csrf_field
%= hidden_field grp => $grp
<table width=95%>
<tr class="item"><td colspan=8 align=center><b><%=l('Group Member')%></td></tr>
<tr class="cell">
% my $i = 0;
% for my $u (sort @$users) {
% 	if ($i % 8 == 0) {
</tr><tr class="cell">
% 	}
% 	$i ++;
<td><%=$u%></td>
% }
</tr><tr><td colspan=8 align=center>
%= submit_button l('Confirm to delete this Group!')
</td></tr></table>
% end
</center>

@@ del_pattern.html.ep
% title l('Delete User or Group');
% layout 'default';
<center>
%= form_for do_delete => (method => 'POST') => begin
%= csrf_field
%= hidden_field words => $words
<table width=95%>
<tr class="item"><td colspan=8 align=center><b><%=l('Group Search Result')%></td></tr>
<tr class="cell">
% my $i = 0;
% for my $g (@$groups) {
% if ($i % 8 == 0) {
</tr><tr class="cell">
% }
% $i ++;
<td><%=$g%></td>
% }
</tr><tr class="item"><td colspan=8 align=center><b><%=l('Will Delete all selected user and group?')%></td></tr>
<tr class="cell">
% $i = 0;
% for my $u (@$users) {
% if ($i % 8 == 0) {
</tr><tr class="cell">
% }
% $i ++;
<td><%=$u%></td>
% }
</tr><tr><td colspan=8 align=center>
%= submit_button l('Confirm delete those user and group!')
</td></tr></table>
% end
</center>

@@ autoadd.html.ep
% title l('Auto Create User Account');
% layout 'default';
<center>
%= javascript begin
function chggrp() {
	var $grp = $('#grps').val();
	$('#grp').val($grp);
}
% if (config('nest') == 1) {
function check() { 
	if ($('#grp').val() == '' || $('#pre').val() == '' || $('#num1').val() == '' || $('#num2').val() == '') {
		alert('<%=l("Group and Serial number cann't be blank!")%>');
		return false;
	} else {
		return true;
	}
}
% } elsif (config('nest') == 2) {
function check() { 
	if ($('#grp').val() == '' || $('#pre').val() == '' || $('#grade1').val() == '' || $('#grade2').val() == '' || $('#num1').val() == '' || $('#num2').val() == '') {
		alert('<%=l("User prefix, Grade number and Serial number cann't be blank!")%>');
		return false;
	} else {
		return true;
	}
}
% } elsif (config('nest') == 3) {
function check() { 
	if ($('#grp').val() == '' || $('#pre').val() == '' || $('#grade1').val() == '' || $('#grade2').val() == '' || $('#class1').val() == '' || $('#class2').val() == '' || $('#num1').val() == '' || $('#num2').val() == '') {
		alert('<%=l("User prefix, Grade number, Class number and Serial number cann't be blank!")%>');
		return false;
	} else {
		return true;
	}
}
% }
% end
<center>
%= form_for do_autoadd => (id => 'myForm', method => 'POST', onsubmit => 'return check()') => begin
%= csrf_field
<table>
<tr><td align=center class="item"><%=l('Group Name')%><br><%=l('(Orgnization Unit)')%></td>
<td class="cell">
%= text_field 'grp' => (id => 'grp', size => 12)
%= t 'select' => (id => 'grps', size => 1, name => 'grps', onchange => 'chggrp()') => begin
%= t 'option', value => undef
% for my $g (@$groups) {
%= t 'option', value => $g, $g
% }
% end
</td></tr>
<tr><td align=right class="item"><%=l('Account Prefix(Ex:stu)')%></td>
<td class="cell"><%= text_field 'pre' => (id => 'pre', size => 8)%></td></tr>
% if (config('nest') > 1) {
<tr><td align=right class="item"><%=l('The secend level number.(Grade):')%></td>
<td class="cell"><%=l('From')%><%= text_field 'grade1' => (id => 'grade1', size => 3)%><%=l('To')%><%= text_field 'grade2' => (id => 'grade2', size => 3)%></td></tr>
% }
% if (config('nest') == 3) {
<tr><td align=right class="item"><%=l('The third level number(Class):')%></td>
<td class="cell"><%=l('From')%><%= text_field 'class1' => (id => 'class1', size => 3)%><%=l('To')%><%= text_field 'class2' => (id => 'class2', size => 3)%></td></tr>
% }
<tr><td align=right class="item"><%=l('Seriel numbers(Seat):')%></td>
<td class="cell"><%=l('From')%><%= text_field 'num1' => (id => 'num1', size => 3)%><%=l('To')%><%= text_field 'num2' => (id => 'num2', size => 3)%></td></tr>
<tr><td colspan=2 align=center class="blue cell"><%=l('Add Zero')%>
%= check_box 'addzero' => 'yes', checked => undef
</td></tr>
<tr><td colspan=2><hr size=1 color=6699cc></td>
% if (config('nest') == 1) {
<tr><td colspan=2><%=l('Attention:Creat new Account will be Prefix+Number. Ex:stu23')%></td></tr>
% }
% if (config('nest') == 2) {
<tr><td colspan=2><%=l('Attention:Creat new Account will be Prefix+Second Lever Number+Number. Ex:stu523')%></td></tr>
% }
% if (config('nest') == 3) {
<tr><td colspan=2><%=l('Attention:Creat new Account will be Prefix+Second Lever Number+Third Level Number+Number. Ex:stu50308')%></td></tr>
% }
<tr><td colspan=2 align=center>
%= submit_button l('Create all users')
</td></table>
% end
</center>

@@ pwd_table.html.ep
% title l('Account and Password table:');
% layout 'default';
<center><table><tr><td><ul>
<% for my $msg (@$messages) { %>
<li><%= $msg %>
<% } %>
</ul></td></tr></table>
% if ($show eq 'yes') {
<table width=95%>
<tr>
% my $cols = scalar %$reqn;
% $cols = 5 if ($cols >5);
% for (my $i=0;$i<$cols;$i++) {
<th class="item"><%=l('Account')%></th><th><%=l('Password')%></th>
% }
</tr>
<tr class="cell">
% my $i = 0;
% for my $u (sort keys %$reqn) {
% if ($i % 3 == 0) {
</tr><tr class="cell">
% }
% $i ++;
<td><%= $u %></td><td><%= $reqn->{$u} %></td>
% }
</table>
% }
</center>

@@ manuadd.html.ep
% title l('Creat User Account from File');
% layout 'default';
<center>
%= javascript begin
function check() { 
	if ($('#upload_file').val() == '') {
		alert('<%=l("You have not selected any file yet!")%>');
		return false;
	} else {
		return true;
	}
}
% end
<center>
%= form_for do_manuadd => (id => 'myForm', method => 'POST', enctype => 'multipart/form-data', onsubmit => 'return check()') => begin
%= csrf_field
<table>
<tr><td colspan=2 align=left class="green">
%= l('You MUST upload a UNIX Compatable text file to Create Accounts! Like this:')
<br>
%= l('Username Groupname Password')
<br>
%= l('Ex:I got two diffrent user and group')
<br><span class="red">
shane admin super123<br>ddjohn teacher dd1234
</span><br>
%= l('PS: You have to had space between all Coloum ,each account a line, and the last row MUST be blank!')
<br><hr></td></tr>
<tr><td align=right class="item"><img src=/img/0folder.gif><%=l('Upload your Account text file...')%></td><td class="cell">
%= file_field 'upload_file', id => 'upload_file'
</td></tr><tr><td colspan=2 align=center>
%= submit_button l('Upload and Create Account!')
</td></table>
% end
</center>

@@ resetpw.html.ep
% title l('Reset Password');
% layout 'default';
%= javascript begin
function rest(id) {
	if (id==0) { $('#grp').val(''); $('#words').val(''); }
	if (id==1) { $('#user').val(''); $('#words').val(''); }
	if (id==2) { $('#user').val(''); $('#grp').val(''); }
}
function check() {
	if (!$('#user').val() && !$('#grp').val() && !$('#words').val()) {
		alert('<%=l('You Have Not Select Any Yet!')%>');
		return false;
	} else {
		return true;
	}
}
% end
<center>
%= form_for resetpw => (method => 'POST', onsubmit => 'return check()') => begin
%= csrf_field
<table>
<tr><td class="item" align=right>
%= l('User Name')
</td><td class="cell">
%= t 'select', (id => 'user', size => 1, onchange => 'rest(0)') => begin
%= t 'option', value => undef
% for my $u (sort @$users) {
%= t 'option', value => $u, $u
% }
% end
<tr><td align=right class="item">
%= l('Group Name')
</td><td class="cell">
%= t 'select', (id => 'grp', size => 1, onchange => 'rest(1)') => begin
%= t 'option', value => undef
% for my $g (sort @$groups) {
%= t 'option', value => $g, $g
% }
% end
</td></tr><tr><td align=right class="item">
%= l('Pattern Match')
</td><td class="cell">
%= text_field 'words' => (id => 'words', onchange => 'rest(2)')
</td></tr><tr><td align=right class="item">
%= l('Reset Password to:')
</td><td class="cell">
%= t 'select', (size => 1, id => 'passwd_form') => begin
% if (config('passwd_form') eq "username") {
%= t 'option', value => 'username', selected => undef, l('Same as Account')
% } else {
%= t 'option', value => 'username', l('Same as Account')
% }
% if (config('passwd_form') eq "random") {
%= t 'option', value => 'random', selected => undef, l('Random')
% } else {
%= t 'option', value => 'random', l('Random')
% }
% if (config('passwd_form') eq "single") {
%= t 'option', value => 'single', selected => undef, l("All set to 'passwd'")
% } else {
%= t 'option', value => 'single', l("All set to 'passwd'")
% }
% end
</td></tr><tr><td colspan=2 align=center>
%= submit_button l('Confirm Reset Password!')
</td></tr>
</table>
% end
</center>

@@ reset_members.html.ep
% title l('Reset Password');
% layout 'default';
<center>
%= form_for do_resetpw => (method => 'POST') => begin
%= csrf_field
%= hidden_field grp => $grp
%= hidden_field passwd_form => $pf
<table width=95%>
<tr class="item"><td colspan=8 align=center><b><%=l('Group Member')%></td></tr>
<tr class="cell">
% my $i = 0;
% for my $u (sort @$users) {
% 	if ($i % 8 == 0) {
</tr><tr class="cell">
% 	}
% 	$i ++;
<td><%=$u%></td>
% }
</tr><tr><td colspan=8 align=center>
%= submit_button l('Confirm Reset This group!')
</td></tr></table>
% end
</center>

@@ reset_pattern.html.ep
% title l('Reset Password');
% layout 'default';
<center>
%= form_for do_resetpw => (method => 'POST') => begin
%= csrf_field
%= hidden_field words => $words
%= hidden_field passwd_form => $pf
<table width=95%>
<tr class="item"><td colspan=8 align=center><b><%=l('Will Reset Selected Users:')%></td></tr>
<tr class="cell">
% my $i = 0;
% for my $u (sort @$users) {
% 	if ($i % 8 == 0) {
</tr><tr class="cell">
% 	}
% 	$i ++;
<td><%=$u%></td>
% }
</tr><tr><td colspan=8 align=center>
%= submit_button l('Confirm Reset those selected Account!')
</td></tr></table>
% end
</center>

@@ chgpw.html.ep
% title l('Change My Password');
% layout 'default';
%= javascript begin
function chk_diff(p1,p2) { return !(p1==p2); }
function chk_len(p1) { return !(p1.value.length>=4 && p1.value.length<=8); }
function pattern(p1) {
	var Ap = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
	var ch = 'abcdefghijklmnopqrstuvwxyz';
	var Num = '0123456789';
	var pps = '~`!@#$%^&*()_-=[]{}\|.,/?:;';
	var c1=c2=c3=c4=0;
	for (i=0;i<p1.length;i++) {
		if (Ap.indexOf(p1.substr(i,1))!=-1) c1=1;
		if (ch.indexOf(p1.substr(i,1))!=-1) c2=1;
		if (Num.indexOf(p1.substr(i,1))!=-1) c3=1;
		if (pps.indexOf(p1.substr(i,1))!=-1) c4=1;
	}
	return ((c1+c2+c3+c4) < 2);
}
function sequence(p1) {
	var Ap = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()QWERTYUIOPASDFGHJKLZXCVBNMZYXWVUTSRQPONMLKJIHGFEDCBA0987654321|+_)(*&^%$#@!POIUYTREWQLKJHGFDSAMNBVCXZ';
	var chmode=oldChMode=0, mstr='';
	p1 = p1.toUpperCase();
	for(i=0;i<p1.length;i++) {
		if (p1.length>=i+3) {
			mstr = p1.substr(i,3);
			if (Ap.indexOf(mstr)!=-1) return true;
		}
	} 
}
function Mrepeat(p1) {
	var maxch=ch=0, maxcan=2;
	for (i=0;i<p1.length;i++) {
		ch=1;
		for (j=i+1;j<p1.length;j++) {
			if (p1.substr(i,1)==p1.substr(j,1)) ch++;
		}
		if (maxch<ch) maxch=ch;
	}
	if (p1.length>6) maxcan =3;
	return (maxch > maxcan); 
}
function check() {
	var errors='';
	var pwd1=$('#pwd').val();
	var pwd2=$('#pwd2').val();
	if (chk_empty(pwd1) || chk_empty(pwd2)) errors='<%=l('Password Typemiss!')%>';
	else if (chk_diff(pwd1,pwd2)) errors='<%=l('Password must be the same.')%>';
% if (config('passwd_rule') % 2) {
	else if (chk_len(pwd1)) errors='<%=l('The Length MUST between 4-8 Letters(Numbers)')%>';
% }
% if (config('passwd_rule') % 4 >= 2) {
	else if (pattern(pwd1)) errors='<%=l('Can not set this passowrd !Password Must Contain Lower or Upper Case Letter,Number,or symbol Char.)')%>';
% }
% if (config('passwd_rule') % 8 >= 4) {
	else if (Mrepeat(pwd1)) errors='<%=l('Too many Same letter Are Not allow to set as password!')%>';
% }
% if (config('passwd_rule') >= 8) {
	else if (sequence(pwd1)) errors='<%=l('Please DO NOT use keyboard sequence.')%>';
% }
	if (errors == '') {
		return true;
	} else {
		alert(errors);
		$('#pwd').val('');
		$('#pwd2').val('');
		return false;
	}
}
% end
<center>
<table>
<tr><td colspan=2 class=blue>
%= l('Please set a more complicated:')
<br>
%= l('Please do not use words as a password.')
<br>
% if (config('passwd_rule') % 2) {
%= l('Password Lenght must between 4 ~ 8 char.')
<br>
% }
% if (config('passwd_rule') % 4 >= 2) {
%=l('Passowrd Must include Upper Case and Lower Cast, numbers ,or symbol any two of them.')
<br>
% }
% if (config('passwd_rule') % 8 >= 4) {
%=l('Not allow repeat char.')
<br>
% }
% if (config('passwd_rule') >= 8) {
%=l('Do not use keyboard,or letter,or number sequence.')
<br>
% }
</td></tr>
<tr><td colspan=2><hr size=1 color=6699cc></td></tr>
%= form_for chgpw => (method => 'POST', onsubmit => 'return check()') => begin
<tr><td class="item" align=right><%=l('New Password:')%><img src=/img/chgpw.gif></td>
<td class="cell">
%= password_field 'pwd', id => 'pwd', maxlength => 12, size => 16
</td></tr><tr><td class="item" align=right><%=l('Confirm Password:')%><img src=/img/mdb.gif></td>
<td class="cell">
%= password_field 'pwd2', id => 'pwd2', maxlength => 12, size => 16
</td></tr>
<tr><td colspan=2 align=center>
%= submit_button l('Change My Password!')
</td></tr></table>
% end
</center>

@@ state_table.html.ep
% title l('Account Flags');
% layout 'default';
<center>
<table width=95%>
<tr class="item">
% my $cols = scalar %$reqn;
% $cols = 5 if ($cols >5);
% for (my $i=0;$i<$cols;$i++) {
<td><%=l('Account')%></td><td><%=l('State')%></td>
% }
<tr class="cell">
% my $i = 0;
% for my $u (sort keys %$reqn) {
% if ($i % 3 == 0) {
</tr><tr class="cell">
% }
% $i ++;
<td><%= $u %></td><td><%= $reqn->{$u} %></td>
% }
</table>
</center>

@@ set_album.html.ep
% title l('Configure Album');
% layout 'default';
<center>
%= form_for set_album => (method => 'POST') => begin
%= csrf_field
<table width=80%>
<tr class="cell"><th align=right>
%= label_for title => l('Album Title')
</th><td>
%= text_field title => config('album_title')
</td></tr>
<tr class="cell"><th align=right>
%= label_for notice => l('Notice Messages')
</th><td>
%= text_area notice => config('album_notice'), rows => 3, cols => 50
</td></tr>
<tr class="cell"><th align=right>
%= label_for showdate => l('Show Created Date')
</th><td>
% if (config('album_showdate') == 1) {
%= check_box showdate => 1, checked => 'checked'
% } else {
%= check_box showdate => 1
% }
</td></tr>
<tr class="cell"><th align=right>
%= label_for showsize => l('Show File Size')
</th><td>
% if (config('album_showsize') == 1) {
%= check_box showsize => 1, checked => 'checked'
% } else {
%= check_box showsize => 1
% }
</td></tr>
<tr class="cell"><th align=right>
%= label_for shownew => l('Show New Tip')
</th><td>
% if (config('album_shownew') == 1) {
%= check_box shownew => 1, checked => 'checked'
% } else {
%= check_box shownew => 1
% }
</td></tr>
<tr class="cell"><th align=right>
%= label_for bgcolor => l('Background Color')
</th><td>
%= color_field bgcolor => config('album_bgcolor') ? config('album_bgcolor') : '#000000'
</td></tr>
<tr class="cell"><th align=right>
%= label_for bgimg => l('Background Image')
</th><td>
%= text_field bgimg => config('album_bgimg') ? config('album_bgimg') : '', size => 40
</td></tr>
<tr class="cell"><th align=right>
%= label_for rowcount => l('How Many Thumbnails Per Row')
</th><td>
%= text_field rowcount => config('album_rowcount') ? config('album_rowcount') : 8, size => 5
</td></tr>
<tr class="cell"><th align=right>
%= label_for imgwidth => l('Thumbnails Width: Pixel or Persent')
</th><td>
%= text_field imgwidth => config('album_imgwidth') ? config('album_imgwidth') : 64, size => 5
</td></tr>
<tr class="cell"><th align=right>
%= label_for imgheight => l('Thumbnails Height: Pixel or Persent')
</th><td>
%= text_field imgheight => config('album_imgheight') ? config('album_imgheight') : 'auto', size => 5
</td></tr>
<tr><td colspan=2 align=center>
%= submit_button l('Configure For Me')
</td></table>
% end
</center>

@@ album.html.ep
% title config('album_title');
% layout 'default';
%= javascript begin
var f1 = "img/album/folder1.gif";
var f2 = "img/album/folder2.gif";

$('.folder').on('mouseenter mouseleave', function() {
    if ( $('img', this).attr('src') == f1 ) {
        $('img', this).attr('src', f2);
    } else {
        $('img', this).attr('src', f1);
    }
});
% end
<center>
<table width=90% border=0 align=center>
<tr><td rowspan="<%= config('album_rowcount') %>">
%= config('album_notice')
</td></tr>
<tr><td rowspan="<%= config('album_rowcount') %>">
<p align=center style="font-size: -1; margin-top: 10; margin-bottom: 0">目前所在位置：<%= $nav %></p>
<hr color=#6699cc size=1>
</td></tr><tr>
% my $i=0;
% for my $k (@$sorted_folds) {
% next if ($k eq '.' || $k eq '..');
% $i++;
<td style='font-size:9pt' align=center width=75>
<a class="folder" href="<%= url_with->query([folder => "$folder/$k"]) %>">
<img id="<%= $K %>" src="img/album/folder1.gif"><br><%= $k %>
% if (config('album_showdate')) {
<br><%=$$folds{$k}->{modify}%>
% }
% if (config('album_showsize')) {
<br><%=$$folds{$k}->{size}%>
% }
% my $dt = Mojo::Date->new($$folds{$k}->{modify})->epoch;
% if (config('album_shownew') && $dt > time + 7*24*60*60) {
<br><img src="img/album/new.gif">
% }
</a></td>
% if ($i% config('album_rowcount') eq 0) {
</tr><tr>
% }
% }
% $i=0;
% for my $k (@$sorted_files) {
% next if ($k =~ /^_.*$/);
% $i++;
<tr><td style='font-size:9pt' align=center width=75>
<a href="<%= url_with->query([folder => "$folder/$k"]) %>">
<img id="<%= $K %>" src="img/album/folder1.gif"><br><%= $k %>
% if (config('album_showdate')) {
<br><%=$$folds{$k}->{modify}%>
% }
% if (config('album_showsize')) {
<br><%=$$folds{$k}->{size}%>
% }
% my $dt = Mojo::Date->new($$folds{$k}->{modify})->epoch;
% if (config('album_shownew') && $dt > time + 7*24*60*60) {
<br><img src="img/album/new.gif">
% }
</a></td>
% if ($i% config('album_rowcount') eq 0) {
</tr><tr>
% }
% }
</center>

@@ show_scratch.html.ep
% title 'Scratch 1.4';
% layout 'default';
<center>
<div class="container">
<applet id="ProjectApplet" style="display:block" code="ScratchApplet" codebase="./" archive="ScratchApplet.jar" height="387" width="482">
<param name="project" value="/show_file?file=<%= $file %>">
</applet>
</div>
<!--a href="/show_pic/$file?file=$file"><%= l('Download') %></a-->
</center>

@@ show_scratch2.html.ep
% title 'Scratch 2';
% layout 'default';
%= javascript 'swfobject.js'
%= javascript begin
var flashapp;
function installPlayer(swfName, swfID) {
	var flashvars = {project: '/show_file?file=<%= $file %>'};
	var params = {
				   allowScriptAccess: 'sameDomain',
				   allowFullScreen: true
				 };
	var attributes = {};
	flashapp = document.getElementById(swfID);
	swfobject.embedSWF(swfName, flashapp, 482, 401, '10.0', false, flashvars, params, attributes);
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
% end
<center>
<body onload="installPlayer('scratch.swf', 'PlayerOnly');">
<div id="PlayerOnly"> 
<p>你需要安裝 Flash Player 才能執行程式。</p> 
</div>
<!--a href="/show_pic/$file?file=$file"><%= l('Download') %></a-->
</center>

@@ show_scratch3.html.ep
% title config('album_title');
% layout 'default';
<center>
%=javascript 'lib.min.js'
%=javascript 'player.js'
</center>

@@ layouts/default.html.ep
<html>
<head>
<meta http-equiv="Content-Type" content="<%=l('text/html; charset=Windows-1252')%>">
<META HTTP-EQUIV="Pargma" CONTENT="no-cache">
<title><%=title%></title>
%= stylesheet '/default.css'
%= javascript 'http://ajax.googleapis.com/ajax/libs/jquery/1/jquery.min.js'
<!--[if IE]>  
%= javascript 'http://html5shiv.googlecode.com/svn/trunk/html5.js'  
<![endif]-->
</head>
<body>
<p align=center class="title darkblue"><%= title %></p>
<%= content %>
<hr color=#FF0000><center><font size=3>
【<a href="javascript:history.go(-1)"><img src=/img/upfolder.gif><%=l('Go Back')%></a>  】
</font></center>
</body>
</html>

@@ default.css
body {
	background-color: #FFFFFF;
	font-size: 11pt;
}
a:link { color:#0000cc; text-decoration: none; }
a:visited { color:#551a8b; text-decoration: none; }
a:active { color:#ff0000; text-decoration: none; }
a:hover { color: #E96606; text-decoration: underline; }
ul { list-style-type: none; }
img { vertical-align: middle; }
table {
	border: 6px;
	padding: 1px;
	border-spacing: 1px;
}
.title {
	font-size: 24px;
	padding: 4px;
	font-family: <%=l('Arial')%>;
}
.desc {
    display: block;
    width: 250px;
    word-wrap: break-word;
}
.nav { color: #fff; background-color: #3E7BB9; text-decoration: bold; }
.item { color: #fff; background-color: #69c; }
.item a:link { color: #fff; text-decoration: none; }
.item a:visited { color: #fff; text-decoration: none; }
.item a:active { color: #fc0; text-decoration: none; }
.item a:hover { color: #fc0; text-decoration: none; }
.cell { color: #000; background-color: #e8efff; font-family: <%=l('Arial')%>; }
.folder { color: #000; background-color: #fee; }
.blue { color: blue; }
.green { color: green; }
.red { color: red; }
.darkblue { color: darkblue; }
.darkgreen { color: darkgreen; }
.darkred { color: darkred; }

@@ left.css
body {
	SCROLLBAR-FACE-COLOR: #def;
	SCROLLBAR-HIGHLIGHT-COLOR: #fff;
	SCROLLBAR-SHADOW-COLOR: #ABDBEC;
	SCROLLBAR-3DLIGHT-COLOR: #A4DFEF;
	SCROLLBAR-ARROW-COLOR: steelblue;
	SCROLLBAR-TRACK-COLOR: #DDF0F6;
	SCROLLBAR-DARKSHADOW-COLOR: #9BD6E6;
	font-size: 11pt;
}
a:link { color: #fff; text-decoration: none; }
a:visited { color: #fff; text-decoration: none; }
a:active { color: #fc0; text-decoration: none; }
a:hover { color: #fc0; text-decoration: none; }
table {
	border-collapse: collapse;
	height: 100%;
	width: 100%;
	border: 1px solid #fff;
	padding: 2px;
	border-spacing: 1px;
}
td {
	text-align: center;
	width: 100%;
	height: 40px;
}
.title {
	text-align: center;
	font-weight: bold;
	color: #fff;
	width: 100%;
	height: 40px;
}
.nav { color: #fff; background-color: #3E7BB9; text-decoration: bold; }
.cap { color: #000; background-color: #fc0; text-decoration: bold; }
.item { color: #fff; background-color: #69c; }

@@ swfobject.js
var swfobject=function(){var D="undefined",r="object",T="Shockwave Flash",Z="ShockwaveFlash.ShockwaveFlash",q="application/x-shockwave-flash",S="SWFObjectExprInst",x="onreadystatechange",Q=window,h=document,t=navigator,V=false,X=[],o=[],P=[],K=[],I,p,E,B,L=false,a=false,m,G,j=true,l=false,O=function(){var ad=typeof h.getElementById!=D&&typeof h.getElementsByTagName!=D&&typeof h.createElement!=D,ak=t.userAgent.toLowerCase(),ab=t.platform.toLowerCase(),ah=ab?/win/.test(ab):/win/.test(ak),af=ab?/mac/.test(ab):/mac/.test(ak),ai=/webkit/.test(ak)?parseFloat(ak.replace(/^.*webkit\/(\d+(\.\d+)?).*$/,"$1")):false,aa=t.appName==="Microsoft Internet Explorer",aj=[0,0,0],ae=null;if(typeof t.plugins!=D&&typeof t.plugins[T]==r){ae=t.plugins[T].description;if(ae&&(typeof t.mimeTypes!=D&&t.mimeTypes[q]&&t.mimeTypes[q].enabledPlugin)){V=true;aa=false;ae=ae.replace(/^.*\s+(\S+\s+\S+$)/,"$1");aj[0]=n(ae.replace(/^(.*)\..*$/,"$1"));aj[1]=n(ae.replace(/^.*\.(.*)\s.*$/,"$1"));aj[2]=/[a-zA-Z]/.test(ae)?n(ae.replace(/^.*[a-zA-Z]+(.*)$/,"$1")):0}}else{if(typeof Q.ActiveXObject!=D){try{var ag=new ActiveXObject(Z);if(ag){ae=ag.GetVariable("$version");if(ae){aa=true;ae=ae.split(" ")[1].split(",");aj=[n(ae[0]),n(ae[1]),n(ae[2])]}}}catch(ac){}}}return{w3:ad,pv:aj,wk:ai,ie:aa,win:ah,mac:af}}(),i=function(){if(!O.w3){return}if((typeof h.readyState!=D&&(h.readyState==="complete"||h.readyState==="interactive"))||(typeof h.readyState==D&&(h.getElementsByTagName("body")[0]||h.body))){f()}if(!L){if(typeof h.addEventListener!=D){h.addEventListener("DOMContentLoaded",f,false)}if(O.ie){h.attachEvent(x,function aa(){if(h.readyState=="complete"){h.detachEvent(x,aa);f()}});if(Q==top){(function ac(){if(L){return}try{h.documentElement.doScroll("left")}catch(ad){setTimeout(ac,0);return}f()}())}}if(O.wk){(function ab(){if(L){return}if(!/loaded|complete/.test(h.readyState)){setTimeout(ab,0);return}f()}())}}}();function f(){if(L||!document.getElementsByTagName("body")[0]){return}try{var ac,ad=C("span");ad.style.display="none";ac=h.getElementsByTagName("body")[0].appendChild(ad);ac.parentNode.removeChild(ac);ac=null;ad=null}catch(ae){return}L=true;var aa=X.length;for(var ab=0;ab<aa;ab++){X[ab]()}}function M(aa){if(L){aa()}else{X[X.length]=aa}}function s(ab){if(typeof Q.addEventListener!=D){Q.addEventListener("load",ab,false)}else{if(typeof h.addEventListener!=D){h.addEventListener("load",ab,false)}else{if(typeof Q.attachEvent!=D){g(Q,"onload",ab)}else{if(typeof Q.onload=="function"){var aa=Q.onload;Q.onload=function(){aa();ab()}}else{Q.onload=ab}}}}}function Y(){var aa=h.getElementsByTagName("body")[0];var ae=C(r);ae.setAttribute("style","visibility: hidden;");ae.setAttribute("type",q);var ad=aa.appendChild(ae);if(ad){var ac=0;(function ab(){if(typeof ad.GetVariable!=D){try{var ag=ad.GetVariable("$version");if(ag){ag=ag.split(" ")[1].split(",");O.pv=[n(ag[0]),n(ag[1]),n(ag[2])]}}catch(af){O.pv=[8,0,0]}}else{if(ac<10){ac++;setTimeout(ab,10);return}}aa.removeChild(ae);ad=null;H()}())}else{H()}}function H(){var aj=o.length;if(aj>0){for(var ai=0;ai<aj;ai++){var ab=o[ai].id;var ae=o[ai].callbackFn;var ad={success:false,id:ab};if(O.pv[0]>0){var ah=c(ab);if(ah){if(F(o[ai].swfVersion)&&!(O.wk&&O.wk<312)){w(ab,true);if(ae){ad.success=true;ad.ref=z(ab);ad.id=ab;ae(ad)}}else{if(o[ai].expressInstall&&A()){var al={};al.data=o[ai].expressInstall;al.width=ah.getAttribute("width")||"0";al.height=ah.getAttribute("height")||"0";if(ah.getAttribute("class")){al.styleclass=ah.getAttribute("class")}if(ah.getAttribute("align")){al.align=ah.getAttribute("align")}var ak={};var aa=ah.getElementsByTagName("param");var af=aa.length;for(var ag=0;ag<af;ag++){if(aa[ag].getAttribute("name").toLowerCase()!="movie"){ak[aa[ag].getAttribute("name")]=aa[ag].getAttribute("value")}}R(al,ak,ab,ae)}else{b(ah);if(ae){ae(ad)}}}}}else{w(ab,true);if(ae){var ac=z(ab);if(ac&&typeof ac.SetVariable!=D){ad.success=true;ad.ref=ac;ad.id=ac.id}ae(ad)}}}}}X[0]=function(){if(V){Y()}else{H()}};function z(ac){var aa=null,ab=c(ac);if(ab&&ab.nodeName.toUpperCase()==="OBJECT"){if(typeof ab.SetVariable!==D){aa=ab}else{aa=ab.getElementsByTagName(r)[0]||ab}}return aa}function A(){return !a&&F("6.0.65")&&(O.win||O.mac)&&!(O.wk&&O.wk<312)}function R(ad,ae,aa,ac){var ah=c(aa);aa=W(aa);a=true;E=ac||null;B={success:false,id:aa};if(ah){if(ah.nodeName.toUpperCase()=="OBJECT"){I=J(ah);p=null}else{I=ah;p=aa}ad.id=S;if(typeof ad.width==D||(!/%$/.test(ad.width)&&n(ad.width)<310)){ad.width="310"}if(typeof ad.height==D||(!/%$/.test(ad.height)&&n(ad.height)<137)){ad.height="137"}var ag=O.ie?"ActiveX":"PlugIn",af="MMredirectURL="+encodeURIComponent(Q.location.toString().replace(/&/g,"%26"))+"&MMplayerType="+ag+"&MMdoctitle="+encodeURIComponent(h.title.slice(0,47)+" - Flash Player Installation");if(typeof ae.flashvars!=D){ae.flashvars+="&"+af}else{ae.flashvars=af}if(O.ie&&ah.readyState!=4){var ab=C("div");
aa+="SWFObjectNew";ab.setAttribute("id",aa);ah.parentNode.insertBefore(ab,ah);ah.style.display="none";y(ah)}u(ad,ae,aa)}}function b(ab){if(O.ie&&ab.readyState!=4){ab.style.display="none";var aa=C("div");ab.parentNode.insertBefore(aa,ab);aa.parentNode.replaceChild(J(ab),aa);y(ab)}else{ab.parentNode.replaceChild(J(ab),ab)}}function J(af){var ae=C("div");if(O.win&&O.ie){ae.innerHTML=af.innerHTML}else{var ab=af.getElementsByTagName(r)[0];if(ab){var ag=ab.childNodes;if(ag){var aa=ag.length;for(var ad=0;ad<aa;ad++){if(!(ag[ad].nodeType==1&&ag[ad].nodeName=="PARAM")&&!(ag[ad].nodeType==8)){ae.appendChild(ag[ad].cloneNode(true))}}}}}return ae}function k(aa,ab){var ac=C("div");ac.innerHTML="<object classid='clsid:D27CDB6E-AE6D-11cf-96B8-444553540000'><param name='movie' value='"+aa+"'>"+ab+"</object>";return ac.firstChild}function u(ai,ag,ab){var aa,ad=c(ab);ab=W(ab);if(O.wk&&O.wk<312){return aa}if(ad){var ac=(O.ie)?C("div"):C(r),af,ah,ae;if(typeof ai.id==D){ai.id=ab}for(ae in ag){if(ag.hasOwnProperty(ae)&&ae.toLowerCase()!=="movie"){e(ac,ae,ag[ae])}}if(O.ie){ac=k(ai.data,ac.innerHTML)}for(af in ai){if(ai.hasOwnProperty(af)){ah=af.toLowerCase();if(ah==="styleclass"){ac.setAttribute("class",ai[af])}else{if(ah!=="classid"&&ah!=="data"){ac.setAttribute(af,ai[af])}}}}if(O.ie){P[P.length]=ai.id}else{ac.setAttribute("type",q);ac.setAttribute("data",ai.data)}ad.parentNode.replaceChild(ac,ad);aa=ac}return aa}function e(ac,aa,ab){var ad=C("param");ad.setAttribute("name",aa);ad.setAttribute("value",ab);ac.appendChild(ad)}function y(ac){var ab=c(ac);if(ab&&ab.nodeName.toUpperCase()=="OBJECT"){if(O.ie){ab.style.display="none";(function aa(){if(ab.readyState==4){for(var ad in ab){if(typeof ab[ad]=="function"){ab[ad]=null}}ab.parentNode.removeChild(ab)}else{setTimeout(aa,10)}}())}else{ab.parentNode.removeChild(ab)}}}function U(aa){return(aa&&aa.nodeType&&aa.nodeType===1)}function W(aa){return(U(aa))?aa.id:aa}function c(ac){if(U(ac)){return ac}var aa=null;try{aa=h.getElementById(ac)}catch(ab){}return aa}function C(aa){return h.createElement(aa)}function n(aa){return parseInt(aa,10)}function g(ac,aa,ab){ac.attachEvent(aa,ab);K[K.length]=[ac,aa,ab]}function F(ac){ac+="";var ab=O.pv,aa=ac.split(".");aa[0]=n(aa[0]);aa[1]=n(aa[1])||0;aa[2]=n(aa[2])||0;return(ab[0]>aa[0]||(ab[0]==aa[0]&&ab[1]>aa[1])||(ab[0]==aa[0]&&ab[1]==aa[1]&&ab[2]>=aa[2]))?true:false}function v(af,ab,ag,ae){var ad=h.getElementsByTagName("head")[0];if(!ad){return}var aa=(typeof ag=="string")?ag:"screen";if(ae){m=null;G=null}if(!m||G!=aa){var ac=C("style");ac.setAttribute("type","text/css");ac.setAttribute("media",aa);m=ad.appendChild(ac);if(O.ie&&typeof h.styleSheets!=D&&h.styleSheets.length>0){m=h.styleSheets[h.styleSheets.length-1]}G=aa}if(m){if(typeof m.addRule!=D){m.addRule(af,ab)}else{if(typeof h.createTextNode!=D){m.appendChild(h.createTextNode(af+" {"+ab+"}"))}}}}function w(ad,aa){if(!j){return}var ab=aa?"visible":"hidden",ac=c(ad);if(L&&ac){ac.style.visibility=ab}else{if(typeof ad==="string"){v("#"+ad,"visibility:"+ab)}}}function N(ab){var ac=/[\\\"<>\.;]/;var aa=ac.exec(ab)!=null;return aa&&typeof encodeURIComponent!=D?encodeURIComponent(ab):ab}var d=function(){if(O.ie){window.attachEvent("onunload",function(){var af=K.length;for(var ae=0;ae<af;ae++){K[ae][0].detachEvent(K[ae][1],K[ae][2])}var ac=P.length;for(var ad=0;ad<ac;ad++){y(P[ad])}for(var ab in O){O[ab]=null}O=null;for(var aa in swfobject){swfobject[aa]=null}swfobject=null})}}();return{registerObject:function(ae,aa,ad,ac){if(O.w3&&ae&&aa){var ab={};ab.id=ae;ab.swfVersion=aa;ab.expressInstall=ad;ab.callbackFn=ac;o[o.length]=ab;w(ae,false)}else{if(ac){ac({success:false,id:ae})}}},getObjectById:function(aa){if(O.w3){return z(aa)}},embedSWF:function(af,al,ai,ak,ab,ae,ad,ah,aj,ag){var ac=W(al),aa={success:false,id:ac};if(O.w3&&!(O.wk&&O.wk<312)&&af&&al&&ai&&ak&&ab){w(ac,false);M(function(){ai+="";ak+="";var an={};if(aj&&typeof aj===r){for(var aq in aj){an[aq]=aj[aq]}}an.data=af;an.width=ai;an.height=ak;var ar={};if(ah&&typeof ah===r){for(var ao in ah){ar[ao]=ah[ao]}}if(ad&&typeof ad===r){for(var am in ad){if(ad.hasOwnProperty(am)){var ap=(l)?encodeURIComponent(am):am,at=(l)?encodeURIComponent(ad[am]):ad[am];if(typeof ar.flashvars!=D){ar.flashvars+="&"+ap+"="+at}else{ar.flashvars=ap+"="+at}}}}if(F(ab)){var au=u(an,ar,al);if(an.id==ac){w(ac,true)}aa.success=true;aa.ref=au;aa.id=au.id}else{if(ae&&A()){an.data=ae;R(an,ar,al,ag);return}else{w(ac,true)}}if(ag){ag(aa)}})}else{if(ag){ag(aa)}}},switchOffAutoHideShow:function(){j=false},enableUriEncoding:function(aa){l=(typeof aa===D)?true:aa},ua:O,getFlashPlayerVersion:function(){return{major:O.pv[0],minor:O.pv[1],release:O.pv[2]}},hasFlashPlayerVersion:F,createSWF:function(ac,ab,aa){if(O.w3){return u(ac,ab,aa)}else{return undefined}},showExpressInstall:function(ac,ad,aa,ab){if(O.w3&&A()){R(ac,ad,aa,ab)}},removeSWF:function(aa){if(O.w3){y(aa)}},createCSS:function(ad,ac,ab,aa){if(O.w3){v(ad,ac,ab,aa)}},addDomLoadEvent:M,addLoadEvent:s,getQueryParamValue:function(ad){var ac=h.location.search||h.location.hash;
if(ac){if(/\?/.test(ac)){ac=ac.split("?")[1]}if(ad==null){return N(ac)}var ab=ac.split("&");for(var aa=0;aa<ab.length;aa++){if(ab[aa].substring(0,ab[aa].indexOf("="))==ad){return N(ab[aa].substring((ab[aa].indexOf("=")+1)))}}}return""},expressInstallCallback:function(){if(a){var aa=c(S);if(aa&&I){aa.parentNode.replaceChild(I,aa);if(p){w(p,true);if(O.ie){I.style.display="block"}}if(E){E(B)}}a=false}},version:"2.3"}}();

@@ img/wam.gif (base64)
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

@@ img/addone.gif (base64)
R0lGODlhIAAgAMIAAP+ZZszM/5mZ/2ZmzO7u7gAAAMjIyAAz/yH5BAEAAAYALAAAAAAgACAAAAPDaFrM1rA9p6pdJJeXuy9DIWzXVXTb6aEDIY6lpWrt6tYvHHNsbWuCoK4004B+QOFQ9js2lUESs+n7RCiyInIFXU63q4BY7J2EqmBPoKxCpztraUX7DrPr2zhxde2r71Z9EH9yGIGCDIR7h4iKJnwMABGSiXBsY2INAJQFmw2YeiZKmpGenQ1QhROknZ6Sm5ScEjsPsoiStESwELK7ubqmu624vybDsMiUxcCmx6rLw5OeyzGn0afU1baRz9mazdm5EdQJADs=

@@ img/addgrp.gif (base64)
R0lGODlhIAAgALMAAAAAAH8AAH94f/8AAAAA/7+4v////wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP///yH5BAEAAA8ALAAAAAAgACAAAAS38MlJq704V8B716AneuA1nlxJoag6sVzxFKkLA/IMuBKcPzvNzZP7YIad34OgMyFxF5rlGYtKVz5dlUILvrKFbm1yxaJkMmKl/D2hReiw3NsmoZfaOl2/u8f3AntmSTOFfxSBGW6GWgEBOQKJRyN+NAOXjgUCjoI9cIw0jgEDopydQIRycywhKWkkPBt+kac2VWiSsSsEBK4PtLovvMMxgb3BqADDvBzMtSWsyNIZBtXW19jZ2tcRADs=

@@ img/upfolder.gif (base64)
R0lGODlhFwAWAKIAAAcHB///B4d/h8e/x////wAAAAAAAAAAACwAAAAAFwAWAAADYki63E6AjEmrtSLevbPk4ORVQFmGwzgBwdAGQKiadH1Ss6u/+xCLGh8vxnv9UkGi71T04ZKtWg/2/ChhzWh1NZy6jjmjVAu0ZqfgpLeZttrebRRIJb/Q6xWPYM/v+/9wgW8JADs=

@@ img/chgpw.gif (base64)
R0lGODlhHgAfALMAAAAAAABgL39/AAAAf3BwcKAAH+QAGwCQLwD/AJCQAM/PAP//AAAA/6SkpP7+/v///yH5BAEAAA8ALAAAAAAeAB8AAAS88MlJq7046817b4D3OaCoNU5amhZBgmTITih4HEA8PzUAHAiczoQiGQyNAECRW3mKgMJxuWA2nJwiyABgNKzDkQPZZTAGPWLD4PB2AWl1g/GChz0+37V27wjgV3p7MiJ/BA0LC395hB4CC3CJiQI7D4+QDQIKVYoCnp+gGZeLVJuSp5KNFI8KAilLCrGyswkKCQmqEpqxPrS3tbe2wLmWs8aMuADJuBmwwLeNMtIbyra2xCyM2JXc3d7f3BEAOw==

@@ img/password.gif (base64)
R0lGODlhIAAgAMQAAAAAAC8wAH94AHBwcJCQAM+QAM/IAP/IAM/4AP/4AM/IL4CAgJCQkJ+YoK+wr7+4v8/IkM/Iz9DQ0N/Y39/g3//4z+Do4P///wAAAAAAAAAAAAAAAAAAAAAAAAAAAP///yH5BAEAAB8ALAAAAAAgACAAAAX/4CeOImCaZKquJLCMC8DO6WK79rcIvEyvr9LCsXt8DAcB6gf7WCymxUPwOSUSPabOSXENXFWX6YBI+mYvC6UrVdpiD0DCMFfSXmv2h3p6xA8ABoJnQB8UE4cmVFcLXwkAZUgEdx8TlpY7H1ebcoEIBgSENZUTEhIvi5yPZQegoqOmp3uaV51Igq4/LxERAx8RqXN0ZZ+hTC+yFot0t62txsdbFMAizHOfoHbReMBUIxW3BgDalA8vExENPOsCggXi5IUPROfpDQ0xexAG7wHQ8kSIfJAQwdSZdvzgvWoSEEyvCAch7Hs3bmEJIg0cSiG0TgHFeAyHvPCzcYUACB9FW71wgA/fh3lDFp5EqXBUSxMWGgLhAYGAAZBVbn5goHOGgHcgX+Bj4IKCUKMFspB4wWBBVQv3FmT8cUIF1ao4n2pRgcMEBQZLLY5dAsACA7BjtQAYkC+uXLUsQgAAOw==

@@ img/del.gif (base64)
R0lGODlhIAAgAOMAAP///8zMzJmZmWZmZt0AAO7u7t3d3aqqqnd3d1VVVURERCIiIgAAAMjIyAAAAMjIyCH5BAEAAA0ALAAAAAAgACAAAATjsLFJq714SsC7/2AIDJNonoBAMlzgvsQrz3SglsBM7HX/3qwcbMcLxHwyYMtFbBqRydWS2SRCf1LhsHp1KbVba/db446zuuoxQOmRu4zCIcGovXuIDAWBxSEZCAcFBQYHBwgJCwt1Xmg+ehV9QVCABggICpmKjI1+fwccBoWHdFGej6AHBgkHCwiLppOfAKqsrrCSUz0Mqautr5w2jqi0vrfBd7u9tsCxujW8xcy4nbLEAKKGiMjDu3yjCeHUwqc9B3oHzmBdPsnsblIC8vP09fb3KwP6+/z9/v/6GEiARDBDgwgAOw==

@@ img/fm.gif (base64)
R0lGODlhDwAQALMAAAcHB4eHB///BwcHhwcH/wf//4eHh8fHx////wAAAAAAAAAAAAAAAAAAAAAAAP///yH5BAEAAA8ALAAAAAAPABAAAARa8D1DqbzYHLGPwZfGjV5lGUiqrmkAoBz1koKLekiBzJ2NoLrCgVd7/YKHAiDQMwKTw8DI54G+AtKDLwZ4HQgEqQ1Lxg4KYCzg0W23H2jCGkSPz+kY9B0v6T4iADs=

@@ img/0folder.gif (base64)
R0lGODlhEAANALMAAAAAAP//AISEhMbGxv///wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP///yH5BAEAAA8ALAAAAAAQAA0AQAQ88ElBqbxYvBG47wIQPtpngsAFrGzLklvXkZWlYXg4jLB8hilYBnfR+GYZUW1ZCYRKx48yZTx5REEmcxUBADs=

@@ img/1folder.gif (base64)
R0lGODlhDwANALMAAAAAAP//AISEhMbGxv///wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP///yH5BAEAAA8ALAAAAAAPAA0AAAQz8D1BqbxYjLCHwJfGjV5lfWAqAB/pbuvXvVz80LM97zV78zkfkGTDjWKmpAnwADifUGgEADs=

@@ img/image.gif (base64)
R0lGODlhEQARALMAAAAAAH8AAAB/AAAAfwB/f39/fwD//7+/v////wAAAAAAAAAAAAAAAAAAAAAAAP///yH5BAEAAA8ALAAAAAARABEAAART8MlJax04ZysHL54VVsUzTudUrMDFTS01rHQB0DFq7LzA550dYQcQAIgXA+FAKAqMBqBpeagWj9FLoXpwGm0XLjfAlQ4C6LTa/JJIAfC4HN6uRwAAOw==

@@ img/html.gif (base64)
R0lGODlhEQARALMAAAAAAH9/AAAAf39/f///AAAA/7+/v////wAAAAAAAAAAAAAAAAAAAAAAAAAAAP///yH5BAEAAA8ALAAAAAARABEAAARV8MlJqx04ZysHN971PSFVFoUErEAloIXwpJLRTkJAwPJk4zraq/f4SYIwFNEYMAw5xVsg8CoYnDGftACoKinG2YMFKNVukoK5Eu5c3/D2mExfQe+PCAA7

@@ img/text.gif (base64)
R0lGODlhEgASALMAAAAAAH9/f/8AAAAA/7+/v////wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP///yH5BAEAAA8ALAAAAAASABIAAARS8MlJqw04aysDf4R3PRlFkOOATkALVJ4aDzT4Up4giOY9ea4HrUbwdT6SIkw4rAlsS4sOimM6H09llaKban9M7CRrXH2+HYJ6zUY/XPB4GWmJAAA7

@@ img/zip.gif (base64)
R0lGODlhEgASALMAAAAAAH9/AH9/f///AL+/v////wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP///yH5BAEAAA8ALAAAAAASABIAAARM8MlJq6Uga3AnIAIoclj2bBtBnkMwrJiwAm6Amt/c7vV7yp6ekJPz8I5EoIR2rBFVRuEuObvdoJdPaAuCVazezk9cAsg05M05TKZEAAA7

@@ img/wave.gif (base64)
R0lGODlhEQATALMAAAAAAH9/AH9/f///AP///wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP///yH5BAEAAA8ALAAAAAARABMAAART8MlJq50A3BsEEBsVDFo4jQJIgBMrjYRGrFJ6wuQzg+4TELpBDLCzjB7CHLH3GgRjHlrKBugkM0VLBiajbaq5IhPTEWRt2kCpN35UPyZKJk6vWyIAOw==

@@ img/video.gif (base64)
R0lGODlhEAAQAIQBAICAgP///wAAAP//n/+fAMDAwP/PAP/PYJ+fYM/PYM+fAFBQUDAwYGBgYJ9gAGCfn2Awn2Bgn8DfwKCgoDAwn6DP8J9gYM/PAM/P/09PT//PMM/v////8M+fYP///////yH+EUNyZWF0ZWQgd2l0aCBHSU1QACH5BAEKAB8ALAAAAAAQABAAAAVS4CeOZGmeKBCsLGAOcNwKJfEwUmAURaC6I0IlAolceLwViYCJRCiMAiAZWFagGA1VGWwQvoZAT1oNfs9UlUmFZPXW4uT0XVKJWaw1cs9D+f8nIQA7

@@ img/doc.gif (base64)
R0lGODlhEAAOALMAAAAAAAD//////wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP///yH5BAEAAA8ALAAAAAAQAA4AAAQ38MlJ6wM4X7wzCGAAXOIXjiYKqqKUku03uqtZrlNqY22+hiKc7wScDX+nym5nWSaVGo9lSn1EAAA7

@@ img/xls.gif (base64)
R0lGODlhEgAPALMAAAAAAAB/f39/fwD//////wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP///yH5BAEAAA8ALAAAAAASAA8AAARH8MlJawUY3wwmICDRScBgDiMZmOJTBoGQeusgDrBsqSwQzxZfDxgU2oiUl1GUueBgS9/sBYPWWh6BdquNejhgXxVZbO7OkggAOw==

@@ img/mdb.gif (base64)
R0lGODlhEQAQALMAAAAAAH9/AH9/f///AP///wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP///yH5BAEAAA8ALAAAAAARABAAAARK8MlJawVAYGApCIMwDAHXfUM2kqYHZsD4WjEXk2M7CfwNsrQfDqeToIaPW/EjHCVzl4A0BXqmLptNwFqkDbidCeZbC7uSXdpGEgEAOw==

@@ img/1file.gif (base64)
R0lGODlhDQAQALMAAAcHB4d/B///B4d/h8e/x////wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP///yH5BAEAAA8ALAAAAAANABAAAARC8D0wK6WSjrd73ZdlbVJpEgBpnmkGXBiqrpLsvm/dngGhky9CQBCg2EpDAPFxDA6LzF0JAI3OaDKCdstFTXBg3CMCADs=

@@ img/all.gif (base64)
R0lGODlhGQANAJEAAAAAAP///wAAAP///yH5BAEAAAMALAAAAAAZAA0AAAI1nI+pCw36hpNtUSjziylyVF3dx5XVdDmnd7DWB6lwG9PZKIOUPN+d3TP0TjohT3U7Bi3MQQEAOw==

@@ img/allfile.gif (base64)
R0lGODlhGQAZAJEAAAAAAP///wAAAP///yH5BAEAAAMALAAAAAAZABkAAAJfnI+pC9g7HjOtUoCzvrrHI1HON0Zd5jxbIoUc6XKudabwaH3quYo1m2PdQpib8FcUXSDMpkyxqyShMZpuQgIutaDuC2UyoZItJRbyg1K91bSOdy4Z46BglreJepx8QwEAOw==

@@ img/allnot.gif (base64)
R0lGODlhGQANAOYAAAAAAP///wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP///yH5BAEAAH8ALAAAAAAZAA0AAAdLgH+Cg4SFhoUAiYqLAH+NjomQj4eTg42XjpmUh4KRkJyehJOKkoiZoZqalZ2sraKMlqOin62rs4aXjKiWm7Wcqa/Atq68krC/yIaBADs=

@@ img/home.gif (base64)
R0lGODlhEwAUALMAAAcHB58HB59nB/8HZ8+XB/+XB//PB4eHh///n8/Pz//3/////wAAAAAAAAAAAP///yH5BAEAAA8ALAAAAAATABQAQASF8Mk5xQwBUIEISEqoIGMCIIb2HCGJCEbhuYpJSZxnosCgSiwRbVj73XKpR8B3e+Q+ol1SAqiChKMswlRdtUYcQ4pmWyXOZwFBIPigy00nQrU0HjunVD3+BEm7G3hXLX84giJaJXkaB4OJQ2VBWWxsAFqRiTAxli6YNAIybZcqVaWmp6UPEQA7

@@ img/upload.gif (base64)
R0lGODlhHgAaALMAAAAAAH9/f/8AAP//AL+/v////wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP///yH5BAEAAA8ALAAAAAAeABoAAASJ8MlJq72Yhp37DRPneWAljlZ5AWiKsa32xuaq0jfFnm0uwT8aADgBEimCzrDIvAieGdAStss9rybe8mG0JGsPH7dZ+YYehMFWF/S6BmnCmooxn+OlaRtpl2z+gIBcQFgfHQEsayRocI1xahtHh4yPeACIMSCOm3KYmQ+cjYiSh4GmiihDqqurKBEAOw==

@@ img/newfd.gif (base64)
R0lGODlhFwAWAKIAAAcHBzcHn4d/h8e/x////wAAAAAAAAAAACwAAAAAFwAWAAADYEi63E6AjEmrtSLevbPk4ORVQWmW3EgFDRt02toqLxZPLJMTNaXisxKv8hvsaDmU72acLXqD4tEBlT6eROa0lf0Ar8Oltwmuak9opYgZuhTbtjG8K6jb7/g8YM/v+/98CQA7

@@ img/chmod.gif (base64)
R0lGODlhGAAWAKIAAAcHBwcHh4d/h8e/x////wAAAAAAAAAAACwAAAAAGAAWAAADZki63K5AjUmrtSKSy3mWXTh92wCcaKoCozYBQSzPMzuQ76qfLag9DRvOpBAECKeH0EUkxICQXukHjd6YVIYRGVn6gM+Fd1pljF/FY9JxboaB7Sw0vtNJRaIh3qMR+P+AgYJddYUoCQA7

@@ img/chown.gif (base64)
R0lGODlhFwAWAKIAAAcHBwcHh4d/h8e/x////wAAAAAAAAAAACwAAAAAFwAWAAADa0i63E6AjEmrtSLevbPk4ORNQGmeKCBqAxC8cByrw9imeLl+0ePQtoggAOkNi5AdifBqNBdAVs/HiPIIx5IiG7EunwtwsialNrwtLFErWXeVaTGTCIVPzeNgDgcPcWx+HUIChIWGh4d7iigJADs=

@@ img/rename.gif (base64)
R0lGODlhFwAWAKIAAAcHBwcHh4d/h8e/x////wAAAAAAAAAAACwAAAAAFwAWAAADaki63E6AjEmrtSLevbPk4OSBQGkOQSBqG3AB6fpZrmvFwziY5e5XOF0E4qtRYKocK1Ij1nrBJWToJGKkjqGtInwstpRuaWqycrFesGzCbJfVyg/1ARfy7r3rLNRh8fsEAoKDhIWGeIiJJgkAOw==

@@ img/mv.gif (base64)
R0lGODlhFwAWAKIAAAcHB///B4d/h8e/x////wAAAAAAAAAAACwAAAAAFwAWAAADYki63E6AjEmrtSLevbPk4ORVQFmGwzgBwdAGQKiadH1Ss6u/+xCLGh8vxnv9UkGi71T04ZKtWg/2/ChhzWh1NZy6jjmjVAu0ZqfgpLeZttrebRRIJb/Q6xWPYM/v+/9wgW8JADs=

@@ img/copy.gif (base64)
R0lGODlhFwAWAKIAAAcHB2eXZzcHnzcvnzdnn4d/h8e/x////ywAAAAAFwAWAAADc3i63H7gmEmrtSXevbPk4ORRQmmeZjUaghG0RByzbitq9GvIczvYhlVLxyPkgMLaZojEMVEp3e0zDFivV+V00oKetEEnjVE6MCnJFjlgBqcN67Y0TB07zluuF6XChTgrfx1+ghgRBYiJiouMAI6PkJGSjwkAOw==

@@ img/fd.gif (base64)
R0lGODlhFwAWAKIAAAcHB//PB///BzcHnzcvn4d/h8e/x////ywAAAAAFwAWAAADdHi63H7gmEmrtSXevbPkEyBeHmgAFIpOpVmNrEYN9CauRmsMy+DmMp5geKAZjZWWcChw7JLBA3PKfFKUUurUGvssBcdwDejN+kBnLNgQaLvbBsI16nu/41Bv3Q6X52diRyQyP4MfhRgRBYuMjY6PN5GSk5MJADs=

@@ img/used.jpg (base64)
/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAB4DASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDuL3vXOXveiivyvCn22C6HN3vesC4/1lFFfR4bY+twmx//2Q==

@@ img/unused.jpg (base64)
/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wgARCAABAB4DASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAb/xAAUAQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAGgAB//xAAUEAEAAAAAAAAAAAAAAAAAAAAg/9oACAEBAAEFAh//xAAUEQEAAAAAAAAAAAAAAAAAAAAQ/9oACAEDAQE/AT//xAAUEQEAAAAAAAAAAAAAAAAAAAAQ/9oACAECAQE/AT//xAAUEAEAAAAAAAAAAAAAAAAAAAAg/9oACAEBAAY/Ah//xAAUEAEAAAAAAAAAAAAAAAAAAAAg/9oACAEBAAE/IR//2gAMAwEAAgADAAAAEAAP/8QAFBEBAAAAAAAAAAAAAAAAAAAAEP/aAAgBAwEBPxA//8QAFBEBAAAAAAAAAAAAAAAAAAAAEP/aAAgBAgEBPxA//8QAFBABAAAAAAAAAAAAAAAAAAAAIP/aAAgBAQABPxAf/9k=
