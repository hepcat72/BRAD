#!/usr/bin/perl -w

#Generated using perl_script_template.pl 1.38
#Robert W. Leach
#rwleach@ccr.buffalo.edu
#Center for Computational Research
#Copyright 2008

#These variables (in main) are used by getVersion() and usage()
my $software_version_number = '1.1';
my $created_on_date         = '9/17/2009';

##
## Start Main
##

use strict;
use Getopt::Long;

#Declare & initialize variables.  Provide default values here.
my($outfile_suffix); #Not defined so a user can overwrite the input file
my @input_files         = ();
my @known_files         = ();
my @calc_files          = ();
my $current_output_file = '';
my $help                = 0;
my $version             = 0;
my $overwrite           = 0;
my $noheader            = 0;
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
  {'f|factor-file=s'       => sub {push(@input_files,   #REQUIRED unless <> is
					sglob($_[1]))}, #         supplied
   '<>'                    => sub {push(@input_files,   #REQUIRED unless -f is
					sglob($_[0]))}, #         supplied
   'k|known-kd-file=s'     => sub {push(@known_files,   #REQUIRED
					sglob($_[1]))},
   'c|calculate-kd-file=s' => sub {push(@calc_files,    #REQUIRED
					sglob($_[1]))},
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
    quit(-1);
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
    quit(-2);
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
    error('No factor files (-f) detected.');
    usage(1);
    quit(-3);
  }
elsif(scalar(@known_files) == 0)
  {
    error('No known Kd files (-k) detected.');
    usage(1);
    quit(-4);
  }
elsif(scalar(@calc_files) == 0)
  {
    error('No calculate Kd files (-c) detected.');
    usage(1);
    quit(-5);
  }

#There must be 1 or scalar(@known_kd) factor files or 1 known kd file (to avoid
#mistakes)
if(scalar(@input_files) != 1 &&
   scalar(@input_files) != scalar(@known_files) &&
   scalar(@known_files)  != 1)
  {
    error('You must enter either 1 factor file (-f) with multiple known Kd ',
	  'files, 1 known Kd file (-k) with multiple factor files, or an ',
	  'equal number of both.  This is to keep things simple so no ',
	  'mistakes are made.  If you enter 1 known Kd or 1 factor file, ',
	  'that file will be used in all the calculations.  If you use an ',
	  'equal number of both, the factor and known Kd files will only be ',
	  'used together in order.  For example, the first known Kd file ',
	  'will be used with the first factor file, the second with the ',
	  'second, and so on.  This is because factors are developed using ',
	  'one set of known Kds and it only makes sense to calculate other ',
	  'Kds using the known Kds that were used to develop the factors.  ',
	  'Note, the order of the files is important.');
    usage(1);
    quit(-6);
  }

#There must be 1 or scalar(@known_kd) factor files or 1 known kd file (to avoid
#mistakes)
if(scalar(@calc_files)  != 1 &&
   scalar(@input_files) != scalar(@calc_files) &&
   scalar(@known_files) != scalar(@calc_files))
  {
    error('You must enter either 1 calculate Kd file (-c) or the same number ',
	  'as either factor files or known Kd files.');
    usage(1);
    quit(-6);
  }

#Check to make sure previously generated output files won't be over-written
#Note, this does not account for output redirected on the command line
if(!$overwrite && defined($outfile_suffix))
  {
    my $existing_outfiles = [];
    foreach my $output_file (map {($_ eq '-' ? 'STDIN' : $_) . $outfile_suffix}
			     @calc_files)
      {push(@$existing_outfiles,$output_file) if(-e $output_file)}

    if(scalar(@$existing_outfiles))
      {
	error("The output files: [@$existing_outfiles] already exist.  ",
	      'Use --overwrite to force an overwrite of existing files.  ',
	      "E.g.:\n",getCommand(1),' --overwrite');
	quit(-4);
      }
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

#Read in all the files
my(@solutions);
foreach my $file (@input_files)
  {push(@solutions,getFactorHash($file))}
my(@known_kd_sets);
foreach my $file (@known_files)
  {push(@known_kd_sets,getKds($file))}
my(@calc_kd_sets);
foreach my $file (@calc_files)
  {push(@calc_kd_sets,getKds($file))}

#Determine the number of times to iterate (the largest number of files)
my $largest = (scalar(@solutions) < scalar(@known_kd_sets) ?
	       (scalar(@known_kd_sets) < scalar(@calc_kd_sets) ?
		scalar(@calc_kd_sets) : scalar(@known_kd_sets)) :
	       (scalar(@solutions) < scalar(@calc_kd_sets) ?
		scalar(@calc_kd_sets) : scalar(@solutions)));
my $db_size = {};

#For each input file
for(my $i = 0;$i < $largest;$i++)
  {
    my $calc_file   = (scalar(@calc_files) == 1 ?
		       $calc_files[0] : $calc_files[$i]);
    my $factor_file = (scalar(@input_files) == 1 ?
		       $input_files[0] : $input_files[$i]);
    my $known_file  = (scalar(@known_files) == 1 ?
		       $known_files[0] : $known_files[$i]);

    my $calc_kds    = $calc_kd_sets[$i];
    if(scalar(@$calc_kds) == 0)
      {
	error("Unable to calculate file [$calc_file] because nothing could ",
	      "be parsed from it.");
	next;
      }

    my $known_kds = (scalar(@known_kd_sets) == 1 ?
		     $known_kd_sets[0] : $known_kd_sets[$i]);
    if(scalar(@$known_kds) == 0)
      {
	error("Unable to calculate file [$calc_file] because the associated ",
	      "known Kd file [$known_file] appeared to either have nothing ",
	      "in it or it could not be parsed.");
	next;
      }
    $db_size->{scalar(@$known_kds)}->{ERRSUM} = 0
      unless(exists($db_size->{scalar(@$known_kds)}->{ERRSUM}));
    $db_size->{scalar(@$known_kds)}->{CNT}    = 0
      unless(exists($db_size->{scalar(@$known_kds)}->{CNT}));

    my $solution = (scalar(@solutions) == 1 ?
		    $solutions[0] : $solutions[$i]);
    if(scalar(keys(%$solution)) == 0)
      {
	error("Unable to calculate file [$calc_file] because the associated ",
	      "factor file [$factor_file] appeared to either have nothing in ",
	      "it or it could not be parsed.");
	next;
      }

    #If an output file name suffix has been defined
    if(defined($outfile_suffix))
      {
	##
	## Open and select the next output file
	##

	#Set the current output file name
	$current_output_file = ($calc_file eq '-' ? 'STDIN' : $calc_file)
	  . $outfile_suffix;

	#Open the output file
	if(!open(OUTPUT,(scalar(@calc_files) == 1 && $i > 0 ?
			 ">>$current_output_file" : ">$current_output_file")))
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
	if(scalar(@calc_files) != 1 || $i == 0)
	  {
	    print('#',getVersion(),"\n",
		  '#',scalar(localtime($^T)),"\n",
		  '#',getCommand(1),"\n") unless($noheader);
	  }
      }

    #Calculate the various Kd's, the average Kd, the standard deviation for a
    #particular loop being calculated and the overall standard deviation

    my $total_errsum = 0;
    my $missing_kds  = 0;
    my $totcnt       = 0;

    print("EQUATION FACTORS: [",
	  join('][',
	       map {my $h = $_;join(',',map {"$_:$h->{$_}"} keys(%$h))}
	       @{$solution->{VALUES}}),
	  "]\n");
    print("TRAINING DB STANDARD DEVIATION: $solution->{STDDEV}\n");
    print("EQUATION TYPE: $solution->{TYPE}\n") if(exists($solution->{TYPE}));
    print("EFFECT RANGE: $solution->{EFFECT}\n\n");

    foreach my $calc_motif (@$calc_kds)
      {
	print("\t",join(',',@{$calc_motif}[0..2]),"\n\n\t\tCALCULATED KDS:\n");

	my($ccp1,$cip,$ccp2,$target_kd);
	($ccp1,$cip,$ccp2,$target_kd) = @$calc_motif;
	if(!defined($target_kd) || $target_kd eq '')
	  {
	    $target_kd   = 0;
	    $missing_kds = 1;
	  }
	my $errsum = 0;
	my $kd_sum = 0;
	my @kds    = ();
	my $cnt    = 0;

	foreach my $motif_array (@$known_kds)
	  {
	    my($kcp1,$kip,$kcp2,$known_kd);
	    ($kcp1,$kip,$kcp2,$known_kd) = @$motif_array;

	    next if($kcp1 eq $ccp1 && $kip eq $cip && $kcp2 eq $ccp2);

	    if(!defined($known_kd) || $known_kd eq '')
	      {
		error("The known Kd file [$known_file] was missing a Kd for ",
		      "loop: [$kcp1,$kip,$kcp2].  Skipping this loop.");
		next;
	      }
	    push(@kds,calculateKd($solution,
				  [$ccp1,$cip,$ccp2],
				  [$kcp1,$kip,$kcp2],
				  $known_kd));
	    $kd_sum += $kds[-1];
	    $errsum += ($target_kd - $kds[-1])**2 unless($target_kd == 0);
	    $cnt++;

	    print("\t\t\t",sigdec($kds[-1],1),"\t(FROM SEED LOOP: ",
		  join(',',@$motif_array),")\n");
	  }

	if(scalar(@kds) == 0)
	  {
	    error("No calculations could be made for loop [$ccp1,$cip,$ccp2] ",
		  "in calculate kd file: [$calc_file] using loops from known ",
		  "kd file [$known_file] and the factors from file ",
		  "[$factor_file].  Data is either invalid or missing.");
	    next;
	  }

	$total_errsum += $errsum unless($target_kd == 0);
	$totcnt += $cnt;

	my $stddev = 0;
	$stddev = sqrt($errsum / $cnt) unless($target_kd == 0);
	my $kd_ave = $kd_sum / $cnt;

	print("\n\t\t\tAVE\tKNOWN",
	      ($target_kd == 0 ? '' : "\tSTDDEV"),"\n");
	print("\t\t\t",sigdec($kd_ave,1),"\t$calc_motif->[3]",
	      ($target_kd == 0 ? '' : "\t" . sigdec($stddev,1)),"\n\n");
      }

    my $total_stddev = 0;
    $total_stddev = sqrt($total_errsum / $totcnt) unless($missing_kds);

    $db_size->{scalar(@$known_kds)}->{ERRSUM} += $total_errsum;
    $db_size->{scalar(@$known_kds)}->{CNT}    += $totcnt;

    print("OVERALL STANDARD DEVIATION: ",sigdec($total_stddev,1),"\n\n")
      unless($missing_kds);

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

print("#DBSIZE\tSTANDARD DEVIATION\n") if(scalar(keys(%$db_size)));
foreach my $size (sort {$a <=> $b} keys(%$db_size))
  {
    if($db_size->{$size}->{CNT})
      {
	print("$size\t",
	      sqrt($db_size->{$size}->{ERRSUM} / $db_size->{$size}->{CNT}),
	      "\n");
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






























##
## Subroutines
##

sub sigdec
  {
    my $num = $_[0];
    my $num_decimals = $_[1];

    return($num) unless($num =~ /\.\d/);

    if($num_decimals == 0)
      {
	if($num =~ /(\d+)\.[5-9]/)
	  {$num = $1 + 1}
	elsif($num =~ /\.[5-9]/)
	  {$num = 1}
	elsif($num =~ /^(\d+)/)
	  {$num = $1}
      }
    elsif($num =~ /\.(\d{$num_decimals})(\d+)/)
      {
	my $dec = $1;
	my $rem = $2;
        if($rem =~ /^[5-9]/)
	  {$dec += 1}
	if($dec =~ /10+/)
	  {
	    $num = int($num) + 1;
	    $num .= '.' . 0 x $num_decimals;
	  }
	else
	  {$num = int($num) . '.' . $dec}
      }

    return($num);
  }

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
      {
	error("Solution contains no effect range.");
	return({});
      }
    if(!exists($solution->{TYPE}))
      {$solution->{TYPE} = 0}

    if($solution->{STDDEV} !~ /^(\d+\.?\d*|\d*\.\d+(e-?\d+)?)\%?$/i)
      {warning("Invalid standard deviation found in file [$input_file]: ",
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

sub getFactorHashOld
  {
    my $input_file = $_[0];

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
	    $solution->{STDDEV} =~ s/\%$//;
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

    if(scalar(keys(%$solution)) != 3)
      {
	error("Invalid or no solution parsed from file [$input_file].  ",
	      "Skipping.");
	return({});
      }

    if($solution->{STDDEV} !~ /^(\d+\.?\d*|\d*\.\d+(e-?\d+)?)$/)
      {warning("Invalid standard deviation found in file [$input_file]: ",
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
		"[$input_file]: [",join(',',map {join('=>',(%$_))} @bad),"].");
      }

    return($solution);
  }

sub getKds
  {
    my $input_file = $_[0];

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
    my $known_kds = [];
    my $motif_check = {};

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

	push(@$known_kds,[$cp1,$ip,$cp2,$kd]);
      }

    close(INPUT);

    verbose('[',($input_file eq '-' ? 'STDIN' : $input_file),'] ',
	    'Input file done.  Time taken: [',scalar(markTime()),' Seconds].');

    return($known_kds);
  }

sub calculateKd
  {
    my $solution        = $_[0]; #{VALUES => [{AT...},{AA...},{{AT...}}]}
    my $calculate_motif = $_[1];
    my $known_motif     = $_[2];
    my $known_kd        = $_[3];
    my $kd              = $known_kd;

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

	      ((exists($solution->{VALUES}->[$p]->{$calculate_motif->[$p]}) &&
		$solution->{VALUES}->[$p]->{$calculate_motif->[$p]} ne '' ?
		$solution->{VALUES}->[$p]->{$calculate_motif->[$p]} : 0) -

	       (exists($solution->{VALUES}->[$p]->{$known_motif->[$p]}) &&
		$solution->{VALUES}->[$p]->{$known_motif->[$p]} ne '' ?
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
	       (exists($solution->{VALUES}->[$p]->{$calculate_motif->[$p]}) &&
		$solution->{VALUES}->[$p]->{$calculate_motif->[$p]} ne '' ?
		$solution->{VALUES}->[$p]->{$calculate_motif->[$p]} : 0) + 1) /

		  (($solution->{EFFECT} - 1) *
		   (exists($solution->{VALUES}->[$p]->{$known_motif->[$p]}) &&
		    $solution->{VALUES}->[$p]->{$known_motif->[$p]} ne '' ?
		    $solution->{VALUES}->[$p]->{$known_motif->[$p]} : 0) + 1);
	  }
      }
    else
      {error("Invalid equation type: [$solution->{TYPE}].")}

    return($kd);
  }

sub calculateKdOld
  {
    my $solution        = $_[0]; #{VALUES => [{AT=>##,...},{AA=>##,...},...]}
    my $calculate_motif = $_[1]; #e.g. ['AT','AA','AT']
    my $known_motif     = $_[2]; #e.g. ['AT','AA','AT']
    my $known_kd        = $_[3]; #e.g. 43

    my $kd = $known_kd;
    foreach my $i (0..$#{$solution->{VALUES}})
      {
	debug("Position ",($i+1),
	      ": $calculate_motif->[$i]_c vs. $known_motif->[$i]_k");
	$kd += $solution->{EFFECT} *
	  ((exists($solution->{VALUES}->[$i]->{$calculate_motif->[$i]})  &&
	    defined($solution->{VALUES}->[$i]->{$calculate_motif->[$i]}) &&
	    $solution->{VALUES}->[$i]->{$calculate_motif->[$i]} ne '' ?
	    $solution->{VALUES}->[$i]->{$calculate_motif->[$i]} : 0) -
	   (exists($solution->{VALUES}->[$i]->{$known_motif->[$i]})  &&
	    defined($solution->{VALUES}->[$i]->{$known_motif->[$i]}) &&
	    $solution->{VALUES}->[$i]->{$known_motif->[$i]} ne '' ?
	    $solution->{VALUES}->[$i]->{$known_motif->[$i]} : 0));
      }

    return($kd);
  }

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

* WHAT IS THIS: This script will take a set of factors for an equation that
                solves Kd rates between a ligand and 1x1 internal RNA loops, the
                data on which the equation was optimized, and a set of loops on
                which the data was not optimized and output the various
                calculated and average calculated Kd for each loop.  It will
                also output a standard deviation for each set of optimized
                factors as well as for each calculated loop.

* FACTOR FILE FORMAT: This is the format output by oneByOneTrnaLigand.pl.  Here
                      is an example:

Solution Standard Deviation: 15.5409137440499
	Position 1:
		AU	0.1
		UA	0.9
		GC	0.6
		CG	
		GU	
		UG	
	Position 2:
		AG	
		GA	
		AC	
		CA	0.5
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
		CG	0
		GU	
		UG	0.9

                      Note, missing data is assumed to be 0 and to mean that the
                      base pair was not a part of the training set.

* KNOWN KD FILE FORMAT: This is the same as the format input into
                        oneByOneTrnaLigand.pl.  Here is an example:

UA,CA,CG	15
UA,CA,UG	23
CG,CA,UA	24
GU,CA,UA	27
UA,CA,GC	28
UG,CA,CG	37
AU,CA,UG	42
GC,CA,UA	42
UA,CA,GU	48
UG,CA,UG	55
UA,CA,UA	65
AU,CA,CG	150
UG,CA,GC	123
CG,CA,CG	102
GC,CA,GC	154
GC,CA,CG	155
GU,CA,GU	261
CG,CA,GC	257
#I changed the below from "No binding" to double the max: 514
AU,CA,AU	514

                        Note, commented lines (those that start with '#') are
                        ignored.

* CALCULATE KD FILE FORMAT: Same as the KNOWN KD FILE FORMAT except the Kd
                            values are optional.

* OUTPUT FORMAT: Text

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
	   grep {$_ ne '-f' &&
		   $_ ne '-k' &&
		     $_ ne '-c'}       #Remove REQUIRED params
	   map {my $key=$_;            #Save the key
		$key=~s/\|.*//;        #Remove other versions
		$key=~s/(\!|=.|:.)$//; #Remove trailing getopt stuff
		$key = (length($key) > 1 ? '--' : '-') . $key;} #Add dashes
	   grep {$_ ne '<>'}           #Remove the no-flag parameters
	   keys(%$GetOptHash)) .
	     ']';

    print << "end_print";
USAGE: $script -f "factor file(s)" -k "known Kd file(s)" -c "calculate Kd file(s)" $options
       $script -k "known Kd file(s)" -c "calculate Kd file(s)" $options < input_file
end_print

    if($no_descriptions)
      {print("`$script` for expanded usage.\n")}
    else
      {
        print << 'end_print';

     -f|--factor-file*    REQUIRED Space-separated file(s inside quotes) of
                                   factors to plug into the Kd-solving equation.
                                   Standard input via redirection is
                                   acceptable.  Perl glob characters (e.g. '*')
                                   are acceptable inside quotes (e.g.
                                   -f "*.txt *.text").  See --help for a
                                   description of the factor file format.
                                   *No flag required.
     -k|--known-kd-file   REQUIRED Space-separated file(s inside quotes) of 1x1
                                   RNA internal loops with known Kd values.
                                   Perl glob characters (e.g. '*') are
                                   acceptable inside quotes (e.g. -f "*.txt
                                   *.text").  See --help for a description of
                                   the known kd file format.
     -c|--calculate-kd-   REQUIRED Space-separated file(s inside quotes) of 1x1
        file                       RNA internal loops with optional known Kd
                                   values.  Perl glob characters (e.g. '*') are
                                   acceptable inside quotes (e.g. -f "*.txt
                                   *.text").  See --help for a description of
                                   the known kd file format.
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
	#The following is to deal with files that have the eof character at the
	#end of the last line.  I may not have it completely right yet.
	if(defined($line))
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
	else
	  {@{$main::infile_line_buffer->{$file_handle}->{FILE}} = ($line)}
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
    my $template_version_number = '1.38';
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
