#!perl -w
#
# Sys::Manage::Conn - Connection to remote Perl
#
# makarow, 2005-09-19
#
#
# !!! ??? see in source code.
# ??? interactive to user commands.
# ??? do not use -b- option due to incorrect file sizing.
# ??? uniqueness of -mark, concepts of '-mark' and 'eval'.
#

package Sys::Manage::Conn;
require 5.000;
use strict;
use Carp;
use IO::Handle;
use IO::Socket;
use IO::Select;
use Safe;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
$VERSION = '0.51';

my $qlcl =0;	# quoting local args not needed because of shell quoting

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
	,-title		=>'Remote command stream'
	,-dirm		=>do{$0 =~/([\\\/])/	# directory marker
			? $1
			: $^O eq 'MSWin32'
			? '\\'
			: '/'}
	,-dirw		=>do{$^O eq 'MSWin32'	# directory working
			? Win32::GetCwd()
			: eval('use Cwd; Cwd::getcwd')}
	,-tmp		=>''			# temporary name (below)
	,-prgcn		=>do{			# program common name
			  $0 eq '-e'
			? do{my $v =$s->class; $v=~s/::/-/g; $v}
			: $0 =~/([^\\\/]+?)(?:\.\w+){0,1}$/
			? $1
			: $0}
	,-time		=>time()		# obj run time
	,-argv		=>[]			# script args (after parse)
	#-exec		=>undef		# -e	# execute '-argv'
	,-debug		=>0		# -d	# debug prompt
	,-echo		=>0		# -v	# echo level: 1+cmd, 2+out, 3+in
	,-progress	=>1			# echo progress indicator
	,-error		=>'die'			# error proc: 'die','warn',false
	,-pack		=>'zip'			# archiver to pack
	#-packx		=>undef			# archiver to unpack
	,-node		=>($^O eq 'MSWin32'	# agent node
			? Win32::NodeName()
			: 'localhost')
	,-port		=>'8008'		# agent port
	,-user		=>''			# agent user
	,-pswd		=>''			# agent password
	,-init		=>($^O eq 'MSWin32'	# init method: wmi, rsh, telnet
			? 'wmi'
			: 'rsh')
	,-timeout	=>undef			# operation timeout
	,-chkip		=>			# check IP, for security
			eval{join('.',unpack('C4',[gethostbyname(
				$^O eq 'MSWin32' 
				? Win32::NodeName() 
				: eval('use Sys::Hostname; Sys::Hostname::hostname')
				)]->[4]))}
	,-perl		=>'perl'		# agent perl path
	#-wmi		=>undef			# WMI connection
	#-wmiph		=>undef			# WMI Win32_Process
	#-wmipid	=>undef			# WMI process id
	#-asrc		=>[]			# agent perl source (see below)
	#-asaw		=>undef			# agent addition written flag
	,-mark		=>'----ret$?$!$@: '	# agent output mark
	,-agent		=>undef			# agent IO::Socket::INET
	,-select	=>undef			# agent IO::Select
	,-errchild	=>0 			# getret() $?	-> $?
	,-errexit	=>0			# getret() $?>>8
	,-erros		=>''			# getret() $!
	,-erros1	=>''			# getret() $^E
	,-erreval	=>''			# getret() $@	-> $@
	,-reteval	=>undef			# getret() result
	,-rxpnd0	=>''			# rxpnd() default command
	,-rxpnd1	=>''			# rxpnd() default options
	, %$s
	);
 $s->{-tmp} =($ENV{TEMP}||$ENV{TMP}||'c:') 
		.$s->{-dirm} .$s->{-prgcn} .'-' .$s->{-time} .'-' .$$;
 $s->set(@_);
 $s
}


sub class {
 substr($_[0], 0, index($_[0],'='))
}


#sub DESTROY {
# my $s =$_[0];
# print $s->strtime(), ' ', $s->class(), " Done([$$]).\n" if $s->{-echo};
#}


sub set {               # Get/set slots of object
			# ()		-> options
			# (-option)	-> value
			# ( ? [command line], ? -option=>value,...)	-> self
 return(keys(%{$_[0]}))	if (@_ <2);
 return($_[0]->{$_[1]})	if (@_ <3) && !ref($_[1]);
 my($s, $arg, %opt) =ref($_[1]) ? @_ : ($_[0],undef,@_[1..$#_]);
 if ($opt{-cfg}||$opt{-config}) {
	my $o =$opt{-cfg}||$opt{-config};
	   $o =do{my $v =$s->class; $v=~s/::/-/g; $v .'-cfg.pl'} 
		if $o =~/^.$/i;
	my $dirb =$ENV{SMDIR}
		? $ENV{SMDIR}
		: $0 eq '-e'
		? $s->error('-cfg: cannot determine base path')
		: do {	my $v =$^O eq 'MSWin32' ? scalar(Win32::GetFullPathName($0)) : $0;
			  $v !~/[\\\/]/
			? (-d './var' ? '.' : -d '../var' ? '..' : '.')
			: $v =~/(?:[\\\/]bin){0,1}[\\\/][^\\\/]+$/i
			? $`
			: '.'
			};
	delete $opt{-cfg}; delete $opt{-config};
	foreach my $b ('bin','var','') {
		my $f =$dirb .($b ? $s->{-dirm} .$b : '') .$s->{-dirm} .$o;
		next if !-f $f;
		eval{local $_ =$s; do $f; 1}
			|| $s->error("-cfg: wrong '$f': $@");
		last
	}
 }
 if (exists($opt{-verbose}))	{$opt{-echo} =$opt{-verbose}; delete $opt{-verbose}}
 if (exists($opt{-v}))		{$opt{-echo} =$opt{-v};	delete $opt{-v}}
 if (exists($opt{-d}))		{$opt{-debug}=$opt{-d};	delete $opt{-d}}
 if (exists($opt{-e}))		{$opt{-exec} =$opt{-e};	delete $opt{-e}}
 if ($arg) {
	$s->{-argv} =$arg;
	if ($arg->[0] && ($arg->[0]=~/^-(?:\w[\w\d]*)*$/)) {
		my $o =shift @$arg;
		$opt{-debug} =1 if $o =~/d/;
		if ($o =~/v/) {
			$opt{-echo} =	  $o =~/v(\d)/
					? $1
					: 2
		}
		if ($o =~/e(?![01+-])/) {
			$opt{-exec} =1;
			$opt{-echo} =2 if $o !~/v/;
		}
	}
	if ($arg->[0] && ($arg->[0]=~/^([^:]+):(.+)/)) {
		$opt{-node} =$1;
		$opt{-port} =$2;
		shift @$arg;
	}
	elsif ($arg->[0]) {
		$opt{-node} =$arg->[0];
		shift @$arg;
	}
	elsif (!$arg->[0]) {
		$opt{-node} =$arg->[0] if defined($arg->[0]) && ($arg->[0] ne '');
		shift @$arg;
	}
	if ($arg->[0] && ($arg->[0]=~/^([^:]+):(.+)/)) {
		$opt{-user} =$1;
		$opt{-pswd} =$2;
		shift @$arg;
	}
	elsif (!$arg->[0]) {
		shift @$arg;
	}

 }
 $opt{-node} =$^O eq 'MSWin32' ? Win32::NodeName() : 'localhost'
		if exists($opt{-node}) && !$opt{-node};
 $opt{-echo} =3 if $opt{-debug};
 foreach my $k (keys(%opt)) {
	$s->{$k} =$opt{$k};
 }
 $s
}


sub isqclad {		# May need shell quote command line arg???
	$_[1] =~/[&<>\[\]{}^=;!'+,`~\s%"?*|()]/
}


sub qclad {		# Quote command line arg(s) on demand
	map {	!defined($_) || ($_ eq '')
		? '""'
		: isqclad($_[0],$_)
		? do {	my $v =$_; $v =~s/"/\\"/g; '"' .$v .'"' }
		: $_ } @_[1..$#_]
}


sub qclat {		# Quote command line arg(s) totally
	map {	my $v =defined($_) ? $_ : '';
		$v =~s/"/\\"/g;
		'"' .$v .'"'
		} @_[1..$#_]
}


sub error {		# Error final
 my $s =$_[0];		# (strings) -> undef
 $@ =join(' ',map {defined($_) ? $_ : 'undef'} @_[1..$#_]);
 STDOUT->flush();
 my $t =time() -$s->{-time}; $t =$t ? ' ' .$t .'s' : '';
 !$s || ($s->{-error} eq 'die')
 ? croak("[error$t] $@\n")
#? confess("[error$t] $@\n")
 : ($s->{-error} eq 'warn')
 ? carp("[error$t] $@\n")
 : return(undef);
 return(undef);
}


sub echo {		# Echo printout
 my $s =shift;		# (item, others)
# print(  ($_[0] =~/^\n+$/ ? shift : ())
#	, $s->strtime(), ' '
#	,($_[0] ? ('[',shift,'] ') : '')
#	, @_);
 my $t =time() -$s->{-time};
 print(  ($_[0] =~/^\n+$/ ? shift : ())
	,($_[0] ? ('[',shift, ($t ? (' ', $t,'s') : ()), '] ') : '')
	, @_);
 STDOUT->flush(); STDERR->flush();	
}


sub oleerr {		# OLE error message
	(Win32::OLE->LastError()||'undef') 
	.' ' 
	.(Win32::OLE->LastError() && Win32::FormatMessage(Win32::OLE->LastError()) ||'undef');
}


sub wmi {		# WMI connection
   !$_[1] 		# (?obect) -> object
 ? $_[0]->{-wmi}
 : ($_[0]->{-wmi}->Get($_[1])
	|| return($_[0]->error('WMI->Get:',$_[1],':',$_[0]->oleerr()))
	)
}


sub wmiph {		# WMI Win32_Process object
	$_[0]->{-wmiph}
}


sub strtime {		# Log time formatter
	my @t =localtime();
	 join('-', $t[5]+1900, map {length($_)<2 ? "0$_" : $_} $t[4]+1,$t[3]) 
	.' ' 
	.join(':', map {length($_)<2 ? "0$_" : $_} $t[2],$t[1],$t[0])
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


sub disconnect {	# Disconnect agent
 my $s=$_[0];		# () -> self
 delete $s->{''};
 eval{$s->{-agent}->close()} if $s->{-agent};
 if ($s->{-wmipid}) {
	my $o =$s->{-wmi}->Get('Win32_Process.ProcessId=' .$s->{-wmipid});
	eval{$o->Terminate()} if $o
 }
 foreach my $k (qw(-wmipid -agent -select -asaw)) {
	delete $s->{$k}
 }
 $s
}


sub agtsrc {		# Agent source
 my($s,$f) =@_;		# (?separate file)
 #use IO::Socket; my($m_,$r_); $r_=IO::Socket::INET->new(LocalPort=>8081,Listen=>1); $m_=$r_->accept(); $r_->close; open(STDERR, '>&STDOUT'); open(STDOUT, '>&' .$m_->fileno); eval $m_->getline if $m_->peerhost() eq '127.0.0.1'
 #use IO::Socket; my($m_,$r_); $r_=IO::Socket::INET->new(LocalPort=>8081,Listen=>1); $m_=$r_->accept(); $r_->close; if($m_->peerhost eq '127.0.0.1'){my $r_; while(defined($r_=$m_->getline)){$m_->printflush($r_)}}
 my $r ='use IO::Socket;'
 .(!$f		? ''
		: "my(\$m_,\$r_,\$p_);\n")
 .'$r_=IO::Socket::INET->new(LocalPort=>' .$s->{-port}
 .($s->{-timeout} ? ',Timeout=>' .$s->{-timeout} : '')
 .',Reuse=>1,Listen=>1);'
 .(!$f		?('$m_=$r_->accept();$r_->close;')
  : $f eq 'l'	?("\n\$m_=\$r_->accept();\$r_->close;\$r_=undef;\$p_=system(1,\$^X,\$0);\n")
    		:("\nwhile(\$m_=\$r_->accept()){\$SIG{CHLD}='IGNORE';\n"
		 .'if($^O eq "MSWin32"){eval("use Win32::Process");$r_->close();$r_=undef;' ."\n"
		 .'Win32::Process::Create($Win32::Process::Create::ProcessObj'
		 .',$^X||$Win32::Process::Create::ProcessObj'
		 .', join(" ",$^X, ($0 =~/\.(?:bat|cmd)$/i ?("-x") :()), $0)'
		 .', 0, &CREATE_NEW_PROCESS_GROUP, ".");' ."\n"
		 .'forked();exit(0)}' ."\n"
		 .'elsif(!defined($p_=fork())){die()}'
		 .'elsif(!$p_){forked();exit(0)}'
		 .'elsif($^O eq "MSWin32"){waitpid($p_,0)}'
		 ."else{}\n}\n"
		 ."sub forked{\$SIG{CHLD}='DEFAULT'; my(\$r_,\$t_);\n"))
 .($s->{-chkip} && !$s->{-debug} 
	? 'die if $m_->peerhost ne \'' .$s->{-chkip} .'\';' 
	 .($f ? "\n" : '')
	: '')
 .'while(defined($r_=$m_->getline)){$@=undef;$r_=eval $r_;'
 .($f ? "\n" : '')
 .'$m_->printflush("\\n'
 .do{my	$v =$s->{-mark};
	$v =~s/([\$\@\\])/\\$1/g;
	$v}
 .'$?\\t$!\\t$^E\\t$@\\t$r_\\n")'
 .(!$f		? '}'
  : $f eq 'l'	? '}'
		: "\n}\$m_->close}");
 $r =~s/(["])/\\$1/g if !$f;
 $r
}


sub agtfile {		# Agent source write
 my $s =shift;	# (?"-'?",filename) -> success
 my $o =$_[0] =~/^-(?:\w[\w\d+-]*)*$/ ? shift : '-';
 my $f =shift;
 if ($qlcl && ($o !~/'/)) {
	$f =~s/([\\"])/\\$1/g;
	$f =eval('"' .$f .'"');
 }
 my $r =$s->lfwrite('-b+', $f, $s->agtsrc('f'));
 if ($r && $o =~/l(?![0-])/) {
	(0 && ($^O eq 'MSWin32') && eval('Win32::IsWin95()')
	? eval('use Win32::Process; 1')	# ??? may be wrong
		&& ($Win32::Process::Create::ProcessObj ||1)
		&& Win32::Process::Create($Win32::Process::Create::ProcessObj
			,$^X
			#join(' ',$s->qclad($^X,'-e','system(1,$^X,@ARGV)', $f, @_))
			,join(' ',$s->qclad($^X, $f, @_))
			, 0, &DETACHED_PROCESS, '.')
	: system(1, $s->qclad($^X, $f, @_)) !=-1
	)
	|| return($s->error('agtfile:',"cannot start '$f': $!"));
 }
 $r
}


sub connect {		# Connect agent node
 my $s =  ref($_[0]) 	# (set args) -> self
	? ($#_ ? set(@_) : $_[0])
	: ($#_ ? Sys::Manage::Conn->new(@_[1..$#_]) : Sys::Manage::Conn->new());
 if ($s->{-exec} && $s->{-argv} && @{$s->{-argv}}
 &&  $s->{-argv}->[0] =~/^(agtfile|lcmd)/) {
	return($s->$1(@{$s->{-argv}}[1..$#{$s->{-argv}}]))
 }
 $s->{''} =1;
 $s->disconnect() if $s->{-agent};
 my $cts =time();
 my $agt =$s->{-asrc} && $s->{-asrc}->[0]
	|| ($s->{-perl} .' -e "' .$s->agtsrc(0) .'"');
 my $ctp =join(' '
		,''
		,$s->{-node} .':' .$s->{-port}
		,($s->{-user} ? ($s->{-user}) : ())
		,'$$' .$$) ."...\n";
 if (!$s->{-init}) {		# agent exists
	$s->echo("\n",'connect','agent',$ctp) if $s->{-echo};
 }
 elsif ($s->{-init} eq 'wmi') {	# using Windows Management Instrumentation
	$s->echo("\n",'connect','wmi',$ctp) if $s->{-echo};
	local $^W = undef;
	eval('use Win32::OLE');
	if (!$s->{-pswd}) {
		$s->{-wmi} =Win32::OLE->GetObject(
				'winmgmts:{impersonationLevel=impersonate}!//'
					# impersonate, delegate
				.$s->{-node} .'/root/cimv2')
			|| return($s->error('WMI->GetObject:',$s->oleerr()))
	}
	else {
		$s->{-wmi} =Win32::OLE->new('WbemScripting.SWbemLocator')
			|| return($s->error('WMI->new:',$s->oleerr()));
		$s->{-wmi}->{Security_}->{ImpersonationLevel}=4;
			# 4-delegate, 3-impersonate
			# if {ImpersonationLevel}=4 fails, so without windows network access
		$s->{-wmi} =$s->{-wmi}->ConnectServer($s->{-node}
					,'root\\cimv2'
					,$s->{-user}
					,$s->{-pswd})
			|| return($s->error('WMI->ConnectServer:',$s->oleerr()));
		$s->{-wmi}->{Security_}->{ImpersonationLevel}=4; 
	}
	$s->echo('connect',"wmi Win32_Process...\n")
			if $s->{-echo} >2;
	$s->{-wmiph} =$s->{-wmi}->Get('Win32_Process')
			|| return($s->error('WMI->Win32_Process:',$s->oleerr()));
	$s->echo('connect',"wmi Win32_Process->Create("
			, $agt
			, ') (', length($agt), ' bytes)'
			, "...\n") if $s->{-echo} >2;
	my $pid =undef;
	my $ret =$s->{-wmiph}->Create($agt,undef,undef,$pid);
		$ret	&& return($s->error('WMI->Win32_Process->Create:',$s->oleerr(),$ret));
		# !!! may be Win32_Process.Create==1 ???
	$s->{-wmipid} =$pid;
 }
 elsif ($s->{-init} eq 'rsh') {	# using remote shell
	$s->echo("\n",'connect','rsh',$ctp) if $s->{-echo};
	my @c = ('rsh',
		,($s->{-user} ? ('-l', $s->{-user}) : ())
		,$s->{-node}, $agt);
	$s->echo('connect',"rsh run("
			, join(' ', @c)
			, ') (', length($agt), ' bytes)'
			, "...\n") if $s->{-echo} >2;
	(system(@c) ==-1) && return($s->error('rsh:',$!));
	($?>>8) && return($s->error('rsh:',($?>>8)))
 }
 elsif ($s->{-init} eq 'telnet') {	# using telnet
	$s->echo("\n",'connect','telnet',$ctp) if $s->{-echo};
	eval('use Net::Telnet');
	my $t =Net::Telnet->new();
	$t 
	&& $t->open($s->{-node})
	&& $t->login($s->{-user}, $s->{-pswd})
	&& $t->print($agt)
	|| return($s->error('telnet:',$t && $t->errmsg))
 }
 elsif (ref($s->{-init}) eq 'CODE') {
	$s->echo("\n",'connect','code',$ctp) if $s->{-echo};
	local $_;
	&{$s->{-init}}($s, $_=$agt)
	|| return($s->error('-init:',$@))
 }
 else {
	return($s->error('Unsupported init method \'' .$s->{-init} .'\''))
 }
 $s->echo('connect',"IO::Socket::INET...")
		if ($s->{-echo}) &&($s->{-progress}||($s->{-echo} >2));
 {	my $cto=$s->{-timeout} ||(time() -$cts +10);
	   $cts=time();
	while (!($s->{-agent} =IO::Socket::INET->new(PeerAddr => $s->{-node}
			,$s->{-timeout} ? ('Timeout'=>$s->{-timeout}) : ()
			,PeerPort => $s->{-port}
			,Proto    => 'tcp'
			,Type     => SOCK_STREAM))
		&& (time() -$cts <$cto)) {
		print '.'
			if ($s->{-echo}) &&($s->{-progress}||($s->{-echo} >2));
		sleep(1);
	}
	print "\n"
			if ($s->{-echo}) &&($s->{-progress}||($s->{-echo} >2));
	!$s->{-agent} && return($s->error('IO::Socket::INET->new:', $@));
	# eval{$s->{-agent}->binmode(1)}; # binmode always
 }
 $s->{-select} =IO::Select->new($s->{-agent});
 return($s->error('IO::Socket::INET:','Connection stop')) 
	if !$s->{-agent}->connected() || !$s->{-select}->can_write();
 $s->echo('connect',"IO::Socket::INET connected.\n")
		if ($s->{-echo} >2) &&($s->{-progress}||($s->{-echo} >2));
 if ($s->{-exec}) {
	if (!$s->{-argv} || !@{$s->{-argv}}) {
	}
	elsif ($s->{-argv}->[0] =~/^(rcmd|reval|fput|rfput|fget|rfget|rdo)/) {
		return($s->$1(@{$s->{-argv}}[1..$#{$s->{-argv}}]))
	}
	else {
		return($s->rcmd(@{$s->{-argv}}))
	}
 }
 $s
}


sub getrow {	# Get row from agent
		# () -> row | undef
	#   !$_[0]->{-timeout}
	# ? $_[0]->{-agent}->getline()
	# : !$_[0]->{-select}->can_read($_[0]->{-timeout})
	# ? undef
	# : $_[0]->{-agent}->getline()
	$_[0]->{-agent}->getline()
}


sub reval0 {	# Remote Eval perl code without any additions
		# (arg,...) -> success
 if (!$_[0]->{-asaw}	# add agent
 && (!$_[0]->{-asrc} || $_[0]->{-asrc}->[1])) {
	my $s =$_[0]; $s->{-asaw} =1;
	my $agt =$s->{-asrc} && $s->{-asrc}->[1] ||
	(''
	.($s->{-title} ? 'print("' .$s->{-title} .'\\n");' : '')
	.'print \'Connected \',$m_->sockport,\' \',join(\'.\',unpack(\'C4\',$m_->peeraddr)),\':\' ,$m_->peerport,"\\n";'
	#.'eval{$m_->binmode(1)};' # binmode always
	.'use Data::Dumper; $Data::Dumper::Indent=0;'
	.'$t_ =$ENV{TEMP}||$ENV{TMP}||"c:";'
	.'$t_ .=($t_=~/([\\\\\/])/ ? $1 : $^O eq "MSWin32" ? "\\\\" : "/") ."' 
	.$s->{-prgcn} .'-" .time() ."-" .$$;'
	.'$ENV{SMELEM}="' .$s->{-node} .'";'
	.'open(OLDOUT,\'>&STDOUT\');open(OLDERR,\'>&STDERR\');open(OLDIN,\'<&STDIN\');'
	.'open(STDERR,\'>&\' .$m_->fileno);open(STDOUT,\'>&\' .$m_->fileno);'
	.'$?=$!=$^E=0;'
	.'1;'
	);
	if ($s->{-debug}) {
		$s->echo('rpl',$agt,"\n");
		$s->{-agent}->printflush($agt,"\n");
		$s->getret();
		$s->echo('rpl',@_[1..$#_],"\n");
		$s->{-agent}->printflush(@_[1..$#_],"\n");
	}
	else {
		$s->echo('rpl', $agt, @_[1..$#_],"\n") if $s->{-echo} >2;
		$s->{-agent}->printflush($agt,@_[1..$#_],"\n");
	}
 }
 else {
	$_[0]->echo('rpl',@_[1..$#_],"\n") if $_[0]->{-echo} >2;
	$_[0]->{-agent}->printflush(@_[1..$#_],"\n");
 }
 $_[0]
}


sub getret {	# Get return of remote eval
 my $s =$_[0];	# (?filter{}) -> marker row | undef
 local $_;
 my $row;
 my $mrk =$s->{-mark};
 @$s{qw(-errexit -errchild -erros -erros1 -erreval -reteval)}
	=(0,0,'','','',undef);
 while (defined($row =$s->getrow())) {
	if ($row =~/^\Q$mrk\E(\d+\t.*)/) {
		my $ret =$1;
		$ret =$` if $ret =~/[\r\n]+$/;
		@$s{qw(-errchild -erros -erros1 -erreval -reteval)}
			=split /\t/, $ret;
		$s->{-errexit} =$s->{-errchild} ? ($s->{-errchild}>>8) : 0;
		$s->{-erros1}  ='' if !$s->{-erros};
		$s->{-reteval} =Safe->new()->reval($s->{-reteval}) if defined($s->{-reteval});
		$s->echo(  (($s->{-echo} >1)&&0
			 ? ('',$mrk)
			 : ('$?$!$@'))
			, $s->{-errexit}
			,( ($s->{-errchild} & 127) || ($s->{-errchild} & 128)
			 ? ('(',($s->{-errchild} & 127),',',($s->{-errchild} & 128),')')
			 : ())
			,( $s->{-erros}
			 ? ("\t", $s->{-erros}
				, ($s->{-erros1} 
					? (' (',$s->{-erros1},')') : ()))
			 : ())
			,($s->{-erreval}
			 ? ("\t", $s->{-erreval})
			 : ())
			,(($s->{-echo} <3) && 0
			 ? ()
			 : !defined($s->{-reteval})
			 ? ()
			 : ref($s->{-reteval})
			 ? ("\t->",ref($s->{-reteval}))
			 : ("\t->",$s->{-reteval})
			 )
			, "\n") if $s->{-echo} >1;
		last;
	}
	elsif ($_[1]) {
		$row =$` if $row =~/[\r\n]+$/;
		print($row,"\n") if $s->{-echo} >1;
		&{$_[1]}($s,$_ =$row)
	}
	else {
		$row =$` if $row =~/[\r\n]+$/;
		print($row,"\n") if $s->{-echo} >1;
	}
 }

 if ($s->{-debug}) {
	print(defined($row) ? '[debug:enter]' : '[end:enter]'); $_ =<STDIN>;
 }

 return($s->error('Connection stop')) 
	if !defined($row);

 $? =$s->{-errchild};
 $@ =$s->{-erreval};
 $row
}


sub reval {	# Remote Eval perl code
 my $s =shift;	# (?"-'o-e-", perl strings, ?filter sub{}) -> return value
 my $o =$_[0] =~/^-(?:\w[\w\d+-]*)*$/ ? shift : '-';
 my $f =ref($_[$#_]) eq 'CODE' ? pop : undef;
 $s->connect if !$s->{''};
 $s->echo('reval','{...}', "\n") if $s->{-echo};
 local $s->{-rxpnd0} ='do{';
 local $s->{-rxpnd1} =$o;
 $s->reval0($s->rxpnd0(@_))
 && $s->getret($f ? $f : ())
 && (1 ? $s->{-reteval} : 1)
}


sub rcmd {	# Remote Run OS command
 my $s =shift;	# (?"-'o-e-", command and arguments, ?filter sub{}) -> success
 my $o =$_[0] =~/^-(?:\w[\w\d+-]*)*$/ ? shift : '-';
 my $f =ref($_[$#_]) eq 'CODE' ? pop : undef;
 $s->connect if !$s->{''};
 $s->echo('rcmd', join(' ', map{defined($_) ? (qclad($s,$_)) : ('undef')} $o, @_), "\n") 
	if $s->{-echo};
 local $s->{-rxpnd0} ='system{';
 local $s->{-rxpnd1} =$o;
 $s->reval0($s->rxpnd0(@_))
 && $s->getret(ref($f) ? ref($f) : ())
 && (!$s->{-errexit})
}


sub lcmd {	# Local OS command
 my $s =shift;	# (?"-", command and arguments, ?filter sub{}) -> success
 my $o =$_[0] =~/^-(?:\w[\w\d+-]*)*$/ ? shift : '-';
 my $f =ref($_[$#_]) eq 'CODE' ? pop : undef;
 $s->echo('lcmd', join(' '
	, map{	defined($_) 
		? (qclad($s, $qlcl && ($o !~/'/)
				? do {	my $v =$_;
					$v =~s/([\\"])/\\$1/g;
					eval('"' .$v .'"') }
				: $_ )) 
		: ('undef')
		} $o, @_), "\n")
	if $s->{-echo};
 if ($f) {
	$!=$^E=0;
	my $hi;
	my $pid =$s->copen($hi
			, map { (scalar(@_) >1) && isqclad($s, $_)
				? do {	my $v =$_;
					if ($qlcl && ($o !~/'/)) {
						$v =~s/([\\"])/\\$1/g;
						$v =eval('"' .$v .'"');
					}
					$v =~s/"/\\"/g;
					'"' .$v .'"'}
				: $_ } @_);
	if ($pid) {
		local $_;
		my $r =undef;
		while(defined($r=readline($hi))) {
			$r = $` if $r =~/[\r\n]*$/;
			print $r, "\n" if $s->{-echo} >1;
			&$f($s,$_=$r)
		}
		my @t =($!,$^E);
		$hi && close($hi);
		STDOUT->flush();
		($!,$^E) =@t;
		waitpid($pid,0);
	}
	else {
		return($s->error('lcmd:',$!))
	}
 }
 else {
	(system(map { (scalar(@_) >1) && isqclad($s, $_)
			? do {	my $v =$_;
				if ($qlcl && ($o !~/'/)) {
					$v =~s/([\\"])/\\$1/g;
					$v =eval('"' .$v .'"');
				}
				$v =~s/"/\\"/g;
				'"' .$v .'"'}
			: $_ } @_) ==-1)
		&& return($s->error('lcmd:',$!))

 }
 !($?>>8)
}


sub rxpnd0 {	# Expand list to evaluation string (base layer)
 my $s =shift;	# (@args) -> perl string
 my $o =$s->{-rxpnd1};
  ($o =~/o[0-]/ ? 'open(STDOUT,\'>&OLDOUT\');' : 'open(STDOUT,\'>&\' .$m_->fileno);')
 .($o =~/e[0-]/ ? 'open(STDERR,\'>&OLDERR\');' : 'open(STDERR,\'>&\' .$m_->fileno);')
 .'select(STDERR);$|=0;select(STDOUT);$|=0;'
 .'$?=$!=$^E=0;my $r_='
 .($s->{-rxpnd0} =~/^system/
	? $s->rxpnd(@_)
	: ('Data::Dumper::Dumper(' .$s->rxpnd(@_) .')')
	)
 .';'
 .'{my @t=($!,$^E);select(STDERR);$|=1;select(STDOUT);$|=1;($!,$^E)=@t};'
 .'$r_;'
}


sub rxpnd {	# Expand list to evaluation string (subsequent layer)
 my $s =shift;	# (?command, ?"-'", @args) -> perl string
 my $c =$_[0] =~/^(?:system\(|`|do[{'"]|eval[{'"])$/ ? shift : ($s->{-rxpnd0}||'');
 my $o =$_[0] =~/^-(?:\w[\w\d+-]*)*$/ ? shift : ($s->{-rxpnd1}||'');
 if ($c =~/^(system)/) {
	local $s->{-rxpnd0} ='do{';
	local $s->{-rxpnd1} =$o;
	my $q =$o=~/'/ ? "'" : '"';
	$1 .'(' .join(','
		, map {	  ref($_)
			? $s->rxpnd(@$_)
			: !defined($_)
			? undef
			: do {	my $v =$_;
				$v =~s/[\n\r]//g;
				$v =~s/\\/\\\\/g;
				if ((scalar(@_) >1) && isqclad($s,$v)) {
					$v =~s/"/\\"/g;
					$v ='"' .$v .'"';
				}
				$v =~s/\Q$q\E/\\$q/g;
				"$q$v$q"
				}
			} @_) .')'
 }
 elsif ($c =~/^(`)/) {
	local $s->{-rxpnd0} ='do{';
	local $s->{-rxpnd1} =$o;
	my $q ='"';
	$1 .join(' '
		, map {	  ref($_)
			? $s->rxpnd(@$_)
			: !defined($_)
			? undef
			: do {	my $v =$_;
				$v =~s/[\n\r]//g;
				$v =~s/\\/\\\\/g;
				$v =~s/\Q$q\E/\\$q/g;
				$v
				}
			} @_) .$1
 }
 elsif ($c =~/^(do|eval)(\{|'|")/) {
	local $s->{-rxpnd0} ='system(';
	local $s->{-rxpnd1} =$o;
	my ($w,$q) =($1,$2);
	my $v =join(''
		, map {   ref($_)
			? $s->rxpnd(@$_)
			: !defined($_)
			? undef
			: do {	my $v =$_;
				$v =~s/[\n\r]//g;
				$v
				}
			} @_);
	if ($q eq '{') {
		$w .$q .$v .'}'
	}
	else {
		$v =~s/\\/\\\\/g;
		$v =~s/\Q$q\E/\\$q/g;
		$w .' ' .$q .$v .$q
	}
 }
}


sub fget {	# Get remote file
 my $s =shift;	# (?"-'m+b-s+z+", remote file, local file, postfix) -> success
 my $o =$_[0] =~/^-(?:\w[\w\d+-]*)*$/ ? shift : '-';
 my ($fa, $fm, @ps) =@_;
 $s->connect if !$s->{''};
 if ($qlcl && ($o !~/'/) && ($o !~/s(?![0-])/)) {
	$fm =~s/([\\"])/\\$1/g;
	$fm =eval('"' .$fm .'"');
 }
 my($m_, $fz, $fh);
 return($s->error("fget: empty args"))
	if !defined($fa) || ($fa eq '');
 $s->echo('fget', qclad($s,$o), ' ', qclad($s,$fa), ' '
	,(($o =~/s(?![0-])/) || !defined($fm) ? '[string]' : (qclad($s,$fm)))
	,"\n")	if $s->{-echo};
 my $oq =$o=~/'/ ? "'" : '"';
 my $op =1024*16;
 local $s->{-rxpnd0} ='do{';
 local $s->{-rxpnd1} =$o;
 if (($o =~/s(?![0-])/) || !defined($fm)) {
	$o .='s+' if $o !~/s(?![0-])/
 }
 else {
	return($s->error("fget: wrong '$fm'"))
		if ($o =~/[pz](?![0-])/ ? (-f $fm) : (-d $fm))
		|| (($fm =~/[\\\/][^\\\/]+$/) && !-d $`);
	if ($o =~/[pz](?![0-])/) {
		$fz =$fm;
		$fm =$s->{-tmp} .'.' .$s->sarcfe()
 	}
	eval('use IO::File');
	$fh =IO::File->new($fm,'w')
	|| return($s->error("fget: open '$fm': $!"));
 }
 my $cr ='{open(STDOUT,\'>&OLDOUT\');'
	.'use IO::File;'
	.'$!=$^E=0;'
	.'my $fa ='
	.(ref($fa) 
		? $s->rxpnd(@$fa)
		: do {my $v =$fa;
			$v =~s/\\/\\\\/g;
			$v =~s/\Q$oq\E/\\$oq/g;
			"$oq$v$oq"
			}) .';'
	.($o =~/[pz](?![0-])/
	 ? (0 && ($o =~/m(?![0-])/) ? 'open(STDERR,\'>&OLDERR\');$!=$^E=0;' : '')
		.'$fa=do' 
		.$s->sarcmk($o !~/m(?![0-])/ ? $o .'t' : $o
				, '$fa', '$t_') .';'
	 : '')
	.'if(!-f $fa) {$m_->printflush($@="No file \'$fa\'\\n");die($@)};'
	.'my $fh=IO::File->new($fa,\'r\');'
	.'if (!$fh) {$m_->printflush($@="Err open \'$fa\': $!\\n");die($@)};'
	.($o =~/b[0-]/ ? '' : 'binmode($fh);')
	.'my $fl=(-s $fa) ||0;'
	.'my $fp=' .$op .';'
	.'print "Transfering \'$fa\'($fl/$fp)";STDOUT->flush();'
	.'open(STDERR,\'>&OLDERR\');$!=$^E=0;'
	.'$m_->printflush(join("\\t",stat $fa),"\\n");'
	.'my $fb; my $fc=0; my $ft;'
	.'while ($fc <$fl){'
	.'$ft=$fc+$fp <= $fl ? $fp : $fl-$fc;'
	.'exit(1) '
	.'if !defined($fh->sysread($fb,$ft))'
	.'|| !defined($m_->syswrite($fb,$ft));'
	.'print \'.\';'
	.'$fc +=$ft};'
	.'print "\\nTransfering \'$fa\'($fc) completed\\n";STDOUT->flush();'
	.'$fh->close;'
	.($o =~/(?:m|[pz])(?![0-])/ ? 'unlink($fa);' : '')
	.(scalar(@ps) ? '{' .$s->rxpnd0(@ps) .'}' : '1')
	.'}';
 $s->reval0($cr)
	|| return($s->error($@));
 my $fs =$s->getrow(); defined($fs) && chomp($fs);
    $fs =!defined($fs)
	? return($s->error('Connection stop'))
	: ($fs =~/^([\d\t]+)$/) && $1
	? [split /\t/, $1]
	: $s->{-error} eq 'die'
	? $s->error($fs)
	: return(do{my $r =$s->error($fs); $s->getret(); $r});
 my $fl =$fs->[7];
 if (($o =~/s(?![0-])/) || !defined($fm)) {
	$s->{-agent}->read($fm, $fl);
	return(!$s->getret() ||$s->{-erreval} ? undef : $fm)
 }
 binmode($fh) if $o !~/b[0-]/;
 $s->echo('fget', qclad($s,$fm), " ($fl/$op)") if $s->{-progress} && $s->{-echo};
 my $fb; my $fc=0; my $ft;
 while ($fc <$fl) {
	$ft =$fc+$op <= $fl ? $op : $fl-$fc;
	# $s->{-select}->can_read(10);
	return($s->error('fget: accept:', $!))
		if !defined($s->{-agent}->read($fb, $ft))
		|| !defined($fh->syswrite($fb, $ft));
	$fc +=$ft;
	print '.' if $s->{-progress} && $s->{-echo};
 }
 print "\n" if $s->{-progress} && $s->{-echo};
 STDOUT->flush();
 $fh->close();
 utime($fs->[8],$fs->[9],$fm);
 if ($fl ne $fc) {
	$s->getret() if $s->{-error} ne 'die';
	return($s->error("fget: less accepted ($fc)"))
 }
 else {
	my $r;
	if (defined($fz)) {
		$r =!defined(eval($s->sarcxt($o .'t','$fm','$fz'))) && $@;
	}
	return($s->getret() 
		&& (!$r ||$s->error("fget: archiver: $r"))
		&& $s->{-reteval})
 }
}


sub fput {	# Put remote file
 my $s =shift;	# (?"-'m+b-s+z+", local file, remote file, ?postfix, ?filter) -> success
 my $o =$_[0] =~/^-(?:\w[\w\d+-]*)*$/ ? shift : '-';
 my ($fm,$fa,@ps) =@_;
 my $fe =scalar(@ps) && (ref($ps[$#ps]) eq 'CODE') ? pop @ps : undef;
 $s->connect if !$s->{''};
 if ($qlcl && ($o !~/'/) && ($o !~/s(?![0-])/)) {
	$fm =~s/([\\"])/\\$1/g;
	$fm =eval('"' .$fm .'"');
 }
 return($s->error("fput: empty args"))
	if !defined($fm) || !defined($fa) || ($fa eq '');
 $s->echo('fput', qclad($s,$o), ' '
		,($o =~/s(?![0-])/ ? '[string]' : (qclad($s,$fm)))
		,' ', qclad($s,$fa), "\n") if $s->{-echo};
 my $oq =$o=~/'/ ? "'" : '"';
 my $op =1024*16;
 local $s->{-rxpnd0} ='do{';
 local $s->{-rxpnd1} =$o;
 my($m_,$fz,$fu,$ze,$fh,$fs);
 if ($o =~/s(?![0-])/) {
	$fs =[0,0,0,0,0,0,0,length($fm),scalar(time),scalar(time),scalar(time),0,0];
 }
 else {
	if ($o =~/[pz](?![0-])/) {
		my $fx =$s->sarcfe();
		if (($fm=~/\.(\Q$fx\E|arj|tar|zip)$/i) && (-f $fm)) {
			$ze =$1;
		}
		else {
			$ze =$fx;
			$fz =$fm;
			$fm =$s->{-tmp} .'.' .$fx;
			$fu =$fm;
			eval($s->sarcmk($o !~/m(?![0-])/ ? $o .'t' : $o
					, '$fz', '$fm'))
				|| return($s->error("fput: archiver: $@"))
		}
	}
	$fs =[stat $fm];
	return($s->error("fput: not readable '$fm'"))
		if !$fs || (!-f $fm) ||(!-r $fm);
	eval('use IO::File');
	$fh =IO::File->new($fm,'r')
		|| return($s->error("fput: open '$fm': $!"));
 }
 my $cr ='{open(STDOUT,\'>&OLDOUT\');'
	.'use IO::File;'
	.'$!=$^E=0;'
	.'my $fa ='
	.(ref($fa) 
		? $s->rxpnd(@$fa)
		: do {my $v =$fa;
			$v =~s/\\/\\\\/g;
			$v =~s/\Q$oq\E/\\$oq/g;
			"$oq$v$oq"
			}) .';'
	.'my $fz=undef;'
	.($o =~/[pz](?![0-])/ 
	 ? '$fz =$fa; $fa=$t_ .".' .$ze .'";'
	 : '')
	.'if(-d $fa) {$m_->printflush($@="Err directory \'$fa\'\\n");die($@)};'
	.'my $fh=IO::File->new($fa,\'w\');'
	.'if (!$fh) {$m_->printflush($@="Err open \'$fa\': $!\\n");die($@)};'
	.($o =~/b[0-]/ ? '' : 'binmode($fh);')
	.'my $fl=' .$fs->[7] .';'
	.'my $fp=' .$op .';'
	.'print "Accepting \'$fa\'($fl/$fp)";STDOUT->flush();'
	.'open(STDERR,\'>&OLDERR\');$!=$^E=0;'
	.'$m_->printflush(0,"\\n");'
	.'my $fb; my $fc=0; my $ft;'
	.'while ($fc <$fl){'
	.'$ft=$fc+$fp <= $fl ? $fp : $fl-$fc;'
	.'exit(1) '
	.'if !defined($m_->read($fb,$ft))'
	.'|| !defined($fh->syswrite($fb,$ft));'
	.'print \'.\';'
	.'$fc +=$ft};'
	.'print "\\nAccepting \'$fa\'($fc) completed\\n";STDOUT->flush();'
	.'$fh->close;'
	.($fs ? 'utime(' .$fs->[8] .',' .$fs->[9] .',$fa);' : '')
	.($o =~/[pz](?![0-])/
	 ? $s->sarcxt($o .'t', '$fa', '$fz') .';'
	 : '')
	.(scalar(@ps) ? '{' .$s->rxpnd0(@ps) .'}' : '1')
	.'}';
 $s->reval0($cr)
	|| return($s->error($@));
 my $fl =$s->getrow(); defined($fl) && chomp($fl);
    $fl =!defined($fl)
	? return($s->error('Connection stop'))
	: ($fl =~/^([\d\t]+)$/)
	? $fs->[7]
	: $s->{-error} eq 'die'
	? $s->error($fl)
	: return(do{my $r =$s->error($fl); $s->getret($fe); $r});
 if ($o =~/s(?![0-])/) {
	$s->{-agent}->syswrite($fm);
	$s->getret($fe);
	return($s->{-reteval});
 }
 binmode($fh) if $o !~/b[0-]/;
 $s->echo('fput', qclad($s,$fm), " ($fl/$op)") if $s->{-progress} && $s->{-echo};
 my $fb; my $fc=0; my $ft;
 while ($fc <$fl) {
	$ft =$fc+$op <= $fl ? $op : $fl-$fc;
	# $s->{-select}->can_read(10);
	return($s->error('fput: transfer:', $!))
		if !defined($fh->sysread($fb, $ft))
		|| !defined($s->{-agent}->syswrite($fb, $ft));
	$fc +=$ft;
	print '.' if $s->{-progress} && $s->{-echo};
 }
 print "\n" if $s->{-progress} && $s->{-echo};
 STDOUT->flush();
 $fh->close();
 if ($fl ne $fc) {
	$s->getret($fe) if $s->{-error} ne 'die';
	return($s->error("fput: less transfered ($fc)"))
 }
 elsif ($s->getret($fe)) {
	 ($o =~/m(?![0-])/) || $fu
	? unlink($fm) || return($s->error("unlink '$fm': $!"))
	: undef;
	return($s->{-reteval});
 }
 else {
	return(undef)
 }
}


sub rfget {	# Get remote file (alias)
	fget(@_)
}

sub rfput {	# Put remote file (alias)
	fput(@_)
}


sub rfwrite {	# Write remote file
 my $s =shift;	# (?"-'b-", remote file, data) -> success
 my $o =$_[0] =~/^-(?:\w[\w\d+-]*)*$/ ? shift : '-';
    $o =~s/s[\d+-]//g;
    $o .='s+';
 $s->fput($o,$_[$#_],@_ >2 ? join("\n", @_[0..$#_-1]) : $_[0]);
}


sub lfwrite {	# Write local file
 my $s =shift;	# ('-b-',filename, strings) -> success
 my $o =$_[0] =~/^-(?:\w[\w\d+-]*)*$/ ? shift : '-';
 my $f =$_[0]; $f ='>' .$f if $f !~/^[<>]/;
 $s->echo('lfwrite', qclad($s,$o), ' ', qclad($s,$f),"\n") if $s->{-echo};
 local *FILE;  open(FILE, $f) || return($s->error("lfwrite: cannot open '$f': $!"));
 my $r =undef;
 if ($o !~/b[0-]/) {
	binmode(FILE);
	$r =defined(syswrite(FILE,$_[1]))
 }
 else {
	$r =print FILE join("\n",@_[1..$#_])
 }
 close(FILE);
 $r || $s->error("lfwrite: cannot write '$f': $!")
}


sub rfread {	# Read remote file
 my $s =shift;	# (?"-'b-", remote file) -> content
 my $o =$_[0] =~/^-(?:\w[\w\d+-]*)*$/ ? shift : '-';
    $o =~s/s[\d+-]//g;
    $o .='s+';
 $s->fget($o,$_[0]);
}



sub lfread {	# Read local file
 my $s =shift;	# (?"-'b-", file) -> content
 my $o =$_[0] =~/^-(?:\w[\w\d+-]*)*$/ ? shift : '-';
 my($f,$f0) =($_[0],$_[0]); 
	if ($f =~/^[<>]+/)	{$f0 =$'}
	else			{$f  ='<' .$f}
 $s->echo('lfread', qclad($s,$o), ' ', qclad($s,$f),"\n") if $s->{-echo};
 local *FILE;  open(FILE, $f) || return($s->error("lfread: cannot open '$f': $!"));
 my $b =undef;
 binmode(FILE) if $o !~/b[0-]/;
 my $r =read(FILE,$b,-s $f0);
 close(FILE);
 defined($r) ? $b : $s->error("lfread: cannot read '$f': $!")
}


sub sarcfe {	# String: Arc: File Extension
 !$_[0]->{-pack}	# () -> string
 ? 'zip'
 : $_[0]->{-pack} =~/(zip|arj|tar)/i
 ? $1
 : 'z';
}


sub sarcmk {	# String: Arc: Make
 my $s =shift;	# (?"-mt", source var, target var) -> perl string
 my $o =$_[0] =~/^-(?:\w[\w\d+-]*)*$/ ? shift : '-';
 my $z =$s->{-pack} ||'zip';
    $z =~s/\\/\\\\/g;
 my($zs,$zt) =@_;
  '{my $zs=' .$zs .';my $zt=' .$zt .';'
 .'$zt .=".' .$s->sarcfe() .'" if $zt!~/\\.[\w\d]{1,4}$/;'
 .'if((-d $zt)){$@="found \'$zt\' directory\\n";$m_ && $m_->printflush($@);die $@};'
 .'if((-f $zt)&&!unlink($zt)){$@="unlink \'$zt\' error: $!\\n"; $m_ && $m_->printflush($@);die $@};'
 .($o =~/t(?![0-])/ ? 'END{unlink($zt)};' : '')
 .'my($zd,$zm)=("","");'
 .'use Cwd; my $wd=Cwd::cwd();'
 .'if(-d $zs){$zd=$zs; $zm=\'*\'}'
 .'elsif(-f $zs){($zd,$zm)=($zs=~/[\\\\\\/]([^\\\\\\/]+)$/) ? ($`,$1) : ("",$zs)}'
 .'elsif($zs=~/^([^*?]+)[\\\\\\/](.+)$/){$zd=$1; $zm=$2}'
 .'else{$zm=$zs};'
 .'$zd="" if $zd eq ".";'
 .'if(($zd ne "")&&((!-d $zd)||(!-x $zd))){$@="not found \'$zd\' directory\\n";$m_ && $m_->printflush($@);die $@};'
 .'if(($zd ne "")&&!chdir($zd)){$@="chdir \'$zd\' error: $!\\n"; $m_ && $m_->printflush($@);die $@};'
 .'my $qm=$zm; if($qm=~/\\s/){$qm =~s/"/\\\\"/g; $qm =\'"\' .$qm .\'"\'};'
 .'my $qt=$zt; if($qt=~/\\s/){$qt =~s/"/\\\\"/g; $qt =\'"\' .$qt .\'"\'};'
 .'my @zc=('
 .( $z =~/tar/i
  ? join(',','"' .$z .'"'
	,'"cf' .($s->{-echo} ? 'v' : '') .'"' #'"--create --file --verbose"'
	,($o =~/m(?![0-])/ ? '"--remove-files"' : ())
	,'$qt','$qm')
  : $z =~/zip/i	# 'r'ecurse, 'S'ystem-hidden, '!'priviliges, 'q'uiet, 'm'ove
  ? join(',','"' .$z .'"'
	,'"-rS!' .($o =~/m(?![0-])/ ? 'm' : '') .($s->{-echo} ? '' : 'q') .'"'
	,'$qt','$qm')
  : $z =~/arj/i
  ? join(',','"' .$z .'"'
	,($o =~/m(?![0-])/ ? '"m"' : '"a"')
	, '"-aryi"'
	,'$qt','$qm')
  : ref($z) eq 'CODE'
  ? join(',', &{$z}($s,'$zt','$zm','$qt','$qm'))
  : ('"' .$z .' $qt $qm"')
	)
 .');'
 .(($o =~/m(?![0-])/) && ($z =~/arj|zip/i) && 1
	? 'if ($^O eq "MSWin32"){my @zc=("attrib","-R",$qm,"/S");'
	 .($s->{-echo} ? 'print join(" ",@zc),"\\n";' : '')
	 .'system(@zc)};'
	: '')
 .($s->{-echo} ? 'print join(" ",@zc),"\\n";' : '')
 .'system(@zc);'
 .'chdir($wd);'
 .'if($?>>8){$@="' .$z .'(\'$zt\',\'$zd\',\'$zm\') error " .($?>>8) ."\\n";$m_ && $m_->printflush($@);die $@};'
 .';$zt}';
}


sub sarcxt {	# String: Arc: Extract
 my $s =shift;	# (?"-mt", source var, target var) -> perl string
 my $o =$_[0] =~/^-(?:\w[\w\d+-]*)*$/ ? shift : '-';
 my $z =$s->{-packx} ||$s->{-pack} ||'zip';
	if(!ref($z)) {
		$z =~s/\\/\\\\/g;
		$z =~s/zip/unzip/i if !$s->{-packx}
	}
 my($zs,$zt) =@_;
  '{my $zs=' .$zs .';my $zt=' .$zt .';my $z="' .(ref($z) eq 'CODE' ? '' : $z) .'";'
 .'if(!($zs=~/\\.(' .$s->sarcfe() .'|arj|tar|zip)$/i)||(!$z)||(lc($1) eq lc("' .$s->sarcfe() .'"))){'
 .'$zs .=".' .$s->sarcfe() .'" if $zs!~/\\.[\w\d]{1,4}$/;'
 .'}elsif($zs=~/\\.(arj|tar|zip)$/i){$z =$1; $z="unzip" if lc($z) eq "zip"};'
 .'if(!-f $zs){$@="not found \'$zs\' file\\n";$m_ && $m_->printflush($@);die $@};'
 .'if((-f $zt)){$@="found \'$zt\' file\\n";$m_ && $m_->printflush($@);die $@};'
 .'if((!-d $zt)&&!mkdir($zt,0777)){$@="mkdir \'$zt\': $!\\n";$m_ && $m_->printflush($@);die $@};'
 .'use Cwd; my $wd=Cwd::cwd();'
 .'if(($z !~/arj|zip/i) && !chdir($zt)){$@="chdir \'$zt\' error: $!\\n"; $m_ && $m_->printflush($@);die $@};'
 .'my $qs=$zs; if($qs=~/\\s/){$qs =~s/"/\\\\"/g; $qs =\'"\' .$qs .\'"\'};'
 .'my $qt=$zt; if($qt=~/\\s/){$qt =~s/"/\\\\"/g; $qt =\'"\' .$qt .\'"\'};'
 .'my @zc=('
 .(ref($z) eq 'CODE'
  ? join(',', &{$z}($s,'$zs','$zt','$qs'))
  :('$z =~/tar/i ?('
   .join(',','"$z"','"xf' .($s->{-echo} ? 'v' : '') .'"','$qs')
   .'): $z =~/zip/i ?('
   .join(',','"$z"','"-o' .($s->{-echo} ? '' : 'q') .'"','$qs','"-d"','$qt')
   .'): $z =~/arj/i ?('
   .join(',','"$z"','"x"', '"-aryi"','$qs','$qt')
   .'):("$z $qs")'))
 .');'
 .($s->{-echo} ? 'print join(" ",@zc),"\\n";' : '')
 .'$!=$^E=0;system(@zc);'
 .'chdir($wd);'
 .($o =~/t(?![0-])/ ? 'unlink($zs);' : '')
 .'if($?>>8){$@=$zc[0] ."(\'$zs\',\'$zt\') error " .($?>>8) ."\\n";$m_ && $m_->printflush($@);die $@};'
 .';$zt}';
}



sub rdo {	# Remote do
 my $s =shift;	# (?"-e-e!#@o-z+", local file, ?@args, ?filter) -> result
		# (?"-e-e!#@o-z+", ?@interpreter, '!', local file, ?@args, ?filter) -> result
 my $o =$_[0] =~/^-(?:\w[\w\d!@#+-]*)*$/ ? shift : '-';
    $o =~s/'//g;
 my $m =$o =~/e([!@#])$/ ? $1 : '!';
 my $b =ref($#_) eq 'CODE' ? pop : undef;
 my(@c,$f,@a);
 for(my $i =0; $i <=$#_; $i++) {
	next if $_[$i] ne $m;
	@c =@_[0..$i-1] if ($i-1 >=0);
	$f =$_[$i+1];
	@a =@_[$i+2..$#_] if ($i +2) <=$#_;
	last;
 }
 if (!defined($f)) {
	$f =$_[0];
	@a =@_[1..$#_] if 1 <=$#_;
 }
 my $x =($f=~/(\.[\w\d]{1,4})$/ ? lc($1) : '');
 my $e =$o =~/[pz](?![0-])/ ? '' : $x ne '' ? $x : '.rdo';
 my($p,$r,$g) =$o =~/[pz](?![0-])/ 
	? ($f =~/([\\\/])([^\\\/]+)$/
		? ($` ,	$2, '${t_}')
		: ('.',	$f, '${t_}'))
	: ($f,'${t_}' .$e, '${t_}' .$e);
 my $q =sub{join(',', map {my $v =$_; $v =~s/(["\\])/\\$1/g; "\"$v\""} @_)};
 my $qq=sub{join(',', map {isqclad($s, $_)
				? &$q(do{my $v=$_; $v=~s/"/\\"/g; "\"$v\""}) 
				: &$q($_) } @_)};
 $s->echo('rdo', join(' '
			, map {	defined($_) ? (qclad($s,$_)) : ('undef')
				} $o, (@c ? (@c,$m) : @c), $f, @a)
		,"\n") if $s->{-echo};
 $s->fput($o, $p, $g
	, 'do{'
	,($o =~/[pz](?![0-])/
	 ?('use Cwd; my $wd=Cwd::cwd();'
	  .'END{$^O eq "MSWin32"'
	  .' ? system($ENV{COMSPEC}||"cmd","/c","rmdir","/s","/q","'.$g .'")'
	  .' : system("rm","-rf","' .$g .'")};'
	  .'chdir("' .$g .'");'
		)
	 :('END{unlink("'. $g .'")};'))
	,'my $rv='
	,(scalar(@c)
	 ? ('system(' .&$qq(@c) .',' .&$q($r) 
			.(scalar(@a) ?(',' .&$qq(@a)) :'') .');$rv=!($?>>8);')
	 : $x eq '.sh'
	 ? ('system(' .&$q('sh',$r)
			.(scalar(@a) ?(',' .&$qq(@a)) :'') .');$rv=!($?>>8);')
	 : $x =~/\.(bat|cmd)/
	 ? ('system($ENV{COMSPEC}||' .&$q('cmd.exe','/c',$r) 
			.(scalar(@a) ?(',' .&$qq(@a)) :'') .');$rv=!($?>>8);')
	 : ('do{@ARGV=(' .&$q(@a) .'); do ' .&$q($r) .'};'))
	,($o =~/[pz](?![0-])/
	 ?('{my @rc=($?,$!,$^E,@_);'
	  .'chdir($wd);'
	  .'($?,$!,$^E,@_)=@rc};'
		)
	 : '')
	,'$rv'
	,($b ? $b : ())
	);
}
