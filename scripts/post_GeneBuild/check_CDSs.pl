#!/usr/local/ensembl/bin/perl -w

=head1 NAME

=head1 DESCRIPTION

script to check whether CDSs starts with ATG and end with stop (TAA|TGA|TAG)\n

=head1 OPTIONS

=cut

use strict;

use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::SeqIO;
use Getopt::Long;
use Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils;


my $dbhost;
my $dbuser    = 'ensro';
my $dbname;
my $dbpass    = undef;

my $dnadbhost;
my $dnadbuser = 'ensro';
my $dnadbname;
my $dnadbpass = undef;

my $genetype;

my $filter;

&GetOptions(
	    'dbname:s'    => \$dbname,
	    'dbhost:s'    => \$dbhost,
	    'dnadbname:s' => \$dnadbname,
	    'dnadbhost:s' => \$dnadbhost,
	    'filter:s'    =>  \$filter,
	    'genetype:s'   => \$genetype,
	   );

unless ( $dbname && $dbhost ){
  print STDERR "script to check whether CDSs starts with ATG and end with stop (TAA|TGA|TAG)\n";
 
  print STDERR "Usage: $0 -dbname -dbhost -dnadbname -dnadbhost\n";
  print STDERR "Optional: -genetype\n";
  exit(0);
}

my %filter_gene;
if ( $filter ){
  open ( IN, "<$filter" ) or die("cannot open file $filter");
  
  while(<IN>){
    chomp;
    my @entries = split;
    $filter_gene{ $entries[0] } = $entries[0];
  }
}

my $dnadb;
if($dnadbhost && $dnadbuser){
  $dnadb = new Bio::EnsEMBL::DBSQL::DBAdaptor(
					      '-host'   => $dnadbhost,
					      '-user'   => $dbuser,
					      '-dbname' => $dnadbname,
					      '-pass'   => $dbpass,
					     );
}




my $db = new Bio::EnsEMBL::DBSQL::DBAdaptor(
					    '-host'   => $dbhost,
					    '-user'   => $dbuser,
					    '-dbname' => $dbname,
					    '-pass'   => $dbpass,
					   );

$db->dnadb($dnadb) if($dnadb);
print STDERR "connected to $dbname : $dbhost\n";
print STDERR "dnadb not defined are you sure your database contains dna\n";



my  @ids = @{$db->get_GeneAdaptor->list_geneIds};

my $start_correct = 0;
my $stop_correct  = 0;
my $both_correct  = 0;

GENE:
foreach my $gene_id(@ids) {
  
  my $gene = $db->get_GeneAdaptor->fetch_by_dbID($gene_id,1);
  if ($genetype){
    next GENE unless ( $gene->type eq $genetype );
  }
  
  if ($filter){
    if ( $filter_gene{$gene->stable_id} ){
      print STDERR "filtering out ".$gene->stable_id."\n";
      next GENE;
    }
  }

  my $chr = $gene->chr_name;

 TRANS:
  foreach my $trans ( @{$gene->get_all_Transcripts} ) {
    my $gene_id = $gene->stable_id || $gene->dbID;
    my $tran_id = $trans->stable_id || $trans->dbID;
    
    my $strand = $trans->start_Exon->strand;
    my ($start,$end);
    my @exons;
    
    if ( $strand == 1 ){
      eval{
	@exons = sort {$a->start <=> $b->end} @{$trans->get_all_translateable_Exons};
      };
      if ( $@ ){
	print STDERR "$@\n";
      }
      next TRANS unless ( @exons );
      $start = $exons[0]->start;
      $end   = $exons[$#exons]->end;
    }
    else{
      eval{
	@exons = sort {$b->start <=> $a->end} @{$trans->get_all_translateable_Exons};
      };
      if ( $@ ){
	print STDERR "$@\n";
      }
      next TRANS unless ( @exons );
      $start = $exons[0]->end;
      $end   = $exons[$#exons]->start;
    }
    
    eval {      
      my $seq;
      foreach my $exon ( @exons ){
	$seq .= $exon->seq->seq;
      }
      my $first_codon = substr( $seq, 0, 3 );
      my $last_codon  = substr( $seq, -3 );
      
      my $start = 0;
      my $end   = 0;
      if ( uc($first_codon) eq 'ATG' ){
	$start_correct++;
	$start =1 ;
      }
      if ( uc($last_codon) eq 'TAA' || uc($last_codon) eq 'TAG' || uc($last_codon) eq 'TGA' ){ 
	$stop_correct++;
	$end = 1;
      }
      if ( $start && $end ){
	$both_correct++;
      }
      
      print "$gene_id $tran_id start:$start stop:$end\n";
      
      #my $tseq = $trans->translate();
      #if ( $tseq->seq =~ /\*/ ) {
      #	print STDERR "translation of ".$trans->dbID." has stop codons. Skipping!\n";
      #	Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_print_Evidence($trans);
      #	next TRANS;
      #      }
      #my $tran_seq = Bio::Seq->new();
      #$tran_seq->seq($seq);
      #$tran_seq->display_id("Gene:$gene_id Transcript:$tran_id CODING SEQUENCE");
      #$tran_seq->desc("HMM:@evidence Chr:$chr Strand:$strand Start:$start End:$end");
      #my $result = $seqio->write_seq($tran_seq);
    };
    if( $@ ) {
      print STDERR "unable to process transcript $tran_id, due to \n$@\n";
    }
  }
}

print "start codons correct: $start_correct\n";
print "stop codons correct : $stop_correct\n";
print "both correct        : $both_correct\n";



sub get_evidence{
  my ($trans) = @_;
  my %evi;
  foreach my $exon (@{$trans->get_all_Exons}){
    foreach my $evidence ( @{$exon->get_all_supporting_features} ){
      $evi{$evidence->hseqname}++;
   }
  }
  return keys %evi;
}
