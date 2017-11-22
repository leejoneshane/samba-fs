#!/usr/bin/perl -U
# 程式$SYSMSG{'sign_separate'}多人郵件遞送伺服器
# 版次$SYSMSG{'sign_separate'}0.1
# 修改日期$SYSMSG{'sign_separate'}2001/6/5
# 程式設計$SYSMSG{'sign_separate'}李忠憲 (hp2013@ms8.hinet.net)
# 頁面美工$SYSMSG{'sign_separate'}黃自強 (DD@mail.ysps.tp.edu.tw)
# 使用本程式必須遵守以下版權規定$SYSMSG{'sign_separate'}
# 本程式遵守GPL 開放原始碼之精神，但僅授權您個人使用
# 此檔頭為本程式版權的一部份，請勿將此檔頭移除
# program: Multi-user Mailer Server
# author: Shane Lee(hp2013@ms8.hinet.net)
# UI design: John Hwang(DD@mail.ysps.tp.edu.tw)
# This Software is Open Source, but for personal use only.
# This title is a part of License. You can NOT remove it.
#
# 使用方法$SYSMSG{'sign_separate'}
# 1. 在自己的網頁上加入超連結，<a href=http://xxx.edu.tw:12000/mail.cgi>寫信給我</a>
# 2. 指定收件者
# 　 在網頁上加入超連結，<a href=http://xxx.edu.tw:12000/mail.cgi?user=yyyy>寫信給本班聯絡人</a>
# 　 yyyy填入要處理信件的使用者帳號
#
$config = "./wam.conf";
$lang_base = "/usr/libexec/wam/lang";
@referers = ('localhost','127.0.0.1');
##############################################################################
$HOST=`/bin/hostname`;
$HOST=~ s/\n//g;

sub check_referer {
	my $check_referer = 0;
	my (@addrs);

	$addr = $ENV{'REMOTE_ADDR'};
	$url = $ENV{'HTTP_REFERER'};
	if ($url =~ m|https?://([^/]*)/~([\w.]+)/(.*)|i) {
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

sub err_user {
	&head("$SYSMSG{'title_system_info'}");
	print "<center><table border=0 style=font-size:11pt><tr><td><p><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'err_cannot_find_online_mail'}</font></p>\n";
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

sub head {
	my($title) = @_;
	print "Content-type: text/html\n\n";
	print '<head><meta http-equiv=Content-Type content="text/html; charset=UTF8">'."\n";
	print "<title>$title</title><script>\n";
	print "function init() { thisform = document.myform; }\n";
	print 'function chk_empty(item) { if (item.value=="") { return true; } }'."\n";
	print "</script></head><body STYLE='font-size:11pt' bgcolor=#ddeeff><center><font size=6 face=$SYSMSG{'variable_font'} color=darkblue>$title</font></center>";
	print '<hr color="#FF0000" width=90%>';
}

sub foot {
	print '<hr color="#FF0000" width=90%>';
	print "<center><font size=3>$SYSMSG{'sign_left'}<a href=\"javascript:history.go(-1)\"><img src=/img/set_gb.gif border=0>$SYSMSG{'backto_prev_page'}</a> | ";
	print "<a href=\"http://webmail.ysps.tp.edu.tw/download/\"><img src=/img/m_wam.gif border=0>$SYSMSG{'download_wam'} $SYSMSG{'sign_right'}</a>";
	print "</font></center></body></html>";
}

sub mailer {
	my($to, $from, $usr, $subject, $body) = @_;
	$from = $SYSMSG{'gbook_miss_from'} if ($from eq "");
	open(MAIL,"|$CONFIG{'mailprog'} -t")  || &err_disk("$SYSMSG{'err_cannot_open'} $CONFIG{'mailprog'} $SYSMSG{'program'}<br>");
	print MAIL "To: $to\n";
	print MAIL "From: $from\n";
	print MAIL "Subject: $subject\n\n";
	print MAIL "$usr $SYSMSG{'mail_from'} $user $SYSMSG{'mail_homepage'} $SYSMSG{'mail_to_you'}$SYSMSG{'sign_separate'}\n";
	print MAIL "-" x 75 . "\n\n";
	print MAIL "$body\n\n";
	print MAIL "-" x 75 . "\n\n";
	close (MAIL);
}

#***********************************************************************************
# MAIN
#***********************************************************************************
&check_referer;
&read_conf;
&get_lang;
&get_form_data;
$user = $DATA{'user'} if ($DATA{'user'} ne '');
$home = (getpwnam($user))[7];
$muid = (getpwnam($user))[2];
&err_user if ($home eq '' || $muid < 500);

if ($DATA{'step'} eq '') {
	&head("$SYSMSG{'mail_title'}-$SYSMSG{'mail_to_owner'}$user");
	print "<script>\n function check() { if (chk_empty(thisform.myname) || chk_empty(thisform.subject) || chk_empty(thisform.from) || chk_empty(thisform.body)) { alert('$SYSMSG{'err_blank_input'}'); }\n else { thisform.submit(); } }\n</script>\n";
	print "</head><body Onload=init() STYLE='font-size:11pt' bgcolor=#ffffff><center><font color=darkblue>$SYSMSG{'mail_hope_reply'}<font color=blue> $user </font>$SYSMSG{'mail_cannot_reply'}</font></center>\n";
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=step value=sendmail>\n";
	print "<input type=hidden name=user value=$user>\n";
	print "<input type=hidden name=to value=\"$user\@$HOST\">\n";
	print "<table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
	print "<a href='mailto:$user\@$HOST\?subject=$user 您好,網頁參觀者有話對您說您...&body=親愛的 $user 您好! %0a%0a%0a================================================================%0a此郵件由 http:\/\/$HOST\/:12000 的WAM主機寄發%0a================================================================%0a'>我要用自己的郵件程式寫信給 $user (可寄附加檔)</a>\n";
	print "<tr><th align=right><font color=darkgreen>$SYSMSG{'mail_input_name'}<img src=/img/fwmail.gif>$SYSMSG{'sign_separate'}</font>\n";
	print "<td><input type=text name=myname>\n";
	print "<tr><th align=right><font color=darkgreen>$SYSMSG{'mail_input_mailbox'}<img src=/img/getmail.gif>$SYSMSG{'sign_separate'}</font>\n";
	print "<td><input type=text name=from>$SYSMSG{'mail_optional'}\n";
	print "<tr><th align=right><font color=darkred>$SYSMSG{'mail_input_subject'}<img src=/img/newmail.gif>$SYSMSG{'sign_separate'}</font>\n";
	print "<td><input type=text name=subject>\n";
	print "<tr><th align=right><font color=darkblue>$SYSMSG{'mail_input_body'}<img src=/img/mail-big.gif>$SYSMSG{'sign_separate'}</font>\n";
	print "<td><textarea rows=10 cols=50 name=body></textarea>\n";
	print "<tr><td><td><input type=button value=\" $SYSMSG{'mail_confirm'} $user \" onclick=javascript:check()>\n";
	print "</table>";
	print "</form></center>";
	&foot();
} elsif ($DATA{'step'} eq 'mailto' && $DATA{'to'}) {
	&head("$SYSMSG{'mail_title'}");
	print "<script>\n function check() { if (chk_empty(thisform.myname) || chk_empty(thisform.subject) || chk_empty(thisform.body)) { alert('$SYSMSG{'err_blank_input'}'); }\n else { thisform.submit(); } }\n</script>\n";
	print "</head><body Onload=init() STYLE='font-size:11pt' bgcolor=#ffffff><center><font color=#6699cc>$SYSMSG{'mail_someone_hint'}</font></center>\n";
	print "<center><form name=myform method=post>\n";
	print "<input type=hidden name=step value=sendmail>\n";
	print "<input type=hidden name=user value=$user>\n";
	print "<input type=hidden name=to value=$DATA{'to'}>\n";
	print "<table border=0 cellpadding=3 cellspacing=1 style=font-size:11pt>\n";
	print "<tr><th align=right>$SYSMSG{'mail_to_whom'}\n";
	print "<td>$DATA{'to'}";
	print "<tr><th align=right><font color=darkgreen>$SYSMSG{'mail_input_name'}<img src=/img/fwmail.gif>$SYSMSG{'sign_separate'}</font>\n";
	print "<td><input type=text name=myname>\n";
	print "<tr><th align=right><font color=darkgreen>$SYSMSG{'mail_input_mailbox'}<img src=/img/getmail.gif>$SYSMSG{'sign_separate'}</font>\n";
	print "<td><input type=text name=from>\n";
	print "<tr><th align=right><font color=darkred>$SYSMSG{'mail_input_subject'}<img src=/img/newmail.gif>$SYSMSG{'sign_separate'}</font>\n";
	print "<td><input type=text name=subject>\n";
	print "<tr><th align=right><font color=darkblue>$SYSMSG{'mail_input_body'}<img src=/img/mail-big.gif>$SYSMSG{'sign_separate'}</font>\n";
	print "<td><textarea rows=10 cols=50 name=body></textarea>\n";
	print "<tr><td><td><input type=button value=\" $SYSMSG{'mail_confirm'} $DATA{'to'} \" onclick=javascript:check()>\n";
	print "</table>";
	print "</form></center>";
	&foot();
} elsif ($DATA{'step'} eq 'sendmail') {
	&mailer($DATA{'to'},$DATA{'from'},$DATA{'myname'},$DATA{'subject'},$DATA{'body'});
	&head("$SYSMSG{'mail_title'}");
	print "<script>alert(\"$SYSMSG{'mail_completed'}\")</script>\n";
	print "<script>history.go(-2)</script>\n";
	&foot();
}
