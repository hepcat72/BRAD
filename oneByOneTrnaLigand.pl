#!/usr/bin/perl -w

#Generated using perl_script_template.pl 1.37
#Robert W. Leach
#rwleach@ccr.buffalo.edu
#Center for Computational Research
#Copyright 2008

#These variables (in main) are used by getVersion() and usage()
my $software_version_number = '1.1';
my $created_on_date         = '8/11/2009';

##
## Start Main
##

use strict;
use Getopt::Long;

#Declare & initialize variables.  Provide default values here.
my($outfile_suffix); #Not defined so a user can overwrite the input file
my @input_files         = ();
my $current_output_file = '';
my $help                = 0;
my $version             = 0;
my $overwrite           = 0;
my $noheader            = 0;
my $ga_flag             = 0;
my $pop_size            = 10000;
my $mutation_rate       = .005; #For approx. 1 mutation per 10 sets of 22 vals
my $crossover_rate      = .7;
my $crossover_cutoff    = .7;
my $crossover_amount   = .5;
my $max_seconds         = 3600;   #One hour
my $target_stddev       = 0;     #Must have stddev <= this number to end early
my $effect_range        = 410.4;
my $cross_validate      = 0;
my @cps                 = ('AU','UA','GC','CG','GU','UG');
my @ips                 = ('AG','GA','AC','CA','AA','GG','CC','CU','UC','UU');

#These variables (in main) are used by the following subroutines:
#verbose, error, warning, debug, getCommand, quit, and usage
my $preserve_args = [@ARGV];  #Preserve the agruments for getCommand
my $verbose       = 0;
my $quiet         = 0;
my $DEBUG         = 0;
my $ignore_errors = 0;

my $GetOptHash =
  {'r|effect-range=s'      => \$effect_range,           #OPTIONAL [410.4]
   'v|cross-validate!'     => \$cross_validate,         #OPTIONAL [Off]
   'g|genetic-algorithm!'  => \$ga_flag,                #OPTIONAL [Off]
   'p|population-size=s'   => \$pop_size,               #OPTIONAL [10000]
   'm|mutation-rate=s'     => \$mutation_rate,          #OPTIONAL [0.005]
   'c|crossover-rate=s'    => \$crossover_rate,         #OPTIONAL [0.7]
   'k|crossover-cutoff=s'  => \$crossover_cutoff,       #OPTIONAL [0.7]
   'a|crossover-amount=s'  => \$crossover_amount,       #OPTIONAL [0.5]
   's|max-seconds=s'       => \$max_seconds,            #OPTIONAL [3600] 1 hr
   't|target-stddev=s'     => \$target_stddev,          #OPTIONAL [0]
   'i|input-file=s'        => sub {push(@input_files,   #REQUIRED unless <> is
					sglob($_[1]))}, #         supplied
   '<>'                    => sub {push(@input_files,   #REQUIRED unless -i is
					sglob($_[0]))}, #         supplied
   'o|outfile-suffix=s'    => \$outfile_suffix,         #OPTIONAL [undef]
   'force|overwrite'       => \$overwrite,              #OPTIONAL [Off]
   'ignore'                => \$ignore_errors,          #OPTIONAL [Off]
   'verbose:+'             => \$verbose,                #OPTIONAL [Off]
   'quiet'                 => \$quiet,                  #OPTIONAL [Off]
   'debug:+'               => \$DEBUG,                  #OPTIONAL [Off]
   'help|?'                => \$help,                   #OPTIONAL [Off]
   'version'               => \$version,                #OPTIONAL [Off]
   'noheader'              => \$noheader,               #OPTIONAL [Off]
  };

#If there are no arguments and no files directed or piped in
if(scalar(@ARGV) == 0 && isStandardInputFromTerminal())
  {
    usage();
    quit(0);
  }

#Get the input options & catch any errors in option parsing
unless(GetOptions(%$GetOptHash))
  {
    #Try to guess which arguments GetOptions is complaining about
    my @possibly_bad = grep {!(-e $_)} @input_files;

    error('Getopt::Long::GetOptions reported an error while parsing the ',
	  'command line arguments.  The error should be above.  Please ',
	  'correct the offending argument(s) and try again.');
    usage(1);
    quit(1);
  }

#Print the debug mode (it checks the value of the DEBUG global variable)
debug('Debug mode on.') if($DEBUG > 1);

#If the user has asked for help, call the help subroutine
if($help)
  {
    help();
    quit(0);
  }

#If the user has asked for the software version, print it
if($version)
  {
    print(getVersion($verbose),"\n");
    quit(0);
  }

#Check validity of verbosity options
if($quiet && ($verbose || $DEBUG))
  {
    $quiet = 0;
    error('You cannot supply the quiet and (verbose or debug) flags ',
	  'together.');
    quit(2);
  }

#Put standard input into the input_files array if standard input has been redirected in
if(!isStandardInputFromTerminal())
  {
    push(@input_files,'-');

    #Warn the user about the naming of the outfile when using STDIN
    if(defined($outfile_suffix))
      {warning('Input on STDIN detected along with an outfile suffix.  Your ',
	       'output file will be named STDIN',$outfile_suffix)}
    #Warn users when they turn on verbose and output is to the terminal
    #(implied by no outfile suffix checked above) that verbose messages may be
    #uncleanly overwritten
    elsif($verbose && isStandardOutputToTerminal())
      {warning('You have enabled --verbose, but appear to possibly be ',
	       'outputting to the terminal.  Note that verbose messages can ',
	       'interfere with formatting of terminal output making it ',
	       'difficult to read.  You may want to either turn verbose off, ',
	       'redirect output to a file, or supply an outfile suffix (-o).')}
  }

#Make sure there is input
if(scalar(@input_files) == 0)
  {
    error('No input files detected.');
    usage(1);
    quit(3);
  }

#Check to make sure previously generated output files won't be over-written
#Note, this does not account for output redirected on the command line
if(!$overwrite && defined($outfile_suffix))
  {
    my $existing_outfiles = [];
    foreach my $output_file (map {($_ eq '-' ? 'STDIN' : $_) . $outfile_suffix}
			     @input_files)
      {push(@$existing_outfiles,$output_file) if(-e $output_file)}

    if(scalar(@$existing_outfiles))
      {
	error("The output files: [@$existing_outfiles] already exist.  ",
	      'Use --overwrite to force an overwrite of existing files.  ',
	      "E.g.:\n",getCommand(1),' --overwrite');
	exit(4);
      }
  }

if($effect_range !~ /^(\d+\.?\d*|\d*\.\d+)$/ || $effect_range == 0)
  {
    error("Invalid effect range entered: [$effect_range].");
    usage(1);
    quit(-1);
  }

if($pop_size < 2 || $pop_size !~ /^\d+$/)
  {
    error("Invalid population size.  The population size (-p) must be an ",
	  "integer value greater than 1.");
    usage(1);
    quit(-2);
  }

if($mutation_rate < 0 || $mutation_rate >= 1 || $mutation_rate !~ /^0*\.\d+$/)
  {
    error("Invalid mutation rate.  The mutation rate (-m) must be a decimal ",
	  "value between 0 and 1, inclusive/exclusive respectively.");
    usage(1);
    quit(-3);
  }

if($crossover_rate < 0 || $crossover_rate >= 1 ||
   $crossover_rate !~ /^(\d*\.\d+|\d+\.\d*)$/)
  {
    error("Invalid crossover rate.  The crossover rate (-c) must be a ",
	  "decimal value between 0 and 1, inclusive/exclusive respectively.");
    usage(1);
    quit(-4);
  }

if($crossover_cutoff < 0 || $crossover_cutoff >= 1 ||
   $crossover_cutoff !~ /^(\d*\.\d+|\d+\.\d*)$/)
  {
    error("Invalid crossover cutoff.  The crossover cutoff (-k) must be a ",
	  "decimal value between 0 and 1, inclusive/exclusive respectively.");
    usage(1);
    quit(-5);
  }

if($crossover_amount <= 0 || $crossover_amount > 1 ||
   $crossover_amount !~ /^(\d*\.\d+|\d+\.\d*)$/)
  {
    error("Invalid crossover amount.  The crossover amount (-a) must be a ",
	  "decimal value between 0 and 1, exclusive/inclusive respectively.");
    usage(1);
    quit(-5);
  }

if($max_seconds !~ /^\d+$/)
  {
    error("Invalid max seconds.  The max seconds (-s) must be a positive ",
	  "integer value.");
    usage(1);
    quit(-6);
  }

if($target_stddev < 0 || $target_stddev !~ /^(\d*\.?\d+|\d+\.\d*)$/)
  {
    error("Invalid target standard deviation.  The target standard ",
	  "deviation (-t) must be a decimal value greater than or equal to ",
	  "0.");
    usage(1);
    quit(-7);
  }


verbose('Run conditions: ',getCommand(1));




#If output is going to STDOUT instead of output files with different extensions
#or if STDOUT was redirected, output run info once
verbose('[STDOUT] Opened for all output.') if(!defined($outfile_suffix));

#Store info. about the run as a comment at the top of the output file if
#STDOUT has been redirected to a file
if(!isStandardOutputToTerminal() && !$noheader)
  {print('#',getVersion(),"\n",
	 '#',scalar(localtime($^T)),"\n",
	 '#',getCommand(1),"\n");}

#For each input file
foreach my $input_file (@input_files)
  {
    #If an output file name suffix has been defined
    if(defined($outfile_suffix))
      {
	##
	## Open and select the next output file
	##

	#Set the current output file name
	$current_output_file = ($input_file eq '-' ? 'STDIN' : $input_file)
	  . $outfile_suffix;

	#Open the output file
	if(!open(OUTPUT,">$current_output_file"))
	  {
	    #Report an error and iterate if there was an error
	    error("Unable to open output file: [$current_output_file].\n$!");
	    next;
	  }
	else
	  {verbose("[$current_output_file] Opened output file.")}

	#Select the output file handle
	select(OUTPUT);

	#Store info. about the run as a comment at the top of the output file
	print('#',getVersion(),"\n",
	      '#',scalar(localtime($^T)),"\n",
	      '#',getCommand(1),"\n") unless($noheader);
      }

    #Open the input file
    if(!open(INPUT,$input_file))
      {
	#Report an error and iterate if there was an error
	error("Unable to open input file: [$input_file].\n$!");
	next;
      }
    else
      {verbose('[',($input_file eq '-' ? 'STDIN' : $input_file),'] ',
	       'Opened input file.')}

    my $line_num     = 0;
    my $verbose_freq = 100;
    my $cp1_hash = {};
    my $ip_hash = {};
    my $cp2_hash = {};
    my @known_kds = ();
    my $motif_check = {};
    my $best_solution = [];

    #For each line in the current input file
    while(getLine(*INPUT))
      {
	$line_num++;
	verboseOverMe('[',($input_file eq '-' ? 'STDIN' : $input_file),'] ',
		      "Reading line: [$line_num].") unless($line_num %
							   $verbose_freq);

	debug("Reading line $line_num");

	next if(/^\s*#/ || /^\s*$/);
	chomp;

	my($pairs,$kd,$cp1,$ip,$cp2,@junk);
	($pairs,$kd,@junk) = split(/ *\t */,$_);
	if(scalar(@junk))
	  {($cp1,$ip,$cp2,$kd,@junk) = ($pairs,$kd,@junk)}
	else
	  {($cp1,$ip,$cp2,@junk) = grep {/[A-Z]/} split(/[^A-Z]+/,uc($pairs))}
	if(scalar(@junk))
	  {warning("Unrecognized content in your input file ($input_file): ",
		   "[@junk].")}

	if(length($cp1) == 6 && (!defined($ip) || $ip eq '' ||
				    !defined($cp2) || $cp2 eq ''))
	  {
	    $ip = $cp1;
	    $ip =~ s/^..(..)..$/$1/;
	    $cp2 = $cp1;
	    $cp2 =~ s/^....(..)$/$1/;
	    $cp1 =~ s/^(..)....$/$1/;
	  }
	elsif($cp1 !~ /^..$/ || $ip !~ /^..$/ || $cp2 !~ /^..$/)
	  {
	    error("Unable to parse line: [$_].");
	    next;
	  }

	my $pair_errors = '';
	if(scalar(grep {$_ eq $cp1} @cps) != 1)
	  {$pair_errors .= "Bad closing-end base pair: [$cp1].  "}
	if(scalar(grep {$_ eq $cp2} @cps) != 1)
	  {$pair_errors .= "Bad closing-end base pair: [$cp2].  "}
	if(scalar(grep {$_ eq $ip} @ips) != 1)
	  {$pair_errors .= "Bad loop pair: [$ip].  "}
	if($pair_errors ne '')
	  {
	    error($pair_errors,"Skipping: [$cp1,$ip,$cp2].");
	    next;
	  }

	if(exists($motif_check->{"$cp1,$ip,$cp2"}))
	  {
	    error("This motif was found multiple times: [$cp1,$ip,$cp2].  ",
		  "Keeping the first one and ignorine duplicates.");
	    next;
	  }
	else
	  {$motif_check->{"$cp1,$ip,$cp2"} = $kd}

	debug("Reading in loop: [$cp1,$ip,$cp2,$kd].");

	$cp1_hash->{$cp1}++;
	$ip_hash->{$ip}++;
	$cp2_hash->{$cp2}++;
	push(@known_kds,[$cp1,$ip,$cp2,$kd]);
      }

    close(INPUT);

    verbose('[',($input_file eq '-' ? 'STDIN' : $input_file),'] ',
	    'Input file done.  Time taken: [',scalar(markTime()),' Seconds].');

    if($cross_validate && scalar(@known_kds) > 1)
      {
	my $cross_count = 0;
	foreach my $motif_array (@known_kds)
	  {
	    $cross_count++;

	    verboseOverMe("Working on solution $cross_count of ",
			  scalar(@known_kds),'.');

	    debug("Calling getSolutionExhaustively with these known Kd ",
		  "arrays: [",grep {$_ ne $motif_array} @known_kds,
		  "].  There are ",scalar(@known_kds),
		  " known Kd arrays total.");

	    my $solution = {};
	    if($ga_flag)
	      {$solution =
		 getSolutionUsingGA([grep {$cp1_hash->{$motif_array->[0]} > 1}
				     keys(%$cp1_hash)],
				    [grep {$ip_hash->{$motif_array->[1]} > 1}
				     keys(%$ip_hash)],
				    [grep {$cp2_hash->{$motif_array->[2]} > 1}
				     keys(%$cp2_hash)],
				    [grep {$_ ne $motif_array}
				     @known_kds])}
	    else
	      {$solution =
		 getSolutionExhaustively([grep {$cp1_hash->{$motif_array->[0]}
						  > 1} keys(%$cp1_hash)],
					 [grep {$ip_hash->{$motif_array->[1]}
						  > 1} keys(%$ip_hash)],
					 [grep {$cp2_hash->{$motif_array->[2]}
						  > 1} keys(%$cp2_hash)],
					 [grep {$_ ne $motif_array}
					  @known_kds])}
#	    reportSolution($solution);

	    my($ccp1,$cip,$ccp2,$target_kd);
	    ($ccp1,$cip,$ccp2,$target_kd) = @$motif_array;
	    my $errsum = 0;

	    foreach my $other_motif (grep {$_ ne $motif_array} @known_kds)
	      {
		my($kcp1,$kip,$kcp2,$known_kd);
		($kcp1,$kip,$kcp2,$known_kd) = @$other_motif;
		$errsum += ($target_kd -
			    calculateKd($solution,
					[$ccp1,$cip,$ccp2],
					[$kcp1,$kip,$kcp2],
					$known_kd))**2;
	      }

	    my $stddev = sqrt($errsum / (scalar(@known_kds) - 1));

	    print("Best Solution $cross_count:\n");
	    reportSolution($solution);
	    print("Cross Validation Result: ",
		  ($solution->{STDDEV} >= $stddev ? 'Within' : 'Outside'),
		  " predicted standard error: Predicted standard error: ",
		  "$solution->{STDDEV}.  Withheld [",
		  join(',',($ccp1,$cip,$ccp2)),
		  "] with a known Kd of $target_kd and resulted in an ",
		  "average calculated Kd that has a standard deviation of ",
		  "[$stddev].\n");
	  }
      }
    else
      {	
	if($cross_validate && scalar(@known_kds) < 2)
	  {error("Not enough data to cross-validate!  ",
		 "Computing one solution.")}

	my $solution = {};
	if($ga_flag)
	  {$solution =
	     getSolutionUsingGA([keys(%$cp1_hash)],
				[keys(%$ip_hash)],
				[keys(%$cp2_hash)],
				[@known_kds])}
	else
	  {$solution =
	     getSolutionExhaustively([keys(%$cp1_hash)],
				     [keys(%$ip_hash)],
				     [keys(%$cp2_hash)],
				     [@known_kds])}
	reportSolution($solution);
      }

    #If an output file name suffix is set
    if(defined($outfile_suffix))
      {
	#Select standard out
	select(STDOUT);
	#Close the output file handle
	close(OUTPUT);

	verbose("[$current_output_file] Output file done.");
      }
  }




verbose("[STDOUT] Output done.") if(!defined($outfile_suffix));

#Report the number of errors, warnings, and debugs on STDERR
if(!$quiet && ($verbose                     ||
	       $DEBUG                       ||
	       defined($main::error_number) ||
	       defined($main::warning_number)))
  {
    print STDERR ("\n",'Done.  EXIT STATUS: [',
		  'ERRORS: ',
		  ($main::error_number ? $main::error_number : 0),' ',
		  'WARNINGS: ',
		  ($main::warning_number ? $main::warning_number : 0),
		  ($DEBUG ?
		   ' DEBUGS: ' .
		   ($main::debug_number ? $main::debug_number : 0) : ''),' ',
		  'TIME: ',scalar(markTime(0)),"s]\n");

    if($main::error_number || $main::warning_number)
      {print STDERR ("Scroll up to inspect errors and warnings.\n")}
  }

##
## End Main
##












sub reportSolution
  {
    my $solution = $_[0];#{VALUES => [{AT...},{AA...},{{AT...}}],STDDEV => ...}
    #global: @cps
    #global: @ips
    #global: $effect_range

    print("Effect Range: $effect_range\n",
	  "Solution Standard Deviation: $solution->{STDDEV}\n",
	  "\tPosition 1:\n",
	  join("\n",
	       map {"\t\t$_\t" .
		      (exists($solution->{VALUES}->[0]->{$_}) ?
		       $solution->{VALUES}->[0]->{$_} : '')} @cps),"\n",
	  "\tPosition 2:\n",
	  join("\n",
	       map {"\t\t$_\t" .
		      (exists($solution->{VALUES}->[1]->{$_}) ?
		       $solution->{VALUES}->[1]->{$_} : '')} @ips),"\n",
	  "\tPosition 3:\n",
	  join("\n",
	       map {"\t\t$_\t" .
		      (exists($solution->{VALUES}->[2]->{$_}) ?
		       $solution->{VALUES}->[2]->{$_} : '')} @cps),"\n");
  }

sub calculateKd
  {
    my $solution        = $_[0]; #{VALUES => [{AT...},{AA...},{{AT...}}]}
    my $calculate_motif = $_[1];
    my $known_motif     = $_[2];
    my $known_kd        = $_[3];
    #global: $effect_range

    my $kd = $known_kd;
    debug("Position 1: $calculate_motif->[0]_c vs. $known_motif->[0]_k");
    $kd += $effect_range * ($solution->{VALUES}->[0]->{$calculate_motif->[0]} -
			    $solution->{VALUES}->[0]->{$known_motif->[0]});
    debug("Position 2: $calculate_motif->[1]_c vs. $known_motif->[1]_k");
    $kd += $effect_range * ($solution->{VALUES}->[1]->{$calculate_motif->[1]} -
			    $solution->{VALUES}->[1]->{$known_motif->[1]});
    debug("Position 3: $calculate_motif->[2]_c vs. $known_motif->[2]_k");
    $kd += $effect_range * ($solution->{VALUES}->[2]->{$calculate_motif->[2]} -
			    $solution->{VALUES}->[2]->{$known_motif->[2]});

    return($kd);
  }

sub internalCalculateKd
  {
    my $solution         = $_[0]; #{VALUES => [{AT...},{AA...},{{AT...}}]}
    my $int_sol_pos_hash = $_[1];
    my $calculate_motif  = $_[2];
    my $known_motif      = $_[3];
    #global: $effect_range

    my $kd = $known_motif->[3];
#    debug("Position 1: $calculate_motif->[0]_c vs. $known_motif->[0]_k");
    $kd += $effect_range *
      ($solution->[$int_sol_pos_hash->{1}->{$calculate_motif->[0]}] * .1 -
       $solution->[$int_sol_pos_hash->{1}->{$known_motif->[0]}] * .1);
#    debug("Position 2: $calculate_motif->[1]_c vs. $known_motif->[1]_k");
    $kd += $effect_range *
      ($solution->[$int_sol_pos_hash->{2}->{$calculate_motif->[1]}] * .1 -
       $solution->[$int_sol_pos_hash->{2}->{$known_motif->[1]}] * .1);
#    debug("Position 3: $calculate_motif->[2]_c vs. $known_motif->[2]_k");
    $kd += $effect_range *
      ($solution->[$int_sol_pos_hash->{3}->{$calculate_motif->[2]}] * .1 -
       $solution->[$int_sol_pos_hash->{3}->{$known_motif->[2]}] * .1);

    return($kd);
  }

sub getSolutionExhaustively
  {
    my $cp1s      = [sort {$a cmp $b} @{$_[0]}];
    my $ips       = [sort {$a cmp $b} @{$_[1]}];
    my $cp2s      = [sort {$a cmp $b} @{$_[2]}];
    my $known_kds = $_[3]; #An array of arrays containing [cp1,ip,cp2,kd]

    if(scalar(@$known_kds) < 2)
      {
	error("Not enough data to calculate a solution.");
	return({});
      }

    debug("Called with [@$cp1s], [@$ips], [@$cp2s], and [@$known_kds].");

    #This is not the solution nthat will be returned, but a simpler
    #representation needed for GetNextIndepCombo.  We are going to assume the
    #pairs are ordered by position and then alphabetical
    my $internal_solution = [];
    my $best_internal_solution = [];
    my @order = (@$cp1s,@$ips,@$cp2s);

    markTime();
    my $cnt = 0;
    my $num_poss = 11**scalar(@order);
    my($ccp1,$cip,$ccp2,$target_kd);
    my($kcp1,$kip,$kcp2,$known_kd);
    my $real_solution    = {};
    my $best_solution    = {};
    my $array_sizes      = [map {11} @order];
    my $stddev           = 0;
    my($best_stddev,$errsum,$num_calcs);

    #Set up a hash that keeps track of the positions of the important values
    #based on pair position and nucleotide values so that we don't have to
    #recreate a hash to look it up every time.  Note, the conversion from an
    #integer of 0-10 to 0 to 1 will happen later
    my $int_sol_pos_hash = {};
    foreach my $int_sol_pos (0..$#order)
      {
	if($int_sol_pos < scalar(@$cp1s))
	  {$int_sol_pos_hash->{1}->{$order[$int_sol_pos]} = $int_sol_pos}
	elsif($int_sol_pos < (scalar(@$cp1s) + scalar(@$ips)))
	  {$int_sol_pos_hash->{2}->{$order[$int_sol_pos]} = $int_sol_pos}
	elsif($int_sol_pos < (scalar(@$cp1s) + scalar(@$ips) + scalar(@$cp2s)))
	  {$int_sol_pos_hash->{3}->{$order[$int_sol_pos]} = $int_sol_pos}
	else
	  {error("We've gone out of the bounds of the order array.  This ",
		 "should not have happened.  Please consult the developer ",
		 "with this exact message.")}
      }

    while(GetNextIndepCombo($internal_solution,$array_sizes))
      {
	$cnt++;

#	my $i = 0;

#	if($DEBUG) #Doing it this way saves computation time...
#	  {
#	    my $i = 0;
#	    debug("Position 1: [",
#		  join(',',map {$order[$i++],$_ * .1}
#		       @{$internal_solution}[0..(scalar(@$cp1s) - 1)]),"].");
#	    debug("Position 2: [",
#		  join(',',map {$order[$i++],$_ * .1}
#		       @{$internal_solution}[scalar(@$cp1s)..
#					     (scalar(@$cp1s) +
#					      scalar(@$ips) - 1)]),"].");
#	    debug("Position 3: [",
#		  join(',',map {$order[$i++],$_ * .1}
#		       @{$internal_solution}[(scalar(@$cp1s) +
#					      scalar(@$ips))..
#					     $#{$internal_solution}]),"].");
#
#	    $i = 0;
#	  }

	#$solution->{VALUES} = [{AT => ...},{AA => ...},{AT => ...}]
#	$real_solution->{VALUES} =
#	  [{map {$order[$i++] => $_ * .1}
#	    @{$internal_solution}[0..(scalar(@$cp1s) - 1)]},
#	   {map {$order[$i++] => $_ * .1}
#	    @{$internal_solution}[scalar(@$cp1s)..(scalar(@$cp1s) +
#						   scalar(@$ips) - 1)]},
#	   {map {$order[$i++] => $_ * .1}
#	    @{$internal_solution}[(scalar(@$cp1s) + scalar(@$ips))..
#				  $#{$internal_solution}]}];
#	reportSolution($real_solution) if($DEBUG);
	$errsum = 0;
	$num_calcs = 0;

	foreach my $calculate_kd_array (@$known_kds)
	  {
#	    ($ccp1,$cip,$ccp2,$target_kd) = @$calculate_kd_array;

#	    debug("Calculating [$ccp1,$cip,$ccp2].");

	    foreach my $known_kd_array (@$known_kds)
	      {
		next if($known_kd_array eq $calculate_kd_array);
		$num_calcs++;
#		($kcp1,$kip,$kcp2,$known_kd) = @$known_kd_array;
#		$errsum += abs($target_kd -
#			       calculateKd($real_solution,
#					   [$ccp1,$cip,$ccp2],
#					   [$kcp1,$kip,$kcp2],
#					   $known_kd));
		$errsum += ($calculate_kd_array->[3] -
			    internalCalculateKd($internal_solution,
						$int_sol_pos_hash,
						$calculate_kd_array,
						$known_kd_array))**2;
	      }
	  }

#	$real_solution->{STDDEV} = $errsum / $num_calcs;
	$stddev = sqrt($errsum / $num_calcs);

	#Copy the solution to the best solution if it has a smaller STDDEV
#	if(!exists($best_solution->{STDDEV}) ||
#	   $real_solution->{STDDEV} < $best_solution->{STDDEV})
#	  {$best_solution = copySolution($real_solution)}
	if(!defined($best_stddev) || $stddev < $best_stddev)
	  {
	    $best_stddev            = $stddev;
	    $best_internal_solution = [@$internal_solution];
	    my $i = 0;
	    verbose("Best Solution [with STD DEV $stddev]: ",
		    join(',',
			 map {$order[$i++] . ":" . ($_ * .1)}
			 @{$best_internal_solution}));
	  }

	unless($cnt % 10000)
	  {
	    my $t = markTime(-1);
	    my $eta = ($t / $cnt) * ($num_poss - $cnt) / 3600;
	    $t /= 3600;
	    $eta =~ s/(\.\d{2})\d+/$1/;
	    $t   =~ s/(\.\d{2})\d+/$1/;
	    verboseOverMe("ETA for this solution: $eta hours.  $cnt of ",
			  "$num_poss done in $t hours.");
	  }
      }

    my $i = 0;
    #$solution->{VALUES} = [{AT => ...},{AA => ...},{AT => ...}]
    $real_solution->{VALUES} =
      [{map {$order[$i++] => $_ * .1}
	@{$best_internal_solution}[0..(scalar(@$cp1s) - 1)]},
       {map {$order[$i++] => $_ * .1}
	@{$best_internal_solution}[scalar(@$cp1s)..(scalar(@$cp1s) +
						    scalar(@$ips) - 1)]},
       {map {$order[$i++] => $_ * .1}
	@{$best_internal_solution}[(scalar(@$cp1s) + scalar(@$ips))..
				   $#{$best_internal_solution}]}];
    $real_solution->{STDDEV} = $best_stddev;

    return($best_solution);
  }

sub getSolutionUsingGA
  {
    my $cp1s      = [sort {$a cmp $b} @{$_[0]}];
    my $ips       = [sort {$a cmp $b} @{$_[1]}];
    my $cp2s      = [sort {$a cmp $b} @{$_[2]}];
    my $known_kds = $_[3]; #An array of arrays containing [cp1,ip,cp2,kd]
    #globals: $pop_size, $mutation_rate, $crossover_rate, $crossover_amount,
    #         $crossover_cutoff, $max_seconds, $target_stddev
    my $target_fitness = ($target_stddev == 0 ?
			  0 : exp(1000*(1/$target_stddev)));

    if(scalar(@$known_kds) < 2)
      {
	error("Not enough data to calculate a solution.");
	return({});
      }

    debug("Called with [@$cp1s], [@$ips], [@$cp2s], and [@$known_kds].");

    my @order = (@$cp1s,@$ips,@$cp2s);

    #Set up a hash that keeps track of the positions of the important values
    #based on pair position and nucleotide values so that we don't have to
    #recreate a hash to look it up every time.  Note, the conversion from an
    #integer of 0-10 to 0 to 1 will happen later
    my $int_sol_pos_hash = {};
    foreach my $int_sol_pos (0..$#order)
      {
	if($int_sol_pos < scalar(@$cp1s))
	  {$int_sol_pos_hash->{1}->{$order[$int_sol_pos]} = $int_sol_pos}
	elsif($int_sol_pos < (scalar(@$cp1s) + scalar(@$ips)))
	  {$int_sol_pos_hash->{2}->{$order[$int_sol_pos]} = $int_sol_pos}
	elsif($int_sol_pos < (scalar(@$cp1s) + scalar(@$ips) + scalar(@$cp2s)))
	  {$int_sol_pos_hash->{3}->{$order[$int_sol_pos]} = $int_sol_pos}
	else
	  {error("We've gone out of the bounds of the order array.  This ",
		 "should not have happened.  Please consult the developer ",
		 "with this exact message.")}
      }

    ##
    ##PRELIMINARY DESIGN
    ##
    #Create initial population randomly
    #Mark the time
    #While running time < max_seconds and best stddev > target stddev
    #  For each solution in the population
    #    Assign solution fitness exp(1000*(1/stddev))
    #    If fitness is better than the best or the best is not yet assigned
    #      Save the best solution
    #  Until the next generation is equal to the population size
    #    Select 2 members of the population based on fitness score
    #    Crossover the two selected
    #    Point-Mutate the two selected
    #    Put the first mutated individual in the next generation
    #    If the next generation size is less than the population size
    #      Put the second mutated individual in the next generation


    #Create initial population randomly
    my $next_generation = [];
    foreach(1..$pop_size)
      {push(@$next_generation,getRandomInternalSolution(scalar(@order)))}
    #Mark the time
    markTime();
    #While running time < max_seconds and best fitness < target fitness
    my($best_fitness,@fitnesses,$best_internal_solution,$rand1,$rand2,$sum,$j,
       $mom,$dad,@new_solutions,$population,$total_fitness);
    my $generation_num = 0;
    while(($max_seconds == 0 || markTime(-1) < $max_seconds) &&
	  (!defined($best_fitness) || $target_fitness == 0 ||
	   $best_fitness < $target_fitness))
      {
	verboseOverMe("Generation ",++$generation_num,".  Assessing fitness.");

	$population = [@$next_generation];
	$next_generation = [];
	@fitnesses = ();
	$total_fitness = 0;
	#For each solution in the population
	foreach my $internal_solution (@$population)
	  {
	    #Assign solution fitness exp(1000*(1/stddev))
	    push(@fitnesses,exp(1000*(1/getStandardDeviation($internal_solution,
						       $int_sol_pos_hash,
						       $known_kds))));
	    $total_fitness += $fitnesses[-1];
	    #If fitness is better than the best or the best is not yet assigned
	    if(!defined($best_fitness) || $fitnesses[-1] > $best_fitness)
	      {
		#Save the best solution
		$best_internal_solution = [@$internal_solution];
		$best_fitness = $fitnesses[-1];

		my $best_stddev = 1/(log($best_fitness)/1000);
		my $i = 0;
		verbose("Best Solution [with STD DEV $best_stddev]: ",
			join(',',
			     map {$order[$i++] . ":" . ($_ * .1)}
			     @{$best_internal_solution}));
	      }
	  }

	debug("Total Fitness: [$total_fitness]  Average Fitness: [",
	      $total_fitness / scalar(@fitnesses),"].");

	verboseOverMe("Beginning Natural Selection & Mutations.");

	#Until the next generation is equal to the population size
	my @next_generation = ();
	for(my $i = 0;$i < $pop_size;$i += 2)
	  {
	    #Select 2 members of the population based on fitness score
	    $rand1 = rand() * $total_fitness;
	    $rand2 = rand() * $total_fitness;

	    $sum = $j = 0;
	    while($sum < $rand1 || $sum < $rand2)
	      {
		$mom = $j if($sum < $rand1 && $sum < $rand2);
		$sum += $fitnesses[$j++];
	      }
	    $dad = $j - 1;

	    debug("Fitness sum: [$sum], ",
		  "Mom: $mom ($fitnesses[$mom]), ",
		  "Dad: $dad ($fitnesses[$dad])");

#	    $sum = 0;
#	    $j = 0;
#	    while($sum < $rand2)
#	      {$sum += $fitnesses[$j++]}
#	    $dad = $j - 1;

	    #Crossover the two selected
	    #Point-Mutate the two selected
#	    my $in = 0;
#	    debug("Mom Before Mutating: ",
#		  join(',',
#		       map {$order[$in++] . ":" . ($_ * .1)}
#		       @{$population->[$mom]}));
#	    $in = 0;
#	    debug("Dad Before Mutating: ",
#		  join(',',
#		       map {$order[$in++] . ":" . ($_ * .1)}
#		       @{$population->[$dad]}));
	    @new_solutions = pointMutate(crossover($population->[$mom],
						   $population->[$dad]));
#	    $in = 0;
#	    debug("Mom After Mutating: ",
#		  join(',',
#		       map {$order[$in++] . ":" . ($_ * .1)}
#		       @{$new_solutions[0]}));
#	    $in = 0;
#	    debug("Dad After Mutating: ",
#		  join(',',
#		       map {$order[$in++] . ":" . ($_ * .1)}
#		       @{$new_solutions[1]}));

	    #Put the first mutated individual in the next generation
	    push(@$next_generation,$new_solutions[0]);

	    #If the next generation size is less than the population size
	    if($i <= $pop_size)
	      {
		#Put the second mutated individual in the next generation
		push(@$next_generation,$new_solutions[1]);
	      }
	  }
      }

    #Convert the internal solution to a "Real solution" so we can return it
    my $i = 0;
    #$solution->{VALUES} = [{AT => ...},{AA => ...},{AT => ...}]
    debug("Last element of best internal solution: ",
	  $#{$best_internal_solution}," = ",
	  $best_internal_solution->[$#{$best_internal_solution}]);
    my $best_solution = {};
    $best_solution->{VALUES} =
      [{map {$order[$i++] => $_ * .1}
	@{$best_internal_solution}[0..(scalar(@$cp1s) - 1)]},
       {map {$order[$i++] => $_ * .1}
	@{$best_internal_solution}[scalar(@$cp1s)..(scalar(@$cp1s) +
						    scalar(@$ips) - 1)]},
       {map {$order[$i++] => $_ * .1}
	@{$best_internal_solution}[(scalar(@$cp1s) + scalar(@$ips))..
				   $#{$best_internal_solution}]}];
    $best_solution->{STDDEV} = 1/(log($best_fitness)/1000);

    return($best_solution);
  }

#Takes internal solutions (array references) and mutates the values contained
#based on the mutation rate.  Returns the *same* array references.  Note, this
#changes the values set in main.  This is OK for the intended use because
#crossover will be called first and it creates new arrays.
sub pointMutate
  {
    my $solutions = [@_];
    #global: $mutation_rate

    foreach my $solution (@$solutions)
      {foreach my $index (0..$#{$solution})
	 {if(rand() <= $mutation_rate)
	    {
#	      debug("Point Mutating.");
	      $solution->[$index] = int(rand(11));
	    }}}

    return(@$solutions);
  }

#Assumes solution arrays are the same size
sub crossover
  {
    my $daughter_solution = [@{$_[0]}];
    my $son_solution      = [@{$_[1]}];
    my($tmp);
    #globals: $crossover_rate, $crossover_amount, $crossover_cutoff
    if(rand() <= $crossover_rate)
      {
	foreach my $position (0..$#{$daughter_solution})
	  {
	    if(($daughter_solution->[$position] * .1 >= $crossover_cutoff ||
		$son_solution->[$position] * .1 >= $crossover_cutoff) &&
	       rand() <= $crossover_amount)
	      {
#		debug("Crossing Over.");
		$tmp = $son_solution->[$position];
		$son_solution->[$position] = $daughter_solution->[$position];
		$daughter_solution->[$position] = $tmp;
	      }
	  }
      }

    return($daughter_solution,$son_solution);
  }

#Creates an array of 22 values that are between 0 and 10 inclusive
sub getRandomInternalSolution
  {
    my $size = $_[0];
    my $internal_solution = [];
    foreach(1..$size)
      {push(@$internal_solution,int(rand(11)))}
    return($internal_solution);
  }

sub getStandardDeviation
  {
    my $internal_solution = $_[0];
    my $int_sol_pos_hash  = $_[1];
    my $known_kds         = $_[2]; #An array of arrays: [[cp1,ip,cp2,kd],,,]

    my $errsum    = 0;
    my $num_calcs = 0;

    foreach my $calculate_kd_array (@$known_kds)
      {
	foreach my $known_kd_array (@$known_kds)
	  {
	    next if($known_kd_array eq $calculate_kd_array);
	    $num_calcs++;
	    $errsum += ($calculate_kd_array->[3] -
			internalCalculateKd($internal_solution,
					    $int_sol_pos_hash,
					    $calculate_kd_array,
					    $known_kd_array))**2;
	  }
      }

    return(sqrt($errsum / $num_calcs));
  }

sub copySolution
  {
    my $solution = $_[0];
    my $copy = {VALUES => [map {my $x = {%$_};$x} @{$solution->{VALUES}}],
		STDDEV => $solution->{STDDEV}};
    return($copy);
  }





#This sub has a "bag" for each position being incremented.  in other words, the
#$pool_size is an array of values equal in size to the $set_size
#Example: while(GetNextIndepCombo($ary,[6,2,6])){print(join(",",@$ary),"\n")}
sub GetNextIndepCombo
  {
    #Read in parameters
    my $combo      = $_[0];  #An Array of numbers
    my $pool_sizes = $_[1];  #An Array of numbers indicating the range for each
                             #position in $combo

    if(ref($combo) ne 'ARRAY' ||
       scalar(grep {/\D/} @$combo))
      {
	print STDERR ("ERROR:ordered_digit_increment.pl:GetNextIndepCombo:",
		      "The first argument must be an array reference to an ",
		      "array of integers.\n");
	return(0);
      }
    elsif(ref($pool_sizes) ne 'ARRAY' ||
	  scalar(grep {/\D/} @$pool_sizes))
      {
	print STDERR ("ERROR:ordered_digit_increment.pl:GetNextIndepCombo:",
		      "The second argument must be an array reference to an ",
		      "array of integers.\n");
	return(0);
      }

    my $set_size   = scalar(@$pool_sizes);

    #Initialize the combination if it's empty (first one) or if the set size
    #has changed since the last combo
    if(scalar(@$combo) == 0 || scalar(@$combo) != $set_size)
      {
	#Empty the combo
	@$combo = ();
	#Fill it with zeroes
        @$combo = (split('','0' x $set_size));
	#Return true
        return(1);
      }

    my $cur_index = $#{@$combo};

    #Increment the last number of the combination if it is below the pool size
    #(minus 1 because we start from zero) and return true
    if($combo->[$cur_index] < ($pool_sizes->[$cur_index] - 1))
      {
        $combo->[$cur_index]++;
        return(1);
      }

    #While the current number (starting from the end of the combo and going
    #down) is at the limit and we're not at the beginning of the combination
    while($combo->[$cur_index] == ($pool_sizes->[$cur_index] - 1) &&
	  $cur_index >= 0)
      {
	#Decrement the current number index
        $cur_index--;
      }

    #If we've gone past the beginning of the combo array
    if($cur_index < 0)
      {
	@$combo = ();
	#Return false
	return(0);
      }

    #Increment the last number out of the above loop
    $combo->[$cur_index]++;

    #For every number in the combination after the one above
    foreach(($cur_index+1)..$#{@$combo})
      {
	#Set its value equal to 0
	$combo->[$_] = 0;
      }

    #Return true
    return(1);
  }














##
## Subroutines
##

##
## This subroutine prints a description of the script and it's input and output
## files.
##
sub help
  {
    my $script = $0;
    my $lmd = localtime((stat($script))[9]);
    $script =~ s/^.*\/([^\/]+)$/$1/;

    #$software_version_number  - global
    #$created_on_date          - global
    $created_on_date = 'UNKNOWN' if($created_on_date eq 'DATE HERE');

    #Print a description of this program
    print << "end_print";

$script version $software_version_number
Copyright 2008
Robert W. Leach
Created: $created_on_date
Last Modified: $lmd
Center for Computational Research
701 Ellicott Street
Buffalo, NY 14203
rwleach\@ccr.buffalo.edu

* WHAT IS THIS: This script takes a set of 1x1 tRNA loops including a single
                closing base pair on each end and it'd Kd for binding a single
                ligand and uses an equation to search all possible solutions
                (in increments of 0.1) that fit the known Kds in that data.
                Using the equation, one can predict the Kd of an unknown loop.
                The solution consists of a set of importance factors broken
                down by base pair position and value.  Here is the equation:

                calculated_k_d = known_k_d + effect_range * (pv1_c - pv1_k) +
                                 effect_range * (lv2_c - lv2_k) + effect_range
                                 * (pv3_c - pv3_k)

                where:
                	pv = pair value
                	lv = loop value
                	1,2,3 = pair position
                	_c = calculated
                	_k = known

                Note, the default effect range is the difference in Kd between
                loops that differ by only one base pair.  At the time this
                script was written, the data we had dictated the default Kd of
                410.4.

* INPUT FORMAT: The input file is a tab-delimited file of tRNA 1x1 loops
                (including a closing base pair on each end).  Each base pair is
                separated by a non-alphabetic character (e.g. comma) and the
                last column is the Kd.  Example:

                GC,UU,CG	130
                CG,UU,CG	1050
                AU,UU,UA	370
                GU,UU,UG	810
                GC,CC,CG	290
                CG,CC,CG	1000
                GC,AA,CG	450
                CG,AA,CG	820
                CG,GG,CG	520

* OUTPUT FORMAT: Example:



end_print

    return(0);
  }

##
## This subroutine prints a usage statement in long or short form depending on
## whether "no descriptions" is true.
##
sub usage
  {
    my $no_descriptions = $_[0];

    my $script = $0;
    $script =~ s/^.*\/([^\/]+)$/$1/;

    #Grab the first version of each option from the global GetOptHash
    my $options = '[' .
      join('] [',
	   grep {$_ ne '-i'}           #Remove REQUIRED params
	   map {my $key=$_;            #Save the key
		$key=~s/\|.*//;        #Remove other versions
		$key=~s/(\!|=.|:.)$//; #Remove trailing getopt stuff
		$key = (length($key) > 1 ? '--' : '-') . $key;} #Add dashes
	   grep {$_ ne '<>'}           #Remove the no-flag parameters
	   keys(%$GetOptHash)) .
	     ']';

    print << "end_print";
USAGE: $script -i "input file(s)" $options
       $script $options < input_file
end_print

    if($no_descriptions)
      {print("`$script` for expanded usage.\n")}
    else
      {
        print << 'end_print';

     -i|--input-file*     REQUIRED Space-separated input file(s inside quotes).
                                   Standard input via redirection is
                                   acceptable.  Perl glob characters (e.g. '*')
                                   are acceptable inside quotes (e.g.
                                   -i "*.txt *.text").  See --help for a
                                   description of the input file format.
                                   *No flag required.
     -r|--effect-range    OPTIONAL [410.4] The maximum difference in Kd
                                   observed when loops differ by only one base
                                   pair (including one closing base pair on
                                   each end).
     -v|--cross-validate  OPTIONAL [Off] For each loop in the input file,
                                   calculate the optimized equation based on
                                   the rest of the data, then evaluate whether
                                   the witheld data falls within the calculated
                                   standard deviation.
     -g|--genetic-        OPTIONAL [Off] Search for a solution using a genetic
        algorithm                 algorithm heuristic.  This strategy will
                                   randomly pick a 'population' of solutions
                                   and then evolve them using the supplied
                                   mutation and crossover rates until the
                                   target standard deviation is reached or the
                                   script runs for the maximum number of
                                   seconds.  Natural selection is driven by the
                                   standard deviation of the solutions.  Lower
                                   standard deviations are an advantage some
                                   solutions will have over others.  The -g
                                   flag is required in order for the following
                                   5 options.  Otherwise, they aren't used.
     -p|--population-size OPTIONAL [10000] The number of solutions generated
                                   at each generation.  Only used when the -g
                                   flag is supplied.
     -m|--mutation-rate   OPTIONAL [0.005] This is a value between 0 and 1
                                   (exclusive) that represents the chance that
                                   each individual importance factor will be
                                   changed to a different randomly selected
                                   value.  Only used when the -g flag is
                                   supplied.
     -c|--crossover-rate  OPTIONAL [0.7] This is a value between 0 and 1
                                   (exclusive) that represents the chance that
                                   two solutions will swap a set of factors for
                                   one position in the loop.  The set swapped
                                   is determined by -k and -a (see those
                                   options below).  Only used when the -g flag
                                   is supplied.
     -k|--crossover-      OPTIONAL [0.7] Advanced option - probably should
        cutoff                     leave the default.  This is a value between
                                   0 and 1 (exclusive).  It determines which
                                   'importance factors' (this value and above)
                                   will be considered for swapping between two
                                   solutions that were selected by natural
                                   selection.  Factors are swapped with the
                                   value in the opposite solution which has a
                                   matching pair (e.g. AU).  See -a for the
                                   amount of these factors that will be
                                   swapped.  Only used when the -g flag is
                                   supplied.
     -a|--crossover-      OPTIONAL [0.5] Advanced option - probably should
        amount                    leave the default.  This is a value between
                                   0 and 1 (exclusive).  It determines the
                                   chance an importance factor above the cutoff
                                   (supplied via -a) will be swapped between
                                   two solutions selected by natural selection.
                                   Only used when the -g flag is supplied.
     -s|--max-seconds     OPTIONAL [3600] The amount of time to spend running
                                   and optimizing the solution.  Note, when
                                   used with the -v option, this time applies
                                   to each of the cross-validation steps, which
                                   is the same as the number of loops in the
                                   supplied file.  A value of 0 means that the
                                   script will run indefinitely until the
                                   --target-stddev is reached.  Only used when
                                   the -g flag is supplied.
     -t|--target-stddev   OPTIONAL [0] If a solution is found with an average
                                   standard deviation at or below this
                                   threshold, the program will stop before the
                                   supplied --max-seconds.  Only used when the
                                   -g flag is supplied.
     -o|--outfile-suffix  OPTIONAL [nothing] This suffix is added to the input
                                   file names to use as output files.
                                   Redirecting a file into this script will
                                   result in the output file name to be "STDIN"
                                   with your suffix appended.  See --help for a
                                   description of the output file format.
     --force|--overwrite  OPTIONAL Force overwrite of existing output files.
                                   Only used when the -o option is supplied.
     --ignore             OPTIONAL Ignore critical errors & continue
                                   processing.  (Errors will still be
                                   reported.)  See --force to not exit when
                                   existing output files are found.
     --verbose            OPTIONAL Verbose mode.  Cannot be used with the quiet
                                   flag.  Verbosity level can be increased by
                                   supplying a number (e.g. --verbose 2) or by
                                   supplying the --verbose flag multiple times.
     --quiet              OPTIONAL Quiet mode.  Suppresses warnings and errors.
                                   Cannot be used with the verbose or debug
                                   flags.
     --help|-?            OPTIONAL Help.  Print an explanation of the script
                                   and its input/output files.
     --version            OPTIONAL Print software version number.  If verbose
                                   mode is on, it also prints the template
                                   version used to standard error.
     --debug              OPTIONAL Debug mode.  Adds debug output to STDERR and
                                   prepends trace information to warning and
                                   error messages.  Cannot be used with the
                                   --quiet flag.  Debug level can be increased
                                   by supplying a number (e.g. --debug 2) or by
                                   supplying the --debug flag multiple times.
     --noheader           OPTIONAL Suppress commented header output.  Without
                                   this option, the script version, date/time,
                                   and command-line information will be printed
                                   at the top of all output files commented
                                   with '#' characters.

end_print
      }

    return(0);
  }


##
## Subroutine that prints formatted verbose messages.  Specifying a 1 as the
## first argument prints the message in overwrite mode (meaning subsequence
## verbose, error, warning, or debug messages will overwrite the message
## printed here.  However, specifying a hard return as the first character will
## override the status of the last line printed and keep it.  Global variables
## keep track of print length so that previous lines can be cleanly
## overwritten.
##
sub verbose
  {
    return(0) unless($verbose);

    #Read in the first argument and determine whether it's part of the message
    #or a value for the overwrite flag
    my $overwrite_flag = $_[0];

    #If a flag was supplied as the first parameter (indicated by a 0 or 1 and
    #more than 1 parameter sent in)
    if(scalar(@_) > 1 && ($overwrite_flag eq '0' || $overwrite_flag eq '1'))
      {shift(@_)}
    else
      {$overwrite_flag = 0}

#    #Ignore the overwrite flag if STDOUT will be mixed in
#    $overwrite_flag = 0 if(isStandardOutputToTerminal());

    #Read in the message
    my $verbose_message = join('',grep {defined($_)} @_);

    $overwrite_flag = 1 if(!$overwrite_flag && $verbose_message =~ /\r/);

    #Initialize globals if not done already
    $main::last_verbose_size  = 0 if(!defined($main::last_verbose_size));
    $main::last_verbose_state = 0 if(!defined($main::last_verbose_state));
    $main::verbose_warning    = 0 if(!defined($main::verbose_warning));

    #Determine the message length
    my($verbose_length);
    if($overwrite_flag)
      {
	$verbose_message =~ s/\r$//;
	if(!$main::verbose_warning && $verbose_message =~ /\n|\t/)
	  {
	    warning('Hard returns and tabs cause overwrite mode to not work ',
		    'properly.');
	    $main::verbose_warning = 1;
	  }
      }
    else
      {chomp($verbose_message)}

    #If this message is not going to be over-written (i.e. we will be printing
    #a \n after this verbose message), we can reset verbose_length to 0 which
    #will cause $main::last_verbose_size to be 0 the next time this is called
    if(!$overwrite_flag)
      {$verbose_length = 0}
    #If there were \r's in the verbose message submitted (after the last \n)
    #Calculate the verbose length as the largest \r-split string
    elsif($verbose_message =~ /\r[^\n]*$/)
      {
	my $tmp_message = $verbose_message;
	$tmp_message =~ s/.*\n//;
	($verbose_length) = sort {length($b) <=> length($a)}
	  split(/\r/,$tmp_message);
      }
    #Otherwise, the verbose_length is the size of the string after the last \n
    elsif($verbose_message =~ /([^\n]*)$/)
      {$verbose_length = length($1)}

    #If the buffer is not being flushed, the verbose output doesn't start with
    #a \n, and output is to the terminal, make sure we don't over-write any
    #STDOUT output
    #NOTE: This will not clean up verbose output over which STDOUT was written.
    #It will only ensure verbose output does not over-write STDOUT output
    #NOTE: This will also break up STDOUT output that would otherwise be on one
    #line, but it's better than over-writing STDOUT output.  If STDOUT is going
    #to the terminal, it's best to turn verbose off.
    if(!$| && $verbose_message !~ /^\n/ && isStandardOutputToTerminal())
      {
	#The number of characters since the last flush (i.e. since the last \n)
	#is the current cursor position minus the cursor position after the
	#last flush (thwarted if user prints \r's in STDOUT)
	my $num_chars = tell(STDOUT) - sysseek(STDOUT,0,1);

	#If there have been characters printed since the last \n, prepend a \n
	#to the verbose message so that we do not over-write the user's STDOUT
	#output
	if($num_chars > 0)
	  {$verbose_message = "\n$verbose_message"}
      }

    #Overwrite the previous verbose message by appending spaces just before the
    #first hard return in the verbose message IF THE VERBOSE MESSAGE DOESN'T
    #BEGIN WITH A HARD RETURN.  However note that the length stored as the
    #last_verbose_size is the length of the last line printed in this message.
    if($verbose_message =~ /^([^\n]*)/ && $main::last_verbose_state &&
       $verbose_message !~ /^\n/)
      {
	my $append = ' ' x ($main::last_verbose_size - length($1));
	unless($verbose_message =~ s/\n/$append\n/)
	  {$verbose_message .= $append}
      }

    #If you don't want to overwrite the last verbose message in a series of
    #overwritten verbose messages, you can begin your verbose message with a
    #hard return.  This tells verbose() to not overwrite the last line that was
    #printed in overwrite mode.

    #Print the message to standard error
    print STDERR ($verbose_message,
		  ($overwrite_flag ? "\r" : "\n"));

    #Record the state
    $main::last_verbose_size  = $verbose_length;
    $main::last_verbose_state = $overwrite_flag;

    #Return success
    return(0);
  }

sub verboseOverMe
  {verbose(1,@_)}

##
## Subroutine that prints errors with a leading program identifier containing a
## trace route back to main to see where all the subroutine calls were from,
## the line number of each call, an error number, and the name of the script
## which generated the error (in case scripts are called via a system call).
##
sub error
  {
    return(0) if($quiet);

    #Gather and concatenate the error message and split on hard returns
    my @error_message = split(/\n/,join('',grep {defined($_)} @_));
    push(@error_message,'') unless(scalar(@error_message));
    pop(@error_message) if(scalar(@error_message) > 1 &&
			   $error_message[-1] !~ /\S/);

    $main::error_number++;
    my $leader_string = "ERROR$main::error_number:";

    #Assign the values from the calling subroutines/main
    my(@caller_info,$line_num,$caller_string,$stack_level,$script);
    if($DEBUG)
      {
	$script = $0;
	$script =~ s/^.*\/([^\/]+)$/$1/;
	@caller_info = caller(0);
	$line_num = $caller_info[2];
	$caller_string = '';
	$stack_level = 1;
	while(@caller_info = caller($stack_level))
	  {
	    my $calling_sub = $caller_info[3];
	    $calling_sub =~ s/^.*?::(.+)$/$1/ if(defined($calling_sub));
	    $calling_sub = (defined($calling_sub) ? $calling_sub : 'MAIN');
	    $caller_string .= "$calling_sub(LINE$line_num):"
	      if(defined($line_num));
	    $line_num = $caller_info[2];
	    $stack_level++;
	  }
	$caller_string .= "MAIN(LINE$line_num):";
	$leader_string .= "$script:$caller_string";
      }

    $leader_string .= ' ';

    #Figure out the length of the first line of the error
    my $error_length = length(($error_message[0] =~ /\S/ ?
			       $leader_string : '') .
			      $error_message[0]);

    #Put location information at the beginning of the first line of the message
    #and indent each subsequent line by the length of the leader string
    print STDERR ($leader_string,
		  shift(@error_message),
		  ($verbose &&
		   defined($main::last_verbose_state) &&
		   $main::last_verbose_state ?
		   ' ' x ($main::last_verbose_size - $error_length) : ''),
		  "\n");
    my $leader_length = length($leader_string);
    foreach my $line (@error_message)
      {print STDERR (' ' x $leader_length,
		     $line,
		     "\n")}

    #Reset the verbose states if verbose is true
    if($verbose)
      {
	$main::last_verbose_size  = 0;
	$main::last_verbose_state = 0;
      }

    #Return success
    return(0);
  }


##
## Subroutine that prints warnings with a leader string containing a warning
## number
##
sub warning
  {
    return(0) if($quiet);

    $main::warning_number++;

    #Gather and concatenate the warning message and split on hard returns
    my @warning_message = split(/\n/,join('',grep {defined($_)} @_));
    push(@warning_message,'') unless(scalar(@warning_message));
    pop(@warning_message) if(scalar(@warning_message) > 1 &&
			     $warning_message[-1] !~ /\S/);

    my $leader_string = "WARNING$main::warning_number:";

    #Assign the values from the calling subroutines/main
    my(@caller_info,$line_num,$caller_string,$stack_level,$script);
    if($DEBUG)
      {
	$script = $0;
	$script =~ s/^.*\/([^\/]+)$/$1/;
	@caller_info = caller(0);
	$line_num = $caller_info[2];
	$caller_string = '';
	$stack_level = 1;
	while(@caller_info = caller($stack_level))
	  {
	    my $calling_sub = $caller_info[3];
	    $calling_sub =~ s/^.*?::(.+)$/$1/ if(defined($calling_sub));
	    $calling_sub = (defined($calling_sub) ? $calling_sub : 'MAIN');
	    $caller_string .= "$calling_sub(LINE$line_num):"
	      if(defined($line_num));
	    $line_num = $caller_info[2];
	    $stack_level++;
	  }
	$caller_string .= "MAIN(LINE$line_num):";
	$leader_string .= "$script:$caller_string";
      }

    $leader_string .= ' ';

    #Figure out the length of the first line of the error
    my $warning_length = length(($warning_message[0] =~ /\S/ ?
				 $leader_string : '') .
				$warning_message[0]);

    #Put leader string at the beginning of each line of the message
    #and indent each subsequent line by the length of the leader string
    print STDERR ($leader_string,
		  shift(@warning_message),
		  ($verbose &&
		   defined($main::last_verbose_state) &&
		   $main::last_verbose_state ?
		   ' ' x ($main::last_verbose_size - $warning_length) : ''),
		  "\n");
    my $leader_length = length($leader_string);
    foreach my $line (@warning_message)
      {print STDERR (' ' x $leader_length,
		     $line,
		     "\n")}

    #Reset the verbose states if verbose is true
    if($verbose)
      {
	$main::last_verbose_size  = 0;
	$main::last_verbose_state = 0;
      }

    #Return success
    return(0);
  }


##
## Subroutine that gets a line of input and accounts for carriage returns that
## many different platforms use instead of hard returns.  Note, it uses a
## global array reference variable ($infile_line_buffer) to keep track of
## buffered lines from multiple file handles.
##
sub getLine
  {
    my $file_handle = $_[0];

    #Set a global array variable if not already set
    $main::infile_line_buffer = {} if(!defined($main::infile_line_buffer));
    if(!exists($main::infile_line_buffer->{$file_handle}))
      {$main::infile_line_buffer->{$file_handle}->{FILE} = []}

    #If this sub was called in array context
    if(wantarray)
      {
	#Check to see if this file handle has anything remaining in its buffer
	#and if so return it with the rest
	if(scalar(@{$main::infile_line_buffer->{$file_handle}->{FILE}}) > 0)
	  {
	    return(@{$main::infile_line_buffer->{$file_handle}->{FILE}},
		   map
		   {
		     #If carriage returns were substituted and we haven't
		     #already issued a carriage return warning for this file
		     #handle
		     if(s/\r\n|\n\r|\r/\n/g &&
			!exists($main::infile_line_buffer->{$file_handle}
				->{WARNED}))
		       {
			 $main::infile_line_buffer->{$file_handle}->{WARNED}
			   = 1;
			 warning('Carriage returns were found in your file ',
				 'and replaced with hard returns.');
		       }
		     split(/(?<=\n)/,$_);
		   } <$file_handle>);
	  }
	
	#Otherwise return everything else
	return(map
	       {
		 #If carriage returns were substituted and we haven't already
		 #issued a carriage return warning for this file handle
		 if(s/\r\n|\n\r|\r/\n/g &&
		    !exists($main::infile_line_buffer->{$file_handle}
			    ->{WARNED}))
		   {
		     $main::infile_line_buffer->{$file_handle}->{WARNED}
		       = 1;
		     warning('Carriage returns were found in your file ',
			     'and replaced with hard returns.');
		   }
		 split(/(?<=\n)/,$_);
	       } <$file_handle>);
      }

    #If the file handle's buffer is empty, put more on
    if(scalar(@{$main::infile_line_buffer->{$file_handle}->{FILE}}) == 0)
      {
	my $line = <$file_handle>;
	if(defined($line))# && $line =~ /./)
	  {
	    if($line =~ s/\r\n|\n\r|\r/\n/g &&
	       !exists($main::infile_line_buffer->{$file_handle}->{WARNED}))
	      {
		$main::infile_line_buffer->{$file_handle}->{WARNED} = 1;
		warning('Carriage returns were found in your file and ',
			'replaced with hard returns.');
	      }
	    @{$main::infile_line_buffer->{$file_handle}->{FILE}} =
	      split(/(?<=\n)/,$line);
	  }
#	else
#	  {
	    #Do the \r substitution for the last line of files that have the
	    #eof character at the end of the last line instead of on a line by
	    #itself.  I tested this on a file that was causing errors for the
	    #last line and it works.
#	    $line =~ s/\r/\n/g if(defined($line));
#	    @{$main::infile_line_buffer->{$file_handle}->{FILE}} = ($line);
#	  }
      }

    #Shift off and return the first thing in the buffer for this file handle
    return($_ = shift(@{$main::infile_line_buffer->{$file_handle}->{FILE}}));
  }

##
## This subroutine allows the user to print debug messages containing the line
## of code where the debug print came from and a debug number.  Debug prints
## will only be printed (to STDERR) if the debug option is supplied on the
## command line.
##
sub debug
  {
    return(0) unless($DEBUG);

    $main::debug_number++;

    #Gather and concatenate the error message and split on hard returns
    my @debug_message = split(/\n/,join('',grep {defined($_)} @_));
    push(@debug_message,'') unless(scalar(@debug_message));
    pop(@debug_message) if(scalar(@debug_message) > 1 &&
			   $debug_message[-1] !~ /\S/);

    #Assign the values from the calling subroutine
    #but if called from main, assign the values from main
    my($junk1,$junk2,$line_num,$calling_sub);
    (($junk1,$junk2,$line_num,$calling_sub) = caller(1)) ||
      (($junk1,$junk2,$line_num) = caller());

    #Edit the calling subroutine string
    $calling_sub =~ s/^.*?::(.+)$/$1:/ if(defined($calling_sub));

    my $leader_string = "DEBUG$main::debug_number:LINE$line_num:" .
      (defined($calling_sub) ? $calling_sub : '') .
	' ';

    #Figure out the length of the first line of the error
    my $debug_length = length(($debug_message[0] =~ /\S/ ?
			       $leader_string : '') .
			      $debug_message[0]);

    #Put location information at the beginning of each line of the message
    print STDERR ($leader_string,
		  shift(@debug_message),
		  ($verbose &&
		   defined($main::last_verbose_state) &&
		   $main::last_verbose_state ?
		   ' ' x ($main::last_verbose_size - $debug_length) : ''),
		  "\n");
    my $leader_length = length($leader_string);
    foreach my $line (@debug_message)
      {print STDERR (' ' x $leader_length,
		     $line,
		     "\n")}

    #Reset the verbose states if verbose is true
    if($verbose)
      {
	$main::last_verbose_size = 0;
	$main::last_verbose_state = 0;
      }

    #Return success
    return(0);
  }


##
## This sub marks the time (which it pushes onto an array) and in scalar
## context returns the time since the last mark by default or supplied mark
## (optional) In array context, the time between all marks is always returned
## regardless of a supplied mark index
## A mark is not made if a mark index is supplied
## Uses a global time_marks array reference
##
sub markTime
  {
    #Record the time
    my $time = time();

    #Set a global array variable if not already set to contain (as the first
    #element) the time the program started (NOTE: "$^T" is a perl variable that
    #contains the start time of the script)
    $main::time_marks = [$^T] if(!defined($main::time_marks));

    #Read in the time mark index or set the default value
    my $mark_index = (defined($_[0]) ? $_[0] : -1);  #Optional Default: -1

    #Error check the time mark index sent in
    if($mark_index > (scalar(@$main::time_marks) - 1))
      {
	error('Supplied time mark index is larger than the size of the ',
	      "time_marks array.\nThe last mark will be set.");
	$mark_index = -1;
      }

    #Calculate the time since the time recorded at the time mark index
    my $time_since_mark = $time - $main::time_marks->[$mark_index];

    #Add the current time to the time marks array
    push(@$main::time_marks,$time)
      if(!defined($_[0]) || scalar(@$main::time_marks) == 0);

    #If called in array context, return time between all marks
    if(wantarray)
      {
	if(scalar(@$main::time_marks) > 1)
	  {return(map {$main::time_marks->[$_ - 1] - $main::time_marks->[$_]}
		  (1..(scalar(@$main::time_marks) - 1)))}
	else
	  {return(())}
      }

    #Return the time since the time recorded at the supplied time mark index
    return($time_since_mark);
  }

##
## This subroutine reconstructs the command entered on the command line
## (excluding standard input and output redirects).  The intended use for this
## subroutine is for when a user wants the output to contain the input command
## parameters in order to keep track of what parameters go with which output
## files.
##
sub getCommand
  {
    my $perl_path_flag = $_[0];
    my($command);

    #Determine the script name
    my $script = $0;
    $script =~ s/^.*\/([^\/]+)$/$1/;

    #Put quotes around any parameters containing un-escaped spaces or astericks
    my $arguments = [@$preserve_args];
    foreach my $arg (@$arguments)
      {if($arg =~ /(?<!\\)[\s\*]/ || $arg eq '')
	 {$arg = "'" . $arg . "'"}}

    #Determine the perl path used (dependent on the `which` unix built-in)
    if($perl_path_flag)
      {
	$command = `which $^X`;
	chomp($command);
	$command .= ' ';
      }

    #Build the original command
    $command .= join(' ',($0,@$arguments));

    #Note, this sub doesn't add any redirected files in or out

    return($command);
  }

##
## This subroutine checks to see if a parameter is a single file with spaces in
## the name before doing a glob (which would break up the single file name
## improperly).  The purpose is to allow the user to enter a single input file
## name using double quotes and un-escaped spaces as is expected to work with
## many programs which accept individual files as opposed to sets of files.  If
## the user wants to enter multiple files, it is assumed that space delimiting
## will prompt the user to realize they need to escape the spaces in the file
## names.
##
sub sglob
  {
    my $command_line_string = $_[0];
    return(-e $command_line_string ?
	   $command_line_string : glob($command_line_string));
  }


sub getVersion
  {
    my $full_version_flag = $_[0];
    my $template_version_number = '1.37';
    my $version_message = '';

    #$software_version_number  - global
    #$created_on_date          - global
    #$verbose                  - global

    my $script = $0;
    my $lmd = localtime((stat($script))[9]);
    $script =~ s/^.*\/([^\/]+)$/$1/;

    if($created_on_date eq 'DATE HERE')
      {$created_on_date = 'UNKNOWN'}

    $version_message  = join((isStandardOutputToTerminal() ? "\n" : ' '),
			     ("$script Version $software_version_number",
			      " Created: $created_on_date",
			      " Last modified: $lmd"));

    if($full_version_flag)
      {
	$version_message .= (isStandardOutputToTerminal() ? "\n" : ' - ') .
	  join((isStandardOutputToTerminal() ? "\n" : ' '),
	       ('Generated using perl_script_template.pl ' .
		"Version $template_version_number",
		' Created: 5/8/2006',
		' Author:  Robert W. Leach',
		' Contact: robleach@ccr.buffalo.edu',
		' Company: Center for Computational Research',
		' Copyright 2008'));
      }

    return($version_message);
  }

#This subroutine is a check to see if input is user-entered via a TTY (result
#is non-zero) or directed in (result is zero)
sub isStandardInputFromTerminal
  {return(-t STDIN || eof(STDIN))}

#This subroutine is a check to see if prints are going to a TTY.  Note,
#explicit prints to STDOUT when another output handle is selected are not
#considered and may defeat this subroutine.
sub isStandardOutputToTerminal
  {return(-t STDOUT && select() eq 'main::STDOUT')}

#This subroutine exits the current process.  Note, you must clean up after
#yourself before calling this.  Does not exit is $ignore_errors is true.  Takes
#the error number to supply to exit().
sub quit
  {
    my $errno = $_[0];
    if(!defined($errno))
      {$errno = -1}
    elsif($errno !~ /^[+\-]?\d+$/)
      {
	error("Invalid argument: [$errno].  Only integers are accepted.  Use ",
	      "error() or warn() to supply a message, then call quit() with ",
	      "an error number.");
	$errno = -1;
      }

    debug("Exit status: [$errno].");

    exit($errno) if(!$ignore_errors || $errno == 0);
  }
