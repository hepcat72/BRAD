#!/usr/bin/perl -w

#Generated using perl_script_template.pl 1.37
#Robert W. Leach
#rwleach@ccr.buffalo.edu
#Center for Computational Research
#Copyright 2008

#These variables (in main) are used by getVersion() and usage()
my $software_version_number = '1.1';
my $created_on_date         = '8/4/2009';

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
my $max_num_loops       = 33;
my @starting_loops      = ();
my $test_only           = 0;
my $random_selection    = 0;
my $symmetry_mode       = 0;

#These variables (in main) are used by the following subroutines:
#verbose, error, warning, debug, getCommand, quit, and usage
my $preserve_args = [@ARGV];  #Preserve the agruments for getCommand
my $verbose       = 0;
my $quiet         = 0;
my $DEBUG         = 0;
my $ignore_errors = 0;

my $GetOptHash =
  {# ENTER YOUR COMMAND LINE PARAMETERS HERE AS BELOW

   'i|input-file=s'     => sub {push(@input_files,   #REQUIRED unless <> is
				     sglob($_[1]))}, #         supplied
   '<>'                 => sub {push(@input_files,   #REQUIRED unless -i is
				     sglob($_[0]))}, #         supplied
   'starting-loops=s'   => sub {push(@starting_loops,#OPTIONAL [none]
				     sglob($_[1]))},
   't|test-only!'       => \$test_only,              #OPTIONAL [Off]
   'r|random-selection!'=> \$random_selection,       #OPTIONAL [Off]
   'symmetry-mode!'     => \$symmetry_mode,          #OPTIONAL [Off]
   'n|num-to-test=s'    => \$max_num_loops,          #OPTIONAL [33]
   'o|outfile-suffix=s' => \$outfile_suffix,         #OPTIONAL [undef]
   'force|overwrite'    => \$overwrite,              #OPTIONAL [Off]
   'ignore'             => \$ignore_errors,          #OPTIONAL [Off]
   'verbose:+'          => \$verbose,                #OPTIONAL [Off]
   'quiet'              => \$quiet,                  #OPTIONAL [Off]
   'debug:+'            => \$DEBUG,                  #OPTIONAL [Off]
   'help|?'             => \$help,                   #OPTIONAL [Off]
   'version'            => \$version,                #OPTIONAL [Off]
   'noheader'           => \$noheader,               #OPTIONAL [Off]
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

if($max_num_loops < 1)
  {
    error("Invalid -n value: [$max_num_loops].  The number of loops to test ",
	  "(-n) must be greater than 0.");
    usage(1);
    quit(5);
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

my @cps = ("GU","UG","GC","CG","AU","UA");
my @ips = ("AA","CC","GG","UU","UC","CU","GA","AG","AC","CA");
my $loop_check = {};
my @tmp_starting_loops = ();
if(scalar(@starting_loops))
  {
    foreach my $loop (@starting_loops)
      {
	my $rev_loop = scalar(reverse($loop));
	if(exists($loop_check->{$loop}) ||
	   ($symmetry_mode && exists($loop_check->{$rev_loop})))
	  {
	    error("This starting loop: [$loop] was added twice.  ",
		  ($symmetry_mode && exists($loop_check->{$rev_loop}) ?
		   'It is an idential rotated version of another one that ' .
		   'was added.  ' : ''),"Your starting loops have been ",
		  "trimmed to account for the duplicate.");
	  }
	else
	  {
	    $loop_check->{$loop} = 0;
	    if($symmetry_mode)
	      {
		#Put the lesser (alphabetically) loop in the starting loops
		push(@tmp_starting_loops,
		     (sort {$a cmp $b} ($loop,$rev_loop))[0]);
	      }
	    else
	      {push(@tmp_starting_loops,$loop)}
	  }
      }

    @starting_loops = @tmp_starting_loops;
  }

if($test_only && scalar(@starting_loops) == 0)
  {
    error("You can only supply the --test-only option with a set of starting ",
	  "loops.");
    usage(1);
    quit(6);
  }
elsif($test_only)
  {$max_num_loops = scalar(@starting_loops)}

#For each input file
foreach my $input_file (@input_files)
  {
    my $hash = {};
    my $old_hash  = {};

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

    #For each line in the current input file
    while(getLine(*INPUT))
      {
	$line_num++;
	verboseOverMe('[',($input_file eq '-' ? 'STDIN' : $input_file),'] ',
		      "Reading line: [$line_num].") unless($line_num %
							   $verbose_freq);

	next if(/^\s*#/ || /^\s*$/);

	#Assumes that second column is the reverse complement of the first
	#column and that when there's only one column, it's a palindrome
	#Note, I'm ignoring the second column
	if(/(\S+)\t(\S+)/)
	  {
	    my $loop1 = uc($1);
	    my $loop2 = uc($2);
	    $loop1 =~ s/[^A-Z]/,/g;
	    $loop2 =~ s/[^A-Z]/,/g;
	    my $loop = (sort {$a cmp $b} ($loop1,$loop2))[0];
	    $hash->{$loop} = 0;
	    $old_hash->{$loop} = 0;
	  }
	elsif(/(\S+)/)
	  {
	    my $loop = uc($1);
	    $loop =~ s/[^A-Z]/,/g;
	    $hash->{$loop} = 0;
	    $old_hash->{$loop} = 0;
	  }
      }

    close(INPUT);

    verbose('[',($input_file eq '-' ? 'STDIN' : $input_file),'] ',
	    'Input file done.  Time taken: [',scalar(markTime()),' Seconds].');

    my @picks     = @starting_loops;
    my $pick_hash = {};

    #If we have some pre-selected loops, get ready to make the first selection
    if(scalar(@picks))
      {
	map
	  {$pick_hash->{$_} = 1;
	     #$pick_hash->{reverse($_)} = 1
	  } @picks;

	foreach my $loop (keys(%$pick_hash))
	  {
	    my($cp1,$ip,$cp2);
	    ($cp1,$ip,$cp2)=split(/[^A-Z]+/,$loop);

	    debug("PICKED LOOP: $loop");

	    if(exists($hash->{"$cp1,$ip,$cp2"}))
	      {debug("INCREMENTING ",$hash->{"$cp1,$ip,$cp2"});
		$hash->{"$cp1,$ip,$cp2"}++}
#	    elsif("$cp1,$ip,$cp2" ne reverse("$cp1,$ip,$cp2") &&
#		  exists($hash->{reverse("$cp1,$ip,$cp2")}))
#	      {debug("INCREMENTING REVERSE ",
#		     $hash->{reverse("$cp1,$ip,$cp2")});
#		$hash->{reverse("$cp1,$ip,$cp2")}++}
	    else
	      {warning("This loop was not found in your file in ",
		       "either orientation.")}

	    #Count all the neighbors (loops which differ by 1 BP) that have
	    #been counted for this current loop
	    my $neighbor_check = {};

	    #For each alternate closing pair (acp)
	    foreach my $acp (@cps)
	      {
		#Alternate the first closing pair, skipping the current one
		if("$acp,$ip,$cp2" ne "$cp1,$ip,$cp2" #&&
		   #"$acp,$ip,$cp2" ne reverse("$cp1,$ip,$cp2")
		  )
		  {
		    my $neighbor = "$acp,$ip,$cp2";
		    #Use the loop that is considered lesser, alphabetically,
		    #when in symmetry mode
		    if($symmetry_mode)
		      {$neighbor = (sort {$a cmp $b}
				    ("$acp,$ip,$cp2",
				     scalar(reverse("$acp,$ip,$cp2"))))[0]}

		    #If this neighbor has already been counted for this loop,
		    #skip it
		    next if(exists($neighbor_check->{$neighbor}));
		    $neighbor_check->{$neighbor} = 1;
		    debug("DOING: $neighbor");

		    #If this potential neighbor is among the selected loops,
		    #Count it as a neighbor to the current loop
		    if(exists($hash->{"$neighbor"}))
		      {debug("INCREMENTING ",$hash->{"$neighbor"});
			$hash->{"$neighbor"}++}

#		    if(exists($hash->{"$acp,$ip,$cp2"}))
#		      {debug("INCREMENTING ",$hash->{"$acp,$ip,$cp2"});
#			$hash->{"$acp,$ip,$cp2"}++}
#		    elsif("$acp,$ip,$cp2" ne reverse("$acp,$ip,$cp2") &&
#			  exists($hash->{reverse("$acp,$ip,$cp2")}))
#		      {debug("INCREMENTING REVERSE ",
#			     $hash->{reverse("$acp,$ip,$cp2")});
#			$hash->{reverse("$acp,$ip,$cp2")}++}
		    else
		      {warning("This loop was not found in your file",
			       ($symmetry_mode ?
				" in either orientation" : ''),
			       ": [$acp,$ip,$cp2]")}
		  }

		#Alternate the last closing pair, skipping the current one
		if("$cp1,$ip,$acp" ne "$cp1,$ip,$cp2" #&&
		   #"$cp1,$ip,$acp" ne reverse("$cp1,$ip,$cp2")
		  )
		  {
		    my $neighbor = "$cp1,$ip,$acp";
		    #Use the loop that is considered lesser, alphabetically,
		    #when in symmetry mode
		    if($symmetry_mode)
		      {$neighbor = (sort {$a cmp $b}
				    ("$cp1,$ip,$acp",
				     scalar(reverse("$cp1,$ip,$acp"))))[0]}

		    #If this neighbor has already been counted for this loop,
		    #skip it
		    next if(exists($neighbor_check->{$neighbor}));
		    $neighbor_check->{$neighbor} = 1;
		    debug("DOING: $neighbor");

		    #If this potential neighbor is among the selected loops,
		    #Count it as a neighbor to the current loop
		    if(exists($hash->{"$neighbor"}))
		      {debug("INCREMENTING ",$hash->{"$neighbor"});
			$hash->{"$neighbor"}++}

#		    if(exists($hash->{"$cp1,$ip,$acp"}))
#		      {debug("INCREMENTING ",$hash->{"$cp1,$ip,$acp"});
#			$hash->{"$cp1,$ip,$acp"}++}
#		    elsif("$cp1,$ip,$acp" ne reverse("$cp1,$ip,$acp") &&
#			  exists($hash->{reverse("$cp1,$ip,$acp")}))
#		      {debug("INCREMENTING REVERSE ",
#			     $hash->{reverse("$cp1,$ip,$acp")});
#			$hash->{reverse("$cp1,$ip,$acp")}++}
		    else
		      {warning("This loop was not found in your file",
			       ($symmetry_mode ?
				" in either orientation" : ''),
			       ": [$cp1,$ip,$acp]")}
		  }
	      }

	    #For each alternate internal pair
	    foreach my $aip (@ips)
	      {
		#Alternate the last closing pair, skipping the current one
		if("$cp1,$aip,$cp2" ne "$cp1,$ip,$cp2" #&&
		   #"$cp1,$aip,$cp2" ne reverse("$cp1,$ip,$cp2")
		  )
		  {
		    my $neighbor = "$cp1,$aip,$cp2";
		    #Use the loop that is considered lesser, alphabetically,
		    #when in symmetry mode
		    if($symmetry_mode)
		      {$neighbor = (sort {$a cmp $b}
				    ("$cp1,$aip,$cp2",
				     scalar(reverse("$cp1,$aip,$cp2"))))[0]}

		    #If this neighbor has already been counted for this loop,
		    #skip it
		    next if(exists($neighbor_check->{$neighbor}));
		    $neighbor_check->{$neighbor} = 1;
		    debug("DOING: $neighbor");

		    #If this potential neighbor is among the selected loops,
		    #Count it as a neighbor to the current loop
		    if(exists($hash->{"$neighbor"}))
		      {debug("INCREMENTING ",$hash->{$neighbor});
			$hash->{$neighbor}++}

#		    if(exists($hash->{"$cp1,$aip,$cp2"}))
#		      {debug("INCREMENTING ",$hash->{"$cp1,$aip,$cp2"});
#			$hash->{"$cp1,$aip,$cp2"}++}
#		    elsif("$cp1,$aip,$cp2" ne reverse("$cp1,$aip,$cp2") &&
#			  exists($hash->{reverse("$cp1,$aip,$cp2")}))
#		      {debug("INCREMENTING REVERSE ",
#			     $hash->{reverse("$cp1,$aip,$cp2")});
#			$hash->{reverse("$cp1,$aip,$cp2")}++}
		    else
		      {warning("This loop was not found in your file",
			       ($symmetry_mode ?
				" in either orientation" : ''),
			       ": [$cp1,$aip,$cp2]")}
		  }
	      }
	  }

#	foreach my $loop (keys(%$pick_hash))
#	  {
#	    my($cp1,$ip,$cp2);
#	    ($cp1,$ip,$cp2)=split(/[^A-Z]+/,$loop);
#
#	    if(exists($hash->{"$cp1,$ip,$cp2"}))
#	      {$hash->{"$cp1,$ip,$cp2"}++}
#	    elsif("$cp1,$ip,$cp2" ne reverse("$cp1,$ip,$cp2") &&
#		  exists($hash->{reverse("$cp1,$ip,$cp2")}))
#	      {$hash->{reverse("$cp1,$ip,$cp2")}++}
#	    else
#	      {warning("This loop was not found in your file in ",
#		       "either orientation: [$cp1,$ip,$cp2].")}
#
#	    #For each alternate closing pair (acp)
#	    foreach my $acp (@cps)
#	      {
#		#Alternate the first closing pair, skipping the current one
#		if("$acp,$ip,$cp2" ne "$cp1,$ip,$cp2" &&
#		   "$acp,$ip,$cp2" ne reverse("$cp1,$ip,$cp2"))
#		  {
#		    if(exists($hash->{"$acp,$ip,$cp2"}))
#		      {$hash->{"$acp,$ip,$cp2"}++}
#		    elsif("$acp,$ip,$cp2" ne reverse("$acp,$ip,$cp2") &&
#			  exists($hash->{reverse("$acp,$ip,$cp2")}))
#		      {$hash->{reverse("$acp,$ip,$cp2")}++}
#		    else
#		      {warning("This loop was not found in your file in ",
#			       "either orientation: [$acp,$ip,$cp2].")}
#		  }
#
#		#Alternate the last closing pair, skipping the current one
#		if("$cp1,$ip,$acp" ne "$cp1,$ip,$cp2" &&
#		   "$cp1,$ip,$acp" ne reverse("$cp1,$ip,$cp2"))
#		  {
#		    if(exists($hash->{"$cp1,$ip,$acp"}))
#		      {$hash->{"$cp1,$ip,$acp"}++}
#		    elsif("$cp1,$ip,$acp" ne reverse("$cp1,$ip,$acp") &&
#			  exists($hash->{reverse("$cp1,$ip,$acp")}))
#		      {$hash->{reverse("$cp1,$ip,$acp")}++}
#		    else
#		      {warning("This loop was not found in your file in ",
#			       "either orientation: [$cp1,$ip,$acp].")}
#		  }
#	      }
#
#	    #For each alternate internal pair
#	    foreach my $aip (@ips)
#	      {
#		#Alternate the last closing pair, skipping the current one
#		if("$cp1,$aip,$cp2" ne "$cp1,$ip,$cp2" &&
#		   "$cp1,$aip,$cp2" ne reverse("$cp1,$ip,$cp2"))
#		  {
#		    if(exists($hash->{"$cp1,$aip,$cp2"}))
#		      {$hash->{"$cp1,$aip,$cp2"}++}
#		    elsif("$cp1,$aip,$cp2" ne reverse("$cp1,$aip,$cp2") &&
#			  exists($hash->{reverse("$cp1,$aip,$cp2")}))
#		      {$hash->{reverse("$cp1,$aip,$cp2")}++}
#		    else
#		      {warning("This loop was not found in your file in ",
#			       "either orientation: [$cp1,$aip,$cp2].")}
#		  }
#	      }
#	  }

	map {$old_hash->{$_} = $hash->{$_}} keys(%$hash);
      }

    foreach((scalar(@starting_loops)+1)..$max_num_loops)
      {
	push(@picks,(sort {$old_hash->{$a} <=> $old_hash->{$b} ||
			     $hash->{$a} <=> $hash->{$b} ||
			       (int(rand(2)) ? -1 : 1)
			   }
		     grep {!exists($pick_hash->{$_})} keys(%$hash))[0]);
	$pick_hash->{$picks[-1]} = 1;
#	$pick_hash->{reverse($picks[-1])} = 1;
	map {$hash->{$_} = 0} keys(%$hash);

	debug("DOING SOLUTION SIZE $_");

	foreach my $loop (keys(%$pick_hash))
	  {
	    my($cp1,$ip,$cp2);
	    ($cp1,$ip,$cp2)=split(/[^A-Z]+/,$loop);

	    debug("PICKED LOOP: $loop");

	    if(exists($hash->{"$cp1,$ip,$cp2"}))
	      {debug("INCREMENTING ",$hash->{"$cp1,$ip,$cp2"});
		$hash->{"$cp1,$ip,$cp2"}++}
#	    elsif("$cp1,$ip,$cp2" ne reverse("$cp1,$ip,$cp2") &&
#		  exists($hash->{reverse("$cp1,$ip,$cp2")}))
#	      {debug("INCREMENTING REVERSE ",
#		     $hash->{reverse("$cp1,$ip,$cp2")});
#		$hash->{reverse("$cp1,$ip,$cp2")}++}
	    else
	      {warning("This loop was not found in your file",
		       ($symmetry_mode ?
			" in either orientation" : ''),
		       ": [$cp1,$ip,$cp2]")}

	    my $neighbor_check = {};

	    #For each alternate closing pair (acp)
	    foreach my $acp (@cps)
	      {
		#Alternate the first closing pair, skipping the current one
		if("$acp,$ip,$cp2" ne "$cp1,$ip,$cp2" #&&
		   #"$acp,$ip,$cp2" ne reverse("$cp1,$ip,$cp2")
		  )
		  {
		    my $neighbor = "$acp,$ip,$cp2";
		    #Use the loop that is considered lesser, alphabetically,
		    #when in symmetry mode
		    if($symmetry_mode)
		      {$neighbor = (sort {$a cmp $b}
				    ("$acp,$ip,$cp2",
				     scalar(reverse("$acp,$ip,$cp2"))))[0]}

		    #If this neighbor has already been counted for this loop,
		    #skip it
		    next if(exists($neighbor_check->{$neighbor}));
		    $neighbor_check->{$neighbor} = 1;
		    debug("DOING: $neighbor");

		    #If this potential neighbor is among the selected loops,
		    #Count it as a neighbor to the current loop
		    if(exists($hash->{"$neighbor"}))
		      {debug("INCREMENTING ",$hash->{"$neighbor"});
			$hash->{"$neighbor"}++}

#		    if(exists($hash->{"$acp,$ip,$cp2"}))
#		      {debug("INCREMENTING ",$hash->{"$acp,$ip,$cp2"});
#			$hash->{"$acp,$ip,$cp2"}++}
#		    elsif("$acp,$ip,$cp2" ne reverse("$acp,$ip,$cp2") &&
#			  exists($hash->{reverse("$acp,$ip,$cp2")}))
#		      {debug("INCREMENTING REVERSE ",
#			     $hash->{reverse("$acp,$ip,$cp2")});
#			$hash->{reverse("$acp,$ip,$cp2")}++}
		    else
		      {warning("This loop was not found in your file",
			       ($symmetry_mode ?
				" in either orientation" : ''),
			       ": [$acp,$ip,$cp2]")}
		  }

		#Alternate the last closing pair, skipping the current one
		if("$cp1,$ip,$acp" ne "$cp1,$ip,$cp2" #&&
		   #"$cp1,$ip,$acp" ne reverse("$cp1,$ip,$cp2")
		  )
		  {
		    my $neighbor = "$cp1,$ip,$acp";
		    #Use the loop that is considered lesser, alphabetically,
		    #when in symmetry mode
		    if($symmetry_mode)
		      {$neighbor = (sort {$a cmp $b}
				    ("$cp1,$ip,$acp",
				     scalar(reverse("$cp1,$ip,$acp"))))[0]}

		    #If this neighbor has already been counted for this loop,
		    #skip it
		    next if(exists($neighbor_check->{$neighbor}));
		    $neighbor_check->{$neighbor} = 1;
		    debug("DOING: $neighbor");

		    #If this potential neighbor is among the selected loops,
		    #Count it as a neighbor to the current loop
		    if(exists($hash->{"$neighbor"}))
		      {debug("INCREMENTING ",$hash->{"$neighbor"});
			$hash->{"$neighbor"}++}

#		    if(exists($hash->{"$cp1,$ip,$acp"}))
#		      {debug("INCREMENTING ",$hash->{"$cp1,$ip,$acp"});
#			$hash->{"$cp1,$ip,$acp"}++}
#		    elsif("$cp1,$ip,$acp" ne reverse("$cp1,$ip,$acp") &&
#			  exists($hash->{reverse("$cp1,$ip,$acp")}))
#		      {debug("INCREMENTING REVERSE ",
#			     $hash->{reverse("$cp1,$ip,$acp")});
#			$hash->{reverse("$cp1,$ip,$acp")}++}
		    else
		      {warning("This loop was not found in your file",
			       ($symmetry_mode ?
				" in either orientation" : ''),
			       ": [$cp1,$ip,$acp]")}
		  }
	      }

	    #For each alternate internal pair
	    foreach my $aip (@ips)
	      {
		#Alternate the last closing pair, skipping the current one
		if("$cp1,$aip,$cp2" ne "$cp1,$ip,$cp2" #&&
		   #"$cp1,$aip,$cp2" ne reverse("$cp1,$ip,$cp2")
		  )
		  {
		    my $neighbor = "$cp1,$aip,$cp2";
		    #Use the loop that is considered lesser, alphabetically,
		    #when in symmetry mode
		    if($symmetry_mode)
		      {$neighbor = (sort {$a cmp $b}
				    ("$cp1,$aip,$cp2",
				     scalar(reverse("$cp1,$aip,$cp2"))))[0]}

		    #If this neighbor has already been counted for this loop,
		    #skip it
		    next if(exists($neighbor_check->{$neighbor}));
		    $neighbor_check->{$neighbor} = 1;
		    debug("DOING: $neighbor");

		    #If this potential neighbor is among the selected loops,
		    #Count it as a neighbor to the current loop
		    if(exists($hash->{"$neighbor"}))
		      {debug("INCREMENTING ",$hash->{$neighbor});
			$hash->{$neighbor}++}

#		    if(exists($hash->{"$cp1,$aip,$cp2"}))
#		      {debug("INCREMENTING ",$hash->{"$cp1,$aip,$cp2"});
#			$hash->{"$cp1,$aip,$cp2"}++}
#		    elsif("$cp1,$aip,$cp2" ne reverse("$cp1,$aip,$cp2") &&
#			  exists($hash->{reverse("$cp1,$aip,$cp2")}))
#		      {debug("INCREMENTING REVERSE ",
#			     $hash->{reverse("$cp1,$aip,$cp2")});
#			$hash->{reverse("$cp1,$aip,$cp2")}++}
		    else
		      {warning("This loop was not found in your file",
			       ($symmetry_mode ?
				" in either orientation" : ''),
			       ": [$cp1,$aip,$cp2]")}
		  }
	      }
	  }

	map {$old_hash->{$_} = $hash->{$_}} keys(%$hash);
      }

    #Print the selections
    print("#Picks: ",join(' ',@picks),"\n");

    #Print the number of sequences that differ by one or fewer pairs for each
    #loop
    foreach my $loop (sort {$old_hash->{$b} <=> $old_hash->{$a}}
		      keys(%$old_hash))
      {print("$loop\t$old_hash->{$loop}\n")}

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

* WHAT IS THIS: This script picks 1x1 internal tRNA loops containing a closing base pair on either end and selects loops to be used in experimental testing.  It bases its decision based on finding the number of loops requested with the most even coverage of other loops given a 1 base-pair difference.  It generates a coverage report of how many other sequences selected match each loop by 2 pairs.

* INPUT FORMAT: The input file is a 2-column file of tRNA internal loops.  The second column is ignored and represents the reverse sequence (rotated 180 degrees) because it is the same sequence.  Input looks like this:

AU,AA,AU	UA,AA,UA
AU,AA,CG	GC,AA,UA
AU,AA,GC	CG,AA,UA
AU,AA,GU	UG,AA,UA
AU,AA,UA
AU,AA,UG	GU,AA,UA
AU,AC,AU	UA,CA,UA

where, as in the first line, AU is the first closing base pair, AA is the loop pair, and AU is the last closing base pair.  Note, AU,AA,UA is symmetrical, so it has no reverse sequence.  There are 192 unique possibilities.  I generated a list of all possibilities using another script (ordered_digit_increment.pl) and manual substitution of numbers for ribonucleotide pairs using text edit.  I then created the two-column output using a perl script one-liner.

* OUTPUT FORMAT: The first line is a commented line indicating the pairs that were chose and the rest is 2 columns of output, the first of which is each loop from the first column of the input file and the second column is the number of selected sequences that differe by 1 or fewer base pairs.

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

     -i|--input-file*     REQUIRED Space-separated loop file(s inside quotes).
                                   Standard input via redirection is
                                   acceptable.  Perl glob characters (e.g. '*')
                                   are acceptable inside quotes (e.g.
                                   -i "*.txt *.text").  See --help for a
                                   description of the input file format.
                                   *No flag required.
     --starting-loops     OPTIONAL [none] Loops (see --help for the way a loop
                                   is represented) separated by spaces inside
                                   quotes.  Use --test-only if you do not want
                                   to add to this set up to the number
                                   indicated by -n.
     -t|--test-only       OPTIONAL [Off] Requires --starting-loops to be
                                   supplied.  This will test the set of loops
                                   you've selected and give you the coverage of
                                   all loops that differ by 1 from the selected
                                   set.  Watch our for errors about your input
                                   set.
     -r|--random-         OPTIONAL [Off] Of loops that have the same coverage,
        selection                  select the next one to add randomly.  This
                                   can improve your coverage because the
                                   heuristic used in loop selection is not
                                   perfect.  Rerun until you get the coverage
                                   you desire.
     -n|--num-to-test     OPTIONAL [33] The number of internal loops to pick.
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
	if(!eof($file_handle))
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
	  {
	    #Do the \r substitution for the last line of files that have the
	    #eof character at the end of the last line instead of on a line by
	    #itself.  I tested this on a file that was causing errors for the
	    #last line and it works.
	    $line =~ s/\r/\n/g if(defined($line));
	    @{$main::infile_line_buffer->{$file_handle}->{FILE}} = ($line);
	  }
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
