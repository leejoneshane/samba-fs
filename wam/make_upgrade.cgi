#!/usr/bin/perl -U
chop($src = `pwd`);
$temp = "/wam";
$des = "/usr/libexec/wam/patch";
$zip_test = `whereis zip`;
$zip_exist = 0;
$zip_exist = 1 if ($zip_test =~ /^zip: .+/);

open(VERSION, "version") || return 0;
chop($myver = <VERSION>);
close(VERSION);

system("mkdir -p $temp/img");
system("cp -f $src/* $temp > /dev/null");
system("rm -rf $temp/logon.cgi > /dev/null");
system("rm -rf $temp/list_copy.cgi > /dev/null");
system("rm -rf $temp/*.new > /dev/null");
system("mv $temp/wam.conf $temp/wam.new > /dev/null");
system("rm -rf $temp/*.conf > /dev/null");
system("rm -rf $temp/*.temp > /dev/null");
system("cp -Rf $src/img/* $temp/img > /dev/null");
system("rm -rf $temp/img/wam.gif > /dev/null");
system("mkdir -p $temp/help");
system("cp -Rf $src/help/* $temp/help > /dev/null");
system("mkdir -p $temp/lang");
system("cp -Rf $src/lang/* $temp/lang > /dev/null");
if ($zip_exist) {
	system("zip -rq $des/wam-$myver-upgrade.zip $temp > /dev/null");
}
system("tar -zcf $des/wam-$myver-upgrade\.tar\.gz $temp > /dev/null");
system("rm -rf $temp");
