#!perl -w
#
# Sample 'rdo' script
#
if (!$ENV{SMELEM}) {
	system('cmd','/c',"$0\\..\\..\\bin\\smcmv.bat"
		,"-k0",'0',$0)
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