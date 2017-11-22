#!/usr/bin/perl -U
# 程式：多人留言版伺服器
# 版次：1.1
# 修改日期：2001/6/5
# 程式設計：李忠憲 (hp2013@ms8.hinet.net)
# 頁面美工：黃自強 (DD@mail.ysps.tp.edu.tw)
# 使用本程式必須遵守以下版權規定：
# 本程式遵守GPL 開放原始碼之精神，但僅授權您個人使用
# 此檔頭為本程式版權的一部份，請勿將此檔頭移除
# program: Multi-user Guestbook Server
# author: Shane Lee(hp2013@ms8.hinet.net)
# UI design: John Hwang(DD@mail.ysps.tp.edu.tw)
# This Software is Open Source, but for personal use only.
# This title is a part of License. You can NOT remove it.
#
# 使用方法：
# 1. 使用 wam.cgi 來設定留言版及管理留言
# 　在網頁上加入超連結，<a href=http://xxx.edu.tw:12000/gbook.cgi>我的留言版</a>
# 2. 指定共用留言版
# 　在網頁上加入超連結，<a href=http://xxx.edu.tw:12000/gbook.cgi?user=yyyy>本班的留言版</a>
# 　yyyy填入提供公用留言版的使用者帳號
#
$config = "./wam.conf";
$lang_base = "/usr/libexec/wam/lang";
$gb_config = '.guestbook_conf';
$gb_data = '.message_data';
$gb_reply = '.reply_data';
$gb_subscribe = '.subscribe_data';
$cgi_url = 'gbook.cgi';
$wam_url = '/';
######  加入能提供訂閱功能的網址,如官方網站
@referers = ('localhost','127.0.0.1');
##############################################################################
$| = 1;
$HOST=`/bin/hostname`;
$HOST=~ s/\n//g;
@DOMAIN = split(/./,$HOST);
$ii = 0;
foreach $DN (@DOMAIN) {
	$DOMAIN[$ii]=".$DOMAIN[$ii]" if ($DN ne '');
	$ii++;
}
$PORT="12000";

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

sub get_lang {
	my($line);
	$CONFIG{'lang'}='Big-5'  if ($CONFIG{'lang'} eq '');
	open (LANG, "$lang_base/$CONFIG{'lang'}") || &err_disk("磁碟錯誤，語言套件目錄無法讀取。disk error! can't open language defined<br>");
	while ($line = <LANG>) {
		my($name, $value) = split(/:::/, $line);
		$value =~ s/\n//g;
		$SYSMSG{$name} = $value;
	}
	close(LANG);
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

sub err_disk {
	my($msg) = @_;
	&head("$SYSMSG{'title_system_info'}");
	print "<center><table border=0 STYLE=font-size:9pt><tr><td><p><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'err_disk_failue'}</font></p>\n";
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

sub err_user {
	&head("$SYSMSG{'title_system_info'}");
	print "<center><table border=0 STYLE=font-size:9pt><tr><td><p><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'err_cannot_find_gbook'}</font></p>\n";
	print '<ul>';
	print "<li>$SYSMSG{'msg_lost_username'}";
	print "<li>$SYSMSG{'msg_no_such_user'}";
	print '</ul>';
	print '<hr color="#FF0000">';
	print "<center><a href=\"javascript:history.go(-1)\"><img align=absmiddle src=/img/upfolder.gif border=0>  $SYSMSG{'backto_prev_page'}</a></center>";
	print '</table></center></body>';
	print "</html>";
	exit 0;
}

sub read_gb_conf {
	my($conf) = @_;
	if (-e $conf) {
		open (CFG, "< $conf") || &err_disk("$SYSMSG{'err_cannot_open_gbook_config'}<br>");
		while ($line = <CFG>) {
			my($name, $value) = split(/:/, $line);
			$value =~ s/\n//g;
			$GBCONF{$name} = $value;
		}
		close(CFG);
	} else {
		$GBCONF{'title'} = " $user".$SYSMSG{'gbook_owned'};
		$GBCONF{'many'} = 5;
		$GBCONF{'page_jump'} = 'yes';
		$GBCONF{'email'} = 'no';
		$GBCONF{'sort'} = 'by_date';
		open (CFG, "> $conf") || &err_disk("$SYSMSG{'err_cannot_open_gbook_config'}<br>");
		foreach $name (keys %GBCONF) {
			print CFG "$name:$GBCONF{$name}\n";
		}
		close(CFG);
	}
}

sub read_data {
	my($data) = @_;
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
				$GBIP{$cnt} = '0.0.0.0' if ($parn eq '0' or $parn eq '');
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

sub write_data {
	my($data) = @_;
	open (DATA, "> $data") || &err_disk("$SYSMSG{'err_cannot_open_gbook_message'}<br>");
	foreach $cnt (keys %GBDATE) {
		$str = join ':::',$cnt,$GBIP{$cnt},$GBDATE{$cnt},$GBAUTH{$cnt},$GBMAIL{$cnt},$GBTITLE{$cnt},$MESSAGES{$cnt},$MODE{$cnt}."\n";
		print DATA $str;
	}
	close(DATA);
}

sub read_reply {
	my($data) = @_;
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

sub write_reply {
	my($data) = @_;
	open (DATA, "> $data") || &err_disk("$SYSMSG{'err_cannot_open_gbook_message'}<br>");
	foreach $cnt (keys %REDATE) {
		$str = join ':::',$cnt,$REPARN{$cnt},$REDATE{$cnt},$REAUTH{$cnt},$REMAIL{$cnt},$RETITLE{$cnt},$REPLYS{$cnt},$REIP{$cnt}."\n";
		print DATA $str;
	}
	close(DATA);
}

sub read_subscribe {
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

sub write_subscribe {
	my($data) = @_;
	open (DATA, "> $data") || &err_disk("$SYSMSG{'err_cannot_open_gbook_subscribe'}<br>");
	foreach $line (sort values %SUBSCRIBE) {
		print DATA "$line\n";
	}
	close(DATA);
}

sub get_cnt {
	my $i;
	for ($i=1;$i<65535;$i++) {
	    last if (!defined($GBDATE{$i}));
	}
	$i;
}

sub get_recnt {
	my $i;
	for ($i=1;$i<65535;$i++) {
	    last if (!defined($REDATE{$i}));
	}
	$i;
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

sub head {
	my($title) = @_;
	print "Content-type: text/html\n\n";
	print "<head><meta http-equiv=Content-Type content=\"$SYSMSG{'charset'}\">\n";
	print "<title>$title</title>\n";
	print "</head><body STYLE='font-size:9pt' bgcolor=#ddeeff><center><font size=6 face=$SYSMSG{'variable_font'} color=darkblue>$title</font></center>";
	print '<hr color="#FF0000" width=90%>';
}

sub foot {
	print '<hr color="#FF0000" width=90%>';
	print "<center><a href=\"http://webmail.ysps.tp.edu.tw/download/\"><img src=img/g_wam.gif border=0>$SYSMSG{'download_wam'}</a>";
	print "</font></center></body></html>";
}

sub bydate {
	$GBDATE{$b} <=> $GBDATE{$a};
}

sub byname {
	$GBAUTH{$a} cmp $GBAUTH{$b};
}

sub byredate {
	$REDATE{$a} <=> $REDATE{$b};
}

sub mailer {
	my($to, $from, $usr, $subject, $body) = @_;
	$from = $SYSMSG{'gbook_miss_from'} if ($from eq "");
	open(MAIL,"|$CONFIG{'mailprog'} -t")  || &err_disk("$SYSMSG{'err_cannot_open'} $CONFIG{'mailprog'} $SYSMSG{'program'}<br>");
	print MAIL "To: $to\n";
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

sub submailer {
	my($from, $usr, $subject, $body) = @_;
	$from = $SYSMSG{'gbook_miss_from'} if ($from eq "");
	open(MAIL,"|$CONFIG{'mailprog'} -t")  || &err_disk("$SYSMSG{'err_cannot_open'} $CONFIG{'mailprog'} $SYSMSG{'program'}<br>");
	print MAIL "To: gbook-$user\@$HOST\n";
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
#***********************************************************************************
# MAIN
#***********************************************************************************
&check_referer if ($ENV{'QUERY_STRING'} ne '' || $ENV{'CONTENT_LENGTH'} gt 0);
&read_conf;
&get_lang;
&get_form_data;
$user = $DATA{'user'} if ($DATA{'user'} ne '');
$home = (getpwnam($user))[7];
$muid = (getpwnam($user))[2];
&err_user if ($home eq '' || $muid < 500 && $muid > 0);
&read_gb_conf("$home/$gb_config");
&read_data("$home/$gb_data");
&read_reply("$home/$gb_reply");

if ($DATA{'step'} eq '') {
	$DATA{'keyword'} =~ s/[<> _-]//g;
	&head($GBCONF{'title'});
	print "<BR><CENTER>【<a href=$cgi_url?step=addnew&user=$user><img src=/img/write2.gif border=0>$SYSMSG{'gbook_write'}</A> | ";
	print "<a href=$cgi_url?step=query&user=$user><img src=/img/chgpw.gif border=0>$SYSMSG{'gbook_subscribe_or_not'}</A> | " if ($GBCONF{'subscribe'} eq 'yes');
	print "<a href=$wam_url\mail.cgi?user=$user><img src=/img/mail-big.gif border=0>$SYSMSG{'gbook_mailto_owner'}</A> | <a href=$wam_url?step=edit_gb><img src=/img/chgpw.gif border=0>$SYSMSG{'gbook_manage'}</A>】</CENTER><hr size=1 color=red width=90%>\n";
	print "<center><form method=post><input type=hidden name=user value=$user><input type=hidden name=page value=$DATA{'page'}><input type=hidden name=startpage value=$DATA{'startpage'}><fieldset><p align=center><b>$SYSMSG{'gbook_keyword_search'}</b><input type=text name=keyword value=\"$DATA{'keyword'}\"><input type=submit value=\" $SYSMSG{'gbook_search_confirm'} \"></p></center></fieldset></form>";
	@GB = sort byname keys %GBAUTH if ($GBCONF{'sort'} eq 'by_name');
	@GB = sort bydate keys %GBDATE if ($GBCONF{'sort'} eq 'by_date');
	@REPLY = sort byredate keys %REDATE;
	if ($DATA{'keyword'} ne '') {
		for ($i=0;$i<=$#REPLY;$i++) {
			if ($RETITLE{$REPLY[$i]} !~ /$DATA{'keyword'}/ && $REPLYS{$REPLY[$i]} !~ /$DATA{'keyword'}/) {
			    splice(@REPLY,$i,1);
			    $i = $i - 1;
			}
		}
		for ($j=0;$j<=$#GB;$j++) {
			if ($GBTITLE{$GB[$j]} !~ /$DATA{'keyword'}/ && $MESSAGES{$GB[$j]} !~ /$DATA{'keyword'}/) {
				$chkflag = 0;
				for ($i=0;$i<=$#REPLY;$i++) {
					if ($REPARN{$REPLY[$i]} eq $GB[$j]) {
					    $chkflag = 1;
					    last;
					}
				}
				if ($chkflag eq 0) {
    				    splice(@GB,$j,1);
				    $j = $j - 1;
				}
			}
		}
	}
	$DATA{'page'} = 1 if ($DATA{'page'} eq ''); 
	$DATA{'startpage'} = 1 if ($DATA{'startpage'} eq ''); 
	if ($GBCONF{'page_jump'} ne 'no') {
		$start = $GBCONF{'many'} * ($DATA{'page'}-1);
		$start = 0 if ($start > $#GB);
		$end = $start + $GBCONF{'many'} - 1;
		$end = $#GB if ($end > $#GB);
	} else {
		$start = 0;
		$end = $#GB;
	}
	print "\n";
	if ($end < 0) {
		print "<center><font color=3699cc face=$SYSMSG{'variable_font'}><h2>$SYSMSG{'gbook_no_msg'}</h2></font><img src=/img/dingdong0.gif ></center>\n";
	} else {

	print "<center><fieldset><legend align=center><font color=red><b>$SYSMSG{'quick_jump'}</b></font></legend>";
	if ($GBCONF{'page_jump'} ne 'no') {
		$num = $DATA{'startpage'}-10;
		print "<a href=$cgi_url?user=$user&keyword=$DATA{'keyword'}&page=$num&startpage=$num>$SYSMSG{'ten_up'}</a>\n" if ($DATA{'startpage'} > 10);
		$num = $DATA{'page'}-1;
		print "<a href=$cgi_url?user=$user&keyword=$DATA{'keyword'}&page=$num&startpage=$DATA{'startpage'}>$SYSMSG{'sign_up'}</a>\n" if ($DATA{'page'} > 1);
		$pagecnt = $DATA{'startpage'}+9;
		$pagecnt = int($#GB/$GBCONF{'many'}+1) if (int($#GB/$GBCONF{'many'}+1) < $pagecnt);
		foreach ($DATA{'startpage'}..$pagecnt) {
			if ($DATA{'page'} == $_) {
				print "$_ ";
			} else {
				print "&nbsp;<a href=$cgi_url?user=$user&keyword=$DATA{'keyword'}&page=$_&startpage=$DATA{'startpage'}> $_ </a>";
			}
		}
		$num = $DATA{'page'}+1;
		print "<a href=$cgi_url?user=$user&keyword=$DATA{'keyword'}&page=$num&startpage=$DATA{'startpage'}>$SYSMSG{'sign_down'}</a>\n" if ($end < $#GB);
		$num = $DATA{'startpage'}+10;
		print "<a href=$cgi_url?user=$user&keyword=$DATA{'keyword'}&page=$num&startpage=$num>$SYSMSG{'ten_down'}</a>\n" if ($DATA{'startpage'}+9 < int($#GB/$GBCONF{'many'}+1));
	}
	print "</center></fieldset><br>";

		for ($start..$end) {
			$cnt = $GB[$_];
			$mydate = &get_date($GBDATE{$cnt});
			if ($GBMAIL{$cnt} eq "") {
				print "<fieldset><legend> $GBAUTH{$cnt} 　 <font color= 6699cc>$SYSMSG{'gbook_msg_date'} $mydate</font> （$GBIP{$cnt}） ";
			} else {
				print "<fieldset><legend> <img src=/img/fwmail.gif border=0><a href=mail.cgi?step=mailto&to=$GBMAIL{$cnt}&user=$user> $GBAUTH{$cnt}</a> 　 <font color= 6699cc> $SYSMSG{'gbook_msg_date'} $mydate</font> （$GBIP{$cnt}） ";
			}
			if ($MODE{$cnt} eq '1') {
				print "</legend>\n";
				print "<div align=right><table border=0 cellpadding=3 cellspacing=1 STYLE=font-size:9pt width=90%><tr><td bgcolor=#6699cc width=15%><font color=white><b>$SYSMSG{'gbook_msg_subject'}</font></td><td bgcolor=#6699cc><font color=white>$GBTITLE{$cnt}</font></td>\n";
				print "<tr><td bgcolor=#ffcccc width=15%><font color=darkred><b>$SYSMSG{'gbook_msg_content'}</b></font></td><td  bgcolor=#ffdcdc><font color=darkblue>$SYSMSG{'gbook_private_hint'}</font><a href=$wam_url><img src=/img/wav.gif border=0>$SYSMSG{'gbook_view_private'}</A></td></tr>";
			} else {
				print "　<a href=$cgi_url?step=reply&user=$user&keyword=$DATA{'keyword'}&page=$DATA{'page'}&startpage=$DATA{'startpage'}&id=$cnt>$SYSMSG{'gbook_msg_reply'}</a>　</legend>\n";
				print "<div align=right><table border=0 cellpadding=3 cellspacing=1 STYLE=font-size:9pt width=90%><tr><td bgcolor=#6699cc width=15%><font color=white><b>$SYSMSG{'gbook_msg_subject'}</font></td><td bgcolor=#6699cc><font color=white>$GBTITLE{$cnt}</font></td>\n";
				print "<tr><td bgcolor=#aaefff width=15%><font color=darkred><b>$SYSMSG{'gbook_msg_content'}</b></font></td><td  bgcolor=#ccffee><font color=darkblue>$MESSAGES{$cnt}</font></td></tr>";
			}
			print "<tr><td colspan=2><div align=right><table border=0 cellpadding=3 cellspacing=1 style=font-size:9pt width=90%>\n";
			for (0..$#REPLY) {
				$parn = $REPLY[$_];
				if ($REPARN{$parn} eq $cnt) {
					$mydate = &get_date($REDATE{$parn});
					if ($REMAIL{$cnt} eq "") {
						print "<tr><td colspan=2> $REAUTH{$parn} 　 <font color=#6699cc> $SYSMSG{'gbook_msg_reply_date'} $mydate</font> （$REIP{$parn}）</td></tr>\n";
					} else {
						print "<tr><td colspan=2><img src=/img/fwmail.gif border=0><a href=mail.cgi?step=mailto&to=$REMAIL{$parn}&user=$user> $REAUTH{$parn}</a><font color=#aa99cc> $SYSMSG{'gbook_msg_date'} $mydate</font> （$REIP{$parn}）</td></tr>\n";
					}
					print "<tr><td bgcolor=#13a8b9 width=15%><font color=white><b>$SYSMSG{'gbook_msg_reply_subject'}</font></td><td bgcolor=#13a8b9><font color=white>$RETITLE{$parn}</font></td></tr>\n";
					print "<tr><td bgcolor=#aaefff width=15%><font color=darkred><b>$SYSMSG{'gbook_msg_reply_content'}</b></font></td><td  bgcolor=#ccffee><font color=darkblue>$REPLYS{$parn}</font></td></tr>";
				}
			}
			print "</table></div></td></tr></table></div></fieldset><br>\n";
		}
	}

	print "<center><fieldset><legend align=center><font color=red><b>$SYSMSG{'quick_jump'}</b></font></legend>";
	if ($GBCONF{'page_jump'} ne 'no') {
		$num = $DATA{'startpage'}-10;
		print "<a href=$cgi_url?user=$user&keyword=$DATA{'keyword'}&page=$num&startpage=$num>$SYSMSG{'ten_up'}</a>\n" if ($DATA{'startpage'} > 10);
		$num = $DATA{'page'}-1;
		print "<a href=$cgi_url?user=$user&keyword=$DATA{'keyword'}&page=$num&startpage=$DATA{'startpage'}>$SYSMSG{'sign_up'}</a>\n" if ($DATA{'page'} > 1);
		$pagecnt = $DATA{'startpage'}+9;
		$pagecnt = int($#GB/$GBCONF{'many'}+1) if (int($#GB/$GBCONF{'many'}+1) < $pagecnt);
		foreach ($DATA{'startpage'}..$pagecnt) {
			if ($DATA{'page'} == $_) {
				print "$_ ";
			} else {
				print "&nbsp;<a href=$cgi_url?user=$user&keyword=$DATA{'keyword'}&page=$_&startpage=$DATA{'startpage'}> $_ </a>";
			}
		}
		$num = $DATA{'page'}+1;
		print "<a href=$cgi_url?user=$user&keyword=$DATA{'keyword'}&page=$num&startpage=$DATA{'startpage'}>$SYSMSG{'sign_down'}</a>\n" if ($end < $#GB);
		$num = $DATA{'startpage'}+10;
		print "<a href=$cgi_url?user=$user&keyword=$DATA{'keyword'}&page=$num&startpage=$num>$SYSMSG{'ten_down'}</a>\n" if ($DATA{'startpage'}+9 < int($#GB/$GBCONF{'many'}+1));
	}
	print "</center></fieldset><br>";
	print "</center></BODY></HTML>";
	&foot;
} elsif ($DATA{'step'} eq 'addnew') {
	&head($SYSMSG{'gbook_title_mailto_owner'});
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=user value=$user>\n";
	print "<input type=hidden name=step value=post>\n";
	print "<input type=hidden name=keyword value=$DATA{'keyword'}>\n";
	print "<input type=hidden name=page value=$DATA{'page'}>\n";
	print "<input type=hidden name=startpage value=$DATA{'startpage'}>\n";
	print "<table border=0 cellpadding=3 cellspacing=1 style=font-size:9pt>\n";
	print "<tr><th align=right><font color=darkblue>$SYSMSG{'gbook_input_name'}</font>\n";
	print "<td><input type=text name=auth>\n";
	print "<tr><th align=right><font color=darkgreen>$SYSMSG{'gbook_input_email'}</font>\n";
	print "<td><input type=text name=email>$SYSMSG{'gbook_email_hint'}\n";
	print "<tr><th align=right><font color=darkred>$SYSMSG{'gbook_input_mode'}</font><td>\n";
	print "<input type=radio name=mode value=0 checked>$SYSMSG{'gbook_mode_public'}\n";
	print "<input type=radio name=mode value=1>$SYSMSG{'gbook_mode_private'}\n";
	print "<tr><th align=right><font color=red>$SYSMSG{'gbook_msg_subject'}</font>\n";
	print "<td><input type=text name=subject>\n";
	print "<tr><th align=right><font color=blue>$SYSMSG{'gbook_msg_content'}</font>\n";
	print "<td><textarea rows=10 cols=50 name=body></textarea>\n";
	print "<tr><td><td><input type=submit value=\" $SYSMSG{'gbook_write_confirm'} \">\n";
	print "</table></form></center>";
	&foot;
} elsif ($DATA{'step'} eq 'query') {
	&head("$SYSMSG{'gbook_title_subscribe'} $GBCONF{'title'}");
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=user value=$user>\n";
	print "<input type=hidden name=step value=subscribe>\n";
	print "<input type=hidden name=keyword value=$DATA{'keyword'}>\n";
	print "<input type=hidden name=page value=$DATA{'page'}>\n";
	print "<input type=hidden name=startpage value=$DATA{'startpage'}>\n";
	print "<table border=0 cellpadding=3 cellspacing=1 style=font-size:9pt width=65%>\n";
	print "<tr><td colspan=2>$SYSMSG{'gbook_thanks_for_subscribe'} $GBCONF{'title'}$SYSMSG{'gbook_subscribe_form'}";
	print "$SYSMSG{'gbook_howto_subscribe'}</td></tr>\n";
	print "<tr><th align=right><font color=darkgreen>$SYSMSG{'gbook_your_email'}</font>\n";
	print "<td><input type=text name=email>$SYSMSG{'gbook_email_hint'}\n";
	print "<tr><th align=right><font color=darkred>$SYSMSG{'gbook_what_you_want'}</font><td>\n";
	print "<input type=radio name=mode value=0 checked>$SYSMSG{'gbook_subscribe'}\n";
	print "<input type=radio name=mode value=1>$SYSMSG{'gbook_unsubscribe'}\n";
	print "<tr><td><td><input type=submit value=\" $SYSMSG{'gbook_subscribe_confirm'}\">\n";
	print "</table></form></center>";
	&foot;
} elsif ($DATA{'step'} eq 'subscribe') {
	&read_subscribe("$home/$gb_subscribe");
	foreach $i (keys %SUBSCRIBE) {
		delete $SUBSCRIBE{$i} if ($SUBSCRIBE{$i} eq $DATA{'email'});
	}
	$SUBSCRIBE{'new'} = $DATA{'email'} if ($DATA{'mode'} eq 0);
	&write_subscribe("$home/$gb_subscribe");
	open(MAIL,"|$CONFIG{'mailprog'} -t")  || &err_disk("$SYSMSG{'err_cannot_open'} $CONFIG{'mailprog'} $SYSMSG{'program'}<br>");
	print MAIL "To: $DATA{'email'}\n";
	print MAIL "From: $user\@$HOST\n";
	if ($DATA{'mode'} eq 0) {
		print MAIL "Subject: $GBCONF{'title'}$SYSMSG{'gbook_subscribe_info'}\n\n";
		print MAIL "-" x 105 . "\n\n";
		print MAIL "$SYSMSG{'gbook_subscribe_request_for'} $GBCONF{'title'}$SYSMSG{'gbook_make_sure'}";
		print MAIL "$SYSMSG{'gbook_please_click'} http://$HOST:$PORT/gbook.cgi?user=$user&step=checkok&email=$DATA{'email'} $SYSMSG{'gbook_to_complete_request'}\n";
		print MAIL "-" x 105 . "\n\n";
	} else {
		print MAIL "Subject: $GBCONF{'title'}$SYSMSG{'gbook_unsubscribe_info'}\n\n";
		print MAIL "-" x 105 . "\n\n";
		print MAIL "$GBCONF{'title'}$SYSMSG{'gbook_goodbye'}\n\n";
		print MAIL "-" x 105 . "\n\n";
	}
	close (MAIL);
	print "Location: $cgi_url?user=$user&keyword=$DATA{'keyword'}&page=$DATA{'page'}&startpage=$DATA{'startpage'}\n\n";
} elsif ($DATA{'step'} eq 'checkok') {
	&read_subscribe("$home/$gb_subscribe");
	foreach $i (keys %SUBSCRIBE) {
		delete $SUBSCRIBE{$i} if ($SUBSCRIBE{$i} eq $DATA{'email'});
	}
	$SUBSCRIBE{'new'} = $DATA{'email'};
	&write_subscribe("$home/$gb_subscribe");
	&head($SYSMSG{'gbook_title_thanks'});
	print "<center><h2><a href=$cgi_url?user=$user>$SYSMSG{'gbook_enter_view'}$GBCONF{'title'}</a></h2></center>\n";
	&foot;
} elsif ($DATA{'step'} eq 'reply') {
	&head($SYSMSG{'gbook_title_reply'});
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=user value=$user>\n";
	print "<input type=hidden name=step value=save>\n";
	print "<input type=hidden name=keyword value=$DATA{'keyword'}>\n";
	print "<input type=hidden name=page value=$DATA{'page'}>\n";
	print "<input type=hidden name=startpage value=$DATA{'startpage'}>\n";
	print "<input type=hidden name=parn value=$DATA{'id'}>\n";
	print "<table border=0 cellpadding=3 cellspacing=1 style=font-size:9pt>\n";
	print "<tr><th align=right><font color=darkblue>$SYSMSG{'gbook_input_name'}</font>\n";
	print "<td><input type=text name=auth>\n";
	print "<tr><th align=right><font color=darkgreen>$SYSMSG{'gbook_input_email'}</font>\n";
	print "<td><input type=text name=email>$SYSMSG{'gbook_email_hint'}\n";
	print "<tr><th align=right><font color=red>$SYSMSG{'gbook_msg_subject'}</font>：\n";
	print "<td><input type=text name=subject value=\"$SYSMSG{'gbook_msg_reply_subject'}$GBTITLE{$DATA{'id'}}\">\n";
	print "<tr><th align=right><font color=blue>$SYSMSG{'gbook_msg_content'}</font>\n";
	my $body = $MESSAGES{$DATA{'id'}};
	$body =~ s/<br>/\r\n>/g;
	print "<td><textarea rows=10 cols=50 name=body>>$body</textarea>\n";
	print "<tr><td><td><input type=submit value=\" $SYSMSG{'gbook_reply_confirm'} \">\n";
	print "</table></form></center>";
	&foot;
} elsif ($DATA{'step'} eq 'save') {
	$cnt = &get_recnt;
	$REIP{$cnt} = $addr;
	$REPARN{$cnt} = $DATA{'parn'};
	$REDATE{$cnt} = time;
	$REAUTH{$cnt} = $DATA{'auth'};
	$REMAIL{$cnt} = $DATA{'email'};
	$RETITLE{$cnt} = $DATA{'subject'};
	$DATA{'body'} =~ s/\r\n/<br>/g;
	$REPLYS{$cnt} = $DATA{'body'};
	&write_reply("$home/$gb_reply");
	&mailer("$user\@$HOST",$DATA{'email'},$DATA{'auth'},$DATA{'subject'},$DATA{'body'}) if ($GBCONF{'email'} eq 'yes');
	&submailer($DATA{'email'},$DATA{'auth'},$DATA{'subject'},$DATA{'body'}) if ($GBCONF{'subscribe'} eq 'yes');
	print "Location: $cgi_url?user=$user&keyword=$DATA{'keyword'}&page=$DATA{'page'}&startpage=$DATA{'startpage'}\n\n";
} elsif ($DATA{'step'} eq 'post') {
	$cnt = &get_cnt;
	$GBDATE{$cnt} = time;
	$GBIP{$cnt} = $addr;
	$GBAUTH{$cnt} = $DATA{'auth'};
	$GBMAIL{$cnt} = $DATA{'email'};
	$GBTITLE{$cnt} = $DATA{'subject'};
	$DATA{'body'} =~ s/\r\n/<br>/g;
	$MESSAGES{$cnt} = $DATA{'body'};
	$MODE{$cnt} = $DATA{'mode'};
	&write_data("$home/$gb_data");
	&mailer("$user\@$HOST",$DATA{'email'},$DATA{'auth'},$DATA{'subject'},$DATA{'body'}) if ($GBCONF{'email'} eq 'yes');
	&submailer($DATA{'email'},$DATA{'auth'},$DATA{'subject'},$DATA{'body'}) if ($GBCONF{'subscribe'} eq 'yes');
	print "Location: $cgi_url?user=$user&keyword=$DATA{'keyword'}&page=$DATA{'page'}&startpage=$DATA{'startpage'}\n\n";
}

