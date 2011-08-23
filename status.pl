#!/usr/bin/perl

use strict;
use warnings;
no warnings 'uninitialized';

use Data::Dumper;
use File::Spec;
use RDF::Redland;
use RDF::Trine qw(iri);
use RDF::Trine::Namespace qw(foaf rdfs);
use RDF::Query;
use RDF::Trine::Error qw(:try);
use Scalar::Util qw(blessed);
use HTML::Entities;


my $url_file	= shift || 'reports.txt';
my $manifestdir	= shift || '/Users/samofool/data/prog/git/perlrdf/RDF-Query/xt/dawg11';

my $doap		= RDF::Trine::Namespace->new( 'http://usefulinc.com/ns/doap#' );
my $mf			= RDF::Trine::Namespace->new( 'http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#' );
my $date		= scalar(gmtime) . ' GMT';
my $exists		= (-r 'sparql.sqlite');
my @manifests	= glob( "${manifestdir}/*/manifest.ttl" );
my $store		= RDF::Trine::Store::DBI::SQLite->new('model', 'dbi:SQLite:dbname=sparql.sqlite', '', '');
my $model		= RDF::Trine::Model->new( $store );
my $parser		= RDF::Trine::Parser->new('turtle');

my @sources;
open( my $fh, '<:utf8', $url_file ) or die $!;
while (defined(my $u = <$fh>)) {
	chomp($u);
	push(@sources, $u);
}
close($fh);

unless ($exists) {
	foreach my $f (@manifests) {
		warn "# loading $f\n";
		try {
			my $base	= "file://";
			if ($f =~ /manifest/) {
				my ($dir)	= ($f =~ m{xt/dawg11/([^/]+)/manifest.ttl});
				$base	= "http://www.w3.org/2009/sparql/docs/tests/data-sparql11/${dir}/manifest#";
			}
			$parser->parse_file_into_model( $base, $f, $model );
		} catch Error with {
			my $e	= shift;
		};
	}
	foreach my $u (@sources) {
		warn "# loading $u\n";
		try {
			RDF::Trine::Parser->parse_url_into_model( $u, $model );
		} catch Error with {
			my $e	= shift;
			warn $e->text;
		};
	}
}


my %results;
my %requirements;
my @software;
my %software;


{
	warn "# getting test requirements\n";
	my $iter	= $model->get_statements( undef, $mf->requires, undef );
	while (my $st = $iter->next) {
		my $test	= $st->subject->uri_value;
		my $req		= $st->object->uri_value;
		if (exists( $requirements{tests}{ $test } )) {
			my $req1	= $requirements{tests}{ $test };
			warn "Test $test has two requirements: $req1, $req\n";
		}
		$requirements{tests}{ $test }	= $req;
		push(@{ $requirements{groups}{$req} }, $test);
	}
}

{
	warn "# getting EARL results\n";
	my $query	= RDF::Query->new(<<"END");
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX earl: <http://www.w3.org/ns/earl#>
PREFIX dt: <http://www.w3.org/2001/sw/DataAccess/tests/test-dawg#>
PREFIX mf: <http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#>
SELECT ?test ?outcome ?approval ?software
WHERE {
	[]
		earl:test ?test ;
		earl:result ?result ;
		earl:subject ?software .
	?result earl:outcome ?outcome .
	?test dt:approval ?approval .
}
END
	my $iter	= $query->execute( $model );
	while (my $row = $iter->next) {
		my ($t, $o, $a, $s)	= map { (blessed($_) and $_->can('uri_value')) ? $_->uri_value : $_ } @{ $row }{ qw(test outcome approval software) };
		my $test	= $t;
		$t	= strip_test($t);
		$a	=~ s{http://www.w3.org/2001/sw/DataAccess/tests/test-dawg#}{};
		$o	=~ s{http://www.w3.org/ns/earl#}{};
		
		my $group;
		if (my $req = $requirements{tests}{$test}) {
			$group	= 'optional';
			$results{ software }{ $s }{ optional }{ $req }{ total }++;
			$results{ software }{ $s }{ optional }{ $req }{ pass }++ if ($o eq 'pass');
		} else {
			$group	= 'required';
			$results{ software }{ $s }{ required }++;
			$results{ software }{ $s }{ required_pass }++ if ($o eq 'pass');
		}
		
		$results{ tests }{ $group }{ $t }{ approval }		= encode_entities($a);
		$results{ tests }{ $group }{ $t }{ software }{ $s }	= encode_entities($o);
		$results{ software }{ $s }{ total }++;
		$results{ software }{ $s }{ total_pass }++ if ($o eq 'pass');
	}
	
	foreach my $s (sort keys %{ $results{ software } }) {
		push(@software, $s);
		my @names	= grep { blessed($_) and $_->isa('RDF::Trine::Node::Literal') } $model->objects_for_predicate_list( iri($s), $doap->name, $foaf->name, $rdfs->label );
		if (@names) {
			$software{ $s }{ name }	= encode_entities($names[0]->literal_value);
		} else {
			$software{ $s }{ name }	= encode_entities($s);
		}
		
		my @h			= $model->objects_for_predicate_list( iri($s), $doap->homepage );
		my @homepages	= grep { blessed($_) and $_->isa('RDF::Trine::Node::Resource') } @h;
		if (@homepages) {
			my $h		= $homepages[0]->uri_value;
			my $name	= $software{ $s }{ name };
			$software{ $s }{ name }	= qq[<a href="$h">$name</a>];
		}
	}
}



print <<"END";
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
        "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
	<meta http-equiv="content-type" content="text/html; charset=utf-8" />
	<title>SPARQL 1.1 Evaluation Test Results</title>
<style type="text/css" title="text/css">
/* <![CDATA[ */
			table {
				border: 1px solid #000;
				border-collapse: collapse;
			}
			
			th { background-color: #ddd; }
			td, th {
				padding: 1px 5px 1px 5px;
				border: 1px solid #000;
			}
			
			td.pass { background-color: #0f0; }
			td.fail { background-color: #f00; }
			td.Approved { background-color: #0f0; }
			td.NotClassified { background-color: #ff0; }
			.foot { font-style: italic }
/* ]]> */
</style></head>
<body>
<h1>SPARQL 1.1 Test Results</h1>

<table>
<tr>
	<th>Test</th>
	<th>Status</th>
END

my $columns	= 2 + scalar(@software);
foreach my $s (@software) {
	warn "# software $s\n";
	my $name	= $software{ $s }{ name };
	print qq[\t<th>$name</th>\n];
}

print <<"END";
</tr>
END

{
	print qq[<tr><th colspan="$columns">Required Tests</td></tr>\n];
	my $total	= scalar(@{[ keys %{ $results{ tests }{ required } } ]});
	foreach my $t (sort keys %{ $results{ tests }{ required } }) {
		warn "# test $t\n";
		my $a	= $results{ tests }{ required }{ $t }{ approval };
		print qq[<tr>\n\t<td>$t</td>\n\t<td class="$a">$a</td>\n];
		foreach my $s (@software) {
			my $o	= $results{ tests }{ required }{ $t }{ software }{ $s };
			if ($o) {
				print qq[<td class="$o">$o</td>\n];
			} else {
				print qq[<td>not run</td>\n];
			}
		}
		print qq[</tr>\n];
	}
	print qq[<tr><td colspan="2">Total &mdash; %Total/%Run (Pass/Run/Total)</td>\n];
	foreach my $s (@software) {
		my $run		= $results{ software }{ $s }{ required };
		my $pass	= $results{ software }{ $s }{ required_pass };
		my $rperc	= sprintf('%.1f%%', 100*($pass/$run));
		my $tperc	= sprintf('%.1f%%', 100*($pass/$total));
		print qq[\t<td><span title="($pass/$run/$total)">$tperc/$rperc</span></td>\n];
	}
	print qq[</tr>\n];
}


foreach my $req (sort keys %{ $requirements{groups} }) {
	my $name	= $req;
	$name		=~ s{http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#}{};
	print qq[<tr><th colspan="$columns">Optional Tests: $name</td></tr>\n];
	my $total	= scalar(@{ $requirements{groups}{$req} });
	foreach my $t (sort @{ $requirements{groups}{$req} }) {
		$t	= strip_test($t);
		warn "# optional test $t\n";
		my $a	= $results{ tests }{ optional }{ $t }{ approval };
		print qq[<tr>\n\t<td>$t</td>\n\t<td class="$a">$a</td>\n];
		foreach my $s (@software) {
			my $o	= $results{ tests }{ optional }{ $t }{ software }{ $s };
			if ($o) {
				print qq[<td class="$o">$o</td>\n];
			} else {
				print qq[<td>not run</td>\n];
			}
		}
		print qq[</tr>\n];
	}
	print qq[<tr><td colspan="2">Total &mdash; %Total/%Run (Pass/Run/Total)</td>\n];
	foreach my $s (@software) {
		my $run		= $results{ software }{ $s }{ optional }{ $req }{ total } || 0;
		my $pass	= $results{ software }{ $s }{ optional }{ $req }{ pass } || 0;
		my $rperc	= sprintf('%.1f%%', 100*($pass/$run));
		my $tperc	= sprintf('%.1f%%', 100*($pass/$total));
		print qq[\t<td><span title="($pass/$run/$total)">$tperc/$rperc</span></td>\n];
	}
	print qq[</tr>\n</table>\n];
}

print qq[<p>Sources:</p>\n<ul>\n];
foreach my $u (@sources) {
	print qq[<li><a href="$u">] . encode_entities($u) . qq[</a></li>\n];
}
print qq[</ul>\n];

print <<"END";
<p class="foot">$date</class>
</body>
</html>
END





sub strip_test {
	my $t	= shift;
	$t	=~ s{http://www.w3.org/2001/sw/DataAccess/tests/data-r2/}{};
	$t	=~ s{http://www.w3.org/2009/sparql/docs/tests/data-sparql11/}{};
#	$t	=~ s{file:///Users/samofool/data/prog/git/perlrdf/RDF-Query/xt/dawg11/}{};
	return $t;
}
