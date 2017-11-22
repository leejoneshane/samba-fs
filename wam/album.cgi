#!/usr/bin/perl -U
# 程式：圖庫管理員
# 版次：0.1
# 修改日期：2002/4/10
# 程式設計：李忠憲 (hp2013@ms8.hinet.net)
# 頁面美工：黃自強 (dd@mail.ysps.tp.edu.tw)
# 使用本程式必須遵守以下版權規定：
# 本程式遵守GPL 開放原始碼之精神，但僅授權教育用途或您個人使用
# 此檔頭為本程式版權的一部份，請勿將此檔頭移除
# program: WAM(Web-Base Accounts Manager)
# author: Shane Lee(hp2013@ms8.hinet.net)
# UI design: John Hwang(dd@mail.ysps.tp.edu.tw)
# special thanx prolin(prolin@sy3es.tnc.edu.tw) suport the passwd-checking javascript
# This Software is Open Source, but for personal use only.
# This title is a part of License. You can NOT remove it.
#
# 使用方法：
# 1. 使用 wam 來設定圖庫管理員及管理圖庫
# 　在網頁上加入超連結，<a href=https://xxx.edu.tw:12000/album>我的電子相簿</a>
# 2. 指定共用圖庫
# 　在網頁上加入超連結，<a href=https://xxx.edu.tw:12000/album?user=yyyy>九年一貫素材庫</a>
# 　yyyy 填入提供公用圖庫的使用者帳號
# 3. 顯示樣式設定
#   每個資料夾可以自行建立 message.htm 來指定顯示樣式，如未設定則沿用父資料夾的設定
#   message.htm 格式如下：
#   <!--
#     title=資料夾主題名稱
#     showdate=yes或no
#     showsize=yes或no
#     newtip=yes或no
#     bgcolor=背景色彩
#     bgpic=背景圖片URL
#     color=背景色彩
#     number=每列顯示圖片個數
#     width=限定圖片寬度
#     height=限定圖片高度
#   -->
#   您要一併顯示在網頁的說明文字（HTML 格式）
# 4. 注意事項
#    showdate 用來設定是否要顯示日期
#    showsize 用來設定是否要顯示檔案大小
#    newtip 用來設定是否要提示一週內的新檔案
#    僅指定圖片寬度時，高度將自動按照比例調整
#    僅指定圖片高度時，寬度將自動按照比例調整
#

$config = "/usr/libexec/wam/wam.conf";
$lang_base = "/usr/libexec/wam/lang";
$pic_conf = '.album_conf';
$cgi_url = '/album.cgi';
#*****************************************************************************************
$HOST=`/bin/hostname`;
$HOST=~ s/\n//g;

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
	$CONFIG{'lang'}='zh_TW'  if ($CONFIG{'lang'} eq '');
	open (LANG, "$lang_base/$CONFIG{'lang'}") || &err_disk("磁碟錯誤，語言套件目錄無法讀取。disk error! can't open language defined<br>");
	while ($line = <LANG>) {
		my($name, $value) = split(/:::/, $line);
		$value =~ s/\n//g;
		$SYSMSG{$name} = $value;
	}
	close(LANG);
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
}

sub check_referer {
	$url = $ENV{'HTTP_REFERER'};
	if ($url =~ m|https?://([^/]*)/~([\w.]+)/(.*)|i) {
		$user = $2;
	}
}

sub err_disk {
	my($msg) = @_;
	print "Content-type: text/html\n\n";
	print "<html><head><meta http-equiv=Content-Type content=\"$SYSMSG{'charset'}\">\n";
	print "<META HTTP-EQUIV=\"Pargma\" CONTENT=\"no-cache\">\n";
	print "<title>$SYSMSG{'title_system_info'}</title>\n";
	print "</head><body STYLE='font-size:9pt' bgcolor=#ddeeff><center><font size=6 face=$SYSMSG{'variable_font'} color=darkblue>$SYSMSG{'title_system_info'}</font><a href=/album-help.htm>$SYSMSG{'help'}</a></center>";
	print '<hr color="#FF0000" width=90%>';
	print "<center><table border=0 style=font-size:9pt><tr><td><p><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'err_disk_failue'}</font></p>\n";
	print $msg;
	print '<ul>';
	print "<li>$SYSMSG{'msg_if_disk_busy'}<a href=\"javascript:history.go(-1)\"><img align=absmiddle src=/img/upfolder.gif border=0>  $SYSMSG{'backto_prev_page'}</a>$SYSMSG{'msg_try_later'}";
	print "<li>$SYSMSG{'msg_if_config_incorrect'}<a href=/wam.cgi?step=config>$SYSMSG{'msg_setup_config'}</a>";
	print "<li>$SYSMSG{'msg_check_disk'}";
	print '</ul>';
	print '<hr color="#6699cc" size=1>';
	print "<center><a href=\"javascript:history.go(-1)\"><img align=absmiddle src=/img/upfolder.gif border=0>  $SYSMSG{'backto_prev_page'}</a></center>";
	print '</table></center></body>';
	print "</html>";
	exit 0;
}

sub err_user {
	print "Content-type: text/html\n\n";
	print "<html><head><meta http-equiv=Content-Type content=\"$SYSMSG{'charset'}\">\n";
	print "<META HTTP-EQUIV=\"Pargma\" CONTENT=\"no-cache\">\n";
	print "<title>$SYSMSG{'title_system_info'}</title><body>\n";
	print "</head><body STYLE='font-size:9pt' bgcolor=#ddeeff><center><font size=6 face=$SYSMSG{'variable_font'} color=darkblue>$SYSMSG{'title_system_info'}</font></center>";
	print '<hr color="#FF0000" width=90%>';
	print "<center><table border=0 style=font-size:9pt><tr><td><p><font color=blue face=$SYSMSG{'variable_font'} size=5>$SYSMSG{'err_cannot_find_album'}</font></p>\n";
	print '<ul>';
	print "<li>$SYSMSG{'msg_lost_username'}";
	print "<li>$SYSMSG{'msg_no_such_user'}";
	print '</ul>';
	print '<hr color="#6699cc" size=1>';
	print "<center><a href=\"javascript:history.go(-1)\"><img align=absmiddle src=/img/upfolder.gif border=0>  $SYSMSG{'backto_prev_page'}</a></center>";
	print '</table></center></body>';
	print "</html>";
	exit 0;
}

sub read_pic_conf {
	my($conf) = @_;
	%PICCONF=();
	if (-e $conf) {
		open (CFG, "< $conf") || &err_disk("$SYSMSG{'err_cannot_open_album_conf'} $conf<br>");
		while ($line = <CFG>) {
			my($name, $value) = split(/:/, $line);
			$value =~ s/\n//g;
			$PICCONF{$name} = $value;
		}
		close(CFG);
	} else {
		$PICCONF{'title'} = $user.$SYSMSG{'album_owned'};
		$PICCONF{'folder'} = 'album';
		$PICCONF{'showdate'} = 'yes';
		$PICCONF{'showsize'} = 'yes';
		$PICCONF{'newtip'} = 'yes';
		open (CFG, "> $conf") || &err_disk("$SYSMSG{'err_cannot_open_album_conf'} $conf<br>");
		foreach $name (keys %PICCONF) {
			print CFG "$name:$PICCONF{$name}\n";
		}
		close(CFG);
	}
}

sub read_pic_msg {
	$PICCONF{'bgcolor'} = '#FFFFFF';
	$PICCONF{'bgpic'} = '/img/album/none.gif';
	$PICCONF{'color'} = '#000080';
	$PICCONF{'message'} = '';
	my $path_cnt = scalar(@temp);
	my $flag=0;
	for ($i=0;$i<$path_cnt;$i++) {
		$mydir = join('/',@temp);
		if (-f "$album_root$mydir/message.htm") {
			$msg_file = "$album_root$mydir/message.htm";
			$flag=1;
			$i=$path_cnt;
		} else {
			pop(@temp);
		}
	}
	if ($flag eq 0 && -f "$album_root/message.htm") {
		$msg_file = "$album_root/message.htm";
		$flag=1;
	}
	if ($flag eq 1) {
		open (CFG, "< $msg_file") || &err_disk("$SYSMSG{'err_cannot_open_album_message'} $msg_file<br>");
		while ($line = <CFG>) {
			$PICCONF{'message'} .= $line;
			my($name, $value) = split(/=/, $line);
			$value =~ s/\r//g;
			$value =~ s/\n//g;
			$PICCONF{$name} = $value;
		}
		close(CFG);
	}
}

sub head {
	print "Content-type: text/html\n\n";
	print "<html><head><meta http-equiv=Content-Type content=\"$SYSMSG{'charset'}\">\n";
	print "<META HTTP-EQUIV=\"Pargma\" CONTENT=\"no-cache\">\n";
	print "<title>$PICCONF{'title'}</title>\n";
	print "<style>A { color: $PICCONF{'color'} }\n";
	print "A:hover { color: #ff0000 }</style>\n";
	print "<script>\n";
	print "function bgcolor(mycolor) {\n";
	print "mycolor = window.showModalDialog('/img/album/color.htm','color','dialogWidth=300px;dialogHeight=222px;center=yes;scrollbars=no;border=thin;help=no;status=no;maximize=no;minimize=no');\n";
	print "document.bgColor=mycolor;\n";
	print "document.body.background='/img/album/none.gif';\n}\n";
	print "function bgpic(picname) {\n";
	print "document.body.background=picname;\n}\n";
	print "</script></head>\n";
	print "<body text=\"$PICCONF{'color'}\" bgColor=\"$PICCONF{'bgcolor'}\" background=\"$PICCONF{'bgpic'}\" style=\"font-size: 9pt\">\n";
	print "<center><font size=+2 face=$SYSMSG{'variable_font'}>$PICCONF{'title'} </font><a href=/album-help.htm>$SYSMSG{'help'}</a>\n";
}

sub foot {
	print "</center><hr width=90% color=#6699cc>\n";
	print "<table width=90% border=0 align=center>\n";
	print "<td style=\"font-size: 9pt\" align=right><a href=# onclick=\"bgcolor();return false;\">更改背景色</a></td>\n";
	print "<tr><td><p align=center style=\"margin-top: 0; margin-bottom: 0\"><font size=-1>\n";
	print "<a href=\"/album.cgi?user=$user\"><img src=/img/album/menu.gif border=0>$SYSMSG{'backto_index'}</a>　\n";
	print "<a href=\"javascript:history.go(-1)\"><img src=/img/upfolder.gif border=0>$SYSMSG{'backto_prev_page'}</a>　\n";
	print "<a href=\"/gbook.cgi?user=$user\"><img border=0 src=/img/write2.gif align=absbottom >$SYSMSG{'gbook'}</a>　\n";
#	print "<a href=\"/album.cgi?user=$user&folder=$DATA{'folder'}&step=upload\"><img border=0 src=/img/upload.gif align=absbottom>$SYSMSG{'album_upload'}</a>　\n";
	print "<a href=\"/mail.cgi?user=$user\"><img border=0 src=/img/newmail.gif align=absbottom >$SYSMSG{'mail_to_owner'}</a>　</font></td></tr></table>\n"; 
	print "</BODY></HTML>\n";
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
	print "Content-type: text/html\n\n";
	print "<html><head><meta http-equiv=Content-Type content=\"$SYSMSG{'charset'}\">\n";
	print "<META HTTP-EQUIV=\"Pargma\" CONTENT=\"no-cache\">\n";
	print "<title>$SYSMSG{'title_system_info'}</title>\n";
	print "</head><body STYLE='font-size:9pt' bgcolor=#ddeeff><center><font size=6 face=$SYSMSG{'variable_font'} color=darkblue>$SYSMSG{'title_system_info'}</font></center>";
	print '<hr color="#FF0000" width=90%>';
	print "<br><center><table border=0 style=font-size:11pt><tr><td><p>$SYSMSG{'err_perm_set'}</p>\n";
	print $msg;
	print '<ul>';
	print "<li>$SYSMSG{'msg_please_check_perm'}";
	print "<li>$SYSMSG{'msg_contact_administrator'}";
	print '</ul>';
	print '<hr color="#6699cc" size=1>';
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

sub get_dir {
	my($mydir) = @_;
	my($line, @lines);
	if (! -d $album_root) {
		mkdir $album_root,'0755';
		chmod '0755',$album_root;
		chown $menu_id,$menu_gid,$album_root; 
	}
	$mydir =~ s/\.\.\///g;
	if ($mydir eq '/') {
		$mydir = '';
	} elsif ($mydir ne '' && $mydir !~ /^\/(\w+)/) {
		$mydir = "/$mydir";
	}
	opendir (DIR, "$album_root$mydir") || &err_disk("$SYSMSG{'err_cannot_open_album_folder'} $mydir<br>");
	@lines=readdir(DIR);
	close(DIR);
	%FOLDS = ();
	%FILES = ();
	%TYPE = ();
	%IMAGE = ();
	%FTIME = ();
	%FSIZE = ();
	%MODIFY = ();
	foreach $line (sort @lines) {
		if ($line !~ /^\.(\w+)/ && $line !~ /^_(\w+)/) {
			if (-d "$album_root$mydir/$line" && $line !~ /^_(\w+)/) {
				$FOLDS{$line} ++;
				$TYPE{$line} = 'DIR';
				$filemgr_rows ++;
			} elsif (-f _ && $line !~ /^tn_(\w+)/ && $line ne 'Thumbs.db' && $line ne 'message.htm') {
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
					$IMAGE{$line} = 'midi.gif';
					$TYPE{$line} = 'WAV';
				} elsif ($line =~ /.[M|m][P|p][G|g]$/) {
					$IMAGE{$line} = 'mpg.gif';
					$TYPE{$line} = 'MPG';
				} elsif ($line =~ /.[M|m][P|p][E|e][G|g]$/) {
					$IMAGE{$line} = 'mpg.gif';
					$TYPE{$line} = 'MPG';
				} elsif ($line =~ /.[W|w][M|m][V|v]$/) {
					$IMAGE{$line} = 'mpg.gif';
					$TYPE{$line} = 'WMV';
				} elsif ($line =~ /.[A|a][V|v][I|i]$/) {
					$IMAGE{$line} = 'mpg.gif';
					$TYPE{$line} = 'AVI';
				} elsif ($line =~ /.[A|a][U|u]$/) {
					$IMAGE{$line} = 'midi.gif';
					$TYPE{$line} = 'AU';
				} elsif ($line =~ /.[W|w][M|m][A|a]$/) {
					$IMAGE{$line} = 'midi.gif';
					$TYPE{$line} = 'WMA';
				} elsif ($line =~ /.[M|m][I|i][D|d][I|i]?$/) {
					$IMAGE{$line} = 'midi.gif';
					$TYPE{$line} = 'MID';
				} elsif ($line =~ /.[D|d][O|o][C|c|T|t]$/) {
					$IMAGE{$line} = 'word.gif';
					$TYPE{$line} = 'DOC';
				} elsif ($line =~ /.[P|p][P|p][T|t]$/) {
					$IMAGE{$line} = 'ppt.gif';
					$TYPE{$line} = 'PPT';
				} elsif ($line =~ /.[X|x][L|l].?$/) {
					$IMAGE{$line} = 'xls.gif';
					$TYPE{$line} = 'XLS';
				} elsif ($line =~ /.[M|m][D|d][B|b|A|a|W|w]?$/) {
					$IMAGE{$line} = 'mdb.gif';
					$TYPE{$line} = 'MDB';
				} elsif ($line =~ /.[S|s][B|b]2?$/) {
					$IMAGE{$line} = 'sb.gif';
					$TYPE{$line} = 'SB';
				} else {
					$IMAGE{$line} = 'other.gif';
					$TYPE{$line} = 'OTHER';
				}
			}
		}
		($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat("$album_root$mydir/$line");
		$FSIZE{$line} = int($size/1024);
		$FTIME{$line} = $mtime;
		$MODIFY{$line} = &get_date($mtime);
	}
	$mydir;
}

sub urlencode {
    my $s = shift;
    $s =~ s/ /+/g;
    return $s;
}

sub urldecode {
    my $s = shift;
    $s =~ s/\+/ /g;
    return $s;
}
#*****************************************************************************************
&read_conf;
&get_lang;
&check_referer;
&get_form_data;
$user = $DATA{'user'} if (defined($DATA{'user'}));
$home = (getpwnam($user))[7];
$menu_id = (getpwnam($user))[2];
$menu_gid = (getpwnam($user))[3];
&err_user if (!-d $home || int($menu_id) < 500 && int($menu_id) > 0);
&read_pic_conf("$home/$pic_conf");
$)=$menu_id;
$>=$menu_gid;
$album_root = "$home/public_html/$PICCONF{'folder'}";

if ($DATA{'step'} eq '') {
	$DATA{'folder'} = &get_dir($DATA{'folder'});
	@temp = split(/\//, $DATA{'folder'});
	if (scalar($temp) <= 1) {
		$uplevel = '/';
	} else {
		pop(@temp);
		$uplevel = join('/',@temp);
	}
	@temp = split(/\//, $DATA{'folder'});
	my $navi = "<a href=\"/album.cgi?user=$user\">目錄</a>";
	my $temp = "";
	foreach $subdir (@temp) {
		next if ($subdir eq '');
		$temp .= "/$subdir";
		$navi .= " / <a href=\"/album.cgi?user=$user&folder=$temp\">$subdir</a>";
	}
	&read_pic_msg;
	&head;
	print "$PICCONF{'message'}\n";
	print "<table width=90% border=0 align=center><tr><td>\n";
	print "<font size=-1><p align=center style=\"margin-top: 10; margin-bottom: 0\">目前所在位置：$navi\n";
#	print "&nbsp;　喜歡的話按右鍵另存目標就可以將檔案下載回去哦!背景圖請用另存圖片</font>\n";
	print "<hr color=#6699cc size=1><table border=0 align=center><tr>\n";
#	print "<td style=\"font-size: 9pt\"><a href=# onclick=\"bgcolor();return false;\">更改背景色</a></td>\n";
	print "</tr></table>\n";
	print "</td></tr></table>\n";
	print "<center><table border=0><tr>\n";
	$i=0;
	foreach $file (sort keys %FOLDS) {
		next if ($file eq '.');
		next if ($file eq '..');
		next if ($file =~ /^_.*$/);
		$newtip = '<br>';
		$newtip = '<img src=/img/album/new.gif><br>' if ($FTIME{$file} >= time-604800);
		$i++;
#		print "<td style='font-size:9pt' align=center width=75><a href=\"/album?user=$user&folder=$DATA{'folder'}/$file\" onmouseover=\"document.all['".$file."'].src='img/album/folder2.gif';\" onmouseout=\"document.all['".$file."'].src='img/album/folder1.gif';\"><img id=\"$file\" src=\"img/album/folder1.gif\" border=0><br>$file</a>";
		print "<td style='font-size:9pt' align=center width=75><a href=\"/album?user=$user&folder=$DATA{'folder'}/$file\"><img src=\"img/album/folder2.gif\" border=0><br>$file</a>";
		print "<br>$MODIFY{$file}" if ($PICCONF{'showdate'} eq 'yes');
		print "<br>$newtip" if ($PICCONF{'newtip'} eq 'yes');
		print "</td>\n";
		print "</tr><tr>\n" if ($i%8 eq 0);
	}
	print "</tr></table><table border=0><tr>\n";
	$i=0;
	$PICCONF{'number'}=7 if ($PICCONF{'number'}<=0);
	foreach $file (sort keys %FILES) {
		next if ($file =~ /^_.*$/);
		$newtip = '<br>';
		$newtip = '<img src=/img/album/new.gif><br>' if ($FTIME{$file} >= time-604800);
		$i++;
		if ($DATA{'folder'} eq '' || $DATA{'folder'} eq '/') {
			$pic = "$album_root/$file";
			$tnpic = "$album_root/tn_$file";
			$tnpic_url = urlencode("showpic/tn_$file?user=$user&path=/$PICCONF{'folder'}/tn_$file");
			$pic_url = urlencode("showpic/$file?user=$user&path=/$PICCONF{'folder'}/$file");
		} else {
			$pic = "$album_root/$DATA{'folder'}/$file";
			$tnpic = "$album_root/$DATA{'folder'}/tn_$file";
			$tnpic_url = urlencode("showpic/tn_$file?user=$user&path=/$PICCONF{'folder'}$DATA{'folder'}/tn_$file");
			$pic_url = urlencode("showpic/$file?user=$user&path=/$PICCONF{'folder'}$DATA{'folder'}/$file");
		}
		if ($TYPE{$file} eq 'GIF' || $TYPE{$file} eq 'JPG' || $TYPE{$file} eq 'PNG' || $TYPE{$file} eq 'BMP') {
			$showpic_url = $pic_url;
			if ($FSIZE{$file} >= 10 && $TYPE{$file} eq 'JPG') {
				system("jpegtopnm '$pic' | pamscale -xsize 75 | pnmtojpeg > '$tnpic'") if (! -e "$tnpic");
			} elsif ($FSIZE{$file} >= 10 && $TYPE{$file} eq 'PNG') {
				system("pngtopnm '$pic' | pamscale -xsize 75 | pnmtopng > '$tnpic'") if (! -e "$tnpic");
			} elsif ($FSIZE{$file} >= 10 && $TYPE{$file} eq 'BMP') {
				system("bmptopnm '$pic' | pamscale -xsize 75 | pnmtobmp > '$tnpic'") if (! -e "$tnpic");
			} elsif ($FSIZE{$file} >= 10 && $TYPE{$file} eq 'BMP') {
				system("giftopnm '$pic' | pamscale -xsize 75 | pnmtogif > '$tnpic'") if (! -e "$tnpic");
			}
			$showpic_url=$tnpic_url if (-e "$tnpic");
			if ($PICCONF{'background'} eq '1') {
				if (!defined($PICCONF{'width'}) && !defined($PICCONF{'height'})) {
					print "<td style='font-size:9pt' align=center width=75><a href=javascript:bgpic('".$pic_url."')><img src=\"$showpic_url\" border=0><br>$file</a>";
				} elsif (defined($PICCONF{'width'}) && !defined($PICCONF{'height'})) {
					print "<td style='font-size:9pt' align=center width=75><a href=javascript:bgpic('".$pic_url."')><img src=\"$showpic_url\" border=0 width=$PICCONF{'width'}><br>$file</a>";  
				} elsif (!defined($PICCONF{'width'}) && defined($PICCONF{'height'})) {
					print "<td style='font-size:9pt' align=center width=75><a href=javascript:bgpic('".$pic_url."')><img src=\"$showpic_url\" border=0 height=$PICCONF{'height'}><br>$file</a>";  
				} else {
					print "<td style='font-size:9pt' align=center width=75><a href=javascript:bgpic('".$pic_url."')><img src=\"$showpic_url\" border=0 width=$PICCONF{'width'} height=$PICCONF{'height'}><br>$file</a>";  
				}
			} else {
				if (!defined($PICCONF{'width'}) && !defined($PICCONF{'height'})) {
					print "<td style='font-size:9pt' align=center width=75><a href=\"$pic_url\" target=_blank><img src=\"$showpic_url\" border=0><br>$file</a>";
				} elsif (defined($PICCONF{'width'}) && !defined($PICCONF{'height'})) {
					print "<td style='font-size:9pt' align=center width=75><a href=\"$pic_url\" target=_blank><img src=\"$showpic_url\" border=0 width=$PICCONF{'width'}><br>$file</a>";  
				} elsif (!defined($PICCONF{'width'}) && defined($PICCONF{'height'})) {
					print "<td style='font-size:9pt' align=center width=75><a href=\"$pic_url\" target=_blank><img src=\"$showpic_url\" border=0 height=$PICCONF{'height'}><br>$file</a>";  
				} else {
					print "<td style='font-size:9pt' align=center width=75><a href=\"$pic_url\" target=_blank><img src=\"$showpic_url\" border=0 width=$PICCONF{'width'} height=$PICCONF{'height'}><br>$file</a>";  
				}
			}
		} else {
			if ($TYPE{$file} eq 'SB') {
				$pic_url = "showscratch?user=$user&path=/$PICCONF{'folder'}$DATA{'folder'}/$file";
			}
			print "<td style='font-size:9pt' align=center width=75><a href=\"$pic_url\"><img src=\"/img/album/$IMAGE{$file}\" border=0><br>$file</a>"; 
		}
		print "<br>$MODIFY{$file}" if ($PICCONF{'showdate'} eq 'yes');
		print "<br>$FSIZE{$file}k" if ($PICCONF{'showsize'} eq 'yes');
		print "<br>$newtip" if ($PICCONF{'newtip'} eq 'yes');
		print "</td>\n";
		print "</tr><tr>\n" if ($i%$PICCONF{'number'} eq 0);
	}
	print "</tr></table>\n";
	&foot;
} elsif ($DATA{'step'} eq 'upload') {
	$mydir = $DATA{'folder'};
	if ($mydir eq '/') {
		$mydir = '';
	} elsif ($mydir ne '' && $mydir !~ /^\/(\w+)/) {
		$mydir = "/$mydir";
	}
	&head;
	print "<center><p><font color=red size=4><b>$SYSMSG{'filemgr_upload_where'} </b></font><img align=absmiddle src=/img/0folder.gif><font color=blue size=4><b> $album_root$mydir</b></font><font color=red size=4><b> $SYSMSG{'folder'}</b></font>\n";
	print "<form name=myform ENCTYPE=\"multipart/form-data\" method=post action=/upload.cgi>\n";
	print "<input type=hidden name=user value=\"$user\">\n";
	print "<input type=hidden name=myfolder value=\"$album_root$mydir\">\n";
	print "<input type=hidden name=prog value=\"/album.cgi?user=$user&folder=$DATA{'folder'}\">\n";
	for ($z=1;$z<6;++$z) { print "<img align=absmiddle src=/img/upload.gif border=0>$SYSMSG{'file'}$z： <input type=file name=\"upload_file\"><br>\n"; }
	print "<input type=submit value=\"$SYSMSG{'filemgr_upload_confirm'}\">\n";
	print "</form></center></tr>";
	&foot;
}
