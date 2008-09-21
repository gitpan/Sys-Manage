#!perl -w
#
# Sys::Manage::Desktops - Centralised management for desktop computers
#
# makarow, 2007-10-04
#
#
# ToDo, see also '???'
# - testing
# - timeout of scripts (startup, logon) should be considered
# + -hostdom for assignments text file
# + errinfo() for NETLCK
# + -atoy=>30 due to NETLCK
# + NETLCK preventing network lost
# + startup -atoy=>10, 15 margin experimented, why?
#

package Sys::Manage::Desktops;
require 5.000;
use strict;
use Carp;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK $SELF);
$VERSION = '0.61';


if ($^O eq 'MSWin32') {
	eval('use Win32');
}

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
 %$s =(	 -prgcn		=>			# program common name
			do{my $v =$s->class; $v=~s/::/-/g; $v}
	,-prgsn		=>(do{$0 =~/([^\\\/]+)$/	# program short name
			? $1
			: $0})
	,-prgpd		=>(do{!$0 ||($0 !~/[\\\/]/)	# program path dir
			? ''
			: ($^O eq 'MSWin32' ? eval{Win32::GetFullPathName($0)} ||$0 : $0) =~/^(.+?)[\\\/][^\\\/]+$/
			? $1
			: ''})
	,-dirm		=>do{$0 =~/([\\\/])/	# directory marker
			? $1
			: $^O eq 'MSWin32'
			? '\\'
			: '/'}
	,-lang		=>'en'			# language to use: 'en'/'ru'
	,-banner	=>''			# program banner text or sub{}
	,-support	=>''			# support banner text of sub{}
	,-hrlen		=>65			# horisontal ruler length
	,-runmode	=>''			# startup,shutdown,logon,logoff,runapp,agent,refresh
						# win95: startup in logon
						# winNT: (startup, ?(agent, start), period)
	,-runrole	=>''			# manager | agent | query
	,-errhndl	=>0			# err handler
	,-errinfo	=>''			# err info
	,-mgrcall	=>"perl $0"		# manager script call for clients
	,-dirmcf	=>''			# dir of command files
	,-dircrs	=>''			# dir of client regs: system
	,-dircru	=>''			# dir of client regs: user
	#,-dirmls	=>''			# dir of mangr logs: system
	#,-dirmlu	=>''                    # dir of mangr logs: user
	#,-dirmrs	=>''			# dir of mangr regs: system
	#,-dirmru	=>''			# dir of mangr regs: user
	#,-smtpsrv	=>undef			# smtp server
	#,-smtpeto	=>[]			# smtp to for errors
	,-dhu		=>undef			# {user =>[names]}
	,-dhn		=>undef			# {node =>[names]}
	,-dla		=>undef			# data list assignments
			# -id
			# -cmt
			# -fresh => id ||[ids]
			# -under => ''|system|user|startup|logon|runapp|logoff|shutdown
			# -nodes => name ||[list]
			# -users => name ||[list]
			# -cnd	=> sub{} -> bool
			# -menu	=>[{par=>val}]	# Win32::Shortcut + 'Name'
			# -mcf	=>[{par=>val}]	# Win32::Shortcut + 'Name'
			# -doid => id ||[ids]
			# -doop =>[[-op => id],[-unreg=>id, time],[-redo=>id, time]]
			# 		-unreg, -unmenu, -redo
			# -do	=> 'cmd line'	# ?!
			# -doop1=> see -doop
			# -last =>1
	,-dha		=>undef			# data hash assignments
	,-dca		=>undef			# data cache assignments
	,-xnodes	=>undef			# exclude nodes
	,-xusers	=>undef			# exclude users
	,-user		=>''			# user name
	,-uadmin	=>0			# admin or system user?
	,-usystem	=>0			# under system account?
	,-domain	=>''			# domain of user
	,-node		=>''			# node name
	,-host		=>''			# host name of node
	,-hostdom	=>''			# host DNS domain
	,-asgid		=>''			# current assignment id
	,-atoy		=>30			# answer timeout agree
	#,-atow		=>0			# answer timeout wait
	#,-atov		=>1			# answer timeout value
	#,-yasg		=>undef			# auto yes asg, if possible
	#,-yerr		=>undef			# auto ack err
	#,-ymyn		=>undef			# auto yes for mesg('yn')
	#,-w32ugrps	=>undef			# win32ugrps() cached
	#,-w32dcf	=>undef			# win32 DC netlogon filesystem
	#,-w32srv
	#,-w32prodtype
	#,-w32nuse
	#,-w32umnu
	, %$s
	);
 $s->{-banner}	="Centralised management for desktop computers";
 $s->{-support}	="Call support, if possible";
 $s->{-host}	=eval('{no warnings; use Sys::Hostname; Sys::Hostname::hostname}');
 $s->{-host}	=$s->{-host} !~/\./
		? join('.', $s->{-host}, map {$_ ? ($_) : ()
			} (do{local $^W =0; eval('{no warnings; use Net::Domain; Net::Domain::hostdomain}')}))
		: $s->{-host};
 $s->{-hostdom} =$s->{-host} =~/^[^\.]*\.(.+)$/ ? $1 : '';
 if ($^O eq 'MSWin32') {
	$s->{-node}	=Win32::NodeName();
	$s->{-mgrcall}	='perl '
			.(do{	my $p =eval{Win32::GetFullPathName($0)} ||$0;
				$p =~s/^\\\\[^\\\/]+\\NetLogon\\/'\\\\' .$s->{-hostdom} .'\\NetLogon\\'/ie
					if $s->{-hostdom};
				$p});
	if ($s->w32dcf()) {
		$s->{-dirmcf} =$s->w32dcf()  .'\\' .$s->{-prgcn} .'-mcf';
	}
	else {
		$s->{-dirmcf} ='%LOGONSERVER%\\NetLogon\\' .$s->{-prgcn} .'-mcf';
	}
 }
 else {
	$s->{-node}	=$s->{-host} =~/\./ ? $' : $s->{-host};
 }
 $s->set(@_);
 $s
}



sub DESTROY {
 my $s =$_[0];
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
 foreach my $k (keys(%opt)) {
	$s->{$k} =$opt{$k};
 }
 if ($opt{-runmode}) {
	if ($opt{-runmode} =~/^(?:startup|shutdown|agent)$/) {
		$s->{-usystem}	=1;
		if ($^O eq 'MSWin32') {
			$s->{-user}	=Win32::LoginName() ||getlogin();
			$s->{-domain}	=$ENV{USERDOMAIN} ||Win32::DomainName();
		}
		else {
			$s->{-user}	=getlogin();
			$s->{-domain}	=$s->{-host} =~/\./ ? $` : $s->{-host};
		}
		$s->{-uadmin} =$s->{-usystem};
	}
	elsif ($opt{-runmode} =~/^(?:logon|logoff|runapp)$/) {
		$s->{-usystem}	=0;
		if ($^O eq 'MSWin32') {
			$s->{-uadmin}	=Win32::IsWin95(); # ||(eval{Win32::IsAdminUser()});
			$s->{-user}	=Win32::LoginName() ||getlogin();
			$s->{-domain}	=$ENV{USERDOMAIN} ||Win32::DomainName();
		}
		else {
			$s->{-uadmin}	=0;
			$s->{-user}	=getlogin();
			$s->{-domain}	=$s->{-host} =~/\./ ? $` : $s->{-host};
		}
	}
 }
 if ($opt{-lang} && ($opt{-lang} eq 'ru')) {
	$s->{-banner}	="–¥­âà «¨§®¢ ­­®¥  ¤¬¨­¨áâà¨à®¢ ­¨¥ ­ áâ®«ì­ëå á¨áâ¥¬"
			if !$opt{-banner};
	$s->{-support}	="Ž¡à â¨â¥áì ¢ á«ã¦¡ã ¯®¤¤¥à¦ª¨, ¯® ¢®§¬®¦­®áâ¨"
			if !$opt{-support};
 }
 if ($opt{-errhndl}) {
	$SELF =$s;
	$SIG{__DIE__} =ref($opt{-errhndl}) ? $opt{-errhndl} : \&errhndl;
 }
 elsif (exists($opt{-errhndl})) {
	$SIG{__DIE__} ='DEFAULT';
 }

 $s
}


sub erros {		# Format OS error message
 my ($s, $v) =@_;
 ($! +0) .'. ' .$! .($^E ? ' (' .($^E +0) .'. ' .$^E .')' : '')
 .($v && ($^O eq 'MSWin32') && ($v =~/^[<>]*\\\\/)
		# && ($! ==13) # Permission denied
 ? ' (' .join('; '
	, $v =~/^[<>]*(\\\\.+?)[\\\/][^\\\/]*$/
	? (-e $1 ? ('') : ("'$1': $!"))
	: ()
	, $v =~/^[<>]*(\\\\[^\\\/]+[\\\/][^\\\/]+)/
	? (-e $1 ? ('') : ("'$1': $!"))
	: ()
	) .')'
 : '');
}


sub errinfo {		# Error info add
 $_[0]->{-errinfo} .=($_[0]->{-errinfo} ? ' // ' : '') .$_[1]
}


sub strtime {		# Log time formatter
	my @t =$#_ >1 ? localtime(@_[1..$#_]) : $_[1] ? localtime($_[1]) : localtime();
	 join('-', $t[5]+1900, map {length($_)<2 ? "0$_" : $_} $t[4]+1,$t[3]) 
	.' ' 
	.join(':', map {length($_)<2 ? "0$_" : $_} $t[2],$t[1],$t[0])
}


sub timeadd {	# Adjust time to years, months, days,...
 my $s =$_[0];
 my @t =localtime($_[1]);
 my $i =5;
 foreach my $a (@_[2..$#_]) {$t[$i] += ($a||0); $i--}
 eval('use POSIX ()') if !$INC{'POSIX.pm'};
 POSIX::mktime(@t[0..5],0,0,$t[8])
}


sub con2gui {
 my $v =$_[1];
 $v =~tr/€‚ƒ„…ð†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™œ›šžŸ ¡¢£¤¥ñ¦§¨©ª«¬­®¯àáâãäåæçèéìëêíîï/ÀÁÂÃÄÅ¨ÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ×ØÙÜÛÚÝÞßàáâãäå¸æçèéêëìíîïðñòóôõö÷øùüûúýþÿ/
	if $_[0]->{-lang} eq 'ru';
 $v
}


sub upcase {
 if (($_[0]->{-lang} eq 'ru') && ($^O eq 'MSWin32')) {
	my $v =$_[1];
	$v =~tr/ ¡¢£¤¥ñ¦§¨©ª«¬­®¯àáâãäåæçèéìëêíîï/€‚ƒ„…ð†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™œ›šžŸ/;
	return($v)
 }
 else {
	return(uc($_[1]))
 }
}


sub error {		# Error final
 my $s =$_[0];		# (strings) -> undef
 my $e =join(' ', map {defined($_) ? $_ : 'undef'} @_[1..$#_]);
    $e =(!$e ? '' : $e =~/[\r\n][ \t]*$/ ? $e : "$e ")
	.'/* assignment=' .$s->{-asgid} ." */"
	if $s->{-asgid};
    $e =(!$e ? '' : $e =~/[\r\n][ \t]*$/ ? $e : "$e ")
	.'/* errinfo=' .$s->{-errinfo} ." */"
	if $s->{-errinfo};
 $@ =$e;
 local $SIG{__DIE__} =$s->{-errhndl} && !ref($s->{-errhndl}) ? 'DEFAULT' : $SIG{__DIE__};
 if ($s->{-runmode} && ($s->{-runmode} =~/^(?:startup|logon|runapp|apply)$/)) {
	local $|=1;
	$s->mesg('err'
		,$s->{-lang} eq 'ru' ? 'Žè¨¡ª ' : 'Error'
		,!$s->{-support}
		? ''
		: !ref($s->{-support}) eq 'CODE'
		? &{$s->{-support}}($s,$e)
		: $s->{-support}
		, $e);
 }
 else {
	local $|=1; print "\n";	# eval{STDOUT->flush()}
 }
 croak("Error: $e\n");
 return(undef);
}

 
sub errhndl {		# Error handler
 my $s =$SELF;
 return if $^S || !$s;
 return if $_[0] 	# bug in Perl 5.6
	&& ($_[0] =~/\sSetDualVar\.pm\s/) 
	&& ($_[0] =~/\/Win32\/TieRegistry\.pm[\s]/);
 my $e =join('',@_);
    $e =(!$e ? '' : $e =~/[\r\n][ \t]*$/ ? $e : "$e ")
	.'/* assignment=' .$s->{-asgid} ." */"
	if $s->{-asgid};
 if ($s->{-runmode} && ($s->{-runmode} =~/^(?:startup|logon|runapp|apply)$/)) {
	$s->mesg('err'
		,$s->{-lang} eq 'ru' ? 'Žè¨¡ª ' : 'Error'
		,!$s->{-support}
		? ''
		: !ref($s->{-support}) eq 'CODE'
		? &{$s->{-support}}($s,$e)
		: $s->{-support}
		,$e)
 }
 return
}


sub echo {		# Echo message
 print(@_[1..$#_],"\n")
}


sub mesg {
 my ($s, $vk, $vt, $vq) =@_;
 my $r ='';
 print "\n", '-' x $s->{-hrlen}, "\n"
	, $s->upcase($vt)
	, $vk eq 'err' ? (': ') : (":\n", '-' x $s->{-hrlen}, "\n");
 if ($#_ >=4) {
	 foreach my $l (@_[4..$#_]) {
		print $l, "\n";
	 }
 }
 else {
	print "\n";
 }
 my $ks =($vk =~/^(?:yn|oc)/ ? '1/0' :  '');
 Win32::Sound::Play($vk eq 'err' ? 'SystemExclamation' : 'SystemQuestion')
	if ($^O eq 'MSWin32') && eval('use Win32::Sound; 1');
 $s->smtpsend(undef, $s->{-smtpeto}
	, 'Error: ' .($s->{-user} ? $s->{-user} .'@' : '') .$s->{-node} .' ' .$s->{-prgcn}
	, $#_ >=4 ? @_[4..$#_] : ())
	if ($vk eq 'err')
	&& $s->{-smtpsrv}
	&& $s->{-smtpeto};
 if ($s->{-ymyn} && ($vk =~/^(?:yn)/)) {
	$r =1;
	print	'-' x $s->{-hrlen}, "\n"
		, $s->upcase($vq), ($ks ? " ($ks) " : " "), $r, "\n";
 }
 elsif ($s->{-yerr} && ($vk =~/^(?:err)/)) {
	$r =1;
	print	'-' x $s->{-hrlen}, "\n"
		, $s->upcase($vq), "\n";
 }
 elsif (eval('use Term::ReadKey; 1')) {
	local $|=1;
	ReadMode(4);
	print	'-' x $s->{-hrlen}, "\n"
		, $s->upcase($vq), ' (', 
		,$ks || 'any key'
		,!$s->{-atow} || !$ks
		? ''
		: $s->{-atov}
		? '; timeout=1'
		: '; timeout=0'
		,$s->{-atow} ? '; 9=pause) ' : ') ';
	my $im =$s->{-atow} ? int($s->{-atow}/5) : 1;
	for(my $i=0; $i <$im; $i++) {
		if(defined($r =ReadKey($s->{-atow} ? 5 : 0))) {
			$r =ReadKey(0)	if $r eq '9';
			$r =undef	if $ks && ($r !~/^(?:1|0)/);
			last		if defined($r);
			$i--
		}
		print '.' if $i <10;
	}
	$r =($s->{-atov} ? 1 : 0)
		if !defined($r);
	print $ks ? $r : '', "\n";
 }
 else {
	print	'-' x $s->{-hrlen}, "\n"
		, $s->upcase($vq), ($ks ? " ($ks) " : " ('Enter') ");
	$r =<STDIN>;
	chomp($r);
 }
 $r
}



sub smtpsend {		# SMTP mail
			# (from, to, subject, text)
 my($s, $from, $to, $subj, @msg) =@_;
 my $host =$s->{-smtpsrv};
 return(0) if !$s->{-smtpsrv};
 my $smtp =eval("use Net::SMTP; Net::SMTP->new(\$host)"); 
 $@	&& warn($@);
 $from =ref($to) ? $to->[0] : $to if !$from;
 return(undef) if !$smtp;
 if (!$smtp)			{warn("SMTP host $host")}
 elsif (!$smtp->mail($from))	{warn("SMTP mail $from")}
 elsif (!$smtp->to(ref($to) 
	? @$to 
	: $to))			{warn("SMTP to $to")}
 elsif (!$smtp->data(join("\n"
	, "From: $from"
	, "To: " .join(', ', ref($to) 
			? @$to 
			: $to)
	, "Subject: $subj"
	, ""
	, @msg)))		{warn("SMTP data")}
 elsif (!$smtp->dataend())	{warn("SMTP dataend")}
 elsif (!$smtp->quit)		{}
 1
}



sub fwrite {		# Store file
 my $s =shift;		# ('-b',filename, strings) -> success
 my $o =$_[0] =~/^-/ ? shift : '-';
 my $f =$_[0]; $f ='>' .$f if $f !~/^[<>]/;
 local *FILE;  open(FILE, $f) || return($s->error("fwrite('open','$f'): " .$s->erros($f)));
 my $r =undef;
 if ($o =~/b/) {
	binmode(FILE);
	$r =defined(syswrite(FILE,$_[1]))
 }
 else {
	$r =print FILE join("\n",@_[1..$#_])
 }
 close(FILE);
 $r || $s->error("fwrite('write','$f'): " .$s->erros($f))
}


sub fstore {
	fwrite(@_)
}


sub fread {		# Load file
 my $s =shift;		# ('-b',filename) -> content
 my $o =$_[0] =~/^-/ ? shift : '-';
 my($f,$f0) =($_[0],$_[0]); 
	if ($f =~/^[<>]+/)	{$f0 =$'}
	else			{$f  ='<' .$f}
 local *FILE;  open(FILE, $f) || return($s->error("fread('open','$f'): " .$s->erros($f0)));
 my $b =undef;
 binmode(FILE) if $o =~/b/;
 my $r =read(FILE,$b,-s $f0);
 close(FILE);
 defined($r) ? $b : $s->error("fread('read','$f'): " .$s->erros($f0))
}


sub fload {
	fread(@_)
}


sub fedit {		# Edit file
 my ($s, $f, $c) =@_;	# (file, sun(self, file, $_=content){} -> new) -> fwrite
 my $v0 =-e $f ? $s->fread("<$f") : '';
 local $_;
 $_ =&$c($s, $f, $_ =$v0);
 return(0) if !defined($_) || ($_ eq $v0);
 $s->fwrite(">$f" .'.bak', $v0);
 $s->fwrite(">$f",$_);
}


sub fglob {	# Glob directory
 my $s =shift;	# (path/mask)
 my @ret;
 if    ($^O ne 'MSWin32') {
	CORE::glob(@_)
 }
 elsif (-e $_[0]) {
	push @ret, $_[0];
	@ret
 }
 else {
	my $msk =($_[0] =~/([^\/\\]+)$/i ? $1 : '');
	my $pth =substr($_[0],0,-length($msk));
	$msk =~s/\*\.\*/*/g;
	$msk =~s:(\(\)[].+^\-\${}[|]):\\$1:g;
	$msk =~s/\*/.*/g;
	$msk =~s/\?/.?/g;
	local (*DIR, $_);
	opendir(DIR, $pth eq '' ? './' : $pth) 
		|| return($s && $s->error("fglob(" .$_[0] ."): opendir('$pth') -> " .$s->erros));
	while(defined($_ =readdir(DIR))) {
		next if $_ eq '.' || $_ eq '..' || $_ !~/^$msk$/i;
		push @ret, "${pth}$_";
	}
	closedir(DIR) || return($s && $s->error("fglob(" .$_[0] ."): closedir('$pth') -> " .$s->erros));
	@ret
 }
}


sub ffind {	# File find
		# (?-opt, path, sub(self, full, path, $_=entry){}, post sub{})
		# 'i'gnore errors, 'r'ecurse
 my ($s, $o, $p, $c, $c1) =$_[1] =~/^-/ ? (@_) : ($_[0], '-r', $_[1..$#_]);
 my $l =$p =~/([\\\/])/ ? $1 : $s->{-dirm};
 local (*DIR, $_);
 opendir(DIR, $p eq '' ? '.' .$p : $p) 
	|| return($o =~/i/ ? 0 : ($s && $s->error("ffind(" .$p ."): opendir('$p') -> " .$s->erros)));
 while(defined($_ =readdir(DIR))) {
	next if $_ eq '.' || $_ eq '..';
	my $e =$p .$l .$_;
	if ((-d $e) && ($o =~/[r]/)) {
		&$c($s,$e,$p,$_)	if $c;
		$s->ffind($o, $e, $c, $c1);
		&$c1($s,$e,$p,$_)	if $c1;
	}
	else {
		&$c($s,$e,$p,$_)	if $c;
		&$c1($s,$e,$p,$_)	if $c1;
	}
 }
 closedir(DIR)
	|| return($o =~/i/ ? 0 : ($s && $s->error("ffind(" .$p ."): closedir('$p') -> " .$s->erros)));
 1
}


sub fpthmk {    # Create directory if needed
 return(1) if -d $_[1];
 my $a ='';
 foreach my $e (split /[\\\/]/, $_[1]) {
	$a .=$e;
	next if !$a;
	if (!-d $a) {
		mkdir($a, 0777) ||return($_[0]->error("fpthmk('$a'): " .$_[0]->erros($a)));
	}
	$a .='/'
 }
 2;
}


sub fcopy {	# Copy files
		# (?-opt, source, target, cnd sub(self, src, tgt){})
		# file, file; file, base; dir*, dir; dir, base
		# opts: 's'tat, 'r'ecurse, 'i'gnore errs
 my $s =shift;
 my $o =$_[0] =~/^-/ ? shift : '-r';
 my ($s0, $t0, $c) =@_;
 local $_;
 if (-f $s0) {
	my $st =$o =~/s/ ? int((stat(_))[9]/2) : 0;
	my $t1 =!-d $t0
		? $t0
		: $s0 =~/([\\\/][^\\\/]+)$/
		? ($t0 .$1)
		: ($t0 . $s->{-dirm} .$s0);
	return(0)	if $c && !&$c($s, $_ =$s0, $t1);
	if ($o =~/s/) {
		my $tt = int(((stat($t1))[9]||0)/2);
		return(0) if $st <= $tt;
	}
	$s->echo('fcopy', ' ', $s0, ' ', $t1) if $o =~/v/;
	unlink($t1) if (-e $t1);
	($^O eq 'MSWin32'
	? Win32::CopyFile($s0, $t1, 1)
	: (eval('use File::Copy (); 1') && File::Copy::syscopy($s0, $t1)))
	|| ($o =~/i/ ? 0 : $s->error("fcopy($s0, $t1): " .$s->erros($t1)))
 }
 else {
	my ($p, $m);
	if (-d $s0) {
		($p, $m) =($s0, '*');
		$s->fpthmk($t0);
		$t0 =$s0 =~/([\\\/][^\\\/]+)$/ ? ($t0 .$1) : ($t0 .$s->{-dirm} .$s0);
		$s->fpthmk($t0);
	}
	elsif (($s0 =~/([^\\\/]+)$/) && ($1 =~/[\?\*]/)) {
		($p, $m) =$s0 =~/^(.*?)[\\\/]([^\\\/]+)$/
			? ($1, $2)
			: ('.', $s0);
		$s->fpthmk($t0);
	}
	else {
		($p, $m) =($s0, '*');
		$s->fpthmk($t0);
	}
	return($o =~/i/ ? 0 : $s->error("fcopy($o, $s0, $t0) -> source dir not found\n"))
		if !-d $p;
	my $r =0;
	foreach my $e ($s->fglob($p .$s->{-dirm} .$m)) {
		if (-d $e) {
			next if $o !~/r/;
			my $t1 =$e =~/([\\\/][^\\\/]+)$/
				? $t0 .$1
				: $e =~/([^\\\/]+)$/
				? $t0 .$s->{-dirm} .$1
				: $t0;
			next	if $c && !&$c($s, $_ =$e, $t1);
			$s->fpthmk($t1);
			$r++ if $s->fcopy($o, $e .$s->{-dirm} .$m, $t1, $c);
		}
		else {
			$r++ if $s->fcopy($o, $e, $t0, $c)
		}
	}
	$r
 }
}


sub frun {	# Run file / command
		# (?-opt, command, args,...)
		# (?-opt, 'do', file, args,...)
		# opts: 'v'erbose, 'i'gnore errs, 'e'xit code test
 my $s =shift;
 my $o =$_[0] =~/^-/ ? shift : '-';
 my $r =0;
 if ($_[0] eq 'do') {
	{local $|=1; $s->echo(join(' ',@_)) if $o =~/v/;}
	local @ARGV = $#_ >1 ? @_[2..$#_] : @ARGV;
	local $SELF = $s;
	local $_ =$s;
	my $x ='{package ' .scalar(caller()) ."; do '"
		.(do{my $v =$_[1]; $v =~s/\\/\\\\/g; $v =~s/'/\\'/g; $v})
		."'}";
	$r =eval $x;
	if (!defined($r) && $@) {
		return($s->error($x,' -> ',$@)) if $o !~/i/;
	}
	return($o =~/e/ ? $r : 1);
 }
 else {
	$s->echo(join(' ',@_)) if $o =~/v/;
	$r =system(@_);
	if ($r <0) {
		return($o =~/i/	? 0 : $s->error(join(' ',@_) .' -> ' .$s->erros));
	}
	else {
		return(1) if $o !~/e/;
		$r =($? >> 8);
		return(!$r ? 1 : $o =~/i/ ? 0 : $s->error(join(' ',@_) .' -> ' .$r));
	}
 }
 $r
}


sub fpthtmp {		# Temporary dir name, may be enforced to create
 my ($s, $ae, $mk) =@_;	# (?assignment, ?mkdir)
 my $f =($ENV{TMP} ||$ENV{TEMP} || '/tmp') 
	.$s->{-dirm} 
	.$s->{-prgcn} .($ae && $ae->{-id} ? '-' .$ae->{-id} : '');
 $s->fpthmk($f) if $f && $mk && (!-e $f);
 $f
}


sub ftmp {		# Temporary file name
 my ($s, $ae, $pid) =@_;	# (?assignment, ?pid)
 $pid =$$ if $pid && ($pid eq '1');
 my $f =($ENV{TMP} ||$ENV{TEMP} || '/tmp') 
	.$s->{-dirm} 
	.$s->{-prgcn} 
	.($ae && $ae->{-id} ? '-' .$ae->{-id} : '') 
	.($pid ? '-' .$pid : '')
	.'.tmp';
 $f
}


sub conn {		# Connect to node
			# (node, command)
 my ($s, $n, $cmd) =@_;
 eval('use Sys::Manage::Conn; 1');
 my $c =Sys::Manage::Conn->new(
	  ref($n) eq 'ARRAY'
	? $n
	: ref($n) eq 'HASH'
	? %{$n}
	: $n
	? (-node =>$n)
	: ()
	, !$_[0]->{-conn}
	? (-echo=>2,-error=>'die')
	: ref($_[0]->{-conn}) eq 'ARRAY'
	? @{$_[0]->{-conn}}
	: ref($_[0]->{-conn}) eq 'HASH'
	? %{$_[0]->{-conn}}
	: (-cfg => $_[0]->{-conn})
	);
 $c->connect();
  !$cmd
 ? $c
 : ref($cmd) eq 'ARRAY'
 ? grep {!$c->rcmd($_)} @$cmd
 : $c->rcmd($cmd);
}


sub w32dcf {		# Win32 DC netlogon filesystem
 return($_[0]->{-w32dcf}) if defined($_[0]->{-w32dcf});
 $_[0]->{-w32dcf} =
 $ENV{SystemRoot} && -e ($ENV{SystemRoot} .'\\SYSVOL\\domain\\scripts')
 ? $ENV{SystemRoot} .'\\SYSVOL\\domain\\scripts'
 : ''
}


sub w32prodtype {	# 1 - Work Station, 2 - Domain Controller, 3 - Server
 if (!$_[0]->{-w32prodtype}) {
	if (Win32::IsWin95()) {
		$_[0]->{-w32prodtype} =1
	}
	else {
		my $v =$_[0]->w32registry('LMachine\\System\\CurrentControlSet\\Control\\ProductOptions\\\\ProductType') ||'';
		$_[0]->{-w32prodtype} =
			$v =~/^\s*WinNT\s*$/i
			? 1
			: $v =~/^\s*LanmanNT\s*$/i
			? 2
			: $v =~/^\s*ServerNT\s*$/i
			? 3
			: 0;
		$_[0]->{-w32prodtype} =
			$_[0]->w32dcf()
			? 2
			: w32wmiqf($_[0], 'Win32_OperatingSystem')->{ProductType} ||0
			if !$_[0]->{-w32prodtype};
	}
 }
 defined($_[1]) ? ($_[0]->{-w32prodtype} >=$_[1]) : $_[0]->{-w32prodtype};
}


sub w32srv {		# Win32 is Server or DC?
 return($_[0]->{-w32srv}) if defined($_[0]->{-w32srv});
 $_[0]->{-w32srv} =
 Win32::IsWinNT && w32prodtype($_[0], 2) && Win32::NodeName() ||''
}


sub w32oleerr {		# Win32 OLE last error message
 (Win32::OLE->LastError()||'undef') 
	.' ' 
	.(Win32::OLE->LastError() && Win32::FormatMessage(Win32::OLE->LastError()) ||'undef')
}


sub w32olenew {		# Win32 OLE new object
 # may be 'Scripting.FileSystemObject', 'WScript', 'WScript.Shell', 'WScript.Network'
 eval('use Win32::OLE; Win32::OLE->Option("Warn"=>0); 1')
 && Win32::OLE->new(@_[1..$#_])
 || $_[0]->error('Win32::OLE->new(' .join(', ', map {defined($_) ? $_ : 'undef'} @_[1..$#_]) .') -> ' .$_[0]->w32oleerr())
}

    
sub w32oleget {		# Win32 OLE get object
 eval('use Win32::OLE; Win32::OLE->Option("Warn"=>0); 1')
 && Win32::OLE->GetObject(@_[1..$#_])
 || $_[0]->error('Win32::OLE->GetObject(' .join(', ', map {defined($_) ? $_ : 'undef'} @_[1..$#_]) .') -> ' .$_[0]->w32oleerr())
}

    
sub w32olein {		# Win32 OLE enumerator
 Win32::OLE::in(@_[1..$#_])
}   


sub w32ADSystemInfo {	# Win32 IADsADSystemInfo
 $_[0]->{-w32ADSystemInfo}
 ||($_[0]->{-w32ADSystemInfo} =$_[0]->w32olenew("ADSystemInfo"))
}


sub w32ADComputer {	# Win32 IADsComputer
 $_[0]->{-w32ADComputer}
 ||($_[0]->{-w32ADComputer} =$_[0]->w32oleget('WinNT://' .$_[0]->{-node} .',computer'))
}


sub w32wmiq {	# Win32 WMI ExecQuery
 my ($s, $q) =@_;	# (query)
 my $o=$s->w32oleget('winmgmts:{impersonationLevel=impersonate}!//'
		.$s->{-node} .'/root/cimv2');
 $q =$q =~/\s/ ? $q : "Select * from $q";
 $o->ExecQuery($q)
 || $_[0]->error("WMI::ExecQuery($q) -> " .$_[0]->w32oleerr())
}


sub w32wmiqf {	# Win32 WMI ExecQuery Fetch
 local $_;		# (query, ?sub{})
 my $o =w32wmiq(@_);
 return(undef) if !$o || !$o->{Count};
 foreach my $e (Win32::OLE::in($o)) {
	$_[2] ? &{$_[2]}($0, $_=$e) : return($e)
 }
 $_[2] ? 1 : undef
}


sub w32registry {	# Win32 Registry
 my $r;
 {	local $SIG{__DIE__}="DEFAULT";
	$r =eval("use Win32::TieRegistry; 1");
 }
 $r || return($_[0] && $_[0]->error('Win32::TieRegistry -> ' .($@ ? $@ : 'unknown error')))
	if !$INC{'Win32/TieRegistry.pm'};
 $_[1] ? $Win32::TieRegistry::Registry->{$_[1]} : $Win32::TieRegistry::Registry
}


sub w32regenu {		# Win32 Registry enumeration of users
 my ($s, $c) =@_;	# (sub(self, key name, $_ ={key hash}, profile dir){})
 my $key =$s->{-prgcn};
 my ($erc,$err);
 local $_;
 return($s->error("w32regenu: MSWin32 required\n"))
	if $^O ne 'MSWin32';
 $s->w32registry();
 if (Win32::IsWin95()) {
	warn("w32regenu: HKEY_CURRENT_USER only on MSWin95\n") if $^W;
	if ($c && $Win32::TieRegistry::Registry->{"HKEY_CURRENT_USER"}) {
		my $r =eval {&$c($s, "HKEY_CURRENT_USER", $_ =$Win32::TieRegistry::Registry->{"HKEY_CURRENT_USER"}, '')||0};
		$erc ="w32regenu: $@" if !defined($r);
		$_ =undef;
	}
	return($s->error($erc)) if $erc;
	return(1);
 }
 return($s->error("w32regenu: Windows NT required\n"))
	if !Win32::IsWinNT();
 my $prd =	  ($ENV{ALLUSERSPROFILE} ||$ENV{USERPROFILE} ||'') =~/^(.+?)[\\\/][^\\\/]+$/
		? $1
		: ($ENV{SystemRoot} .'\\Profiles');
 return($s->error("w32regenu: '$prd' profiles dir not found\n"))
	if !-d $prd;
 my %prs;
 $Win32::TieRegistry::Registry->AllowLoad(1);
 foreach my $l (sort keys %{$s->w32registry('Users')}) {
	my $k =$l =~/^(.*)[\\\/]$/ ? $1 : $l;
	next	if !$k
		|| ($k=~/_Classes$/i);
	# print "w32regenu: HKEY_USERS\\$k\n";
	my $f ='';
	my $d =$Win32::TieRegistry::Registry->{"Users\\$k\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Shell Folders"};
	if ($d) {
		foreach my $e (sort keys %{$d}) {
			next	if !$e
				|| !$d->{$e}
				|| ($d->{$e} !~/^\Q$prd\E\\([^\\]+)/i);
			$f =$prd .'\\' .$1;
			$prs{lc($f)} =1;
			last;
		}
	}
	next if !$f;
	if ($c && $Win32::TieRegistry::Registry->{"HKEY_USERS\\$k"}) {
		my $r =eval {&$c($s, "HKEY_USERS\\$k", $_ =$Win32::TieRegistry::Registry->{"HKEY_USERS\\$k"}, $f)||0};
		$erc ="w32regenu: $@" if !defined($r);
		$_ =undef;
	}
	return($s->error($erc)) if $erc;
 }
 foreach my $f ($s->fglob("$prd\\*")) {
	next	if $prs{lc($f)}
		|| !-f "$f\\ntuser.dat";
	# print "w32regenu: $f\n";
	$err ='';
	if (!$Win32::TieRegistry::Registry->{'Users'}->RegLoadKey($key,"$f\\ntuser.dat")) {
		$err =$^E;
		warn("Win32::TieRegistry::RegLoadKey($f): $^E\n") if $^W;
	}
	elsif ($c && $Win32::TieRegistry::Registry->{"HKEY_USERS\\$key"}) {
		my $r =eval {&$c($s, "HKEY_USERS\\$key", $_ =$Win32::TieRegistry::Registry->{"HKEY_USERS\\$key"}, $f)||0};
		$erc ="w32regenu: $@" if !defined($r);
		$_ =undef;
	}
	$Win32::TieRegistry::Registry->{'Users'}->RegUnLoadKey($key)
	|| (!$err && $^W && warn("Win32::TieRegistry::RegUnLoadKey($f): $^E\n"));
	return($s->error($erc)) if $erc;
 }
 1
}


sub w32nuse {		# Win32 'net use' commands
			# () -> 'net use' text
			# (drive) -> path used
			# (drive, path) -> drive used
 my ($s, $o, $d, $p, @a) =defined($_[1]) && ($_[1] =~/^-/) ? (@_) : ($_[0], '-iv', @_[1..$#_]);
 $s->{-w32nuse} =`net use`	if !$s->{-w32nuse};
 return($s->{-w32nuse})	if !$d;
 chop($d)	if substr($d,-1) eq ':';
 return($s->{-w32nuse} =~/\s\Q${d}:\E\s*([^\s]*)/i ? ($1 || $d) : (0))
		if !$p;
 return($d)
		if $s->{-w32nuse} =~/\s\Q${d}:\E\s+\Q${p}\E/i;
 my $r;
 if ($p =~/^\/d/i) {
	$r =$s->frun($o, 'net', 'use', $d .':', '/delete', @a);
 }
 elsif (Win32::IsWin95()) {
	$r =$s->frun($o, 'net', 'use', $d .':', $p, @a, '/Yes');
 }
 elsif (Win32::IsWinNT() && ($o !~/v/)) {
	$s->echo(join(' ','net','use',$d,$p,@a)) if $o =~/v/;
	my $v =($s->{-w32nuse} =~/\s\Q${d}:\E\s*/i 
		? "net use ${d}: /delete & net use ${d}: $p 2>&1" 
		: "net use ${d}: $p 2>&1");
	$v =`$v`;
	$r =$?>>8;
	return($s->error(join(' ','net','use',$d,$p,@a,'->','$?' .$r,$v)))
		if $r && ($o !~/i/);
	$r =!$r;
 }
 elsif (Win32::IsWinNT() && ($o =~/v/)) {
	$r =$s->frun($o, 'net', 'use', $d .':', '/delete')
		if $s->{-w32nuse} =~/\s\Q${d}:\E\s*/i;
	$r =$s->frun($o, 'net', 'use', $d .':', $p, @a);
 }
 else {
	`net use $d /delete`;
	$r =$s->frun($o, 'net', 'use', $d .':', $p, @a);
 }
 $r && $d
}


sub w32umnu {		# Win32 User Menu Item policy
			# (place opt m|p|d, item file name, item parameters)
			# (opt, clean filter sub{}(ffind sub{}))
			# start 'm'enu, 'p'rograms, 'd'esktop, 'i'gnore, 'v'erbose
			# $s->{-w32umnu} may be base path to menu item dirs.
 my ($s, $p, $f, %o) =@_;
 local $_;
 if (!$s->{-w32umnuM}) {
	my $r =$s->w32registry('CUser\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Shell Folders');
	$s->{-w32umnuM} =$r->{'Start Menu'};
	$s->{-w32umnuP}	=$r->{'Programs'};
	$s->{-w32umnuD}	=$r->{'Desktop'};
	eval('use Win32::Shortcut');
 }
 $s->{-w32umnuH} ={}	if !$s->{-w32umnuH};
 if (ref($f) eq 'CODE') {	# clean
	my $sch =sub{	if ($s->{-w32umnuH}->{lc($_[1])}) {
			}
			elsif (&$f(@_)) { # $_ =~/(?:\[NFD\]|\(NFD\))[.\w]*$/
				$s->echo(join(' ','unlink',$_[1])) if $p =~/v/;
				-d $_[1] ? rmdir($_[1]) : unlink($_[1])
			}};
	foreach my $m (qw(-w32umnuM -w32umnuP -w32umnuD)) {
		$s->ffind('-ri', $s->{$m}, undef, $sch);
	}
 	return(1)
 }
 return(undef)		if !$p ||!$f;
 foreach my $k (keys %o) {
	my $m =( $k =~/path|targ/i	? 'Path'
		:$k =~/arg/i		? 'Arguments'
		:$k =~/work|dir/i	? 'WorkingDirectory'
		:$k =~/desc|dsc/i	? 'Description'
		:$k =~/show/i		? 'ShowCmd'
		:$k =~/hot/i		? 'Hotkey'
		:$k =~/i.*l/i		? 'IconLocation'
		:$k =~/i.*n/i		? 'IconNumber'
		:$k);
	next if $m eq $k;
	$o{$m} =$o{$k};
	delete  $o{$k};
 }
 foreach my $l (qw(M P D)) {
	next if $p !~/$l/i;
	if (!%o) {
		my $d =($s->{-w32umnu} ||'') .$s->{-dirm} .$f;
		$d .='.NT' if ($p =~/o/) && Win32::IsWinNT() && (-d "${d}.NT");
		$s->ffind('-r' .$p, $d
			, sub{	my $ff =$_[0]->{'-w32umnu' .$l} 
				#	.$_[0]->{-dirm}
					.substr($_[1],length($d));
				if (-d $_[1]) {
					$_[0]->{-w32umnuH}->{lc($ff)} =1;
					$_[0]->fpthmk($ff);
				}
				elsif (($ff =~/\.pif$/i) && Win32::IsWinNT()) {
					$_[0]->{-w32umnuH}->{lc($ff)} =1;
					$ff =~s/\.pif$/\.lnk/i;
					$_[0]->fcopy('-s' .$p, $_[1], $ff);
					# my $me =Win32::Shortcut->new($ff);
					# $me->Save($ff);
					$_[0]->{-w32umnuH}->{lc($ff)} =1;
				}
				else {
					$_[0]->fcopy('-s' .$p, $_[1], $ff);
					$_[0]->{-w32umnuH}->{lc($ff)} =1;
				}});
		next
	}
	my $ff =$s->{'-w32umnu' .$l} .$s->{-dirm} .$f
		.( $f !~/\.(?:lnk|pif)$/i ? '.lnk' : '');
	$ff =~s/\.pif$/\.lnk/i if Win32::IsWinNT();
	if (!$s->{-w32umnuH}->{lc($ff)}) {
		my $d =($ff =~/^(.+?)[\\\/][^\\\/]+$/ ? $1 : '');
		$s->fpthmk($d) if $d;
	}
	my $me =Win32::Shortcut->new($ff);
	my $mw =0;
	foreach my $k (keys %o) {
		$mw =1 if (defined($me->{$k}) ? $me->{$k} : '') ne (defined($o{$k}) ? $o{$k} : '');
		$me->{$k} =$o{$k};
	}
	$s->echo(join(' ','Win32::Shortcut', $p, $ff)) if ($p =~/v/) && $mw;
	$me->Save($ff) if $mw;
	$s->{-w32umnuH}->{lc($ff)} =1;
 }
 1
}




sub banner {		# Echo banner
 my ($s, @b) =@_;	# (?text)
 local $|=1;
 if (ref($s->{-banner}) eq 'CODE') {
	&{$s->{-banner}}($s);
 }
 elsif (scalar(@b) || $s->{-banner}) {
	print "\n", '-' x $s->{-hrlen}, "\n" if $s->{-hrlen};
	print scalar(@b) ? @b : $s->{-banner},"\n";
 }
 if (!scalar(@b)) {
 print "  mngr= ", join('; ', map {(defined($s->{$_}) ? $s->{$_} : 'undef')
	} qw (-mgrcall)), "\n";
 print "  host= ", join('; ', map {(defined($s->{$_}) ? $s->{$_} : 'undef')
	} qw (-host -node -hostdom)), "\n";
 print "  user= ", join('; ', map {(defined($s->{$_}) ? $s->{$_} : 'undef')
	} qw (-user -domain -dirmcf)), "\n";
 }
 print '-' x $s->{-hrlen}, "\n"	if $s->{-hrlen};
 1
}



sub acRegFile {	# Logon info file 'r'ead/'w'rite
 my ($s, $dk) =@_;

}



sub ulogon {		# Name of user logged on above system
 my($s,$o) =@_;		# ('w'rite|'r'ead) -> user name || ''
 @$s{qw(-user -domain -dircru)} =('','','')
	if $o eq 'r';
 my $fn;
 if ($^O eq 'MSWin32') {
	if (Win32::IsWin95()) {
		if ($o eq 'r') {
			$s->{-user}	=Win32::LoginName() ||getlogin();
			$s->{-domain}	=$ENV{USERDOMAIN} ||Win32::DomainName();
			# $s->{-dircru}	=$s->acRegDir('user'); # not needed
		}
		return($s->{-user})
	}
	elsif (1) {
		if ($o eq 'w') {
			my $r =$s->w32registry("CUser\\Software");
			$r->CreateKey('Sys-Manage-Desktops') if !$r->{'Sys-Manage-Desktops'};
			$r->{'Sys-Manage-Desktops\\\\user'} =$s->{-domain} .'\\' .$s->{-user};
		}
		elsif ($o eq 'r') {
			foreach my $l (sort keys %{$s->w32registry('Users')}) {
				my $k =($l =~/^(.*)[\\\/]$/ ? $1 : $l);
				my ($v, $a);
				next	if !$k
					|| !($v =$Win32::TieRegistry::Registry->{"Users\\$k\\Software\\Sys-Manage-Desktops\\\\user"})
					|| !($a =$Win32::TieRegistry::Registry->{"Users\\$k\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Shell Folders\\\\AppData"});
				$a =$a .$s->{-dirm} .$s->{-prgcn};
				next	if !-d $a;
				@$s{qw(-user -domain)} =($v =~/^([^\\]+)\\(.+)$/ ? ($2, $1) : ($v, ''));
				$s->{-dircru} =$a;
				last;
			}
		}
		return($s->{-user})
	}
 }
 else {
 }
 return('') if !$fn;
 $fn =$fn .$s->{-dirm} .$s->{-prgcn} .'-logon.txt';
 if ($o eq 'w') {
	$s->fwrite($fn, @$s{qw(-user -domain -dircru)})
 }
 elsif ($o eq 'r') {
	return('') if !-s $fn;
	@$s{qw(-user -domain -dircru)} =$s->fread($fn);
 }
 $s->{-user}
}


sub unames {		# Names of user
 my($s,$u) =@_;		# (?user) -> [names]
 $u =join('\\', map {$_ ? ($_) : ()
			} $s->{-domain}
			, $s->{-user})	if !$u || ($u eq '1');
 my $r;
 if ($s->{-dhu}) {
	$r =$s->{-dhu}->{$u} ||$s->{-dhu}->{lc($u)};
	$r =$s->{-dhu}->{$1} ||$s->{-dhu}->{lc($1)}
		if !$r && ($u =~/[\\\/](.+)$/);
	# $r =$s->{-dhu}->{lc($u)} =[$s->w32ugrps($u)]
	#	if !$r && ($^O eq 'MSWin32') && Win32::IsWinNT();
	$r =[]	if !$r;
 }
 elsif (($^O eq 'MSWin32') && Win32::IsWinNT()) {
	$s->{-w32ugrps} ={}	if !$s->{-w32ugrps};
	if (!($r =$s->{-w32ugrps}->{lc($u)})) {
		$r =$s->{-w32ugrps}->{lc($u)} =[$s->w32ugrps($u)];
	}
 }
 [$u
	, $u =~/[\\\/](.+)$/
	? $1
	: $u =~/^([^@]+)@/
	? $1
	: ()
	, $r
	? @$r
	: ($^O eq 'MSWin32') && Win32::IsWinNT()
	? $s->w32ugrps($u)
	: ()
	]
}



sub nnames {		# Names of node
 my($s,$u) =@_;		# (?user) -> [names]
 $u =join('\\', map {$_ ? ($_) : ()
			} ($^O eq 'MSWin32') && Win32::IsWinNT()
			? $s->w32ADSystemInfo->{DomainShortName}
			: ()
			, $s->{-node})	if !$u || ($u eq '1');
 my $r;
 if ($s->{-dhn}) {
	$r =$s->{-dhn}->{$u} ||$s->{-dhn}->{lc($u)};
	$r =$s->{-dhn}->{$1} ||$s->{-dhn}->{lc($1)}
		if !$r && ($u =~/[\\\/](.+)$/);
	# $r =$s->{-dhn}->{lc($u)} =[$s->w32ugrps($u .'$')]
	#	if !$r && ($^O eq 'MSWin32') && Win32::IsWinNT();
	$r =[] if !$r;
 }
 elsif (($^O eq 'MSWin32') && Win32::IsWinNT()) {
	$s->{-w32ugrps} ={}	if !$s->{-w32ugrps};
	if (!($r =$s->{-w32ugrps}->{lc($u .'$')})) {
		$r =$s->{-w32ugrps}->{lc($u .'$')} =[$s->w32ugrps($u .'$')];
	}
 }
 [$u
	, $u =~/[\\\/](.+)$/
	? $1
	: $u =~/^([^@]+)@/
	? $1
	: ()
	, $r
	? @$r
	: ($^O eq 'MSWin32') && Win32::IsWinNT()
	? $s->w32ugrps($u .'$')
	: ()
	]
}



sub w32ugrps {	# Win32 user groups
		# (name) -> groups list
 my $uif =$_[1];		# user input full name
 my $uid ='';			# user input domain name
 my $uin ='';			# user input name shorten
 my @gn;			# group names
 my @gp;			# group paths
 return(@gn) if Win32::IsWin95();
 eval('use Win32::OLE'); Win32::OLE->Option('Warn'=>0);
 if	($uif =~/^([^\\]+)\\(.+)/)	{ $uid =$1;	$uin =$2 }
 elsif	($uif =~/^([^@]+)\@(.+)/)	{ $uid =$2;	$uin =$1 }
 else					{ $uin =$uif;	
					  $uid =$_[0]->w32ADSystemInfo->{DomainShortName}
						||Win32::NodeName()}
 my $oh =Win32::OLE->GetObject('WinNT://' .$uid .',domain');
 return(@gn) if !$oh;
 my $ou =Win32::OLE->GetObject("WinNT://$uid/$uin,user");
 return(@gn) if !$ou;
 my $dp =			# domain prefix for global groups, optional
	  lc($oh->{Parent}) eq lc($ou->{Parent})
	? ''
	: $ou->{Parent} =~/([^\\\/]+)$/
	? $1 .'\\'
	: '';
 if ($ou->{Groups} && $ou->{Groups}->{Count}) {
	foreach my $og (Win32::OLE::in($ou->{Groups})) { # global groups from user's domain
		next if !$og || !$og->{Class} || $og->{groupType} ne '2';
		push @gn, $dp .$og->{Name};
		push @gp, $og->{ADsPath};
	}
 }
 my $uc =lc($ou->{ADsPath});	# user compare
 my $gc =[map {lc($_)} @gp];	# group compare
 $oh->{Filter} =['Group'];
 foreach my $og (Win32::OLE::in($oh)) {
	next if !$og || !$og->{Class} || $og->{groupType} ne '2';
	foreach my $om (Win32::OLE::in($og->{Members})) {
		next if !$om || !$om->{Class} || ($om->{Class} ne 'User' && $om->{Class} ne 'Group');
		my $mc =lc($om->{ADsPath});
		foreach my $p (@$gc) {
			next if $p ne $mc;
			push @gn, $og->{Name};
			push @gp, $og->{ADsPath};
			$mc =undef;
			last;
		}
		last if !$mc;
		if ($mc eq $uc) {
			push @gn, $og->{Name};
			push @gp, $og->{ADsPath};
			last;
		}
	}
 }
 @gn;
}



sub dGet {		# Get assignment by ID
 if ($_[0]->{-dla}) {	# (id) -> {assignment}
	return($_[0]->{-dha}->{$_[1]}) if $_[0]->{-dha};
	my $s =$_[0];
	$s->{-dha} ={};
	foreach my $e (@{$s->{-dla}}) {
		next if !$e->{-id};
		$s->{-dha}->{$e->{-id}} =$e
	}
	return($s->{-dha}->{$_[1]})
 }
 else {
	return($_[0]->error('dGet(): No assignments datastore'));
 }
}


sub dQuery {		# Query assignments
 my($s,$q,$n,$u) =@_;	# (category, node name, user name) -> [assignments]
			# (-mcf), ('', system, user), startup, logon, runapp, logoff, shutdown
 $n ='(' .join('|', map {my $v =$_; $v =~s/([^\w\d])/\\$1/g; $v
		} ref($n) ? @$n : @{$s->nnames($n)}) .')'
	if $n && (ref($n) ne 'CODE');
 $u ='(' .join('|', map { my $v =$_; $v =~s/([^\w\d])/\\$1/g; $v
		} ref($u) ? @$u : @{$s->unames($u)}) .')'
	if $u && (ref($u) ne 'CODE');
 print "\ndQuery("
	, !ref($s->{-dla}) && $s->{-dla} && $s->{-dca}
	? "'load'"
	: !defined($q)
	? "'undef'"
	: "'$q'"
	, ($n ? ", node~=$n" : '')
	, ($u ? ", user~=$u" : '')
	, ")\n";
 return([]) 	if $n
		&& $s->{-xnodes}
		&& grep /^$n$/i, ref($s->{-xnodes}) ? @{$s->{-xnodes}} : $s->{-xnodes};
 return([]) 	if $u 
		&& $s->{-xusers}
		&& grep /^$u$/i, ref($s->{-xusers}) ? @{$s->{-xusers}} : $s->{-xusers};
 my $cn =!$n					# nodes condition
	? $n
	: ref($n) eq 'CODE'
	? $n
	: sub {	grep /^$n$/i, ref($_[2]) ? @{$_[2]} : $_[2]};
 my $cu =!$u					# users condition
	? $u
	: ref($u) eq 'CODE'
	? $u
	: sub {	grep /^$u$/i, ref($_[2]) ? @{$_[2]} : $_[2]};
 my $cq =ref($q) eq 'CODE'
	? $q
	: !defined($q)
	? $q
	: $q eq '-mcf'
	? sub {$_[0]->{-mcf}}
	: !$q
	? sub {!$_[0]->{-under} || ($_[0]->{-under} =~/^(?:system|user)$/)}
	: $q eq 'system'
	? sub {!$_[0]->{-under} || ($_[0]->{-under} eq $q)}
	: sub {$_[0]->{-under} && ($_[0]->{-under} eq $q)};
 my $cw =$s->{-runmode} && ($s->{-runmode} =~/^(?:startup|logon|agent|apply|runapp|logoff|shutdown)/)
	? $s->strtime(time)
	: undef;
 my $ce;					# unfolder
    $ce=sub {	((map {	my $e =dGet($s,$_);
			!$e ? () : $e->{-doid} ? &$ce($e) : ($e)
			}	  ref($_[0]->{-doid}) 
				? @{$_[0]->{-doid}}
				: $_[0]->{-doid}
				? ($_[0]->{-doid})
				: ())
		,$_[0])	};
 my $r =[];
 local $s->{-asgid} ='';
 if (ref($s->{-dla})) {
	foreach my $e (@{$s->{-dla}}) {
		next	if !$e->{-id};
		$s->{-asgid} =$e->{-id};
		next	if ($cn && $e->{-nodes} && !&$cn($s, $e, $e->{-nodes}))
			|| ($cu && $e->{-users} && !&$cu($s, $e, $e->{-users}))
			|| (ref($e->{-cnd}) && !&{$e->{-cnd}}($s,$e))
			|| ($cw && $e->{-since} && ($e->{-since} gt $cw));
		if (!defined($q)) {
			push @$r, $e->{-doid} ? &$ce($e) : ($e)
		}
		elsif ($e->{-doid}) {
			push @$r, map {&$cq($_) ? $_ : ()} &$ce($e);
		}
		elsif (&$cq($e)) {
			push @$r, $e;
		}
	}
 }
 elsif ($s->{-dla}) {
	local *FILE;
	open(FILE, $s->{-dla}) || return($s->error("dQuery('open','" .$s->{-dla} ."'): " .$s->erros));
	my ($qu, $qm) =$s->{-dca} ||!defined($q)
			? ()
			: $q eq '-mcf'
			? (undef, $q)
			: ($q);
	my ($id, $yq, $yn, $yu, $yc, $yt) =('');
	my ($yd) =1;
	my ($ha,$hr) =({},{});
	my $l;
	while (1) {
		undef $!;
		if (!defined($l =<FILE>)) {
			return($s->error("dQuery('readline'): " .$s->erros)) if $!;
			$yq =	!defined($qu) ? !$qm : (!$qu || ($qu eq 'system'))
				if !defined($yq);
			$ha->{$id} =1 if $id && $yq && $yn && $yu && $yc;
			last
		}
		elsif ($l =~/^[\s#]*[\r\n]/) {
		}
		elsif ($l =~/^(-hostdom|-domain)\s*[=>]+\s*['"]*([^\s\n\r'"]+)/) {
			$yd =(lc($2) eq 'all') ||(lc($2) eq lc($s->{$1}))
		}
		elsif (!$yd) {
		}
		elsif ($l =~/^-dhn\b/) {
			if ($n && ($l =~/^-dhn\s*[=>]+\s*[\['"]*$n\b/i)) {
				my $v =($l =~/^-\w+\s*[=>]+\s*([^\n\r]+)/i) && $1;
				$v =$v=~/^[\[]/ ? eval($v) : $v=~/^["']/ ? eval("[$v]") : [split /\s*[,;]\s*/, $v];
				return($s->error("dQuery('$l'): $@")) if !defined($v);
				$s->{-dhn} ={$v->[0]=>[ref($s->{-dhn}) && $s->{-dhn}->{$v->[0]}
					? @{$s->{-dhn}->{$v->[0]}}
					: ()
					, @$v[1..$#$v]]};
				$n ='(?:' .join('|', $v->[0], map {my $v =$_; $v =~s/([^\w\d])/\\$1/g; $v
					} @{$s->{-dhn}->{$v->[0]}}) .')';
			}
		}
		elsif ($l =~/^-dhu\b/) {
			if ($u && ($l =~/^-dhu\s*[=>]+\s*[\['"]*$u\b/i)) {
				my $v =($l =~/^-\w+\s*[=>]+\s*([^\n\r]+)/i) && $1;
				$v =$v=~/^[\[]/ ? eval($v) : $v=~/^["']/ ? eval("[$v]") : [split /\s*[,;]\s*/, $v];
				return($s->error("dQuery('$l'): $@")) if !defined($v);
				$s->{-dhu} ={$v->[0]=>[ref($s->{-dhu}) && $s->{-dhu}->{$v->[0]}
					? @{$s->{-dhu}->{$v->[0]}}
					: ()
					, @$v[1..$#$v]]};
				$u ='(?:' .join('|', $v->[0], map {my $v =$_; $v =~s/([^\w\d])/\\$1/g; $v
					} @{$s->{-dhu}->{$v->[0]}}) .')';
			}
		}
		elsif ($l =~/^-id\s*[=>]+\s*['"]*([^\s\n\r'"]+)/) {
			$yq =	!defined($qu) ? !$qm : (!$qu || ($qu eq 'system'))
				if !defined($yq);
			$ha->{$id} =1 if $id && $yq && $yn && $yu && $yc && $yt;
			$id =$1;
			$s->{-asgid} =$id;
			$yq =undef; $yn =$yu =$yc =$yt =1;
		}
		elsif ($l =~/^-doid\b/) {
			if (!$s->{-dha}) {
				$l =~/^-[\w\d]+\s*[=>]+\s*([^\n\r]+)/;
				my $v =$1;
				foreach my $e (
					  $v =~/^[\[]/
					? @{eval($v)}
					: $v =~/^["']/
					? eval($v)
					: split /\s*[,;]\s*/, $v) {
					return($s->error("dQuery('$l'): $@")) if !defined($e);
					$hr->{$e} =1;
				}
			}
		}
		elsif ($l =~/^-doop[1]*\b/) {
			if (!$s->{-dha}) {
				$l =~/^-[\w\d]+\s*[=>]+\s*([^\n\r]+)/;
				my $v =$1;
				foreach my $e (@{eval($v =~/^\[\[/ ? $v : "[$v]")}) {
					return($s->error("dQuery('$l'): $@")) if !defined($e);
					$hr->{$e->[1]} =1;
				}
			}
		}
		elsif ($l =~/^-under\b/) {
			next if !defined($qu);
			$yq =	($qu
				? $l =~/^-under\s*[=>]+\s*['"]*$qu/
				: $l =~/^-under\s*[=>]+\s*['"]*(?:system|user)/)
			|| 0;
		}
		elsif ($l =~/^-mcf\b/) {
			$yq =1 if $qm;
		}
		elsif ($l =~/^-nodes\b/) {
			$yn =0	if $n && ($l !~/['"]$n['"]/i);
		}
		elsif ($l =~/^-users\b/) {
			$yu =0	if $u && ($l !~/['"]$u['"]/i);
		}
		elsif ($l =~/^-cnd\s*[=>]+\s*([^\n\r]+)/) {
			my $v =$1;
			   $v =$v =~/^sub\s*\{/ ? eval($v) : eval("sub{$v}");
			return($s->error("dQuery('$l'): $@")) if !defined($v);
			$yc =0 if !&$v($s);
		}
		elsif ($l =~/^-since\s*[=>]+\s*['"]*([^\s\n\r'"]+)/) {
			$yt =0 if $1 gt $cw;
		}
	}
	seek(FILE, 0, 0) || return($s->error("dQuery('seek','" .$s->{-dla} ."'): " .$s->erros));
	my $hl;
	while (1) {
		undef $!;
		if (!defined($l =<FILE>)) {
			return($s->error("dQuery('readline'): " .$s->erros)) if $!;
			last
		}
		elsif ($l =~/^[\s#]*[\r\n]/) {
		}
		elsif ($l =~/^-id\s*[=>]+\s*['"]*([^\s\n\r'"]+)/) {
			$id =$1;
			$s->{-asgid} =$id;
			$hl =undef;
			$ha->{$id} =$hl ||($hl ={-id=>$id})	if $ha->{$id};
			$hr->{$id} =$hl ||($hl ={-id=>$id})	if $hr->{$id};
			push @$r, $ha->{$id}			if $ha->{$id};
		}
		elsif ($hl && ($l =~/^(-[\w\d]+)\s*[=>]+\s*([^\n\r]+)/)) {
			my ($k, $v) =($1,$2);
			if ($k =~/^-(?:nodes|users|doid|fresh)$/) {
				$hl->{$k} =$v =~/^[\['"]/
						? eval($v)
						: [split /\s*[,;]\s*/, $v];
			}
			elsif ($k =~/^-(?:menu|mcf)$/) {
				$hl->{$k} =eval($v =~/^[\[\{]/ ? $v : "[$v]");
			}
			elsif ($k =~/^-(?:doop|doop1)$/) {
				$hl->{$k} =eval($v =~/^\[\[/ ? $v : "[$v]");
			}
			elsif ($k =~/^-(?:cnd)$/) {
				$hl->{$k} =eval($v =~/^sub\s*\{/ ? $v : "sub{$v}");
			}
			elsif ($v =~/^['"]/) {
				$hl->{$k} =eval($v);
			}
			else {
				$hl->{$k} =$v;
			}
			return($s->error("dQuery('readattr', '$k', '$v'): $@"))
				if !defined($hl->{$k}) && $@;
		}
	}
	close(FILE);
	$s->{-dha} =$hr	if !$s->{-dha};
	if ($s->{-dca}) {
		$s->{-dla} =$r;
		return(dQuery(@_));
	}
	my $i =0;
	while ($i <=$#$r) {
		if ($r->[$i]->{-doid}) {
			my @a =!defined($q)
				? &$ce($r->[$i])
				: map {&$cq($_)} &$ce($r->[$i]);
			splice @$r, $i, 1, $a;
			$i +=$#a;
			next
		}
		$i++
	}
 }
 else {
	return($s->error('dQuery(): No assignments datastore'));
 }
 $r
}


sub mcfStore {	# Store menu command file(s)
		# (assignment, ? menu elem, ? chk ass) -> success
 my ($s, $ass, $mnu, $chk) =@_;
 if (!$mnu) {
	if ($ass->{-mcf}) {
		foreach my $e (ref($ass->{-mcf}) eq 'ARRAY' ? @{$ass->{-mcf}} : $ass->{-mcf}) {
			$s->mcfStore($ass, $e, $chk)
		}
	}
	return(1)
 }
 $chk =1 if !$chk && $ass->{-fresh};
 my $f =$s->{-dirmcf} .$s->{-dirm} .$ass->{-id} 
		.($mnu->{-mcf} ? '-' .$mnu->{-mcf} : '') 
		.($^O eq 'MSWin32' ? '.bat' : '');
 $s->fwrite($f
	, $chk
	? $s->{-mgrcall} ." runapp"
	: ()
	, $mnu->{WorkingDirectory}
	? 'cd ' .$mnu->{WorkingDirectory}
	: ()
	, ($^O eq 'MSWin32' ? 'start ' : '') .$mnu->{Path} .($mnu->{'Arguments'} ? ' ' .$mnu->{'Arguments'} : '')
	);
}


sub mePath {	# Menu element path translator
		# (assignment, menu name) -> file path
 my($s, $a, $f) =@_;
 my($u,$l,$f1,$r);
 if ($f =~/^(all|user|\.default)[^\\\/]*[\\\/](programs|desktop|startup|start)[^\\\/]*[\\\/]/i) {
	$u =$1;
	$l =$2;
	$f1=$';
 }
 elsif ($a) {
	$u =!$a->{-under} ||($a->{-under} =~/^(?:system|startup\d*|shutdown)$/)
		? 'all'
		: 'user';
	if ($f =~/^(programs|desktop|startup|start)[^\\\/]*[\\\/]/i) {
		$l =$1;
		$f1=$';
	}
	else {
		$l ='programs';
		$f1=$f
	}
 }
 else {
	$u ='all';
	$l ='programs';
	$f1=$f
 }
 if ($^O eq 'MSWin32') {
	$u =	  $u =~/^all/i
		? 'LMachine\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Shell Folders\\\\'
		: $u =~/^\.default/i
		? 'Users\\.DEFAULT\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Shell Folders\\\\'
		: 'CUser\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Shell Folders\\\\';
	$l =	$l =~/^prog/i
		? 'Programs'
		: $l =~/^startup/i
		? 'Startup'
		: $l =~/^start/i
		? 'Start Menu'
		: $l =~/^desk/i
		? 'Desktop'
		: 'Programs';
	$r =($s->w32registry($u .$l) ||$s->w32registry($u ."Common $l"));
 }
 $r =$r && join($s->{-dirm}, $r, map {$_ ? ($_) : ()} $f1) ||$f;
 $r
}


sub meStore {	# Store menu element(s)
		# (assignment, ? menu elem, ? cmd file) -> success
 my ($s, $ass, $mnu, $mcf) =@_;
 if ($#_ <2) {
	if ($ass->{-mcf}) {
		foreach my $e (ref($ass->{-mcf}) eq 'ARRAY' ? @{$ass->{-mcf}} : $ass->{-mcf}) {
			$s->meStore($ass, $e, 1)
		}
	}
	if ($ass->{-menu}) {
		foreach my $e (ref($ass->{-menu}) eq 'ARRAY' ? @{$ass->{-menu}} : $ass->{-menu}) {
			$s->meStore($ass, $e, 0)
		}
	}
	return(1)
 }
 $mcf =$mcf && ($s->{-dirmcf} .$s->{-dirm} .$ass->{-id}
	.($mnu->{-mcf} ? '-' .$mnu->{-mcf} : '')
	.($^O eq 'MSWin32' ? '.bat' : ''));
 my $mef =$s->mePath($ass,$mnu->{Name});
 return($s->error("meStore('" .$ass->{-id} ."'): Empty menu item name")) if !$mef;
 ($mef =~/[\\\/][^\\\/]+$/) && $s->fpthmk($`);
 my $r;
 if ($^O eq 'MSWin32') {
	eval('use Win32::Shortcut');
	$mef .='.lnk' if $mef !~/\.(?:lnk|pif)$/i;
	my $me =Win32::Shortcut->new($mef);
	if ($mcf) {
		$me->{Path} =$mcf;
		$me->{Arguments} ='';
	}
	else {
		$me->{Path} =$mnu->{Path};
		$me->{Arguments} =$mnu->{Arguments} if $mnu->{Arguments};
	}
	foreach my $k (qw(Arguments WorkingDirectory Description ShowCmd Hotkey IconLocation IconNumber)) {
		$me->{$k} =$mnu->{$k} if defined($mnu->{$k});
	}
	$r =$me->Save($mef);
 }
 $r
}


sub meDel {	# Delete menu element(s)
		# (assignment, ? menu elem) -> success
 my ($s, $ass, $mnu) =@_;
 if ($#_ <2) {
	if ($ass->{-mcf}) {
		foreach my $e (ref($ass->{-mcf}) eq 'ARRAY' ? @{$ass->{-mcf}} : $ass->{-mcf}) {
			$s->meDel($ass, $e)
		}
	}
	if ($ass->{-menu}) {
		foreach my $e (ref($ass->{-menu}) eq 'ARRAY' ? @{$ass->{-menu}} : $ass->{-menu}) {
			$s->meDel($ass, $e)
		}
	}
	return(1)
 }
 my $mef =$s->mePath($ass,$mnu->{Name});
 return($s->error("meDel('" .$ass->{-id} ."'): Empty menu item name")) if !$mef;
 $mef .='.lnk' if ($mef !~/\.(?:lnk|pif)$/i) && ($^O eq 'MSWin32');
 -e $mef
 ? unlink($mef)
	||$s->error("unlink('$mef'): " .$s->erros)
 : 1;
 if ($mef =~/(.+)[\\\/][^\\\/]+$/) {
	rmdir($1)	# empty folder only, ignoring errors
 }
 1
}


sub acRegDir {	# Assignment directory
		# ('system'|'user') -> success
 my ($s, $dk) =@_;
 if ($^O eq 'MSWin32') {
	$s->{-dircrs} =($ENV{SystemRoot} ||$ENV{windir}) .'\\' .$s->{-prgcn}
		if !$s->{-dircrs};
	$s->{-dircru} =($ENV{AppData} 
				||$s->w32registry('CUser\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Shell Folders\\\\AppData')
				||$ENV{windir})
		.'\\' .$s->{-prgcn}
		if !$s->{-dircru} && ($dk eq 'user');
 }
 else {
	$s->{-dircrs} ='/var/' .$s->{-prgcn}
		if !$s->{-dircrs};
	$s->{-dircru} =$ENV{HOME} .$s->{-dirm} .$s->{-prgcn}
		if !$s->{-dircru} && $ENV{HOME} && ($dk eq 'user');
 }
 my $d =  $dk eq 'system'
	? $s->{-dircrs}
	: $s->{-dircru};
 $d && (!-e $d) && $s->fpthmk($d) && $d;
}



sub acRfm {	# Assignment call manager filesystem
		# (-dirmrs|-dirmru|runmode, file|'*'|false) -> dir | mask | file
 my ($s, $m, $fe) =@_;
 my $dv = $m && ($m =~/^-/)
	? $s->{$m}
	: !$m ||($m =~/^(?:system|-dirmrs)/)
	? $s->{-dirmrs}
	: $m =~/^(?:user|-dirmru)/
	? $s->{-dirmru}
	: $m =~/^(?:startup|apply|shutdown|-dirmls)/
	? $s->{-dirmls}
	: $m =~/^(?:logon|logoff|-dirmlu)/
	? $s->{-dirmlu}
	: $s->error("acRfm('$m') -> unexpected mode");
 return(undef)	if !$dv;
 my $n =$s->{-node};
 my $u =!$m ||($m =~/^(?:system|startup|agent|apply|shutdown|-dirmrs)/)
	? ''
	: $s->{-user};
 my ($f, $e) =!$fe ? ($fe, '') : $fe =~/^(.+?)(\.[^.]+)$/ ? ($1, $2) : ($fe, '');
 $dv =&$dv($s, $m, $n, $u, $f, $e) if ref($dv);
 my $r;
 if ($dv =~/\[.{0,2}(?:[nfe]|u[slw]{0,1}).{0,2}\]/) {
	$r =$dv;
	$r =~s/\[(.{0,2})n(.{0,2})\]/$n ? $1 .lc($n) .$2 : ''/e;
	$r =~s/\[(.{0,2})us(.{0,2})\]/$1 .($u ||'sys') .$2/e;
	$r =~s/\[(.{0,2})ul(.{0,2})\]/$1 .($u ||getlogin()) .$2/e;
	$r =~s/\[(.{0,2})uw(.{0,2})\]/$1 .($u ? $u : ($^O eq 'MSWin32') && Win32::IsWin95() ? getlogin() : 'sys') .$2/e;
	$r =~s/\[(.{0,2})u(.{0,2})\]/$u ? $1 .$u .$2 : ''/e;
	if ($r =~s/\[(.{0,2})e(.{0,2})\]/$e ? $1 .$e .$2 : ''/e) {
		$r =~s/\[(.{0,2})f(.{0,2})\]/$1 .($f ||'xxx') .$2/e;
	}
	else {
		$r =~s/\[(.{0,2})f(.{0,2})\]/$1 .($f ||'xxx') .($e ||'') .$2/e;
	}
	$r =$r =~/^(.+)[\\\/][^\\\/]*$/ ? $1 : $r if !$f;
 }
 else {
	$r =$dv	.$s->{-dirm} .lc($n) .($u ? "-$u" : '')
		.($f ? $s->{-dirm} .$f .$e : '')
 }
 $r
}


sub acReg {	# Assignment call registration
		# (assignment) -> fwrite
 my ($s, $ae, @txt) =@_;
 my ($d, $m) =!$ae->{-under} ||($ae->{-under} =~/^(?:system|startup|shutdown)/)
	? ($s->{-dircrs}, $s->{-dirmrs} &&'-dirmrs')
	: ($s->{-dircru}, $s->{-dirmru} &&'-dirmru');
 my @w =(!@txt
	? ('# ' .$s->strtime() .' ' .$s->{-prgcn} .' assignment registration'
	  ,'# ' .join('; ', map {defined($s->{$_}) && !ref($s->{$_}) ? ($_ .'=' .$s->{$_}) : ()
		} qw(-host -node -user -domain -uadmin -usystem))
	  ,(map {defined($ae->{$_}) && !ref($ae->{$_}) ? ('# ' .$_ .'=' .$ae->{$_}) : ()
		} sort {$a cmp $b} keys %$ae)
		)
	: ('',map {"# $_"} @txt)
	);
 if ($m) {
	$s->fpthmk($s->acRfm($m));
	local $SIG{__DIE__}="DEFAULT";
	eval{$s->fwrite((!@txt ? '' : '>>') .$s->acRfm($m, $ae->{-id}), @w)}
	|| ($^W && $@ && warn($@));
 }
 $s->fwrite((!@txt ? '' : '>>') .$d .$s->{-dirm} .$ae->{-id}, @w);
}


sub acRegDel {	# Assignment call registration delete
		# (assignment, ? max time) -> success
 my ($s, $ae, $ast) =@_;
 my ($d, $m) =!$ae->{-under} ||($ae->{-under} =~/^(?:system|startup|shutdown)/)
	? ($s->{-dircrs}, $s->{-dirmrs} &&'-dirmrs')
	: ($s->{-dircru}, $s->{-dirmru} &&'-dirmru');
 my $f =$d .$s->{-dirm} .$ae->{-id};
 my $fm=$m && $s->acRfm($m, $ae->{-id});
 return(0) if !-e $f;
 if ($ast) {
	my @st =stat($f);
	return(0) if $st[9] && ($s->strtime($st[9]) gt $ast);
 }
 unlink($fm)
	||($^W && warn("unlink('$fm'): " .$s->erros))
	if $fm && (-e $fm);
 unlink($f)
	||$s->error("unlink('$f'): " .$s->erros);
}


sub acRegRen {	# Assignment call register rename
 my ($s, $ae, $f2) =@_;		# (ass, ext)
 my ($d, $m) =!$ae->{-under} ||($ae->{-under} =~/^(?:system|startup|shutdown)/)
	? ($s->{-dircrs}, $s->{-dirmrs} &&'-dirmrs')
	: ($s->{-dircru}, $s->{-dirmru} &&'-dirmru');
 my $f1=$d .$s->{-dirm} .$ae->{-id};
 $f2 =$d .$s->{-dirm} .$ae->{-id} .$f2;
 return(0) if !-e $f1;
 if ($m) {
	my $m1 =$s->acRfm($m, $ae->{-id});
	my $m2 =$s->acRfm($m, $ae->{-id} .$_[2]);
	((!-e $m2) || unlink($m2))
	&& (rename($m1, $m2))
	||($^W && warn("rename('$m1','$m2'): " .$s->erros))
		if -e $m1;
 }
 ((!-e $f2) || unlink($f2))
 && (rename($f1, $f2))
	||$s->error("rename('$f1','$f2'): " .$s->erros);
}


sub acRegChk {	# Assignment call registration check
 my ($s, $ae, $ast, $xx) =@_;	# (ass, ? max time) -> registered
 $ae =$s->dGet($ae) if !ref($ae);
 my $d =!$ae->{-under} ||($ae->{-under} =~/^(?:system|startup|shutdown)/)
	? $s->{-dircrs}
	: $s->{-dircru};
 my $f =$d .$s->{-dirm} .$ae->{-id};
 return($xx ||0) if !-e $f;
 return(1) if !$ast;
 my @st =stat($f);
 return(0) if $st[9] && ($s->strtime($st[9]) le $ast);
 1
}


sub acRegSync {	# Assignments sync to manager
 my ($s, $m) =@_;
 my ($dc, $dm) =$m eq 'system' ? ($s->{-dircrs}, $s->{-dirmrs} &&'-dirmrs') : ($s->{-dircru}, $s->{-dirmru} &&'-dirmru');
 return(0) if !$dm;
 eval('use File::Copy (); 1') if $^O ne 'MSWin32';
 my %ha;
 $s->fpthmk($s->acRfm($dm));
 foreach my $f ($s->fglob($dc .$s->{-dirm} .'*')) {
	my $e =$f =~/[\\\/]([^\\\/]+)$/ ? $1 : $f;
	my $w =$s->acRfm($dm, $e);
	$ha{lc($w)} =$f;
	next if -e $w && ((-s $f) eq (-s $w));
	($^O eq 'MSWin32'
	? Win32::CopyFile($f, $w, 1)
	: File::Copy::syscopy($f, $w))
	||($^W && warn("fcopy('$f','$w'): " .$s->erros($w)));
 }
 foreach my $w ($s->fglob($s->acRfm($dm,'*'))) {
	next	if $ha{lc($w)};
	# next	if ($w =~/\.[^\\\/]*$/) && ($w !~/\.(?!err|do)$/i);
	unlink($w) ||($^W && warn("unlink('$w'): " .$s->erros($w)));
 }
 1
}


sub acQuery {	# Assignments pending query
		# ([assignments]) -> [filtered]
 my($s,$q,$n,$u) =@_;
 $s->acRegDir('system')	if !$q || ($q eq 'system');
 $s->acRegDir('user')	if !$q || ($q eq 'user');
 my $as =$s->dQuery($q,$n,$u);
 my $ds =$s->{-dircrs} && (-e $s->{-dircrs}) && ($s->{-dircrs} .$s->{-dirm});
 my $du =$s->{-dircru} && (-e $s->{-dircru}) && ($s->{-dircru} .$s->{-dirm});
 [map {	my $r =
	!$_ || !$_->{-id} ||($_->{-under} && ($_->{-under} !~/^(?:system|user)/))
	? undef
	: !$_->{-under} || ($_->{-under} =~/^(?:system)/)
	? (!$ds ? undef : -e ($ds .$_->{-id}) ? undef : $_)
	: $_->{-under} && ($_->{-under} =~/^(?:user)/)
	? (!$du ? undef : -e ($du .$_->{-id}) ? undef : $_)
	: $_;

	!$r
	? ()
	: $r->{-do} || $r->{-menu} || $r->{-mcf} || $r->{-doop1}
	? ($r)
	: $r->{-doop}
		&& (grep {!$_->[2] || !$s->acRegChk($_->[1],$_->[2],1)
				} @{$r->{-doop}})
	? ($r)
	: ()
	} @$as]
}


sub acRun {	# Assignment call run
		# (assignment, ?-operation ||'-do')
 my ($s, $ae, $op, @arg) =@_;
 $op ='-do' if !$op;

 if ($ae->{-doop}) {
	my $x =1;
	foreach my $e (@{$ae->{-doop}}) {
		my $e1 =$s->dGet($e->[1]);
		return($s->error("acRun(): not found '" .$e->[1] ."' assignment"))
			if !$e1;
		$s->acRun($e1, $e->[0], $#$e >1 ? @$e[2..$#$e] : ());
		$x =0	if ($e->[0] !~/(?:-redo|-unreg)/)
			|| !$e->[2];
	}
	return(1) if $x && ($op eq '-do') && !$ae->{$op};
 }

 if ($op eq '-unreg') {
	return($s->acRegDel($ae,@arg)||1)
 }
 elsif ($op eq '-redo') {
	return($s->acRegDel($ae,@arg)
		? $s->acRun($ae)
		: 1)
 }
 elsif ($op =~/^(?:-unmenu)/) {
	return($s->meDel($ae))
 }
 elsif (($op !~/^(?:-do|-undo)/)
	||(!$ae->{$op} &&($op =~/^(?:-undo)/))
		) {
	return($s->error('acRun(): Unimplemented ' .$ae->{-id} .'{' .$op .'}'));
 }

 my $reg =($op eq '-do') && (!$ae->{-under} ||($ae->{-under} =~/^(?:system|user)/));
 $s->acReg($ae)		if $reg;
 return(1)		if !$ae->{$op} && !$ae->{-menu} && !$ae->{-mcf};
 $s->meStore($ae)	if $op eq '-do';
 $s->meDel($ae)		if $op eq '-undo';
 return(1)		if !$ae->{$op};
 my $cmd =$ae->{$op};
    $cmd =$1 if $cmd =~/^[!?](.*)/;
 local $ENV{SMLOG} =	  !$ae->{-under} ||($ae->{-under} =~/^(?:system)/)
			? $s->{-dircrs} .$s->{-dirm} .$ae->{-id}
			: $ae->{-under} =~/^(?:user)/
			? $s->{-dircru} .$s->{-dirm} .$ae->{-id}
			: ($s->acRfm($ae->{-under}, $ae->{-id})
				||($^O eq 'MSWin32' ? 'nul' : 'nil'));
 local $ENV{SMID}  =$ae->{-id};
 print $cmd,"\n";
 my($r, $err);
 if ($cmd =~/^do\s(.+)$/) {
	$cmd =$1;
	$r =eval{$s->fread($cmd)};
	if (!$r) {
		$err ="do '$cmd': $@";
	}
	elsif (!($r =eval("sub{$r}"))) {
		$err ="do '$cmd': $@";
	}
	elsif (!defined($r =eval{&$r($s, $ae)}||0)) {
		$err ="do '$cmd': $@";
	}
	elsif (!$r) {
		$err ="do '$cmd': " .(defined($r) ? $r : 'undef');
	}
 }
 else {
	# $cmd =~s/\$ENV\{SMLOG\}/'"' .$ENV{SMLOG} .'"'/ge;
	$r =system($cmd);
	if ($r <0) {
		$r =0;
		$err ="system '$cmd': " .$s->erros;
	}
	else {
		$r  =1;
		my $rc =($? >> 8);
		$reg && $s->acReg($ae, '', '-exit=' .$rc);
		$err ="system '$cmd': $rc"	# unsuccess
			if 	(($ae->{$op} =~/^\?/) && $rc)
			||	(($ae->{$op} =~/^\!/) && !$rc);
	}
 }
 if ($err) {
	$err .="; $@"	if $reg && !eval{$s->acRegRen($ae, '.err')};
	$err .="; $@"	if ($op eq '-do') && !eval{$s->meDel($ae)};
	return($s->error($err));
 }
 $s->meStore($ae)	if $op eq '-do';
 if ($ae->{-doop1}) {
	foreach my $e (@{$ae->{-doop1}}) {
		$s->acRun($s->dGet($e->[1]), $e->[0], $#$e >1 ? @$e[2..$#$e] : ())
	}
 }
 $r
}


sub alRun {	# Assignments list run
		# ([list], ? ask, ? chk net) -> true
 my ($s, $al, $ask, $nfa) =@_;
 # !$ask - all assignments in order listed
 # system assignents - all, than user assignments
 # user assignments until the first system assignment
 return(1) if !@$al;
 if ($nfa) {
	foreach my $e (qw(-dirmrs -dirmls)) {
		next	if !$s->{$e}
			|| (($s->acRfm($e) ||'') !~/^(.+?)[\\\/][^\\\/]+$/);
		local *DIR;
		if (opendir(DIR, $1))	{closedir(DIR)}
		else			{$nfa =0 if !-e $1}
		last;
	}
 }
 local ($ENV{SML1},$ENV{SML2})
	=($s->acRfm($s->{-runmode},'*') ||'') =~/^([^\*]+)\*(.*)$/
	? ($1, $2)
	: ('','');
 $ENV{SML1} && $s->fpthmk($s->acRfm($s->{-runmode})) 
	if $nfa ||!defined($nfa);
 my ($al1, $al2) =([],[]);
 my $x =0;
 if (!$ask) {
	$al1 =$al;
 }
 elsif (($^O eq 'MSWin32') && Win32::IsWin95) {
	$al1 =$al;
 }
 elsif (defined($nfa) && !$nfa && ($s->{-runmode} =~/^(?:agent|apply)/)) {
	$al2 =$al;
 }
 elsif ($s->{-runmode} =~/^(?:startup|agent|apply)/) {
	foreach my $ae (@$al) {
		if (!$ae->{-under} || ($ae->{-under} eq 'system')) {
			push @$al1, $ae
		}
		else {
			push @$al2, $ae;
			$x =1;
		}
	}
 }
 elsif ($s->{-runmode} =~/^(?:logon|runapp)/) {
	foreach my $ae (@$al) {
		last if $x;
		if ($ae->{-under} && ($ae->{-under} ne 'system')) {
			push @$al1, $ae
		}
		else {
			push @$al2, $ae;
			$x =1;
		}
	}
 }
 if ($ask && scalar(@$al1)) {
	return(0)
	if !$s->mesg('yn'
		, $s->{-lang} eq 'ru'
		? (" §­ ç¥­¨ï ª ¨á¯®«­¥­¨î", "à¨¬¥­¨âì ­ §­ ç¥­¨ï?")
		: ("Assignments to be executed", "Apply assignments?")
		,map {$_->{-id}
			. ' (' .($_->{-under} ||'system')
			. ') '
			.($_->{-cmt} ||$_->{-do} ||($_->{-doop} && join('; ', map {join(' ', @$_)} @{$_->{-doop}})) ||'')
			} @$al1
			, ($s->{-runmode} 
				&& ($s->{-runmode} =~/^(?:startup|agent|apply|runapp)/) 
				? @$al2 
				: ()));
 }
 foreach my $ae (@$al1) {
	local $s->{-asgid} =$ae->{-id};
	print "\n"
		, $ae->{-id}
		, " ("
		, $ae->{-under} ||'system'
		, ") "
		, $ae->{-cmt} ||$ae->{-do} ||($ae->{-doop} && join('; ', map {join(' ', @$_)} @{$ae->{-doop}})) ||''
		, "\n";
	$s->acRun($ae);
	if ($ae->{-last}) {
		$s->mesg('ok'
			, $s->{-lang} eq 'ru'
			? ("’à¥¡ã¥âáï ¯¥à¥§ £àã§ª ", "¥à¥§ ¯ãáâ¨â¥ ª®¯ìîâ¥à ¤«ï ¯à®¤®«¦¥­¨ï")
			: ("Restart needed", "Restart the computer to continue")
			);
		return(1);
	}
 }
 if ($ask && scalar(@$al2) && ($s->{-runmode} =~/^(?:logon|runapp|agent|apply)/)) {
	my $v =
	$s->mesg(($^O eq 'MSWin32') && Win32::IsWinNT() ? 'oc' : 'ok'
		, $s->{-lang} eq 'ru'
		? (" §­ ç¥­¨ï ª ¨á¯®«­¥­¨î", "¥à¥§ ¯ãáâ¨â¥ ª®¯ìîâ¥à ¤«ï ¯à®¤®«¦¥­¨ï")
		: ("Assignments to be executed", "Restart the computer to continue")
		,map {$_->{-id}
			. ' (' .($_->{-under} ||'system')
			. ') '
			.($_->{-cmt} ||$_->{-do} ||($_->{-doop} && join('; ', map {join(' ', @$_)} @{$_->{-doop}})) ||'')
			} @$al2);
	Win32::InitiateSystemShutdown($s->{-node}, $s->{-prgcn}, 30, 0, 1)
		if $v && ($^O eq 'MSWin32') && Win32::IsWinNT;
 }
 1;
}


sub runmngr {	# Run as manager?
 (!$_[1]
 || (($_[1] =~/^(?:query|refresh)$/i) 
	|| ($_[2] && ($_[2] eq 'say') && ($_[1] eq 'agent'))))
 && getlogin()
}


sub runuser {	# Run as user?
 $_[1] && ($_[1] =~/^(?:logon|logoff|runapp)$/i) && getlogin()
}


sub Run {	# Run module
 my($s,@arg) =@_;
 local $SELF =$s;
 local $_;
 if ($s->{-runrole} && $arg[0]) {
	return(0) if $arg[0]
		&& (	  $s->{-runrole} =~/^(?:mngr|manager)$/i
			? join(' ',@arg) !~/^(?:query|refresh|agent say)\b/i
			: $s->{-runrole} =~/^(?:query)$/i
			? join(' ',@arg) !~/^(?:query)\b/i
			: join(' ',@arg) =~/^(?:refresh|agent say)\b/i)
 }
 if (!$arg[0]) {
	$s->banner();
	print "Usage:\n\t$^X $0 runMode args\n";
	print "Management Run Modes:\n";
	print "\t'query' (mode|'undef', ?node|'undef', ?user|'undef');\n";
	print "\t'refresh', 'refresh pressing';\n";
	print "\t'agent say' node ?minutes, 'agent say' node 'agent'...\n";
	print "Desktop Run Modes:\n";
	print "\t'startup', 'startup agent' ?minutes;\n";
	print "\t'logon', 'logoff', 'shutdown'.\n";
	print "Non-obvious Desktop Run Modes:\n";
	print "\t'runapp'; 'agent' ('start'|'stop'|'loop'|'apply') minutes.\n";
	return($s->error("Run(): run mode required"));
 }
 $s->set(-runmode =>$arg[0]);
 $s->errinfo(join('; ', map {defined($s->{$_}) ? ($_ .'=' .$s->{$_}) : ()
	} qw(-mgrcall -host -node -hostdom -user -domain -dirmcf)));

 local *NETLCK;
 if ( (($s->{-runmode} =~/^(?:startup|shutdown)$/)
	||($s->{-runmode} eq 'agent') && ($arg[1] eq 'apply'))
 && ($_ =$s->{-dirmls} ||$s->{-dirmrs})
 && (/^([\w:]*[\\\/]*[^\\\/]+[\\\/][^\\\/]+)/)) {
	$s->errinfo("NETLCK('$1'): "
		.(opendir(NETLCK,$1)
		? 'ok'
		: $s->erros()))
 }

 my $l;
 if ($s->{-runmode} eq 'startup') {
	@$s{qw(-atow -atov)} =($s->{-atoy}, 1);
	local *DIRL; ($_ =$s->{-dirmrs} ||$s->{-dirmls}) && (/^([\w:]*[\\\/]*[^\\\/]+[\\\/][^\\\/]+)/) && opendir(DIRL,$1);
	if ($arg[1]
	&& ($^O eq 'MSWin32') && Win32::IsWinNT) {
		splice @arg, 1, 0, 'agent', 'start'
			if $arg[1] =~/^\d+$/;
		$arg[2] ='start'
			if !$arg[2];
		$s->Run(@arg[1..$#arg]);
		$s->set(-runmode =>$arg[0]);
		print "\n";
	}
	$s->banner();
	local $s->{-ymyn} =$s->{-yasg};
	local ($s->{-dca}, $s->{-dla}) =(1, $s->{-dla});
	$l =$s->dQuery($s->{-runmode}, 1);
	$s->alRun($l)	if @$l;
	$l =$s->acQuery('system', 1);
	$s->alRun($l,1)	if @$l;
	$s->acRegSync('system');
	$l =$s->dQuery('startup1', 1);
	$s->alRun($l)	if @$l;
 }
 elsif ($s->{-runmode} eq 'shutdown') {
	@$s{qw(-atow -atov)} =($s->{-atoy}, 1);
	$l =$s->dQuery($s->{-runmode}, 1);
	$s->alRun($l)	if @$l;
 }
 elsif ($s->{-runmode} eq 'logon') {
	@$s{qw(-atow -atov)} =($s->{-atoy}, 1);
	$s->banner();
	$s->ulogon('w');
	local $s->{-ymyn} =$s->{-yasg};
	local ($s->{-dca}, $s->{-dla}) =(1, $s->{-dla});
	if (($^O eq 'MSWin32') && Win32::IsWin95) {
		$l =$s->dQuery('startup', 1, 1);
		$s->alRun($l)	if @$l;
		$l =$s->acQuery('system', 1, 1);
		$s->alRun($l,1)	if @$l;
		$s->acRegSync('system');
		$l =$s->dQuery('startup1', 1, 1);
		$s->alRun($l)	if @$l;
	}
	$l =$s->dQuery($s->{-runmode}, 1, 1);
	$s->alRun($l)	if @$l;
	$l =$s->acQuery('user', 1, 1);
	$s->alRun($l,1)	if @$l;
	$s->acRegSync('user');
	$l =$s->dQuery('logon1', 1, 1);
	$s->alRun($l)	if @$l;
 }
 elsif ($s->{-runmode} eq 'logoff') {
	$l =$s->dQuery($s->{-runmode}, 1, 1);
	$s->alRun($l)	if @$l;
 }
 elsif ($s->{-runmode} eq 'runapp') {
	$s->banner();
	local ($s->{-dca}, $s->{-dla}) =(1, $s->{-dla});
	$l =$s->dQuery('runapp', 1, 1);
	$s->alRun($l)	if @$l;
	$l =$s->acQuery('', 1, 1);
	$s->alRun($l,1)	if @$l;
 }
 elsif ($s->{-runmode} eq 'agent') {
	# (start | stop | loop | apply | say), minutes
	$s->banner();
	return($s->error('Run(): No agent option'))
		if !$arg[1] || !($^O eq 'MSWin32') 
		|| !Win32::IsWinNT();
	if ($arg[1] eq 'say') {
		return($s->error('Run(): node name required'))
			if !$arg[2];
		return($s->conn($arg[2]
			, $arg[3] && ($arg[3] eq 'agent')
			? [$s->{-mgrcall} .' ' .join(' ',@arg[3..$#arg])
			  ,'at']
			: $arg[3] && ($arg[3] eq 'redo')
			? [$s->{-mgrcall} .' agent ' .join(' ',@arg[3..$#arg])]
			: $arg[3] && ($arg[3] !~/^\d+$/)
			? [join(' ',@arg[3..$#arg])
				]
			: [$s->{-mgrcall} .' agent stop'
			  ,$s->{-mgrcall} .' agent loop' .($arg[3] ? ' ' .$arg[3] : '')
			  ,'at']))
	}
	elsif ($arg[1] eq '-unreg') {
		return($s->error('Run(): assignment id required'))
			if !$arg[2];
		my $ae =$s->dGet($arg[2]);
		return($s->error("Run(): not found '" .$arg[2] ."' assignment"))
			if !$ae;
		$s->acRegDir('system');
		return($s->acRegDel($ae));
	}
	elsif ($arg[1] eq '-redo') {
		return($s->error('Run(): assignment id required'))
			if !$arg[2];
		my $ae =$s->dGet($arg[2]);
		return($s->error("Run(): not found '" .$arg[2] ."' assignment"))
			if !$ae;
		$s->acRegDir('system');
		$s->acRegDel($ae);
		return($s->acRun($ae))
	}
	my $mgr =$0 && Win32::GetFullPathName($0);
	   $mgr =$mgr && Win32::GetShortPathName($mgr);
	   $mgr =$mgr && ($mgr =~/[\\\/]/)
		? ( $^X && ($^X =~/[\\\/]/)
		  ? "$^X $mgr"
		  : $s->{-mgrcall} =~/^([^\s]+\s)/
		  ? $1 .$mgr
		  : $s->{-mgrcall})
		: $s->{-mgrcall};
	my $la =0;
	if ($arg[1] =~/^(?:start|stop|loop)$/) {
		my $q =($mgr =~/([\\\/][^\\\/]+)$/ ? $1 : (' '. $mgr))
			.' agent ';
		foreach my $l (`at`) {
			next if $l !~/\Q$q\E[\w\d\s]*[\r\n]*$/i;
			next if $l !~/(\d+)/;
			my $v =$1;
			if (($l =~/\sapply[\s\r\n]*$/)
			&& ($arg[1] eq 'loop')) {
				$la =1;
			}
			elsif ($v) {
				print "at $v /d $l";
				system("at $v /d")
			}
		}
		return(1) if $arg[1] eq 'stop';
	}
	if ($la && ($arg[1] eq 'loop')) {
	}
	elsif ($arg[1] eq 'loop') {
		$s->ulogon('r');
		$l =$s->acQuery($s->{-user} ? '' : 'system', 1, 1);
		if (@$l) {
			my $t0 =3;
			my $t1 =$s->strtime($s->timeadd(time(),0,0,0,0
				, $arg[2] && ($arg[2] =~/^\d+$/) && ($arg[2] <$t0)
				? $arg[2]
				: $t0));
			$t1 =$1 if $t1 =~/\s([^\s]+)/;
			my $cmd ="at $t1 /interactive"
				# .' ' .($ENV{COMSPEC} ||'cmd.exe')
				# .' /c start "' .$s->{-prgcn} .' agent" /Dc:\\'
				." $mgr agent apply";
			print "$cmd\n";
			if (system($cmd) <0) {
				return($s->error("$cmd: " .$s->erros))
			}
		}
	}
	elsif ($arg[1] eq 'apply') {
		local $s->{-runmode} ='apply';
		$s->ulogon('r');
		$l =$s->acQuery($s->{-user} ? '' : 'system', 1, 1);
		$s->alRun($l,1,1)	if @$l;
	}
	if (1 && ($arg[1] ne 'apply')) {
		my $t1 =$arg[2] && ($arg[2] =~/^\d+$/)
			? $s->strtime($s->timeadd(time(),0,0,0,0,$arg[2]))
			: $arg[1] eq 'start'
			? $s->strtime($s->timeadd(time(),0,0,0,0,5))
			: $s->strtime($s->timeadd(time(),0,0,0,1));
		$t1 =$1 if $t1 =~/\s([^\s]+)/;
		my $cmd ="at $t1 $mgr agent loop"
			.($arg[2] && ($arg[2] =~/^\d+$/) ? ' ' .$arg[2] : '');
		print "$cmd\n";
		if (system($cmd) <0) {
			return($s->error("$cmd: " .$s->erros))
		}
	}
 }
 elsif ($s->{-runmode} eq 'refresh') {
	$s->dQuery();
	$l =$s->dQuery('-mcf');
	my $all =$arg[1] && ($arg[1] eq 'pressing');
	foreach my $e (@$l) {
		print $e->{-id}, $e->{-fresh} ? ' (fresh)' : '', "\n";
		$s->mcfStore($e, undef, $all || $e->{-fresh});
	}
 }
 elsif ($s->{-runmode} eq 'query') {
	$l =$s->dQuery(map {!defined($_) || ($_ eq 'undef')
				? undef
				: $_
				} @arg[1..3]);
	foreach my $ae (@$l) {
		print $ae->{-id}
		, " ("
		, $ae->{-under} ||'system'
		, ") "
		, $ae->{-cmt} ||$ae->{-do} ||($ae->{-doop} && join('; ', map {join(' ', @$_)} @{$ae->{-doop}})) ||''
		, "\n";
	}
 }
 1
}
