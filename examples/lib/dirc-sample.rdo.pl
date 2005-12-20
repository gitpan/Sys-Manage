#!perl -w
#
# Sample 'rdo' script
#
if (!defined($ENV{SMELEM}) ||($ENV{SMELEM} eq '')) {
	system($^X, "$0\\..\\..\\bin\\smcmv.p", "-k0", '0', $0)
}
elsif ($ENV{SMDIR}) {
	die "Execute this script on Agent!"
}
else {	
	system('cmd','/c','dir','c:\\');
	1
}