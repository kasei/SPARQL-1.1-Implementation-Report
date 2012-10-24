# SPARQL 1.1 Implementation Report: https://github.com/kasei/SPARQL-1.1-Implementation-Report
# 
# Copyright © 2012 Gregory Todd Williams. All Rights Reserved. This work is
# distributed under the W3C® Software License [1] in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# 
# [1] http://www.w3.org/Consortium/Legal/2002/copyright-software-20021231

package SPARQLReport;

use strict;
use warnings;
use v5.12;

use Carp qw(confess);
use File::Copy;
use File::Spec;
use File::Path qw(make_path);
use RDF::Redland;
use RDF::Trine qw(iri);
use RDF::Trine::Namespace qw(foaf rdf rdfs);
use RDF::Query;
use RDF::Trine::Error qw(:try);
use Scalar::Util qw(blessed);
use HTML::Entities;
use Data::Dumper;
# use Module::Load::Conditional qw(can_load);
# can_load(modules => {'RDF::Trine::Parser::Serd' => 0});

my $manifestbase	= 'http://www.w3.org/2009/sparql/docs/tests/data-sparql11';
my $doap			= RDF::Trine::Namespace->new( 'http://usefulinc.com/ns/doap#' );
my $mf				= RDF::Trine::Namespace->new( 'http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#' );
my $dt				= RDF::Trine::Namespace->new( 'http://www.w3.org/2001/sw/DataAccess/tests/test-dawg#' );
my $earl			= RDF::Trine::Namespace->new( 'http://www.w3.org/ns/earl#' );

sub new {
	my $class			= shift;
	my $sources			= shift || [];
	my $manifestdir		= shift;
	
	my ($d,$m,$y)		= (gmtime())[3,4,5];
	$y					+= 1900;
	$m++;
	my $date			= sprintf('%04d-%02d-%02d', $y, $m, $d);
	my $path			= File::Spec->catdir('data', $date);
	make_path($path);
	my $self			= bless({ sources => $sources, manifestdir => $manifestdir, data_path => $path }, $class);
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

sub data_path {
	my $self	= shift;
	return $self->{data_path};
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
			$self->archive_file('manifests', 'manifest-all.ttl', $f);
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
	$self->get_test_details();
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
			$self->archive_file('manifests', $f, $file);
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
			RDF::Trine::Parser->parse_url_into_model(
				$u,
				$model,
				context		=> iri('http://myrdf.us/ns/sparql/Implementations'),
				content_cb	=> sub {
					my $url		= shift;
					my $content	= shift;
					my $resp	= shift;
					$self->archive_string('implementations', $url, $content);
				},
			);
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
		my $iter	= $model->get_statements( undef, $mf->conformanceRequirement, undef, iri('http://myrdf.us/ns/sparql/Manifests') );
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
	{
		my $iter	= $model->get_statements( undef, $mf->includedSpecifications, undef, iri('http://myrdf.us/ns/sparql/Manifests') );
		my $st		= $iter->next;
		my $list	= $st->object;
		foreach my $n ($model->get_list( $list )) {
			my $u	= $n->uri_value;
			push(@{ $self->{ ordered_spec_uris } }, $u);
		}
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
	return @{ $self->{ ordered_spec_uris } };
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
	my ($test_list)	= $model->objects( $man, $mf->entries, iri('http://myrdf.us/ns/sparql/Manifests') );
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

sub test_name {
	my $self	= shift;
	my $test	= shift;
	my $iri		= $test->uri_value;
	return $self->{ test_name }{ $iri }
}

sub test_type {
	my $self	= shift;
	my $test	= shift;
	my $iri		= $test->uri_value;
	return $self->{ test_type }{ $iri }
}

sub software_test_result {
	my $self		= shift;
	my $software	= shift;
	my $test		= shift;
	my $model		= $self->model;
	return $self->{ test_results }{ software }{ $software->as_string }{ $test->uri_value };
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
		my $iter	= $model->get_statements( undef, $dt->approval, undef, iri('http://myrdf.us/ns/sparql/Manifests') );
		while (my $st = $iter->next) {
			my $test	= $st->subject->uri_value;
			my $status	= $st->object->uri_value;
			$self->{ test_approval }{ $test }	= $status;
		}
	}
	
	
}

sub get_test_details {
	my $self	= shift;
	my $model	= $self->model;
	{
		my $iter	= $model->get_statements( undef, $mf->name, undef, iri('http://myrdf.us/ns/sparql/Manifests') );
		while (my $st = $iter->next) {
			my $test	= $st->subject->uri_value;
			my $desc	= $st->object->literal_value;
			$self->{ test_name }{ $test }	= $desc;
		}
	}
	
	no warnings 'qw';
	foreach my $type (qw(
					http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#NegativeSyntaxTest11
					http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#NegativeUpdateSyntaxTest11
					http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#PositiveSyntaxTest11
					http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#PositiveUpdateSyntaxTest11
					http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#QueryEvaluationTest
					http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#UpdateEvaluationTest
					http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#ServiceDescriptionTest
					http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#ProtocolTest
					http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#CSVResultFormatTest
					http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#GraphStoreProtocolTest
				)) {
		
		my $iter	= $model->get_statements( undef, $rdf->type, iri($type), iri('http://myrdf.us/ns/sparql/Manifests') );
		while (my $st = $iter->next) {
			my $test	= $st->subject->uri_value;
			my $name;
			if ($type =~ /Eval/) {
				$name	= "evaluation test";
			} elsif ($type =~ /Syntax/) {
				$name	= "syntax test";
			} elsif ($type =~ /ResultFormat/) {
				$name	= "result format test";
			} elsif ($type =~ /ServiceDescription/) {
				$name	= "service description test";
			} elsif ($type =~ /Protocol/) {
				$name	= "protocol test";
			} elsif ($type =~ /GraphStore/) {
				$name	= "graph store protocol test";
			} else {
				confess "Unrecognized test type $type";
			}
			
			if ($type =~ /Update/) {
				$name	= "update $name";
			} elsif ($type =~ /Query/) {
				$name	= "query $name";
			}
			$name	= "negative $name" if ($type =~ /Negative/);
			
			$self->{ test_type }{ $test }	= ucfirst($name);
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
	unless ($query) {
		warn RDF::Query->error;
	}
	my $iter	= $query->execute( $model );
	while (my $r = $iter->next) {
		my $t			= $r->{test};
		unless (blessed($t) and $t->isa('RDF::Trine::Node::Resource')) {
			warn "Test node is not an IRI: " . Dumper($t);
			next;
		}
		my $test		= $r->{test}->uri_value;
		my $outcome		= $r->{outcome}->uri_value;
		my $software	= $r->{software}->as_string;
		
		if ($outcome =~ /passed/) {
			$outcome	= $earl->pass->uri_value;
		}
		if ($outcome =~ /failed/) {
			$outcome	= $earl->fail->uri_value;
		}
		
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
			my $soft	= $st->object;
			my $s		= $soft->as_string;
			$software{ $s }	= $soft;
		}
	}
	
	$self->{software}	= [ values %software ];
	
	foreach my $s (@{ $self->{software} }) {
# 		push(@names, $model->objects( 
		my @names	= grep { blessed($_) and $_->isa('RDF::Trine::Node::Literal') } $model->objects_for_predicate_list( $s, $doap->name, $foaf->name, $rdfs->label );
		if (@names) {
			$self->{ software_names }{ $s->as_string }	= $names[0]->literal_value;
		} else {
			$self->{ software_names }{ $s->as_string }	= $s->uri_value;
		}
		
		my @links	= grep { blessed($_) and $_->isa('RDF::Trine::Node') } $model->objects_for_predicate_list( $s, $doap->homepage, $foaf->homepage );
		if (@links) {
			$self->{ software_links }{ $s->as_string }	= $links[0]->value;
		}
	}
	
	# produce a final ordering of the implementations based on their name
	$self->{software}	= [ sort { lc($self->software_name($a)) cmp lc($self->software_name($b)) } values %software ];
}

sub software {
	my $self	= shift;
	return @{ $self->{software} };
}

sub software_name {
	my $self	= shift;
	my $s		= shift;
	return $self->{ software_names }{ $s->as_string };
}

sub software_link {
	my $self	= shift;
	my $s		= shift;
	return $self->{ software_links }{ $s->as_string };
}

sub archive_string {
	my $self	= shift;
	my $group	= shift;
	my $name	= shift;
	my $string	= shift;
	
	$name		=~ s{^https?://}{};
	
	my $base	= $self->data_path;
	my $dest	= File::Spec->catfile( $base, $group, $name );
	(undef, my $dir)	= File::Spec->splitpath($dest);
	make_path($dir);
	open(my $fh, '>', $dest);
	print {$fh} $string;
	close($fh);
}

sub archive_file {
	my $self	= shift;
	my $group	= shift;
	my $name	= shift;
	my $file	= shift;
	my $base	= $self->data_path;
	my $dest	= File::Spec->catfile( $base, $group, $name );
	(undef, my $dir)	= File::Spec->splitpath($dest);
	make_path($dir);
	copy($file, $dest);
}

sub test_anchor {
	my $self	= shift;
	my $test	= shift;
	my $iri		= $test->uri_value;
	
	if ($iri =~ m{([^/]+)/manifest#(.+)$}) {
		my $dir		= $1;
		my $name	= $2;
		my $id		= join('-', $dir, $name);
# 		warn "Test anchor: $id\n";
		return $id;
	} else {
		warn "Unexpected test IRI syntax: $iri";
		return;
	}
}

sub test_link {
	my $self	= shift;
	my $test	= shift;
	my $anchor	= $self->test_anchor( $test );
	return qq[http://www.w3.org/2009/sparql/docs/tests/summary.html#${anchor}];
}

1;


