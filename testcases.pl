#!/usr/bin/perl

use strict;
use warnings;
no warnings 'uninitialized';
use lib qw(. lib);
use Carp qw(confess);
use Data::Dumper;
use RDF::Trine qw(iri);
use RDF::Trine::Namespace qw(rdfs);
use LWP::UserAgent;
use HTML::Entities;
use SPARQLReport;

# use HTTP::Cache::Transparent;
# HTTP::Cache::Transparent::init( {
# 	BasePath => '/tmp/cache',
# } );

my $mf				= RDF::Trine::Namespace->new( 'http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#' );
my $qt				= RDF::Trine::Namespace->new( 'http://www.w3.org/2001/sw/DataAccess/tests/test-query#' );
my $ut				= RDF::Trine::Namespace->new( 'http://www.w3.org/2009/sparql/tests/test-update#' );
my $manifestdir		= shift || '/Users/samofool/data/prog/git/perlrdf/RDF-Query/xt/dawg11';
my $date			= scalar(gmtime) . ' GMT';

unlink('sparql.sqlite');
my $r	= SPARQLReport->new( [], $manifestdir );
$r->load_data();

my @tests;
my @manifests	= $r->manifests;
foreach my $man (@manifests) {
	my $uri	= $r->manifest_iri( $man );
	push(@tests, $r->manifest_tests($uri));
}

my %manifest_ids;
my %test_ids;
foreach my $man (@manifests) {
	my $m		= $r->manifest_iri( $man );
	my $uri		= $m->uri_value;
	my ($id)	= $uri =~ m[/([^/]+)/([^/]+)$];
	if (exists $manifest_ids{ $uri }) {
		die "manifest defined twice: $uri -> $id\n";
	}
	$manifest_ids{ $uri }	= $id;
}
foreach my $t (@tests) {
	my $uri	= $t->uri_value;
	my ($id)	= $uri =~ m[#(.*)$];
	if (exists $test_ids{ $uri }) {
		die "test defined twice: $uri -> $id\n";
	}
	$test_ids{ $uri }	= $id;
}



my $ua	= LWP::UserAgent->new;

print_html_head();

print qq[<ul>\n];
foreach my $t (sort { $a->uri_value cmp $b->uri_value } @tests) {
	my $uri			= $t->uri_value;
	my $uri_short	= strip_uri($uri);
	my $id			= $test_ids{ $uri };
	my $name		= $r->test_name( $t );
	warn "no name for $uri" unless defined($name);
	if ($name) {
		print qq[\t<li><a href="#${id}">${uri_short}</a> - $name</li>\n];
	} else {
		print qq[\t<li><a href="#${id}">${uri_short}</a></li>\n];
	}
}
print qq[</ul>\n];

# foreach syntax test
#	print
#		test name, internal link
#		status (e.g. Approved)
#		comment ("negative syntax test, should fail to parse")
#		requirements
#		test description
# foreach eval test
#	print
#		test name, internal link
#		status (e.g. Approved)
#		comment ("negative syntax test, should fail to parse")
#		requirements
#		test description

my $model	= $r->model;

# foreach test
foreach my $t (sort { $a->uri_value cmp $b->uri_value } @tests) {
	my $uri			= $t->uri_value;
	my $id			= $test_ids{ $uri };
	my $name		= $r->test_name( $t ) || '(none)';
	my $type		= $r->test_type( $t );
	my ($action)	= $model->objects( $t, $mf->action );
	
	print qq[\n<hr/>\n];
	print qq[<!-- $uri -->\n];
	print qq[<h2 id="${id}">] . encode_entities($name) . qq[</h2>\n];
	print encode_entities($type) . "\n";
	
	# @@ TODO
	# <div class="approval">Approved by <a href="${approval_url}">${approval_url}</a></div>
	
	if ($type =~ /evaluation/i) {
		# eval tests
		my ($result)	= $model->objects( $t, $mf->result );
		
		print_dataset( $model, $action, ($type =~ /update/i) );

		if ($type =~ /update/i) {
			my ($update)	= $model->objects( $action, $ut->request );
			my $uuri		= $update->uri_value;
			my $uuri_short	= strip_uri($uuri);
			my $sparql		= encode_entities(get_url($ua, $uuri));
			$sparql			=~ s[\n][<br/>]g;
			print qq[<h3>Update</h3>\n];
			print qq[<a href="${uuri}">${uuri_short}</a><br/>\n];
			print qq[<div class="query">${sparql}</div>\n];
			
			# 	print link to results file (or the actual results table?)
			print qq[<h3>Result Dataset:</h3>\n];
			print_update_dataset( $model, $result );
		} else {
	 		my ($query)		= $model->objects( $action, $qt->query );
 			my $quri		= $query->uri_value;
			my $quri_short	= strip_uri($quri);
			my $sparql		= encode_entities(get_url($ua, $quri));
			$sparql			=~ s[\n][<br/>]g;
			print qq[<h3>Query</h3>\n];
			print qq[<a href="${quri}">${quri_short}</a><br/>\n];
			print qq[<div class="query">${sparql}</div>\n];

			# 	print link to results file (or the actual results table?)
			my $ruri		= $result->uri_value;
			my $ruri_short	= strip_uri($ruri);
			print qq[<h3>Results</h3>\n];
			print qq[<p><a href="${ruri}">${ruri_short}</a></p>\n];
 		}
	} else {
		# syntax tests
		my $quri		= $action->uri_value;
		my $quri_short	= strip_uri($quri);
		my $sparql		= encode_entities(get_url($ua, $quri));
		$sparql		=~ s[\n][<br/>]g;
		print qq[<h3>Query</h3>\n];
		print qq[<a href="${quri}">${quri_short}</a><br/>\n];
		print qq[<div class="query">${sparql}</div>\n];
	}
}

print_html_foot($date);


sub print_dataset {
	my $model	= shift;
	my $action	= shift;
	my $update	= shift;
	my $ns		= $update ? $ut : $qt;
	
	my @data		= $model->objects( $action, $ns->data );
	my @gdata		= $model->objects( $action, $ns->graphData );
	my @sdata		= $model->objects( $action, $ns->serviceData );
	my %sdata;
	foreach my $s (@sdata) {
		my ($e)	= $model->objects( $s, $qt->endpoint );
		my (@d)	= $model->objects( $s, $qt->data );
		my (@g)	= $model->objects( $s, $qt->graphData );
		$sdata{ $e->uri_value }	= [ \@d, \@g ];
	}
	
	#	print dataset (if any)
	print qq[<h3>Input Dataset:</h3>\n];
	print qq[<div class="dataset">\n];
	print qq[<h4>Default Graph</h4>\n];
	foreach my $d (@data) {
		my $uri	= $d->uri_value;
		my $uri_short	= strip_uri($uri);
		my $rdf			= get_url($ua, $uri);
		print qq[<p><a href="${uri}">${uri_short}</a></p>\n];
		print qq[<div class="query">] . encode_entities($rdf) . qq[</div>\n];
	}
	print qq[<h4>Named Graphs</h4>\n];
	foreach my $d (@gdata) {
		if ($update) {
			my ($graph)		= $model->objects( $d, $ut->graph );
			my ($name)		= $model->objects( $d, $rdfs->label );
			my $uri			= $name->literal_value;
			my $url			= $graph->uri_value;
			my $rdf			= get_url($ua, $url);
			print qq[<p><a href="${uri}">${uri}</a></p>\n];
			print qq[<div class="query">] . encode_entities($rdf) . qq[</div>\n];
		} else {
			my $uri	= $d->uri_value;
			my $uri_short	= strip_uri($uri);
			my $rdf			= get_url($ua, $uri);
			print qq[<p><a href="${uri}">${uri_short}</a></p>\n];
			print qq[<div class="query">] . encode_entities($rdf) . qq[</div>\n];
		}
	}
	print qq[</div>\n];
	
	my @skeys	= keys %sdata;
	if (@skeys) {
		#	print remote dataset(s)
		foreach my $suri (@skeys) {
			print qq[<h4>Remote Endpoint: $suri</h4>\n];
			print qq[<div class="dataset">\n];
			my ($da, $ga)	= @{ $sdata{ $suri } || [] };
			print qq[<h5>Default Graph</h5>\n];
			foreach my $d (@{ $da || [] }) {
				my $uri	= $d->uri_value;
				my $uri_short	= strip_uri($uri);
				my $rdf			= get_url($ua, $uri);
				print qq[<p><a href="${uri}">${uri_short}</a></p>\n];
				print qq[<div class="query">] . encode_entities($rdf) . qq[</div>\n];
			}
			print qq[<h5>Named Graphs</h5>\n];
			foreach my $g (@{ $ga || [] }) {
				my $uri	= $g->uri_value;
				my $uri_short	= strip_uri($uri);
				my $rdf			= get_url($ua, $uri);
				print qq[<p><a href="${uri}">${uri_short}</a></p>\n];
				print qq[<div class="query">] . encode_entities($rdf) . qq[</div>\n];
			}
			print qq[</div>\n];
		}
	}
}

sub print_update_dataset {
	my $model	= shift;
	my $action	= shift;
	
	my @data		= $model->objects( $action, $ut->data );
	my @gdata		= $model->objects( $action, $ut->graphData );
	
	#	print dataset (if any)
	print qq[<div class="dataset">\n];
	print qq[<h4>Default Graph</h4>\n];
	foreach my $d (@data) {
		my $uri	= $d->uri_value;
		my $uri_short	= strip_uri($uri);
		my $rdf			= get_url($ua, $uri);
		print qq[<p><a href="${uri}">${uri_short}</a></p>\n];
		print qq[<div class="query">] . encode_entities($rdf) . qq[</div>\n];
	}
	print qq[<h4>Named Graphs</h4>\n];
	foreach my $d (@gdata) {
		my ($graph)		= $model->objects( $d, $ut->graph );
		my ($name)		= $model->objects( $d, $rdfs->label );
		my $uri			= $name->literal_value;
		my $rdf			= get_url($ua, $graph->uri_value);
		print qq[<p><a href="${uri}">${uri}</a></p>\n];
		print qq[<div class="query">] . encode_entities($rdf) . qq[</div>\n];
	}
	print qq[</div>\n];
}


################################################################################

sub get_url {
	my $ua		= shift;
	my $uri		= shift;
	$uri		=~ s{http://www.w3.org/2009/sparql/docs/tests/data-sparql11/}{file://$manifestdir/};
	my $resp	= $ua->get($uri);
	unless ($resp->is_success) {
		warn $uri;
		confess Dumper($resp);
	}
	
	my $content	= $resp->content;
	confess "uh oh" if ($content =~ /DOCTYPE/);
	return $content;
}

sub strip_uri {
	my $t	= shift;
	$t	=~ s{http://www.w3.org/2009/sparql/docs/tests/data-sparql11/sparql11/data-sparql11/}{};
	$t	=~ s{http://www.w3.org/2009/sparql/docs/tests/data-sparql11/}{};
	$t	=~ s{http://www.w3.org/2001/sw/DataAccess/tests/data-r2/}{};
#	$t	=~ s{file:///Users/samofool/data/prog/git/perlrdf/RDF-Query/xt/dawg11/}{};
	return $t;
}

sub print_html_head {
	print <<"END";
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
        "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
	<meta http-equiv="content-type" content="text/html; charset=utf-8" />
	<link rel="stylesheet" type="text/css" href="http://www.w3.org/StyleSheets/TR/base.css" />
	<link rel="stylesheet" type="text/css" href="http://www.w3.org/2001/sw/DataAccess/tests/tests.css" />
	<title>SPARQL 1.1 Evaluation Test Results</title>
	<style type="text/css" title="text/css">
/* <![CDATA[ */
		.dataset {
			border: 1px dashed #bbb;
			margin-top: 1em;
			margin-bottom: 1em;
			padding: 1em;
		}
/* ]]> */
</style></head>
<body>
<h1>SPARQL 1.1 Test Suite</h1>

END
}

sub print_html_foot {
	my $date	= shift;
	print <<'END';
<hr/>
<p>
	Generated for the <a href="http://www.w3.org/2009/sparql/docs/tests/">SPARQL 1.1 test suite</a> by <a href="https://github.com/kasei/SPARQL-1.1-Implementation-Report">SPARQL-1.1-Implementation-Report</a>.
	Direct new implementation reports and feedback to <a href="mailto:public-rdf-dawg-comments@w3.org">public-rdf-dawg-comments@w3.org</a>.
</p>
END
	print qq[<p class="foot">$date</p>\n];
	print <<'END';
$Id: $
</body>
</html>
END
}

__END__
