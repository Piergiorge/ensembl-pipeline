#!/usr/local/ensembl/bin/perl -w

#this is a copy of sections of /ensembl-compara/scripts/taxonomy/taxonTreeTool.pl
#uses -dbname style commands 

#example commands:
#perl load_taxonomy.pl -taxon_id 9606 -taxondbhost ecs2 -taxondbport 3365 \
#-taxondbname ncbi_taxonomy

#perl load_taxonomy.pl -name "Echinops telfairi" -taxondbhost ecs2 -taxondbport 3365 -taxondbname \
#ncbi_taxonomy -lcdbhost ia64g -lcdbport 3306 -lcdbname sd3_tenrec_1_ref -lcdbuser ensadmin \
#-lcdbpass ****

use strict;
use Switch;
use Getopt::Long;
use Bio::EnsEMBL::Compara::DBSQL::DBAdaptor;

$| = 1;

# pretending I've got an object here
# by creating a blessed hash ref and passing it around like an object
# this is to avoid using global variables in functions, and to consolidate
# the globals into a nice '$self' package
my $self = bless {};

$self->{'scale'} = 10;

my ($help, $taxondbhost, $taxondbport, $taxondbname);
my ($lcdbhost, $lcdbport, $lcdbname, $lcdbuser, $lcdbpass);


GetOptions('help'           => \$help,
           'taxon_id=i'     => \$self->{'taxon_id'},
           'name=s'         => \$self->{'scientific_name'},
           'taxondbhost=s'  => \$taxondbhost,
           'taxondbport=s'  => \$taxondbport,
           'taxondbname=s'  => \$taxondbname,
           'dbhost|lcdbhost=s'     => \$lcdbhost,
           'dbport|lcdbport=s'     => \$lcdbport,
           'dbname|lcdbname=s'     => \$lcdbname,
           'dbuser|lcdbuser=s'     => \$lcdbuser,
	   'dbpass|lcdbpass=s'     => \$lcdbpass,
          );


#No test for lcdbname which cause other opts to get eaten!

my $state;
if($self->{'taxon_id'}) { $state = 1; }
if($self->{'scientific_name'}) { $state = 2; }
if($self->{'taxon_id'} && $lcdbname) { $state = 3; };
if($self->{'scientific_name'} && $lcdbname) { $state = 3; };

if ($self->{'taxon_id'} && $self->{'scientific_name'}) {
  print "You can't use -taxon_id and -name together. Use one or the other.\n\n";
  exit 3;
}

if ($help or !$state) { usage(); }


my $taxon_dbc     = connect_db($taxondbhost, $taxondbport, $taxondbname, "ensro");
my $lc_dbc;
if (defined $lcdbname){
	$lc_dbc = 	connect_db($lcdbhost, $lcdbport, $lcdbname, $lcdbuser, $lcdbpass);
}


Bio::EnsEMBL::Registry->no_version_check(1);

switch($state) {
  case 1 { fetch_by_ncbi_taxon_id($self); }
  case 2 { fetch_by_scientific_name($self); }
  case 3 { load_taxonomy_in_core($self); }
}


#cleanup memory
if($self->{'root'}) {
#  print("ABOUT TO MANUALLY release tree\n");
  $self->{'root'}->release_tree;
  $self->{'root'} = undef;
#  print("DONE\n");
}

exit(0);


#######################
#
# subroutines
#
#######################

sub usage {
  print "load_taxonomy.pl [options]\n";
  print "  -help                  : print this help\n";
  print "  -taxondbhost host -taxondbport port -taxondbname dbname\n";
  print "                         : connect to taxonomy database\n";
  print "  -taxon_id <int>        : print classification by taxon_id\n";
  print "  -name <string>         : print classification by scientific name e.g. \"Homo sapiens\"\n";
  print "  -lcdbhost host -lcdbport port -lcdbname dbname -lcdbuser user -lcdbpass passwd\n";
  print "                         : the low coverage database for which you want to update the taxonomy information in the meta table\n ";  
  print "                          to be used with -taxon_id or -name\n";
  print "load_taxonomy.pl v1.1\n";

  exit(1);
}

sub fetch_by_ncbi_taxon_id {
  my $self = shift;
  my $taxonDBA = $taxon_dbc->get_NCBITaxonAdaptor;
  my $node = $taxonDBA->fetch_node_by_taxon_id($self->{'taxon_id'});
  $node->no_autoload_children;
  my $root = $node->root;
  
#  $root->print_tree($self->{'scale'});
  if ($node->rank eq 'species') {
  #if ($node->rank eq 'species' || $node->rank eq 'subspecies') {
    print "classification: ",$node->classification,"\n";
    print "scientific name: ",$node->binomial,"\n";
    if (defined $node->common_name) {
      print "common name: ",$node->common_name,"\n";
    } else {
      print "no common name\n";
    }
  }
  $self->{'root'} = $root;
}

sub fetch_by_scientific_name {
  my $self = shift;
  my $taxonDBA = $taxon_dbc->get_NCBITaxonAdaptor;
  my $node = $taxonDBA->fetch_node_by_name($self->{'scientific_name'});
  $node->no_autoload_children;
  my $root = $node->root;

#  $root->print_tree($self->{'scale'});
  if ($node->rank eq 'species') {
    print "classification: ",$node->classification,"\n";
    print "scientific name: ",$node->binomial,"\n";
    if (defined $node->common_name) {
      print "common name: ",$node->common_name,"\n";
    } else {
      print "no common name\n";
    }
  }
  $self->{'root'} = $root;
}

sub load_taxonomy_in_core {
  my $self = shift;
  my $taxonDBA = $taxon_dbc->get_NCBITaxonAdaptor;
  my $node;
  if (defined $self->{'taxon_id'}) {
    $node = $taxonDBA->fetch_node_by_taxon_id($self->{'taxon_id'});
  } else {
    $node = $taxonDBA->fetch_node_by_name($self->{'scientific_name'});
  }

  my $match_rank = ($node->name eq 'Canis familiaris') ? 'subspecies' : 'species';
#  my $match_rank;
#  if ($node->name eq 'Canis familiaris' ||
#      $node->name eq 'Gorilla gorilla gorilla' ||
#      $node->name eq 'Mustela putorius furo' 
#     ) {
#    $match_rank = 'subspecies';
#  } else {
#    $match_rank = 'species';
#  }

  if($node->rank ne $match_rank){
      print "ERROR: taxon_id=",$self->{'taxon_id'},", '",$node->name,"' is rank '",$node->rank,"'.\n";
      print "It is not a rank 'species' (subspecies for dog). So it can't be loaded.\n\n";
    exit 2;
  }



  $node->no_autoload_children;
  my $root = $node->root;

  my $mc = $lc_dbc->get_MetaContainer;
  $mc->delete_key('species.classification');
  $mc->delete_key('species.common_name');
  $mc->delete_key('species.taxonomy_id');
  $mc->delete_key('species.ensembl_common_name');
  $mc->delete_key('species.ensembl_alias_name');
  print "Loading species.taxonomy_id = ",$node->node_id,"\n";
  $mc->store_key_value('species.taxonomy_id',$node->node_id);
  if (defined $node->common_name) {
    $mc->store_key_value('species.common_name',$node->common_name);
    print "Loading species.common_name = ",$node->common_name,"\n";
  }
  if (defined $node->has_tag('ensembl common name')) {
    $mc->store_key_value('species.ensembl_common_name',$node->get_tagvalue('ensembl common name'));
    print "Loading species.ensembl_common_name = ",$node->get_tagvalue('ensembl common name'),"\n";
  }
  if (defined $node->has_tag('ensembl alias name')) {
    $mc->store_key_value('species.ensembl_alias_name',$node->get_tagvalue('ensembl alias name'));
    print "Loading species.ensembl_alias_name = ",$node->get_tagvalue('ensembl alias name'),"\n";
  }
  if (defined $node->has_tag('genbank common name')) {
    print "Found species.genbank_common_name = ",$node->get_tagvalue('genbank common name'),"\n";
  }
  if (defined $node->has_tag('scientific name')) {
    print "Found species.scientific_name = ",$node->get_tagvalue('scientific name'),"\n";
  }
  if (defined $node->has_tag('common name')) {
    print "Found species.common_name = ",join (',',@{$node->get_tagvalue('common name')}),"\n";
  }
  if (defined $node->has_tag('misspelling')) {
    print "Found species.alias = ",$node->get_tagvalue('misspelling'),"\n";
  }
  if (defined $node->has_tag('synonym')) {
    print "Found species.synonym = ",$node->get_tagvalue('synonym'),"\n";
  }

  # It is possible to remove the subspecies from the full species.classification list by commenting out the following line in 
  #ensembl-compara/modules/Bio/EnsEMBL/Compara/NCBITaxon.pm
  #sub _to_text_classification : 
  # unshift @text_classification, $subspecies if (defined $subspecies);
  my @classification = split(",",$node->classification(",", 1));
  LEVEL: foreach my $level (@classification) {
    print "Loading species.classification = ",$level,"\n";
    next LEVEL if ($level =~ /\s+/);
    $mc->store_key_value('species.classification',$level);
  }
  $self->{'root'} = $root;
}

sub connect_db{
  my $host       = shift;
  my $port       = shift;
  my $dbname     = shift;
  my $user       = shift;
  my $pass       = shift;
  my $dbObj;

  if($pass){
	$dbObj      = new Bio::EnsEMBL::Compara::DBSQL::DBAdaptor(
						     -host   => $host,
						     -port   => $port,
						     -user   => $user,
						     -dbname => $dbname,
						     -pass  => $pass
						    );
  }else{
	$dbObj      = new Bio::EnsEMBL::Compara::DBSQL::DBAdaptor(
							 -host    => $host,
							 -port    => $port,
							 -user    => $user,
							 -dbname  => $dbname
							);
  }
  if(!$dbObj){
    die "\ncould not connect to \"$dbname\".\n";
  }
  return $dbObj;
}
