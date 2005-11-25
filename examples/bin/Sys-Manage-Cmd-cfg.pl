#!perl -w
#
# Systems management command volley (Sys::Manage::Cmd)
# Config file.
#

my $s =$_;

# Script associations (see also embedded in source):
# $s->{-assoc}->{'.ftp'}	=sub{['ftp','-n','-s:loginfile','!elem!','<',$_[1]->[0]]};

# Target collections:
$s->{-target}->{'all'}	=[1,2,3,4,5,6];
$s->{-target}->{'some'}	=[1,2,3];

# Target branches:
$s->{-branch}->{1}	=[1,2];
$s->{-branch}->{2}	=[3,4];
$s->{-branch}->{3}	=[5,6];

# Defaults:
$s->set(-k=>'cmd', -o=>'b', -i=>0, -log=>1, -ping=>0);

# Queues & Services:
$s->set(-reject=>sub{
	if (!$ENV{SMCFP}) {
	}
	elsif ($ENV{SMCFP} =~/\b(?:Admin|Administrator|test)\b/i) {
		$_[0]->set(-k=>$1) 
			if $ENV{SMCFP} =~/(sched|assign)/i
			&& ($_[0]->{-ckind} eq 'cmd');
	}
	elsif ($ENV{SMCFP} =~/\bOperator\b/i) {
		$_[0]->set(-k=>($ENV{SMCFP} =~/(assign)/ ? "oTE-$1" : 'oTE-cmd'));
		return('illegal target') if !$_[0]->istarget('irkcpdc');
		return('illegal script') if !$_[0]->isscript();
	}
	else {
		return("unconsidered queue '$ENV{SMCFP}'")
	}
	''
	});
