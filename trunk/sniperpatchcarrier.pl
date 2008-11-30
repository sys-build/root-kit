#!/usr/bin/perl

# sniper-patch-carrier: tool for patch-set sending
# usage description is partially copied from sendpatchset.
# Copyright 2008, Qinghuang Feng <qhfeng.kernel@gmail.com>.
# Under GPL license

use Email::Send;
use Email::Simple::Creator; # or other Email::

sub usage 
{
	print <<EOT;    
Usage: sniperpatchcarrier controlfile 

    Sample control file:
        # this is a comment
        SMTP: smtp.gmail.com
	USER: your-smtp-account-username 
	PWD: your-smtp-account-password
        From: Joe Blow <jb\@example.com>
        To: Harry Hacker<hhacker\@another.example.com>
        Cc: Lurker One <lurker1\@yet_another.example.com>
        Cc: lurker2\@a_third.example.com
        Bcc: blindrecipient\@secret_dropoff.example.com
        Subject: [PATCH 1/2] Short sweet descriptive phrase
        File: path-of-message-text-for-first-patch
        Subject: [PATCH 2/2] Another short sweet phrase
        File: path-of-message-text-for-second-patch

    Above sends out two email messages, with specified Subject lines,
    and contents from corresponding Files.

    Each "File" line sends a message, using the latest values for
    the other keywords set so far in file.  The To, Cc and Bcc lists
    accumulate.

    First word on each line of control file is a keyword.  It can be
    any mix of upper/lower case, with optional trailing colon.
    The keyword "Subject" can be abbreviated as "Subj".

    Try testing by first sending patch set only to one or more of
    your own email addresses.

    The following documents explain how to submit patches to the
    Linux kernel:

     1) Documentation/SubmittingPatches, a file in the kernel source
	  http://lxr.linux.no/source/Documentation/SubmittingPatches
     2) Documentation/CodingStyle
	  http://lxr.linux.no/source/Documentation/CodingStyle
     3) Andrew Morton's "The Perfect Patch", available at:
          http://www.zip.com.au/~akpm/linux/patches/stuff/tpp.txt
     4) Jeff Garzik's "Linux kernel patch submission format", at:
          http://linux.yyz.us/patch-format.html
     5) Greg Kroah-Hartman's "How to piss off a kernel subsystem maintainer"
	  http://www.kroah.com/log/2005/03/31/
     6) Linus's email on the canonical patch format:
          http://lkml.org/lkml/2005/4/7/183

    Linus describes the canonical patch format:

	That canonical format is:

		Subject: [PATCH 001/123] [<area>:] <explanation>

	together with the first line of the body being a

		From: Original Author <origa@email.com>

	followed by an empty line and then the body of the explanation.

	After the body of the explanation comes the "Signed-off-by:"
	lines, and then a simple "---" line, and below that comes the
	diffstat of the patch and then the patch itself.
EOT

	exit(1);
}

$VERSION = "1.06";

$smtpserver="";
$smtpuser="";
$smtppwd="";

$fromaddr="";
@subjects = ();  #note: don't to use ""!
@patches = (); 
$toaddrs = ""; 
$ccaddrs = ""; 
$bccaddrs = ""; 
$refid = "";

$patch_count = 0;
$patch_content ="";

$control_file = "";

   
sub parse_control
{
	#0. verify the integrity of control file
	if (open(INTEGRITY, $control_file)) {
		my $integrity = 1;
		my %integrity_panic = (
			"smtp" => "smtp:",
			"user" => "user:",
			"pwd" => "pwd:",
			"subj" => "subject:",
			"file" => "file:",
		);
		my $ctrl_file;
		print "\n>checking the integrity of control file...\n\n";
		while (<INTEGRITY>) {
			$ctrl_file .= $_;
		}
	
		unless ($ctrl_file =~ /smtp\s*\:/i) {
			$integrity = 0;
		} else {$integrity_panic{"smtp"} = 0;}

		unless ($ctrl_file =~ /user\s*\:/i) {
			$integrity = 0;
		} else {$integrity_panic{"user"} = 0;}

		unless ($ctrl_file =~ /pwd\s*\:/i) {
			$integrity = 0;
		} else {$integrity_panic{"pwd"} = 0;}
	
		unless ($ctrl_file =~ /subj(?:ect)?\s*\:/i) {
			$integrity = 0;
		} else {$integrity_panic{"subj"} = 0;}

		unless ($ctrl_file =~ /file\s*\:/i) {
			$integrity = 0;
		} else {$integrity_panic{"file"} = 0;}

		if ($integrity == 0) {
			print "ERROR: control file is not integrate. \n";
			print "You must add the following item(s) to it!\n\n";
			my $key;
			my $value;
			while (($key, $value) = each %integrity_panic) {
				#print $key."=>".$value."\n";
				if ($value){
					print $value."\n";
				}				
			}
			exit(1);
		} else {print "ok!\n";}

	close(INTEGRITY);
	#<-open
	} else {
		print "can't open control file!\n";
		exit(1);
	}


	#1. parse control file
	if (open(CTRLFILE, $control_file)) {
		print "\n>reading the control file\n";
		while (<CTRLFILE>) {
			print;
			#FIXME: why the last \s* doesn't work as what I want?
			#so I fix it in the following. see stuff under close(CTRLFILE)
			if (m{smtp\s*\:\s*(.*)\s*}i) {
				$smtpserver = $1;
			} elsif (m{user\s*\:\s*(.*)\s*}i) {
				$smtpuser = $1;
			} elsif (m{pwd\s*\:\s*(.*)\s*}i) {
				$smtppwd = $1;
			} elsif (m{from\s*\:\s*(.*)\s*}i) {
				$fromaddr = $1 ;
			} elsif (m{to\s*\:\s*(.*)\s*}i) {
                                $toaddrs .= $1.", ";
			} elsif (m{\bcc\b\s*\:\s*(.*)\s*}i) {
                                $ccaddrs .= $1.", ";
			} elsif (m{bcc\s*\:\s*(.*)\s*}i) {
                                $bccaddrs .= $1.", ";
			} elsif (m{subj(?:ect)?\s*\:\s*(.*)\s*}i) {
				push @subjects, $1;				
			} elsif (m{file\s*\:\s*(.*)\s*}i) {
				push @patches, $1;
			} 
		}
	
	close(CTRLFILE);
	
	print "\nafter fixed\n";
	#now we fix anything MAY introduce the bug.  Pretty strictly!	
	print "\n>smtp config:\n";
	$smtpserver =~ s/\s+$//;
	print $smtpserver."\n";
	$smtpuser =~ s/\s+$//;
	print $smtpuser."\n";
	$smtppwd =~  s/\s+$//;
	print $smtppwd."\n";
	
	print "\n>mail address:\n";
	#we assume that "," is invalid for a mail-address itself.
	$fromaddr =~ s/(\s*\,\s*)$//;
	print  "from:".$fromaddr."\n";
	$toaddrs =~ s/(\s+\,)/\,/g;     #for user input
	$toaddrs =~ s/(\,\s*)$//;       #for action of srcipt itself
	print    "  to:".$toaddrs."\n";
	$ccaddrs =~ s/\s+\,/\,/g;
	$ccaddrs =~ s/(\,\s*)$//;
	print    "  cc:".$ccaddrs."\n";
	$bccaddrs =~ s/(\s+\,)/\,/g;
	$bccaddrs =~ s/(\,\s*)$//;
	print     " bcc:".$bccaddrs."\n";

	#subjects don't need to fix.
	#defer the fix of patch file name to #2
		
	print "\nall mail address is ok?\nIf NO problem, press \"c\" to continue\n\n";
	chomp (my $answer = <STDIN>); 
	unless ($answer =~ /^c$/) {
		print "aborted by user.\n";
		exit(1);
	}

	#2 check configuration 
	print ">>checking the relation between subject and patch file...\n\n";
	if (scalar(@subjects) == scalar(@patches)) {
		$patch_count = scalar(@subjects);
		my $check_i;
		for ($check_i = 0; $check_i < $patch_count; $check_i++) {
			#the defered fix
			$patches[$check_i] =~ s/\s+$//;
			my $show_i = $check_i + 1;
			print "$show_i:".$subjects[$check_i]."\n";
			print "$show_i:".$patches[$check_i]."\n\n";
		}
		print "All relations are ok?\nIf NO problem, press \"c\" to continure\n";
		chomp (my $answer = <STDIN>);
		unless ($answer =~ /^c$/) {
			print "aborted by user.\n";
			exit(1);
		}
	} else {
		print "<< ERROR! the count of subjects isn't equal to the patches's\n";
		exit(1);
	}
    
	#//<-open 		
	} else {
		print "can't open control file!\n";
		exit(1);
	}


	#3 check the patches format
	my $patch_i = undef;
	$check_patch_global_success = 1;
	print "\n>>checking patch format...\n\n";
	for ($patch_i = 0; $patch_i < $patch_count; $patch_i++) {
		my $show_patch_i = $patch_i + 1;
		print "patch $show_patch_i: ";

		#patch 0 is not the real patch, don't check it.
		if ($subjects[$patch_i] =~ /\[\s*PATCH\s*0+\//i) {
                	print "found [PATCH 0/*], ingore it...\n\n";
                	next;
                }

		if (open(PATCH_CHECK, $patches[$patch_i])) {

			my $success = 1;
			$line = undef;
			while (<PATCH_CHECK>) {
				$line .= $_;
			}
			my $sign_match = undef;
			if ($line =~ m{(\bSigned-off-by:\s+(?:.+?)\s+\<(?:.+?\@.+?)\>\s*\n)}) {
				$sign_match =$1;
				#print $sign_match;
			} else {
				$success = 0;
				print "<< ERROR: no sign or sign format error.\n";
				print "Please obey the following example strictly.\n\n";
				print "Signed-off-by: your-name <your-mail\@gmail.com>\n";
			}
			
			if ($success == 1){	
				unless ($line =~ m{\b$sign_match\-\-\-\s*\n}) {
					$success = 0;	
					print "<< ERROR: no patch separator \"---\"\n";
					print "please add \"---\" in a new line just following the Signed-off-by line\n";
				}
			}

			if ($success == 1) { 
				print "ok\n"; 
			} else {
				print "ERROR\n";
				$check_patch_global_success = 0;
			}

			print "\n";
			close(PATCH_CHECK);
		#<-open
		} else {
			print "<< FATAL error: can't open \"$patches[$patch_i]\" It was mis-typed?\n";
			exit(1);	
		}
	#<-for
	}
	
	#TODO: add a summarisation of bad patch?
	if ($check_patch_global_success == 0) {
		print "Abort, please check your patch format.\n";
		print "The following is a good example:\n\n";
		print <<GOOD_PATCH;
Paramter \@mem has been removed since v2.6.26, now delete its comment.

Signed-off-by: your-name <your-name\@gmail.com>
---
diff --git a/mm/oom_kill.c b/mm/oom_kill.c
index 64e5b4b..460f90e 100644
--- a/mm/oom_kill.c
+++ b/mm/oom_kill.c
...(ignore the diff content)
GOOD_PATCH
		print "\n";
		exit(1);

	#<-if ($check_patch...
	} else {
		print "ok, all patches format are right.\n\n"
	}
	
}

sub create_mailer 	
{
	$mailer = Email::Send->new( {
		mailer => 'SMTP::TLS',
        	mailer_args => [
            		Host => $smtpserver,
            		Port => 587,
            		User => $smtpuser,
            		Password => $smtppwd,
            		#Hello => 'fayland.org',
        	]
    	} );
}

    

sub send_onemail
{
	my ($index) = @_;
	
	my $email = Email::Simple->create(
		header => [
        		From    => $fromaddr,
        		To      => $toaddrs,
			Cc	=> $ccaddrs,
			Bcc	=> $bccaddrs,
        		Subject => $subjects[$index],
		],
		body => $patch_content,
	);
	$email->header_set( 'User-Agent' => "sniper-patch-carrier/$VERSION" );
	
	print " sending email: $subjects[$index] ...\n";
	eval { $mailer->send($email) };
	if (!$@) {
		print ">>success!\n";
	} else { die ">>Error sending email: $@"}
}

sub read_onemail 
{
	my ($index) = @_;
	my $file = $patches[$index];
	print " reading file: $file ...\n";
	$patch_content = undef;
	if (open(FILE, $file)) { 
        	while (<FILE>) {
                	$patch_content .= $_; 
        	}
	close(FILE);
	} else {
        	print "can't open patch!";
		exit(1);
	}

}


sub send_mails 
{	
	print ">>now sending all patches...\n\n";
	print " file count: $patch_count\n";
	my $i ;
	for ($i = 0; $i < $patch_count; $i++) {
		my $show_i = $i + 1;
		print "\n$show_i:\n";
		read_onemail($i);
		send_onemail($i);
	}
	print "\nGood! over\n\n";
}

sub parse_argv 
{
	unless ($control_file = shift @ARGV) {
		usage;
	}
}


parse_argv;
parse_control;
create_mailer;
send_mails; 
