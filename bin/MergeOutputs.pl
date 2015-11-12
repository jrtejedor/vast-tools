#!/usr/bin/perl
# Script to merge vast-tools outputs from different sub-samples into samples
# Format of the table with groupings must be:
# Subsample1\tSampleA
# Subsample2\tSampleA
# Subsample3\tSampleB
# ...

use warnings;
use strict;
use Cwd qw(abs_path);
use Getopt::Long;

# INITIALIZE PATH AND FLAGS
my $binPath = abs_path($0);
$0 =~ s/^.*\///;
$binPath =~ s/\/$0$//;

my $dbDir; # directory of VASTDB
my $species; # needed to run expr merge automatically
my $groups; # list with the groupings: sample1_rep1\tgroup_1\n sample1_rep2\tgroup_1\n...
my $folder; # actual folder where the vast-tools outputs are (the to_combine folder!)
my $effective; #effective file for expression. Obtained automatically from VASTDB
my $expr_only; # if you want to do expr only, just write anything.
my $move_to_PARTS; # to move the merged subfiles into the PARTS folder
my $IR_version = 1; # version of IR pipeline

Getopt::Long::Configure("no_auto_abbrev");
GetOptions(               "groups=s" => \$groups,
			  "g=s" => \$groups,
			  "dbDir=s" => \$dbDir,
                          "outDir=s" => \$folder,
                          "o=s" => \$folder,
			  "IR_version=i" => \$IR_version,
			  "sp=s" => \$species,
			  "expr" => \$expr,
                          "exprONLY" => \$expr_only,
                          "help" => \$helpFlag,
			  "move_to_PARTS" => \$move_to_PARTS
    );


our $EXIT_STATUS = 0;

sub errPrint {
    my $errMsg = shift;
    print STDERR "[vast merge error]: $errMsg\n";
    $EXIT_STATUS++; 
}

sub errPrintDie {
    my $errMsg = shift;
    errPrint $errMsg;
    exit $EXIT_STATUS if ($EXIT_STATUS != 0);
}

sub verbPrint {
    my $verbMsg = shift;
    if($verboseFlag) {
	chomp($verbMsg);
	print STDERR "[vast merge]: $verbMsg\n";
    }
}

# Check database directory
unless(defined($dbDir)) {
    $dbDir = "$binPath/../VASTDB";
}
$dbDir = abs_path($dbDir);
$dbDir .= "/$species";
errPrint "The database directory $dbDir does not exist" unless (-e $dbDir or $helpFlag);


if (!defined($ARGV[0]) || $helpFlag){
    die "\nUsage: vast-tools merge -g path/groups_file [-o align_output] [options]

Merges vast-tools outputs from multiple subsamples into grouped samples

OPTIONS: 
        --sp Hsa/Mmu/etc         Three letter code for the database (default Hsa)
        --dbDir db               Database directory (default VASTDB)
        -g, --groups             File with groupings (subsample1\\tsampleA\\nsubsample2\\tsampleA...)
        -o, --outDir             Path to output folder of vast-tools align (default vast_out)
        --IR_version             Version of the Intron Retention pipeline (1 or 2) (default 1)
        --expr                   Merges cRPKM files
        --exprONLY               Merges only cRPKM files
        --move_to_PARTS          Moves the subsample files to PARTS\/ within output folders (default ON)
        --help                   Prints this help message


*** Questions \& Bug Reports: Manuel Irimia (mirimia\@gmail.com)

";
}

# Sanity checks
errPrintDie "Needs to provide a file with the groupings\n" if (!defined $groups);
errPrintDie "IR version must be either 1 or 2." if ($IR_version != 1 && $IR_version != 2);

# If exprONLY, activates expr
$expr=1 if (defined $exprONLY);

verbPrint "Using VASTDB -> $dbDir";
# change directories
errPrintDie "The output directory \"$folder/to_combine\" does not exist" unless (-e "$folder/to_combine");
chdir($folder) or errPrint "Unable to change directories into output" and die;
verbPrint "Setting output directory to $folder";


if (defined $move_to_PARTS){
    system "mkdir $folder/to_combine/PARTS" unless (-e "$folder/to_combine/PARTS");
    system "mkdir $folder/expr_out/PARTS" unless (-e "$folder/expr_out/PARTS") || (!defined $expr);    
}

my %group;
my %list;

### Loading group info
open (GROUPS, $groups) || errPrint "Cannot open $groups file\n";
while (<GROUPS>){
    # cleaning in case they were made in Mac's excel
    $_ =~ s/\r//g;
    $_ =~ s/\"//g;
    chomp($_);
    my @temp = split(/\t/,$_);
    $group{$temp[0]}=$temp[1];
    $list{$temp[1]}=1;
}
close GROUPS;

### variables for merging:
my $N_expr = 0; # number of merged expression files
my $N_IR = 0;
my $N_IRsum = 0;
my $N_MIC = 0;
my $N_EEJ = 0;
my $N_MULTI = 0;
my $N_EXSK = 0;

my %eff;
my %READS_EXPR;
my %TOTAL_READS_EXPR;
my %IR;
my $IR_head;
my $IRsum_head;
my $MIC_head;
my %MIC;
my %dataMIC;
my %EEJ;
my %EEJpositions;
my %EXSK;
my $EXSK_head;
my %dataEXSK_post;
my %dataEXSK_pre;
my $MULTI_head;
my %dataMULTI_pre;
my %dataMULTI_mid;
my %dataMULTI_post;
my %MULTIa;
my %MULTIb;

### For expression
verbPrint "Doing merging for Expression files only ...\n" if (defined $exprONLY);

if (defined $expr){
    $effective = "$dbDir/EXPRESSION/$species"."_mRNA-50.eff";
}

if (-e $effective){
    print "Loading Effective data ...\n";
    open (EFF, $effective) || die "Needs Effective\n";
    while (<EFF>){
	chomp;
	my @temp=split(/\t/,$_);
	$eff{$temp[0]}=$temp[1];
    }
    close EFF;
    
    print "Loading Expression files ...\n";
    my @files=glob("$folder/expr_out/*.cRPKM");
    foreach my $file (@files){
	my ($root)=$file=~/.+\/(.+?)\.cRPKM/;
	next if !$group{$root};
	$N_expr++;
	
	verbPrint "   Processing $file\n";
	open (I, $file) or errPrint "Can't open $file";
	while (<I>){
	    chomp;
	    my @temp=split(/\t/,$_);
	    my $gene=$temp[0];
	    if ($temp[1] eq "NA" || $temp[1] eq "ne"){
		$READS_EXPR{$group{$root}}{$gene}="NA";
	    }
	    else {
		$READS_EXPR{$group{$root}}{$gene}+=$temp[2];
		$TOTAL_READS_EXPR{$group{$root}}+=$temp[2];
	    }
	}
	close I;
	system "mv $file $folder/expr_out/PARTS/" if (defined $move_to_PARTS);
    }
}
else {
    errPrintDie "$effective file does not exist\n";
}

verbPrint "Warning: Not merging Expression data\n" unless (defined $expr); 
   
unless (defined $expr_only){
### For IR (v1 and v2)
    verbPrint "Loading IR files (for version $IR_version)...\n";
    if ($IR_version == 1){
	my @files=glob("$folder/to_combine/*.IR"); 
	foreach my $file (@files){
	    my ($root)=$file=~/.+\/(.+?)\.IR/;
	    next if (!defined $group{$root});
	    $N_IR++; 
	    
	    verbPrint "   Processing $file\n";
	    open (I, $file);
	    $IR_head=<I>;
	    while (<I>){
		chomp;
		my @temp=split(/\t/,$_);
		my $event=$temp[0];
		for my $i (1..$#temp){
		    $IR{$group{$root}}{$event}[$i]+=$temp[$i];
		}
	    }
	    close I;
	    system "mv $f $folder/to_combine/PARTS/" if (defined $move_to_PARTS);
	}
    }
    elsif ($IR_version == 2){
	my @files=glob("$folder/to_combine/*.IR2"); 
	foreach my $file (@files){
	    my ($root)=$file=~/.+\/(.+?)\.IR2/;
	    next if (!defined $group{$root});
	    $N_IR++; 
	    
	    verbPrint "   Processing $file\n";
	    open (I, $file);
	    $IR_head=<I>;
	    while (<I>){
		chomp;
		my @temp=split(/\t/,$_);
		my $event=$temp[0];
		for my $i (1..$#temp){
		    $IR{$group{$root}}{$event}[$i]+=$temp[$i];
		}
	    }
	    close I;
	    system "mv $f $folder/to_combine/PARTS/" if (defined $move_to_PARTS);
	}
	
	verbPrint "Loading IR.summary_v2.txt files ...\n"; # only in v2
	@files=glob("$folder/to_combine/*.IR.summary_v2.txt"); 
	foreach my $file (@files){
	    my ($root)=$file=~/.+\/(.+?)\.IR.summary_v2/;
	    next if (!defined $group{$root});
	    $N_IRsum++;

	    verbPrint "   Processing $file\n";
	    open (I, $file) || errPrintDie "Can't open $file\n";
	    $IRsum_head=<I>;
	    while (<I>){
		chomp($_);
		my @temp=split(/\t/,$_);
		my $event=$temp[0];
		for my $i (1..$#temp){
		    $IRsum{$group{$root}}{$event}[$i]+=$temp[$i]; # in v2 it has 6 elements 1..6 (corr counts and raw counts)
		}
	    }
	    close I;
	    system "mv $file $folder/to_combine/PARTS/" if (defined $move_to_PARTS);
	}
    }
    
### For MIC
    verbPrint "Loading Microexon files ...\n";
    @files=glob("$folder/to_combine/*.micX");
    foreach my $file (@files){
	($root)=$file=~/.+\/(.+?)\.micX/;
	next if (!defined $group{$root});
	$N_MIC++;

	verbPrint "   Processing $file\n";
	open (I, $file) || errPrintDie "Can't open $file\n";
	$MIC_head=<I>;
	while (<I>){
	    chomp($_);
	    my @temp=split(/\t/,$_);
	    my $event=$temp[1];
	    $dataMIC{$event}=join("\t",@temp[0..5]);
	    for my $i (7..$#temo){ # Raw_reads_exc  Raw_reads_inc  Corr_reads_exc  Corr_reads_inc
		$MIC{$group{$root}}{$event}[$i]+=$temp[$i] if $temp[$i] ne "NA";
		$MIC{$group{$root}}{$event}[$i]="NA" if $temp[$i] eq "NA";
	    }
	}
	### Needs to recalculate PSI: from 9 and 10
	close I;
	system "mv $file $folder/to_combine/PARTS/" if (defined $move_to_PARTS);
    }
    
### For EEJ2
    verbPrint "Loading eej2 files ...\n";
    @files=glob("$folder/to_combine/*.eej2");
    foreach my $file (@files){
	my ($root)=$file=~/.+\/(.+?)\.eej2/;
	next if (!defined $group{$root});
	$N_EEJ++;

	verbPrint "   Processing $f\n";
	open (I, $file) or errPrintDie "Can't open $file\n";
	while (<I>){
	    chomp($_);
	    my @temp=split(/\t/,$_);
	    my $event="$temp[0]\t$temp[1]";
	    $EEJ{$group{$root}}{$event}+=$temp[2];
	    
	    my $tot_control=0;
	    my @positions=split(/\,/,$temp[4]);
	    foreach my $pos (@positions){
		my ($p,$n)=$pos=~/(\d+?)\:(\d+)/;
		$EEJpositions{$group{$root}}{$event}[$p]+=$n;
		$tot_control+=$n;
	    }
	    errPrint "Sum of positions ne total provided for $event in $file\n" if $tot_control ne $temp[2];
	}
	close I;
	system "mv $file $folder/to_combine/PARTS/" if (defined $move_to_PARTS);
    }
    
### For EXSK
    verbPrint "Loading EXSK files ...\n";
    @files=glob("$folder/to_combine/*.exskX");
    foreach my $file (@files){
	my ($root)=$file=~/.+\/(.+?)\.exskX/;
	next if (!defined $group{$root});
	$N_EXSK++;
	
	verbPrint "   Processing $file\n";
	open (I, $file) or errPrintDie "Can't open $file\n";
	$EXSK_head=<I>;
	while (<I>){
	    chomp($_);
	    my @temp=split(/\t/,$_);
	    my $event=$temp[3];
	    $dataEXSK_pre{$event}=join("\t",@temp[0..11]);
	    $dataEXSK_post{$event}=join("\t",@temp[22..25]);
	    for my $i (13..$#temp){ # PSI  Reads_exc  Reads_inc1  Reads_inc2  Sum_of_reads  .  Complexity  Corrected_Exc  Corrected_Inc1  Corrected_Inc2
		# only 13-16 and 19-21 really
		$EXSK{$group{$root}}{$event}[$i]+=$temp[$i] if $temp[$i] ne "NA";
		$EXSK{$group{$root}}{$event}[$i]="NA" if $temp[$i] eq "NA";
	    }
	}
	### Needs to recalculate PSI: from 20+21 and 19
	close I;
	system "mv $file $folder/to_combine/PARTS/" if (defined $move_to_PARTS);
    }
    
### For MULTI
    verbPrint "Loading MULTI files ...\n";
    @files=glob("$folder/to_combine/*.MULTI3X");
    foreach my $file (@files){
	my ($root)=$file=~/.+\/(.+?)\.MULTI3X/;
	next if (!defined $group{$root});
	$N_MULTI++;

	verbPrint "   Processing $file\n";
	open (I, $file) or errPrintDie "Can't open $file\n";
	$MULTI_head=<I>;
	while (<I>){
	    chomp($_);
	    my @temp=split(/\t/,$_);
	    my $event=$temp[3];
	    # fixed data for each event (it basically overwrites it each time)
	    $dataMULTI_pre{$event}=join("\t",@temp[0..11]);
	    $dataMULTI_mid{$event}=join("\t",@temp[17..18]);
	    $dataMULTI_post{$event}=join("\t",@temp[23..25]);
	    
	    for my $i (13..16){ # only sum of raw reads 
		$MULTIa{$group{$root}}{$event}[$i]+=$temp[$i] if $temp[$i] ne "NA";
		$MULTIa{$group{$root}}{$event}[$i]="NA" if $temp[$i] eq "NA";
	    }
	    for my $i (19..21){ 
		my ($a,$b,$c)=$temp[$i]=~/(.*?)\=(.*?)\=(.*)/;
		$MULTIb{$group{$root}}{$event}[$i][0]+=$a if $a ne "NA";
		$MULTIb{$group{$root}}{$event}[$i][0]="NA" if $a eq "NA";
		$MULTIb{$group{$root}}{$event}[$i][1]+=$b if $b ne "NA";
		$MULTIb{$group{$root}}{$event}[$i][1]="NA" if $b eq "NA";
		$MULTIb{$group{$root}}{$event}[$i][2]+=$c if $c ne "NA";
		$MULTIb{$group{$root}}{$event}[$i][2]="NA" if $c eq "NA";
	    }
	}
	### Needs to recalculate PSI: from 20a+21a and 19a
	close I;
	system "mv $file $folder/to_combine/PARTS/" if (defined $move_to_PARTS);
    }

### Doing sample number check
    errPrintDie "Different number of samples in each Cassette module\n" if $N_EXSK != $N_MULTI || $N_EXSK != $N_MIC || $N_EXSK != $N_EEJ;
    errPrintDie "Different number of samples in each IR file\n" if $N_IR != $N_IRsum && $IR_version == 2;
    verbPrint "Warning: Number of IR samples doesn't match those of other events\n" if $N_IR != $N_EXSK;
    verbPrint "Warning: Number of EXPR samples ($N_expr) doesn't match those of other events ($N_EXSK)\n" if $N_expr != $N_EXSK && (defined $expr);
} 

### Print output files
verbPrint "Printing group files ...\n";
foreach my $group (sort keys %list){
    verbPrint ">>> $group\n";

    ### EXPR
    if (defined $expr){
	open (EXPR, ">$folder/expr_out/$group.cRPKM") || errPrintDie "Cannot open output file"; 
	foreach my $g (sort keys %{$READS_EXPR{$group}}){
	    my $cRPKM = "";
	    if ($READS_EXPR{$group}{$g} eq "NA" || $eff{$g}==0){
		$cRPKM="NA";
	    }
	    else {
		$cRPKM=sprintf("%.2f",1000000*(1000*$READS_EXPR{$group}{$g}/$eff{$g})/$TOTAL_READS_EXPR{$group}); 
	    }
	    print EXPR "$g\t$cRPKM\t$READS_EXPR{$group}{$g}\n";
	}
	close EXPR;
    }
    unless (defined $exprONLY){
	### IR
	if ($IR_version == 1){
	    open (IR, ">$folder/to_combine/$group.IR") || errPrintDie "Cannot open IR output file";
	    print IR "$IR_head";
	    foreach my $ev (sort keys %{$IR{$group}}){
		print IR "$ev\t$IR{$group}{$ev}[1]\t$IR{$group}{$ev}[2]\t$IR{$group}{$ev}[3]\t$IR{$group}{$ev}[4]\n";
	    }
	    close IR;
	}
	elsif ($IR_version == 2){
	    open (IR, ">$folder/to_combine/$group.IR2") || errPrintDie "Cannot open IR output file";
	    print IR "$IR_head";
	    foreach my $ev (sort keys %{$IR{$group}}){
		print IR "$ev\t$IR{$group}{$ev}[1]\t$IR{$group}{$ev}[2]\t$IR{$group}{$ev}[3]\t$IR{$group}{$ev}[4]\n";
	    }
	    close IR;
	    ### IRsum (only v2)
	    open (IRsum, ">$folder/to_combine/$group.IR.summary_v2.txt") || errPrintDie "Cannot open IRsum output file";
	    print IRsum "$IRsum_head";
	    foreach $ev (sort keys %{$IRsum{$group}}){
		print IRsum "$ev\t$IRsum{$group}{$ev}[1]\t$IRsum{$group}{$ev}[2]\t$IRsum{$group}{$ev}[3]\t$IRsum{$group}{$ev}[4]\t$IRsum{$group}{$ev}[5]\t$IRsum{$group}{$ev}[6]\n";
	    }
	    close IRsum;
	}
	### MIC
	open (MIC, ">$folder/to_combine/$group.micX") || errPrintDie "Cannot open micX output file";
	print MIC "$MIC_head";
	foreach my $ev (sort keys %{$MIC{$group}}){
	    my $PSI_MIC_new = "";
	    if (($MIC{$group}{$ev}[10]+$MIC{$group}{$ev}[9])>0 && $MIC{$group}{$ev}[10] ne "NA" && $MIC{$group}{$ev}[9] ne "NA"){
		$PSI_MIC_new=sprintf("%.2f",100*$MIC{$group}{$ev}[10]/($MIC{$group}{$ev}[10]+$MIC{$group}{$ev}[9]));
	    }
	    else {
		$PSI_MIC_new="NA";
	    }
	    print MIC "$dataMIC{$ev}\t$PSI_MIC_new\t$MIC{$group}{$ev}[7]\t$MIC{$group}{$ev}[8]\t$MIC{$group}{$ev}[9]\t$MIC{$group}{$ev}[10]\n";
	}
	close MIC;
	### EXSK
	open (EXSK, ">$folder/to_combine/$group.exskX") || errPrintDie "Cannot open exskX output file";
	print EXSK "$EXSK_head";
	foreach my $ev (sort keys %{$EXSK{$group}}){
	    my $PSI_EXSK_new = "";
	    if (($EXSK{$group}{$ev}[19]+($EXSK{$group}{$ev}[20]+$EXSK{$group}{$ev}[21])/2)>0){
		$PSI_EXSK_new=sprintf("%.2f",100*($EXSK{$group}{$ev}[20]+$EXSK{$group}{$ev}[21])/(($EXSK{$group}{$ev}[20]+$EXSK{$group}{$ev}[21])+2*$EXSK{$group}{$ev}[19]));
	    }
	    else {
		$PSI_EXSK_new="NA";
	    }
	    print EXSK "$dataEXSK_pre{$ev}\t$PSI_EXSK_new\t$EXSK{$group}{$ev}[13]\t$EXSK{$group}{$ev}[14]".
		"\t$EXSK{$group}{$ev}[15]\t$EXSK{$group}{$ev}[16]\t.\tS\t$EXSK{$group}{$ev}[19]\t$EXSK{$group}{$ev}[20]".
		"\t$EXSK{$group}{$ev}[21]\t$dataEXSK_post{$ev}\n";
	}
	close EXSK;
	### MULTI
	open (MULTI, ">$folder/to_combine/$group.MULTI3X") || errPrintDie "Cannot open MULTI3X output file";
	print MULTI "$MULTI_head";
	foreach my $ev (sort keys %{$MULTIa{$group}}){
	    my $PSI_MULTI_new = "";
	    if ((($MULTIb{$group}{$ev}[20][0]+$MULTIb{$group}{$ev}[21][0])+2*$MULTIb{$group}{$ev}[19][0])>0){
		$PSI_MULTI_new=sprintf("%.2f",100*($MULTIb{$group}{$ev}[20][0]+$MULTIb{$group}{$ev}[21][0])/(($MULTIb{$group}{$ev}[20][0]+$MULTIb{$group}{$ev}[21][0])+2*$MULTIb{$group}{$ev}[19][0]));
	    }
	    else {
		$PSI_MULTI_new="NA";
	    }
	    
	    ### Recalculates complexity
	    my  $from_S=$MULTIb{$group}{$ev}[19][2]+$MULTIb{$group}{$ev}[20][2]+$MULTIb{$group}{$ev}[21][2]; # reads coming only from the reference EEJs (refI1, refI2 and refE)
	    my $from_C=($MULTIb{$group}{$ev}[19][0]+$MULTIb{$group}{$ev}[20][0]+$MULTIb{$group}{$ev}[21][0])-$from_S; # all other reads
	    my $Q;
	    if ($from_C > ($from_C+$from_S)/2) {$Q="C3";}
	    elsif ($from_C > ($from_C+$from_S)/5 && $from_C <= ($from_C+$from_S)/2){$Q="C2";}
	    elsif ($from_C > ($from_C+$from_S)/20 && $from_C <= ($from_C+$from_S)/5){$Q="C1";}
	    else {$Q="S";}
	    
	    print MULTI "$dataMULTI_pre{$ev}\t$PSI_MULTI_new\t$MULTIa{$group}{$ev}[13]\t$MULTIa{$group}{$ev}[14]\t$MULTIa{$group}{$ev}[15]\t$MULTIa{$group}{$ev}[16]\t$dataMULTI_mid{$ev}\t".
		"$MULTIb{$group}{$ev}[19][0]=$MULTIb{$group}{$ev}[19][1]=$MULTIb{$group}{$ev}[19][2]\t".
		"$MULTIb{$group}{$ev}[20][0]=$MULTIb{$group}{$ev}[20][1]=$MULTIb{$group}{$ev}[20][2]\t".
		"$MULTIb{$group}{$ev}[21][0]=$MULTIb{$group}{$ev}[21][1]=$MULTIb{$group}{$ev}[21][2]\t".
		"$Q\t$dataMULTI_post{$ev}\n";
	}
	close MULTI;
	### EEJ2
	open (EEJ2, ">$folder/to_combine/$group.eej2") || errPrintDie "Cannot open eej2 output file";
	foreach my $ev (sort keys %{$EEJ{$group}}){
	    my $pos="";
	    for my $i (0..$#{$EEJpositions{$group}{$ev}}){
		$pos.="$i:$EEJpositions{$group}{$ev}[$i]," if $EEJpos{$group}{$ev}[$i];
	    }
	    chop($pos);
	    print EEJ2 "$ev\t$EEJ{$group}{$ev}\tNA\t$pos\n";
	}
    }
}