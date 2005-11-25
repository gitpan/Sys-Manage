#!perl -w
#
# Connection to remote Perl (command line utility)
#
#	makarow, 2005-09-19
#
# Command line syntax:
#
#  perl smrmt -vde node:port user:password command-args
#
#  (all command line arguments are optional, at least first will be 'node')
#
#	-v		verbose mode, from 'v1' to 'v3'
#	-d		debug mode (step-by-step execution)
#	-e		execute rest of command line
#	node		remote computer name or tcp/ip address, 0 - local
#	port		remote computer IO::Socket::INET server port
#	user		user name on remote computer
#	password	password to login
#
#	command-args (using '-e' or '-exec=>1'; '?' - optional):
#
#		rcmd	?-'o-e-		os-command	argumets-list
#		rdo	?-o-e-p		?os-command !	local-script	?args
#		fget	?-'mp		remote-source	local-target
#		fput	?-'mp		local-source	remote-target
#
#		where:
#			-'	quote remote arg with "'"
#			-o-	refuse STDOUT
#			-e-	refuse STDERR
#			-p, -z	pack file(s)
#			-m	move file(s)
use Sys::Manage::Conn;
exit !Sys::Manage::Conn->new([@ARGV],-cfg=>1,-exec=>1,-echo=>2,-error=>'die')->connect();
