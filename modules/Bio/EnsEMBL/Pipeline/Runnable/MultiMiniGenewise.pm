#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=pod 

=head1 NAME

Bio::EnsEMBL::Pipeline::Runnable::MultiMiniGenewise

=head1 SYNOPSIS

    my $obj = Bio::EnsEMBL::Pipeline::Runnable::MultiMiniGenewise->new(-genomic  => $genseq,
								  -features => $features)

    $obj->run

    my @newfeatures = $obj->output;


=head1 DESCRIPTION

=head1 CONTACT

Describe contact details here

=head1 APPENDIX

The rest of the documentation details each of the object methods. 
Internal methods are usually preceded with a _

=cut

# Let the code begin...

package Bio::EnsEMBL::Pipeline::Runnable::MultiMiniGenewise;

use vars qw(@ISA);
use strict;

use Bio::EnsEMBL::Pipeline::Runnable::MiniGenewise;

@ISA = qw(Bio::EnsEMBL::Pipeline::RunnableI );

sub new {
    my ($class,@args) = @_;
    my $self = $class->SUPER::new(@_);    
           
    my( $genomic, $features,$seqfetcher, $endbias) = 
      $self->_rearrange([qw(GENOMIC
			    FEATURES
			    SEQFETCHER
			    ENDBIAS
			   )],
			@args);


    $self->throw("No genomic sequence input")                     unless defined($genomic);
    $self->throw("No seqfetcher provided")                        unless defined($seqfetcher);
    $self->throw("No features input")                             unless defined($features);
    
    $self->throw("[$genomic] is not a Bio::PrimarySeqI")          unless $genomic->isa("Bio::PrimarySeqI");
    $self->throw("[$seqfetcher] is not a Bio::DB::RandomAccessI") unless $seqfetcher->isa("Bio::DB::RandomAccessI");
    
    $self->genomic_sequence($genomic) if defined($genomic);
    $self->seqfetcher($seqfetcher)    if defined($seqfetcher);
    $self->endbias($endbias)          if defined($endbias);
    $self->features($features)        if defined($features);
    
    return $self;
  }

sub features {
  my ($self,$features) = @_;
  
  if (!defined($self->{_features})) {
    $self->{_features} = [];
  }
  if (defined($features)) {
    if (ref($features) eq "ARRAY") {
      foreach my $f (@$features) {
	if ($f->isa("Bio::EnsEMBL::FeaturePair")) {
	  push(@{$self->{_features}},$f);
	} else {
	  $self->throw("Object [$f] is not a Bio::EnsEMBL::FeaturePair");
	}
      }
    } else {
      $self->throw("[$features] is not an array ref.");
    }
  }
  return $self->{_features};
}

=head2 genomic_sequence

Title   :   genomic_sequence
  Usage   :   $self->genomic_sequence($seq)
 Function:   Get/set method for genomic sequence
  Returns :   Bio::Seq object
  Args    :   Bio::Seq object

=cut
  
sub genomic_sequence {
    my( $self, $value ) = @_;    
    if ($value) {
      #need to check if passed sequence is Bio::Seq object
      $value->isa("Bio::PrimarySeqI") || $self->throw("Input isn't a Bio::PrimarySeqI");
      $self->{'_genomic_sequence'} = $value;
    }
    return $self->{'_genomic_sequence'};
  }

=head2 endbias

  Title   :   endbias
    Usage   :   $self->endbias($endbias)
  Function:   Get/set method for endbias
    Returns :   
    Args    :   

=cut
    
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

=head2 seqfetcher

    Title   :   seqfetcher
    Usage   :   $self->seqfetcher($seqfetcher)
    Function:   Get/set method for SeqFetcher
    Returns :   Bio::DB::RandomAccessI object
    Args    :   Bio::DB::RandomAccessI object

=cut

sub seqfetcher {

  my( $self, $value ) = @_;    
  
  if (defined($value)) {
    #need to check if we are being passed a Bio::DB::RandomAccessI object
    $self->throw("[$value] is not a Bio::DB::RandomAccessI") unless $value->isa("Bio::DB::RandomAccessI");
    $self->{'_seqfetcher'} = $value;
  }
  return $self->{'_seqfetcher'};
}



=head2 get_all_features_by_id

    Title   :   get_all_features_by_id
    Usage   :   $hash = $self->get_all_features_by_id;
    Function:   Returns a ref to a hash of features.
                The keys to the hash are distinct feature ids
    Returns :   ref to hash of Bio::EnsEMBL::FeaturePair
    Args    :   none

=cut

sub get_all_features_by_id {
    my( $self) = @_;
    
    my  %idhash;
    my  %scorehash;
    
  FEAT: foreach my $f (@{$self->features}) {
      if (!(defined($f->hseqname))) {
	$self->warn("No hit name for " . $f->seqname . "\n");
	next FEAT;
      } 
      if (defined($idhash{$f->hseqname})) {
	push(@{$idhash{$f->hseqname}},$f);
      } else {
	$idhash{$f->hseqname} = [];
	push(@{$idhash{$f->hseqname}},$f);
      }
      if (defined($scorehash{$f->hseqname})) {
	if ($f->score > $scorehash{$f->hseqname}) {
	  $scorehash{$f->hseqname} = $f->score;
	}
      } else {
	$scorehash{$f->hseqname} = $f->score;
      }
    }
    
    my @sorted_ids = keys %idhash;
    
    @sorted_ids = sort {$scorehash{$a} <=> $scorehash{$b}} @sorted_ids;
    
    return (\%idhash,\@sorted_ids);
  }


=head2 get_all_feature_ids

  Title   : get_all_feature_ids
  Usage   : my @ids = get_all_feature_ids
  Function: Returns an array of all distinct feature hids 
  Returns : @string
  Args    : none

=cut

sub get_all_feature_ids {
  my ($self) = @_;
  
  my ($idhash,$idref) = $self->get_all_FeaturesById;
  
  return @$idref;
  
}

=head2 get_Sequence

  Title   : get_Sequence
  Usage   : my $seq = get_Sequence($id)
  Function: Fetches sequences with id $id
  Returns : Bio::PrimarySeq
  Args    : none

=cut

sub get_Sequence {
  my ($self,$id) = @_;
  
  if (defined($self->{'_seq_cache'}{$id})) {
    return $self->{'_seq_cache'}{$id};
  } 
  
  my $seqfetcher = $self->seqfetcher;    
  
  my $seq;
  
  eval {
    $seq = $seqfetcher->get_Seq_by_acc($id);
  };
  
  if ($@) {
    $self->throw("Problem fetching sequence for [$id]: [$@]\n");
  }
  return $seq;
}

=head2 run

  Title   : run
  Usage   : $self->run
  Function: 
  Returns : none
  Args    : 

=cut

sub run {
  my ($self) = @_;

  my ($fhash,$ids) = $self->get_all_features_by_id;
  
  foreach my $id (@$ids) {
    print "Processing $id\n";
    
    my @features = @{$fhash->{$id}};
    my @extras   = $self->_find_extras (@features);
    
    if (scalar(@extras) > 0) {
      my $pepseq = $self->get_Sequence($features[0]->hseqname);
      
      if (defined($pepseq)) {
	my $runnable  = new Bio::EnsEMBL::Pipeline::Runnable::MiniGenewise(
									   -genomic => $self->genomic_sequence,
									   -protein => $pepseq,
									   -features=> \@features,
									   -endbias => $self->endbias);
	
	$runnable->run;
	print "Runnable output " . $runnable->output . "\n";
	
	push(@{$self->{_output}},$runnable->output);
	
      } else {
	$self->throw("Can't fetch sequence for " . $features[0]->hseqname . "\n");
      }
    } else {
      print "No extra features - skipping " . $features[0]->hseqname . "\n";
    }
  }
  return 1;
}

sub _find_extras {
  my ($self,@features) = @_;
  
  my @output = $self->output;
  my @new;
  
 FEAT: 
  foreach my $f (@features) {
    
    my $found = 0;

    # does this need to be hardcoded?
    # smaller for virgin genomes?
    if (($f->end - $f->start) < 50) {
      next FEAT;
    }      
    
    foreach my $out (@output) {
      foreach my $sf ($out->sub_SeqFeature) {
	if ($f->overlaps($sf)) {
	  $found = 1;
	}
      }
    }
    
    if ($found == 0) {
      push(@new,$f);
    }
  }
  return @new;
}

1;

