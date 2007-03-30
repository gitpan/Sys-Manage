#!perl -w
#
# Sys::Manage::CmdEscort - Sys::Manage::Cmd command execution escort
#
# makarow, 2005-09-10
#
# 

package Sys::Manage::CmdEscort;
require 5.000;
require Exporter;
use strict;
use Carp;
use IO::File;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
@ISA	= qw(Exporter);
@EXPORT	= qw(CmdEscort);

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
	,-dirw		=>do{$^O eq 'MSWin32'	# directory working
			? Win32::GetCwd()
			: eval('use Cwd; Cwd::getcwd')}
	#-logpid	=>undef			# pid file
	#-cignor	=>undef		# -i	# command exit code ignoring
	,-echo		=>2		# -v	# echo verbosity switches
					# -vct	# ... concurrency, time including
	,-echol		=>2		# -v#	# ... verbosity level
	#-esc		=>undef		# -esc	# cmd line escaped
	,-clog		=>''		# ...	# command log name
	,-cline		=>[]		# ...	# command line
	, %$s
	);
 $s->set(@_);
 $s
}

sub DESTROY {
 my $s =$_[0];
 if ($s->{-logpid}) {
	my $t =time();
	while ((-e $s->{-logpid}) 
	&& !eval{unlink($s->{-logpid})}) {
		last if time() -$t >60;
		sleep(10)
	}
	$s->{-logpid}=undef
 }
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
 my($s, $arg, %opt) =ref($_[1]) ? @_ : ($_[0],undef,@_[1..$#_]);
 foreach my $k (keys(%opt)) {
	next if $k !~/^-(?:\w|vt|vc|esc)$/;
	my($n, $v) =($k, $opt{$k});
	$n =	  $n eq '-i'	? '-cignor'
		: $n eq '-v'	? '-echo'
		: $n;
	delete $opt{$k};
	$opt{$n} =$v
 }
 if ($arg) { for (my $i=0; $i <=$#$arg; $i++) {
	if ($arg->[$i] =~/^-i(.*)$/i) {
		$opt{-cignor} =($1 eq '' ? 1 : $1)
				if !exists $opt{-cignor}
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
	else {
		$opt{-clog}  =$arg->[$i];
		$opt{-cline} =[$opt{-esc} ? $s->qclau(@$arg[$i+1..$#$arg]) : @$arg[$i+1..$#$arg]];
		last;
	}
 }}
 $opt{-echol} =$opt{-echo} =~/(\d+)/ ? $1 : 2
		if $opt{-echo};
 foreach my $k (keys(%opt)) {
	$s->{$k} =$opt{$k};
 }
 $s
}


sub getcwd {		# Working directory
	$^O eq 'MSWin32'
	? Win32::GetCwd()
	: eval('use Cwd; Cwd::getcwd')
}


sub strtime {		# Log time formatter
	my @t =localtime();
	 join('-', $t[5]+1900, map {length($_)<2 ? "0$_" : $_} $t[4]+1,$t[3]) 
	.' ' 
	.join(':', map {length($_)<2 ? "0$_" : $_} $t[2],$t[1],$t[0])
}


sub qclad {		# Quote command line arg(s) on demand
	map {	!defined($_) || ($_ eq '')
		? qclat($_[0], $_)
		: /[&<>\[\]{}^=;!'+,`~\s%"?*|()]/	# ??? see shell
		? qclat($_[0], $_)
		: $_ } @_[1..$#_]
}


sub qclat {		# Quote command line arg(s) total
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


sub copen3 {		# Command output open
 my $s =$_[0];		# (?input file, handle var, command,...) -> pid
 my $p;
 if (0) {
	$_[2] =eval('use IO::File; IO::File->new()');
	$p =open($_[2], '-|', join(' ', @_[3..$#_]) 
		.' 2>>&1'
		.($_[1] ? ' <' .$_[1] : ''));
 }
 else {
	eval('use IPC::Open3');
	local *IN;
	open(IN,'<', $_[1]) 
		|| do{	$@ ="Open('<" .$_[1] ."') -> $! ($^E)";
			return(undef)}
		if $_[1];
	my $x =($_[1] ? '<&IN' : undef);
	$p =eval{IPC::Open3::open3($x, $_[2], $_[2], @_[3..$#_])};
	eval{fileno($x) && close($x)};
	eval{fileno(IN) && close(IN)} if !defined($p) && $_[1];
 }
 $p
}



sub CmdEscort {		# New + Execute shortcut
  Sys::Manage::CmdEscort->new(@_)->execute();
}


sub execute {		# Execute command (target action)
 my $s =$_[0];		# ( ? [command line], ? -option=>value,...)	-> self
    $s->set(@_[1..$#_]);
 my $p =($ENV{SMPID} && ($ENV{SMPID}=~/^\d+$/) && ($ENV{SMPID} ne $$)
	? ($ENV{SMPID} .',') 
	: ('')) .$$;

 my $fl =$s->{-clog};
	foreach my $k ('-go.txt','-run.txt','-ok.txt','-err.txt','-erg.txt') {
		next if !-e "$fl$k";
		unlink("$fl$k")
	}
    $fl =$s->{-clog} .'-run.txt';
 my $fh =IO::File->new($fl,'w')
	|| croak("\$\$$p Error: creating '$fl': $!");
 $s->{-logpid} =$s->{-clog} =~/([^\\\/]+)([\\\/])([^\\\/]+)[\\\/]([^\\\/]+)$/ 
	? $` .$2 .'var' .$2 .$$ .'-' .$1 .'-' .$3 .'-' .$4 .'.pid'
	: undef;
 eval{$s->{-logpid} =link($fl, $s->{-logpid}) && $s->{-logpid}; $! =$^E=0} 
	if $s->{-logpid};
 $fh->print($s->strtime()," \$\$$p "
	,join(' ', $s->qclad(@{$s->{-cline}})),"\n");
 $fh->flush();
 local *OLDIN;	fileno(STDIN)  && open(OLDIN,  '<&STDIN');
 local *OLDOUT; fileno(STDOUT) && open(OLDOUT, '>&STDOUT');
 local *OLDERR; fileno(STDERR) && open(OLDERR, '>&STDERR');
 my $cl =[@{$s->{-cline}}];
 my $hi =undef;
 my $ho =undef;
	if ((@$cl>2) && ($cl->[$#$cl-1] eq '<')) {
		$ho =$cl->[$#$cl];
		$cl =[@$cl[0..$#$cl-2]];
	}

 print(($s->{-echo} =~/t/ ? ($s->strtime(), ' ') : ()), "\$\$$p ", $s->{-clog}
	," = ", join(' ', $s->qclad(@{$s->{-cline}})), "\n")
	if $s->{-echol};
 my $hp;
 ($?,$!,$^E) =(0,0,0);
 if ($cl->[0] && ($cl->[0] =~/^(do|eval)$/)) {
	local @ARGV =@$cl[2..$#$cl];
	open(STDOUT, '>&' .$fh->fileno());
	open(STDERR, '>&' .$fh->fileno());
	($?,$!,$^E) =(0,0,0);
	my $r =   $cl->[0] eq 'do'
		? do($cl->[1])
		: ref($cl->[1])
		? eval{&{$cl->[1]}($s,@ARGV)}
		: $cl->[1]=~/^([\w\d:]+)->/
		? eval('use ' .$1 .';' .$cl->[1])
		: eval($cl->[1]);
	my @e =($?,$!,$^E,$@);
	$fh->flush();
	($?,$!,$^E,$@) =@e;
	$fh->print($s->strtime(), " \$\$$p Exit: "
		, join(' '
		, ($r ? 0 : $?>>8 ? $?>>8 : $@ ? 255 : 255)
		, (($? & 127)||($? & 128)
		  ? '(' .($? & 127) .',' .($? & 128) .')'
		  : ())
		, ($@ ? (!($?>>8) ? '[eval] ' : '') ."$@" : ())
		, ($@ ? $! .($^E ? "($^E)" : '') : ())), "\n");
	eval{STDOUT->flush(); STDERR->flush()};
	fileno(OLDIN)  && open(STDIN,  '<&OLDIN');  fileno(OLDIN)  && close(OLDIN);
	fileno(OLDOUT) && open(STDOUT, '>&OLDOUT'); fileno(OLDOUT) && close(OLDOUT);
	fileno(OLDERR) && open(STDERR, '>&OLDERR'); fileno(OLDERR) && close(OLDERR);
	$fh->close();
	eval{$s->{-logpid} =!(-e $s->{-logpid}) || unlink($s->{-logpid}) ? undef : $s->{-logpid}
		} if $s->{-logpid};
	($?,$!,$^E,$@) =@e;
	print( 	 ($s->{-echo} =~/t/ ? ($s->strtime(), ' ') : ())
		,"\$\$$p "
		,($s->{-echo} =~/c/ ? $s->{-clog} ." = " : 'Exit: ')
		, join(' '
		, ($r ? 0 : $?>>8 ? $?>>8 : $@ ? 255 : 255)
		, (($? & 127)||($? & 128)
		  ? '(' .($? & 127) .',' .($? & 128) .')'
		  : ())
		, ($@ ? (!($?>>8) ? '[eval] ' : '') ."$@" : ())
		, ($@ ? $! .($^E ? "($^E)" : '') : ())), "\n")
		if $s->{-echol};
	eval{STDOUT->flush(); STDERR->flush()};
	rename(	  $s->{-clog} .'-run.txt'
		, (!$r) && !$s->{-cignor}
		? ($s->{-clog} .'-err.txt')
		: ($s->{-clog} .'-ok.txt'));
	chdir($s->{-dirw}) if lc($s->getcwd()) ne lc($s->{-dirw});
 }
 elsif ($hp =$s->copen3(  $ho
			, $hi
			,($cl ->[0] eq '-e'
			? ($^X
				,'-e'
				,do{my	$v =$cl->[1]; $v=~s/"/\\"/g;
					$v =	$v=~/^([\w\d:]+)->/
						? "use $1;$v"
						: $v;
					'"exit !do{' .$v .'}"'}
				,'--'
				,$cl ->[1] =~/-esc=>1/
				? $s->qclae(@$cl[2..$#$cl])
				: $s->qclad(@$cl[2..$#$cl])
				)
			: $s->qclad(@$cl)))) {
	($!,$^E) =(0,0);
	my $r;
	while (defined($r =readline($hi))) {
		$r = $` if $r =~/[\r\n]*$/;
		print $r,"\n"	if $s->{-echol} && ($s->{-echo} !~/c/);
		$fh->print($r,"\n");
	}
	waitpid($hp,0);
	my @e =($?,$!,$^E,$@);
	{	eval{STDOUT->flush(); STDERR->flush()};
		fileno(OLDIN)  && open(STDIN,  '<&OLDIN');  fileno(OLDIN)  && close(OLDIN);
		fileno(OLDOUT) && open(STDOUT, '>&OLDOUT'); fileno(OLDOUT) && close(OLDOUT);
		fileno(OLDERR) && open(STDERR, '>&OLDERR'); fileno(OLDERR) && close(OLDERR);
		eval{STDOUT->flush(); STDERR->flush()}};
	($?,$!,$^E,$@) =@e;
	print( 	 ($s->{-echo} =~/t/ ? ($s->strtime(), ' ') : ())
		,"\$\$$p "
		,($s->{-echo} =~/c/ ? $s->{-clog} ." = " : 'Exit: ')
		,($?>>8)
		,($?>>8 ? " $!" : '')
		,"\n") if $s->{-echol};
	($?,$!,$^E,$@) =@e;
	$fh->print($s->strtime()
		, " \$\$$p Exit: "
		, ($?>>8)
		, (($? & 127)||($? & 128)
		  ? ' (' .($? & 127) .',' .($? & 128) .')'
		  : '')
		, ($?>>8 ? " $!" .($! && $^E ? " ($^E)" : '') : ''), "\n");
	$fh->close();
	eval{$s->{-logpid} =!(-e $s->{-logpid}) || unlink($s->{-logpid}) ? undef : $s->{-logpid}
		} if $s->{-logpid};
	eval{STDOUT->flush(); STDERR->flush()};
	($?,$!,$^E,$@) =@e;
	rename(	  $s->{-clog} .'-run.txt'
		, ($?>>8) && !$s->{-cignor} 
		? ($s->{-clog} .'-err.txt') 
		: ($s->{-clog} .'-ok.txt'));
	chdir($s->{-dirw}) if lc($s->getcwd()) ne lc($s->{-dirw});
 }
 else {
	my @e =($?,$!,$^E,$@);
	fileno(OLDIN)  && open(STDIN,  '<&OLDIN');  fileno(OLDIN)  && close(OLDIN);
	fileno(OLDOUT) && open(STDOUT, '>&OLDOUT'); fileno(OLDOUT) && close(OLDOUT);
	fileno(OLDERR) && open(STDERR, '>&OLDERR'); fileno(OLDERR) && close(OLDERR);
	($?,$!,$^E,$@) =@e;
	eval{$fh->print($s->strtime(), " \$\$$p Exit: 255 [IPC] $! $@\n")};
	eval{$fh->close()};
	eval{$s->{-logpid} =!(-e $s->{-logpid}) || unlink($s->{-logpid}) ? undef : $s->{-logpid}
		} if $s->{-logpid};
	eval{STDOUT->flush(); STDERR->flush()};
	rename(($s->{-clog} .'-run.txt'), ($s->{-clog} .'-err.txt'))
		|| carp("\$\$$p rename: (" .($s->{-clog} .'-run.txt')
			.', ' .($s->{-clog} .'-err.txt') .") -> $! " 
			.($^E ? " ($^E)" : '') ."\n");
	chdir($s->{-dirw}) if lc($s->getcwd()) ne lc($s->{-dirw});
	($?,$!,$^E,$@) =@e;
	croak("\$\$$p Exit: 255 [IPC] $! $@");
 }
 $s
}
