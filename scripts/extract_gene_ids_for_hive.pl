#!/usr/bin/env perl
# $Source: /tmp/ENSCOPY-ENSEMBL-PIPELINE/scripts/extract_gene_ids_for_hive.pl,v $
# $Revision: 1.5 $

# Usage: ./extract_gene_ids_for_hive.pl -analysis_id <number - optional>
#                                       -status <status string - optional> 
#                                       -file <filename - fasta file from blast db>
#                                       > <output file>

use warnings ;
use strict;
use Getopt::Long qw(:config no_ignore_case);

my ($analysis_id, $status, $filename);

GetOptions("-analysis_id" => \$analysis_id,
	   "-status=s"    => \$status,
	   "-file=s"      => \$filename);

unless (defined $filename && $filename ne ''){
  print STDERR join ("\n", 
		     "Command-line options : ",
		     "-file          input file (required)",
		     "-status        hive status (optional - default is READY)",
		     "-analysis_id   hive analysis id (optional - default 1)",
		     "Output is written to STDOUT, so you might like to ",
		     "redirect it to a file.") . "\n";
  die "Command line options not specified."
}

$analysis_id = 1 unless $analysis_id;
$status = 'READY' unless $status;

$status = uc($status);

open(IN, $filename) or die "Unable to find or open [$filename]";

while (<IN>) {
  if (/>(\S+)/) {
    print STDOUT join("\t", ('','',$analysis_id,$1,'','',$status,'','','','','')) . "\n";
  }
}

close(IN);
