#!perl -w
#
# Sys::Manage::Cmd - Systems management command volley
#
# makarow, 2005-09-09
#
# !!! ??? see in source code.
# ??? switch on var files fault tolerance?
# ??? ejecting logfiles?
#

package Sys::Manage::Cmd;
require 5.000;
use strict;
use UNIVERSAL;
use Carp;
use IO::File;
use Fcntl qw(:DEFAULT :flock :seek :mode);
use POSIX qw(:sys_wait_h);
use Data::Dumper;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
$VERSION = '0.62';

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
	#,-runmod	=>undef			# run mode, for logging
	#-config	=>undef			# config use, '-cfg' also
	,-error		=>'die'			# error handler

	,-echo		=>2		# -v	# echo verbosity switches
					# -vct	# ... commands, time including
	,-echol		=>2		# -v#	# ... verbosity level
	,-log		=>undef			# log file name
	#-logh					# log file handler
	#-autoflush	=>undef			# autoflush
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
			,'rcmd'	=>['-e', 'Sys::Manage::Conn->connect([@ARGV],-v=>2,-e=>1,-cfg=>1,-esc=>1)','!elem!',['!user!:!pswd!']]
				# ['-e' due to 'END{' | 'eval' reducing processes
				# see 'execute': rdo fput fget
			}

	#-var		=>{}			# persistent variables
	#-varh		=>undef			# persistent variables file handle
	#-vgxi		=>undef		# -gx	# go-exclude init flag
	#-vgxf		=>undef		#	# go-exclude file name
	#-vgxv		=>undef			# go-exclude hash of targets

	,-ckind		=>'cmd'		# -k	# cmd kind (namespace)
	#-credo		=>''		# -r	# cmd redo id (also in -l) or switch (for -a)
	#-cassign	=>''		# -a	# cmd assignment name (analogous -r)
	#-cloop		=>60*10		# -l	# cmd loop (pause length)
					# -lg -le		# pings/errs
	#-cpause	=>undef		# -p	# cmd prestart pause (in -l)
	,-corder	=>'s'		# -o	# cmd order = 's'equental
								# 'c'oncurrent
								# 'b'ranched
	#-cbranch	=>undef		# -b	# cmd order branch name (in -o)
	#-ctarget	=>'all'		# -t	# cmd target(s)
	#-cxtgt		=>[]		# -x	# cmd target exclusions
	#-cuser		=>undef		# -u	# cmd user:password
	#-cignor	=>undef		# -i	# cmd exit code ignoring
	#-esc		=>undef		# -esc	# cmd line escaped
	,-cline		=>[]		# ...	# cmd line
	#-cid		=>undef			# cmd result id
	#-cerr		=>undef			# cmd result errors
	, %$s
	);
 $s->set(@_);
 $s
}


sub daemonize {		# Daemonize process
 my $s =$_[0];
 my $null =$^O eq 'MSWin32' ? 'nul' : '/dev/null';
 open(STDIN,  "$null")  || return($s->error($$,'','',"daemonize(STDIN) -> $!")); 
 open(STDOUT,">$null")  || return($s->error($$,'','',"daemonize(STDOUT) -> $!"));
 eval("use POSIX 'setsid'; setsid()");
 open(STDERR,'>&STDOUT')|| return($s->error($$,'','',"daemonize(STDERR) -> $!"));
 $s
}


sub DESTROY {
 my $s =$_[0];
 $s->vgxf('d') if $s->{-vgxi};
 $s->echowr($$,'End' .($s->{-runmod}||''), '',$?) if $s->{-runmod};
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
			|| return($s->error($$,'','',"wrong config '$f': $@"));
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
		: $n eq '-u'	? '-cuser'
		: $n eq '-g'	? '-ping'
		: $n eq '-gx'	? (!$v || ($v=~/^[\d\w]$/i) ? '-vgxi' : '-vgxf')
		: $n eq '-v'	? '-echo'
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
	elsif ($arg->[$i] =~/^-l([\d\w]*)$/i) {
		my $v =defined($1) && ($1 ne '') ? $1 : '';
		   $v =$v .(60*10) if $v !~/\d/;
		$opt{-cloop} =$v
					if !exists $opt{-cloop}
	}
	elsif ($arg->[$i] =~/^-p(\d*)$/i) {
		$opt{-cpause} =$1||1
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
	elsif ($arg->[$i] =~/^-u(.*)$/i) {
		$opt{-cuser} =$1	if $1 && !exists $opt{-cuser}
	}
	elsif ($arg->[$i] =~/^-g(\d*)$/i) {
		my $v =$1;
		$opt{-ping} =1		if !(exists $opt{-ping}) && ($v ne '0');
		$opt{-pingtime} =$v	if !(exists $opt{-pingtime})
								&& $v && ($v >1);
	}
	elsif ($arg->[$i] =~/^-gx(.*)$/i) {
		my $v =$1;
		$opt{-vgxi} =1		if !$v && !exists($opt{-vgxi});
		$opt{-vgxf} =$v		if $v  && ($v !~/^[\d\w]$/)
					&& !exists($opt{-vgxf});
	}
	elsif ($arg->[$i] =~/^-v([\d\w]*)$/i) {
		my $v =$1;
		   $v =''	if !defined($v);
		   $v .=2	if $v !~/\d/;		
		$opt{-echo} =$v	if !(exists $opt{-echo});
		$opt{-echol}=$v =~/(\d+)/ ? $1 : 2;
	}
	elsif ($arg->[$i] =~/^-esc/i) {
		$opt{-esc} =1;
	}
	elsif (exists($opt{-ctarget})) {
		$opt{-cline} =[$opt{-esc} ? $s->qclau(@$arg[$i..$#$arg]) : @$arg[$i..$#$arg]]; 
		last;
	}
	else {
		$opt{-ctarget} =$arg->[$i];
		$opt{-cline} =[$opt{-esc} ? $s->qclau(@$arg[$i+1..$#$arg]) : @$arg[$i+1..$#$arg]];
		last;
	}
 }}

 $opt{-echol} =$opt{-echo} =~/(\d+)/ ? $1 : 2
		if $opt{-echo};
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
		? return($s->error($$,'','',"unimplemented '-logevt'=>" .$s->{-logevt}))
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
		: return($s->error($$,'','',"bad '-logevt'=>" .$s->{-logevt}));
 }
 $opt{-vgxf} =($opt{-prgcn} ||$s->{-prgcn})
	.'-' .time() .'-' .$$ .'-vgx.pl'
	if $opt{-vgxi} && !$opt{-vgxf};
 foreach my $k (keys(%opt)) {
	$s->{$k} =$opt{$k};
 }
 if ($arg && ($s->{-cbranch} || $s->{-cpause})) {
	$s->execute(); exit(0)
 }
 $s
}


sub strtime {		# Log time formatter
	my @t =defined($_[1]) ? localtime($_[1]) : localtime();
	 join('-', $t[5]+1900, map {length($_)<2 ? "0$_" : $_} $t[4]+1,$t[3]) 
	.' ' 
	.join(':', map {length($_)<2 ? "0$_" : $_} $t[2],$t[1],$t[0])
}


sub qclad {		# Quote command line arg(s) on demand
	map {	# Cmd: The following special characters require quotation marks:
		# & < > [ ] { } ^ = ; ! ' + , ` ~ [white space]
		# Shell: see execvp(3) - for args list processing
		!defined($_) || ($_ eq '')
		? qclat($_[0], $_)
		: /[&<>\[\]{}^=;!'+,`~\s%"?*|()]/	# ??? see shell
		? qclat($_[0], $_)
		: $_ } @_[1..$#_]
}


sub qclat {		# Quote command line arg(s) totally
	map {	my $v =defined($_) ? $_ : '';
		$v =~s/"/\\"/g;				# ??? perl specific
		$v =~s/\\$/\\\\/;
		'"' .$v .'"'
		} @_[1..$#_]
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


sub qclauw {	# UnEscape command line wholly, preserving -options
	my $k;
 	map {	my $v =defined($_) ? $_ : '';
		$k =0 if $v eq '-esc';
		$k =1 if ($v !~/^-/) && !$k && defined($k);
		$v =~s/_([0-9a-fA-F]{2})/chr hex($1)/ge	if $k;
		$v eq '-esc'
		? $v # ()
		: $v
		} @_[1..$#_]
}



sub autoflush {		# set autoflush
 my $s =$_[0];
 return($s->{-autoflush}) if !defined($_[1]);
 my @f =(select(), do{select(STDERR); $|}, do{select(STDOUT); $|});
 select(STDERR); $|=$s->{-autoflush};
 select(STDOUT); $|=$s->{-autoflush};
 $s->{-logh}->autoflush($s->{-autoflush}) if $s->{-logh};
 select($f[0]);
}


sub flush {		# Flush STDOUT/STDERR
 eval('use IO::File; STDOUT->flush(); STDERR->flush()');
 $_[0]->{-logh} && $_[0]->{-logh}->flush();
 1
}


sub echomap {		# Map echo args to print/write
 return(('[', $_[1]||$$, ']: '
	, $_[2] ||''
	, $_[3] && ($_[3] =~/^\d+$/) ? ('[', $_[3], ']: ') : $_[2] ? (': ', $_[3]||'') : ($_[3]||'')
	, @_[4..$#_]
	))
}


sub echo {		# Echo to stdout
	print(!$#_ ? () : ($_[0]->{-echo} =~/t/ ? strtime($_[0]) .' ' : '', echomap(@_)), "\n")
		if $_[0]->{-echol}
}


sub echowr {		# Echo to log
 if ($_[0]->{-log}) {
	if (!$_[0]->{-logh}) {
		my $s =$_[0];
		$s->{-log} =$s->{-dirb} .$s->{-dirm} .'var' .$s->{-dirm} 
			.$s->{-prgcn} .'-log.txt' if $s->{-log} =~/^\d+$/;
		my $fn =$s->{-log};
		$s->{-logh} =IO::File->new('>>' .$s->{-log})
			|| return($s->error($$,'','',"cannot open '" .$s->{-log} ."': $!"));
	}
	$_[0]->{-logh}->print(!$#_ ? () : (strtime($_[0]),' ',echomap(@_)),"\n")
 }
}


sub echowrf {		# Echo to log force
 echowr(@_)
}


sub echolog {		# Echo + log
 echo(@_); echowr(@_)
}


sub warning {		# Echo Warning
 my @a =($_[0], $_[1]||$$, $_[2] ||'Warning', @_[3..$#_]);
 echowrf(@a); carp(join('', echomap(@a)) ."\n")
}


sub error {		# Error finish
 flush(@_);
 my @a =($_[0], $_[1]||$$, $_[2] ||'Error', @_[3..$#_]);
 echowrf(@a);
 !$_[0] || ($_[0]->{-error} eq 'die')
 ? croak(join('', echomap(@a),"\n"))
 : ($_[0]->{-error} eq 'warn')
 ? carp(join('', echomap(@a),"\n"))
 : return(undef);
 return(undef);
}


sub logask {		# Echo log query
 my $s =shift;		# (-opt, start, end, on row, on end)
			# >, >=, <, <=, 'v'erbose, 's'calar
			# 'pid's, 'err'ors, 'all'
 my $o =$_[0] && (($_[0] eq '-') || ($_[0] =~/^-[^\d]/i)) ? shift : '-v';
 my $ds=$_[0] && ($_[0] =~/^[-\d]/) ? shift : undef;
 my $de=$_[0] && ($_[0] =~/^[-\d]/) ? shift : undef;
 my $q0=shift ||'all';
 my $q1= $q0;
 my $q2= shift;
 my $ll='';
 my $rr='';
 my ($id, %rq, $rq);
 local $_;
 return(undef) if !$s->{-log};
 $s->{-log} =$s->{-dirb} .$s->{-dirm} .'var' .$s->{-dirm} 
	.$s->{-prgcn} .'-log.txt' 
	if $s->{-log} =~/^\d+$/;
 my $fh =IO::File->new('<' .$s->{-log})
	|| return($s->error($$,'','',"cannot open '" .$s->{-log} ."': $!"));
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
 if (ref($q1)) {}
 elsif ($q1 =~/^all/i) {
	$q1 =sub{1}
 }
 elsif ($q1 =~/^pid/i) {
	$rq=join("\n"
		,map {/perl/i ? $_ : ()
			} split /[\r\n]+/, ($^O eq 'MSWin32' ? (`tlist 2>nul` ||`tasklist 2>nul` || '') : `ps 2>nul`));
	$q1=sub{if (/^\d{2,4}-\d\d-\d\d\s+\d\d:\d\d:\d\d\s+\[(\d+)\]/){
			my $id =$1;
			if (/[\]:]\s+(?:End|Exit)\w*[\[:]/i) {
				delete $rq{$id}
			}
			elsif ($rq !~/\b\Q$id\E\b/) {
			}
			elsif (!$rq{$id}) {
				$rq{$id} =$_
			}
			elsif (/[\]:]\s+(?:Start\w*)[\[:]/i) {
				$rq{$id} =$_
			}
			elsif (/[\]:]\s+(?:Logging)[\[:]/) {
				$rq{$id} .=$_ if $rq{$id}
			}
		}; ''};
	$q2 =sub{join('', map {	my $v =$rq{$_};
				if ($v =~/Logging:\s[^\r\n>]+->\s*([^\r\n\s]+)/) {
					foreach my $f (glob($1 .$s->{-dirm} .'*.txt')) {
						next if $f !~/-(?:run|go).txt$/i;
						$v .=$s->strtime((stat($f))[10]) ." $f\n";
						$v .=(eval{$s->fload('-',$f)}) ||'';
					}
				}
				$v ."\n"
				} sort {$rq{$a} cmp $rq{$b}} keys %rq)
		};
 }
 elsif ($q1 =~/^err/) {
	$q1=sub{if (/^\d{2,4}-\d\d-\d\d\s+\d\d:\d\d:\d\d\s+\[(\d+)\]/){
			$id =$1;
			if (/[\]:]\s+(?:End|Exit)\w*[\[:]/i) {
				if (/\b(?:Error|Exit\w*:\s+[1-9]+|End\w*:\s+[1-9])\b/i) {
					$_[1] =$rq{$id} .$_[1] if $rq{$id};
					delete $rq{$id};
					return($_[1])
				}
				else {
					delete $rq{$id};
					return('')
				}
				delete $rq{$id}
			}
			elsif (!$rq{$id}) {
				$rq{$id} =$_
			}
			elsif (/[\]:]\s+(?:Start\w*)[\[:]/i) {
				$rq{$id} =$_;
			}
			elsif (/[\]:]\s+(?:Logging)[\[:]/) {
				$rq{$id} .=$_ if $rq{$id};
			}
		}
		if (/\b(?:Error|CmdExcess|Exit\w*:\s+[1-9]+|Backlogs:\s+[1-9]+)\b/i) {
			$_[1] =$rq{$id} .$_[1] if $id && $rq{$id} && $_[1] ne $rq{$id};
			delete $rq{$id};
			return($_[1])
		} 0};
 }
 else {
	my $q0 =$q1; $q0 =~s/\\/\\\\/g; $q0 =eval("sub{$q0}");
	$q1=sub{if (/^\d{2,4}-\d\d-\d\d\s+\d\d:\d\d:\d\d\s+\[(\d+)\]/) {
			$id =$1;
			if (/[\]:]\s+(?:End|Exit)\w*[\[:]/i) {
				if (&$q0(@_)) {
					$_[1] =$rq{$id} .$_[1] if $rq{$id};
					delete $rq{$id};
					return($_[1])
				}
				else {
					delete $rq{$id};
					return('')
				}
			}
			elsif (!$rq{$id}) {
				$rq{$id} =$_
			}
			elsif (/[\]:]\s+(?:Start\w*)[\[:]/i) {
				$rq{$id} =$_;
			}
			elsif (/[\]:]\s+(?:Logging)[\[:]/) {
				$rq{$id} .=$_ if $rq{$id};
			}
		}
		if (&$q0(@_)) {
			$_[1] =$rq{$id} .$_[1] if $id && $rq{$id} && $_[1] ne $rq{$id};
			delete $rq{$id};
			return($_[1])
		} 0};
 }
 if (!$ds) {}
 elsif (($o =~/>/) && ($o !~/>=/)) {
	while (defined($ll =readline($fh))) {
		next	if $ll !~/^\d\d\d\d-\d\d-\d\d/;
		last	if $ll gt $ds;
	}
 }
 else {
	while (defined($ll =readline($fh))) {
		next	if $ll !~/^\d\d\d\d-\d\d-\d\d/;
		last	if $ll ge $ds;
	}
 }
 while (defined($ll)) {
	last	if $ll !~/^\d\d\d\d-\d\d-\d\d\s/
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
	$ll =readline($fh);
 }
 if ($q2) {
	my $r =&$q2($s, $rr);
	print $r	if $o =~/v/;
	$rr =$r		if $o =~/s/;
 }
 close($fh);
 $rr
}


sub regask {		# Registrations query
 my $s =shift;		# (-opt, start, end, on row, on end)
			# >, >=, <, <=, 'v'erbose, 's'calar
			# 'pid's, 'err'ors, 'dir's, 'all'
 my $o =$_[0] && (($_[0] eq '-') || ($_[0] =~/^-[^\d]/i)) ? shift : '-v';
 my $ds=$_[0] && ($_[0] =~/^[-\d]/) ? shift : undef;
 my $de=$_[0] && ($_[0] =~/^[-\d]/) ? shift : undef;
 my $q0=shift ||'dirs';
 my $q1=$q0;
 my $q2=shift;
 my $rr='';
 local $_;
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
 if (ref($q1)) {}
 elsif ($q1 =~/^all/i) {
	$q1 =sub{1};
 }
 elsif ($q1 =~/^dir/i) {
	$q1 =sub{1};
 }
 elsif ($q1 =~/^pid/i) {
	$q1 =sub{/-(?:go|run)\.txt$/i};
 }
 elsif ($q1 =~/^err/i) {
	$q1 =sub{/-(?:erg|err)\.txt$/i};
 }
 else {
	$q1 =~s/\\/\\\\/g;
	$q1 =eval("sub{$q1}");
 }
 local(*DIRB, *DIRK, *DIRC);
 my $dirk=$s->{-dirb};
 opendir(DIRB,$dirk)
	||return($s->error($$,'','',"cannot open '$dirk': $!"));
 foreach $dirk (sort {lc($a) cmp lc($b)} readdir(DIRB)) {
	next if $dirk !~ /^log-/i;
	my $dirr =$s->{-dirb} .$s->{-dirm} .$dirk;
	next if !-d $dirr;
	opendir(DIRK, $dirr)
		||return($s->error($$,'','',"cannot open '$dirr': $!"));
	while (defined($dirr =readdir(DIRK))) {
		next if ($dirr eq '.') || ($dirr eq '..');
		my $dirn =$s->{-dirb} .$s->{-dirm} .$dirk .$s->{-dirm} .$dirr;
		next if !-d $dirn;
		my @stat =stat($dirn);
		next if $ds && ($s->strtime($stat[9]) lt $ds);
		next if $de && ($s->strtime($stat[9]) gt $de);
		if ($q0 =~/^dir/i) {
			my $ll =$s->strtime($stat[9])
				.' '
				.$dirk .$s->{-dirm} .$dirr
				."\n";
			$rr .=$ll	if !$q2 && ($o =~/s/);
			print $ll	if !$q2 && ($o =~/v/);
			next
		}
		opendir(DIRC, $dirn)
			||return($s->error($$,'','',"cannot open '$dirn': $!"));
		while (defined($dirn =readdir(DIRC))) {
		# foreach $dirn (sort {lc($a) cmp lc($b)} readdir(DIRC)) {
			next if ($dirn eq '.') || ($dirn eq '..');
			my $dirf =$s->{-dirb} .$s->{-dirm} .$dirk .$s->{-dirm} .$dirr .$s->{-dirm} .$dirn;
			next if !&$q1($s, $rr, $dirk, $dirr, $dirn, $_ =$dirf);
			@stat =stat($dirf);
			my $ll =$s->strtime($stat[9])
				.' '
				.$dirk .$s->{-dirm} .$dirr .$s->{-dirm} .$dirn
				."\n";
			$rr .=$ll	if !$q2 && ($o =~/s/);
			print $ll	if !$q2 && ($o =~/v/);
		}
		eval{close(DIRC)};
	}
	eval{close(DIRK)};
 }
 eval{close(DIRB)};
 if ($q2) {
	my $r =&$q2($s, $_ =$rr);
	$rr =$r;
	print $rr	if $o =~/v/;
 }
 $rr
}


sub fstore {		# Store file
 my $s =shift;		# ('-b',filename, strings) -> success
 my $o =$_[0] =~/^-(?:\w[\w\d+-]*)*$/ ? shift : '-';
 my $f =$_[0]; $f ='>' .$f if $f !~/^[<>]/;
 local *FILE;  open(FILE, $f) || return($s->error($$,'','',"fstore: cannot open '$f': $!"));
 my $r =undef;
 if ($o =~/b/) {
	binmode(FILE);
	$r =defined(syswrite(FILE,$_[1]))
 }
 else {
	$r =print FILE join("\n",@_[1..$#_])
 }
 close(FILE);
 $r || $s->error($$,'','',"fstore: cannot write '$f': $!")
}



sub fload {		# Load file
 my $s =shift;		# ('-b',filename) -> content
 my $o =$_[0] =~/^-(?:\w[\w\d+-]*)*$/ ? shift : '-';
 my($f,$f0) =($_[0],$_[0]); 
	if ($f =~/^[<>]+/)	{$f0 =$'}
	else			{$f  ='<' .$f}
 local *FILE;  open(FILE, $f) || return($s->error($$,'','',"fload: cannot open '$f': $!"));
 my $b =undef;
 binmode(FILE) if $o =~/b/;
 my $r =read(FILE,$b,-s $f0);
 close(FILE);
 defined($r) ? $b : $s->error($$,'','',"fload: cannot read '$f': $!")
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
	return(undef)
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
 my $ft ='';	# $fn .'.tmp';	# ??? fault tolerance off
 my $hf;
 my $bf;
 if (!-f $fn) {
    $s->{-var} ={};
    $s->vstore();
 }
 if ($hf =IO::File->new('+<' .$fn)) {
	flock($hf,$lck) if $lck;	# LOCK_EX/LOCK_SH
	sysread($hf,$bf,-s $fn);
	if ($ft && -f $ft) {$bf =$s->fload($ft)}
	my $VAR1;
	$s->{-var} =eval($bf);
	!$lck && close($hf);
	return($s->error($$,'','',"cannot load '$fn': $! $@"))
		if !ref($s->{-var});
	$s->{-varh}=$lck ? $hf : undef;
 }
 else {
	return($s->error($$,'','',"cannot open '$fn': $!"))
 }
 $s->{-var}
}


sub vstore {		# Store common variables
 my $s  =shift;		# (? upd sub{}) -> {vars}
 my $fn =$s->{-dirb} .$s->{-dirm} .'var' .$s->{-dirm} .$s->{-prgcn} .'-var.pl';
 my $ft ='';	# $fn .'.tmp';	# ??? fault tolerance off
 my $hf;
 if ($_[0]) {
	if ($hf =$s->{-varh}) {
		flock($hf, LOCK_UN |LOCK_NB);
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
		|| return($s->error($$,'','',"cannot open '$fn': $!"));
	flock($hf,LOCK_EX);
 }
 if ($hf) {
	$s->{-var} ={} if !$s->{-var};
	my $o =Data::Dumper->new([$s->{-var}]); $o->Indent(1);
	my $bf=$o->Dump();
	if ($ft) {$s->fstore($ft .'.tmp', $bf); rename($ft .'.tmp', $ft)};
	sysseek($hf, 0, 0);
	syswrite($hf,$bf) ne length($bf)
	? return($s->error($$,'','',"cannot write '$fn': $!"))
	: 1;
	truncate($hf,sysseek($hf, 0, 1));
	flock($hf,LOCK_UN |LOCK_NB);
	close($hf);
	if ($ft) {unlink($ft)};
	$s->{-varh} =undef;
 }
 $s->{-var};
}


sub vgxf {		# Control go-exclude targets file
 my ($s,$o) =@_;	# ('l'|'s'|'d')
 return(undef) if !$s->{-vgxf};
 my $f =$s->{-dirb} .$s->{-dirm} .'var' .$s->{-dirm} .$s->{-vgxf};
 if ($o eq 'l') {	# load
	my $v =-f $f ? $s->fload($f) : undef;
	my $VAR1;
	$s->{-vgxv} =$v ? eval($v) : {}
 }
 elsif ($o eq 's') {	# store
	my $o =Data::Dumper->new([$s->{-vgxv}||{}]); $o->Indent(1);
	my $v =$o->Dump();
	$s->fstore($f, $v)
 }
 elsif ($o eq 'd') {	# delete
	delete $s->{-vgxi};
	delete $s->{-vgxf};
	delete $s->{-vgxv};
	unlink($f)
 }
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
    $id =~s/[^\w\d_]/-/g;
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
				: -d ($lgd .$s->{-dirm} .$_)
				? $_
				: ()
				} readdir(DIR);
	close(DIR);
	if (@dir >$lim) {
		for (my $i=$lim; $i<=$#dir; $i++) {
			my $t =$lgd .$s->{-dirm} .$dir[$i];
			$s->echolog($$,'Deleting','',$t) if $s->{-echol} >1;
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



sub execute {		# Execute command (target action) with current options
 my $s =$_[0];		# ( ? [command line], ? -option=>value,...) -> success
    $s->set(@_[1..$#_]);
    $s->{-cid} =$s->{-cerr} =undef;
    $s->checkbase();
 my $esc =$s->{-esc} ||1; # internal cmd line escaping: 0 - off, 1 - on
 return $s->logask('pids')
	if ref($_[1]) && (($_[1]->[0] ||'') eq 'cmdstat') && ($#{$_[1]} ==0);
 return $s->logask(@{$_[1]}[1..$#{$_[1]}])
	if ref($_[1]) && (($_[1]->[0] ||'') eq 'logask');
 return $s->regask(@{$_[1]}[1..$#{$_[1]}])
	if ref($_[1]) && (($_[1]->[0] ||'') eq 'regask');
 if (!$s->{-cbranch} && !$s->{-cpause}) {
	$s->{-runmod} ='Cmd';
	&{$s->{-echol} >1 ? \&echolog : \&echowr}($s,$$
		,"StartCmd",$ENV{SMPID}
		, join(' '
			, map {
				 ref($_) eq 'ARRAY'
				? (map {$_ eq '-k0' 
					? '-k' .$s->{-ckind}
					: $_ =~/^(-u[^:]*):/
					? $1
					: ($s->qclad($_))
					} @$_)
				: $_ =~/^(-u[^:]*)/
				? ($s->qclad($1))
				: ($s->qclad($_))
				} @_[1..$#_]));
 }
 elsif ($s->{-cpause} && !$s->{-cbranch}) {
	$s->daemonize()	if $s->{-cloop} 
			&& ($s->{-cloop} !~/[vw]/)
			&& ($^O ne 'MSWin32');
	$ENV{SMPID} ='';
	$s->{-runmod} ='Loop';
	&{$s->{-echol} >1 ? \&echolog : \&echowr}($s,$$
		,'StartLoop','', $s->{-cloop} .' # '
		, join(' ', &{$esc ? \&qclauw : \&qclad}($s
			,map {	$_ =~/^(-u[^:]*):/
				? $1
				: $_
				} @ARGV
			)));
	eval{STDOUT->flush()};
	sleep($s->{-cloop} =~/(\d+)/ ? $1 || (60*10) : (60*10))
 }
 elsif ($s->{-cbranch}) {
	$s->{-runmod} ='Branch';
	$s->echowr($$,"StartBranch",$ENV{SMPID}, $s->{-cbranch} .' # '
		, join(' ', &{$esc ? \&qclauw : \&qclad}($s
			,map {	$_ =~/^(-u[^:]*):/
				? $1
				: $_
				} @ARGV
			)));
 }

 if ($s->{-reject}) {				# Check reject condition
	my $r =eval{&{$s->{-reject}}($s)||''};
	$r =$@ if !defined($r);
	return($s->error($$,'','',"reject '$r'")) if $r;
 }

 if (('cmdfile' eq lc($s->{-cline}->[0]||0))	# Command file processing
 ||  ('cmdfile' eq lc((ref($s->{-ctarget}) ? $s->{-ctarget}->[0] : $s->{-ctarget})||0))) {
	my $cmd =[@{$s->{-cline}}];
	   $cmd ='cmdfile' eq lc($cmd->[0])
		? [@$cmd[1..$#$cmd]]
		: $cmd;
	$s->{-cerr} =[];
	$ENV{SMPID} =$$;
	if ($cmd->[0] =~/\.(?:pl|p)$/) {
		my $r =eval{	local $_ =$s;
				local @ARGV =@$cmd[1..$#$cmd];
				do $cmd->[0]};
		$s->{-cerr}->[0] =1 if !$r;
		return($r);
	}
	else {
		$s->{-cmdfile}=eval('use Sys::Manage::CmdFile; Sys::Manage::CmdFile->new()')
			if !$s->{-cmdfile};
		my $e =0;
		my $r =$s->{-cmdfile}
			->dofile(sub {
			my @arg=($s->qclad($^X)
				,($0 =~/\.(?:bat|cmd)$/i ? ('-x') : ())
				,$s->qclad($0)
				,($s->{-ping} ?	('-g' .$s->{-pingtime})	: ())
				,($s->{-vgxf} ?	('-gx' .$s->{-vgxf}) : ())
				,($s->{-echo} ? ('-v' .$s->{-echo}) : ())
				,$_);
			local $s->{-echol} =$s->{-echo} =~/c/ ? $s->{-echol} ||1 : $s->{-echol};
			$s->echolog($$,'CmdPick', '', join(' ', @arg) ,' (', $cmd->[0],')')
				if $s->{-echo} =~/c/;
			$s->fstore('-',	'>>' .$_[1]
				, $s->strtime() ." [$$]: "
				. "CmdPick: "
				. join(' ', @arg)
				. "\n")
				if $_[1];
			if (system(join(' ', @arg)) !=-1) {
				# cmdfile direct parsing is difficult due to
				#	loops and command string parsing.
				$e +=$?>>8 ? 1 : 0;
				$s->echolog($$,'CmdExit', '', ($?>>8), ' (' .join(' ', @arg) .')')
					if $s->{-echo} =~/c/;
			}
			else {
				$e +=1;
				$s->echolog($$,'Error','',$!,' # ',join(' ', @arg));
				die("Error: $! # " .join(' ', @arg));
				return(undef)
			}
			}, @$cmd);

		$s->vgxf('l') if $e && $s->{-vgxf} && $s->{-vgxi};
		$s->echolog($$
			, $s->{-cmdfile}->{-retexc}
			? ("CmdExcess", '', $s->{-cmdfile}->{-retexc},' # ',join(' ','cmdfile',@$cmd))
			: ("Backlogs", '', $e||'Ok'
				#, ($s->{-vgxv} && scalar(%{$s->{-vgxv}}) ? ', skipped: ' .join(', ', sort keys %{$s->{-vgxv}}) : ())
				," # ",join(' ', 'cmdfile', @$cmd)));
		$s->{-cerr}->[0] =$e if $e;
		return(!$e && $r);
	}
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
	return($s->error($$,'','',"no command target")) if !@$target;
 $s->echolog($$,'Targets','' 
	,(ref($s->{-ctarget}) 
		? join(', ', @{$s->{-ctarget}}) 
		: $s->{-ctarget} ), " -> "
	,join(", ", @$target))
	if !$s->{-cbranch} && !$s->{-cpause} 
	&& ($s->{-echol} >1);

 my $cmd  =[@{$s->{-cline}}];			# Tune Command line
	return($s->error($$,'','',"no command line")) if !$cmd->[0];
	foreach my $k (qw(lcmd rdo ldo fput fget mput mget)) {
		$s->{-assoc}->{$k}=$s->{-assoc}->{'rcmd'}
	}
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
 $s->echolog($$,'Command',''
	,join(' ', $s->qclad(@{$s->{-cline}})), " -> "
	,join(' ', $s->qclad(@$cmd)))
	if !$s->{-cbranch} && !$s->{-cpause} 
	&& ($s->{-echol} >1);

 eval('use Sys::Manage::CmdEscort; 1')		# Set Command Environment
	|| return($s->error($$,'','',"no Sys::Manage::CmdEscort"));
 $s->vgxf('l') if $s->{-vgxf};
 my $cid =$s->{-cid} =$s->cmid();
 my $dir =$s->{-dirb} .$s->{-dirm} .'log-' .$s->{-ckind};
    mkdir($dir,0777) if !-d $dir;
    $dir =$dir .$s->{-dirm} .$cid;
    mkdir($dir,0777) if !-d $dir;
 &{$s->{-echol} >1 ? \&echolog : \&echowr}($s, $$
 	,'Logging',''
	,"$cid -> $dir")
	if !$s->{-cbranch};

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
			,(ref($s->{-cxtgt}) ? map {"-x$_"} @{$s->{-cxtgt}} : defined($s->{-cxtgt}) ? ('-x' .$s->{-cxtgt}) :())
			,($s->{-cignor} ? '-i' : ())
			,($s->{-vgxf} ? ('-gx' .$s->{-vgxf}) : ())
			,($s->{-ping} ? ('-g' .$s->{-pingtime}) : ())
			,($s->{-echo} ? ('-v' .$s->{-echo}) : ())
			,($esc ? '-esc' : ())
			);
		$s->echolog($$,'Branching',''
			,join(' ', $s->qclad(@arg,@{$s->{-cline}}))) 
			if $s->{-echol} >1;
		(system(1, $s->qclad($^X)
			, ($0 =~/\.(?:bat|cmd)$/i ? ('-x') : ())
			, $s->qclad(@arg)
			, $esc ? $s->qclae(@{$s->{-cline}}) : $s->qclad(@{$s->{-cline}})
			) == -1)
		&& return($s->error($$,'','',"system(Branching) -> $!"));
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
	next if $s->{-vgxv} && $s->{-vgxv}->{$e};
	if (-e "${fn}-err.txt") {
		if ($s->{-credo} 
		|| ($s->{-cloop} && ($s->{-cloop} !~/g/))) {
			unlink("${fn}-err.txt")
		}
		else {
			next
		}
	}
	if (-e "${fn}-erg.txt") {
		unlink("${fn}-erg.txt")
	}
	if ($s->{-ping}) {		# pinging
		$s->fstore("${fn}-go.txt"
			,join(" ", $s->strtime()
				,"[$$]"
				,$s->class().'::ping'
				.($ENV{SMPID} && ($ENV{SMPID} ne $$) ? "[$ENV{SMPID}]:" : ':')
				,map {defined($s->{$_})
					? ($_ .'=' .$s->{$_})
					: ($_ .'=undef')
					} qw(-pingprot -pingtime -pingcount))
				,"\n");
		my $r =$s->ping($e);
		if (!defined($r)) {
			rename("${fn}-go.txt", "${fn}-erg.txt")
			||return($s->error($$,'','',"rename(", "${fn}-go.txt"
				,",", "${fn}-erg.txt", ") -> $!"));
			next
		}
	}
	if (-e "${fn}-go.txt") {
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

		my $u =   !$s->{-cuser}
			? $s->dsmd(-user=>$e)
			: $s->{-cuser} =~/^([^:]+):(.*)/
			? [$1,$2]
			: [$s->{-cuser},''];
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
		$s->cmsubst($cme, '(user)', $u);
		$s->cmsubst($cme, '(pswd|passwd|password)', $p);
		$s->cmsubst($cme, '(elem|host|node|target)', $e);
		$s->cmsubst($cme, '(log)', $fn);
	}

					# logging command to object
	$s->{-logevt} && &{$s->{-logevt}}($s, $fn, $cme, '');

	if ($order =~/[s]/) {	# start types
		# $s->echowr($$,'','',"$fn = ",join(' ', $s->qclad(@$cme)));
		eval{Sys::Manage::CmdEscort::CmdEscort([$fn, @$cme]
		,-i=>$s->{-cignor}
		,-v=>$s->{-echol} .($s->{-echo} =~/([t])/ ? $1 : '')); 1}
		#||$s->echowr($$,'Error','',"eval(Sys::Manage::CmdEscort::CmdEscort) -> $@\n")
		||return($s->error($$,'','',"system(Sys::Manage::CmdEscort::CmdEscort) -> $!"))
	}
	if ($order =~/[b]/) {
		$ENV{SMPID} =$$;
		eval{Sys::Manage::CmdEscort::CmdEscort([$fn, @$cme]
		,-i=>$s->{-cignor}
		,-v=>$s->{-echol} .($s->{-echo} =~/([t])/ ? $1 : '') .'c'); 1}
		#||$s->echowr($$,'Error','',"eval(Sys::Manage::CmdEscort::CmdEscort) -> $@\n")
		||return($s->error($$,'','',"system(Sys::Manage::CmdEscort::CmdEscort) -> $!"))
	}
	elsif ($order =~/[c]/) {
		$ENV{SMPID} =$$;
		my $pid =system( 1	# [IPC::Open3] 1 == P_NOWAIT
			,$s->qclad($^X)
			,'-e"use Sys::Manage::CmdEscort; CmdEscort([@ARGV]'
				.($s->{-cignor} ? ',-i=>1' : '')
				.(',-v=>\'' .$s->{-echol} .($s->{-echo} =~/([t])/ ? $1 : '') .'c\'')
				.($esc ? ',-esc=>1' : '')
				.')"'
			,$s->qclat($fn)
			,$esc ? $s->qclae(@$cme) : $s->qclat(@$cme)
			);
		return($s->error($$,'','',"system(CmdEscort) -> $!"))
			if $pid ==-1;
	}
 }

 if (($order =~/[sc]/)			# Reap/wait child processes
 ||  (!$s->{-cbranch} && ($order =~/[b]/))){
	while (waitpid(-1,0) !=-1) {} # wait() >=0 # WNOHANG
 }

 my $errc =[];					# Count errors
 my $errl =0;
 if (!$s->{-cbranch}) {
	foreach my $e (@$target) {
		my $fn =$dir .$s->{-dirm} .$e;
		$ENV{SMELEM} =$e;
		$ENV{SMLOG}  =$fn;
		if    (-e "${fn}-ok.txt") {
		}
		elsif (-e "${fn}-err.txt") {
			$errc->[0]	 =($errc->[0]||0) +1;
			$errl		+=1	if $s->{-cloop} 
						&& ($s->{-cloop} !~/g/);
			$s->{-vgxv}->{$e}=1	if $s->{-vgxv};
			$s->{-logevt} && &{$s->{-logevt}}($s, $fn, $cmd, 'err');
		}
		elsif (-e "${fn}-erg.txt") {
			$errc->[0]	 =($errc->[0]||0) +1;
			$errl		+=1;
			$s->{-vgxv}->{$e}=1	if $s->{-vgxv};
		}
		elsif ( (-e "${fn}-run.txt")
		||	(-e "${fn}-go.txt")) {
			$errc->[1] =($errc->[1]||0) +1;
			$s->{-vgxv}->{$e} =1	if $s->{-vgxv};
			$s->{-logevt} && &{$s->{-logevt}}($s, $fn, $cmd, 'run');
		}
		elsif ($s->{-vgxv} && $s->{-vgxv}->{$e}) {
			$s->fstore("${fn}-erg.txt"
				,join(" ",$s->strtime()
				,"[$$]"
				,$s->class() .'::gx'
				.($ENV{SMPID} && ($ENV{SMPID} ne $$) ? "[$ENV{SMPID}]:" : ':')
				,'skiped/excluded formerly'), "\n")
		}
		else {
			$errc->[2]	 =($errc->[2]||0) +1;
			$errl		+=1;
			$s->{-vgxv}->{$e}=1	if $s->{-vgxv};
			$s->{-logevt} && &{$s->{-logevt}}($s, $fn, $cmd, 'exit');
		}
	}
 }
 if (@$errc) {
	$s->{-cerr} =$errc;
	$s->vgxf('s') if $s->{-vgxf} && !$s->{-cpause};
	$s->echolog($$,'Backlogs',''
		, join(', '
		, ($errc->[0] ? $errc->[0] .' exited'	: ())
		, ($errc->[1] ? $errc->[1] .' running'	: ())
		, ($errc->[2] ? $errc->[2] .' missed'	: ())
		#, (($s->{-vgxi}||($s->{-echol}>1)) && $s->{-vgxv} && scalar(%{$s->{-vgxv}}) ? 'skipped: ' .join(', ', sort keys %{$s->{-vgxv}}) : ())
		))
 }
 else {
	$s->{-cerr} =undef;
	$s->echolog($$,'Backlogs',''
		,join(', ', 'Ok'
		#, (($s->{-vgxi}||($s->{-echol}>1)) && $s->{-vgxv} && scalar(%{$s->{-vgxv}}) ? 'skipped: ' .join(', ', sort keys %{$s->{-vgxv}}) : ())
		))
		if !$s->{-cbranch};
 }
 if ($s->{-cloop} && $errl) {			# Loop rerun
	my @arg =($0
		,('-l' .$s->{-cloop})
		,($s->{-cpause} ? ('-p' .$s->{-cpause}) : ('-p1'))
		,('-o' .$s->{-corder})
		,('-k' .$s->{-ckind})
		,($s->{-cassign} ? ('-a' .$s->{-cassign}) : ("-r$cid"))
		,(ref($s->{-ctarget}) ? map {"-t$_"} @{$s->{-ctarget}} : ('-t' .$s->{-ctarget}))
		,(ref($s->{-cxtgt}) ? map {"-x$_"} @{$s->{-cxtgt}} : defined($s->{-cxtgt}) ? ('-x' .$s->{-cxtgt}) :())
		,($s->{-cignor} ? '-i' : ())
		,($s->{-ping} ? ('-g' .$s->{-pingtime}) : ())
		,($s->{-echo} ? ('-v' .$s->{-echo}) : ())
		,($esc ? '-esc' : ())
		);
	$s->echolog($$,'Looping','', join(' ', $s->qclad(@arg,@{$s->{-cline}})))
		if $s->{-echol} >1;
	if (($^O eq 'MSWin32') && ($s->{-cloop} !~/v/)) {
		eval('use Win32::Process');
		Win32::Process::Create($Win32::Process::Create::ProcessObj
			, $^X	||$Win32::Process::Create::ProcessObj
			, join(' '
				, $s->qclad($^X)
				, ($0 =~/\.(?:bat|cmd)$/i ? ('-x') : ())
				, $s->qclat(@arg)
				, $esc ? $s->qclae(@{$s->{-cline}}) : $s->qclat(@{$s->{-cline}})
				)
			, 0
			, ($s->{-cloop} =~/w/) || 1
			? &CREATE_NEW_CONSOLE : &CREATE_NEW_PROCESS_GROUP
			, '.')
		|| return($s->error($$,'','',"system(Looping) -> $!"));
			# ??? IPC::Open3 fails with DETACHED_PROCESS;
			# use CREATE_NEW_CONSOLE better CREATE_NEW_PROCESS_GROUP
			# with 'daemonize' also.
	}
	else {
		$SIG{CHLD} ='IGNORE';
		(system(1, $s->qclad($^X)
			, ($0 =~/\.(?:bat|cmd)$/i ? ('-x') : ())
			, $s->qclat(@arg)
			, $esc ? $s->qclae(@{$s->{-cline}}) : $s->qclat(@{$s->{-cline}})
			) ==-1)
		&& return($s->error($$,'','',"system(Looping) -> $!"));
	}
 }
 !$s->{-cerr}
}


sub cmd {		# Execute command (target action) given
 my $s =shift;		# (execute args) -> success
 foreach my $k (qw(-credo -cassign -cloop -cpause -cbranch -ctarget -cxtgt -cuser -cignor -esc -cline)) {
	# not reset input:  -ckind -corder
	# not reset output: -cid   -cerr
	delete $s->{$k}
 }
 $s->execute(@_)
}
