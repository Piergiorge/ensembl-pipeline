=pod

=head1 NAME
  
Bio::EnsEMBL::Pipeline::Runnable::GeneWise - aligns protein hits to genomic sequence

=head1 SYNOPSIS

    # Initialise the genewise module  
    my $genewise = new  Bio::EnsEMBL::Pipeline::Runnable::Genewise  ('genomic'  => $genomic,
								       'protein'  => $protein,
								       'memory'   => $memory);


   $genewise->run;
    
   my @genes = $blastwise->output

=head1 DESCRIPTION


=head1 CONTACT

Describe contact details here

=head1 APPENDIX

The rest of the documentation details each of the object methods. Internal methods are usually preceded with a _

=cut

package Bio::EnsEMBL::Pipeline::Runnable::Genewise;

use strict;  
use vars   qw(@ISA);

# Object preamble

use Bio::EnsEMBL::Root;
use Bio::EnsEMBL::Analysis::Programs qw(genewise); 
use Bio::EnsEMBL::SeqFeature;
use Bio::EnsEMBL::FeaturePair;
use Bio::EnsEMBL::Pipeline::RunnableI;
use Bio::SeqIO;
@ISA = qw(Bio::EnsEMBL::Pipeline::RunnableI);

sub new {
  my($class,@args) = @_;
  my $self = $class->SUPER::new(@args);
  
  my ($genomic, $protein, $memory,$reverse,$endbias,$genewise) = 
      $self->_rearrange([qw(GENOMIC PROTEIN MEMORY REVERSE ENDBIAS GENEWISE)], @args);
  
#  print $genomic . "\n";

  $genewise = 'genewise' unless defined($genewise);

  $self->genewise($self->find_executable($genewise));

  $self->genomic($genomic) || $self->throw("No genomic sequence entered for blastwise");
  $self->protein($protein) || $self->throw("No protein sequence entered for blastwise");

  $self->reverse($reverse)   if (defined($reverse));             
  $self->endbias($endbias)   if (defined($endbias));             
  $self->memory ($memory)    if (defined($memory));

  return $self;
}

sub genewise {
  my ($self,$arg) = @_;

  if (defined($arg)) {
    $self->{_genewise} = $arg;
  }
  return $self->{_genewise};
}

# RunnableI methods

sub run {
    my ($self) = @_;

    $self->_wise_init;
    $self->_align_protein;
}

sub output {
    my ($self) = @_;

#    return $self->eachGene;
    return $self->eachExon;
}

# Now the blastwise stuff

sub set_environment {
  my ($self) = @_;
  
  if (! -d $ENV{WISECONFIGDIR}) {
    $self->throw("No WISECONFIGDIR ["  . $ENV{WISECONFIGDIR} . "]");
  }
}

sub _wise_init {
  my($self,$genefile) = @_;

#  print("Initializing genewise\n");

  $self->set_environment;

}


=pod

=head2 _align_protein

  Title   : _align_protein
  Usage   : $bw->align_protein($pro,$start,$end)
  Function: aligns a protein to a genomic sequence between the genomic coords $start,$end
  Returns : nothing
  Args    : Bio:Seq,int,int

=cut


sub _align_protein {
  my ($self) = @_;
  my $memory   = $self->memory;
  
  my $gwfile   = "/tmp/gw." . $$ . ".out";
  my $genfile  = "/tmp/gw." . $$ . "." . $self->protein->id . ".gen.fa";
  my $protfile = "/tmp/gw." . $$ . "." . $self->protein->id . ".pro.fa";
  
  my $genio  = new Bio::SeqIO(-file   => ">$genfile",
			      '-format' => 'fasta');
  my $verbose = 0;
  #if($self->protein->id eq 'CE25688'){
  #  $verbose = 1;
  #}
  $genio->write_seq($self->genomic);
  $genio = undef;
  
  my $proio  = new Bio::SeqIO(-file   => ">$protfile",
			      '-format' => 'fasta');
  
  $proio->write_seq($self->protein);
  $proio = undef;

  my $genewise = $self->genewise;
#  my $command = "/nfs/acari/birney/wise2-bin-snapshot/genewise $protfile $genfile -genesf -kbyte $memory -ext 2 -gap 12 -subs 0.0000001 -quiet";
  my $command = "$genewise $protfile $genfile -genesf -kbyte $memory -ext 2 -gap 12 -subs 0.0000001 -quiet";
    
  if ($self->endbias == 1) {
    $command .= " -init endbias -splice flat ";
  }
  
  if ($self->reverse == 1) {
    $command .= " -trev ";
  }
  
  #print STDERR "Command is $command\n";
  
  open(GW, "$command |") or $self->throw("error piping to genewise: $!\n");
  #open(GW, "$command | tee -a /tmp/genewise.out |") or $self->throw("error piping to genewise: $!\n");
  # for genesf parsing
  my @genesf_exons;
  my $curr_exon;
  my $curr_gene;
  # making assumption of only 1 gene prediction ... this will change once we start using hmms

  #print STDERR "################# GENEWISE ####################\n";
 GENESF: 
  while (<GW>) {
    
#    print STDERR "$_";
   
    chomp;
    my @f = split;
   
    #if ( $f[0] =~/Protein/ ){
    #  print STDERR $_."\n";
    #}
 
    next unless (defined $f[0] && ($f[0] eq 'Gene' || $f[0] eq 'Exon' || $f[0] eq 'Supporting'));
    
    #print STDERR $_."\n";
    if($f[0] eq 'Gene'){
      #print STDERR "$_" if($verbose);
      # flag a frameshift - ultimately we will do something clever here but for now ...
      
      # frameshift is here defined as two or more genes produced by Genewise from a single protein
      if (/^(Gene\s+\d+)$/){
	if(!defined($curr_gene)){
	  $curr_gene = $1;
	}
	elsif($1 ne $curr_gene){
	  $self->warn("frameshift!\n");
	}
      }
    }
    
    elsif($f[0] eq 'Exon'){
      #print STDERR "$_" if($verbose);
      #      make a new "exon"
      $curr_exon = new Bio::EnsEMBL::SeqFeature;
      $curr_exon->seqname  ($self->genomic->id);
      $curr_exon->id        ($self->protein->id);

      #print STDERR "setting phase to $f[4]\n";
      my $phase = $f[4];
      $curr_exon->phase($phase);
      
      my $start  = $f[1];
      my $end    = $f[2];
      my $strand = 1;
      if($f[1] > $f[2]){
	$strand = -1;
	$start  = $f[2];
	$end    = $f[1];
      }
      # end phase is the number of bases at the end of the exon which do not 
      # fall in a codon and it coincides with the phase of the following exon.
      my $exon_length = $end - $start + 1;
      my $end_phase   = ( $exon_length + $curr_exon->phase ) %3;
      #print STDERR "setting end_phase to $end_phase\n";
      $curr_exon->end_phase($end_phase);

      $curr_exon->start($start);
      $curr_exon->end($end);
      $curr_exon->strand($strand);

      $self->addExon($curr_exon);
      push(@genesf_exons, $curr_exon);
    
      #print STDERR "Exon: ".$start."-".$end." phase: ".$phase." end_phase: ".$end_phase." str: ".$strand."\n" if($verbose);
    }
    
    elsif($f[0] eq 'Supporting'){
      #print STDERR "$_" if($verbose);
      my $gstart = $f[1];
      my $gend   = $f[2];
      my $strand = 1;
      if ($gstart > $gend){
	$gstart = $f[2];
	$gend = $f[1];
	$strand = -1;
      }
      
      # check strand sanity
      if($strand != $curr_exon->strand){
	$self->warn("incompatible strands between exon and supporting feature - cannot add suppfeat\n");
	next GENESF;
      }

      my $pstart = $f[3];
      my $pend   = $f[4];
      #print STDERR "Supporting start ".$gstart. " end ".$gend." hstart ".$pstart." hend ".$pend."\n" if($verbose); 
      if($pstart > $pend){
	$self->warn("Protein start greater than end! Skipping this suppfeat\n");
	next GENESF;
      }
      
      # start a new "alignment"
      my $fp = new Bio::EnsEMBL::FeaturePair();
      $fp->start($gstart);
      $fp->end($gend);
      $fp->strand($strand);
      $fp->seqname('genomic');
      $fp->hseqname($self->protein->id);
      $fp->hstart($pstart);
      $fp->hend($pend);
      $fp->hstrand(1);
      $curr_exon->add_sub_SeqFeature($fp,'');
    }
    
  } 
  
  close(GW) or $self->throw("Error running genewise:$!\n");
  
  

  unlink $genfile;
  unlink $protfile;
  unlink $gwfile;
}


# These all set/get or initializing methods

sub reverse {
    my ($self,$arg) = @_;

    if (defined($arg)) {
	$self->{'_reverse'} = $arg;
    }
    return $self->{'_reverse'};
}

sub endbias {
    my ($self,$arg) = @_;

    if (defined($arg)) {
	$self->{'_endbias'} = $arg;
    }

    if (!defined($self->{'_endbias'})) {
      $self->{'_endbias'} = 0;
    }

    return $self->{'_endbias'};
}

sub memory {
    my ($self,$arg) = @_;

    if (defined($arg)) {
	$self->{'_memory'} = $arg;
    }

    return $self->{'_memory'} || 100000;
}

sub genomic {
    my ($self,$arg) = @_;

    if (defined($arg)) {
	$self->throw("Genomic sequence input is not a Bio::SeqI or Bio::Seq or Bio::PrimarySeqI") unless
	    ($arg->isa("Bio::SeqI") || 
	     $arg->isa("Bio::Seq")  || 
	     $arg->isa("Bio::PrimarySeqI"));
		
	
	$self->{'_genomic'} = $arg;
    }
    return $self->{'_genomic'};
}

sub protein {
    my ($self,$arg) = @_;

    if (defined($arg)) {
	$self->throw("[$arg] is not a Bio::SeqI or Bio::Seq or Bio::PrimarySeqI") unless
	    ($arg->isa("Bio::SeqI") || 
	     $arg->isa("Bio::Seq")  || 
	     $arg->isa("Bio::PrimarySeqI"));

	$self->{'_protein'} = $arg;


    }
    return $self->{'_protein'};
}

#sub addGene {
#    my ($self,$arg) = @_;

#    if (!defined($self->{'_output'})) {
#	$self->{'_output'} = [];
#    }
#    push(@{$self->{'_output'}},$arg);

#}

#sub eachGene {
#    my ($self) = @_;

#    if (!defined($self->{'_output'})) {
#	$self->{'_output'} = [];
#    }

#    return @{$self->{'_output'}};
#}

sub addExon {
    my ($self,$arg) = @_;

    if (!defined($self->{'_output'})) {
	$self->{'_output'} = [];
    }
    push(@{$self->{'_output'}},$arg);

}

sub eachExon {
    my ($self) = @_;

    if (!defined($self->{'_output'})) {
	$self->{'_output'} = [];
    }
    #   print "there are ".@{$self->{'_output'}}." genes\n";
    #   foreach my $gene(@{$self->{'_output'}}){
    #     print "gene has ".$gene->sub_SeqFeature." exon\n";
    #     foreach my $e($gene->sub_SeqFeature){
    #	print "exon has ".$e->sub_SeqFeature." supporting features\n";
    #  }
    #}
    return @{$self->{'_output'}};
}

1;
