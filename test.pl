#!perl -w
use strict;
use Test;


BEGIN { plan tests => 9 + 1 + ($^O eq 'MSWin32' ? 4 : 0) +6}

if (1) {
   print "\nRequired modules:\n";
   foreach my $m ('Data::Dumper','Fcntl','IO::File','IO::Handle','IO::Socket','IO::Select','IPC::Open3','Safe','Sys::Hostname') {
     print "use $m\t";
     ok(eval("use $m; 'ok'"), 'ok');
   }
}

if (1) {
   print "\nOptional modules:\n";
   foreach my $m ('Net::Ping') {
     print "use $m\t";
     skip(!eval("use $m; 1"), 1);
   }
}

if ($^O eq 'MSWin32') {
   print "\nWin32 modules:\n";
   foreach my $m ('Win32','Win32::EventLog','Win32::TieRegistry','Win32::OLE') {
     print "use $m\t";
     ok(eval("use $m; 'ok'"), 'ok');
     # skip(!eval("use $m; 1"), 1);
   }
}

if (1) {
   print "\nPackaged modules:\n";
   foreach my $m ('Cmd','CmdEscort','CmdFile','Conn','Schedule','Desktops') {
     print "use Sys::Manage::${m}\t";
     ok(eval("use Sys::Manage::${m}; 1"), 1);
   }
}
