#!/usr/bin/perl

#
# checknostatic: Find {init|exit} functions that have no {static|__init|__exit} .
# Copyright 2008, Qinghuang Feng <qhfeng.kernel@gmail.com>.
# Under GPL license

#TODO: to implement the fast mode!
$FAST_MODE = 0; #set to speed up the parsing, the result is still very reliable in fact.

$kernel_dir=shift || die "Need a directory argument (the root dir or a subdir of kernel sources).\n";

@ARGV=split(/\0/, `find "$kernel_dir" -type f -iname "*.c" -print0`);

$all_problem_count = 0;
$all_init_exit_fun = 0;
$bad_static_function = 0;
$bad_init_function = 0;
$bad_exit_function = 0;
$all_bad_function  = 0;
$all_file_count    = 0;		
$start_time = localtime;

$all_fuck = 0;
$analyse_fuck = 0;
#all *fuck* are for debug

%nostatic;
%noinit;
%noexit;

print "scanning...\n\n";

foreach $file (@ARGV) {

	#now, we check one file

	$init_fun = undef;
	$exit_fun = undef;
	$need_analyse = 0;
	
	#to check whether there are init/exit functions
	if (open(FILE, $file)) {
		$all_file_count++;
		$first_fuck = 0;
		#my $count = 0;
		#改进：1.从最后开始匹配 2.两个函数都找到后，停止其他行的匹配
		#Can we only check the end of file?
		#通过fuck debug可知，一个文件只可能有一个init和exit函数。
		#所以可以后面遍历，进行优化。
        	while (<FILE>) {
                	if (m/\bmodule_init\b\s?\((\w+)\)/) {
				$all_init_exit_fun++;
				#last if ($count == 2);
                        	$init_fun = $1; 
				$need_analyse = 1;
				#$count++;
				$first_fuck++;
                	} elsif (m/\bmodule_exit\b\s?\((\w+)\)/) {
				$all_init_exit_fun++;
				#last if ($count == 2);
                        	$exit_fun = $1; 
				$need_analyse = 1;
				#$count++;
				$first_fuck++;
                	} 

		}
        	if ($first_fuck > 2) {
                	print ">>>>>>>>>>>>WARNING<<<<<<<<<<<\n";
			$all_fuck++;
			print "script has bug to parse the following file!\n";
			print "$file\n\n";
        	}


		close(FILE);

	} else {
		print "Cannot open $file: $!.\n";

	}


	$line = " ";
	
	if ($need_analyse == 1) {
		if (open(FILE2, $file)) {

        		while (<FILE2>) {
				$_ =~ s/\n/ /; 
				$line .= $_;
        		}	
		
			#now, we have got a single string $line comprised of all file lines without "\n".
			#we analyse this string with following format
			#[static] int|void [__init|__exit] fun (void)
			#[static] [__init|__exit] int|void fun (void)
			#TODO: to fuck the analyse too!
			#
			#we assume all init function return int.FIXME: warning occurs! 
			$second_fuck = 0;
                	if ($line =~ m{(
					(?:\w{0,10}\s+)?(?:__init\s+)?
					int\s+(?:__init\s+)?\b$init_fun\b
					\s*\(void\)
						)}x) {
                        	#print "\$init_fun: $init_fun\n";
                        	#print "$1\n";
                        	$tmp = $1;
				#print $tmp."\n";
				my $init_bad = 0;
				$analyse_fuck++;
                        	unless ($tmp =~ m/static/) {
					$init_bad = 1;
					$bad_static_function++;
					$all_problem_count++;
                                	print "no static: $tmp\n";
					print "           ".$file."\n\n";
                        	}
				unless ($tmp =~ m/__init/) {
					$init_bad = 1;
					$all_problem_count++;
					print "no __init: $tmp\n";
					print "           ".$file."\n\n";
				} 

				if ($init_bad) {
					$bad_init_function++;
				}
                	} 
		
			#we assume all exit function return void. FIXME: warning occurs!	
			if ($line =~ m{(
					(?:\w{0,10}\s+)?(?:__exit\s+)?
					void\s+(?:__exit\s+)?\b$exit_fun\b
					\s*\(void\)
						)}x) {

                        	#print "\$exit_fun: $exit_fun\n";
                        	#print "$1\n";
				$tmp = $1;      
				#print $tmp."\n";
				my $exit_bad = 0;
				$analyse_fuck++;  
				unless ($tmp =~ m/static/) {
					$exit_bad = 1;
					$bad_static_function++;
					$all_problem_count++;
                                	print "no static: $tmp\n";
					print "           ".$file."\n\n";
                        	}
				unless ($tmp =~ m/__exit/) {
					$exit_bad = 1;
					$all_problem_count++;
					print "no __exit: $tmp\n";
					print "           ".$file."\n\n";
				}

                                if ($exit_bad) {
                                        $bad_exit_function++;
                                }

                	}

        		close(FILE2);

		} else {
			print "Cannot open $file: $!.secondly\n";
		}

	}

#we will check next file in the following iteration.
}		
		
$end_time = localtime;
$all_bad_function = $bad_init_function + $bad_exit_function;

print "------\nOver! All files in $kernel_dir have been checked.\n";
print "start: $start_time\n";  
print "end:   $end_time\n";
print "all parsed files:			$all_file_count\n";
print "all found {init|exit} functions:  	$all_init_exit_fun\n";
print "all parsed {init|exit} functions:	$analyse_fuck\n";

print "all bad {init|exit} functions:   	$all_bad_function\n";
print "all bad init functions:			$bad_init_function\n";
print "all bad exit functions:			$bad_exit_function\n";
print "{static|__init|__exit}-lack:		$all_problem_count\n";	
print "static-lack         	                $bad_static_function\n\n";


if ($all_fuck != 0) {
	print "mis-parsed file count to: 		$all_fuck, script has bug!\n";
}

if ($all_init_exit_fun != $analyse_fuck) {
	print "Count of the should be parsed doesn't equal to the really been parsed's. script has bug!\n";
}


