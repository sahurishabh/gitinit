#!/usr/local/bin/perl -w

###############################################################################
# Program     : load_possible_peptides.pl
# Author      : Eric Deutsch <edeutsch@systemsbiology.org>
# $Id$
#
# Description : This script loads a text file of possible peptides in a
#               specific biosequence_set.  This is ususally a culled list of
#               peptides not every possible one, e.g. ones with two
#               tryptic terminii and/or within a specific mass range, but
#               can be anything, of course.
#
#               The file format, as generated by Jimmy Eng's digestdb is TSV:
# biosequence_name mass preceding_residue peptide following_residue index[optional]
###############################################################################


###############################################################################
# Generic SBEAMS setup for all the needed modules and objects
###############################################################################
use strict;
use Getopt::Long;
use FindBin;

use lib qw (../perl ../../perl);
use vars qw ($sbeams $sbeamsMOD $q
             $PROG_NAME $USAGE %OPTIONS $QUIET $VERBOSE $DEBUG $DATABASE
	     $TESTONLY
             $current_contact_id $current_username
	     $fav_codon_frequency
            );


#### Set up SBEAMS core module
use SBEAMS::Connection qw($q);
use SBEAMS::Connection::Settings;
use SBEAMS::Connection::Tables;
$sbeams = SBEAMS::Connection->new();

use SBEAMS::Proteomics::Utilities;

#use CGI;
#$q = CGI->new();

  #### Set up use of some special stuff to calculate pI.  FIXME
  use lib qw (/net/db/projects/proteomics/src/Proteomics/blib/lib
    /net/db/projects/proteomics/src/Proteomics/blib/arch/auto/Proteomics);
  use Proteomics;



###############################################################################
# Set program name and usage banner for command like use
###############################################################################
$PROG_NAME = $FindBin::Script;
$USAGE = <<EOU;
Usage: $PROG_NAME [OPTIONS]
Options:
  --verbose n          Set verbosity level.  default is 0
  --quiet              Set flag to print nothing at all except errors
  --debug n            Set debug flag
  --testonly           If set, rows in the database are not changed or added
  --delete_existing    Delete the existing peptides for this set before
                       loading.  Normally, if there are existing peptides,
                       the load is blocked.
  --update_existing    Update the existing peptide set with information
                       in the file
  --set_tag            The set_tag of a biosequence_set that the peptides are
                       to be associated with
  --source_file        Filename for the source file containing the list of
                       possible peptides in the format listed above
  --check_status       Is set, nothing is actually done, but rather the
                       biosequence_set and number of existing peptide is shown
  --halt_at xxxx       Is set, stop processing with the regexp matches
                       the biosequence_name

 e.g.:  $PROG_NAME --set_tag Dros_aaR2 --check_status
 e.g.:  $PROG_NAME --set_tag Dros_aaR2 --source_file floyd-pep.txt

EOU


#### Process options
unless (GetOptions(\%OPTIONS,"verbose:s","quiet","debug:s","testonly",
  "delete_existing","update_existing","source_file:s",
  "set_tag:s","check_status","halt_at:s",
  )) {
  print "$USAGE";
  exit;
}

$VERBOSE = $OPTIONS{"verbose"} || 0;
$QUIET = $OPTIONS{"quiet"} || 0;
$DEBUG = $OPTIONS{"debug"} || 0;
$TESTONLY = $OPTIONS{"testonly"} || 0;
if ($DEBUG) {
  print "Options settings:\n";
  print "  VERBOSE = $VERBOSE\n";
  print "  QUIET = $QUIET\n";
  print "  DEBUG = $DEBUG\n";
  print "  TESTONLY = $TESTONLY\n";
}


###############################################################################
# Set Global Variables and execute main()
###############################################################################
main();
exit(0);


###############################################################################
# Main Program:
#
# Call $sbeams->Authenticate() and exit if it fails or continue if it works.
###############################################################################
sub main {

  #### Try to determine which module we want to affect
  my $module = $sbeams->getSBEAMS_SUBDIR();
  my $work_group = 'unknown';
  if ($module eq 'Proteomics') {
    $work_group = "${module}_admin";
    $DATABASE = $DBPREFIX{$module};
  }


  #### Do the SBEAMS authentication and exit if a username is not returned
  exit unless ($current_username = $sbeams->Authenticate(
    work_group=>$work_group,
  ));


  $sbeams->printPageHeader() unless ($QUIET);
  handleRequest();
  $sbeams->printPageFooter() unless ($QUIET);


} # end main



###############################################################################
# handleRequest
###############################################################################
sub handleRequest { 
  my %args = @_;


  #### Define standard variables
  my ($i,$element,$key,$value,$line,$result,$sql);


  #### Set the command-line options
  my $delete_existing = $OPTIONS{"delete_existing"} || '';
  my $update_existing = $OPTIONS{"update_existing"} || '';
  my $source_file = $OPTIONS{"source_file"} || '';
  my $check_status = $OPTIONS{"check_status"} || '';
  my $set_tag = $OPTIONS{"set_tag"} || '';
  my $halt_at = $OPTIONS{"halt_at"} || '';


  #### Print out the header
  unless ($QUIET) {
    $sbeams->printUserContext();
    print "\n";
  }


  #### Define a scalar and array of biosequence_set_id's
  my ($biosequence_set_id,$n_biosequence_sets);
  my @biosequence_set_ids;


  #### If there was a set_tag specified, identify it
  if ($set_tag) {
    $sql = "
          SELECT BSS.biosequence_set_id
            FROM ${DATABASE}biosequence_set BSS
           WHERE BSS.set_tag = '$set_tag'
             AND BSS.record_status != 'D'
    ";

    @biosequence_set_ids = $sbeams->selectOneColumn($sql);
    $n_biosequence_sets = @biosequence_set_ids;

    die "No biosequence_sets found with set_tag = '$set_tag'"
      if ($n_biosequence_sets < 1);
    die "Too many biosequence_sets found with set_tag = '$set_tag'"
      if ($n_biosequence_sets > 1);


  #### If there was NOT a set_tag specified, error out
  } else {
    print "ERROR: You must specify the --set_tag parameter\n";
    print $USAGE;
    exit;
  }

  $biosequence_set_id = $biosequence_set_ids[0];


  #### Get the status of the biosequence_set
  my $status = getBiosequenceSetStatus(
    biosequence_set_id => $biosequence_set_id,
    show_status => 'Detailed',
  );


  #### If we're not just checking the status
  unless ($check_status) {

    #### If there was NOT a source_file specified, error out
    unless ($source_file) {
	print "ERROR: You must specify the --source_file parameter to load\n";
	print $USAGE;
	exit;
    }

    my $do_load = 0;
    $do_load = 1 if ($status->{n_peptides} == 0);
    $do_load = 1 if ($update_existing);
    $do_load = 1 if ($delete_existing);

    #### If it's determined that we need to do a load, do it
    if ($do_load) {
      $result = loadPossiblePeptides(
        set_name=>$status->{set_name},
        source_file=>$source_file,
        halt_at=>$halt_at,
      );
    } else {
	print "This biosequence already has peptides: use update or delete.\n";
    }

  } else {
      print <<EOS;
      Status for biosequence: $status->{set_name}
                     Set Tag: $status->{set_tag}
                    Set Path: $status->{set_path}
                     Version: $status->{set_version}
         Number of sequences: $status->{n_biosequences}
      Num. possible peptides: $status->{n_peptides}
EOS
  }

  return;

} # end handleRequest



###############################################################################
# getBiosequenceSetStatus
###############################################################################
sub getBiosequenceSetStatus {
  my %args = @_;
  my $SUB_NAME = 'getBiosequenceSetStatus';


  #### Decode the argument list
  my $biosequence_set_id = $args{'biosequence_set_id'}
   || die "ERROR[$SUB_NAME]: biosequence_set_id not passed";
  my $show_status = $args{'show_status'};


  #### Define standard variables
  my ($i,$element,$key,$value,$line,$result,$sql);


  #### Get information about this biosequence_set_id from database
  $sql = "
          SELECT BSS.biosequence_set_id,set_name,set_tag,set_path,set_version
            FROM ${DATABASE}biosequence_set BSS
           WHERE BSS.biosequence_set_id = '$biosequence_set_id'
             AND BSS.record_status != 'D'
  ";
  my @rows = $sbeams->selectSeveralColumns($sql);


  #### Put the information in a hash
  my %status;
  $status{biosequence_set_id} = $rows[0]->[0];
  $status{set_name} = $rows[0]->[1];
  $status{set_tag} = $rows[0]->[2];
  $status{set_path} = $rows[0]->[3];
  $status{set_version} = $rows[0]->[4];


  #### Get the number of biosequences for this biosequence_set_id from database
  $sql = "
          SELECT count(*) AS 'count'
            FROM ${DATABASE}biosequence BS
           WHERE BS.biosequence_set_id = '$biosequence_set_id'
  ";
  my ($n_biosequences) = $sbeams->selectOneColumn($sql);


  #### Add information to hash
  $status{n_biosequences} = $n_biosequences;


  #### Get the number of peptides for this biosequence_set_id from database
  $sql = "
          SELECT count(*) AS 'count'
            FROM ${DATABASE}possible_peptide PP
            JOIN ${DATABASE}biosequence BS
	         ON ( PP.biosequence_id = BS.biosequence_id )
           WHERE BS.biosequence_set_id = '$biosequence_set_id'
  ";
  my ($n_peptides) = $sbeams->selectOneColumn($sql);


  #### Add information to hash
  $status{n_peptides} = $n_peptides;


  #### Return information
  return \%status;

}



###############################################################################
# loadPossiblePeptides
###############################################################################
sub loadPossiblePeptides {
  my %args = @_;
  my $SUB_NAME = 'loadPossiblePeptides';


  #### Decode the argument list
  my $set_name = $args{'set_name'}
   || die "ERROR[$SUB_NAME]: biosequence_set_id not passed";
  my $source_file = $args{'source_file'}
   || die "ERROR[$SUB_NAME]: source_file not passed";
  my $halt_at = $args{'halt_at'};


  #### Define standard variables
  my ($i,$element,$key,$value,$line,$result,$sql);


  #### Set the command-line options
  my $delete_existing = $OPTIONS{"delete_existing"};
  my $update_existing = $OPTIONS{"update_existing"};


  #### Verify the source_file
  unless ( -e "$source_file" ) {
    die("ERROR[$SUB_NAME]: Cannot find file $source_file");
  }


  #### Set the set_name
  $sql = "SELECT set_name,biosequence_set_id" .
         "  FROM ${DATABASE}biosequence_set";
  #print "SQL: $sql\n";
  my %set_names = $sbeams->selectTwoColumnHash($sql);
  my $biosequence_set_id = $set_names{$set_name};


  #### If we didn't find it then bail
  unless ($biosequence_set_id) {
    bail_out("Unable to determine a biosequence_set_id for '$set_name'.  " .
      "A record for this biosequence_set must already have been entered " .
      "before the sequences may be loaded.");
  }


  #goto UNIQUENESSUPDATE;


  #### Test if there are already sequences for this biosequence_set
  $sql = "
    SELECT COUNT(*)
      FROM ${DATABASE}possible_peptide PP
      JOIN ${DATABASE}biosequence BS
           ON ( PP.biosequence_id = BS.biosequence_id )
     WHERE biosequence_set_id = '$biosequence_set_id'
  ";
  my ($count) = $sbeams->selectOneColumn($sql);

  #### If so
  if ($count) {

    #### If the delete_existing option was selected, delete them
    if ($delete_existing) {
      print "Deleting...\n$sql\n";
      $sql = "
        DELETE ${DATABASE}possible_peptide
          FROM ${DATABASE}possible_peptide PP
          JOIN ${DATABASE}biosequence BS
               ON ( PP.biosequence_id = BS.biosequence_id )
         WHERE biosequence_set_id = '$biosequence_set_id'
      ";
      $sbeams->executeSQL($sql);

    #### Otherwise unless the update_existing option was explicitly set, die
    } elsif (!($update_existing)) {
      die("There are already possible_peptide records for this ".
        "biosequence_set.  Please delete those records before trying to ".
        "load new sequences, or specify the --delete_existing ".
        "or --update_existing flags.");
    }

  }


  #### Open source_file
  unless (open(INFILE,"$source_file")) {
    die("Cannot open file '$source_file'");
  }


  #### Create a hash to store biosequence_name = biosequence_id
  $sql = "
          SELECT biosequence_name,biosequence_id
            FROM ${DATABASE}biosequence BS
           WHERE BS.biosequence_set_id = '$biosequence_set_id'
  ";
  my %biosequence_ids = $sbeams->selectTwoColumnHash($sql);


  #### Create a hash to store key = value:
  ####    biosequence_name-peptide-peptide_offset = possible_peptide_id
  my %possible_peptide_ids;
  if ($update_existing) {
    $sql = "
          SELECT biosequence_name+'-'+peptide_sequence+'-'+LTRIM(STR(peptide_offset)),
                 possible_peptide_id
            FROM ${DATABASE}possible_peptide PP
            JOIN ${DATABASE}biosequence BS
                 ON ( PP.biosequence_id = BS.biosequence_id )
           WHERE BS.biosequence_set_id = '$biosequence_set_id'
    ";
    %possible_peptide_ids = $sbeams->selectTwoColumnHash($sql);
  }


  #### Definitions for loop
  my ($biosequence_id,$possible_peptide_id,$possible_peptide_key);
  my $counter = 0;
  my ($insert,$update);
  my @columns;

  my ($biosequence_name,$mass,$peptide,$peptide_offset,$preceding_residue);
  my ($following_residue,$n_tryptic_terminii,$is_cysteine_containing);
  my ($isoelectric_point,$elution_index);

  #### Loop over all data in the file
  while ($line=<INFILE>) {

    #### Strip CRs of all flavors
    $line =~ s/[\n\r]//g;

    #### Skip comment lines
    next if (/^#/);

    #### Split the line into its components and extract the data
    @columns = split("\t",$line);
    ($biosequence_name,$mass,$preceding_residue,$peptide,
      $following_residue,$peptide_offset) = @columns;
    $peptide_offset = 0 unless ($peptide_offset);

    ### FIXME: do some field validation here?

    #### If a halt_at specifier was listed, check it and finish when
    if ($halt_at && $biosequence_name =~ /$halt_at/) {
      print "WARNING: Premature stop at $biosequence_name due to ".
        "match with halt_at parameter '$halt_at'\n";
      last;
    }


    #### Calculate some properties of the peptide
    # Trypsin-specific. FIXME: implement for other enzymes?
    $n_tryptic_terminii = 0;
    $n_tryptic_terminii++ if ($preceding_residue =~ /^[KR]$/);
    $n_tryptic_terminii++
      if (substr($peptide,length($peptide)-1,1) =~ /^[KR]$/);
    $is_cysteine_containing = 'N';
    $is_cysteine_containing = 'Y' if ($peptide =~ /C/);
    $isoelectric_point = Proteomics::COMPUTE_PI($peptide,length($peptide),0);
    $elution_index = SBEAMS::Proteomics::Utilities::calcElutionTime(
      peptide=>$peptide,
    );


    #### Determine the biosequence_id
    $biosequence_id = $biosequence_ids{$biosequence_name};
    unless ($biosequence_id) {
      print "ERROR: Unable to resolve biosequence_name '$biosequence_name'. ".
        "Current settings require this.  Cannot continue.\n\n";
      exit;
    }


    #### Add in a hack/check for peptide length
    my $limited_peptide = $peptide;
    if (length($peptide) > 1024) {
      $limited_peptide = substr($peptide,0,1021).'...';
      print "\nWARNING: Truncating peptide in '$biosequence_name'\n";
    }


    #### Split the line into its components and populate attribute hash
    my %rowdata = (
      biosequence_id => $biosequence_id,
      mass => $mass,
      peptide_sequence => $limited_peptide,
      peptide_offset => $peptide_offset,
      preceding_residue => $preceding_residue,
      following_residue => $following_residue,
      n_tryptic_terminii => $n_tryptic_terminii,
      is_cysteine_containing => $is_cysteine_containing,
      is_unique => 'N',
      isoelectric_point => $isoelectric_point,
      elution_index => $elution_index,
    );


    #### If we're updating, then try to find the appropriate record
    $insert = 1; $update = 0;
    $possible_peptide_key = $biosequence_name.'-'.$peptide.'-'.$peptide_offset;
    $possible_peptide_id = $possible_peptide_ids{$possible_peptide_key};
    if ($update_existing) {
      if (defined($possible_peptide_id)) {
        if ($possible_peptide_id > 0) {
          $insert = 0; $update = 1;
        }
      } else {
        print "WARNING: INSERTing instead of UPDATing ".
          "'$possible_peptide_key'\n";
      }

    }


    #### Verify that we haven't done this one already
    if (defined($possible_peptide_id) && $possible_peptide_id == -999) {
      print "\nWARNING: Duplicate possible_peptide_key ".
        "'$possible_peptide_key' in file!  Skipping the duplicate.\n";

    } else {
      #### Insert the data into the database
      loadPossiblePeptide(
        insert=>$insert,
        update=>$update,
        table_name=>"${DATABASE}possible_peptide",
        rowdata_ref=>\%rowdata,
        PK_name=>"possible_peptide_id",
        PK_value => $possible_peptide_id,
      );

      $counter++;
    }


    #### Add this one to the list of already seen
    $possible_peptide_ids{$possible_peptide_key} = -999;


    #### Print some progress feedback for the user
    #last if ($counter > 5);
    print "$counter..." if ($counter % 100 == 0 && !($QUIET));

  }


  close(INFILE);
  print "\n$counter rows INSERT/UPDATed\n";

UNIQUENESSUPDATE:

  print "Updating uniqueness flags...\n";
  $sql = "
	UPDATE ${DATABASE}possible_peptide
	   SET is_unique = 'Y'
	 WHERE possible_peptide_id IN (
		SELECT MAX(possible_peptide_id)
		  FROM ${DATABASE}possible_peptide PP
		  JOIN ${DATABASE}biosequence BS
		       ON ( PP.biosequence_id = BS.biosequence_id )
		 WHERE 1 = 1
		   AND BS.biosequence_set_id = '$biosequence_set_id'
		 GROUP BY peptide_sequence
		HAVING COUNT(*) = 1
	       )
  ";

  $sbeams->executeSQL($sql);
  print "Done.\n\n";


}



###############################################################################
# loadPossiblePeptide
###############################################################################
sub loadPossiblePeptide {
  my %args = @_;
  my $SUB_NAME = "loadPossiblePeptide";

  #### Decode the argument list
  my $insert   = $args{'insert'}   || 0;
  my $update   = $args{'update'}   || 0;
  my $PK_name  = $args{'PK_name'}  || $args{'PK'} || '';
  my $PK_value = $args{'PK_value'} || '';

  my $rowdata_ref = $args{'rowdata_ref'}
    || die "ERROR[$SUB_NAME]: rowdata not passed!";
  my $table_name = $args{'table_name'}
    || die "ERROR[$SUB_NAME]:table_name not passed!";


  #### INSERT/UPDATE the row
  my $result = $sbeams->updateOrInsertRow(insert=>$insert,
					 update=>$update,
					 table_name=>$table_name,
					 rowdata_ref=>$rowdata_ref,
					 PK=>$PK_name,
					 PK_value => $PK_value,
					 verbose=>$VERBOSE,
					 testonly=>$TESTONLY,
					);

  return;

}



