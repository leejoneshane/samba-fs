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
use Net::LDAP;

####################### initialzing ###########################################
my $s = Mojolicious::Sessions->new;
$s->default_expiration(3600);
my $c = plugin 'Config';
&init_conf;
my $lh = WAM::I18N->get_handle($c->{language}) || die "What language?";
my $ldap = Net::LDAP->new("127.0.0.1") || die "openLDAP Down?";
my %admins = map { $_ => 1 } split(/,/, $c->{admin});
my $share_conf = "/etc/samba/example.conf";
my $lang_base = "/web";
my $account = "/tmp/account.lst";
my $itoa64 = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
my $today = int(time / 86400);
my (@LANGS,@MESSAGES,@RESERVED,%USERS,%UIDS,%UGID,%GROUPS,%GIDS,%GUSERS);
####################### My Library ############################################
sub init_conf {
	$c->{language} = 'tw' unless defined $c->{language};
	$c->{admin} = 'admin' unless defined $c->{admin};
	$c->{passwd_range} = 'all' unless defined $c->{passwd_range};
	$c->{passwd_form} = 'username' unless defined $c->{passwd_form};
	$c->{nest} = 1 unless defined $c->{nest};
	$c->{acltype} = 0 unless defined $c->{acltype};
	$c->{acls} = '' unless defined $c->{acls};
}

sub flush {
	@RESERVED = ();
	%USERS = {};
	%UIDS = {};
	%UGID = {};
	%GROUPS = {};
	%GIDS = {};
	%GUSERS = {};	
}

sub users {
    my($name,$pw,$uid,$gid,$gcos,$dir,$shell);
	while(($name,$pw,$uid,$gid,$gcos,$dir,$shell) = getpwent()) {
		if ($uid > 1000) {
		    $USERS{$name} ++;
			$UIDS{$name} = $uid;
			$UGID{$name} = $gid;
		} else {
		    push @RESERVED, $name;
		}
	}
	endpwent();
}

sub groups {
	my ($name,$passwd,$gid,$members);
	while(($name,$passwd,$gid,$members) = getgrent()) {
		if ($gid > 1000) {
		    $GROUPS{$name} ++;;
			$GIDS{$name} = $gid;
			$GUSERS{$name} = split(",", $members);
		} else {
		    push @RESERVED, $name;
		}
	}
	endgrent();
}

sub is_reserved {
	my($testname)= @_;
	foreach my $name (@RESERVED) {
		return 1 if ($name eq $testname);
	}
}

sub user_exists {
	return exists($UIDS{$_});
}

sub group_exists {
	return exists($GIDS{$_});
}

sub ldap_ssha {
  my $pw = @_;
  return `slappasswd -s "$pw" -n`;
}

sub rnd64 {
  my $range = @_;
  my $ret = '';
  my $n = 8;
  my $i;
  $range = $c->{'passwd_range'}  unless defined $range;
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
	&head(app->l('title_system_info'));
	print "<center><table border=0 style=font-size:11pt><tr><td><p><font color=blue face=app->l('variable_font') size=5>app->l('err_disk_failue'}</font></p>\n";
	print $msg;
	print '<ul>';
	print "<li>app->l('msg_if_disk_busy')<a href=\"javascript:history.go(-1)\"><img align=absmiddle src=/img/upfolder.gif border=0>  app->l('backto_prev_page'}</a>app->l('msg_try_later')";
	print "<li>app->l('msg_if_config_incorrect')<a href='/config'>app->l('msg_setup_config')</a>";
	print "<li>app->l('msg_check_disk')";
	print '</ul>';
	print '<hr color="#FF0000">';
	print "<center><a href=\"javascript:history.go(-1)\"><img align=absmiddle src=/img/upfolder.gif border=0>  app->l('backto_prev_page')</a></center>";
	print '</table></center></body>';
	print "</html>";
	exit 0;
}

sub err_account {
	&head(app->l('title_system_info'));
	print "<center><table border=0 style=font-size:11pt><tr><td><p><font color=blue face=app->l('variable_font') size=5>app->l('err_check_account')</font></p>\n";
	print "app->l('msg_please_check'}";
	print '<ul>';
	print "<li>app->l('msg_if_misstype')<a href=\"javascript:history.go(-1)\"><img align=absmiddle src=/img/upfolder.gif border=0>  app->l('backto_prev_page')</a>app->l('msg_reinput')";
	print "<li>app->l('msg_just_for_user')";
	print '</ul>';
	print '<hr color="#FF0000">';
	print "<center><a href=\"javascript:history.go(-1)\"><img align=absmiddle src=/img/upfolder.gif border=0>  app->l('backto_prev_page')</a></center>";
	print '</table></center></body>';
	print "</html>";
	exit 0;
}

sub get_lang_list {
	opendir (DIR, "$lang_base") || &err_disk("磁碟錯誤，語言套件目錄無法讀取。disk error! can't open language defined<br>");
	@LANGS=grep { /.*\.po$/ } readdir(DIR);
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

sub addone {
	my($usr,$grp,$pw) = @_;
	if (!user_exists($usr) && !is_reserved($usr) && !is_reserved($grp)) {
	    &add_grp($grp);
		system("adduser -DH -G $grp $usr");
		system("echo -e \"$pw\\n$pw\" | smbpasswd -as $usr");
	}
}

sub read_request {
	open (REQ, "< $account") || &err_disk("$account app->l('err_cannot_open').<br>");
	while (my $line = <REQ>) {
		my($uname, $gname, $pwd) = split(/ /, $line);
		$pwd =~ s/[\n|\r]//g;
		&addone($uname, $gname, $pwd) if ($uname ne '' && $gname ne '' && $pwd ne '');
	}
	close(REQ);
}

sub autoadd {
	my($grp, $pre, $st, $ed, $z, $gst, $ged, $cst, $ced) = @_;
	my($u1, $u2, $u3, $i, $j, $k, $l1, $l2, $l3, $g, $p, $n, $d);
	$l1 = length($ed);
	$l2 = length($ged);
	$l3 = length($ced);
	if ($c->{nest} eq 1) {
		for ($i=int($st); $i<=int($ed); $i++) {
			$u1 = '';
			for (1..$l1-length($i)){$u1 .= '0';}
			$n = $pre.(($z eq 'yes')?$u1:'').$i;
			$p = (($c->{passwd_form} eq 'username')?$n:(($c->{passwd_form} eq 'random')?&rnd64:"passwd"));
			&addone($n, $grp, $p, '');
		}
	} elsif ($c->{nest} eq 2) {
		for ($j=int($gst); $j<=int($ged); $j++) {
			for ($i=int($st); $i<=int($ed); $i++) {
				$u1 = '';
				for (1..$l1-length($i)){$u1 .= '0';}
				$u2 = '';
				for (1..$l2-length($j)){$u2 .= '0';}
				$n = $pre.(($z eq 'yes')?$u2:'').$j.(($z eq 'yes')?$u1:'').$i;
				$p = (($c->{passwd_form} eq 'username')?$n:(($c->{passwd_form} eq 'random')?&rnd64:"passwd"));
				$g = $pre.(($z eq 'yes')?$u2:'').$j;
				&addone($n, $pre, $p, $g);
			}
		}
	} elsif ($c->{nest} eq 3) {
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
					$p = (($c->{passwd_form} eq 'username')?$n:(($c->{passwd_form} eq 'random')?&rnd64:"passwd"));
					$d = $pre.(($z eq 'yes')?$u2:'').$j;
					$g = $pre.(($z eq 'yes')?$u2:'').$j.(($z eq 'yes')?$u3:'').$k;
					&addone($n, $pre, $p, "$d/$g");
				}
			}
		}
	}
}

sub add_wam {
	my $usr = @_;
	return if ($usr eq 'admin');
	$admins{$usr} = 1 unless exists($admins{$usr});
	$c->{admin} => join( ",", keys %admins);
}

sub del_wam {
	my $usr = @_;
	return if ($usr eq 'admin');
	delete $admins{$usr} if exists($admins{$usr});
	$c->{admin} => join( ",", keys %admins);
}

sub add_grp {
	my($grp) = @_;
	system("addgroup $grp") if (!group_exists($grp));
}

sub del_grp {
	my($grp) = @_;
	system("delgroup $grp") if (group_exists($grp));
}

sub delone {
	my($usr) = @_;
	my $uid = $UIDS{$usr};
	print "<center>app->l('del_user_now') $usr ，uid: $uid ....</center><br>";
	system("smbpasswd -x $usr || deluser $usr");
	delete $USERS{$usr};
	delete $UIDS{$usr};
	delete $UGID{$usr};
}

sub reset_pw {
	my($u, $g, $w, $pf) = @_;
	my($usr, @CHGPW, $pw);
	if ($u eq '999') {
		$g = '';
		$w = '';
		foreach $usr (%USERS) { push @CHGPW, $usr; }
	} elsif ($u ne '') {
		$g = '';
		$w = '';
		push (@CHGPW, $u) if (user_exists($u));
	}
	if ($g ne '') {
		$w = '';
		return if (int($GIDS{$g})<1000);
		if (group_exists($g)) {
			foreach $usr (%USERS) { push @CHGPW, $usr if ($UGID{$usr} eq $GIDS{$g}); }
		}
	}
	if ($w ne '') {
		foreach $usr (%USERS) { push @CHGPW, $usr if ($usr =~ /$w/); }
	}
	foreach $usr (@CHGPW) {
		if ($pf eq 'username') {
			exec("echo -e \"$usr\\n$usr\" | smbpasswd -as $usr");
		} elsif ($pf eq 'random') {
			$pw = &rnd64;
			exec("echo -e \"$pw\\n$pw\" | smbpasswd -as $usr");
		} elsif ($pf eq 'single') {
			exec("echo -e \"password\\npassword\" | smbpasswd -as $usr");
		}
	}
}

sub chg_passwd {
	my($p1, $p2) = @_;
	my $usr = getpwuid($s->{uid});
	if ($p1 eq $p2) {
		exec("echo -e \"$p1\\n$p1\" | smbpasswd -as $usr");
	} else {
		&head(app->l('title_chgpw'));
		print "<hr><center><table border=0 style=font-size:11pt><tr><td><p>app->l('err_bad_passwd')</p>\n";
		print "app->l('err_cannot_continue_change_passwd').<br>";
		print '<ul>';
		print "<li>app->l('msg_passwd_must_same')";
		print '</ul>';
		print '<hr color="#FF0000">';
		print "<center><a href=\"javascript:history.go(-1)\"><img align=absmiddle src=/img/upfolder.gif border=0>  app->l('backto_prev_page')</a></center>";
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
	"$perm4$perm3$perm2$perm1";
}

sub err_perm {
	my($msg) = @_;
	&head("app->l('title_system_info')");
	print "<br><center><table border=0 style=font-size:11pt><tr><td><p>app->l('err_perm_set')</p>\n";
	print $msg;
	print '<ul>';
	print "<li>app->l('msg_please_check_perm')";
	print "<li>app->l('msg_contact_administrator')";
	print '</ul>';
	print '<hr color="#FF0000">';
	print "<center><a href=\"javascript:history.go(-1)\"><img align=absmiddle src=/img/upfolder.gif border=0>  app->l('backto_prev_page')</a></center>";
	print '</table></center></body>';
	print "</html>";
	exit 0;
}

sub check_perm {
	my($target,$flag) = @_;
	my $true = 0;
	my($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($target);
	my($perm) = &myoct($mode & 07777);
	if ($s->{uid} eq $uid) {
		$perm = substr($perm,1,1);
	} elsif ($s->{gid} eq $gid) {
		$perm = substr($perm,2,1);
	} else {
		$perm = substr($perm,3,1);
	}
	if ($flag eq 0) {
		if ($s->{uid} eq $uid) {
			$true = 1;
		} else {
			$true = 0;
		}
	} else {
		$true = $perm & $flag;
	}
	$true = 1 if (is_admin());
	$true;
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
	return 0 unless defined($s->{user});
	return exists($admins{$s->{user}});
};

helper basic_auth => sub {
	my $ca = shift;
	my ($usr, $pwd) = @_;
	return $ldap->bind("uid=$usr,ou=People,dc=cc,dc=tp,dc=edu,dc=tw", password => $pwd, version =>3);
};

get '/relogon' => sub {
	$s->{expires} = 1;
} => 'logon_form';

post '/logon' => sub {
  my $ca = shift;
  # Check CSRF token
  my $v = app->validation;
  push @MESSAGES, app->l('Bad CSRF token!');
  $ca->render(template => 'warning', messages=> @MESSAGES, status => 403) if $v->csrf_protect->has_error('csrf_token');

  if (app->basic_auth($ca->req->body_params->param('user'), $ca->req->body_params->param('password'))) {
    $s->{user} = $ca->req->body_params->param('user');
    $s->{uid} = $UIDS{$s->{user}};
    $s->{gid} = $UGID{$s->{user}};
    $s->{passed} = 1;
#    $s->store();
    $ca->redirect_to('/');
  } else {
    push @MESSAGES, app->l('Username or Password Wrong!');
    $ca->render(template => 'warning', messages=> @MESSAGES, status => 403);
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
		foreach $acl (@acls) {
			if ($userip =~ /$acl/) {
				$check_acl = 1 - $c->{acltype};
				last;
			}
		}
	} else {
		$check_acl = $c->{acltype};
	}

	if ($check_acl eq 1) {
		push @MESSAGES, app->l('You can Not use this links!');
  		$ca->stash(messages => @MESSAGES);
  		$ca->render(template => 'warning', status => 403);
	  	return undef;
	} else {
		return 1 if $s->{passed};
	}
  	$ca->redirect_to('/relogon');
};

get '/' => 'frames';
get '/left' => 'left';
get '/right' => 'right';
get '/dies' => sub { die 'Intentional error' };

app->secrets(['WAM is meaning Web-base Account Management']);
app->start;

__DATA__

@@ warning.html.ep
% title l('WARNING');
% layout 'default';
<%= dumper $messages %>

@@ frames.html.ep
<head><meta http-equiv=Content-Type content="<%=l('text/html; charset=Windows-1252')%>">
<META HTTP-EQUIV=Pargma CONTENT=no-cache>
<title>WAM</title></head>
<FRAMESET COLS="130,*"  framespacing=0 border=0 frameborder=0>
<FRAME SRC=/left NAME=wam_left marginwidth=0 marginheight=0 noresize>
<FRAME SRC=/right NAME=wam_main>
</FRAMESET>

@@ left.html.ep
<head><meta http-equiv=Content-Type content="<%=l('text/html; charset=Windows-1252')%>">
<META HTTP-EQUIV=Pargma CONTENT=no-cache>
<title>WAM</title>
<base target=wam_main></head>
<body link=#FFFFFF vlink=#ffffff alink=#FFCC00  style="SCROLLBAR-FACE-COLOR: #ddeeff; SCROLLBAR-HIGHLIGHT-COLOR: #ffffff; SCROLLBAR-SHADOW-COLOR: #ABDBEC; SCROLLBAR-3DLIGHT-COLOR: #A4DFEF; SCROLLBAR-ARROW-COLOR: steelblue; SCROLLBAR-TRACK-COLOR: #DDF0F6; SCROLLBAR-DARKSHADOW-COLOR: #9BD6E6">
<table style="font-size: 11 pt; border-collapse:collapse" height=100% width=100% border=1 cellspadding=2 bordercolorlight=#808080 bordercolordark=#C0C0C0 cellpadding=2 align=left bordercolor=#FFFFFF cellspacing=1>;
<tr><td align=center bgcolor=#3E7BB9 width=100% height=100%><b><font color=#FFFFFF>WAM</font></b></td></tr>
% if (is_admin) {
<tr><td align=center bgColor=#6699cc width=100% height=100%><a href="/help/help_root.htm" style="text-decoration: none"><%=l('Admin User Manual')%></a></td></tr>
<tr><td align=center bgcolor=#FFCC00 width=100% height=100%><b><%=l('System Management')%></b></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/config" style="text-decoration: none"><%=l('Config Your System')%></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/setadmin" style="text-decoration: none"><%=l('Setup WAM Manager')%></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/filesmgr" style="text-decoration: none"><%=l('File Manager')%></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/sharemgr" style="text-decoration: none"><%=l('Share Folder')%></a></td></tr>
<tr><td align=center bgColor=#FFCC00 width=100% height=100%><b><%=l('Account Management')%></b></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/addgrp" style="text-decoration: none"><%=l('Add Group')%></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/addone" style="text-decoration: none"><%=l('Creat an Account')%></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/delete" style="text-decoration: none"><%=l('Delete User or Group')%></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/autoadd" style="text-decoration: none"><%=l('Auto Create User Account')%></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/upload" style="text-decoration: none"><%=l('Creat User Account from File')%></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/resetpw" style="text-decoration: none"><%=l('Reset Password')%></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/chgpw" style="text-decoration: none"><%=l('Change My Password')%></a></td></tr>
<tr><td align=center bgColor=#ffcc00 width=100% height=100%><b><%=l('Log Out')%></td></tr>
<tr><td align=center bgColor=#3E7BB9 width=100% height=100%><a href="/relogon" target=_top style="text-decoration: none"><%=l('Log Out')%></a></td></tr>
% } else {
<tr><td align=center bgColor=#FFCC00 width=100% height=100%><a href="/help/help_user.htm" style="text-decoration: none"><b><font color=black><%=l('User Manual')%></b></font></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/filesmgr" style="text-decoration: none"><%=l('File Manager')%></a></td></tr>
<tr><td align=center bgColor=#6699CC width=100% height=100%><a href="/chgpw" style="text-decoration: none"><%=l('Change My Password')%></a></td></tr>
<tr><td align=center bgColor=#ffcc00 width=100% height=100%><b><%=l('Log Out')%></td></tr>\n";
<tr><td align=center bgColor=#3E7BB9 width=100% height=100%><a href="/relogon" target=_top style="text-decoration: none"><%=l('Log Out')%></a></td></tr>
% }
</table></body></html>

@@ right.html.ep
% title l('Login WAM');
% layout 'default';
<center><a href="javascript:onclick=alert('<%=l('Please type your Account & Password below first!!')%>')" border=0><img align=absmiddle src=/img/wam.gif border=0></a>

@@ logon_form.html.ep
% title l('Login WAM');
% layout 'default';
<center><a href="javascript:onclick=alert('<%=l('Please type your Account & Password below first!!')%>')" border=0><img align=absmiddle src=/img/wam.gif border=0></a>
%= form_for logon => begin
%= csrf_field
<table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>
<tr><th align=left>
%= label_for user => l('Account')
：<td>
%= text_field 'user', maxlength => 20, size => 20
<th align=right>
%= label_for password => l('Password')
：<td>
%= password_field 'password', size => 20
<td  colspan=2 align=center>
%= submit_button, value => l('Login WAM')
</table>
% end
</center>

@@ layouts/default.html.ep
<html>
<head>
<meta http-equiv="Content-Type" content="<%=l 'text/html; charset=Windows-1252' %>">
<META HTTP-EQUIV="Pargma" CONTENT="no-cache">
<title><%=title %></title>
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
<font size=+2 face="<%=l 'Arial' %>" color=darkblue><%= title %> </font> [
% if (is_admin) {
<a href=/help/help_root.htm target=_blank><%=l('Admin User Manual')%></a>
% } else {
<a href=/help/help_user.htm target=_blank><%=l('User Manual')%></a>
% }
 ]</center>
<%= content %>
<hr color=#FF0000><center><font size=3>
【<a href="javascript:history.go(-1)"><img align=absmiddle src=/img/upfolder.gif border=0><%=l 'Go Back' %></a>  】
</font></center>
</body>
</html>

@@ img/wam.gif (base64)
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

@@ img/upfolder.gif (base64)
R0lGODlhFwAWAKIAAAcHB///B4d/h8e/x////wAAAAAAAAAAACwAAAAAFwAWAAADYki63E6AjEmrtSLevbPk4ORVQFmGwzgBwdAGQKiadH1Ss6u/+xCLGh8vxnv9UkGi71T04ZKtWg/2/ChhzWh1NZy6jjmjVAu0ZqfgpLeZttrebRRIJb/Q6xWPYM/v+/9wgW8JADs=
