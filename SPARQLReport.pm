package SPARQLReport;

use strict;
use warnings;
use v5.12;

use File::Spec;
use RDF::Redland;
use RDF::Trine qw(iri);
use RDF::Trine::Namespace qw(foaf rdfs);
use RDF::Query;
use RDF::Trine::Error qw(:try);
use Scalar::Util qw(blessed);
use HTML::Entities;

my $manifestbase	= 'http://www.w3.org/2009/sparql/docs/tests/data-sparql11';
my $doap			= RDF::Trine::Namespace->new( 'http://usefulinc.com/ns/doap#' );
my $mf				= RDF::Trine::Namespace->new( 'http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#' );
my $dt				= RDF::Trine::Namespace->new( 'http://www.w3.org/2001/sw/DataAccess/tests/test-dawg#' );

sub new {
	my $class			= shift;
	my $sources			= shift || [];
	my $manifestdir		= shift;
	my $self			= bless({ sources => $sources, manifestdir => $manifestdir }, $class);
	my $store			= RDF::Trine::Store::DBI::SQLite->new('model', 'dbi:SQLite:dbname=sparql.sqlite', '', '');
	$self->{model}		= RDF::Trine::Model->new( $store );
	return $self;
}

sub sources {
	my $self	= shift;
	return @{ $self->{ sources } };
}

sub model {
	my $self	= shift;
	return $self->{model};
}

sub manifestdir {
	my $self	= shift;
	return $self->{manifestdir};
}

sub load_data {
	my $self	= shift;
	my $model			= $self->model;
	my $parser			= RDF::Trine::Parser->new('turtle');
	
	my $man				= File::Spec->catfile( $self->manifestdir, 'manifest-all.ttl' );
	for my $f ($man) {
		warn "# loading $f\n";
		try {
			my $base	= join('/', $manifestbase, 'manifest-all.ttl');
			$parser->parse_file_into_model( $base, $f, $model, context => iri('http://myrdf.us/ns/sparql/Manifests') );
		} catch Error with {
			my $e	= shift;
		};
	}
	
	$self->get_manifests();
	$self->load_manifest_data;
	$self->load_source_data;
	$self->get_software();
	$self->get_test_status();
	$self->get_test_results();
}

sub load_manifest_data {
	my $self	= shift;
	my $model	= $self->model;
	my $parser			= RDF::Trine::Parser->new('turtle');
	foreach my $f ($self->manifests) {
		try {
			my ($dir)	= ($f =~ m{([^/]+)/manifest.ttl});
			my $base	= join('/', $manifestbase, $dir, 'manifest.ttl' );
			my $file	= File::Spec->catfile( $self->manifestdir, $f );
			warn "# loading $file with base $base\n";
			$parser->parse_file_into_model( $base, $file, $model, context => iri('http://myrdf.us/ns/sparql/Manifests') );
		} catch Error with {
			my $e	= shift;
			warn $e->text;
		};
	}
}

sub load_source_data {
	my $self	= shift;
	my $model	= $self->model;
	my $parser	= RDF::Trine::Parser->new('turtle');
	foreach my $u ($self->sources) {
		warn "# loading $u\n";
		try {
			RDF::Trine::Parser->parse_url_into_model( $u, $model, context => iri('http://myrdf.us/ns/sparql/Implementations') );
		} catch Error with {
			my $e	= shift;
			warn $e->text;
		};
	}
}

sub get_manifests {
	my $self	= shift;
	my $model	= $self->model;
	{
		my $iter	= $model->get_statements( undef, $mf->conformanceRequirement );
		my %manifests;
		my %specs;
		while (my $st = $iter->next) {
			my $spec	= $st->subject;
			my $uri		= $spec->uri_value;
			my $list	= $st->object;
			my @mans;
			foreach my $n ($model->get_list( $list )) {
				my $u	= $n->uri_value;
				my $f	= $u;
				$f		=~ s[$manifestbase/][];
				$manifests{ files }{ $f }++;
				$manifests{ specs }{ $f }{ $uri }++;
				push(@mans, $f);
			}
			my ($name)	= $uri =~ m{([^/]+)/*$};
			$specs{ $uri }{ manifests }	= { map { $_ => 1 } @mans };
			$specs{ $uri }{ id }		= $name;
		}
		$self->{specs}		= \%specs;
		$self->{manifests}	= \%manifests;
	}
	foreach my $s (keys %{ $self->{specs} }) {
		my $spec	= iri($s);
		my ($name)	= $model->objects( $spec, $rdfs->label, undef );
		if ($name) {
			$self->{ specs }{ $s }{ name }	= $name->literal_value;
		} else {
			$self->{ specs }{ $s }{ name }	= $self->{ specs }{ $s }{ id };
		}
	}
}

sub specs {
	my $self	= shift;
	return keys %{ $self->{ specs } };
}

sub spec_name {
	my $self	= shift;
	my $spec	= shift;
	return $self->{specs}{ $spec }{ name };
}

sub spec_id {
	my $self	= shift;
	my $spec	= shift;
	return $self->{specs}{ $spec }{ id };
}

sub manifests {
	my $self	= shift;
	my @manifests	= keys %{ $self->{ manifests }{ files } };
	return @manifests;
}

sub spec_manifests {
	my $self	= shift;
	my $spec	= shift;
	my $specs	= $self->{specs};
	return keys %{ $specs->{ $spec }{ manifests } }
}

sub manifest_iri {
	my $self	= shift;
	my $man		= shift;
	return iri(join('/',$manifestbase,$man));
}

sub spec_tests {
	my $self		= shift;
	my $spec		= shift;
	my $model		= $self->model;
	my ($man_list)	= $model->objects( iri($spec), $mf->conformanceRequirement );
	my @man			= $model->get_list( $man_list );
	my @tests		= map { $self->manifest_tests( $_ ) } @man;
	return sort { $a->uri_value cmp $b->uri_value } @tests;
}

sub manifest_tests {
	my $self		= shift;
	my $man			= shift;
	my $model		= $self->model;
	my ($test_list)	= $model->objects( $man, $mf->entries );
	my @tests		= $model->get_list( $test_list );
	return sort { $a->uri_value cmp $b->uri_value } @tests;
}

sub test_is_optional {
	my $self	= shift;
	my $test	= shift;
	my $iri		= $test->uri_value;
	my @groups	= keys %{ $self->{ test_status }{ $iri } || {} };
	return scalar(@groups) ? 1 : 0;
}

sub test_approval_status {
	my $self	= shift;
	my $test	= shift;
	my $iri		= $test->uri_value;
	return $self->{ test_approval }{ $iri }
}

sub software_test_result {
	my $self		= shift;
	my $software	= shift;
	my $test		= shift;
	my $model		= $self->model;
	return $self->{ test_results }{ software }{ $software->uri_value }{ $test->uri_value };
}

sub get_test_status {
	my $self	= shift;
	my $model	= $self->model;
	{
		my $iter	= $model->get_statements( undef, $mf->requires, undef, iri('http://myrdf.us/ns/sparql/Manifests') );
		while (my $st = $iter->next) {
			my $test	= $st->subject->uri_value;
			my $req		= $st->object->uri_value;
			$self->{ test_status }{ $test }{ $req }++;
			$self->{ require_groups }{ $req }{ $test }++;
		}
	}
	
	{
		my $iter	= $model->get_statements( undef, $dt->approval );
		while (my $st = $iter->next) {
			my $test	= $st->subject->uri_value;
			my $status	= $st->object->uri_value;
			$self->{ test_approval }{ $test }	= $status;
		}
	}
	
	
}

sub get_test_results {
	my $self	= shift;
	my $model	= $self->model;
	my $query	= RDF::Query->new(<<"END");
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX earl: <http://www.w3.org/ns/earl#>
PREFIX dt: <http://www.w3.org/2001/sw/DataAccess/tests/test-dawg#>
PREFIX mf: <http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#>
SELECT ?test ?outcome ?approval ?software
WHERE {
	GRAPH <http://myrdf.us/ns/sparql/Implementations> {
		[]
			earl:test ?test ;
			earl:result [ earl:outcome ?outcome ] ;
			earl:subject ?software .
	}
}
END
	my $iter	= $query->execute( $model );
	while (my $r = $iter->next) {
		my $test		= $r->{test}->uri_value;
		my $outcome		= $r->{outcome}->uri_value;
		my $software	= $r->{software}->uri_value;
		push( @{ $self->{ test_results }{raw} }, [$test, $outcome, $software] );
		$self->{ test_results }{ software }{ $software }{ $test }	= $outcome;
		$self->{ test_results }{ test }{ $test }{ $software }		= $outcome;
	}
}

sub get_software {
	my $self	= shift;
	my $model	= $self->model;
	my %software;
	{
		my $iter	= $model->get_statements( undef, iri('http://www.w3.org/ns/earl#subject'), undef, iri('http://myrdf.us/ns/sparql/Implementations') );
		while (my $st = $iter->next) {
			my $s	= $st->object->uri_value;
			$software{ $s }++;
		}
	}
	$self->{software}	= [ map { iri($_) } keys %software ];
	
	foreach my $s (@{ $self->{software} }) {
# 		push(@names, $model->objects( 
		my @names	= grep { blessed($_) and $_->isa('RDF::Trine::Node::Literal') } $model->objects_for_predicate_list( $s, $doap->name, $foaf->name, $rdfs->label );
		if (@names) {
			$self->{ software_names }{ $s->uri_value }	= $names[0]->literal_value;
		} else {
			$self->{ software_names }{ $s->uri_value }	= $s->uri_value;
		}
	}
}

sub software {
	my $self	= shift;
	return @{ $self->{software} };
}

sub software_name {
	my $self	= shift;
	my $s		= shift;
	my $uri		= $s->uri_value;
	return $self->{ software_names }{ $uri };
}

1;
