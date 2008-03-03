#!perl -w
#
# Sys::Manage::Schedule - Scriptic schedule trunk
#
# makarow, 2005-09-15
#
# !!! see in source code
# ??? qclad(@_) inside 'cmdfck'?
# !!! 'soon' multiplatform
# !!! 'chpswd' may fail?
#	Platform SDK: Directory Services: Changing the Password on a Service's User Account
# ??? '-surun' may be interrupted by system down or another -surun
#

package Sys::Manage::Schedule;
require 5.000;
use strict;
use Carp;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
$VERSION = '0.59';

1;


#######################


sub new {		# Create new object
 my $c=shift;		# ( ? [command line], ? -option=>value,...)	-> self
 my $s ={};
 bless $s,$c;
 $s =$s->initialize(@_);
 $s
}


sub initialize {	# Initialize newly created object
 my $s =shift;		# ( ? [command line], ? -option=>value,...)	-> self
 %$s =(  ''		=>undef
	,-dirm		=>do{$0 =~/([\\\/])/	# directory marker
			? $1
			: $^O eq 'MSWin32'
			? '\\'
			: '/'}
	,-dirb		=>do {			# directory base
			my $v =$^O eq 'MSWin32' ? scalar(Win32::GetFullPathName($0)) ||$0 : $0;
			$v !~/[\\\/]/
			? (-d './var' ? '.' : -d '../var' ? '..' : '.')
			: $v =~/(?:[\\\/]bin){0,1}[\\\/][^\\\/]+$/i
			? $`
			: '.'}
	,-dirv		=>''			# directory for vars & logs, below
	,-logmax	=>1024*1024*2		# log file size
	,-logpid	=>1			# log pid file switch / name
	,-prgfn		=>do{$^O eq 'MSWin32'	# program full name
			? scalar(Win32::GetFullPathName($0)) ||$0
			: $0}
	,-prgsn		=>do{$0 =~/([^\\\/]+)$/	# program short name
			? $1
			: $0}
	,-prgcn		=>do{			# program common name
			$0 =~/([^\\\/]+?)(?:\.\w+){0,1}$/
			? $1
			: $0}
	,-w32at		=>$^O eq 'MSWin32'	# is win32 (internally)
	#-w32svco	=>undef			# win32 service obj (internally)
	#-susr		=>''			# su user
	#-spsw		=>''			# su password
	,-n0		=>22			# night begin hour
	,-n1		=>0			# night middle hour
	,-n2		=>4			# night end hour
	,-d0		=>8			# day begin hour
	,-d1		=>12			# day middle hour
	,-d2		=>19			# day end hour
	,-time		=>time()		# start time
	,-timel		=>undef			# start localtime
	,-runmod	=>''		# ...	# runnimg mode: -run, -runsu, -set,...
	,-runarg	=>''		# ...	# schedule args escaped
	,-atopt		=>''			# at options saved (internally)
	#-atarg		=>undef			# at first cmd (internally)
	#-crontab	=>undef			# crontab entries (internally)
	#-wrlck		=>undef			# lock file
	#-wrlcs		=>''			# lock file additional
	#-wrlog		=>undef			# writing logfile redirected
	#-wrout		=>undef			#	old stdout
	#-wrerr		=>undef			#	old stderr
	#-cmdfile	=>undef			# 'cmdfile' object
	, %$s
	);
 $s->{-timel} =localtime($s->{-time});
 $s->set(@_);
 $s
}


sub class {
 substr($_[0], 0, index($_[0],'='))
}


sub daemonize {		# Daemonize process
 my $s =$_[0];
 my $null =$^O eq 'MSWin32' ? 'nul' : '/dev/null';
 open(STDIN,  "$null")  || return($s->echologdie("daemonize(STDIN) -> $!")); 
 open(STDOUT,">$null")  || return($s->echologdie("daemonize(STDOUT) -> $!"));
 eval("use POSIX 'setsid'; setsid()");
 open(STDERR,'>&STDOUT')|| return($s->echologdie("daemonize(STDERR) -> $!"));
 $s
}


sub DESTROY {
 my $s =$_[0];
 if($s->{-crontab}) {
	$s->vfwrite('>crontab.txt',@{$s->{-crontab}});
	$s->run('crontab',$s->vfname('crontab.txt'));
 }

 if ($s->{-logpid} && (length($s->{-logpid}) >1)) {
	if (!unlink($s->{-logpid})) {
		$s->echolog(join(' ', map {$_ ? ($_) : ()} 'unlink',$s->{-logpid},$!,$^E));
	}
	eval{$s->logrdr(undef)} if $s->{-wrlog};
 }
 $s
}


sub set {               # Get/set slots of object
			# ()		-> options
			# (-option)	-> value
			# ( ? [command line], ? -option=>value,...)	-> self
 return(keys(%{$_[0]}))	if (@_ <2);
 return($_[0]->{$_[1]})	if (@_ <3) && !ref($_[1]);
 my($s, $arg, %opt) =ref($_[1]) ? @_ : ($_[0],undef,@_[1..$#_]);
 if ($arg) {
	$opt{-runmod} =$arg->[0] || '-set';
	$opt{-runarg} =$arg->[1] || '0';
 }
 foreach my $k (keys(%opt)) {
	$s->{$k} =$opt{$k};
 }
 $s
}



sub max {		# Max number
 (($_[1]||0) >($_[2]||0) ? $_[1] : $_[2])||0
}


sub strtime {		# Log time formatter
	my @t =localtime();
	 join('-', $t[5]+1900, map {length($_)<2 ? "0$_" : $_} $t[4]+1,$t[3]) 
	.' ' 
	.join(':', map {length($_)<2 ? "0$_" : $_} $t[2],$t[1],$t[0])
}


sub hostname {		# This host name
 no warnings; 
 eval('use Sys::Hostname(); Sys::Hostname::hostname')
}


sub hostnode {		# This host node name
 $^O eq 'MSWin32'
 ? Win32::NodeName()
 : $_[0]->hostname(@_[1..$#_]) =~/^([^\.]+)/
 ? $1
 : $_[0]->hostname(@_[1..$#_])
}


sub hostdomain {	# This host domain
 no warnings;
 my $h =$_[0]->hostname(@_[1..$#_]);
 $h =~/^[^\.]*\.(.+)$/
	? $1
	: eval('use Net::Domain(); Net::Domain::hostdomain')
}


sub qclad {		# Quote command line arg(s) on demand
	map {	!defined($_) || ($_ eq '')
		? '""'
		: /[&<>\[\]{}^=;!'+,`~\s%"?*|()]/	# ??? see shell
		? do {	my $v =$_; 
			$v =~s/"/\\"/g;			# ??? perl specific
			$v =~s/\\$/\\\\/;  
			'"' .$v .'"' }
		: $_ } @_[1..$#_]
}


sub printflush {	# Print STDOUT with autoflush
 my $s =$_[0];		# (print args) -> print result
 my @f =(select(), do{select(STDERR); $|}, do{select(STDOUT); $|});
 select(STDERR); $|=1;
 select(STDOUT); $|=1;
 my $r =print(@_[1..$#_]);
 select(STDERR); $|=$f[1];
 select(STDOUT); $|=$f[2];
 select($f[0]);
 $r
}


sub echolog {		# Echo + log
 my $s=shift;		# (message)
 $s->printflush(@_,"\n");
 $s->{-wrlog} && $s->{-wrlog}->print($s->strtime(),' ',@_,"\n") 
	&& $s->{-wrlog}->flush();
}


sub echologdie {	# Echo + log + die
 my $s=shift;		# (message)
 $s->{-wrlog} && $s->{-wrlog}->print($s->strtime(),' ',@_,"\n") 
	&& $s->{-wrlog}->flush();
 croak(join('',@_) ."\n")
}


sub echologwarn {	# Echo + log + die
 my $s=shift;		# (message)
 $s->{-wrlog} && $s->{-wrlog}->print($s->strtime(),' ',@_,"\n") 
	&& $s->{-wrlog}->flush();
 carp(join('',@_) ."\n")
}


sub flush {		# Flush STDOUT/STDERR
 eval('use IO::File; STDOUT->flush(); STDERR->flush()')
}


sub fopen {		# File open
 my ($s,$f) =@_;	# (file name) -> file handle
 eval('use IO::File');
 IO::File->new($f) || $s->echologdie("Error '$!' (fopen,'$f')");
}


sub copen {		# Command output open
 my $s =$_[0];		# (handle var, command,...) -> pid
 my $p;
 if (0) {
	$_[1] =eval('use IO::File; IO::File->new()');
	$p =open($_[1], '-|', join(' ', @_[2..$#_]) .' 2>>&1');
 }
 else {
	eval('use IPC::Open3');
	my $x;
	$p =eval{IPC::Open3::open3($x, $_[1], $_[1], @_[2..$#_])};
	eval{fileno($x) && close($x)};
 }
 $p
}


sub fwrite {		# File write
			# (file name, strings)
 my $fn =$_[1] =~/^[+<>]/ ? $_[1] : ('>' .$_[1]);
 my $fh =$_[0]->fopen($fn);
 my $r =$fh->print(map {/[\r\n]$/ ? $_ : "$_\n";
	} @_[2..$#_]);
 $fh->close();
 $r;
}



sub fread {		# Load file
 my $s =$_[0];		# (filename) -> content
 my $f0=$_[1];
 my $fn=$_[1] =~/^[+<>]/ ? $_[1] : ('<' .$_[1]);
 my $fh =$_[0]->fopen($fn);
 my $b =undef;
 my $r =$fh->read($b,-s $f0);
 eval{$fh->close()};
 defined($r) ? $b : $s->echologdie("Error '$!' (fread,'$fn')")
}


sub fload {		# Load file
	fread(@_)
}


sub ftruncate {		# File truncate
 my ($s, $f) =@_;	# (filename)
 my $max =$s->{-logmax}; # ~1024*1024
 return(1) if !$max;
 my $frm =1024*4;
 my $fsz =(-s $f)||0;
 return(1) if $fsz <=$max;
 my $ftw =$f =~/\.([^.\\\/]+)/ ? ($` .'.tmp') : ($f .'.tmp');
 if (1) {
	my $f0 =eval{$s->fopen("<$f")}   ||return(undef);
	my $f1 =eval{$s->fopen(">$ftw")} ||return(undef);
	my $cnt=0;
	my $row='';
	while ( (  ($cnt <$frm)
		 ||($fsz -$cnt >$max))
		&& defined($row=readline($f0))) {
		$cnt +=length($row);
	}
	while (defined($row=readline($f0))) {
		$f1->print($row);
	}
	$f0->close(); $f1->close();
	rename($ftw, $f) || return(undef);
 }
 2;
}



sub vfname {		# Var file name (in variables directory)
    !$_[1]		# (abbreviate) -> full file name
  ? $_[0]->{-dirv} .$_[0]->{-dirm}
  : $_[1] =~/^([+<>]+)(.+)/
  ? $1 .$_[0]->{-dirv} .$_[0]->{-dirm} .$_[0]->{-prgcn} .'-' .$2
  : $_[0]->{-dirv} .$_[0]->{-dirm} .$_[0]->{-prgcn} .'-' .$_[1]
}


sub vfopen {		# Var file open
 $_[0]->fopen(		# (abbreviate) -> file handle
	$_[0]->vfname($_[1]||'>>log.txt'))
}


sub vfwrite {		# Var file write
			# (abbreviate, strings)
  $_[0]->fwrite($_[0]->vfname($_[1]), @_[2..$#_])
}


sub vftruncate {	# Var file truncate
			# (abbreviate)
	$_[0]->ftruncate($_[0]->vfname($_[1]))
}



sub logrdr {	# Log output redirector
 my $s =$_[0];	# (on)		-> -wrout (output saved)
		# ()		-> -wrout
		# (off)		-> -wrlog (log opened)
		# (undef)	->  undef
 if (!$#_) {
	return($s->{-wrout})
 }
 elsif ($_[1] && !$s->{-wrout}) {
	$s->flush();
	$s->{-wrlog} =$s->vfopen('>>log.txt') if !$s->{-wrlog};
	$s->{-wrout} =eval('use IO::File; IO::File->new(">&STDOUT")');
	$s->{-wrerr} =eval('use IO::File; IO::File->new(">&STDERR")');
	open(STDERR, '>&STDOUT');
	open(STDOUT, '>&' .$s->{-wrlog}->fileno());
	return($s->{-wrout})
 }
 elsif (!$_[1] && $s->{-wrout}) {
	$s->flush();
	open(STDOUT, '>&' .$s->{-wrout}->fileno());
	open(STDERR, '>&' .$s->{-wrerr}->fileno());
	$s->{-wrout}->close();	$s->{-wrerr}->close();
	delete $s->{-wrout};	delete $s->{-wrerr};
 }
 elsif (!$_[1] && defined($_[1]) && !$s->{-wrlog}) {
	$s->{-wrlog} =$s->vfopen('>>log.txt')
 }
 if (!defined($_[1]) && $s->{-wrlog}) {
	$s->{-wrlog}->close();	delete $s->{-wrlog}
 }
 $s->{-wrlog}
}


sub loglck {	# Lock operation
 my ($s,$l,$t) =@_;	# (true|false|undef, ?nonblock) -> success
 $t =($t ? '| LOCK_NB' : '');
 $s->{-wrlck} =$s->vfopen('>lck.txt') if !$s->{-wrlck};
 my $r =flock($s->{-wrlck}
		, !$l	
		? eval("use Fcntl qw(:flock); LOCK_UN $t")
		: $l >1
		? eval("use Fcntl qw(:flock); LOCK_EX $t")
		: eval("use Fcntl qw(:flock); LOCK_SH $t"));
 if ($#_ && !defined($l)) {
	$s->{-wrlck}->close() if $s->{-wrlck};
	delete $s->{-wrlck};
 }
 $r;
}


sub loglcs {	# Lock operation for su / soon
 my ($s,$l,$t) =@_;	# (true|false|undef, ?nonblock) -> success
 $t =($t ? '| LOCK_NB' : '');
 $s->{-wrlcs} =$s->vfopen('>lcs.txt') if !$s->{-wrlcs};
 my $r =flock($s->{-wrlcs}
		, !$l	
		? eval("use Fcntl qw(:flock); LOCK_UN $t")
		: $l >1
		? eval("use Fcntl qw(:flock); LOCK_EX $t")
		: eval("use Fcntl qw(:flock); LOCK_SH $t"));
 if ($#_ && !defined($l)) {
	$s->{-wrlcs}->close() if $s->{-wrlcs};
	delete $s->{-wrlcs};
 }
 $r;
}


sub atesc {	# Escape 'at' options
 my $v =ref($_[1]) ? join(' ', @{$_[1]}) : join(' ',@_[1..$#_]);
 $v =~s/([^-\d\w:,\/\s])/sprintf("\\%02x",ord($1))/eg;
 $v =~s/([\s])/_/g;
 $v
}


sub atarg {	# Repeat 'at' options in subsequent entry using first
 my $s =$_[0];	# (at entry) -> (at entry filled)
 $s->{-atarg}
 ? (map {  !defined($_[$_+1]) ||($_[$_+1] eq '')
	? $s->{-atarg}->[$_]
	: $_[$_+1]
	} (0..max($s,$#{$s->{-atarg}},$#_-1)))
 : (@_[1..$#_])
}


sub run {	# Start OS command
 my $s =$_[0];	# (command) -> !exit code
 $!=$^E=0;
 $s->printflush(join(' ',@_[1..$#_]),"\n");
 my $r =system(@_[1..$#_]);
 $s->printflush("Error '$!'\n") if $r <0;
 ($r >=0) && !($?>>8)
}


sub runopen {	# Open OS command as filehandle
 my $s =$_[0];	# (command) -> file handle
 $s->printflush(join(' ',@_[1..$#_]),"\n");
 my $h;
 $!=$^E=0;
 $s->{-runopen} =$s->copen($h, @_[1..$#_]);
 $s->{-runopen} && $h;
}


sub runlist {	# List OS command as an array
 my $s =$_[0];	# (command) -> strings list
 my $h =runopen(@_);
 my @r =map {(/[\r\n]*$/ ? $` : $_)} <$h>;
 waitpid($s->{-runopen},0);
#$s->flush();
 @r
}


sub runlcl {	# Log os command line
 my $s =shift;	# (command) -> success
 $s->loglck(1);
 $s->logrdr(0) if !$s->{-wrlog};
 $s->echolog(join(' ',@_));
 my $r  =system(@_);
 if ($r <0) {
	$s->{-wrlog}->print($s->strtime(), " Error '$!' (", join(' ',@_) ,")\n");
 }
 else {
	$s->{-wrlog}->print($s->strtime(), ' Exit ',($?>>8),' (', join(' ',@_), ")\n");
 }
 $s->{-wrlog}->flush();
 $s->loglck(0);
 ($r >=0) && !($?>>8)
}


sub runlog {	# Log os command execution
 my $s =shift;	# (command) -> success
 $s->loglck(1);  
 $s->logrdr(0) if !$s->{-wrlog};
 $s->echolog(join(' ',@_));
 $!=$^E=0;
 my $hi;
 my $pid =$s->copen($hi, @_);
 if ($pid) {
	$s->{-wrlog}->print($s->strtime(), ' $$', $pid, ' (', join(' ',@_), ")\n");
	$s->{-wrlog}->flush();
	my $r =undef;
	while(defined($r=readline($hi))) {
		$r = $` if $r =~/[\r\n]*$/;
		print($r, "\n");
		$s->{-wrlog}->print($r, "\n");
	}
	$hi && close($hi);
	waitpid($pid,0);
	$s->{-wrlog}->print($s->strtime(), ' Exit ', ($?>>8),' (', join(' ',@_), ")\n");
	$s->{-wrlog}->flush();
	$s->loglck(0);
	return !($?>>8)
 }
 else { 
	my @e =($!, $^E);
	$hi && close($hi);
	($!, $^E) =@e;
	$s->{-wrlog}->print($s->strtime(), " Error '$!' (", join(' ',@_), ")\n");
	$s->{-wrlog}->flush();
	$s->loglck(0);
	return(undef)
 }
}


sub cmdfile {	# Shift command file
 $_[0]->{-cmdfile} =eval('use Sys::Manage::CmdFile; Sys::Manage::CmdFile->new()')
	if !$_[0]->{-cmdfile};
 my $r =$_[0]->{-cmdfile}->dofile(@_[1..$#_]);
 if ($_[0]->{-cmdfile}->{-retexc}) {
	$_[0]->loglck(1);
	$_[0]->logrdr(0) if !$_[0]->{-wrlog};
	$_[0]->echolog('cmdfile',$_[0]->{-cmdfile}->{-retexc});
	$_[0]->{-wrlog}->flush();
	$_[0]->loglck(0);
 }
 $r	
}


sub cmdfck {	# Check command file
 $_[0]->{-cmdfile} =eval('use Sys::Manage::CmdFile; Sys::Manage::CmdFile->new()')
	if !$_[0]->{-cmdfile};
 my $r =$_[0]->{-cmdfile}->dofck(@_[1..$#_]);
 if ($_[0]->{-cmdfile}->{-retexc}) {
	$_[0]->loglck(1);
	$_[0]->logrdr(0) if !$_[0]->{-wrlog};
	$_[0]->echolog('cmdfile',$_[0]->{-cmdfile}->{-retexc});
	$_[0]->{-wrlog}->flush();
	$_[0]->loglck(0);
 }
 $r
}


sub w32oleerr {	# Win32 OLE error message
	(Win32::OLE->LastError()||'undef') 
	.' ' 
	.(Win32::OLE->LastError() && Win32::FormatMessage(Win32::OLE->LastError()) ||'undef');
}


sub w32svcr {	# Win32 services registry
		# (... ) -> registry
 no warnings;
 eval('use Win32::TieRegistry');
 $Win32::TieRegistry::Registry->{"LMachine\\System\\CurrentControlSet\\Services" .($_[1] ? '\\' .$_[1] : '')}
}


sub w32svco {	# Win32 service object
 my $s=$_[0];	# () -> object | (stop|start) -> success
 my $n=$s->{-prgsn};
 my $m=1;	# 0 net use, 1 wmi, 2 adsi
 local $^W=undef;
 my $o =$s->{-w32svco} =$s->{-w32svco} || 
	(!$m
	? undef
	: $m ==1
	? (eval('use Win32::OLE; 1') && Win32::OLE->GetObject("winmgmts:Win32_Service.Name='$n'"))
	: (eval('use Win32::OLE; 1') && Win32::OLE->GetObject('WinNT://' .Win32::NodeName() .'/' .$n .',Service')));
 return($o) if !$#_;
 my $r;
 $@ =undef;
 if (!$m) {
	$r =$s->run('net', ($_[1] ? 'start' : 'stop'), $n);
	$@ ='exit ' .($?>>8) if !$r;
 }
 elsif ($m ==1) {
	$r =$_[1] ? $o->StartService() : $o->StopService();
	$@ ='wmi ' .$r if $r;
	$r =$r ? 0 : 1;
	sleep(1) if $_[1] && $r;		# $o->{Started} -> false always!
 }
 elsif ($m ==2) {
	$r =$_[1] ? $o->Start() : $o->Stop();	# fails sometimes
	$@ ='adsi ' .$r if $r;
	$r =$r ? 0 : 1;
	sleep(1) if $_[1] && $r;		# $o->{Status} -> 8(ADS_SERVICE_ERROR)?
 }
 $r
}


sub startup {	# Start schedule execution (internal)
 my $s=$_[0];	# () -> self
 $s->{''} =1;
 $s->{-dirv} = -d ($s->{-dirb} .$s->{-dirm} .'var')
		? ($s->{-dirb} .$s->{-dirm} .'var')
		: ($s->{-dirb} .$s->{-dirm} .$s->{-prgcn})
	if !$s->{-dirv};
 if ($s->{-runmod} =~/^-set/) {			# clean schedule existed
	$s->printflush($s->class(), " Scheduling '", $s->{-prgsn}, "'\n");
	mkdir($s->{-dirv},0777) if !-e $s->{-dirv};
	if ($s->{-w32at}) {
		my $qs =$s->{-prgfn};
		my @at =split /\s*\r*\n\r*/, `at`;
		foreach my $r (@at) {
			next if $r !~/\b\Q$qs\E\b/;
			my $i =($r =~/^[^\d]*(\d+)/ ? $1 : undef);
			next if !$i;
			$s->run('at', $i, '/d', '/y');
		}
	}
	else {
		my $qs =$s->{-prgfn};
		$s->{-crontab} =
			[map {	/\b\Q$qs\E\b/ ? () : ($_)
				} split /\s*\r*\n\r*/, `crontab -l`];
		$s->vfwrite('>crontab.txt',@{$s->{-crontab}});
		$s->run('crontab',$s->vfname('crontab.txt'));
	}
	exit(0) if $s->{-runmod} =~/^-setdel/;	# delete settings
 }
 elsif ($s->{-runmod} eq '-svcinst') {		# install service
	croak("Error: Win32 only function") if $^O ne 'MSWin32';
	my $n =$s->{-prgsn};
	$s->printflush($s->class(), " Installing Windows Service '$n'...\n");
	my $p ='';
	foreach my $d (split /\s*\;\s*/, $ENV{PATH}) {
		next if !-e "$d\\srvany.exe";
		$p =$d; last;
	}
	if (!$p) {
		$s->printflush("Not found ResKip 'srvany.exe' in path, exit.\n");
		exit(1);
	}
	$s->run('instsrv',$n,"$p\\srvany.exe");
	$s->w32svcr()->{$n}
		={'Parameters' =>{
			 'Application'=>$^X
			,'AppParameters'=>'-e"$SIG{CHLD}=\'IGNORE\';system(1,$^X,@ARGV)" '
						.$s->{-prgfn} .' -runsu 0'
			,'AppDirectory'=>$s->{-dirb}
		}};
	$s->run('sc','config',$n
		,'type=', 'own'
		,'start=', 'auto'
		,($ARGV[1] ? ('obj=', $ARGV[1]) : ())
		,($ARGV[2] ? ('password=', $ARGV[2]) : ())
		);
	$s->printflush("\nCheck '$n' service 'Startup type' and 'Log on'!\n");
	exit(0);
 }
 elsif ($s->{-runmod} eq '-svcdel') {		# remove service
	croak("Error: Win32 only function") if $^O ne 'MSWin32';
	my $n =$s->{-prgsn};
	$s->printflush($s->class(), " Removing Windows Service '$n'...\n");
	$s->run('instsrv',$n,"Remove");
	exit(0);
 }
 elsif ($s->{-runmod} eq '-surun') {		# start switched user and exit
	if ($^O eq 'MSWin32') {
		if ($s->{-susr} && $s->{-spsw}) {
			$s->printflush('[',$s->{-prgfn},'] -surun:wmi, ',($s->{-runarg}||0), ', $$', $$,"...\n");
			local $^W=undef;
			eval('use Win32::OLE');
			my $wmi =Win32::OLE->new('WbemScripting.SWbemLocator');
			$wmi =$wmi->ConnectServer(Win32::NodeName(),'root\\cimv2',$s->{-susr},$s->{-spsw})
				|| croak 'Error(WMI->ConnectServer): ' .$s->w32oleerr();
				# !!! OLE exception from "SWbemLocator": User credentials cannot be used for local connections
			$wmi->{Security_}->{ImpersonationLevel}=3; # 4-delegate, 3-impersonate;
			my $mih =$wmi->Get('Win32_Process')
				|| croak 'Error(WMI->Win32_Process): ' .$s->w32oleerr();
			$mih->Create(join(' '
					,$^X,$s->{-prgfn},'-runsu'
					,$s->{-runarg}||0
					), undef,undef,$wmi)
				&& croak 'Error(WMI->Create): ' .$s->w32oleerr();
		}
		else {
			my $n =$s->{-prgsn};
			$s->printflush('[',$s->{-prgfn},'] -surun, ',($s->{-runarg}||0), ', $$', $$,"...\n");
			$s->logrdr(0) if !$s->{-wrlog};
			$s->{-wrlog}->print("\n", $s->strtime(), ' [', $s->{-prgsn},'] -surun, ',($s->{-runarg}||0), ', $$', $$,"\n");
			$s->{-wrlog}->flush();
			$s->loglcs(2);
			$s->w32svco(0);
			$s->w32svcr("$n\\Parameters")->{AppParameters}
				='-e"$SIG{CHLD}=\'IGNORE\';system(1,$^X,@ARGV)" '
				.$s->{-prgfn} .' -runsu ' .($s->{-runarg}||0);
			$s->w32svco(1);
			$s->{-wrlog}->print("Error '$@' (w32svco,1)\n")
				if $@;
			# !!! service startup may be continues, interrupted
			# $s->w32svcr("$n\\Parameters")->{AppParameters}
			#	='-e"$SIG{CHLD}=\'IGNORE\';system(1,$^X,@ARGV)" '
			#	.$s->{-prgfn} .' -runsu 0';
			$s->loglcs(0);
		}
		exit(0);
	}
	else {
		if ($s->{-susr} && !$s->{-spsw}) {
			$SIG{CHLD}='IGNORE';
			($>||0) ==0
			? $s->run(1
				,(-e '/bin/su' ? '/bin/su' : 'su')
				,$s->{-susr}
				,'-c','"' .join(' '
					,$^X
					,($s->{-prgfn} =~/\.(?:bat|cmd)$/i ? ('-x') : ())
					,$s->{-prgfn}, '-runsu', $s->{-runarg})
					.'"')
			: $s->run(1
				,(-e '/bin/sudo' ? '/bin/sudo' : 'sudo')
				,'-u', $s->{-susr}
				,$^X, $s->{-prgfn}, '-runsu', $s->{-runarg});
			exit(0)
		}
		$s->printflush('[',$s->{-prgfn},'] -runsu, ',($s->{-runarg}||0), ', $$', $$,"...\n");
		$s->{-runmod} ='-runsu';
	}
 }
 elsif ($s->{-runmod} eq '-run') {		# run task
	$s->printflush('[',$s->{-prgfn},'] -run, ',($s->{-runarg}||0), ', $$', $$,"...\n");
 }
 elsif ($s->{-runmod} eq '-runsu') {		# run task switched user
	if ($^O eq 'MSWin32') {
		my $n =$s->{-prgsn};
		$s->printflush('[',$s->{-prgfn},'] -runsu, ',($s->{-runarg}||0), ', $$', $$,"...\n");
		if (!$s->{-susr}
		&& (($s->w32svcr("$n\\Parameters\\AppParameters")||'') 
				!~/\s0\s*$/)) {	# from -surun
			$s->loglcs(2);
			$s->w32svcr("$n\\Parameters")->{AppParameters}
				='-e"$SIG{CHLD}=\'IGNORE\';system(1,$^X,@ARGV)" '
				.$s->{-prgfn} .' -runsu 0';
			$s->loglcs(0);
		}
		$s->w32svco(0) if !$s->{-susr};
	}
	else {
		$s->printflush('[',$s->{-prgfn},'] -runsu, ',($s->{-runarg}||0), ', $$', $$,"...\n");
	}
 }
 else {
	croak("Error('-runmod'): " 
		.(!defined($s->{-runmod}) ? 'undef' : $s->{-runmod} eq '' ? "''" : $s->{-runmod})
		);
 }

 if ($s->{-runmod} =~/^-run/) {			# log/pid file rotator
	$s->{-logpid} =$s->vfname() .$$ .'-' .$_[0]->{-prgcn}
		.$s->{-runmod}			# pid file
		.(do{	my $a =$s->{-runarg};
			# $a =~s/([^a-zA-Z0-9_.-])/uc sprintf("%%%02x",ord($1))/eg;
			$a =~s/\s/_/g;
			$a =~s/:/-/g;
			$a =~s/([^a-zA-Z0-9_.-])/-/g;
			$a
			})
		.'.pid'
		if $s->{-logpid};
	$s->fwrite($s->{-logpid}, $s->strtime() .' ['.$s->{-prgsn} 
		."] " .$s->{-runmod} .', ' .$s->{-runarg} .', $$' .$$) 
		if $s->{-logpid};
	if ($s->{-logmax}			# log file rotator
	&& ($s->{-logmax} <((-s $s->vfname('log.txt'))||0))) {
		$s->logrdr(undef) if $s->{-wrlog};
		if ($s->loglck(2,1)) {
			$s->vftruncate('log.txt');
			$s->loglck(0);
		}
	}
	$s->vfwrite('>>log.txt', "\n". $s->strtime() .' ['.$s->{-prgsn} 
		."] " .$s->{-runmod} .', ' .$s->{-runarg} .', $$' .$$);
	local *DIR;				# pid file cleaner
	if ($s->{-logpid} && $_[0]->{-dirv} && opendir(DIR, $_[0]->{-dirv})) {
		my $f;
		my $q ='-' .$_[0]->{-prgcn} .'-';
		while ($f =readdir(DIR)) {
			next	if !$f
				|| ($f !~/\.pid$/i)
				|| ($f !~/^\d+\Q$q\E/)
				|| ($s->{-logpid} =~/\Q$f\E$/i);
			my $n =$_[0]->{-dirv} .$_[0]->{-dirm} .$f;
			my $t =(stat($n))[8];
			next	if time() -$t < 60*60*24*5;
			$s->echolog('unlink',' ',$n
				, unlink($n)
				? ()
				: (map {$_ ? ($_) : ()} ' ',$!,' ',$^E));
		}

	}
 }

 if ($s->{-runmod} =~/^-run/) {			# work dir
	chdir $s->{-dirb};
 }
 $s;
}


sub at {	# At... condition (interface)
		# (?-options, ?at args, ?sub{}) -> true | false
 my ($s,$o) =($_[0], $_[1] =~/^-/ ? $_[1] : '');
 my $r;
 $s->{''} =$s->startup() && 1	# startup, if not yet
	if !$s->{''};

 $s->{-atarg} =undef;		# check condition / set 'at'
 if (ref($o ? $_[2] : $_[1])) {
	foreach my $c (@_[($o ? 2 : 1) .. $#_]) {
		next if ref($c) ne 'ARRAY';
		$r =at_($s, $o, @$c);
		$s->{-atarg} =$c if !$s->{-atarg};
		last if $r && ($s->{-runmod} =~/^-run/);
	}
 }
 else {
	$r =$o 
	? (ref($_[$#_]) ? at_(@_[1..$#_-1]) : at_(@_))
	: (ref($_[$#_]) ? at_($s, $o, @_[1..$#_-1]) : at_($s, $o, @_[1..$#_]))
 }
 return(undef)
	if ($s->{-runmod} !~/^-run/) || !$r;

   $o =~/w/			# write logfile
 ? $s->loglck(1) && $s->logrdr(1)
 : $s->{-wrout}
 ? $s->logrdr(undef)
 : undef;

    $r				# execute sub{} given
 && (ref($_[$#_]) eq 'CODE') 
 && &{$_[$#_]}($s);

 $s->loglck(0) if $o =~/w/;

 $r
}


sub at_ {	# At... condition (implementation)
 my ($s,$o) =@_[0..1];
 if ($s->{-runmod} =~/^-run/) {		# Run condition
	if (($o =~/s/) && ($s->{-runmod} !~/^-runsu/)) {
		return(undef)
	}
	elsif (($o !~/s/) && ($s->{-runmod} =~/^-runsu/)) {
		return(undef)
	}
	elsif ($o =~/a/) {			# run anytime
		return(1)
	}
	elsif ($o =~/([dn]\d)/) {	# run daily/nightly begin/middle/end
		my $on =$1;
		return(1) if $s->{-atopt} =~/\Q$on\E/;
		$s->loglck(2);
		$s->logrdr(0) if !$s->{-wrlog};
		my $r =undef;
		if ($s->atopt("-$on")) {
			$s->{-atopt} .=$on;
			$s->vfwrite($on .'.txt', $s->strtime() ." " .$s->class() .'::at $$' .$$);
			$s->{-wrlog}->print($s->strtime(), " [", $s->{-prgsn}, "] $o\n");
			$s->{-wrlog}->flush();
			$r =1
		}
		$s->loglck(0);
		return($r)
	}
	return(	  ($s->{-atarg}		# comparing sys scheduler options
			? $s->{-runarg} ne atesc($s, atarg($s, @_[2..$#_]))
			: $s->{-runarg} ne atesc($s, @_[2..$#_]))
		? undef
		: ($o =~/s/) && ($s->{-runmod} !~/^-runsu/)
		? undef
		: 1
		)
 }
 elsif ($s->{-runmod} =~/^-set/) {	# Setup system scheduler
	if (($o =~/([dn]\d)/)		# daily/nightly autofill
	&& !$s->{-atarg}
	&& (!defined($_[2]) ||($_[2] eq ''))
		) {
		$s->{-atarg} =$s->{-w32at}
			? [$s->{"-$1"} .':00', '/every:M,T,W,Th,F,S,Su']
			: [0, $s->{"-$1"}, '*', '*', '*']
	}
	return(undef)			# without system scheduler
		if ($#_<3) 
		&& !$s->{-atarg}
		&& (!defined($_[2]) ||($_[2] =~/^(?:|0|\w[\w\d_]*)$/));
	if ($s->{-w32at}) {		# win32at system scheduler
		$s->echologdie("Error(-set): Win32 service '" .$s->{-prgsn} ."' not installed")
			if ($o =~/s/)
			&& !$s->{-susr} && !$s->{-spsw}
			&& !$s->w32svcr($s->{-prgsn});
		$s->run('at', atarg($s, @_[2..$#_]), $^X
			, ($s->{-prgfn} =~/\.(?:bat|cmd)$/i ? ('-x') : ())
			, $s->{-prgfn}
			, $o =~/s/ ? '-surun' : '-run'
			, atesc($s, atarg($s, @_[2..$#_])))
	}
	else {				# crontab system scheduler
		push @{$s->{-crontab}}
		, join(' '
			, atarg($s, @_[2..$#_]), $^X, $s->{-prgfn}
			, $o =~/s/ ? '-surun' : '-run'
			, atesc($s, atarg($s, @_[2..$#_])));
	}
	return(undef);
 }
}


sub atopt {	# At options check
 my ($s,$o) =@_[0..1];		# (-options) -> success
 if ($o =~/a/) {		# run anytime
	return(1)
 }
 elsif ($o =~/([dn]\d)/) {	# run daily/nightly begin/middle/end
	my $on =$1;
	return(1) if $s->{-atopt} =~/\Q$on\E/;
	my $os =(stat $s->vfname($on .'.txt'))[9];
	my $ot =$os ? [localtime $os] : undef;
	my $cs =$s->{-time};
	my $ct =[localtime($cs)];
	foreach my $l ($ot,$ct) {
		$l->[7] =$l->[5] 	# year .yday
			. (length($l->[7]) <3
			? ('0' x (3 -length($l->[7]))) .$l->[7] 
			: $l->[7]) if $l
	}
	if ($on =~/n1|n2|d0/) {		# night middle, night end, day begin
		return(1)
		if ($ct->[2] >=$s->{"-$on"})
		&& ($ct->[7] ne ($ot && $ot->[7] || 0))
	}
	elsif ($on =~/d1|d2|n0/) {	# day middle, day end, night begin
		return(1)
		if !$ot
		?  1
		: ($ct->[2] >=$s->{"-$on"})
		? ($ot->[2] < $s->{"-$on"})	|| ($ot->[7] <$ct->[7])
		: ($ot->[7] < $ct->[7]-1)
		?  1
		: ($ot->[7] <$ct->[7])		&& ($ot->[2] <$s->{"-$on"})
	}
 }
 undef
}


sub soon {	# Cyclical starting sub{}
		# (?-options, period, command)
		# (?-options, 'self', -runmod, -runarg)
		# (?-options, period, name, code{})
 my ($s, $o, $p, $n, $c) =(shift, ($_[0]=~/^-/ ? shift : '-'), @_);
 $s->echologdie("Error(soon): not Win32") if $^O ne 'MSWin32';
 return(undef)	if $s->{-runmod} !~/^(?:-run|-runsu|-set)/;
 if (!$c || ($n eq 'self')) {
	if ($s->{-runmod} =~/^(?:-run|-runsu)/) {
		my @t1 =localtime(time +(!$p ? 60 *15 : $p <60 ? 60 : $p));
		my @c =('at',$t1[2] .':' .$t1[1]
				,($o =~/i/ ? ('/interactive') : ())
				,($n eq 'self'
				? join(' ', $^X, $s->{-prgfn}, @_[2..$#_])
				: $n));
		return($s->run(@c));
	}
	else {
		return(undef);
	}
 }
 $s->{-wrout} && $s->logrdr(0);
 my $q =$s->{-prgfn} .' ' .($o =~/s/ ? '-surun' : '-run') .' ' .$n;
 my $t =defined($s->{-runarg}) && ($s->{-runarg} eq $n)
	&& defined($s->{-runmod})
	&& ($s->{-runmod} eq ($o =~/s/ ? '-runsu' : '-run'));
 return(undef)	if !$t && (`at` =~/\b\Q$q\E\b/);
 my $r =undef;
 if ($s->loglcs(2, $t ? 0 : 1)) {
	$s->logrdr(0) if !$s->{-wrlog};
	if ($t) {	 			# execute
		$s->logrdr(1) if $o =~/w/;

		$r =eval{&$c($s,$o,@_)};

		$s->{-wrlog}->flush();
		$s->logrdr(0) if $o =~/w/;
	}
	if (1) {				# reschedule
		foreach my $r (split /\s*\r*\n\r*/, `at`) {
			next if $r !~/\b\Q$q\E\b/;
			my $i =($r =~/^[^\d]*(\d+)/ ? $1 : undef);
			next if !$i;
			my @c =('at', $i, '/d', '/y');
			$s->echolog('[soon] ', join(' ',$n,@c));
			system(@c);
		}
		$p =$p		# !!! long period may be shorten somehow
			if !$t && ($p/2 >60*15);
		my @t1 =localtime(time +(!$p ? 60 *15 : $p <60 ? 60 : $p));
		my @c =('at',$t1[2] .':' .$t1[1]
			,($o =~/i/ ? ('/interactive') : ())
			,$^X
			,($s->{-prgfn} =~/\.(?:bat|cmd)$/i ? ('-x') : ())
			,$s->{-prgfn}
			,$o =~/s/ ? '-surun' : '-run'
			,$n);
		$s->echolog('[soon] ', join(' ',$n,@c));
		map {$s->echolog('[soon] ',$n,' ',$_)
			} $s->runlist(@c);
		$s->{-wrlog}->flush();
	}
	$s->loglcs(0,1);
 }
 else {
	$s->loglcs(0,1);
 }
 $r
}


sub chpswd {	# Change service password
 my ($s,$su,$sp,@sh) =@_;	# (user, password, additional hosts) -> success
				# (..., [host, service],...)
 $s->echologdie("Error(chpswd): not Win32") if $^O ne 'MSWin32';
 $s->loglck(2);
 $s->logrdr(0) if !$s->{-wrlog};
 my $sn =$s->{-prgsn};
 $su =$su || $s->{-prgcn};
 $sp =$sp || do {	my $p=''; 
			while(length($p) <20) {
				my $c =rand(ord('z'));
				next if chr($c) !~/[\w\d.!#\@\$\%&+-]/;
				$p .=chr($c);
			} $p};
 print("[chpswd] $sn,$su,'*','',", join(',',@sh), "\n");
 $s->{-wrlog}->print($s->strtime(), " [chpswd] net user $su\n");
 my $e  ='';
 my @rc =$s->runlist('net','user'
		,($su =~/\\/ ? $' : $su =~/\@/ ? $` : $su)
		,'"' .$sp .'"'
		,($su =~/(?:\\|\@)/ ? '/domain' : ())
		);
 if (scalar(@rc) ? !grep /\ssuccess/i, @rc : $?>>8) {
	$e =$@ ="Error " .($?>>8) ." (net user $su)\n" .join("\n", @rc);
	$s->echologwarn($@);
	$s->loglck(0);
	return(undef);
 }
 else {
	map {	$s->{-wrlog}->print($s->strtime()," [chpswd] $_\n") if $_
		} @rc;
	foreach my $h ('',@sh) {
		$s->{-wrlog}->print($s->strtime(), ' [chpswd] sc '
			, (ref($h) ? $h->[0] ||'' : $h ||'') 
			,' config \'', (ref($h) ? $h->[1] ||$sn ||'' : $sn ||'')
			,"'\n");
		my $ei ='';
		my $i  =0;
		while(1) {
			@rc =$s->runlist('sc', (ref($h) && $h->[0]
					? '\\\\' .$h->[0]
					: !ref($h) && $h 
					? "\\\\$h" 
					: ())
				,'config', (ref($h) && $h->[1]
					? $h->[1]
					: $sn)
				,'type=', 'own'
				,'obj=', ($su =~/(?:\\|\@)/ ? $su : ".\\$su")
				,'password=', '"' .$sp .'"');
			if (scalar(@rc) ? !grep /\ssuccess/i, @rc : $?>>8) {
				$@ ='Error '
					.($?>>8)
					.' (sc '
					.(ref($h) ? $h->[0] ||'' : $h ||'')
					.' config \''
					.(ref($h) ? $h->[1] ||$sn ||'' : $sn ||'')
					.'\')' ."\n" .join("\n", @rc);
				$ei =$@;
				$s->echologwarn($@);
				last if !$h || (ref($h) && !$h->[0]);
				last if ++$i >2;
				sleep(10)
			}
			else {
				$ei ='';
				map {	$s->{-wrlog}->print($s->strtime()
						," [chpswd] $_\n") if $_
					} @rc;
				last;
			}
		}
		$e .=($e ? "\n" : '') .$ei if $ei;
	}
 }
 $s->loglck(0);
 $@=$e;
 !$e
}

