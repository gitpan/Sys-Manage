@echo off
@if not exist %0 set 0=%0.bat
perl -w -x -S %0 %*
@exit %ERRORLEVEL%
@goto endofperl
#!perl -w
#line 8
#
# Systems management command volley (Sys::Manage::Cmd) 
# Command line
#
# Command line:
#	perl smcmv.p all dir !elem!
#	perl smcmv.p -oc	all		dir !elem!
#	perl smcmv.p -ob	-tall		dir !elem!
#	perl smcmv.p -rPrevId	-tall		dir !elem!
#	perl smcmv.p -aTest	-tall		dir !elem!
#	perl smcmv.p -l10	-tall		dir !elem!
#	perl smcmv.p -ob -l10	-atest	-tall	dir !elem!
#
# Options:
#	-kNameSpace	- kind (namespace) of command
#	-rCommandId	- redo command id (used also inside '-l'); or switch (for '-a')
#	-aAssignName	- assignment name, to use as command id
#	-lPauseSecs	- loop with pause before each subsequent redo
#	-lg...		- ... for pings usuccessful only
#	-lv, -lw...	- ... console 'v'erbose or 'w'indowed subsequent turns
#	-o(s|c|b)	- order of execution: 
#				's'equental
#				'c'oncurrent
#				'b'ranched (concurrent branches)
#	-tTargetName	- target, may be several '-t', instead of positional argument
#	-xTargetExcl	- exclusion from target list, may be several '-x'
#	-uUser:pswd	- user name and password for target
#	-g		- ping target before command, also use -gPingTimeout
#	-gx		- exclude unsuccessful targets sequentially
#	-i		- ignore exit code
#	-v(0|1|2)	- verbosity level
#	-vc...		- ... cmdfile rows include
#	-vt...		- ... date-time include
#
# Predefined commands:
#	see 'smrmt' script: 'rcmd', 'rdo', 'fput', 'fget', 'mput', 'mget' with options.
#	see 'cmdfile'.
#
use Sys::Manage::Cmd;
$s =Sys::Manage::Cmd->new(-cfg=>1);

# Command line execution
$s->execute([@ARGV]) 
|| exit(eval{my $v=0; 
	$s->{-cerr} && (map {$v +=defined($_) &&(/^\d+$/) ? $_ : 0} @{$s->{-cerr}});
	$v >254 ? 254 : $v} ||255);
__END__
:endofperl