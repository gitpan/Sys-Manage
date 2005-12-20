#!perl -w
#
# Sample 'rdo' script
#
if (!defined($ENV{SMELEM}) ||($ENV{SMELEM} eq '')) {
	system($^X, "$0\\..\\..\\bin\\smcmv.p", "-k0", '0', $0)
}
elsif (!$ENV{SMDIR}) {
	die "Execute this script on Manager!"
}
else {	use Sys::Manage::Conn;
	my $s=Sys::Manage::Conn->connect([@ARGV]
		,-cfg=>1,-echo=>2,-node=>$ENV{SMELEM});
	$s->rcmd('cmd','/c','dir','c:\\');
	1
}