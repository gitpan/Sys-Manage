#!perl -w
#
# Sys::Manage::Cmd - Systems management command volley
#
# makarow, 2005-09-09
#
# !!! see in source code
# ??? eject logfiles?
# 

package Sys::Manage::Cmd;
require 5.000;
use strict;
use UNIVERSAL;
use Carp;
use IO::File;
use Fcntl qw(:DEFAULT :flock :seek :mode);
use Data::Dumper;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
$VERSION = '0.50';

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
 %$s =(  -dirm		=>do{$0 =~/([\\\/])/	# directory marker
			? $1
			: $^O eq 'MSWin32'
			? '\\'
			: '/'}
	,-dirb		=>do {			# directory base
			my $v =$^O eq 'MSWin32' ? scalar(Win32::GetFullPathName($0)) : $0;
			$v !~/[\\\/]/
			? (-d './var' ? '.' : -d '../var' ? '..' : '.')
			: $v =~/(?:[\\\/]bin){0,1}[\\\/][^\\\/]+$/i
			? $`
			: '.'}
	,-dirl		=>100			# logged commands limit
	,-prgsn		=>do{$0 =~/([^\\\/]+)$/	# program short name
			? $1
			: $0}
	,-prgcn		=>			# program common name
			do{my $v =$s->class; $v=~s/::/-/g; $v}
	#-config	=>undef			# config use, '-cfg' also
	,-error		=>'die'			# error handler
	,-echo		=>2		# -v	# echo verbosity level
	#-echot		=>undef		# -vt	# echo time including
	,-log		=>undef			# log file name
	#-logh					# log file handler
	,-logevt	=>undef			# log event trigger sub{}
	#-logevth*				# log event trigger handles
	,-vsml		=>'!'			# var subst mark left
	,-vsmr		=>'!'			# var subst mark right
							# see 'cmsubst', $ENV{SYSMNGELM}, $ENV{SYSMNGLOG}, '<'
	#-dsmd		=>undef			# data store of metadata
	,-target	=>{}			# targets for commands
	,-branch	=>{}			# branch sets for -corder
	#-user		=>{}||sub{}		# user name and password
	#-pswd		=>undef			#	interface
	#-reject	=>undef			# reject command condition
	#-cmdfile	=>undef			# 'cmdfile' object
	,-ping		=>undef		# -g	# ping usage / object
	,-pingprot	=>'icmp'		# ping protocol
	,-pingtime	=>15			# ping timeout
	,-pingcount	=>4			# ping attempt count
	,-assoc		=>{			# associations for script commands
			 '.p'	=>[$^X]
			,'.pl'	=>[$^X]
			,'.plx'	=>['do']
			,'.bat'	=>['cmd.exe','/c']
			,'.cmd'	=>['cmd.exe','/c']
			,'.ftp'	=>sub{['ftp','-n','!elem!','<',$_[1]->[0]]}
				#'.ftp'	=>sub{['ftp','-n','-s:loginfile','!elem!','<',$_[1]->[0]]}
			,'rcmd'	=>['-e', 'Sys::Manage::Conn->connect([@ARGV],-v=>2,-e=>1,-cfg=>1)','!elem!',['!user!:!pswd!']]
				# ['-e' due to 'END{' | 'eval' reducing processes
				# see 'execute': rdo fput fget
			}
	,-ckind		=>'cmd'		# -k	# cmd kind (namespace)
	#-credo		=>''		# -r	# cmd redo id (also in -l) or switch (for -a)
	#-cassign	=>''		# -a	# cmd assignment name (analogous -r)
	#-cloop		=>60*10		# -l	# cmd loop (pause length)
	#-cpause	=>-cloop	# -p	# cmd prestart pause (in -l)
	,-corder	=>'s'		# -o	# cmd order = 's'equental
								# 'c'oncurrent
								# 'b'ranched
	#-cbranch	=>undef		# -b	# cmd order branch name (in -o)
	#-ctarget	=>'all'		# -t	# cmd target(s)
	#-cxtgt		=>[]		# -x	# cmd target exclusions
	#-cignor	=>undef		# -i	# cmd exit code ignoring
	,-cline		=>[]		# ...	# cmd line
	#-cid		=>undef			# cmd result id
	#-cerr		=>undef			# cmd result errors
	, %$s
	);
 $s->set(@_);
 $s
}


sub class {
 substr($_[0], 0, index($_[0],'='))
}


sub set {               # Get/set slots of object
			# ()		-> options
			# (-option)	-> value
			# ( ? [command line], ? -option=>value,...)	-> self
 return(keys(%{$_[0]}))	if (@_ <2);
 return($_[0]->{$_[1]})	if (@_ <3) && !ref($_[1]);
 my($s, $arg, %opt) =ref($_[1]) ? (@_) : ($_[0],undef,@_[1..$#_]);
 if ($opt{-cfg}||$opt{-config}) {
	my $o =$opt{-cfg}||$opt{-config};
	   $o =do{my $v =$s->class; $v=~s/::/-/g; $v .'-cfg.pl'} 
		if $o =~/^.$/i;
	delete $opt{-cfg}; delete $opt{-config};
	foreach my $b ('bin','var','') {
		my $f =$s->{-dirb} .($b ? $s->{-dirm} .$b : '') .$s->{-dirm} .$o;
		next if !-f $f;
		eval{local $_ =$s; do $f; 1}
			|| $s->error("wrong config '$f': $@");
		last
	}
 }
 foreach my $k (keys(%opt)) {
	next if $k !~/^-(?:\w|vt|vc)$/;
	my($n, $v) =($k, $opt{$k});
	$n =	  $n eq '-k'	? '-ckind'
		: $n eq '-a'	? '-cassign'
		: $n eq '-r'	? '-credo'
		: $n eq '-l'	? '-cloop'
		: $n eq '-p'	? '-cpause'
		: $n eq '-o'	? '-corder'
		: $n eq '-b'	? '-cbranch'
		: $n eq '-i'	? '-cignor'
		: $n eq '-t'	? '-ctarget'
		: $n eq '-x'	? '-cxtgt'
		: $n eq '-g'	? '-ping'
		: $n eq '-v'	? '-echo'
		: $n =~/^-vt/	? '-echot'
		: $n;
	delete $opt{$k};
	$opt{$n} =$v
 }
 if ($arg) { for (my $i=0; $i <=$#$arg; $i++) {
	if ($arg->[$i] =~/^-k(.*)$/i) {
		$opt{-ckind} =!defined($1) || ($1 eq '')
				? 'cmd'
				: $1
			if !exists $opt{-ckind};
	}
	elsif ($arg->[$i] =~/^-a(.+)$/i) {
		$opt{-cassign} =$1	if !exists $opt{-cassign}
	}
	elsif ($arg->[$i] =~/^-r(.+)$/i) {
		$opt{-credo} =$1	if !exists $opt{-credo}
	}
	elsif ($arg->[$i] =~/^-l(\d*)$/i) {
		$opt{-cloop} =$1||(60*10)
					if !exists $opt{-cloop}
	}
	elsif ($arg->[$i] =~/^-p(\d*)$/i) {
		$opt{-cpause} =$1||$opt{-cloop}||(60*10)
					if !exists $opt{-cpause}
	}
	elsif ($arg->[$i] =~/^-o(.*)$/i) {
		$opt{-corder} =$1||'s'	if !exists $opt{-corder}
	}
	elsif ($arg->[$i] =~/^-b(.+)$/i) {
		$opt{-cbranch} =$1	if !exists $opt{-cbranch}
	}
	elsif ($arg->[$i] =~/^-i(.*)$/i) {
		$opt{-cignor} =($1 eq '' ? 1 : $1)
				if !exists $opt{-cignor}
	}               
	elsif ($arg->[$i] =~/^-t(.*)$/i) {
		my $v =defined($1) && ($1 ne '') ? $1 : 'all';
		ref($opt{-ctarget})
		? push @{$opt{-ctarget}}, $v
		: exists($opt{-ctarget})
		? do{$opt{-ctarget} =[$opt{-ctarget},$v]}
		: do{$opt{-ctarget} =$v};
	}
	elsif ($arg->[$i] =~/^-x(.*)$/i) {
		my $v =$1||'all';
		ref($opt{-cxtgt})
		? push @{$opt{-cxtgt}}, $v
		: exists($opt{-cxtgt})
		? do{$opt{-cxtgt} =[$opt{-cxtgt},$v]}
		: do{$opt{-cxtgt} =$v};
	}
	elsif ($arg->[$i] =~/^-g(\d*)$/i) {
		my $v =$1;
		$opt{-ping} =1		if !(exists $opt{-ping}) && ($v ne '0');
		$opt{-pingtime} =$v	if !(exists $opt{-pingtime})
								&& $v && ($v >1);
	}
	elsif ($arg->[$i] =~/^-v([\d\w]*)$/i) {
		my $v =$1;
		$opt{-echo} =$v	if !(exists $opt{-echo})  && ($v =~/^\d+$/);
		$opt{-echo} =2	if !(exists $opt{-echo})  && ($v eq '');
		$opt{-echot}=1	if !(exists $opt{-echot}) && ($v =~/^t/i);
	}
	elsif (exists($opt{-ctarget})) {
		$opt{-cline} =[@$arg[$i..$#$arg]]; last;
	}
	else {
		$opt{-ctarget} =$arg->[$i];
		$opt{-cline} =[@$arg[$i+1..$#$arg]]; last;
	}
 }}

 $opt{-ckind} =	  !$opt{-cline}
		? 'cmd'
		: (  $^O eq 'MSWin32'
		   ? scalar(Win32::GetFullPathName($opt{-cline}->[0]))
		   : $opt{-cline}->[0]) =~/[\\\/]lib-([^\\\/]+)[\\\/][^\\\/]+$/i
		? $1
		: 'cmd'
		if defined($opt{-ckind}) && ($opt{-ckind} eq '0');
 $opt{-pingtime} =$opt{-ping} 
	if $opt{-ping} && ($opt{-ping} =~/^\d+$/) && ($opt{-ping} >1);
 if ($opt{-logevt} && !ref($opt{-logevt})) {
	my $logevth =$opt{-logevt};
	$opt{-logevt} =
		  $opt{-logevt} =~/\bSys::Syslog\b/i
		? $s->error("unimplemented '-logevt'=>" .$s->{-logevt})
		: $opt{-logevt} =~/\bopcmsg\b/i
		? sub{my($s,$l,$c,$x)=@_;
			system($logevth
			.' severity='	.(!$x ? 'normal' : 'warning')
			.' application='.$s->{-prgsn}
			.' object='	.$ENV{SMELEM}
			.' node='	.(eval('use Sys::Hostname; Sys::Hostname::hostname()')||'unknown')
			.' msg_grp=OS'
			.' msg_text='	.$s->{-prgsn} .' '
					.$l .' '
					.($x ? 'backlog ' .$x : 'start')
					.': ' .join(' ',@$c)
			)}
		: $opt{-logevt} =~/\bWin32::EventLog\b/i
		? sub{my($s,$l,$c,$x)=@_;
			$s->{-logevth} =eval(
				  $logevth =~/\buse\s/i
				? $logevth
				: $logevth !~/^Win32::EventLog$/i
				? 'use Win32::EventLog; '.$logevth
				: 'use Win32::EventLog; Win32::EventLog->new("Application","' .Win32::NodeName .'")'
					# "Application" only? "Security" debug
					 ) if !$s->{-logevth};
			$s->{-logevth}->Report({''=>''
				#,'Computer' =>$ENV{SMELEM} # target
				#,'Source'=>$s->{-prgsn} .',' .$s->class() # log name
				,'EventType'=>(!$x
						? &Win32::EventLog::EVENTLOG_INFORMATION_TYPE()
						: &Win32::EventLog::EVENTLOG_WARNING_TYPE())
				,'Category'=>0
				,'EventID'=>0
				,'Data'=>''
				,'Strings'=>$s->{-prgsn} .' '
					.$l .' '
					.($x ? 'backlog ' .$x : 'start')
					.': ' .join(' ',@$c) ."\x00"
				});
			# $s->{-logevth}->Close(); $s->{-logevth}=undef;
			}
		: $s->error("bad '-logevt'=>" .$s->{-logevt});
 }
 $opt{-echo} =2 
	if $opt{-echo} && (-echo ==1);
 foreach my $k (keys(%opt)) {
	$s->{$k} =$opt{$k};
 }
 if ($arg && ($s->{-cbranch} || $s->{-cpause})) {
	$s->execute(); exit(0)
 }
 $s
}


sub strtime {		# Log time formatter
	my @t =localtime();
	 join('-', $t[5]+1900, map {length($_)<2 ? "0$_" : $_} $t[4]+1,$t[3]) 
	.' ' 
	.join(':', map {length($_)<2 ? "0$_" : $_} $t[2],$t[1],$t[0])
}


sub qclad {		# Quote command line arg(s) on demand
	map {	# Cmd: The following special characters require quotation marks:
		# & < > [ ] { } ^ = ; ! ' + , ` ~ [white space]
		# Shell: see execvp(3) - for args list processing
		/[&<>\[\]{}^=;!'+,`~\s%"?*|()]/	# ??? see shell
		? do {	my $v =$_; $v =~s/"/\\"/g; '"' .$v .'"' }
		: $_ } @_[1..$#_]
}


sub qclat {		# Quote command line arg(s) totally
	map {	my $v =$_;
		$v =~s/"/\\"/g;
		'"' .$v .'"'
		} @_[1..$#_]
}


sub error {		# Error final
 my $s =$_[0];		# (strings) -> undef
 my $e =join(' ', map {defined($_) ? $_ : 'undef'} @_[1..$#_]);
 eval{STDOUT->flush()};
 $@ =$e;
 $s && $s->{-log} && $s->echolog("Error: $e");
 $@ =$e;
 !$s || ($s->{-error} eq 'die')
 ? croak("Error: $e\n")
 : ($s->{-error} eq 'warn')
 ? carp("Error: $e\n")
 : return(undef);
 return(undef);
}


sub echo {		# Echo message
 print	(($_[0]->{-echot} ? ($_[0]->strtime(), ' ') : ())
	,'$$',($ENV{SMPID} && ($ENV{SMPID} ne $$) ? $ENV{SMPID} .',' : ''), $$
	,' ',@_[1..$#_],"\n")
	if $_[0]->{-echo};
 $_[0]->echolog(@_[1..$#_]) if $_[0]->{-log};
}


sub echolog {		# Echo log message
 if ($_[0]->{-log}) {
	if (!$_[0]->{-logh}) {
		my $s =$_[0];
		$s->{-log} =$s->{-dirb} .$s->{-dirm} .'var' .$s->{-dirm} 
			.$s->{-prgcn} .'-log.txt' if $s->{-log} =~/^\d+$/;
		my $fn =$s->{-log};
		$s->{-logh} =IO::File->new('>>' .$s->{-log})
			|| return($s->error("cannot open '" .$s->{-log} ."': $!"));
	}
	$_[0]->{-logh}->print(
		$_[0]->strtime(),' '
		,$_[0]->{-prgsn}
		,' $$',($ENV{SMPID} && ($ENV{SMPID} ne $$) ? $ENV{SMPID} .',' : ''),$$
		,"\t"
		,@_[1..$#_],"\n");
 }
}


sub fstore {		# Store file
 my $s =shift;		# ('-b',filename, strings) -> success
 my $o =$_[0] =~/^-(?:\w[\w\d+-]*)*$/ ? shift : '-';
 my $f =$_[0]; $f ='>' .$f if $f !~/^[<>]/;
 local *FILE;  open(FILE, $f) || return($s->error("fstore: cannot open '$f': $!"));
 my $r =undef;
 if ($o =~/b/) {
	binmode(FILE);
	$r =defined(syswrite(FILE,$_[1]))
 }
 else {
	$r =print FILE join("\n",@_[1..$#_])
 }
 close(FILE);
 $r || $s->error("fstore: cannot write '$f': $!")
}



sub fload {		# Load file
 my $s =shift;		# ('-b',filename) -> content
 my $o =$_[0] =~/^-(?:\w[\w\d+-]*)*$/ ? shift : '-';
 my($f,$f0) =($_[0],$_[0]); 
	if ($f =~/^[<>]+/)	{$f0 =$'}
	else			{$f  ='<' .$f}
 local *FILE;  open(FILE, $f) || return($s->error("fload: cannot open '$f': $!"));
 my $b =undef;
 binmode(FILE) if $o =~/b/;
 my $r =read(FILE,$b,-s $f0);
 close(FILE);
 defined($r) ? $b : $s->error("fload: cannot read '$f': $!")
}



sub ping {		# Ping object
			# (object) -> success
 return(undef) if !$_[0]->{-ping};
 if(!ref($_[0]->{-ping})) {
	eval('use Net::Ping');
	$_[0]->{-ping} =Net::Ping->new($_[0]->{-pingprot},$_[0]->{-pingtime});
 }
 if ($_[0]->{-pingcount}) {
	for(my $i =0; $i <$_[0]->{-pingcount}; $i++) {
		my $r =$_[0]->{-ping}->ping($_[1]);
		return($r) if !defined($r) || $r;
	}
	return(0)
 }
 else {
	return($_[0]->{-ping}->ping($_[1]))
 }	
}


sub checkbase {		# Check/install base operational environment
 my $s =$_[0];		# () -> self
 if (!$s->{-cbranch} && !$s->{-cpause}) {
	foreach my $d ('var'
			,'log-' .$s->{-ckind}
			, 'lib', 'lib-' .$s->{-ckind}
			# 'bin'
			) {
		my $dir =$s->{-dirb} .$s->{-dirm} .$d;
		next if -d $dir;
		mkdir($dir,0777);
	}
 }
 $s
}


sub vload {   		# Load common variables
 my ($s, $lck) =@_;	# (?LOCK_EX) -> {vars}
 return($s->{-var}) if $s->{-var} && !$lck;
 my $fn =$s->{-dirb} .$s->{-dirm} .'var' .$s->{-dirm} .$s->{-prgcn} .'-var.pl';
 my $hf;
 my $bf;
 if (!-f $fn) {
    $s->{-var} ={};
    $s->vstore();
 }
 if ($hf =IO::File->new('+<' .$fn)) {
	flock($hf,$lck) if $lck;	# LOCK_EX/LOCK_SH
	sysread($hf,$bf,-s $fn);
	my $VAR1;
	$s->{-var} =eval($bf);
	!$lck && close($hf);
	return($s->error("cannot load '$fn': $! $@"))
		if !ref($s->{-var});
	$s->{-varh}=$lck ? $hf : undef;
 }
 else {
	return($s->error("cannot open '$fn': $!"))
 }
 $s->{-var}
}


sub vstore {		# Store common variables
 my $s  =shift;		# (? upd sub{}) -> {vars}
 my $fn =$s->{-dirb} .$s->{-dirm} .'var' .$s->{-dirm} .$s->{-prgcn} .'-var.pl';
 my $hf;
 if ($_[0]) {
	if ($hf =$s->{-varh}) {
		flock($hf, LOCK_UN);
		close($hf);
		$s->{-varh} =undef;
	}
	$s->vload(LOCK_EX);
	$s->{-var} ={} if !$s->{-var};
	&{$_[0]}($s,$s->{-var});
	$hf =$s->{-varh};
 }
 elsif ($s->{-varh}) {
	$hf =$s->{-varh}
 }
 else {
	$hf =IO::File->new('+>' .$fn)
		|| return($s->error("cannot open '$fn': $!"));
	flock($hf,LOCK_EX);
 }
 if ($hf) {
	$s->{-var} ={} if !$s->{-var};
	my $o =Data::Dumper->new([$s->{-var}]); $o->Indent(1);
	my $bf=$o->Dump();
	truncate($hf,0);
	seek($hf,0,0);
	syswrite($hf,$bf) ne length($bf)
	? return($s->error("cannot write '$fn': $!"))
	: 1;
	flock($hf,LOCK_UN);
	close($hf);
	$s->{-varh} =undef;
 }
 $s->{-var};
}



sub padl {		# Padleft string given
			# (sign, length, string) -> padded
 length($_[3]) <$_[2] ? $_[1] x ($_[2] - length($_[3])) . $_[3] : $_[3]
}


sub dwnext {		# Next digit-word string value
			# (string, ? min length) -> next value
 my $v =$_[1] ||'0';
 for(my $i =1; $i <=length($v); $i++) {
	next if ord(substr($v,-$i,1)) >=ord('z');
	substr($v,-$i,1)=chr(ord(substr($v,-$i,1) eq '9' ? chr(ord('a')-1) : substr($v,-$i,1)) +1);
	substr($v,-$i+1)='0' x ($i-1) if $i >1;
	return($_[2] && length($v) <$_[2] ? '0' x ($_[2] -length($v)) .$v : $v)
 }
 $v =chr(ord('0')+1) .('0' x length($v));
 $_[2] && length($v) <$_[2] ? '0' x ($_[2] -length($v)) .$v : $v
}


sub dwprev {		# Previous digit-word string value
 my($s,$v,$l) =@_;	# (string, ? min length) -> prev value
 $v ='z' x ($l ||10) if !$v;
 my $j =length($v)-1;
 my $c =undef;
 for(my $i=$j; $i >=0; $i--) {
	$c =substr($v,$i,1);
	if (ord($c) >ord('a'))		{$c =chr(ord($c)-1)}
	elsif (ord($c) ==ord('a'))	{$c ='9'}
	elsif (ord($c) >ord('0'))	{$c =chr(ord($c)-1)}
	else				{next}
	substr($v,$i,1) =$c;
	substr($v,$i+1,$j-$i) ='z' x ($j-$i) if $i <$j;
	$c =undef;
	last
 }
 $v = 'z' x ($l ||10) if defined($c);
 $v
}


sub cmid {		# New / get command subdirectory
 my $s =$_[0];		# () -> command subdirectory
 return($s->{-credo})	if $s->{-credo} && $s->{-cloop};
 return($s->{-cassign})	if $s->{-cassign};
 return($s->{-credo})	if $s->{-credo} && $s->{-credo} !~/^(?:\+|y|1)$/i;
 my $asc=0;
 my $id =!$s->{-cline}->[0] 
	? ''
	: $s->{-cline}->[0] =~/^(?:do|eval)$/
	? $s->{-cline}->[1]
	: $s->{-cline}->[0];
    $id =!$id
	? ''
	: $id =~/([^\\\/]+)$/
	? $1
	: $id;
    $id =~s/\./-/g;
 if ($asc) {
	0
	? do{$id =$s->padl(0, 10, scalar(time)) .$$ .'-' .$id}
	: $s->vstore(sub{	my $k ='-kind_' .$_[0]->{-ckind};
				$_[1]->{$k} =$s->dwnext($_[1]->{$k}, 10);
				$id =$_[1]->{$k} .'-' .$id})
 }
 else {
	0
	? $id =$s->padl(0, 10, 2**32 -scalar(time)) .$$ .'-' .$id
	: $s->vstore(sub{	my $k ='-kind_' .$_[0]->{-ckind};
				$_[1]->{$k} =$s->dwprev($_[1]->{$k}, 10);
				$id =$_[1]->{$k} .'-' .$id})
 }
 my $lim =$s->{-dirl};		# Log autotruncator
 my $lgd =$s->{-dirb} .$s->{-dirm} .'log-' .$s->{-ckind};
 local *DIR;
 if (opendir(DIR,$lgd)) {
	my @dir =sort {$asc ? lc($b) cmp lc($a) : lc($a) cmp lc($b)
			} map { ($_ eq '') || ($_ eq '.') || ($_ eq '..')
				? ()
				: -d $_
				? $_
				: ()
				} readdir(DIR);
	close(DIR);
	if (@dir >$lim) {
		for (my $i=$lim; $i<=$#dir; $i++) {
			my $t =$lgd .$s->{-dirm} .$dir[$i];
			$s->echo("Deleting:\t'$t'") if $s->{-echo} >1;
			$^O eq 'MSWin32'
			? system('cmd','/c','rmdir','/s','/q',$t)
				# ? system('cmd','/c','del','/f','/s','/q',$t)
			: system('rm','-r','-f',$t);
		}
	}
 }
 $id
}


sub dsmd {		# Data store of metadata
 my $r =$_[0]->{-dsmd}		# (-type) -> [names] | []
 && &{$_[0]->{-dsmd}}(@_);	# (-type, -name) -> [values] | undef
   $r		                # -type: -target, -branch, -user, -pswd, -assoc
 ? $r
 : !$_[0]->{$_[1]}
 ? []
 : $#_ <2
 ? [keys %{$_[0]->{$_[1]}}]
 : ref($_[0]->{$_[1]}) eq 'CODE'
 ? &{$_[0]->{$_[1]}}(@_)
 : $_[0]->{$_[1]}->{$_[2]}
}


sub lffind {		# Lib file find
 my($s,$z,$f) =@_;	# (zip?, file) -> filepath
 return($f) if !defined($f) || ($f eq '');
 if ($z) {
	$z =   ($f=~/[\\\/][^\\\/]+$/ ? $` : undef);
	$z =$z && ($z=~/\.[^.]{1,4}$/ ? $z : undef);
 }
 my $e;
 foreach my $d (  ''
		, $s->{-dirb} .$s->{-dirm} .'lib-' .$s->{-ckind}
		, $s->{-dirb} .$s->{-dirm} .'lib'
		, $s->{-dirb} .$s->{-dirm} .'bin'
		) {
	$e =($d ? $d .$s->{-dirm} : '') .$f;
	return($e) if -f $e;
	$e =($d ? $d .$s->{-dirm} : '') .$z;
	return($e) if -f $e;
 }
 $f
}


sub tgtexpand {		# Expand element using Targets
 my $s =shift;		# (element|[list]) -> [expanded list]
 my %h =();
 [map { $h{$_}
	? () 
	: do{$h{$_}=1; $_}
	} map { my $v =$_;
		my $t =dsmd($s,-target=>$v);
		  $t
		? @{tgtexpand($s,$t)} 
		: ($v)
			} ref($_[0]) 
			? @{$_[0]} 
			: !defined($_[0]) && !$#_ 
			? () 
			: $_[0]]
}


sub istarget {		# Is all targets listed?
 my $s =$_[0];		# (targets possible) -> contains?
 my $cnd =$s->tgtexpand([@_[1..$#_]]);
 my $tgt =$s->{-cxtgt}
	? $s->tgtexpand($s->{-cxtgt})
	: $s->tgtexpand($s->{-ctarget});
    $tgt =[map {my $v =$_;
		!(grep {$v =~/^\Q$_\E$/i} @$tgt)
		? $v
		: ()
		} @{$s->tgtexpand($s->{-ctarget})}]
	if $s->{-cxtgt};
 foreach my $e (@$tgt) {
	next if grep /^\Q$e\E$/i, @$cnd;
	return(undef)
 }
 $s
}


sub isscript {		# Is kind script to be executed
 my $s =shift;		# (?'lib') -> exists?
 my $f =$s->{-cline} && $s->{-cline}->[0];
 return(undef) if !$f;
 foreach my $k ('lib-' .$s->{-ckind}, @_) {
	return($s) if -f (($k	? $s->{-dirb} .$s->{-dirm} .$k 
				: $s->{-dirb})
			.$s->{-dirm} .$f)
 }
 undef
}


sub cmsubst {		# Substitute variables into command/args
 my $m =		# ([cmd], variable name, variable value) -> string
	$_[0]->{-vsml} .$_[2] .$_[0]->{-vsmr};
 my $j =0;
 for(my $i=0; $i <=$#{$_[1]};$i++) {
	if (!ref($_[1]->[$i])) {
		next if $_[1]->[$i] !~/$m/;
		$_[1]->[$i] =~s/$m/ref($_[3]) ? &{$_[3]}($_[0], $`, $') : $_[3]/eg;
		$j +=1;
	}
	else {
		my $y =0;
		my @r =map{ my	$e =$_;
				$y +=($e =~s/$m/ref($_[3]) ? &{$_[3]}($_[0], $`, $') : $_[3]/eg);
				$e
				} @{$_[1]->[$i]};
		if (!$y) {
		}
		elsif ($_[3] ne '') {
			splice @{$_[1]},$i,1,@r;
			$j +=$y
		}
		else {
			splice @{$_[1]},$i,1;
		}
	}
 }
 $j
}


sub cmsubstrdo {	# Substitute 'rdo' file
 my ($s, $c) =@_;	# (command) -> command
 my $o =(($c->[1] ||'') =~/^-/ ? $c->[1] : '');
 my $m =($o =~/e([!@#])/ ? $1 : '!');
 my $j =$o ? 2 : 1;
 for(my $i =0; $i <=$#$c; $i++) {
	next if $c->[$i] ne $m;
	$j =$i+1;
	last
 }
 $c->[$j] =$s->lffind(($o =~/[pz](?![0-])/ ? 1 : 0), $c->[$j])
	if defined($c->[$j]);
 $c;
}


sub execute {		# Execute command (target action)
 my $s =$_[0];		# ( ? [command line], ? -option=>value,...)	-> self
    $s->set(@_[1..$#_]);
    $s->{-cid} =$s->{-cerr} =undef;
    $s->checkbase();
 if (!$s->{-cbranch} && !$s->{-cpause}) {
	$s->echo("Starting:\t"
		, join(' '
			, map { 
				 ref($_) eq 'ARRAY'
				? (map {$_ eq '-k0' 
						? '-k' .$s->{-ckind} 
						: ($s->qclad($_))
						} @$_)
				: ($s->qclad($_))
				} @_[1..$#_])) 
		if !$s->{-echo} ||($s->{-echo} >1)
 }
 elsif ($s->{-cpause} && !$s->{-cbranch}) {
	$s->echo("StartLoop:\t" .$s->{-cloop} .'; '
		, join(' ', $s->qclad(@ARGV))) 
		if !$s->{-echo} ||($s->{-echo} >1);
	eval{STDOUT->flush()};
	sleep($s->{-cloop})
 }
 elsif ($s->{-cbranch}) {
	$s->echolog("StartBranch:\t" .$s->{-cbranch} .'; '
		, join(' ', $s->qclad(@ARGV)));
 }

 if ($s->{-reject}) {				# Check reject condition
	my $r =eval{&{$s->{-reject}}($s)||''};
	$r =$@ if !defined($r);
	return($s->error("reject '$r'")) if $r;
 }

 my $target =$s->tgtexpand($s->{-ctarget});	# Expand Target(s) into elements
	if ($s->{-cxtgt}) {
		my $cxtgt =$s->tgtexpand($s->{-cxtgt});
		$target =[map {	my $v =$_;
				!(grep {$v =~/^\Q$_\E$/i} @$cxtgt)
				? $v
				: ()
				} @$target]
	}
	return($s->error("no command target")) if !@$target;
 $s->echo("Targets:\t" 
	,(ref($s->{-ctarget}) 
		? join(', ', @{$s->{-ctarget}}) 
		: $s->{-ctarget} ), " -> "
	,join(", ", @$target))
	if !$s->{-cbranch} && !$s->{-cpause} && (!$s->{-echo} ||($s->{-echo} >1));

 my $cmd  =[@{$s->{-cline}}];			# Tune Command line
	return($s->error("no command line")) if !$cmd->[0];
	foreach my $k (qw(lcmd rdo ldo fput fget)) {$s->{-assoc}->{$k}=$s->{-assoc}->{'rcmd'}};
	$ENV{SMDIR} =$s->{-dirb};
	$ENV{SMLIB} ='';
	if (($cmd->[0] eq 'rdo') && $s->dsmd(-assoc=>'rdo')) {
		$s->cmsubstrdo($cmd)
	}
	elsif (($cmd->[0] eq 'ldo') && $s->dsmd(-assoc=>'ldo')) {
		$s->cmsubstrdo($cmd)
	}
	elsif (!$s->dsmd(-assoc=>lc($cmd->[0]))) {
		$cmd->[0] =$s->lffind(0,$cmd->[0]);
		$ENV{SMLIB} =$cmd->[0] =~/[\\\/][^\\\/]+$/ 
			? $` 
			: $^O eq 'MSWin32' 
			? scalar(Win32::GetFullPathName('.'))
			: '.';
	}
 $s->echo("Command:\t"
	,join(' ', $s->qclad(@{$s->{-cline}})), " -> "
	,join(' ', $s->qclad(@$cmd)))
	if !$s->{-cbranch} && !$s->{-cpause} && (!$s->{-echo} ||($s->{-echo} >1));

 eval('use Sys::Manage::CmdEscort; 1')		# Set Command Environment
	|| return($s->error("no Sys::Manage::CmdEscort"));
 my $cid =$s->{-cid} =$s->cmid();
 my $dir =$s->{-dirb} .$s->{-dirm} .'log-' .$s->{-ckind} .$s->{-dirm} .$cid;
 mkdir($dir,0777) if !-d $dir;
 $s->echo("Logging:\t" 
	,"$cid -> $dir")
	if !$s->{-cbranch} && !$s->{-cpause} && (!$s->{-echo} ||($s->{-echo} >1));

 my $cms =$target;				# Branch Command
 my $order =$s->{-corder};
 if ($order eq 'b') {
	my $branch =$s->{-cbranch};
	my @brtgt  =();
	my $brcnt  =0;
	if (!defined($branch) || ($branch eq '')) {
		@brtgt	=sort {lc($a) cmp lc($b)} @{$s->dsmd('-branch')};
		$branch	=shift @brtgt;
		$ENV{SMPID} =$$;
	}
	foreach my $b (@brtgt) {
		my $brexp =$s->tgtexpand($s->dsmd(-branch=>$b));
		$cms =[ map {	my $v =$_;
				((grep /^\Q$v\E$/i, @$brexp)
				? ()
				: ($v))	} @$cms];
		my $brdo;
		foreach my $eb (@$brexp) {
			if (grep /^\Q$eb\E$/i,@$target) {
				$brdo =1;
				last;
			}
		}
		next if !$brdo;
		$brcnt +=1;
		my @arg =($0
			,"-b$b", "-ob", ('-k' .$s->{-ckind})
			,($s->{-cassign} ? ('-a' .$s->{-cassign}) : ("-r$cid"))
			,(ref($s->{-ctarget}) ? map {"-t$_"} @{$s->{-ctarget}} : ('-t' .$s->{-ctarget}))
			,(ref($s->{-cxtgt}) ? map {"-x$_"} @{$s->{-cxtgt}} : defined($s->{-cxtgt}) ? ('-t' .$s->{-cxtgt}) :())
			,($s->{-cignor} ? '-i' : ())
			,($s->{-ping} ? ('-g' .$s->{-pingtime}) : ())
			,($s->{-echo} !=2 ? '-v' .($s->{-echo}||0) : ())
			,($s->{-echot} ? '-vt' : ())
			,@{$s->{-cline}});
		$s->echo("Branching:\t"
			,join(' ', $s->qclad(@arg))) 
			if !$s->{-echo} ||($s->{-echo} >1);
		system(1, $^X, ($0 =~/\.(?:bat|cmd)$/i ? ('-x','-S') : ()), $s->qclat(@arg));
	}
	$order ='s' if scalar(@brtgt) && !$brcnt;
	if (!scalar(@brtgt)) {
		my $brexp  =$s->tgtexpand($s->dsmd(-branch=>$branch));
		$cms =[ map {	my $v =$_;
				((grep /^\Q$v\E$/i, @$brexp)
				? ($v)
				: ())	} @$cms];
	}
	$target =$cms if $s->{-cbranch};
 }
 else {
 	$ENV{SMPID} =$$;
 }	

 foreach my $e (@$cms) {			# Execute Commands on Targets
	my $fn =$dir .$s->{-dirm} .$e;
	next if -e "${fn}-run.txt" || -e "${fn}-ok.txt";
	if (-e "${fn}-err.txt") {
		if ($s->{-credo} || $s->{-loop}) {
			unlink("${fn}-err.txt")
		}
		else {
			next
		}
	}
	if ($s->{-ping}) {		# pinging
		$s->fstore("${fn}-go.txt"
			,join("\t",$s->strtime()
				,'[' .($ENV{SMPID}||$$) .",$$]"
				,$s->class().'::ping'),"\n");
		my $r =$s->ping($e);
		if (!defined($r)) {
			$s->fstore("${fn}-err.txt"
				,join("\t",$s->strtime()
				,'[' .($ENV{SMPID}||$$) .",$$]"
				,$s->class() .'::ping'
				,!defined($r) ? 'undef' : $r),"\n");
			unlink("${fn}-go.txt");
		}
		next if !$r;
		unlink("${fn}-go.txt")
	}
	elsif (-e "${fn}-go.txt") {
		unlink("${fn}-go.txt")
	}

	my $cme =[@$cmd];		# associations & substitutions
	{	if (($cme->[0]=~/\.rdo(?:\.\w+){0,1}$/i)
		&& $s->dsmd(-assoc=>'rdo')) {
			unshift @$cme, 'rdo'
		}
		elsif (($cme->[0]=~/\.ldo(?:\.\w+){0,1}$/i)
		&& $s->dsmd(-assoc=>'ldo')) {
			unshift @$cme, 'ldo'
		}
		my $a =$s->dsmd(-assoc=>lc($cme->[0]))
			|| (($cme->[0] =~/([^\\\/]+)$/)
				&& $s->dsmd(-assoc=>lc($1)))
			|| (($cme->[0] =~/(\.[^\\\/.]+)$/)
				&& $s->dsmd(-assoc=>lc($1)));
		$ENV{SMELEM} =$e;
		$ENV{SMLOG}  =$fn;
		my $u =$s->dsmd(-user=>$e);
		my $p =ref($u) ? $u->[1] : $s->dsmd(-pswd=>$e);
		   $u =ref($u) ? $u->[0] : $u;
		   $u ='' if !defined($u);
		   $p ='' if !defined($p);
		$ENV{SMUSER} =$u;
		$ENV{SMPSWD} =$p;
		if (!$a || !$a->[0]) {
		}
		elsif (ref($a) eq 'CODE') {
			$cme =&$a($s,$cme,$fn,$e,$u,$p);
		}
		else {
			unshift @$cme, @$a
		}
		$s->cmsubst($cme, '(elem|host|node)', $e);
		$s->cmsubst($cme, '(log)', $fn);
		$s->cmsubst($cme, '(user)', $u);
		$s->cmsubst($cme, '(pswd|passwd|password)', $p);
	}

					# logging command to object
	$s->{-log} && $s->echolog("$fn = ",join(' ', $s->qclad(@$cme)));
	$s->{-logevt} && &{$s->{-logevt}}($s, $fn, $cme, '');

	if ($order =~/[s]/) {	# start types
		eval{Sys::Manage::CmdEscort::CmdEscort([$fn, @$cme]
		,-i=>$s->{-cignor},-v=>$s->{-echo},-vt=>$s->{-echot}); 1}
		;#||warn("Error: Sys::Manage::CmdEscort::CmdEscort: $@\n");
	}
	if ($order =~/[b]/) {
		eval{Sys::Manage::CmdEscort::CmdEscort([$fn, @$cme]
		,-i=>$s->{-cignor},-v=>$s->{-echo},-vt=>$s->{-echot},-vc=>1); 1}
		;#||warn("Error: Sys::Manage::CmdEscort::CmdEscort: $@\n");
	}
	elsif ($order =~/[c]/) {
		$ENV{SMPID} =$$;
		system(	 1	# [IPC::Open3] 1 == P_NOWAIT
			,$^X
			,'-e"use Sys::Manage::CmdEscort; CmdEscort([@ARGV]'
				.($s->{-cignor} ? ',-i=>1' : '')
				.(',-v=>' .$s->{-echo}||0)
				.($s->{-echot} ? ',-vt=>1' : '')
				.(',-vc=>1')
				.')"'
			,$s->qclat($fn, @$cme)
			)
	}
 }

 if (($order =~/[sc]/)			# Reap/wait child processes
 ||  (!$s->{-cbranch} && ($order =~/[b]/))){
	while (waitpid(-1,0) >=0) {} # wait() >=0
 }

 my $errc =[];					# Count errors
 if (!$s->{-cbranch}) {
	foreach my $e (@$target) {
		my $fn =$dir .$s->{-dirm} .$e;
		$ENV{SMELEM} =$e;
		$ENV{SMLOG}  =$fn;
		if    (-e "${fn}-ok.txt") {
		}
		elsif (-e "${fn}-err.txt") {
			$errc->[0] =($errc->[0]||0) +1;
			$s->{-logevt} && &{$s->{-logevt}}($s, $fn, $cmd, 'err');
		}
		elsif (-e "${fn}-run.txt") {
			$errc->[1] =($errc->[1]||0) +1;
			$s->{-logevt} && &{$s->{-logevt}}($s, $fn, $cmd, 'run');
		}
		else {
			$errc->[2] =($errc->[2]||0) +1;
			$s->{-logevt} && &{$s->{-logevt}}($s, $fn, $cmd, 'exit');
		}
	}
 }
 if (@$errc) {
	$s->{-cerr} =$errc;
	$s->echo("Backlogs:\t"
		, join(', '
		, ($errc->[0] ? $errc->[0] .' exited'	: ())
		, ($errc->[1] ? $errc->[1] .' running'	: ())
		, ($errc->[2] ? $errc->[2] .' missed'	: ())))
 }
 else {
	$s->{-cerr} =undef;
	$s->echo("Backlogs:\tOk") if !$s->{-cbranch};
 }
 if ($s->{-cloop} && @$errc) {			# Loop rerun
	my @arg =($0
		,('-l' .$s->{-cloop})
		,($s->{-cpause} ? ('-p' .$s->{-cpause}) : ('-p1'))
		,('-o' .$s->{-corder})
		,('-k' .$s->{-ckind})
		,($s->{-cassign} ? ('-a' .$s->{-cassign}) : ("-r$cid"))
		,(ref($s->{-ctarget}) ? map {"-t$_"} @{$s->{-ctarget}} : ('-t' .$s->{-ctarget}))
		,(ref($s->{-cxtgt}) ? map {"-x$_"} @{$s->{-cxtgt}} : defined($s->{-cxtgt}) ? ('-t' .$s->{-cxtgt}) :())
		,($s->{-cignor} ? '-i' : ())
		,($s->{-ping} ? ('-g' .$s->{-pingtime}) : ())
		,($s->{-echo} !=2 ? '-v' .($s->{-echo}||0) : ())
		,($s->{-echot} ? '-vt' : ())
		,@{$s->{-cline}});
	$s->echo("Looping:\t", join(' ', $s->qclad(@arg)))
		if !$s->{-echo} ||($s->{-echo} >1);
	$SIG{CHLD} ='IGNORE';
	system(1, $^X, ($0 =~/\.(?:bat|cmd)$/i ? ('-x','-S') : ()), $s->qclat(@arg));
 }
 !$s->{-cerr}
}


sub cmdfile {	# Shift command file
 $_[0]->{-cmdfile} =eval('use Sys::Manage::CmdFile; Sys::Manage::CmdFile->new()')
	if !$_[0]->{-cmdfile};
 $_[0]->{-cmdfile}->dofile(@_[1..$#_])
}