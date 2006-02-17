#!perl -w
#
# Sys::Manage::CmdFile - Systems management commands file processor
#
# makarow, 2005-10-30
#
# !!! see in source code
# 

package Sys::Manage::CmdFile;
require 5.000;
use strict;
use UNIVERSAL;
use Carp;
use IO::File;
use Fcntl qw(:DEFAULT :flock :seek :mode);

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
$VERSION = '0.52';

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
 %$s =(
	# -dofck => undef
	%$s);
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
 my($s, %opt) =@_;
 foreach my $k (keys(%opt)) {
	$s->{$k} =$opt{$k};
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
	map {	!defined($_) || ($_ eq '')
		? '""'
		: /[&<>\[\]{}^=;!'+,`~\s%"?*|()]/	# ??? see shell
		? do {	my $v =$_; $v =~s/"/\\"/g; '"' .$v .'"' }
		: $_ } @_[1..$#_]
}


sub error {		# Error final
 my $s =$_[0];		# (strings) -> undef
 my $e =join(' ', map {defined($_) ? $_ : 'undef'} @_[1..$#_]);
 eval{STDOUT->flush()};
 $@ =$e;
 croak("Error: $e\n");
 return(undef);
}


sub iofopen {		# File open
 my ($s,$f) =@_;	# (file name) -> file handle
 eval('use IO::File');
 IO::File->new($f) || $s->error("$! (iofopen,'$f')");
}



sub dofile {		# Command queue
			# (script||sub{}, comfile, ?tgtfile, ?rdrfile) -> success
 my ($s,$fqp,$fqi,$fql,$fqr) =@_;
 my ($dqb, $dqm);
 $s   =Sys::Manage::CmdFile->new() if !ref($s);
 $fqp =scalar(Win32::GetFullPathName($fqp))
	if !ref($fqp) && ($^O eq 'MSWin32');
 $dqm =!ref($fqp) && $fqp =~/([\\\/])/ ? $1 : $^O eq 'MSWin32' ? '\\' : '/';
 $dqb =ref($fqp) || !$fqp
	? undef
	: $fqp =~/(?:[\\\/]bin){0,1}[\\\/][^\\\/]+$/
	? $`
	: '.';
 $dqb =scalar(Win32::GetFullPathName($dqb))
	if $dqb && ($^O eq 'MSWin32');
 local $ENV{SMCFP} =$s->{-dofck} ? '' : $fqi;
 $fqi =$dqb .$dqm .$fqi
	if $dqb && $fqi && ($fqi =~/[\\\/][^\\\/]+$/ ? $` && (!-d $`) : 1);
 $fqi =scalar(Win32::GetFullPathName($fqi))
	if $fqi && ($^O eq 'MSWin32');
 if (!-e $fqi) {
	my $hqi =$s->iofopen('>' .$fqi);
	$hqi->print("# '",(ref($fqp) ? $0 : $fqp)
		, "' incoming command lines"
		,($fql ? " queue.\n" : " file.\n")
		,"# Contains command lines to be executed" 
		,($fql ? " and shifted to '$fql'.\n" : ".\n")
		,"# Syntax:\n"
		,"#\t# - comment row\n"
		,"#\t  - empty row, ignored\n"
		,"#\tcommand row, to be executed"
		);
	$hqi->close()
 }
 $dqm =$fqi =~/([\\\/])/ ? $1 : $^O eq 'MSWin32' ? '\\' : '/';
 $dqb =$fqi =~/[\\\/][^\\\/]+$/
	? $`
	: '.';
 $fql =$dqb .$dqm .$fql
	if $dqb && $fql && ($fql =~/[\\\/][^\\\/]+$/ ? $` && (!-d $`) : 1);
 $fql =scalar(Win32::GetFullPathName($fql))
	if $fql && ($^O eq 'MSWin32');
 $fqr =$dqb .$dqm .$fqr
	if $dqb && $fqr && ($fqr =~/[\\\/][^\\\/]+$/ ? $` && (!-d $`) : 1);
 $fqr =scalar(Win32::GetFullPathName($fqr))
	if $fqr && ($^O eq 'MSWin32');
 if ($fql && !-e $fql) {
	my $hql =$s->iofopen('>' .$fql);
	$hql->print("# '$fqi' history command file\n");
	$hql->close()
 }
 my $fqt =''; # $fqi .'.tmp'; # ??? restore procedure ???
 my $erc ='';
 if ($fqt
 && (-e $fqt)
 && (((-s $fqt)||0) > ((-s $fqi) ||0))) {
	rename($fqt, $fqi)
 }
 while (1) {
	my $hql =!$s->{-dofck} && $fql && $s->iofopen('>>' .$fql);
	my $hqi =$s->iofopen('+<' .$fqi); flock($hqi, LOCK_SH);
	my $row ='';
	my $pos =0;
	my $run ='';
	while (do{$pos=tell($hqi); defined($row =readline($hqi))}) {
		if (!$row || ($row =~/^\s*#/) || ($row =~/^[\s\r\n]*$/)) {
			next;
		}
		if (!$run || !$hql) {
			$run =$row;
			$run =$` if $run =~/[\r\n\s]+$/;
			if ($hql) {
				$hql->print($s->strtime(),' $$',$$,"\t",$run,"\n");
				$hql->flush();
				if (!$fqr && $fql && 0) {
					$hql->close(); $hql =undef;
				}
			}
			if ($s->{-dofck}) {
				$hql->close() if $hql; $hql =undef;
				$hqi->close() if $hqi; $hqi =undef;
			}
			my $err =0;
			local $_=$s->{-dofck}
				? (join('',$s->qclad($fqi))
				  .($fql && join('',' ',$s->qclad($fql)) ||'')
				  .($fqr && join('',' >>',$s->qclad($fqr),' 2>>&1') ||''))
				: ($run
				  .($fqr 
				  ? join('', ' >>', $s->qclad($fqr),' 2>>&1')
				  : $fql && 0	# !!! share violation
				  ? join('', ' 2>>', $s->qclad($fql))
				  : ''));
			if (ref($fqp)
			&& !eval{&$fqp(	  $s->{-dofck}
					? ($fqi
					  ,($fql ? $fql : !$fqr ? () : '')
					  ,($fqr ? $fqr : ()))
					: ($run,$fqr)); 1}) {
				$err =$@;
			}
			elsif (!ref($fqp) && ($s->{-dofck} ? $fqp : 1)) {
				print('$$', $$, ' ', ($fqp ? $fqp .' ' : '')
					, $_, ' (' ,$fqi, ")\n")
					if !$s->{-dofck};
				$err =
				system( ( !$fqp
					? ''
					: $fqp =~/\.(?:pl|p)$/ 
					? "$^X $fqp "
					: $fqp =~/\.(?:bat|cmd)$/ 
					? "cmd /c $fqp "
					: "$fqp ")
					.$_);
				$err =$! if $err ==-1;
				$err =$?>>8;
			}

			return(!$err)
				if $s->{-dofck};

			$hql =$s->iofopen('>>' .$fql)
				if !$hql && $fql;
			
			$hql->print($s->strtime(),' $$',$$,"\terror: $err\n")
				if $hql && $err;

			$erc =($erc||0 +1)
				if $err;

			if ($hql) {
				my $po1 =tell($hqi);
				my $buf;
				flock($hqi, LOCK_UN);
				flock($hqi, LOCK_EX);

				seek($hqi,0,0);
				while	(((tell($hqi)||0) <=$pos)
				&&	defined($row =readline($hqi))) {}
				$row =$` if defined($row) && ($row =~/[\r\n\s]+$/);

				if (defined($row)
				&& ((tell($hqi)||0)==$po1)
				&& ($row eq $run)) {
					if ($fqt) {
						my $hqt =$s->iofopen('>' .$fqt .'.tmp');
						seek($hqi,0,0)
						&& defined(read($hqi, $buf, -s $hqi))
						&& $hqt->print($buf);
						$hqt->close();
						rename($fqt .'.tmp', $fqt);
					}
					seek($hqi,$po1,0)
					&& defined(read($hqi, $buf, -s $hqi))
					&& seek($hqi,$pos,0)
					&& ($hqi->autoflush(1)||1)
					&& $hqi->print($buf .(' ' x ($po1-$pos)))
					&& truncate($hqi,tell($hqi) -($po1-$pos))
					|| return($s->error("$! (shift,'$fqi')"));

					$fqt && unlink($fqt)
				}

				flock($hqi, LOCK_UN);
				$hqi->close();
				$hqi =undef;
				last;
			}
		}
	}
	flock($hqi, LOCK_UN |LOCK_NB) if $hqi;
	$hqi->close() if $hqi;
	$hql->close() if $hql;
	last if !$run || !$hql;
 }
 !$erc
}


sub dofck {		# Command queue check / run
 my $s =shift;		# (script||sub{}||undef, comfile,...) -> success
    $s =Sys::Manage::CmdFile->new() if !ref($s);
 local $s->{-dofck} =1;
 $s->dofile(@_)
}