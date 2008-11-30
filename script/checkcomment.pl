#!/usr/bin/perl

# checkcomment: find functions those has comment problem,
# Copyright 2008, Qinghuang Feng <qhfeng.kernel@gmail.com>.
# Under GPL license

# $SHOW_ALL == $SHOW_LESS + $SHOW_MORE + $SHOW_EQU
$SHOW_ALL	= 0; 		#set to debug script itself.
$SHOW_LESS 	= 1;		#set to show info when comment items is less than the factual. 
$SHOW_MORE 	= 1;		#set to show info when comment items is more than the factual.
$SHOW_EQU	= 0;
$SHOW_NUM	= 0;		#TODO:set to show when comment item's name is diffrent from function's.

$count_all 	= 0;
$count_less	= 0;
$count_more	= 0;
$count_equ	= 0;


%sum_less;
%sum_more;

$start_time = localtime;

$kernel_dir=shift || die "Need a directory argument (the root dir or a subdir of kernel sources.\n";

@ARGV=split(/\0/, `find "$kernel_dir" -type f -iname "*.[c]" -print0`);



#脚本本身调试注意事项：
#1.漏检测：该问题只能通过检测到观察点的统计量察觉到。一个观察点即是包含一个注释和对应的一个函数头的数据块
#2.错报：
#a.错误多报：把正常的观察点(EQU)报为错误的观察点(MORE 或 LESS)
#b.错误少报：把错误的观察点(MORE 或 LESS)报为正常的观察点(EQU)
#目前统计，错报多报的概率很低，但还能改进。主要问题是粗匹配有问题，
#导致匹配出的一个数据块包含多个观察点（主要是两个）
#TODO:找出参数个数相同，但名字不一样的。
foreach $file (@ARGV) {

	$line = " ";

	if (open(FILE, $file)) {

		print "checking $file\n";

        	while (<FILE>) {
			$_ =~ s/\n/ /; 
			$line .= $_;
        	}
	
		#or use foreach my $tmp ($line =~ m{....}/xg) {...} 
		#策略：多次匹配。1.粗匹配 2.数据加工 3.细匹配
		#以降低效率换精确性，也方便调试
		
		#TODO:粗匹配哪里使用非贪婪匹配来杜绝出多个注释块的问题而又不导致漏检测？？
		#1./** <-会不会有/ **等情况?
		#2.参数注释块
		#3.函数注释块 <-这里会产生问题.
		#4.*/
		#5函数头
		#
		#FIXME: how to deal with files such as drivers/net/sfc/falcon.c ?
		#solution: we replace . with [^\*\n] in line 2, 4 (see the end of this file)
		#to fix that problem.
		#It will lead to ignoring all the comments which have * before or after @ line? 
		#But it seems that the harm is very slight.
                while ($line =~ m{(
				(?:\/\*\*\s+)
				(?:\*\s*[^\*\n]{0,80}\*{0,2}){0,2}
				(?:\*.{0,10}\@.{0,20}\:.{0,80})+
				(?:\*[^\*\n]{0,80}\*{0,2}){0,10}
				(?:\*\/\s*)
				(?:[\w\*\,\s]*\([\w\*\,\s]+\))
				)}xg) {

                        #下面提取并处理本文件中的一个目标块，包含注释和函数头.
                        #start to deal with one matched block which include comment
                        #and function head.
			my $tmp = " ";
                        $tmp = $1;
			#粗匹配完成

			#粗匹配结果数据的加工，为细匹配作准备
			my $to_cook = " ";
			my $cook_comment = " ";
			my $cook_fun = " ";

			#删除多余空格
			$tmp =~ s/\s+/ /g;
			$to_cook = $tmp;

			

                        #提取函数头
                        if ($to_cook =~ m{(\*\/[\w\*\,\s]*\([\w\*\,\s]+\))} ) {
				$cook_fun = $1;
                        } else {
                        	print "<< no function found, please check coarse match! ++";
                        }

			#提取注释
			if ($to_cook =~ m{(\/\*.+\*\/)} ) {

				$cook_comment = $1;

			} else {
				print "<< no comment found, bug of coarse match! ++\n\n";
			}

			

			#脚本bug检测.注释块含有){或) {则说明粗匹配有bug,注释中含有函数体，通常是函数体过短导致。
			#一般还含有第二个函数的注释及其函数
			if ($cook_comment =~ m{(\)\s?\{)}) {
				print "<< script bug in coarse match! continue, but will lose next watch-point!++\n\n";
				print "\$cook_comment:(before fine match)\n$cook_comment\n\n";
				
				#截取前面一个注释.+?为非贪婪匹配
				if ($cook_comment =~ m{(.+?\*\s?\/)}) {
					$cook_comment = $1;
					print "\$cook_comment:(after fine match)\n$cook_comment\n\n";
				} else {print "<< strange script bug! please check both coarse and fine match of comment!++\n\n"}			
			
				print "\$cook_fun: \n$cook_fun\n\n";	
			}
			#如果注释块 $cook_comment 含有**，只取前面部分。
			#**后面是函数体说明
			#delete the function body comments
			if ($cook_comment =~ m{(\.+\@\.+\*\s\*)}) {
				$cook_comment = $1;
				print "<< function comment found, discard them ++\n\n";
			}



			#FIXME: 如果粗匹配得到的一个数据块包含多个(基本是两个)观察点，也就是说含有两个短小的注释及函数体，
			#或者是含有一个函数的注释和函数体，再加上第二个函数的注释（没有函数体本身），那么第二个函数就
			#会漏测。但是相信在这种情况下漏掉的错误点非常少了。

			#fire
			my @count_comment = " ";
			my @count_fun	 = " ";
			
			#细匹配开始
			#
			#提取注释中的参数
			@count_comment = $cook_comment =~ /\@\w+\:/g;
			$s_c_c = scalar(@count_comment);
			
			#去除不标准注释的返回值说明
			if ($count_comment[-1] =~ /return/i) {
				$s_c_c--;
			}



                        #提取函数中的参数
                        @count_fun = $cook_fun =~ /,/g;
                        $s_c_f = scalar(@count_fun);
                        #add one for ","
                        $s_c_f = $s_c_f + 1;

			#TODO: 换成函数调用形式	
			if ($SHOW_ALL == 1){
                                print "-----------------------------------------------\n";
                                $count_all++;
                                print "$file\n\n";
        			print "\$to_cook\n$to_cook\n\n";
        			print "\$cook_comment: \n$cook_comment\n\n";
        			print "\$cook_fun: \n$cook_fun\n\n";
				print "in $file\n\n";
        			print ">> \@count_comment: ".$s_c_c."\n";
        			print ">> \@count_fun: ".$s_c_f."\n\n";

				if ($s_c_c < $s_c_f) {
					print "<< comment less than fun<<<<<<<<<<<<<<<<<<<<\n\n";
				} elsif ($s_c_c > $s_c_f){
					print "<< comment more than fun<<<<<<<<<<<<<<<<<<<<\n\n";
				}#no alarm for EQU.

			} else {
			
				if (($SHOW_LESS == 1) && ($s_c_c < $s_c_f)) {
					print "-----------------------------------------------\n";
        				$count_less++;
                                	print "$file\n\n";
                                	print "\$to_cook\n$to_cook\n\n";
        				print "\$cook_comment: \n$cook_comment\n\n";
        				print "\$cook_fun: \n$cook_fun\n\n";
					print "in $file\n\n";
        				print ">> \@count_comment: ".$s_c_c."\n";
                                	print ">> \@count_fun: ".$s_c_f."\n\n";
						

					$cook_fun =~ s/\*\///;
                                        $sum_less{$count_less.":".$cook_fun} = "\nin: ".$file;


					print "<< comment less than fun<<<<<<<<<<<<<<<<<<<<\n\n";
				}
			 
				if (($SHOW_MORE == 1) && ($s_c_c > $s_c_f)) {
					print "-----------------------------------------------\n";
        				$count_more++;
                                	print "$file\n\n";
                                	print "\$to_cook\n$to_cook\n\n";
        				print "\$cook_comment: \n$cook_comment\n\n";
        				print "\$cook_fun: \n$cook_fun\n\n";
					print "in $file\n\n";
        				print ">> \@count_comment: ".$s_c_c."\n";
                                	print ">> \@count_fun: ".$s_c_f."\n\n";

					$cook_fun =~ s/\*\///;
					$sum_more{$count_more.":".$cook_fun} = "\nin: ".$file;
					
					print "<< comment more than fun<<<<<<<<<<<<<<<<<<<<\n\n";
				}

                                if (($SHOW_EQU == 1) && ($s_c_c == $s_c_f)) {
                                        print "-----------------------------------------------\n";
                                        $count_equ++;
                                        print "$file\n\n";
                                        print "\$to_cook\n$to_cook\n\n";
                                        print "\$cook_comment: \n$cook_comment\n\n";
                                        print "\$cook_fun: \n$cook_fun\n\n";
                                        print "in $file\n\n";
                                        print ">> \@count_comment: ".$s_c_c."\n";
                                        print ">> \@count_fun: ".$s_c_f."\n\n";
   						 
					#no alarm.
                                }
					
			}	

		
		#接着提取本文件中下一个目标块，包含注释和函数头.
		#to analyse the next matched block in a same file in next iteration. 	
                }
		

        	close(FILE);

	} else {
		print "Cannot open $file: $!.\n";
	}

#we will check the next file in the following iteration.
}

$end_time = localtime;

print "------\nOver! All files in $kernel_dir have been checked.\n";
print "start: $start_time\n";
print "end:   $end_time\n";
print "count: \n";
print "\$count_all:  $count_all\n" if ($SHOW_ALL == 1);
print "\$count_less: $count_less\n" if ($SHOW_LESS == 1);
print "\$count_more: $count_more\n" if ($SHOW_MORE == 1);
print "\$count_equ:  $count_equ\n" if ($SHOW_EQU == 1);
	

if ($count_more) {	
	print "-----------";
	print "\nThe summary for count-more:\n\n";

	for my $key ( sort { $a <=> $b } keys %sum_more) {
  		print $key, $sum_more{$key}, "\n\n";
	}

}


if ($count_less) {
        print "-----------";
        print "\nThe summary for count-less:\n\n";
	
	for my $key ( sort { $a <=> $b } keys %sum_less) {
  		print $key, $sum_less{$key}, "\n\n";
	}
}
# origial solution, but it was unable to check several files as drivers/net/sfc/falcon.c
#                while ($line =~ m{( 
#                                (?:\/\*\*\s+)
#                                (?:\*.{0,80}){0,2}
#                                (?:\*.{0,10}\@.{0,20}\:.{0,80})+
#                                (?:\*.{0,80}){0,10}
#                                (?:\*\/\s*)
#                                (?:[\w\*\,\s]*\([\w\*\,\s]+\))
#                                )}xg) {

