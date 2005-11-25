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
use IPC::Open3;
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
	#-cignor	=>undef		# -i	# command exit code ignoring
	,-echo		=>2		# -v	# echo verbosity level
	#-echot		=>undef		# -vt	# echo time including
	#-echoc		=>undef		# -vc	# echo concurrency mode
	,-clog		=>''		# ...	# command log name
	,-cline		=>[]		# ...	# command line
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
 my($s, $arg, %opt) =ref($_[1]) ? @_ : ($_[0],undef,@_[1..$#_]);
 foreach my $k (keys(%opt)) {
	next if $k !~/^-(?:\w|vt|vc)$/;
	my($n, $v) =($k, $opt{$k});
	$n =	  $n eq '-i'	? '-cignor'
		: $n eq '-v'	? '-echo'
		: $n =~/^-vt/	? '-echot'
		: $n =~/^-vc/	? '-echoc'
		: $n;
	delete $opt{$k};
	$opt{$n} =$v
 }
 if ($arg) { for (my $i=0; $i <=$#$arg; $i++) {
	if ($arg->[$i] =~/^-i(.*)$/i) {
		$opt{-cignor} =($1 eq '' ? 1 : $1)
				if !exists $opt{-cignor}
	}
	elsif ($arg->[$i] =~/^-v([\w\d]*)$/i) {
		my $v =$1;
		$opt{-echo} =$v	if !(exists $opt{-echo})  && ($v =~/^\d+$/);
		$opt{-echo} =2	if !(exists $opt{-echo})  && ($v eq '');
		$opt{-echot}=1	if !(exists $opt{-echot}) && ($v =~/^t/i);
		$opt{-echoc}=1	if !(exists $opt{-echoc}) && ($v =~/^c/i);
	}
	else {
		$opt{-clog}  =$arg->[$i];
		$opt{-cline} =[@$arg[$i+1..$#$arg]]; last;
	}
 }}
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
	map {	/[&<>\[\]{}^=;!'+,`~\s%"?*|()]/	# ??? see shell
		? do {	my $v =$_; $v =~s/"/\\"/g; '"' .$v .'"' }
		: $_ } @_[1..$#_]
}


sub qclat {		# Quote command line arg(s) total
	map {	my $v =$_;
		$v =~s/"/\\"/g;
		'"' .$v .'"'
		} @_[1..$#_]
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
	foreach my $k ('-go.txt','-run.txt','-ok.txt','-err.txt') {
		next if !-e "$fl$k";
		unlink("$fl$k")
	}
    $fl =$s->{-clog} .'-run.txt';
 my $fh =IO::File->new($fl,'w')
	|| croak("\$\$$p Error: creating '$fl': $!");
 $fh->print($s->strtime()," \$\$$p "
	,join(' ', $s->qclad(@{$s->{-cline}})),"\n");
 $fh->flush();
 local *OLDIN;	open(OLDIN,  '<&STDIN');
 local *OLDOUT; open(OLDOUT, '>&STDOUT');
 local *OLDERR; open(OLDERR, '>&STDERR');
 local *RDRIN;
 my $cl =[@{$s->{-cline}}];
 my $hi =undef;
 my $ho =undef;
	if ((@$cl>2) && ($cl->[$#$cl-1] eq '<')) {
		$ho =open(RDRIN,'<',$cl->[$#$cl]) 
			|| croak("[$p] Error: opening '" .$cl->[$#$cl] ."': $!");
		$cl =[@$cl[0..$#$cl-2]];
	}

 print(($s->{-echot} ? ($s->strtime(), ' ') : ()), "\$\$$p ", $s->{-clog}
	," = ", join(' ', $s->qclad(@{$s->{-cline}})), "\n")
	if $s->{-echo};
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
	open(STDIN,  '<&OLDIN');	close(OLDIN);
	open(STDOUT, '>&OLDOUT');	close(OLDOUT);
	open(STDERR, '>&OLDERR');	close(OLDERR);
	$fh->close();
	($?,$!,$^E,$@) =@e;
	print( 	 ($s->{-echot} ? ($s->strtime(), ' ') : ())
		,"\$\$$p "
		, ($s->{-echoc}
		? $s->{-clog} ." = "
		: 'Exit: ')
		, join(' '
		, ($r ? 0 : $?>>8 ? $?>>8 : $@ ? 255 : 255)
		, (($? & 127)||($? & 128)
		  ? '(' .($? & 127) .',' .($? & 128) .')'
		  : ())
		, ($@ ? (!($?>>8) ? '[eval] ' : '') ."$@" : ())
		, ($@ ? $! .($^E ? "($^E)" : '') : ())), "\n")
		if $s->{-echo};
	eval{STDOUT->flush(); STDERR->flush()};
	rename(	  $s->{-clog} .'-run.txt'
		, (!$r) && !$s->{-cignor}
		? ($s->{-clog} .'-err.txt')
		: ($s->{-clog} .'-ok.txt'));
	chdir($s->{-dirw}) if lc($s->getcwd()) ne lc($s->{-dirw});
 }
 elsif ($hp =eval{IPC::Open3::open3( $ho ? '<&RDRIN' : '<&STDIN'
				, $hi
				, $hi
				,($cl ->[0] eq '-e'
				? ($^X
					,'-e'
					,do{my	$v =$cl->[1]; $v=~s/"/\\"/g;
						$v =$v=~/^([\w\d:]+)->/
						? "use $1;$v"
						: $v;
						'"exit !do{' .$v .'}"'}
					,$s->qclad(@$cl[2..$#$cl]))
				: $s->qclad(@$cl)))}) {
	($!,$^E) =(0,0);
	my $r;
	while (defined($r =readline($hi))) {
		$r = $` if $r =~/[\r\n]*$/;
		print $r,"\n"	if $s->{-echo} && !$s->{-echoc};
		$fh->print($r,"\n");
	}
	waitpid($hp,0);
	my @e =($?,$!,$^E,$@);
	{	eval{STDOUT->flush(); STDERR->flush()};
		open(STDIN,  '<&OLDIN');	close(OLDIN);
		open(STDOUT, '>&OLDOUT');	close(OLDOUT);
		open(STDERR, '>&OLDERR');	close(OLDERR);
		eval{STDOUT->flush(); STDERR->flush()}};
	($?,$!,$^E,$@) =@e;
	print( 	 ($s->{-echot} ? ($s->strtime(), ' ') : ())
		,"\$\$$p "
		, ($s->{-echoc}
		? $s->{-clog} ." = "
		: 'Exit: ')
		,($?>>8)
		,($?>>8 ? " $!" : '')
		,"\n") if $s->{-echo};
	($?,$!,$^E,$@) =@e;
	$fh->print($s->strtime()
		, " \$\$$p Exit: "
		, ($?>>8)
		, (($? & 127)||($? & 128)
		  ? ' (' .($? & 127) .',' .($? & 128) .')'
		  : '')
		, ($?>>8 ? " $!" .($! && $^E ? " ($^E)" : '') : ''), "\n");
	$fh->close();
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
	open(STDIN,  '<&OLDIN');	close(OLDIN);
	open(STDOUT, '>&OLDOUT');	close(OLDOUT);
	open(STDERR, '>&OLDERR');	close(OLDERR);
	($?,$!,$^E,$@) =@e;
	$fh->print($s->strtime(), " \$\$$p Exit: 255 [IPC] $! $@\n");
	$fh->close();
	eval{STDOUT->flush(); STDERR->flush()};
	rename(($s->{-clog} .'-run.txt'), ($s->{-clog} .'-err.txt'));
	chdir($s->{-dirw}) if lc($s->getcwd()) ne lc($s->{-dirw});
	($?,$!,$^E,$@) =@e;
	croak("\$\$$p Exit: 255 [IPC] $! $@");
 }
 $s
}
