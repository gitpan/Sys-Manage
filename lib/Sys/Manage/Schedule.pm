#!perl -w
#
# Sys::Manage::Schedule - Scriptic schedule trunk
#
# makarow, 2005-09-15
#
# ToDo (see also '???', '!!!' in the source code):
# === '-surunl' mode with File::Temp
# ??? serialization with loglcs(2) may be embarrassing
# !!! 'soon' multiplatform
# !!! 'chpswd' may fail?
#	Platform SDK: Directory Services: Changing the Password on a Service's User Account
# ??? '-surun' may be interrupted by system down or another -surun
#

package Sys::Manage::Schedule;
require 5.000;
use strict;
use Carp;
use Fcntl qw(:flock);

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
$VERSION = '1.01';

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
	,-loglto	=>60*60*8		# log file lock timeout
	,-autoflush	=>1			# autoflush
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
	,-runmod	=>''			# runnimg mode: -run, -runsu, -set,...
	,-runopt	=>''			# 'e'scaped args, 'l'ist, [\d] soon
	,-runtmp	=>''			# temp file name to redirect screen
	,-runarg	=>''		# ...	# schedule args escaped
	,-atopt		=>''			# at options saved (internally)
	#-atarg		=>undef			# at first cmd (internally)
	#-crontab	=>undef			# crontab entries (internally)
	#-wrlck		=>undef			# lock file
	#-wrlckl	=>undef			# lock file level
	#-wrlcs		=>''			# lock file additional
	#-wrlcsl	=>undef			# lock file additional level
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
	daemonise(@_)
}


sub daemonise {		# Daemonize process
 my $s =$_[0];
 my $null =$^O eq 'MSWin32' ? 'nul' : '/dev/null';
 open(STDIN,  "$null")  || return($s->error(0,'','',"daemonize(STDIN) -> $!")); 
 open(STDOUT,">$null")  || return($s->error(0,'','',"daemonize(STDOUT) -> $!"));
 eval("use POSIX 'setsid'; setsid()");
 open(STDERR,'>&STDOUT')|| return($s->error(0,'','',"daemonize(STDERR) -> $!"));
 $s
}


sub DESTROY {
 my $s =$_[0];
 return($s) if $$ <0;
 if($s->{-crontab}) {
	$s->vfwrite('>crontab.txt',@{$s->{-crontab}});
	$s->run('crontab',$s->vfname('crontab.txt'));
 }
 if (($s->{-runmod} && ($s->{-runmod} !~/^-*logask/))
 && ($s->{-wrlog} || $s->logrdr(0))) {
	$s->echowr($$,'EndSched','',$?>>8, ' # ', join(' ',$s->{-runmod}||0, $s->{-runarg}||0));
 }
 eval{$s->{-wrlckl} && $s->loglck(0)};
 eval{$s->{-wrlcsl} && $s->loglcs(0)};
 if ($s->{-runtmp}) {
	print STDOUT "\0x00\0x00";
	close(STDOUT); close(STDERR);
	delete($s->{-runtmp});
 }
 eval{$s->{-wrlog} && $s->logrdr(undef)};
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
 if ($opt{-runmod} && ($s->{-runmod} =~/^(-surun|-runsu|-run)(.+)/)) {
	$s->{-runmod} =$1;
	my $o =$2;
	if ($o =~/^(.*)=(.+)/) {
		$o =$1;
		($s->{-runtmp}) =$s->qclau($2);
	}
	$s->{-runopt} =$o;
	@ARGV[2..$#ARGV] =$s->qclau(@ARGV[2..$#ARGV])
			if ($s->{-runopt} =~/e/) && ($#ARGV >1);
 }
 $s
}



sub max {		# Max number
 (($_[1]||0) >($_[2]||0) ? $_[1] : $_[2])||0
}


sub strtime {		# Log time formatter
	my @t =$_[1] ? localtime($_[1]) : localtime();
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


sub qclae {		# Escape command line arg(s)
 	map {	my $v =defined($_) ? $_ : '';
		$v =~s/([^a-zA-Z0-9])/uc sprintf('_%02x',ord($1))/eg;
		$v
		} @_[1..$#_]
}


sub qclau {	# UnEscape command line arg(s)
 	map {	my $v =defined($_) ? $_ : '';
		$v =~s/_([0-9a-fA-F]{2})/chr hex($1)/ge;
		$v
		} @_[1..$#_]
}


sub autoflush {		# set autoflush
 my $s =$_[0];
 return($s->{-autoflush}) if !defined($_[1]);
 my @f =(select(), do{select(STDERR); $|}, do{select(STDOUT); $|});
 select(STDERR); $|=$s->{-autoflush};
 select(STDOUT); $|=$s->{-autoflush};
 $s->{-wrlog}->autoflush($s->{-autoflush}) if $s->{-wrlog};
 select($f[0]);
}


sub flush {		# Flush STDOUT/STDERR
 eval('use IO::File; STDOUT->flush(); STDERR->flush()');
 $_[0]->{-wrlog} && $_[0]->{-wrlog}->flush();
 1
}


sub echomap {		# Map echo args to print/write
 return(('[', $_[1]||$$, ']: '
	, $_[2] ||''
	, $_[3] && ($_[3] =~/^\d+$/) ? ('[', $_[3], ']: ') : $_[2] ? (': ', $_[3]) : ($_[3])
	, @_[4..$#_]
	))
}


sub echo {		# Echo to stdout
	print(!$#_ ? () : echomap(@_), "\n")
}


sub echowr {		# Echo to log
 $_[0]->{-wrlog} && $_[0]->{-wrlog}->print(
	!$#_ ? () : (strtime($_[0]),' ', echomap(@_)),"\n")
}


sub echowrf {		# Echo to log force
 return(echowr(@_)) if $_[0]->{-wrlog};
 mkdir($_[0]->{-dirv},0777) if !-e $_[0]->{-dirv};
# return($_[0]->vfwrite('>>log.txt', "\n", join('',strtime($_[0]), ' ', echomap(@_))));
 my $fh =eval('use IO::File; 1') && IO::File->new($_[0]->vfname('>>log.txt'));
 my $r =$fh && $fh->print(map {/[\r\n]$/ ? $_ : "$_\n";
			} ("\n", join('',strtime($_[0]), ' ', echomap(@_))));
 $fh->close();
 $r
}


sub echolog {		# Echo + log
 echo(@_); echowr(@_)
}


sub warning {		# Echo Warning
 my @a =($_[0], $_[1]||$$, $_[2] ||'Warning', @_[3..$#_]);
 echowrf(@a); carp(join('', echomap(@a)) ."\n")
}


sub error {		# Error finish
 my @a =($_[0], $_[1]||$$, $_[2] ||'Error', @_[3..$#_]);
 echowrf(@a);
 croak(join('', echomap(@a)) ."\n")
}


sub ftemp {		# Temporary file name
	eval('use File::Temp; File::Temp->new()->filename()')
		|| $_[0]->error(0,'','',"File::Temp->new()->filename() -> $@")
}


sub fopen {		# File open
 my ($s,$f) =@_;	# (file name) -> file handle
 eval('use IO::File');
 IO::File->new($f) || $s->error(0,'','',"fopen('$f') -> $!");
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
 defined($r) ? $b : $s->error(0,'','',"fread('$fn') -> $!")
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


sub vfread {		# Var file read
			# (abbreviate)
  $_[0]->fread($_[0]->vfname($_[1]))
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
	if (!$s->{-wrlog}) {
		$s->{-wrlog} =$s->vfopen('>>log.txt');
		$s->autoflush(1) if $s->{-autoflush};
	}
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
	$s->{-wrlog} =$s->vfopen('>>log.txt');
	$s->autoflush(1) if $s->{-autoflush};
 }
 if (!defined($_[1]) && $s->{-wrlog}) {
	$s->{-wrlog}->close();	delete $s->{-wrlog}
 }
 $s->{-wrlog}
}


sub loglck {	# Lock operation
 my ($s,$l,$t) =@_;	# (true|false|excl|undef, ?nonblock) -> success
 $s->{-wrlck} =$s->vfopen('>lck.txt') if !$s->{-wrlck};
 return(undef) if !$s->{-wrlck};
 my $r;
 if (!$#_) {
	$r =$s->{-wrlckl}
 }
 elsif (!$l) {
	$r =flock($s->{-wrlck}, LOCK_UN);
	delete($s->{-wrlckl});
	if (!defined($l)) {
		$s->{-wrlck}->close() if $s->{-wrlck};
		delete $s->{-wrlck};
	}
 }
 elsif (defined($s->{-wrlckl}) && ($s->{-wrlckl} eq $l)) {
	return(1)
 }
 elsif ($t || !$s->{-loglto}) {
	eval{$s->{-wrlog}->flush()} if $s->{-wrlog};
	if ($s->{-wrlckl}) {
		flock($s->{-wrlck}, LOCK_UN);
	}
	my $l1 =$l >1 ? LOCK_EX : LOCK_SH;
	$r =flock($s->{-wrlck}, $t ? $l1 | LOCK_NB : $l1);
	$s->{-wrlckl} =$l;
 }
 else {
	my $t =0;
	my $l1 =$l >1 ? LOCK_EX : LOCK_SH;
	my $t0 =time();
	eval{$s->{-wrlog}->flush()} if $s->{-wrlog};
	if ($s->{-wrlckl}) {
		flock($s->{-wrlck}, LOCK_UN);
		delete($s->{-wrlckl});
	}
	while (1) {
		$r =flock($s->{-wrlck}, $t ? $l1 | LOCK_NB : $l1);
		if (time() -$t0 >$s->{-loglto}) {
			$r =flock($s->{-wrlck}, LOCK_UN);
			$s->{-wrlck}->close();
			delete $s->{-wrlck};
			delete $s->{-wrlckl};
			return($s->error(0,'','',"loglck() -> timeout " .$s->{-loglto} .' since ' .$s->strtime($t0)))
		}
		elsif ($t && !$r) {
			sleep(5)
		}
		else {
			$s->{-wrlckl} =$l;
			last
		}
	}
 }
 $r;
}


sub loglcs {	# Lock operation for su / soon
 my ($s,$l,$t) =@_;	# (true|false|excl|undef, ?nonblock) -> success
 $s->{-wrlcs} =$s->vfopen('>lcs.txt') if !$s->{-wrlcs};
 return(undef) if !$s->{-wrlcs};
 my $r;
 if (!$#_) {
	$r =$s->{-wrlcsl}
 }
 elsif (!$l) {
	$r =flock($s->{-wrlcs}, LOCK_UN);
	delete($s->{-wrlcsl});
	if (!defined($l)) {
		$s->{-wrlcs}->close() if $s->{-wrlcs};
		delete $s->{-wrlcs};
	}
 }
 elsif (defined($s->{-wrlcsl}) && ($s->{-wrlcsl} eq $l)) {
	return(1)
 }
 elsif ($t || !$s->{-loglto}) {
	eval{$s->{-wrlog}->flush()} if $s->{-wrlog};
	if ($s->{-wrlcsl}) {
		flock($s->{-wrlcs}, LOCK_UN);
	}
	my $l1 =$l >1 ? LOCK_EX : LOCK_SH;
	$r =flock($s->{-wrlcs}, $t ? $l1 | LOCK_NB : $l1);
	$s->{-wrlcsl} =$l;
 }
 else {
	my $t =0;
	my $l1 =$l >1 ? LOCK_EX : LOCK_SH;
	my $t0 =time();
	eval{$s->{-wrlog}->flush()} if $s->{-wrlog};
	if ($s->{-wrlcsl}) {
		flock($s->{-wrlcs}, LOCK_UN);
		delete($s->{-wrlcsl});
	}
	while (1) {
		$r =flock($s->{-wrlcs}, $t ? $l1 | LOCK_NB : $l1);
		if (time() -$t0 >$s->{-loglto}) {
			$r =flock($s->{-wrlcs}, LOCK_UN);
			$s->{-wrlcs}->close();
			delete $s->{-wrlcs};
			delete $s->{-wrlcsl};
			return($s->error(0,'','',"loglcs() -> timeout " .$s->{-loglto} .' since ' .$s->strtime($t0)))
		}
		elsif ($t && !$r) {
			sleep(5)
		}
		else {
			$s->{-wrlcsl} =$l;
			last
		}
	}
 }
 $r;
}


sub logask {		# Echo log query
 my $s =shift;		# (-opt, -fname, start, end, on row, on end)
			# >, >=, <, <=, 'v'erbose, 's'calar
			# 'm'ark: 'm'ove, when 'a'll, 'u'se ('mm','ma','mu')
			# -fname: filename, filepath, w32:name
			# -ddate format: dd.mm.yyy...
			# 'pid's, 'err'ors, 'warn'ings and errors, 'all'
 my($o, $fl, $fm, $mi, $mo, $ds, $de, $q0, $q1, $q2);
 while(scalar(@_)) {
	if ($_[0] eq '')	{shift}
	elsif (!$o  && ($_[0] =~/^-[vsm<>=]/))	{$o =shift}
	elsif (!$o  && ($_[0] eq '-'))		{$o =shift}
	elsif (!$fl && ($_[0] =~/^-f(.*)/))	{$fl =$1; shift}
	elsif (!$mi && ($_[0] =~/^-d(.*)/))	{$mi =$1; shift}
	elsif (!$ds && ($_[0] =~/^[-\d]/))	{$ds =shift}
	elsif (!$de && ($_[0] =~/^[-\d]/))	{$de =shift}
	elsif (!$q0)	{$q0 =shift}
	elsif (!$q2)	{$q2 =shift}
	else {last}
 }
 $o  ='-v'	if !$o;
 $fl ='log.txt'	if !$fl;
 $fm =$fl;
	$fl =$s->vfname($fl)	if $fl !~/(?:[\\\/]|\Aw32:|\AMSWin32:)/;
	$fm =~s/[\\\/:]/-/g	if $fm =~/[\\\/:]/;
	$fm = $s->vfname($fm =~/^(.+?)(\.[^.]*)$/ ? "$1-i$2" : ($fm .'-i'));
 if ($ds && ($ds =~/-m[amu]$/)) {
	$o .=substr($ds, -3);
	$ds =substr($ds, 0, length($ds) -3);
 }
 $q0 ='all'	if !$q0;
 $q1 =$q0;
# print "***\$o=$o, \$fl=$fl, \$ds=$ds, \$de=$de, \$q0=$q0, \$q2=$q2\n";
# exit(0);
 my ($ll, $rr) =('','');
 my ($cs,$ce,$ci,$di) =(0,0,0,'');
 my ($id, %rq, $rq);
 local $_;
 my ($fh, $rl, $rx);
	if ($fl =~/^(?:w32|MSWin32):(.+)/i) {
		my $fl =$1;
		eval('use Win32::EventLog');
		my($wrn, $wrb, $wri, $wrh, $wet);
		$fh=Win32::EventLog->new($fl, $ENV{ComputerName})
			|| return($s->error($$,'','',"Win32::EventLog::new($fl) -> $!"));
		$fh->GetNumber($wrn)
			|| return($s->error($$,'','',"Win32::EventLog::GetNumber($fl) -> $!"));
		$fh->GetOldest($wrb)
			|| return($s->error($$,'','',"Win32::EventLog::GetOldest($fl) -> $!"));
		$wet ={	 &Win32::EventLog::EVENTLOG_ERROR_TYPE => 'Error'
			,&Win32::EventLog::EVENTLOG_WARNING_TYPE => 'Warning'
			,&Win32::EventLog::EVENTLOG_INFORMATION_TYPE => 'Info'
			,&Win32::EventLog::EVENTLOG_AUDIT_SUCCESS => 'Success'
			,&Win32::EventLog::EVENTLOG_AUDIT_FAILURE  => 'Failure'
			};
		$wri =0;
		$rl = sub {	return(undef) if $wri >=$wrn;
			if ($_[0]) {
			$fh->Read(&Win32::EventLog::EVENTLOG_FORWARDS_READ|&Win32::EventLog::EVENTLOG_SEEK_READ, $wrb +$wri, $wrh)
				|| return($s->error($$,'','',"Win32::EventLog::Read($fl, $wri) -> $!"));
	                Win32::EventLog::GetMessageText($wrh) if $_[0];
			$wri++;
			}
			# Category; ClosingRecordNumber; Computer; Data; 
			# EventID; EventType; Length; Message;
			# RecordNumber; Source; Strings; TimeGenerated; Timewritten
			# User;
			! $_[1]
			? strtime($s, $wrh->{TimeGenerated}) ."\n"
			: strtime($s, $wrh->{TimeGenerated})
				." "
				.join(' '
					,$wet->{$wrh->{EventType}} ||$wrh->{EventType}
					,$wrh->{EventID} & 0x7FFF
					,$wrh->{Source} ||''
					,$wrh->{Category} ? $wrh->{Category} : ()
					,$wrh->{Computer} ? $wrh->{Computer} : ()
					,$wrh->{User} ? $wrh->{User} : ()
					,$wrh->{Message}||''
					) ."\n";
			};
		$rx =sub{$fh->Close()};
	}
	else {
		$fh =$s->fopen("<$fl");
		if ($mi) {
			$mo =	  $mi =~/^[d]+\W[m]+\W[y]+/
				? '$3-$2-$1'
				: $mi =~/^[m]+\W[d]+\W[y]+/
				? '$3-$1-$2'
				: $mi =~/^[y]+\W[d]+\W[m]+/
				? '$1-$3-$2'
				: '$1-$2-$3';
			$mo .=	  $mi =~/^[dmy]+\W[dmy]+\W[dmu]+[\W]+[h]+\W[m]+\W[s]+/
				? ' $4:$5:$6'
				: $mi =~/^[dmy]+\W[dmy]+\W[dmu]+[\W]+[h]+\W[m]+/
				? ' $4:$5:00'
				: $mi =~/^[dmy]+\W[dmy]+\W[dmu]+[\W]+[h]+/
				? ' $4:00:00'
				: ' 00:00:00';
			$mi =~s/([^dmyhms\s]+)/\\Q$1\\E/g;
			$mi =~s/[dmyhms]+/(\\d+)/g;
			$mi =~s/\s/\\s+/g;
			$mo ='sub{$_[0] =~s/^' .$mi .'/' .$mo .'/; $_[0]}';
			# print "***$mo\n";
			$mo =eval($mo);
			$rl =sub{if($_[0]) {$mi =readline($fh)};
				 defined($mi) && $_[0] ? &$mo($mi) : $mi};
		}
	}

 $ds =	!$ds || ($ds =~/^\d\d\d\d-\d\d-\d\d/)
	? $ds
	: $ds =~/^-*(\d+)m/i
	? $s->strtime(time() -$1 * 60)
	: $ds =~/^-*(\d+)h/i
	? $s->strtime(time() -$1 * 60 * 60)
	: $ds =~/^-*(\d+)d/i
	? $s->strtime(time() -$1 * 60 * 60 *24)
	: $s->strtime(time() + eval($ds)||0);
 $de =	!$de || ($de =~/^\d\d\d\d-\d\d-\d\d/)
	? $de
	: $de =~/^-*(\d+)m/i
	? $s->strtime(time() -$1 * 60)
	: $de =~/^-*(\d+)h/i
	? $s->strtime(time() -$1 * 60 * 60)
	: $de =~/^-*(\d+)d/i
	? $s->strtime(time() -$1 * 60 * 60 *24)
	: $s->strtime(time() + eval($de)||0);
 if (($o =~/m/) && (-f $fm)) {
	my $v =$s->fread($fm);
	$ds =$v =~/\$ds=([^\r\n]*)/ ? $1||'' : $ds;
	$cs =$v =~/\$cs=([^\r\n]*)/ ? $1||0  : $cs;
	$de =$v =~/\$de=([^\r\n]*)/ ? $1||'' : $de;
	$ce =$v =~/\$ce=([^\r\n]*)/ ? $1||0  : $ce;
	if (($o =~/mm/) || (($o =~/ma/) && ($q0 =~/^all/i))) {
		if ($de) { $ds =$de; $cs =$ce +1 }
		$de ='';
		$ce =0
	}
 }
 if (ref($q1)) {}
 elsif ($q1 =~/^all/i) {
	$q1 =sub{1}
 }
 elsif ($q1 =~/^pid/i) {
	$rq=$^O eq 'MSWin32' ? (`tlist 2>nul` ||`tasklist 2>nul` || '') : `ps 2>nul`;
 	$q1=sub{if (/^\d{2,4}-\d\d-\d\d\s+\d\d:\d\d:\d\d\s+\[(\d+)\]/){
			my $id =$1;
			if (/[\]:]\s+(?:End\w*|EndSched|Exit\w*)[\[:]/i) {
				delete $rq{$id};
			}
			elsif ($rq !~/\b\Q$id\E\b/) {
			}
			elsif (!$rq{$id}
			||	(/[\]:]\s+(?:Start|StartSched)[\[:]/i)) {
				$rq{$id} =$_;
			}
			elsif (/[\]:]\s+(?:Start\w*)[\[:]/i) {
				$rq{$id} =$_ if !$rq{$id}
			}
			elsif (length($rq{$id}) <3*1024) {
				$rq{$id} .=$_;
				$rq{$id} .="...\n" if length($rq{$id}) >=3*1024;
			}
		}; ''};
	$q2=	sub{join('', map {	$rq{$_} ."\n"
				} sort {$rq{$a} cmp $rq{$b}} keys %rq)
		};
 }
 elsif ($q1 =~/^err/) {
	$q1=	$rl # $fl =~/^(?:w32|MSWin32):/
	? sub{	/^[-:\d\s]*Error\s\d+/ ? 1 : 0
		}
	: sub{	if (/^\d{2,4}-\d\d-\d\d\s+\d\d:\d\d:\d\d\s+\[(\d+)\]/) {
			$id =$1;
			if (/[\]:]\s+(?:End\w*|EndSched|Exit\w*)[\[:]/i) {
				if ((/\b(?:end|endsched|exit)[:\s]+[1-9]+\b/i)
				||  (/(?<![\\\/]|\w)(?:emerg|alert|crit|error)(?![\\\/]|\w)/i)) {
					$_[1] =$rq{$id} .$_[1] if $id && $rq{$id} && ($_[1] ne $rq{$id});
					delete $rq{$id}; $id ='';
					return($_[1])
				}
				else {
					delete $rq{$id}; $id ='';
					return(0)
				}
			}
			elsif (!defined($rq{$id})
			||	(/[\]:]\s+(?:Start|StartSched)[\[:]/i)) {
				$rq{$id} =$_;
			}
			elsif (/[\]:]\s+(?:Start\w*)[\[:]/i) {
				$rq{$id} =$_ if !$rq{$id}
			}

		}
		if ((/\b(?:end|endsched|exit)[:\s]+[1-9]+\b/i)
		||  (/(?<![\\\/]|\w)(?:emerg|alert|crit|error)(?![\\\/]|\w)/i)) {
			$_[1] =$rq{$id} .$_[1] if $id && $rq{$id} && ($_[1] ne $rq{$id});
			$rq{$id} ='' if $id;
			return($_[1])
		} 0};
 }
 elsif ($q1 =~/^warn/) {
	$q1=	$rl # $fl =~/^(?:w32|MSWin32):/
	? sub{	/^[-:\d\s]*(Error|Warning)\s\d+/ ? 1 : 0
		}
	: sub{	if (/^\d{2,4}-\d\d-\d\d\s+\d\d:\d\d:\d\d\s+\[(\d+)\]/) {
			$id =$1;
			if (/[\]:]\s+(?:End\w*|EndSched|Exit\w*)[\[:]/i) {
				if ((/\b(?:end|endsched|exit)[:\s]+[1-9]+\b/i)
				||  (/(?<![\\\/]|\w)(?:emerg|alert|crit|error|warning|warn)(?![\\\/]|\w)/i)) {
					$_[1] =$rq{$id} .$_[1] if $id && $rq{$id} && ($_[1] ne $rq{$id});
					delete $rq{$id}; $id ='';
					return($_[1])
				}
				else {
					delete $rq{$id}; $id ='';
					return(0)
				}
			}
			elsif (!defined($rq{$id})
			||	(/[\]:]\s+(?:Start|StartSched)[\[:]/i)) {
				$rq{$id} =$_;
			}
			elsif (/[\]:]\s+(?:Start\w*)[\[:]/i) {
				$rq{$id} =$_ if !$rq{$id}
			}

		}
		if ((/\b(?:end|endsched|exit)[:\s]+[1-9]+\b/i)
		||  (/(?<![\\\/]|\w)(?:emerg|alert|crit|error|warning|warn)(?![\\\/]|\w)/i)) {
			$_[1] =$rq{$id} .$_[1] if $id && $rq{$id} && ($_[1] ne $rq{$id});
			$rq{$id} ='' if $id;
			return($_[1])
		} 0};
 }
 else {
	my $q0 =$q1; $q0 =~s/\\/\\\\/g; $q0 =eval("sub{$q0}");
	$q1=	$rl # $fl =~/^(?:w32|MSWin32):/
	? sub{	&$q0(@_)
		}
	: sub{	if (/^\d{2,4}-\d\d-\d\d\s+\d\d:\d\d:\d\d\s+\[(\d+)\]/) {
			$id =$1;
			if (/[\]:]\s+(?:End\w*|EndSched|Exit\w*)[\[:]/i) {
				if (&$q0(@_)) {
					$_[1] =$rq{$id} .$_[1] if $id && $rq{$id} && ($_[1] ne $rq{$id});
					delete $rq{$id}; $id ='';
					return($_[1])
				}
				else {
					delete $rq{$id}; $id ='';
					return(0)
				}
			}
			elsif (!defined($rq{$id})
			||	(/[\]:]\s+(?:Start|StartSched)[\[:]/i)) {
				$rq{$id} =$_
			}
			elsif (/[\]:]\s+(?:Start\w*)[\[:]/i) {
				$rq{$id} =$_ if !$rq{$id}
			}
		}
		if (&$q0(@_)) {
			$_[1] =$rq{$id} .$_[1] if $id && $rq{$id} && ($_[1] ne $rq{$id});
			$rq{$id} ='' if $id;
			return($_[1])
		} 0};
 }
 if (!$ds) {}
 elsif (($o =~/>/) && ($o !~/>=/)) {
	while (defined($ll =$rl ? &$rl(1) : readline($fh))) {
		next	if $ll !~/^\d{2,4}-\d\d-\d\d/;
		last	if $ll gt $ds;
	}
 }
 elsif ($o =~/m/) {
	$di =''; $ci =0;
	while (defined($ll =$rl ? &$rl(1) : readline($fh))) {
		if ($ll =~/^(\d{2,4}-\d\d-\d\d \d\d:\d\d:\d\d)/) {
			if ($1 lt $ds)		{ next }
			elsif ($1 gt $ds)	{ $di =$1; $ci =0; last }
			elsif (!$di)		{ $di =$1 }
		}
		if ($di) {
			last if $ci >= $cs;
			$ci++	# $ci gt if eof(), else match
		}
	}	
 }
 else {
	while (defined($ll =$rl ? &$rl(1) : readline($fh))) {
		next	if $ll !~/^\d{2,4}-\d\d-\d\d/;
		last	if $ll ge $ds;
	}
 }
 $ll = &$rl(0,1) if $rl && defined($ll);
 if ($o =~/m/) {
	while (defined($ll)) {
		if ($ll =~/^(\d{2,4}-\d\d-\d\d \d\d:\d\d:\d\d)\s/) {
			if ($di ne $1) {
				last if $de && ($1 gt $de);
				$di =$1; $ci =0;
			}
		}
		last if $de && ($di eq $de) && ($ci >$ce);
		$_ =$ll;
		if (&$q1($s, $ll)) {
			print $ll	if !$q2 && ($o =~/v/);
			$rr .=$ll	if !$q2 && ($o =~/s/);
		}
		$ll =$rl ? &$rl(1,1) : readline($fh);
		$ci++;	# $ci gt if eof(), ($di eq $de), ($1 gt $de)
	}
	if (($o =~/mm/) || (($o =~/ma/) && ($q0 =~/^all/i)) || (!-f $fm)) {
		$s->fwrite($fm
			,'# logask iterator mark'
			,'$ds=' .($ds ||'')
			,'$cs=' .$cs
			,'$de=' .($di ||'')
			,'$ce=' .($ci > 0 ? $ci -1 : 0)
		)
	}
 }
 else {
	while (defined($ll)) {
		last	if $ll !~/^\d{2,4}-\d\d-\d\d\s/
			? 0
			: !$de || ($ll lt $de)
			? 0
			: ($o =~/</) && ($o !~/<=/)
			? $ll gt $de
			: 1;
		$_ =$ll;
		if (&$q1($s, $ll)) {
			print $ll	if !$q2 && ($o =~/v/);
			$rr .=$ll	if !$q2 && ($o =~/s/);
		}
		$ll =$rl ? &$rl(1,1) : readline($fh);
	}
 }
 if ($q2) {
	my $r =&$q2($s, $rr);
	print $r	if $o =~/v/;
	$rr =$r		if $o =~/s/;
 }
 $rx ? &$rx() : close($fh);
 $rr
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
 $s->echo($$,'run','',join(' ',@_[1..$#_]));
 my $r;
 $r =system(@_[1..$#_]);
 # $r =system(1,@_[1..$#_]); # 1 == P_NOWAIT
 # if ($r <0) {
 #	$s->echo($$,'run','',"Error '$!'") if $r <0;
 # }
 # elsif ($r) {
 #	$s->echowr($r,'Start', $$, ' # ', join(' ',@_));
 #	waitpid($r,0)
 #	$s->echowr($r,'End', $$, ' # ', join(' ',@_));
 # }
 if ($r <0) {
	my $e =$!;
	my $et=($! +0) .". $!" .($^E ? ' ' .($^E +0) .". $^E"  : '');
	$s->loglck(1) if !$s->{-wrlckl};
	$s->logrdr(0) if !$s->{-wrlog};
	$s->echolog($$,'Error', '', "$et # ", join(' ','run',@_[1..$#_]));
	$! =$e;
	$@ =$et;
 }
 ($r >=0) && !($?>>8)
}


sub runopen {	# Open OS command as filehandle
 my $s =$_[0];	# (command) -> file handle
 $s->echo($$,'runopen','',join(' ',@_[1..$#_]));
 my $h;
 $!=$^E=0;
 $s->{-runopen} =$s->copen($h, @_[1..$#_]);
 if (!$s->{-runopen}) {
	my $et =$@ ||(($! +0) .". $!" .($^E ? ' ' .($^E +0) .". $^E"  : ''));
	$s->loglck(1) if !$s->{-wrlckl};
	$s->logrdr(0) if !$s->{-wrlog};
	$s->echolog($$,'Error', '', "$et # ", join(' ','runopen',@_[1..$#_]));
	$@ =$et;
 }
 $s->{-runopen} && $h;
}


sub runlist {	# List OS command as an array
 my $s =$_[0];	# (command) -> strings list
 my $h =runopen(@_);
 my @r;
 if ($s->{-runopen}) {
	@r =map {(/[\r\n]*$/ ? $` : $_)} <$h>;
	waitpid($s->{-runopen},0);
 }
 @r
}


sub runlcl {	# Log os command line
 my $s =shift;	# (command) -> success
 $s->loglck(1) if !$s->{-wrlckl};
 $s->logrdr(0) if !$s->{-wrlog};
 $s->echolog($$,'runlcl','',join(' ',@_));
 my $r;
 if (0) {
	$r =system(@_);
	my @e =($!, $^E);
	($!, $^E) =@e;
	$r <0
	? $s->echolog($$,'Error','',"$! # ", join(' ','runlcl',@_))
	: $s->echowr($$,'Result','',($?>>8),' # ', join(' ','runlcl',@_))
 }
 else {
	$r =system(1,@_); # 1 == P_NOWAIT
	if ($r <0) {
		my $et=($! +0) .". $!" .($^E ? ' ' .($^E +0) .". $^E"  : '');
		$s->echolog($$,'Error', '', "$et # ", join(' ','runlcl',@_));
		$@ =$et;
	}
	elsif ($r) {
		$s->echowr($r, 'Start', $$, join(' ','runlcl',@_));
		waitpid($r,0);
		$s->echowr($r, 'End', '', ($?>>8), ' # ',join(' ','runlcl',@_));
	}
 }
 ($r >=0) && !($?>>8)
}


sub runlog {	# Log os command execution
 my $s =shift;	# (command) -> success
 $s->loglck(1) if !$s->{-wrlckl};
 $s->logrdr(0) if !$s->{-wrlog};
 $s->echolog($$,'runlog','',join(' ',@_));
 $!=$^E=0;
 my $ff=$^O eq 'MSWin32' ? $] >= 5.008008 : 1; # fork switch to log stderr as errors
 my ($hi, $hr, $he);
 eval('use IPC::Open3');
 my $pid =$ff
	? eval{IPC::Open3::open3($hi, $hr
		, $he =eval('use Symbol; Symbol::gensym'), @_)}
	: eval{IPC::Open3::open3($hi, $hr, '', @_)};
 $hi && fileno($hi) && close($hi);
 if (!$pid) {
	my @e =($!, $^E);
	my $et=($! +0) .". $!" .($^E ? ' ' .($^E +0) .". $^E"  : '');
	eval{fileno($hr) && close($hr); fileno($he) && close($he)};
	($!, $^E) =@e;
	$s->echolog($$, 'Error', '', $et, ' # ', join(' ',@_));
	$@ =$et;
	return(undef)
 }
 elsif ($ff) {
	$s->echowr($pid, 'Start', $$, join(' ',@_));
	my $r;
	my $re =sub {while(defined($r=readline($he))) {
			$r = $` if $r =~/[\r\n]*$/;
			next if $r eq '';
			echolog($s, $pid, 'Error', '', $r);
		}};
	my $pif=eval('use Thread; 1') && (eval{Thread->new($re)});
	$ff  =0		if $pif;
	$pif =fork	if $ff;
	if ($pif ||!defined($pif)) {
		echolog($s, $pid, 'Error', '', "fork read stderr -> $!")
			if !$pif;
		while(defined($r=readline($hr))) {
			$r = $` if $r =~/[\r\n]*$/;
			next if $r eq '';
			echolog($s, $pid, '', '', $r);
		}
		&$re();
		eval{fileno($hr) && close($hr)};
		eval{fileno($he) && close($he)};
		waitpid($pid,0);
		$ff ? ($pif && waitpid($pif,0)) : ($pif && $pif->join());
		$s->echowr($pid, 'End', '', ($?>>8), ' # ', join(' ',@_));
		return !($?>>8)
	}
	elsif ($ff) {
		$s->echowr($$, 'Start', $pid, join(' ','read','stderr',@_)) if $$ >0;
		&$re();
		$s->echowr($$, 'End', '', join(' ','0','#','read','stderr',@_)) if $$ >0;
		exit(0)
	}
 }
 else {
	$s->echowr($pid, 'Start', $$, join(' ',@_));
	my $r;
	while(defined($r=readline($hr))) {
		$r = $` if $r =~/[\r\n]*$/;
		next if $r eq '';
		echolog($s, $pid, '', '', $r);
	}
	eval{fileno($hr) && close($hr)};
	waitpid($pid,0);
	$s->echowr($pid, 'End', '', ($?>>8), ' # ', join(' ',@_));
	return !($?>>8)
 }
}


sub cmdfile {	# Shift command file
 $_[0]->{-cmdfile} =eval('use Sys::Manage::CmdFile; Sys::Manage::CmdFile->new()')
	if !$_[0]->{-cmdfile};
 my $r =$_[0]->{-cmdfile}->dofile(@_[1..$#_]);
 if ($_[0]->{-cmdfile}->{-retexc}) {
	$_[0]->loglck(1) if !$_[0]->{-wrlckl};
	$_[0]->logrdr(0) if !$_[0]->{-wrlog};
	$_[0]->echolog($$,'cmdfile','',join(' ',$_[0]->{-cmdfile}->{-retexc}));
	$@ =$_[0]->{-cmdfile}->{-retexc};
 }
 $r	
}


sub cmdfck {	# Check command file
 $_[0]->{-cmdfile} =eval('use Sys::Manage::CmdFile; Sys::Manage::CmdFile->new()')
	if !$_[0]->{-cmdfile};
 my $r =$_[0]->{-cmdfile}->dofck(@_[1..$#_]);
 if ($_[0]->{-cmdfile}->{-retexc}) {
	$_[0]->loglck(1) if !$_[0]->{-wrlckl};
	$_[0]->logrdr(0) if !$_[0]->{-wrlog};
	$_[0]->echolog($$,'cmdfile','',join(' ',$_[0]->{-cmdfile}->{-retexc}));
	$@ =$_[0]->{-cmdfile}->{-retexc};
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
 my $r;
 my $o =$s->{-w32svco} =$s->{-w32svco} || 
	(!$m
	? undef
	: $m ==1
	? (eval('use Win32::OLE; 1') && Win32::OLE->GetObject("winmgmts:Win32_Service.Name='$n'"))
	: (eval('use Win32::OLE; 1') && Win32::OLE->GetObject('WinNT://' .Win32::NodeName() .'/' .$n .',Service')));
 if ($m && !$o) {
	$@ ='Win32::OLE->GetObject() -> ' .$s->w32oleerr();
	$s->echowrf($$, 'Warning', '', $@ .' # w32svco(' .$m .',' .($#_ ? $_[1] : 'undef') ."); Using 'net' command...")
 }
 else {
	$@ =undef;
 }
 if (!$#_) {
	return($o)
 }
 elsif (!$m || !$o) {
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
 return($s) if $s->{''};
 $s->{''} =1;
 $s->autoflush(1) if $s->{-autoflush};
 $s->{-dirv} = -d ($s->{-dirb} .$s->{-dirm} .'var')
		? ($s->{-dirb} .$s->{-dirm} .'var')
		: ($s->{-dirb} .$s->{-dirm} .$s->{-prgcn})
	if !$s->{-dirv};
 if ($s->{-runmod} =~/^-*logask/) {
	$s->logask(@ARGV[1..$#ARGV]);
 }
 elsif ($s->{-runmod} =~/^-set/) {			# clean schedule existed
	$s->echo($$,'Scheduling','', $s->{-runmod});
	$s->loglck(1);
	$s->logrdr(0) if !$s->{-wrlog};
	$s->echowr();
	$s->echowr($$,'StartSched','',join(' ',$s->{-runmod}));
	mkdir($s->{-dirv},0777) if !-e $s->{-dirv};
	if ($s->{-w32at}) {
		my $qs =$s->{-prgfn};
		my @at =split /\s*\r*\n\r*/, `at`;
		foreach my $r (@at) {
			next if $r !~/\b\Q$qs\E\b/i;
			my $i =($r =~/^[^\d]*(\d+)/ ? $1 : undef);
			next if !$i;
			$s->run('at', $i, '/d', '/y');
		}
	}
	else {
		my $qs =$s->{-prgfn};
		$s->{-crontab} =
			[map {	/\b\Q$qs\E\b/i ? () : ($_)
				} split /\s*\r*\n\r*/, `crontab -l`];
		$s->vfwrite('>crontab.txt',@{$s->{-crontab}});
		$s->run('crontab',$s->vfname('crontab.txt'));
	}
	if ($s->{-runmod} =~/^-setdel/) {	# delete settings
		$s->logrdr(undef);
		$s->loglck(0);
		exit(0)
	}
 }
 elsif ($s->{-runmod} eq '-svcinst') {		# install service
	croak("Error: Win32 only function") if $^O ne 'MSWin32';
	my $n =$s->{-prgsn};
	$s->echo($$,'Installing Windows Service','', $s->{-runmod},',',$n,'...');
	$s->loglck(1);
	$s->logrdr(0) if !$s->{-wrlog};
	$s->echowr();
	$s->echowr($$,'StartSched','',join(' ',$s->{-runmod}));
	my $p ='';
	foreach my $d (split /\s*\;\s*/, $ENV{PATH}) {
		next if !-e "$d\\srvany.exe";
		$p =$d; last;
	}
	if (!$p) {
		$s->error($$,'','',"Not found ResKip 'srvany.exe' in path, exit.");
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
	$s->echo();
	$s->echo($$,'-svcinst','', "Check '$n' service 'Startup type' and 'Log on'!");
	$s->logrdr(undef);
	$s->loglck(0);
	exit(0);
 }
 elsif ($s->{-runmod} eq '-svcdel') {		# remove service
	croak("Error: Win32 only function") if $^O ne 'MSWin32';
	my $n =$s->{-prgsn};
	$s->echo($$,'Removing Windows Service','', $s->{-runmod},',',$n,'...');
	$s->loglck(1);
	$s->logrdr(0) if !$s->{-wrlog};
	$s->echowr();
	$s->echowr($$,'StartSched','',join(' ',$s->{-runmod}));
	$s->run('instsrv',$n,"Remove");
	$s->logrdr(undef);
	$s->loglck(0);
	exit(0);
 }
 elsif ($s->{-runmod} =~/^-surun/) {		# start switched user and exit
	if ($^O eq 'MSWin32') {
		my $ft =$s->{-runopt} =~/([l\d]+)/ ? $1 : undef;
		if ($ft && ($ft =~/\d/)) {
			$s->echo($$,'StartSched','',"-surun:soon($ft) ", $s->{-runarg}||0);
			$s->loglck(1) if !$s->{-wrlckl};
			$s->logrdr(0) if !$s->{-wrlog};
			$s->echowr();
			$s->echowr($$,'StartSched','',"-surun:soon($ft) ", $s->{-runarg}||0);
			my $tt =$ft;
			local $s->{-runmod} ='-run';
			$ft =$s->ftemp();
			$s->soon('-',$tt,'self'
					,join('='
						,'-run-e'
						,$ft ? $s->qclae($ft) : ())
				,$s->{-runarg}||0
				,$#ARGV >1 ? $s->qclae(@ARGV[2..$#ARGV]) : ()
				)
		}
		elsif ($s->{-susr} && $s->{-spsw}) {
			$s->echo($$,'StartSched','','-surun:wmi ',$s->{-runarg}||0);
			$s->loglck(1) if !$s->{-wrlckl};
			$s->logrdr(0) if !$s->{-wrlog};
			$s->echowr();
			$s->echowr($$,'StartSched','','-surun:wmi ',$s->{-runarg}||0);
			local $^W=undef;
			eval('use Win32::OLE');
			my $wmi =Win32::OLE->new('WbemScripting.SWbemLocator');
			$wmi =$wmi->ConnectServer(Win32::NodeName(),'root\\cimv2',$s->{-susr},$s->{-spsw})
				|| croak 'Error(WMI->ConnectServer): ' .$s->w32oleerr();
				# !!! OLE exception from "SWbemLocator": User credentials cannot be used for local connections
			$wmi->{Security_}->{ImpersonationLevel}=3; # 4-delegate, 3-impersonate;
			my $mih =$wmi->Get('Win32_Process')
				|| croak 'Error(WMI->Win32_Process): ' .$s->w32oleerr();
			$ft =$ft && $s->ftemp();
			$mih->Create(join(' '
					,$^X, $s->{-prgfn}
					,join('='
						,'-runsu-e'
						,$ft ? $s->qclae($ft) : ())
					,$s->{-runarg}||0
					,$#ARGV >1 ? $s->qclae(@ARGV[2..$#ARGV]) : ()
					), undef,undef,$wmi)
				&& $s->error(0,'','',"WMI->Create($^X) -> " .$s->w32oleerr());
		}
		else {
			my $n =$s->{-prgsn};
			$s->echo($$,'StartSched','','-surun:svc ',($s->{-runarg}||0), '...');
			$s->loglck(1) if !$s->{-wrlckl};
			$s->logrdr(0) if !$s->{-wrlog};
			$s->echowr();
			$s->echowr($$,'StartSched','','-surun:svc ',$s->{-runarg}||0);
			$s->loglcs(2);
			$s->w32svco(0);
			$ft =$ft && $s->ftemp();
			$s->w32svcr("$n\\Parameters")->{AppParameters}
				='-e"$SIG{CHLD}=\'IGNORE\';system(1,$^X,@ARGV)" '
				.join(' '
					,$s->{-prgfn}
					,join('='
						,'-runsu-e'
						,$ft ? $s->qclae($ft) : ())
					,$s->{-runarg}||0
					,$#ARGV >1 ? $s->qclae(@ARGV[2..$#ARGV]) : ()
				);
			$s->w32svco(1)
			|| ($@ && $s->echowr($$,'Error','',"$@ # w32svco,1"));
			# !!! service startup may be continues, interrupted
			# $s->w32svcr("$n\\Parameters")->{AppParameters}
			#	='-e"$SIG{CHLD}=\'IGNORE\';system(1,$^X,@ARGV)" '
			#	.$s->{-prgfn} .' -runsu 0';
		}
		$s->logrdr(undef);
		$s->loglck(0);
		$s->loglcs(0);
		if ($ft) {
			print "File::Temp='$ft'";
			my ($fh, $fr);
			while (!(-f $ft)
				|| !(-s $ft)
				|| !($fh=eval{$s->fopen("<$ft")})
				) {
				print '.';
				sleep(1);
			}
			print "\n";
			while ($fh) {
				$fr =readline($fh);
				if (!defined($fr)) {seek($fh, 0, 1)}
				elsif ($fr eq "\0x00\0x00") {last}
				else {print $fr}
			}
			if ($fh) {
				close($fh);
				unlink($ft) || $s->error(0,'','',"unlink('$ft') -> $!");
			}
		}
		exit(0);
	}
	elsif ($s->{-susr} && !$s->{-spsw}) {
		$s->echo($$,'StartSched','','-surun:su ',$s->{-runarg}||0);
		$s->loglck(1) if !$s->{-wrlckl};
		$s->logrdr(0) if !$s->{-wrlog};
		$s->echowr();
		$s->echowr($$,'StartSched','','-surun:su ',$s->{-runarg}||0);
		$SIG{CHLD}='IGNORE';
		($>||0) ==0
		? $s->run(1
			,(-e '/bin/su' ? '/bin/su' : 'su')
			,$s->{-susr}
			,'-c','"' .join(' '
				,$^X
				,($s->{-prgfn} =~/\.(?:bat|cmd)$/i ? ('-x') : ())
				,$s->{-prgfn}, '-runsu-e', $s->{-runarg}
				,$#ARGV >1 ? $s->qclae(@ARGV[2..$#ARGV]) : ()
				) .'"')
		: $s->run(1
			,(-e '/bin/sudo' ? '/bin/sudo' : 'sudo')
			,'-u', $s->{-susr}
			,$^X, $s->{-prgfn}, '-runsu-e', $s->{-runarg}
			,$#ARGV >1 ? $s->qclae(@ARGV[2..$#ARGV]) : ()
			);
		$s->logrdr(undef);
		$s->loglck(0);
		exit(0)
	}
	else {
		$s->{-runmod} ='-runsu';
		$s->echo($$,'StartSched','',join(' ',$s->{-runmod}, $s->{-runarg}||0));
	}
 }
 elsif ($s->{-runmod} =~ /^-runsu/) {		# run task switched user
	if ($s->{-runtmp}) {
		open(STDOUT, '>' .$s->{-runtmp})
			|| $s->error(0,'','',"open('$s->{-runtmp}') -> $!");
		open(STDERR, '>>&1');
	}
	$s->echo($$,'StartSched','',join(' ',$s->{-runmod}, $s->{-runarg}||0
		, $#ARGV >1 ? $s->qclad(@ARGV[2..$#ARGV]) : ()));
	$s->loglck(1) if !$s->{-wrlckl};
	if ($^O eq 'MSWin32') {
		my $n =$s->{-prgsn};
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
 }
 elsif ($s->{-runmod} =~ /^-run/) {		# run task
	if ($s->{-runtmp}) {
		open(STDOUT, '>' .$s->{-runtmp})
			|| $s->error(0,'','',"open('$s->{-runtmp}') -> $!");
		open(STDERR, '>>&1');
	}
	$s->echo($$,'StartSched','',join(' ',$s->{-runmod}, $s->{-runarg}||0
		, $#ARGV >1 ? $s->qclad(@ARGV[2..$#ARGV]) : ()));
 }
 else {
	croak("Error('-runmod'): " 
		.(!defined($s->{-runmod}) ? 'undef' : $s->{-runmod} eq '' ? "''" : $s->{-runmod})
		);
 }

 if ($s->{-runmod} =~/^-run/) {	
	if ($s->{-logmax}			# log file rotator
	&& ($s->{-logmax} <((-s $s->vfname('log.txt'))||0))) {
		$s->logrdr(undef)		if $s->{-wrlog};
		$s->vftruncate('log.txt')	if $s->loglck(2,1);
	}
	$s->loglck(1);				# start execution
	$s->logrdr(0);
	$s->echowr();
	$s->echowr($$,'StartSched','',join(' ',$s->{-runmod}, $s->{-runarg}||0
		, $#ARGV >1 ? $s->qclad(@ARGV[2..$#ARGV]) : ()));
	chdir $s->{-dirb};			# work dir
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

				# write logfile
 $s->loglck(1) if !$s->{-wrlckl};

   $o =~/w/
 ? $s->logrdr(1)
 : $s->{-wrout}
 ? $s->logrdr(0)
 : undef;

    $r				# execute sub{} given
 && (ref($_[$#_]) eq 'CODE') 
 && &{$_[$#_]}($s);

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
	elsif ($o =~/a/) {		# run anytime
		return(1)
	}
	elsif ($o =~/([dn]\d)/) {	# run daily/nightly begin/middle/end
		my $on =$1;
		return(1) if $s->{-atopt} =~/\Q$on\E/;
		$s->loglck(1) if !$s->{-wrlckl};
		$s->logrdr(0) if !$s->{-wrlog};
		$s->loglcs(2);	# $s->loglck(2)
		my $r =undef;
		if ($s->atopt("-$on")) {
			$s->echowr($$,'at','',$o);
			$s->{-atopt} .=$on;
			$s->vfwrite($on .'.txt', $s->strtime() ." [$$]: at: $o");
			$r =1
		}
		$s->loglcs(0);	# $s->loglck(1)
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
			? [$s->{"-$1"} .':00', $o=~/i/ ? '/interactive' : (), '/every:M,T,W,Th,F,S,Su']
			: [0, $s->{"-$1"}, '*', '*', '*']
	}
	return(undef)			# without system scheduler
		if ($#_<3) 
		&& !$s->{-atarg}
		&& (!defined($_[2]) ||($_[2] =~/^(?:|0|\w[\w\d_]*)$/));
	if ($s->{-w32at}) {		# win32at system scheduler
		$s->error($$,'','',"-set: Win32 service '" .$s->{-prgsn} ."' not installed")
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
 $s->error($$,'soon','',"Error: not MSWin32") if $^O ne 'MSWin32';
 return(undef)	if $s->{-runmod} !~/^(?:-run|-runsu|-set)/;
 if (!ref($c) || ($n eq 'self')) {
	if ($s->{-runmod} =~/^(?:-run|-runsu)/) {
		my @t1 =localtime(time +(!$p ? 60 *15 : $p <60 ? 60 : $p));
		my @c =('at',$t1[2] .':' .$t1[1]
				,($o =~/i/ ? ('/interactive') : ())
				,($n eq 'self'
				? ($^X, $s->{-prgfn}, @_[2..$#_])
				: ($n, $#_ >1 ? @_[2..$#_] : ())
				));
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
 return(undef)	if !$t && (`at` =~/\b\Q$q\E\b/i);
 $s->loglck(1) if !$s->{-wrlckl};
 $s->logrdr(0) if !$s->{-wrlog};
 my $r =undef;
 if ($s->loglcs(2, $t ? 0 : 1)) {		# lock nonblock if match
	if ($t) {	 			# execute
		$s->logrdr(1) if $o =~/w/;

		$r =eval{&$c($s,$o,@_)};

		$s->{-wrlog}->flush();
		$s->logrdr(0) if $o =~/w/;
	}
	if (1) {				# reschedule
		foreach my $r (split /\s*\r*\n\r*/, `at`) {
			next if $r !~/\b\Q$q\E\b/i;
			my $i =($r =~/^[^\d]*(\d+)/ ? $1 : undef);
			next if !$i;
			my @c =('at', $i, '/d', '/y');
			$s->echolog($$,'soon', '', join(' ',$n,@c));
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
		$s->echolog($$,'soon', '', join(' ',$n,@c));
		map {$s->echolog($$,'soon', '', $n,' ',$_)
			} $s->runlist(@c);
	}
	$s->loglcs(0);
 }
 $r
}


sub chpswd {	# Change service password
 my ($s,$su,$sp,@sh) =@_;	# (user, password, additional hosts) -> success
				# (..., [host, service],...)
 $s->loglck(1) if !$s->{-wrlckl};
 $s->logrdr(0) if !$s->{-wrlog};
 $s->error($$,'chpswd','',"Error: not Win32") if $^O ne 'MSWin32';
 $s->loglcs(2);
 my $sn =$s->{-prgsn};
 $su =$su || $s->{-prgcn};
 $sp =$sp || do {	my $p=''; 
			while(length($p) <20) {
				my $c =rand(ord('z'));
				next if chr($c) !~/[\w\d.!#\@\$\%&+-]/;
				$p .=chr($c);
			} $p};
 $s->echo($$,'chpswd','',"$sn,$su,'*','',", join(',',@sh));
 $s->echowr($$,'chpswd','',"net user $su");
 my $e  ='';
 my @rc =do{	my $v =join(' ',
		'net','user'
		,($su =~/\\/ ? $' : $su =~/\@/ ? $` : $su)
		,'"' .$sp .'"'
		,($su =~/(?:\\|\@)/ ? '/domain' : ())
		,'2>>&1'
		);
		$s->echo($$,'chpswd','',$v);
		map {(/[\r\n]*$/ ? $` : $_)} `$v`};
 if ($?>>8) {
	$e =$@ ="chpswd: " .($?>>8) ." # net user $su\n" .join("\n", @rc);
	foreach my $v (split /[\n\r]+/, $e) {
		$s->echolog($$,'Error','',$v);
	}
	$s->loglcs(0);
	return(undef);
 }
 else {
	map {	$s->echolog($$,'chpswd','',$_) if $_
		} @rc;
	foreach my $h ('',@sh) {
		my $ei ='';
		my $i  =0;
		while(1) {
			$s->echowr($$,'chpswd','','sc '
				, (ref($h) ? $h->[0] ||'' : $h ||'') 
				,' config \'', (ref($h) ? $h->[1] ||$sn ||'' : $sn ||'')
				, '\''
				);
			@rc =do{my $v =join(' ',
					,'sc', (ref($h) && $h->[0]
					? '\\\\' .$h->[0]
					: !ref($h) && $h 
					? "\\\\$h" 
					: ())
				,'config', (ref($h) && $h->[1]
					? $h->[1]
					: $sn)
				,'type=', 'own'
				,'obj=', ($su =~/(?:\\|\@)/ ? $su : ".\\$su")
				,'password=', '"' .$sp .'"'
				);
				$s->echo($$,'chpswd','',$v);
				map {(/[\r\n]*$/ ? $` : $_)} `$v`};
			if (scalar(@rc) ? !grep /\ssuccess/i, @rc : $?>>8) {
				$@ ='chpswd: '
					.($?>>8)
					.' # sc '
					.(ref($h) ? $h->[0] ||'' : $h ||'')
					.' config \''
					.(ref($h) ? $h->[1] ||$sn ||'' : $sn ||'')
					."'\n" .join("\n", @rc);
				$ei =$@;
				foreach my $v (split /[\n\r]+/, $ei) {
					$s->echolog($$,'Error','',$v);
				}
				last if !$h || (ref($h) && !$h->[0]);
				last if ++$i >2;
				sleep(10)
			}
			else {
				$ei ='';
				map {	$s->echolog($$,'chpswd','',$_) if $_
					} @rc;
				last;
			}
		}
		$e .=($e ? "\n" : '') .$ei if $ei;
	}
 }
 $s->loglcs(0);
 $@=$e;
 !$e
}

