#!/usr/bin/perl -w

#Generated using perl_script_template.pl 1.37
#Robert W. Leach
#rwleach@ccr.buffalo.edu
#Center for Computational Research
#Copyright 2008

#These variables (in main) are used by getVersion() and usage()
my $software_version_number = '1.6';
my $created_on_date         = '8/11/2009';

##
## Start Main
##

use strict;
use Getopt::Long;

#Declare & initialize variables.  Provide default values here.
my($outfile_suffix); #Not defined so a user can overwrite the input file
my @input_files               = ();
my @refine_files              = ();
my $current_output_file       = '';
my $help                      = 0;
my $version                   = 0;
my $overwrite                 = 0;
my $noheader                  = 0;
my $ga_flag                   = 0;
my $use_raw_error             = 0;
my $pop_size                  = 10000;
my $mutation_rate             = .005; #For approx. 1 mutation/10 sets of 22 vals
my $crossover_rate            = .7;
my $crossover_cutoff          = .7;
my $crossover_amount          = .5;
my $max_seconds               = 0; #One hour
my $target_stddev             = 0; #Must have stddev <= this number to end early
my $default_effect_range_add  = 500;
my $default_effect_range_mult = 15;
my $effect_range              = 0;
my $calc_effect_range         = 0;
my $cross_validate            = 0;
my @cps                       = ('AU','UA','GC','CG','GU','UG');
my @ips                       = ('AG','GA','AC','CA','AA','GG','CC','CU','UC',
				 'UU');
my $precision_level           = 1;
my $fitness_factor            = 100; #Kludge to enhance fittness of good solns
my $unweighted_kd_mode        = 0;
my $weight_kd_c               = 200;
my $weight_kd_x               = 1.5;
my $weight_kd_xsquared        = .005;
my $weight_kd_xcubed          = .00025;
my $equation_type             = 0;

$| = 1;

#These variables (in main) are used by the following subroutines:
#verbose, error, warning, debug, getCommand, quit, and usage
my $preserve_args = [@ARGV];  #Preserve the agruments for getCommand
my $verbose       = 0;
my $quiet         = 0;
my $DEBUG         = 0;
my $ignore_errors = 0;

my $GetOptHash =
  {'r|effect-range=s'      => \$effect_range,           #OPTIONAL [largest diff
					                #          plus 20% or
					                #          500]
   'q|equation-type=s'     => \$equation_type,          #OPTIONAL [0]
   'f|refine-solution=s'   => sub {push(@refine_files,  #OPTIONAL [nothing]
					sglob($_[1]))},
   'u|use-unweighted-kd!'  => \$unweighted_kd_mode,     #OPTIONAL [Off]
   'v|cross-validate!'     => \$cross_validate,         #OPTIONAL [Off]
   'g|genetic-algorithm!'  => \$ga_flag,                #OPTIONAL [Off]
   'p|population-size=s'   => \$pop_size,               #OPTIONAL [10000]
   'm|mutation-rate=s'     => \$mutation_rate,          #OPTIONAL [0.005]
   'x|crossover-rate=s'    => \$crossover_rate,         #OPTIONAL [0.7]
   'crossover-cutoff=s'    => \$crossover_cutoff,       #OPTIONAL [0.7]
   'crossover-amount=s'    => \$crossover_amount,       #OPTIONAL [0.5]
   's|max-seconds=s'       => \$max_seconds,            #OPTIONAL [0]
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

   ##Advanced - don't tamper with unless you understand it completely

   'd|kd-weight-d=s'       => \$weight_kd_c,            #OPTIONAL [200]
   'c|kd-weight-cx=s'      => \$weight_kd_x,            #OPTIONAL [1.5]
   'b|kd-weight-bx2=s'     => \$weight_kd_xsquared,     #OPTIONAL [0.005]
   'a|kd-weight-ax3=s'     => \$weight_kd_xcubed,       #OPTIONAL [0.00025]
   'l|precision-level=s'   => \$precision_level,        #OPTIONAL [1]
   'e|use-raw-error!'      => \$use_raw_error,          #OPTIONAL [Off]
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

if($effect_range !~ /^(\d+\.?\d*|\d*\.\d+)$/)
  {
    error("Invalid effect range entered: [$effect_range].");
    usage(1);
    quit(-1);
  }
elsif($effect_range == 0)
  {$calc_effect_range = 1}

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

if(scalar(@refine_files) != 0 && scalar(@refine_files) != scalar(@input_files))
  {
    error('The number of solution files (-f) to refine must be the same as ',
	  'the number of input files (-i).');
    usage(1);
    quit(-8);
  }

if(scalar(@refine_files) && $cross_validate)
  {
    error("Incompatible options selected.  You cannot refine solutions (-f) ",
	  "in cross-validate (-c) mode.");
    usage(1);
    quit(-9);
  }

if(scalar(@refine_files) && $effect_range != 0)
  {
    error("Incompatible options selected.  You cannot refine solutions (-f) ",
	  "with an effect range (-r) because the solution contains an effect ",
	  "range.");
    usage(1);
    quit(-10);
  }

if(scalar(@refine_files) && $equation_type != 0)
  {
    warning("Incompatible options selected.  You cannot refine solutions (-f) ",
	    "with an equation type (-q) selected because solutions contains ",
	    "an embedded equation type.  We will assume that you know what ",
	    "you're doing (since you could be using a solution produced by an ",
	    "earlier version of this script and use the equation type you ",
	    "provided, but it will be over-written by the value in the ",
	    "equation/factor file you provided if it is there).");
  }

if($precision_level !~ /^[1-9]\d*$/)
  {
    error("Invalid precision level (-l): [$precision_level].  It must be a ",
	  "positive integer.");
    usage(1);
    quit(-11);
  }

if($precision_level > 3)
  {warning("It is recommended that you not make the precision level very high ",
	   "simply because of the chances of not being able to find a good ",
	   "solution.  If you do use a high precision level, you should ",
	   "increase the population size and running time to account for the ",
	   "greater possibilities.")}

if($use_raw_error && $unweighted_kd_mode)
  {
    warning("-e and -w are incompatible.  If you are using raw error (-e), ",
	    "you cannot weight the Kd (-w) in the denominator of error/Kd ",
	    "because raw error does not have Kd in the equation.  We will ",
	    "thus assume -e was supplied by mistake and turn it off for you.");
    $use_raw_error = 0;
  }

if($equation_type !~ /^\d+$/)
  {
    if($equation_type =~ /^(cum|add)/i)
      {$equation_type = 0}
    elsif($equation_type =~ /^mult/i)
      {$equation_type = 1}
    else
      {
	error("Invalid equation type (-q): [$equation_type].  Options are ",
	      "limited to 'cumulative'/'additive' effect (0) or ",
	      "'multiplicative' effect (1).  ",
	      "Defaulting to the cumulative effect equation (0).");
	$equation_type = 0;
      }
  }

if($equation_type != 0 && $equation_type != 1)
  {
    error("Invalid equation type (-q): [$equation_type].  Options are limited ",
	  "to 'cumulative'/'additive' effect (0) or 'multiplicative' ",
	  "effect (1).  Defaulting to the cumulative effect equation (0).");
    $equation_type = 0;
  }

verbose('Run conditions: ',getCommand(1));




#If output is going to STDOUT instead of output files with different extensions
#or if STDOUT was redirected, output run info once
verbose('[STDOUT] Opened for all output.') if(!defined($outfile_suffix));

#Store info. about the run as a comment at the top of the output file if
#STDOUT has been redirected to a file
my $header = join('',('#',getVersion(),"\n",
		      '#',scalar(localtime($^T)),"\n",
		      '#',getCommand(1),"\n"));
if(!isStandardOutputToTerminal() && !$noheader)
  {print($header);}

my $rand_input = '1' . ('0' x $precision_level);
$rand_input++;
my $conversion_factor = '.' . ('0' x ($precision_level - 1)) . '1';
debug("Precision Level: $precision_level, Rand Input: $rand_input, ",
      "Conversion Factor: $conversion_factor");

#For each input file
foreach my $input_file (@input_files)
  {
    my($refine_file);
    $refine_file = shift(@refine_files) if(scalar(@refine_files));

    if($calc_effect_range)
      {$effect_range = 0}

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

    my $line_num            = 0;
    my $verbose_freq        = 100;
    my $cp1_hash            = {};
    my $ip_hash             = {};
    my $cp2_hash            = {};
    my @known_kds           = ();
    my $motif_check         = {};
    my $best_solution       = [];
    my $diff_by_one         = {};
    my $largest_diff_by_one = 0;
    my $largest_frac_by_one = 0;

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

	#Check to see if loop is a non-binder
	if(!defined($kd) || $kd !~ /^\d+\.?\d*(e\+?\d+)?$/i)
	  {$kd = 'none'}

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
		  "Keeping the first one and ignoring duplicates.");
	    next;
	  }
	else
	  {$motif_check->{"$cp1,$ip,$cp2"} = $kd}

	debug("Reading in loop: [$cp1,$ip,$cp2,$kd].");

	$cp1_hash->{$cp1}++;
	$ip_hash->{$ip}++;
	$cp2_hash->{$cp2}++;
	push(@known_kds,[$cp1,$ip,$cp2,$kd]);

	#Skip the difference calculation if the loop doesn't bind
	next if($kd eq 'none');

	#Keep track of the largest difference in Kd's between loops that differ
	#by only one base pair so we can use it to calculate a good effect
	#range.
	foreach my $quar ("$cp1$ip","$cp1$cp2","$ip$cp2")
	  {
	    if(exists($diff_by_one->{$quar}))
	      {
		if($kd < $diff_by_one->{$quar}->{SM})
		  {
		    if(exists($diff_by_one->{$quar}->{LA}))
		      {$diff_by_one->{$quar}->{SM} = $kd}
		    else
		      {
			$diff_by_one->{$quar}->{LA} =
			  $diff_by_one->{$quar}->{SM};
			$diff_by_one->{$quar}->{SM} = $kd;
		      }
		  }
		elsif(!exists($diff_by_one->{$quar}->{LA}) ||
		      $kd > $diff_by_one->{$quar}->{LA})
		  {$diff_by_one->{$quar}->{LA} = $kd}
		else
		  {$diff_by_one->{$quar}->{SM} = $kd}

		if(exists($diff_by_one->{$quar}->{LA}) &&
		   ($diff_by_one->{$quar}->{LA} - $diff_by_one->{$quar}->{SM}) >
		   $largest_diff_by_one)
		  {
		    $largest_diff_by_one =
		      $diff_by_one->{$quar}->{LA} - $diff_by_one->{$quar}->{SM};
		    $largest_frac_by_one =
		      $diff_by_one->{$quar}->{LA} / $diff_by_one->{$quar}->{SM};
		  }
	      }
	    else
	      {$diff_by_one->{$quar}->{SM} = $kd}
	  }
      }

    close(INPUT);

    verbose('[',($input_file eq '-' ? 'STDIN' : $input_file),'] ',
	    'Input file done.  Time taken: [',scalar(markTime()),' Seconds].');

    #Set the effect range based on whether there's a supplied value or if not,
    #see if the data supports a calculated range (and if so, calculate a range
    #based on the equation type), else use the default based on the equation
    #type.
    if($largest_diff_by_one == 0 && $effect_range == 0)
      {
	if(!defined($equation_type) || $equation_type == 0)
	  {$effect_range = $default_effect_range_add}
	elsif($equation_type == 1)
	  {$effect_range = $default_effect_range_mult}
	else
	  {
	    error("Invalid equation type: [$equation_type]");
	    next;
	  }
      }
    elsif($effect_range == 0)
      {
	if(!defined($equation_type) || $equation_type == 0)
	  {$effect_range = $largest_diff_by_one + ($largest_diff_by_one * .2)}
	elsif($equation_type == 1)
	  {$effect_range = $largest_frac_by_one + ($largest_frac_by_one * .2)}
	else
	  {
	    error("Invalid equation type: [$equation_type]");
	    next;
	  }
      }

    verbose("Effect Range: [$effect_range]");

    #Cross-validate if requested and valid
    if($cross_validate && scalar(@known_kds) > 1)
      {
	#Store info. about the run as a comment at the top of the output file
	#if noheader is not true and we're not in a valid cross-validate mode
	print($header) if(!$noheader);

	my $cross_count = 0;
	foreach my $motif_array (@known_kds)
	  {
	    $cross_count++;

	    verbose("Working on solution $cross_count of ",
		    scalar(@known_kds),'.');

	    debug("Calling getSolutionExhaustively with these known Kd ",
		  "arrays: [",grep {$_ ne $motif_array} @known_kds,
		  "].  There are ",scalar(@known_kds),
		  " known Kd arrays total.");

	    if($cp1_hash->{$motif_array->[0]} == 1 ||
	       $ip_hash->{$motif_array->[1]}  == 1 ||
	       $cp2_hash->{$motif_array->[2]} == 1)
	      {
		warning("Cannot predict a reliable set of factors for loop: ",
			"[@$motif_array] because one or more of its base ",
			"pairs does not exist in the remaining data that is ",
			"being used for optimization.  This script cannot be ",
			"expected to generate importance factors for base ",
			"pairs on which it has not data on which to optimize ",
			"the factor.  Skipping this loop in the cross-",
			"validation.");
		next;
	      }

	    my $solution = {};
	    if($ga_flag)
	      {$solution =
		 getSolutionUsingGA([keys(%$cp1_hash)],
				    [keys(%$ip_hash)],
				    [keys(%$cp2_hash)],
				    [grep {$_ ne $motif_array}
				     @known_kds])}
	    else
	      {$solution =
		 getSolutionExhaustively([keys(%$cp1_hash)],
					 [keys(%$ip_hash)],
					 [keys(%$cp2_hash)],
					 [grep {$_ ne $motif_array}
					  @known_kds])}

	    my($ccp1,$cip,$ccp2,$target_kd);
	    ($ccp1,$cip,$ccp2,$target_kd) = @$motif_array;

	    my $stddev =
	      getStandardDeviation($solution,
				   [grep {$_ ne $motif_array} @known_kds],
				   $motif_array);

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

	#Prepare to refine the supplied solution
	my($refine_solution,$refinement_factor,$refine_solution_unaltered);
	if(defined($refine_file) && $refine_file ne '')
	  {
	    $refine_solution           = getFactorHash($refine_file);
	    $refine_solution_unaltered = copySolution($refine_solution);

	    #Figure out what decimal place we're adding to the refined solution
	    #and prepare it so that values are centered around the current ones
	    if(defined($refine_solution))
	      {
		$effect_range  = $refine_solution->{EFFECT};
		$equation_type = $refine_solution->{TYPE};

		my $max_places = 0;
		foreach my $valhash (@{$refine_solution->{VALUES}})
		  {
		    my $places =
		      (sort {$b <=> $a}
		       map {my $p=$_;$p=~s/\d*\.//;length($p)}
		       values(%$valhash))[0];
		    $max_places = $places if($places > $max_places);
		  }

		$refinement_factor = '0.' . '0' x ($max_places +
						   $precision_level - 1) . '1';

		#We want the factor to be between 0 and 1 (inclusive).  Since we
		#know we're going to be adding at most 10 * refinement_factor
		#and that we're going to be subtracting 5 * refinement_factor,
		#we need to make sure nothing will end up less than 0 or greater
		#than 1
		my $subt = $refinement_factor * 5;
		my $max = 1 - ($refinement_factor * 10);

		foreach my $valhash (@{$refine_solution->{VALUES}})
		  {
		    foreach my $key (keys(%$valhash))
		      {
			unless($valhash->{$key} eq '')
			  {
			    $valhash->{$key} -= $subt;
			    $valhash->{$key} = 0 if($valhash->{$key} < 0);
			    $valhash->{$key} = $max if($valhash->{$key} > $max);
			  }
		      }
		  }
	      }
	  }

	my $solution = {};
	if($ga_flag)
	  {$solution =
	     getSolutionUsingGA([keys(%$cp1_hash)],
				[keys(%$ip_hash)],
				[keys(%$cp2_hash)],
				[@known_kds],
			        $refine_solution,
			        $refinement_factor,
			        $refine_solution_unaltered,
			        $current_output_file)}
	else
	  {$solution =
	     getSolutionExhaustively([keys(%$cp1_hash)],
				     [keys(%$ip_hash)],
				     [keys(%$cp2_hash)],
				     [@known_kds],
				     $refine_solution,
				     $refinement_factor,
				     $refine_solution_unaltered,
				     $current_output_file)}
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












sub getFactorHash
  {
    my $input_file = $_[0];
    #globals: $effect_range, $equation_type

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
    my $solution = {};

    #For each line in the current input file
    while(getLine(*INPUT))
      {
	$line_num++;
	verboseOverMe('[',($input_file eq '-' ? 'STDIN' : $input_file),'] ',
		      "Reading line: [$line_num].") unless($line_num %
							   $verbose_freq);

	next if(/^\s*#/ || /^\s*$/);

	if(/Solution Standard Deviation: (\S+)$/)
	  {
	    if(exists($solution->{STDDEV}))
	      {
		error("Found an extra solution on line [$line_num] in file ",
		      "[$input_file].  Only one solution is allowed per ",
		      "file.  Skipping other solutions.");
		last;
	      }
	    $solution->{STDDEV} = $1;
	  }
	elsif(/Effect Range: (\S+)/)
	  {
	    if(exists($solution->{EFFECT}))
	      {
		error("Found an extra solution on line [$line_num] in file ",
		      "[$input_file].  Only one solution is allowed per ",
		      "file.  Skipping other solutions.");
		last;
	      }
	    $solution->{EFFECT} = $1;
	  }
	elsif(/Equation Type: (\S+)/)
	  {
	    if(exists($solution->{TYPE}))
	      {
		error("Found an extra solution on line [$line_num] in file ",
		      "[$input_file].  Only one solution is allowed per ",
		      "file.  Skipping other solutions.");
		last;
	      }
	    $solution->{TYPE} = $1;
	  }
	elsif(/^\tPosition \d+:$/)
	  {push(@{$solution->{VALUES}},{})}
	elsif(/^\t\t(\S+)\t?(\S*)$/)
	  {
	    my $pair   = $1;
	    my $factor = $2;
	    $factor = '' unless(defined($factor));

	    if(exists($solution->{VALUES}->[-1]->{$pair}))
	      {
		error("This base pair: [$pair] was found more than once in ",
		      "position [",scalar(@{$solution->{VALUES}}),
		      "] in file: [$input_file].  Keeping the first value ",
		      "and skipping the extra.");
		next;
	      }

	    $solution->{VALUES}->[-1]->{$pair} = $factor;
	  }
	else
	  {
	    chomp;
	    error("Unable to parse line $line_num: [$_].");
	  }
      }

    close(INPUT);

    verbose('[',($input_file eq '-' ? 'STDIN' : $input_file),'] ',
	    'Input file done.  Time taken: [',scalar(markTime()),' Seconds].');

    if(scalar(keys(%$solution)) < 2)
      {
	error("Invalid or no solution parsed from file [$input_file].  ",
	      "Skipping.");
	return({});
      }

    if(!exists($solution->{EFFECT}))
      {$solution->{EFFECT} = $effect_range}
    if(!exists($solution->{TYPE}))
      {$solution->{TYPE}   = $equation_type}

    if($solution->{STDDEV} !~ /^(\d+\.?\d*|\d*\.\d+)$/)
      {warning("invalid standard deviation found in file [$input_file]: ",
	       "[$solution->{STDDEV}].")}

    if(scalar(@{$solution->{VALUES}}) < 3)
      {
	error("Invalid solution in file [$input_file].  The loop must be at ",
	      "least 1x1 with 2 closing base pair positions.  Only [",
	      scalar(@{$solution->{VALUES}}),"] positions were parsed.  ",
	      "Skipping.");
	return({});
      }
    elsif(scalar(@{$solution->{VALUES}}) > 3)
      {warning("This script was written to calculate STDDEV's of 1x1 ",
	       "internal loops, but the solution in file [$input_file] ",
	       "appears to be for a larger loop.  It may still work, but ",
	       "this could be a mistake.")}

    my @bad =
      grep {my $h = $_;
	    scalar(grep {$_ !~ /^([A-Z]{2}|)$/i ||
			   $h->{$_} !~ /^(0?\.?\d*|1|)$/} keys(%$h))}
	@{$solution->{VALUES}};
    if(scalar(@bad))
      {
	warning("Invalid base pairs or factor valuess were in your file ",
		"[$input_file]: [(",
		join(')(',
		     map {my $x=$_;
			  join('=>',map {"$_=>$x->{$_}"} keys(%$x))} @bad),
		")].");
      }

    return($solution);
  }

sub reportSolution
  {
    my $solution = $_[0];#{VALUES => [{AT...},{AA...},{{AT...}}],STDDEV => ...}
    my $outfile  = $_[1];
    #globals: @cps, @ips, $effect_range, $use_raw_error, $equation_type, &
    #$header

    #This is for backwards compatibility
    my $et = (exists($solution->{TYPE}) ? $solution->{TYPE} : $equation_type);
    my $er = (exists($solution->{EFFECT}) ?
	      $solution->{EFFECT} : $effect_range);

    #Note, we do not need to alter this sub to account for refined solutions
    #because getSolutionExhaustively and getSolutionUsingGA return whole actual
    #refined solutions

    my $output =
      join('',("Equation Type: $et\n",
	       "Effect Range: $er\n",
	       "Solution Standard Deviation: $solution->{STDDEV}",
	       ($use_raw_error ? '' : '%'),"\n",
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
			    $solution->{VALUES}->[2]->{$_} : '')} @cps),"\n"));

    if(defined($outfile) && $outfile ne '')
      {
	#Open the output file
	if(!open(OUTPUT,">$outfile"))
	  {
	    #Report an error and iterate if there was an error
	    error("Unable to open output file: [$outfile].\n$!");
	  }
	else
	  {select(OUTPUT)}

	print($header);
      }

    print($output);

    if(defined($outfile) && $outfile ne '')
      {
	#Select standard out
       select(STDOUT);
	#Close the output file handle
	close(OUTPUT);
      }

    return($output);
  }

sub calculateKd
  {
    my $solution        = $_[0]; #{VALUES => [{AT...},{AA...},{{AT...}}]}
    my $calculate_motif = $_[1];
    my $known_motif     = $_[2];
    my $known_kd        = $_[3];
    my $kd = $known_kd;

    if(!exists($solution->{EFFECT}))
      {
	error("No effect-range was in the provided solution.");
	return($kd);
      }

    if(scalar(@{$solution->{VALUES}}) != scalar(@$calculate_motif) &&
       scalar(@{$solution->{VALUES}}) != (scalar(@$calculate_motif) - 1) &&
       scalar(@{$solution->{VALUES}}) != scalar(@$known_motif) &&
       scalar(@{$solution->{VALUES}}) != (scalar(@$known_motif) - 1))
      {error("Motifs are not all the same size.")}


    #Note, we do not need to alter this sub to account for refined solutions
    #because getSolutionExhaustively and getSolutionUsingGA return whole actual
    #refined solutions and that's what this sub should take as input.
    #See internalCalculateKd to merge a refining solution and the refined
    #internal solution factors

    if(!exists($solution->{TYPE}) || $solution->{TYPE} == 0)
      {
	foreach my $p (0..$#{$solution->{VALUES}})
	  {
	    if($calculate_motif->[$p] !~ /^[A-Z]{2}$/i ||
	       $known_motif->[$p]     !~ /^[A-Z]{2}$/i)
	      {
		error("Expected 2 base pairs, but got: ",
		      "[$calculate_motif->[$p] and $known_motif->[$p]]");
		next;
	      }

	    debug("Position ",($p+1),
		  ": $calculate_motif->[$p]_c vs. $known_motif->[$p]_k");

	    $kd += $solution->{EFFECT} *

	      ((exists($solution->{VALUES}->[$p]->{$calculate_motif->[$p]}) ?
		$solution->{VALUES}->[$p]->{$calculate_motif->[$p]} : 0) -

	       (exists($solution->{VALUES}->[$p]->{$known_motif->[$p]}) ?
		$solution->{VALUES}->[$p]->{$known_motif->[$p]} : 0));
	  }
      }
    elsif($solution->{TYPE} == 1)
      {
	foreach my $p (0..$#{$solution->{VALUES}})
	  {
	    if($calculate_motif->[$p] !~ /^[A-Z]{2}$/i ||
	       $known_motif->[$p]     !~ /^[A-Z]{2}$/i)
	      {
		error("Expected 2 base pairs, but got: ",
		      "[$calculate_motif->[$p] and $known_motif->[$p]]");
		next;
	      }

	    debug("Position ",($p+1),
		  ": $calculate_motif->[$p]_c vs. $known_motif->[$p]_k");

	    $kd *=

	      (($solution->{EFFECT} - 1) *
	       (exists($solution->{VALUES}->[$p]->{$calculate_motif->[$p]}) ?
		$solution->{VALUES}->[$p]->{$calculate_motif->[$p]} : 0) + 1) /

		  (($solution->{EFFECT} - 1) *
		   (exists($solution->{VALUES}->[$p]->{$known_motif->[$p]}) ?
		    $solution->{VALUES}->[$p]->{$known_motif->[$p]} : 0) + 1);
	  }
      }
    else
      {error("Invalid equation type: [$solution->{TYPE}].")}

    return($kd);
  }

sub internalCalculateKd
  {
    my $solution          = $_[0]; #[pos1factor,pos2factor,pos3factor,...]
    my $int_sol_pos_hash  = $_[1]; #{1=>{AU=>pos1,CG=>pos2,...},
                                   # 2=>{AA=>pos7,...},
                                   # ...}
    my $calculate_motif   = $_[2];
    my $known_motif       = $_[3];
    my $refine_solution   = $_[4];
    my $refinement_factor = $_[5];
    my $kd                = $known_motif->[3];
    #global: $effect_range, $equation_type

    if(scalar(@$calculate_motif) != scalar(@$known_motif))
      {error("Motifs are not all the same size.")}

    if(defined($refine_solution))
      {
	#Cursory check on the solution sizes - should do something more precise
	if(scalar(@{$refine_solution->{VALUES}}) != scalar(@$calculate_motif) &&
	   scalar(@{$refine_solution->{VALUES}}) != (scalar(@$calculate_motif) -
						     1) &&
	   scalar(@{$refine_solution->{VALUES}}) != scalar(@$known_motif) &&
	   scalar(@{$refine_solution->{VALUES}}) != (scalar(@$known_motif) - 1))
	  {error("Motifs are not all the same size.")}

	#This is for backwards compatibility
	my $et = (exists($refine_solution->{TYPE}) ?
		  $refine_solution->{TYPE} : $equation_type);
	my $er = (exists($refine_solution->{EFFECT}) ?
		  $refine_solution->{EFFECT} : $effect_range);

	#Each factor in the existing refining solution must have a value added
	#to it consisting of the refinement factor times the random value in the
	#internal solution

	foreach my $p (0..$#{$refine_solution->{VALUES}})
	  {
	    #Make sure the loops as large as the refine solution
	    if($calculate_motif->[$p] !~ /^[A-Z]{2}$/i ||
	       $known_motif->[$p]     !~ /^[A-Z]{2}$/i)
	      {
		error("Expected 2 base pairs, but got: ",
		      "[$calculate_motif->[$p] and $known_motif->[$p]]");
		next;
	      }

	    #Make sure we don't go outside the bounds of the internal solution
	    if((exists($int_sol_pos_hash->{$p+1}->{$calculate_motif->[$p]}) &&
		$int_sol_pos_hash->{$p+1}->{$calculate_motif->[$p]} >=
		scalar(@$solution)) ||
	       (exists($int_sol_pos_hash->{$p+1}->{$known_motif->[$p]}) &&
		$int_sol_pos_hash->{$p+1}->{$known_motif->[$p]} >=
		scalar(@$solution)))
	      {
		error("Position in hash does not exist in internal solution.");
		next;
	      }

	    debug("Position ",($p+1),
		  ": $calculate_motif->[$p]_c vs. $known_motif->[$p]_k");

	    my $c = (exists($refine_solution->{VALUES}->[$p]
			    ->{$calculate_motif->[$p]}) ?
		     $refine_solution->{VALUES}->[$p]
		     ->{$calculate_motif->[$p]} : 0) +
		       (exists($int_sol_pos_hash->{$p+1}
			       ->{$calculate_motif->[$p]}) ?
			$solution->[$int_sol_pos_hash->{$p+1}
				    ->{$calculate_motif->[$p]}] *
			$refinement_factor : 0);
	    my $k = (exists($refine_solution->{VALUES}->[$p]
			    ->{$known_motif->[$p]}) ?
		     $refine_solution->{VALUES}->[$p]->{$known_motif->[$p]} :
		     0) +
		       (exists($int_sol_pos_hash->{$p+1}
			       ->{$known_motif->[$p]}) ?
			$solution->[$int_sol_pos_hash->{$p+1}
				    ->{$known_motif->[$p]}] *
			$refinement_factor : 0);

	    if(!defined($et) || $et == 0)
	      {$kd += $er * ($c - $k)}
	    elsif($et == 1)
	      {$kd *= ((($er - 1) * $c + 1) / (($er - 1) * $k + 1))}
	    else
	      {error("Invalid equation type: [$et].")}
	  }

#	my $c1 = (exists($refine_solution->{VALUES}->[0]
#			 ->{$calculate_motif->[0]}) ?
#		  $refine_solution->{VALUES}->[0]->{$calculate_motif->[0]} :
#		  0) +
#		    (exists($int_sol_pos_hash->{1}->{$calculate_motif->[0]}) ?
#		     $solution->[$int_sol_pos_hash->{1}
#				 ->{$calculate_motif->[0]}] *
#		     $refinement_factor : 0);
#	my $k1 = (exists($refine_solution->{VALUES}->[0]->{$known_motif->[0]}) ?
#		  $refine_solution->{VALUES}->[0]->{$known_motif->[0]} : 0) +
#		    (exists($int_sol_pos_hash->{1}->{$known_motif->[0]}) ?
#		     $solution->[$int_sol_pos_hash->{1}->{$known_motif->[0]}] *
#		     $refinement_factor : 0);
#	my $c2 = (exists($refine_solution->{VALUES}->[1]
#			 ->{$calculate_motif->[1]}) ?
#		  $refine_solution->{VALUES}->[1]->{$calculate_motif->[1]} :
#		  0) +
#		    (exists($int_sol_pos_hash->{2}->{$calculate_motif->[1]}) ?
#		     $solution->[$int_sol_pos_hash->{2}
#				 ->{$calculate_motif->[1]}] *
#		     $refinement_factor : 0);
#	my $k2 = (exists($refine_solution->{VALUES}->[1]->{$known_motif->[1]}) ?
#		  $refine_solution->{VALUES}->[1]->{$known_motif->[1]} : 0) +
#		    (exists($int_sol_pos_hash->{2}->{$known_motif->[1]}) ?
#		     $solution->[$int_sol_pos_hash->{2}->{$known_motif->[1]}] *
#		     $refinement_factor : 0);
#	my $c3 = (exists($refine_solution->{VALUES}->[2]
#			 ->{$calculate_motif->[2]}) ?
#		  $refine_solution->{VALUES}->[2]->{$calculate_motif->[2]} :
#		  0) +
#		    (exists($int_sol_pos_hash->{3}->{$calculate_motif->[2]}) ?
#		     $solution->[$int_sol_pos_hash->{3}
#				 ->{$calculate_motif->[2]}] *
#		     $refinement_factor : 0);
#	my $k3 = (exists($refine_solution->{VALUES}->[2]->{$known_motif->[2]}) ?
#		  $refine_solution->{VALUES}->[2]->{$known_motif->[2]} : 0) +
#		    (exists($int_sol_pos_hash->{3}->{$known_motif->[2]}) ?
#		     $solution->[$int_sol_pos_hash->{3}->{$known_motif->[2]}] *
#		     $refinement_factor : 0);
#
#	$kd += $er * ($c1 - $k1);
#	$kd += $er * ($c2 - $k2);
#	$kd += $er * ($c3 - $k3);
      }
    else
      {
	foreach my $p (0..($#{$known_motif} - 1))
	  {
	    #Make sure the calculate loop is as large as the known loop
	    if($calculate_motif->[$p] !~ /^[A-Z]{2}$/i ||
	       $known_motif->[$p]     !~ /^[A-Z]{2}$/i)
	      {
		error("Expected 2 base pairs, but got: ",
		      "[$calculate_motif->[$p] and $known_motif->[$p]]");
		next;
	      }

	    #Make sure we don't go outside the bounds of the internal solution
	    if((exists($int_sol_pos_hash->{$p+1}->{$calculate_motif->[$p]}) &&
		$int_sol_pos_hash->{$p+1}->{$calculate_motif->[$p]} >=
		scalar(@$solution)) ||
	       (exists($int_sol_pos_hash->{$p+1}->{$known_motif->[$p]}) &&
		$int_sol_pos_hash->{$p+1}->{$known_motif->[$p]} >=
		scalar(@$solution)))
	      {
		error("Position in hash does not exist in internal solution.");
		next;
	      }

	    debug("Position ",($p+1),
		  ": $calculate_motif->[$p]_c vs. $known_motif->[$p]_k");

	    my $c =
	      (exists($int_sol_pos_hash->{$p+1}->{$calculate_motif->[$p]}) ?
	       $solution->[$int_sol_pos_hash->{$p+1}
			   ->{$calculate_motif->[$p]}] *
	       $conversion_factor : 0);
	    my $k =
	      (exists($int_sol_pos_hash->{$p+1}->{$known_motif->[$p]}) ?
	       $solution->[$int_sol_pos_hash->{$p+1}->{$known_motif->[$p]}] *
	       $conversion_factor : 0);

	    if(!defined($equation_type) || $equation_type == 0)
	      {$kd += $effect_range * ($c - $k)}
	    elsif($equation_type == 1)
	      {$kd *= ((($effect_range - 1) * $c + 1) /
		       (($effect_range - 1) * $k + 1))}
	    else
	      {error("Invalid equation type: [$equation_type].")}
	  }

#	my $c1 = (exists($int_sol_pos_hash->{1}->{$calculate_motif->[0]}) ?
#		  $solution->[$int_sol_pos_hash->{1}->{$calculate_motif->[0]}] *
#		  $conversion_factor : 0);
#	my $k1 = (exists($int_sol_pos_hash->{1}->{$known_motif->[0]}) ?
#		  $solution->[$int_sol_pos_hash->{1}->{$known_motif->[0]}] *
#		  $conversion_factor : 0);
#	my $c2 = (exists($int_sol_pos_hash->{2}->{$calculate_motif->[1]}) ?
#		  $solution->[$int_sol_pos_hash->{2}->{$calculate_motif->[1]}] *
#		  $conversion_factor : 0);
#	my $k2 = (exists($int_sol_pos_hash->{2}->{$known_motif->[1]}) ?
#		  $solution->[$int_sol_pos_hash->{2}->{$known_motif->[1]}] *
#		  $conversion_factor : 0);
#	my $c3 = (exists($int_sol_pos_hash->{3}->{$calculate_motif->[2]}) ?
#		  $solution->[$int_sol_pos_hash->{3}->{$calculate_motif->[2]}] *
#		  $conversion_factor : 0);
#	my $k3 = (exists($int_sol_pos_hash->{3}->{$known_motif->[2]}) ?
#		  $solution->[$int_sol_pos_hash->{3}->{$known_motif->[2]}] *
#		  $conversion_factor : 0);
#
#	$kd += $effect_range * ($c1 - $k1);
#	$kd += $effect_range * ($c2 - $k2);
#	$kd += $effect_range * ($c3 - $k3);

##    debug("Position 1: $calculate_motif->[0]_c vs. $known_motif->[0]_k");
#	$kd += $effect_range *
#	  ($solution->[$int_sol_pos_hash->{1}->{$calculate_motif->[0]}] * .1 -
#	   $solution->[$int_sol_pos_hash->{1}->{$known_motif->[0]}] * .1);
##    debug("Position 2: $calculate_motif->[1]_c vs. $known_motif->[1]_k");
#	$kd += $effect_range *
#	  ($solution->[$int_sol_pos_hash->{2}->{$calculate_motif->[1]}] * .1 -
#	   $solution->[$int_sol_pos_hash->{2}->{$known_motif->[1]}] * .1);
##    debug("Position 3: $calculate_motif->[2]_c vs. $known_motif->[2]_k");
#	$kd += $effect_range *
#	  ($solution->[$int_sol_pos_hash->{3}->{$calculate_motif->[2]}] * .1 -
#	   $solution->[$int_sol_pos_hash->{3}->{$known_motif->[2]}] * .1);
      }

    return($kd);
  }

sub getSolutionExhaustively
  {
    my $cp1s                      = [sort {$a cmp $b} @{$_[0]}];
    my $ips                       = [sort {$a cmp $b} @{$_[1]}];
    my $cp2s                      = [sort {$a cmp $b} @{$_[2]}];
    my $known_kds                 = $_[3];#An array of arrays [[cp1,ip,cp2,kd]]
    my $refine_solution           = $_[4];
    my $refinement_factor         = $_[5];
    my $refine_solution_unaltered = $_[6];
    my $outfile                   = $_[7];
    #globals: $target_stddev, $equation_type, $effect_range

    if(scalar(@$known_kds) < 2)
      {
	error("Not enough data to calculate a solution.");
	return({});
      }

    debug("Called with [@$cp1s], [@$ips], [@$cp2s], and [@$known_kds].");

    #This is not the solution that will be returned, but a simpler
    #representation needed for GetNextIndepCombo.  We are going to assume the
    #pairs are ordered by position and then alphabetical
    my $internal_solution = [];
    my $best_internal_solution = [];
    my @order = (@$cp1s,@$ips,@$cp2s);

    markTime();
    my $cnt = 0;
    my $num_poss = $rand_input**scalar(@order);
    my($ccp1,$cip,$ccp2,$target_kd);
    my($kcp1,$kip,$kcp2,$known_kd);
    my $best_solution    = {};
    my $array_sizes      = [map {$rand_input} @order];
    my $stddev           = 0;
    my($best_stddev);#,$errsum,$num_calcs);

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

    if(defined($refine_solution))
      {
	$best_stddev = getStandardDeviation($refine_solution_unaltered,
					    $known_kds);
	verbose("Overall Starting Standard Deviation: [$best_stddev].");
      }

    while(GetNextIndepCombo($internal_solution,$array_sizes))
      {
	$cnt++;

	$stddev = getInternalStandardDeviation($internal_solution,
					       $int_sol_pos_hash,
					       $known_kds,
					       $refine_solution,
					       $refinement_factor);

	#If we've encountered a better solution
	if(!defined($best_stddev) || $stddev < $best_stddev)
	  {
	    $best_stddev            = $stddev;
	    $best_internal_solution = [@$internal_solution];

	    my $i = 0;

	    if(defined($refine_solution))
	      {
		my $ary = mergeRefinements($refine_solution->{VALUES},
					   $refinement_factor,
					   $best_internal_solution,
					   \@order,
					   $cp1s,
					   $ips,
					   $cp2s);
		verbose("Best Solution [with STD DEV $best_stddev",
			($use_raw_error ? '' : '%'),"]: ",
			join(',',
			     map {my $x=$_;
				  map {"$_:$x->{$_}"}
				    sort {$a cmp $b} keys(%$x)}
			     @$ary));
	      }
	    else
	      {
		$i = 0;
		verbose("Best Solution [with STD DEV $stddev",
			($use_raw_error ? '' : '%'),"]: ",
			join(',',
			     map {$order[$i++] . ":" .
				    ($_ * $conversion_factor)}
			     @{$best_internal_solution}));
	      }

	    $i = 0;
	    reportSolution({VALUES =>
			    [{map {$order[$i++] => $_ * $conversion_factor}
			      @{$best_internal_solution}[0..(scalar(@$cp1s) -
							     1)]},
			     {map {$order[$i++] => $_ * $conversion_factor}
			      @{$best_internal_solution}[scalar(@$cp1s)..
							 (scalar(@$cp1s) +
							  scalar(@$ips) - 1)]},
			     {map {$order[$i++] => $_ * $conversion_factor}
			      @{$best_internal_solution}
			      [(scalar(@$cp1s) + scalar(@$ips))..
			       $#{$best_internal_solution}]}],
			    STDDEV => $best_stddev,
			    EFFECT => $effect_range,
			    TYPE   => $equation_type},
			   $outfile);

	    if(($max_seconds != 0 && markTime(-1) > $max_seconds) ||
	       $best_stddev <= $target_stddev)
	      {
		if($max_seconds != 0 && markTime(-1) > $max_seconds)
		  {verbose("Hit max time")}
		else
		  {verbose("Hit target STDDEV of $target_stddev: ",
			   "[$best_stddev]")}

		last;
	      }
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

    if(defined($refine_solution))
      {
	$best_solution->{VALUES} = mergeRefinements($refine_solution->{VALUES},
						    $refinement_factor,
						    $best_internal_solution,
						    \@order,
						    $cp1s,
						    $ips,
						    $cp2s);
      }
    else
      {
	my $i = 0;

	#$solution->{VALUES} = [{AT => ...},{AA => ...},{AT => ...}]
	$best_solution->{VALUES} =
	  [{map {$order[$i++] => $_ * $conversion_factor}
	    @{$best_internal_solution}[0..(scalar(@$cp1s) - 1)]},
	   {map {$order[$i++] => $_ * $conversion_factor}
	    @{$best_internal_solution}[scalar(@$cp1s)..(scalar(@$cp1s) +
							scalar(@$ips) - 1)]},
	   {map {$order[$i++] => $_ * $conversion_factor}
	    @{$best_internal_solution}[(scalar(@$cp1s) + scalar(@$ips))..
				       $#{$best_internal_solution}]}];
      }

    $best_solution->{STDDEV} = $best_stddev;
    $best_solution->{EFFECT} = $effect_range;
    $best_solution->{TYPE}   = $equation_type;

    return($best_solution);
  }

sub mergeRefinements
  {
    my $refine_val_ary     = $_[0];
    my $refinement_factor  = $_[1];
    my $internal_solution  = $_[2];
    my $order              = $_[3];
    my $cp1s               = $_[4];
    my $ips                = $_[5];
    my $cp2s               = $_[6];
    my $real_solution_vals = {};

    my $i = 0;

    #[{AT => ...},{AA => ...},{AT => ...}]
    $real_solution_vals =
      [{map {my $j = $i++;$order->[$j] => $refine_val_ary->[0]->{$order->[$j]} +
	       ($_ * $refinement_factor)}
	@{$internal_solution}[0..(scalar(@$cp1s) - 1)]},
       {map {my $j = $i++;$order->[$j] => $refine_val_ary->[1]->{$order->[$j]} +
	       ($_ * $refinement_factor)}
	@{$internal_solution}[scalar(@$cp1s)..(scalar(@$cp1s) + scalar(@$ips) -
					       1)]},
       {map {my $j = $i++;$order->[$j] => $refine_val_ary->[2]->{$order->[$j]} +
	       ($_ * $refinement_factor)}
	@{$internal_solution}[(scalar(@$cp1s) + scalar(@$ips))..
			      $#{$internal_solution}]}];

    return($real_solution_vals);
  }

sub getSolutionUsingGA
  {
    my $cp1s                      = [sort {$a cmp $b} @{$_[0]}];
    my $ips                       = [sort {$a cmp $b} @{$_[1]}];
    my $cp2s                      = [sort {$a cmp $b} @{$_[2]}];
    my $known_kds                 = $_[3];#An array of arrays [[cp1,ip,cp2,kd]]
    my $refine_solution           = $_[4];
    my $refinement_factor         = $_[5];
    my $refine_solution_unaltered = $_[6];
    my $outfile                   = $_[7];
    #globals: $pop_size, $mutation_rate, $crossover_rate, $crossover_amount,
    #         $crossover_cutoff, $max_seconds, $target_stddev, $fitness_factor

    my $target_fitness = ($target_stddev == 0 ?
			  0 : 1/$target_stddev);#exp($fitness_factor/$target_stddev));

    debug("TARGET FITNESS: $target_fitness");

    if(scalar(@$known_kds) < 2)
      {
	error("Not enough data to calculate a solution.");
	return({});
      }

    debug("Called with [@$cp1s], [@$ips], [@$cp2s], and a database of [",
	  scalar(@$known_kds),"] loops.");

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

    my($best_fitness);
    if(defined($refine_solution))
      {
	my $best_stddev = getStandardDeviation($refine_solution_unaltered,
					       $known_kds);
	$best_fitness = 1/$best_stddev;#exp($fitness_factor*(1/$best_stddev));
	verbose("Overall Starting Standard Deviation: [$best_stddev",
		($use_raw_error ? '' : '%'),"]:");
	verbose(reportSolution($refine_solution)) if($DEBUG);
	verbose(reportSolution($refine_solution_unaltered)) if($DEBUG);
      }

    ##
    ##PRELIMINARY DESIGN
    ##
    #Create initial population randomly
    #Mark the time
    #While running time < max_seconds and best stddev > target stddev
    #  For each solution in the population
    #    Assign solution fitness exp($fitness_factor*(1/stddev))
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

    debug('First Random Internal Solution: [',
	  join(',',@{$next_generation->[0]}),']');

    #Mark the time
    markTime();
    #While running time < max_seconds and best fitness < target fitness
    my(@fitnesses,$best_internal_solution,$rand1,$rand2,$sum,$j,
       $mom,$dad,@new_solutions,$population,$total_fitness);
    my $generation_num = 0;
    while(!defined($best_fitness) || $target_fitness == 0 ||
	  $best_fitness < $target_fitness)
      {
	verboseOverMe("Generation ",++$generation_num,".  Assessing fitness.");

	$population = [@$next_generation];
	$next_generation = [];
	@fitnesses = ();
	$total_fitness = 0;
	#For each solution in the population
	foreach my $internal_solution (@$population)
	  {
	    #Assign solution fitness exp($fitness_factor*(1/stddev))
	    push(@fitnesses,
		 (1/
		 #exp($fitness_factor/
		     getInternalStandardDeviation($internal_solution,
						  $int_sol_pos_hash,
						  $known_kds,
						  $refine_solution,
						  $refinement_factor)));
	    $total_fitness += $fitnesses[-1];

	    debug("FITNESS(",#exp($fitness_factor/STDDEV)
		  "1/STDDEV",
		  "): $fitnesses[-1]");

	    #If fitness is better than the best or the best is not yet assigned
	    if(!defined($best_fitness) || $fitnesses[-1] > $best_fitness)
	      {
		#Save the best solution
		$best_internal_solution = [@$internal_solution];
		$best_fitness = $fitnesses[-1];

		my $best_stddev = 1/$best_fitness;#$fitness_factor/log($best_fitness);

		my $i = 0;

		if(defined($refine_solution))
		  {
		    my $ary = mergeRefinements($refine_solution->{VALUES},
					       $refinement_factor,
					       $best_internal_solution,
					       \@order,
					       $cp1s,
					       $ips,
					       $cp2s);
		    verbose("Best Solution [with STD DEV $best_stddev",
			    ($use_raw_error ? '' : '%'),"]: ",
			    join(',',
				 map {my $x=$_;
				      map {"$_:$x->{$_}"}
					sort {$a cmp $b} keys(%$x)}
				 @$ary));
		  }
		else
		  {
		    $i = 0;
		    verbose("Best Solution [with STD DEV $best_stddev",
			    ($use_raw_error ? '' : '%'),"]: ",
			    join(',',
				 map {$order[$i++] . ":" .
					($_ * $conversion_factor)}
				 @$best_internal_solution));
		  }

		$i = 0;
		reportSolution({VALUES =>
				[{map {$order[$i++] => $_ * $conversion_factor}
				  @{$best_internal_solution}[0..(scalar(@$cp1s)
								 - 1)]},
				 {map {$order[$i++] => $_ * $conversion_factor}
				  @{$best_internal_solution}[scalar(@$cp1s)..
							     (scalar(@$cp1s) +
							      scalar(@$ips) -
							      1)]},
				 {map {$order[$i++] => $_ * $conversion_factor}
				  @{$best_internal_solution}
				  [(scalar(@$cp1s) + scalar(@$ips))..
				   $#{$best_internal_solution}]}],
				STDDEV => $best_stddev,
				EFFECT => $effect_range,
				TYPE   => $equation_type},
			       $outfile);

		last if(($max_seconds != 0 && markTime(-1) > $max_seconds) ||
			($target_fitness != 0 &&
			 $best_fitness > $target_fitness));
	      }

	    last if(($max_seconds != 0 && markTime(-1) > $max_seconds) ||
		    ($target_fitness != 0 && $best_fitness > $target_fitness));
	  }

	debug("Total Fitness: [$total_fitness]  Average Fitness: [",
	      $total_fitness / scalar(@fitnesses),"].");

	if(($max_seconds != 0 && markTime(-1) > $max_seconds) ||
	   ($target_fitness != 0 && $best_fitness > $target_fitness))
	  {
	    if($max_seconds != 0 && markTime(-1) > $max_seconds)
	      {verbose("Hit max time")}
	    else
	      {verbose("Hit target fitness of $target_fitness: ",
		       "[$best_fitness]")}

	    last;
	  }

	verboseOverMe("Generation $generation_num.  Beginning Natural ",
		      "Selection & Mutations.");

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

	verbose("Generation $generation_num.  Done.");
      }

    #Convert the internal solution to a "Real solution" so we can return it
    my $best_solution = {};
    if(defined($refine_solution))
      {
	$best_solution->{VALUES} = mergeRefinements($refine_solution->{VALUES},
						    $refinement_factor,
						    $best_internal_solution,
						    \@order,
						    $cp1s,
						    $ips,
						    $cp2s);
      }
    else
      {
	my $i = 0;
	#$solution->{VALUES} = [{AT => ...},{AA => ...},{AT => ...}]
	debug("Last element of best internal solution: ",
	      $#{$best_internal_solution}," = ",
	      $best_internal_solution->[$#{$best_internal_solution}]);
	$best_solution->{VALUES} =
	  [{map {$order[$i++] => $_ * $conversion_factor}
	    @{$best_internal_solution}[0..(scalar(@$cp1s) - 1)]},
	   {map {$order[$i++] => $_ * $conversion_factor}
	    @{$best_internal_solution}[scalar(@$cp1s)..(scalar(@$cp1s) +
							scalar(@$ips) - 1)]},
	   {map {$order[$i++] => $_ * $conversion_factor}
	    @{$best_internal_solution}[(scalar(@$cp1s) + scalar(@$ips))..
				       $#{$best_internal_solution}]}];
      }

    $best_solution->{STDDEV} = 1/$best_fitness;#$fitness_factor/(log($best_fitness));
    $best_solution->{EFFECT} = $effect_range;
    $best_solution->{TYPE}   = $equation_type;

    return($best_solution);
  }

#Takes internal solutions (array references) and mutates the values contained
#based on the mutation rate.  Returns the *same* array references.  Note, this
#changes the values set in main.  This is OK for the intended use because
#crossover will be called first and it creates new arrays.
sub pointMutate
  {
    my $solutions = [@_];
    #global: $mutation_rate, $rand_input

    #Note, this does not need to change to accommodate the refining solution
    #method because the internal solution is simply an integer between 0 and 10.
    #We are essentially changing this number times the refinement factor when
    #refining an existing solution.
    foreach my $solution (@$solutions)
      {foreach my $index (0..$#{$solution})
	 {if(rand() <= $mutation_rate)
	    {
#	      debug("Point Mutating.");
	      $solution->[$index] = int(rand($rand_input));
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
	    #Note, if we are refining a solution, multiplying by
	    #$conversion_factor here is OK because the internal solution
	    #supplied consists of integers from 0 to $rand_input.  This means
	    #that the crossover cutoff will be applied to the refined solution
	    #based on the refinement factor instead of the actual values in the
	    #refining solution.  This is what we want.
	    if(($daughter_solution->[$position] * $conversion_factor >=
		$crossover_cutoff ||
		$son_solution->[$position] * $conversion_factor >=
		$crossover_cutoff) &&
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
    #Note, this does not need to change to accommodate the refining solution
    #method because the internal solution is simply an integer between 0 and 10.
    foreach(1..$size)
      {push(@$internal_solution,int(rand($rand_input)))}
    return($internal_solution);
  }

sub getInternalStandardDeviation
  {
    my $internal_solution = $_[0];
    my $int_sol_pos_hash  = $_[1];
    my $known_kds         = $_[2]; #An array of arrays: [[cp1,ip,cp2,kd],,,]
    my $refine_solution   = $_[3];
    my $refinement_factor = $_[4];

    my $errsum    = 0;
    my $num_calcs = 0;
    my($err);

    foreach my $calculate_kd_array (@$known_kds)
      {
	debug("KD: $calculate_kd_array->[3]");
	debug("WEIGHTED KD: ",weightKd($calculate_kd_array->[3]));

	foreach my $known_kd_array (@$known_kds)
	  {
	    next if($known_kd_array eq $calculate_kd_array);
	    $num_calcs++;
	    my $pred_kd =
	      internalCalculateKd($internal_solution,
				  $int_sol_pos_hash,
				  $calculate_kd_array,
				  $known_kd_array,
				  $refine_solution,
				  $refinement_factor);
	    $err = $calculate_kd_array->[3] - $pred_kd;

	    debug("PREDICTED KD: $pred_kd\nDIFFERENCE: $err");

	    unless($use_raw_error)
	      {
		debug("PERCENT DIFFERENCE: ",100*$err/$calculate_kd_array->[3],
		      '%');

		#Convert the error to a percentage of the known Kd value
		if($unweighted_kd_mode)
		  {
		    #By first dividing by the known Kd
		    $err /= $calculate_kd_array->[3];
		  }
		else
		  {
		    #By first dividing by the weighted known Kd
		    $err /= weightKd($calculate_kd_array->[3]);
		  }

		#Then by multiplying by 100;
		$err *= 100;

		debug("WEIGHTED PERCENT DIFFERENCE: $err\%");
	      }

	    debug("ERROR SQUARED: ",$err**2);

	    $errsum += $err**2;
	  }

	debug("RUNNING ERROR SUM FOR KD($calculate_kd_array->[3]): $errsum");
      }

    debug("OVERALL STDDEV (sqrt($errsum / $num_calcs)): ",
	  sqrt($errsum / $num_calcs));

    return(sqrt($errsum / $num_calcs));
  }

sub getStandardDeviation
  {
    my $solution   = $_[0];
    my $known_kds  = $_[1]; #An array of arrays: [[cp1,ip,cp2,kd],,,]
    my $calc_array = $_[2]; #OPTIONAL - calculates STDDEV of whole solution if
                            #           not supplied

    my $errsum    = 0;
    my $num_calcs = 0;
    my($err);
    #globals: $unweighted_kd_mode

    foreach my $calculate_kd_array (defined($calc_array) ?
				    $calc_array : @$known_kds)
      {
	foreach my $known_kd_array (@$known_kds)
	  {
	    next if($known_kd_array eq $calculate_kd_array);
	    $num_calcs++;
	    $err = $calculate_kd_array->[3] -
	      calculateKd($solution,
			  $calculate_kd_array,
			  $known_kd_array,
			  $known_kd_array->[3]);

	    unless($use_raw_error)
	      {
		#Convert the error to a percentage of the known Kd value
		if($unweighted_kd_mode)
		  {
		    #By first dividing by the known Kd
		    $err /= $calculate_kd_array->[3];
		  }
		else
		  {
		    #By first dividing by the weighted known Kd
		    $err /= weightKd($calculate_kd_array->[3]);
		  }

		#Then by multiplying by 100;
		$err *= 100;
	      }

	    $errsum += $err**2;
	  }
      }

    return(sqrt($errsum / $num_calcs));
  }

sub weightKd
  {
    my $kd = $_[0];
    #globals: $weight_kd_c,$weight_kd_x,$weight_kd_xsquared,$weight_kd_xcubed
    return($weight_kd_c +
	   $weight_kd_x * $kd +
	   $weight_kd_xsquared * $kd**2 +
	   $weight_kd_xcubed * $kd**3);
  }

sub copySolution
  {
    my $solution = $_[0];
    my $copy = {VALUES => [map {my $x = {%$_};$x} @{$solution->{VALUES}}],
		STDDEV => $solution->{STDDEV}};
    if(exists($solution->{EFFECT}))
      {$copy->{EFFECT} = $solution->{EFFECT}}
    if(exists($solution->{TYPE}))
      {$copy->{TYPE} = $solution->{TYPE}}
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


* OUTPUT FORMAT: Regular mode example (without using -v):

Effect Range: 472
Solution Standard Deviation: 15.5409137440499
	Position 1:
		AU	1
		UA	0.8
		GC	0.7
		CG	
		GU	
		UG	
	Position 2:
		AG	
		GA	
		AC	
		CA	0.8
		AA	
		GG	
		CC	
		CU	
		UC	
		UU	
	Position 3:
		AU	
		UA	
		GC	0.6
		CG	0.2
		GU	
		UG	0.1

                 The lines without numbers represent under-representation of the
                 input data.  If a pair is not represented in a position, an
                 optimized value cannot be assigned to it.  These factors are
                 assumed to be 0 when optimizing.

                 With the cross-validate option, multiple solutions are output along with a message of standard deviation of the calculations for the loop left out:

Best Solution 1:
Effect Range: 472
Solution Standard Deviation: 67.076514694261
        Position 1:
                AU      0.9
                UA      0.7
                GC      0.9
                CG      0.9
                GU      0.9
                UG      0.8
        Position 2:
                AG      
                GA      
                AC      
                CA      0.7
                AA      
                GG      
                CC      
                CU      
                UC      
                UU      
        Position 3:
                AU      0.9
                UA      0
                GC      0.2
                CG      0.1
                GU      0.3
                UG      0
Cross Validation Result: Within predicted standard error: Predicted standard error: 67.076514694261.  Withheld [UA,CA,CG] with a known Kd of 15 and resulted in an average calculated Kd that has a standard deviation of [47.8650185417284].
Best Solution 2:
Effect Range: 472
Solution Standard Deviation: 65.4860020965415
        Position 1:
                AU      0.6
                UA      0.4
                GC      0.6
...

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

-- BASIC OPTIONS --

     -i|--input-file*     REQUIRED Space-separated input file(s inside quotes).
                                   Standard input via redirection is
                                   acceptable.  Perl glob characters (e.g. '*')
                                   are acceptable inside quotes (e.g.
                                   -i "*.txt *.text").  See --help for a
                                   description of the input file format.
                                   *No flag required.
     -q|--equation-type   OPTIONAL [0] Values can be 'additive' ('cumulative' or
                                   '0' will work for this too) or
                                   'multiplicative' ('1' will work for this as
                                   well).  The first additive option adds the
                                   effect range multiplied by the difference
                                   between the optimized factors (factors are
                                   values between [0 and 1], inclusive).  The
                                   factor for the base pair in the loop with
                                   known Kd is subtracted from the factor for
                                   the base pair in the loop whose Kd is being
                                   predicted and the result is multiplied by the
                                   effect range.  This is done for each position
                                   and added to the Kd of the loop with known
                                   Kd.  For example:

                                   (0) KDp = KDk
                                              + E * (Fp1 - Fk1)
                                              + E * (Fp2 - Fk2)
                                              + E * (Fp3 - Fk3)

                                   KDp - Predicted Kd
                                   KDk - Known Kd
                                   E   - Effect Range
                                   Fp# - Factor for the base pair at position #
                                         in the loop whose Kd is being predicted
                                   Fk# - Factor for the base pair at position #
                                         in the loop whose Kd is known

                                   The multiplicative equation multiplies the
                                   known Kd by a fraction for each base pair in
                                   the loop.  The numerator of each fraction is
                                   the (effect range minus one) times the factor
                                   for the base pair in the loop being predicted
                                   (factors are values between [0 and 1],
                                   inclusive) plus one.  The denominator is the
                                   same, except it's for the known loop.  This
                                   results in a max factor being the effect
                                   range and the smallest factor being
                                   1/effect-range.  For example:

                                   (1) KDp = KDk
                                              * (((E - 1) * Fp1 + 1) /
                                                 ((E - 1) * Fk1 + 1))
                                              * (((E - 1) * Fp2 + 1) /
                                                 ((E - 1) * Fk2 + 1))
                                              * (((E - 1) * Fp3 + 1) /
                                                 ((E - 1) * Fk3 + 1))

                                   KDp - Predicted Kd
                                   KDk - Known Kd
                                   E   - Effect Range
                                   Fp# - Factor for the base pair at position #
                                         in the loop whose Kd is being predicted
                                   Fk# - Factor for the base pair at position #
                                         in the loop whose Kd is known

                                   See --effect-range for the difference in the
                                   way it is used based on --equation-type.
                                   Cannot be used with the --refine-solution
                                   option because the equation type is embedded
                                   in each factor file.
     -r|--effect-range    OPTIONAL [500* with '-q 0' or 15* with '-q 1'] When
                                   --equation-type is 0, the default effect
                                   range is calculated as the maximum difference
                                   in Kd observed when loops differ by only one
                                   base pair (including one closing base pair on
                                   each end).  When --equation-type is 1, the
                                   default effect range is calculated as the
                                   maximum Kd fraction for loops which differ by
                                   only one base pair.  *If there are no loops
                                   that differ by one base pair, the default
                                   value indicated is used.  Cannot be used with
                                   the --refine-solution option because the
                                   effect range is embedded in each factor file.
                                   Note, the largest effect range between loops
                                   which differ by one base pair is
                                   automatically calculated as described above
                                   and then 20% is added (to account for
                                   incompleteness of the data).  If there are
                                   very few input Kds, it is recommended you
                                   supply a value using this option, especially
                                   when comparing results from different sets
                                   constructed from the same pool for cross-
                                   validation purposes.
     -v|--cross-validate  OPTIONAL [Off] For each loop in the input file,
                                   calculate the optimized equation based on
                                   the rest of the data, then evaluate whether
                                   the witheld data falls within the calculated
                                   standard deviation.  Cannot be used with the
                                   -f option.
     -g|--use-genetic-    OPTIONAL [Off] Search for a solution using a genetic
        algorithm                  algorithm heuristic.  This strategy will
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

-- RUNNING TIME OPTIONS --

     -s|--max-seconds     OPTIONAL [0] The amount of time to spend running and
                                   optimizing the solution.  Note, when used
                                   with the -v option, this time applies to
                                   each of the cross-validation steps, which is
                                   the same as the number of loops in the
                                   supplied file.  A value of 0 means that the
                                   script will run indefinitely until the
                                   --target-stddev is reached.
     -t|--target-stddev   OPTIONAL [0] If a solution is found with an average
                                   standard deviation at or below this
                                   threshold, the program will stop.  Note that
                                   this value is a percentage standard
                                   deviation of the Kd (or weighted Kd unless
                                   -u is supplied).  If you would like a target
                                   standard deviation in raw Kd, then you must
                                   use -e, but note that using that option will
                                   not focus effort on binders, but rather find
                                   the best solution for all data with the same
                                   std-dev.

-- ACCURACY OPTIONS --

     -f|--refine-solution OPTIONAL [nothing] Supply a perviously output
                                   solution file in the format of the output of
                                   this script (See OUTPUT FORMAT in --help).
                                   The algorithm will add a decimal place to
                                   the supplied solution to refine it by a
                                   decimal place.  The smallest decimal place
                                   present in the supplied solution file is
                                   used for all the contained factors.  Factors
                                   are adjusted up or down by half of the next
                                   decimal place present.  For example, if your
                                   current factors are in increments of tenths,
                                   then the refined solution will add facotrs
                                   ranging from -0.05 to 0.05 (inclusive).
                                   Factors will never go below zero or above 1.
                                   This option cannot be used with the -v or -r
                                   options.
     -l|--precision-level OPTIONAL [1] An integer greater than 0 that affects
                                   the number of decimal places in the solution
                                   factors.  Increasing this number is not
                                   advisable.  You should add precision by
                                   using -f, but if on the first pass, you see
                                   very large standard deviations and an effect
                                   range that is very large and the increment
                                   between known Kd's is very small, you might
                                   try incrementing the precision level *on the
                                   first pass only*, not on refining solutions.
                                   Note that this will increase the search
                                   space, so if you increase the precision
                                   level, you should also increase the
                                   population size (-p) and max seconds (-s).
                                   This parameter is only used if -g is
                                   supplied.
     -e|--use-raw-error   OPTIONAL [Off] Default behavior is to measure error
                                   by percentage.  For example, if the
                                   predicted Kd is 300 and the actual value is
                                   400, it is off by 25%.  Also, if the
                                   predicted is 30 and the actual is 40, the
                                   error is again 25% even though the
                                   difference is 10 versus 100.  By supplying
                                   -e, you would be measuring error by the raw
                                   difference in values (100 versus 10) instead
                                   of by percentage (25% versus 25%).  So,
                                   using the default behavior instead causes
                                   solutions to be more accurate for lower
                                   Kd's.
     -u|--use-unweighted- OPTIONAL [Off] Divide the error of predicted Kd's by
        kd                         the actual known unweighted Kd and measure
                                   standard deviation of the resulting percent
                                   value.  E.g. A predicted Kd of 10 for an
                                   actual Kd of 100 will result in an error
                                   value of 10%.  If this option is not
                                   supplied, then the actual known Kd value
                                   will be weighted by a polynomial which
                                   promotes accuracy for smaller Kd and relaxes
                                   accuracy for larger Kd's.  See
                                   --kd-weight-const, --kd-weight-x-fact, and
                                   --kd-weight-x-sq-fact.
     -a|--kd-weight-ax3   OPTIONAL [0.00025] The factor (a) in the Kd weighting
                                   equation: kd_weighted = aKd^3 + b*Kd^2 +
                                   c*Kd + d.  See -u for an explanation of the
                                   effect of weighting the Kd.
     -b|--kd-weight-bx2   OPTIONAL [0.005] The factor (b) in the Kd weighting
                                   equation: kd_weighted = aKd^3 + b*Kd^2 +
                                   c*Kd + d.  See -u for an explanation of the
                                   effect of weighting the Kd.
     -c|--kd-weight-cx    OPTIONAL [1.5] The factor (c) in the Kd weighting
                                   equation: kd_weighted = aKd^3 + b*Kd^2 +
                                   c*Kd + d.  See -u for an explanation of the
                                   effect of weighting the Kd.
     -d|--kd-weight-d     OPTIONAL [200] The constant (d) in the Kd weighting
                                   equation: kd_weighted = aKd^3 + b*Kd^2 +
                                   c*Kd + d.  See -u for an explanation of the
                                   effect of weighting the Kd.

-- GENETIC ALGORITHM OPTIONS --

     -p|--population-size OPTIONAL [10000] The number of solutions generated
                                   at each generation.  Only used when the -g
                                   flag is supplied.
     -m|--mutation-rate   OPTIONAL [0.005] This is a value between 0 and 1
                                   (exclusive) that represents the chance that
                                   each individual importance factor will be
                                   changed to a different randomly selected
                                   value.  Only used when the -g flag is
                                   supplied.
     -x|--crossover-rate  OPTIONAL [0.7] This is a value between 0 and 1
                                   (exclusive) that represents the chance that
                                   two solutions will swap a set of factors for
                                   one position in the loop.  The set swapped
                                   is determined by -k and -a (see those
                                   options below).  Only used when the -g flag
                                   is supplied.
     --crossover-cutoff   OPTIONAL [0.7] Advanced option - probably should
                                   leave the default.  This is a value between
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
     --crossover-amount   OPTIONAL [0.5] Advanced option - probably should
                                   leave the default.  This is a value between
                                   0 and 1 (exclusive).  It determines the
                                   chance an importance factor above the cutoff
                                   (supplied via -a) will be swapped between
                                   two solutions selected by natural selection.
                                   Only used when the -g flag is supplied.

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
