#!perl -w
#
# Sample 'rdo' script
#
if (!$ENV{SMELEM}) {
	system('cmd','/c',"$0\\..\\..\\bin\\smcmv.bat"
		,"-k0",'0','rdo',$0)
}
elsif ($ENV{SMDIR}) {
	die "Execute this script on Agent!"
}
else {	
	system('cmd','/c','dir','c:\\');
	1
}