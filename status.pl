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


my $url_file		= shift || 'reports.txt';
my $manifestdir		= shift || '/Users/samofool/data/prog/git/perlrdf/RDF-Query/xt/dawg11';
my $manifestbase	= 'http://www.w3.org/2009/sparql/docs/tests/data-sparql11';
my $doap			= RDF::Trine::Namespace->new( 'http://usefulinc.com/ns/doap#' );
my $mf				= RDF::Trine::Namespace->new( 'http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#' );
my $date			= scalar(gmtime) . ' GMT';
my $exists			= (-r 'sparql.sqlite');
my $store			= RDF::Trine::Store::DBI::SQLite->new('model', 'dbi:SQLite:dbname=sparql.sqlite', '', '');
my $model			= RDF::Trine::Model->new( $store );
my $parser			= RDF::Trine::Parser->new('turtle');

#my @manifests		= glob( "${manifestdir}/*/manifest.ttl" );

my $man				= File::Spec->catfile( $manifestdir, 'manifest-all.ttl' );
for my $f ($man) {
	warn "# loading $f\n";
	try {
		my $base	= join('/', $manifestbase, 'manifest-all.ttl');
		$parser->parse_file_into_model( $base, $f, $model );
	} catch Error with {
		my $e	= shift;
	};
}

my (@specs, %specs, @manifests);
{
	my %manifests;
	my $iter	= $model->get_statements( undef, $mf->conformanceRequirement );
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
		$specs{ $uri }{ name }		= $name;
	}
	@specs		= keys %specs;
	@manifests	= keys %{ $manifests{ files } };
}

my @sources;
open( my $fh, '<:utf8', $url_file ) or die $!;
while (defined(my $u = <$fh>)) {
	chomp($u);
	next if (substr($u,0,1) eq '#');
	next if ($u !~ /\S/);
	push(@sources, $u);
}
close($fh);

unless ($exists) {
	foreach my $f (@manifests) {
		try {
			my ($dir)	= ($f =~ m{([^/]+)/manifest.ttl});
			my $base	= join('/', $manifestbase, $dir, 'manifest.ttl' );
			my $file	= File::Spec->catfile( $manifestdir, $f );
			warn "# loading $file with base $base\n";
			$parser->parse_file_into_model( $base, $file, $model );
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


# my $iter	= $model->get_statements( undef, $mf->entries );
# while (my $r = $iter->next) {
# 	warn $r->as_string;
# }
# exit;

foreach my $spec (@specs) {
# 	warn "*** spec $spec\n";
	foreach my $man (keys %{ $specs{ $spec }{ manifests } }) {
# 		warn "      manifest $man\n";
		my $m	= iri(join('/',$manifestbase,$man));
		my ($test_list)	= $model->objects( $m, $mf->entries );
		my @tests		= $model->get_list( $test_list );
		foreach my $test (@tests) {
# 			warn "        test $test\n";
			$specs{ $spec }{ tests }{ $test->uri_value }++;
		}
	}
}


sub get_requirements {
	my $model	= shift;
	my %requirements;
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
	return %requirements;
}

sub get_software {
	my $model	= shift;
	my @software;
	my $squery	= RDF::Query->new('SELECT DISTINCT ?software WHERE { [] <http://www.w3.org/ns/earl#subject> ?software }');
	my $siter	= $squery->execute( $model );
	while (my $r = $siter->next) {
		my $s	= $r->{software}->uri_value;
		push(@software, $s);
	}
	return @software;
}

sub get_results {
	my $model			= shift;
	my $requirements	= shift;
	my $specs			= shift;
	my $software		= shift;
	my %conditions		= @_;
	my %results;
	my %software;
	warn "# getting EARL results for " . join(' ', %conditions) . "\n";
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
		
		if (my $spec = $conditions{ spec }) {
			# skip the test unless it's defined for this spec
			next unless $specs->{ $spec }{ tests }{ $test };
		}
		
		my $group;
		if (my $req = $requirements->{tests}{$test}) {
			$group	= 'optional';
			$results{ software }{ $s }{ optional }{ $req }{ total }++;
			$results{ software }{ $s }{ optional }{ $req }{ pass }++ if ($o eq 'pass');
			$results{ tests }{ $group }{ $req }{ $test }{ run }++;
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
	
	
	foreach my $s (@$software) {
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
	return (\%results, \%software);
}

sub print_spec_test_table {
	my $model		= shift;
	my $spec		= shift;
	my $specs		= shift;
	my $sl			= shift;
	my $requirements	= shift;
	my ($r, $sh)	= get_results( $model, $requirements, $specs, $sl, spec => $spec );
	
	my %results		= %$r;
	my @software	= @$sl;
	my %software	= %$sh;
	my $name		= $specs{ $spec }{ name };




	print <<"END";
<h3 id="$name">$name</h3>
<table>
<tr>
	<th>Test</th>
	<th>Status</th>
END

	my $columns	= 2 + scalar(@software);
	foreach my $s (@software) {
# 		warn "# software $s\n";
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
# 			warn "# test $t\n";
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
			my $rperc	= ($run == 0) ? 'n/a' : sprintf('%.1f%%', 100*($pass/$run));
			my $tperc	= ($total == 0) ? 'n/a' : sprintf('%.1f%%', 100*($pass/$total));
			print qq[\t<td><span title="($pass/$run/$total)">$tperc/$rperc</span></td>\n];
		}
		print qq[</tr>\n];
	}

	
	foreach my $req (sort keys %{ $requirements->{groups} }) {
		my $name	= $req;
		$name		=~ s{http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#}{};

		my @opt_tests	= grep { exists $results{ tests }{ optional }{ $req }{ $_ }{ run } } @{ $requirements->{groups}{$req} };
		if (scalar(@opt_tests)) {
			print qq[<tr><th colspan="$columns">Optional Tests: $name</td></tr>\n];
			my $total	= scalar(@opt_tests);
			foreach my $t (sort @{ $requirements->{groups}{$req} }) {
				$t	= strip_test($t);
	# 			warn "# optional test $t\n";
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
				my $rperc	= ($run == 0) ? 'n/a' : sprintf('%.1f%%', 100*($pass/$run));
				my $tperc	= ($total == 0) ? 'n/a' : sprintf('%.1f%%', 100*($pass/$total));
				print qq[\t<td><span title="($pass/$run/$total)">$tperc/$rperc</span></td>\n];
			}
			print qq[</tr>\n];
		}
	}
	print qq[</table>\n];
}

sub print_html_head {
	my $slist	= shift;
	my $specs	= shift;
	my $software	= shift;
	
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
				width: 850px;
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
<ul>
	<li>Specifications<ul>
		
END

	foreach my $spec (@$slist) {
		my $name	= $specs{ $spec }{ name };
		print qq[\t\t<li><a href="#$name">$name</a></li>\n];
	}

	print "</ul></li></ul>\n";
}

sub print_html_foot {
	print <<"END";
<p class="foot">$date</class>
</body>
</html>
END
}

sub strip_test {
	my $t	= shift;
	$t	=~ s{http://www.w3.org/2001/sw/DataAccess/tests/data-r2/}{};
	$t	=~ s{http://www.w3.org/2009/sparql/docs/tests/data-sparql11/}{};
#	$t	=~ s{file:///Users/samofool/data/prog/git/perlrdf/RDF-Query/xt/dawg11/}{};
	return $t;
}





my %requirements	= get_requirements( $model );
my @software		= get_software( $model );
my @slist			= reverse sort @specs;
print_html_head(\@slist, \%specs);
foreach my $spec (@slist) {
	print_spec_test_table($model, $spec, \%specs, \@software, \%requirements);
}
print qq[<p>Sources:</p>\n<ul>\n];
foreach my $u (@sources) {
	print qq[<li><a href="$u">] . encode_entities($u) . qq[</a></li>\n];
}
print qq[</ul>\n];
print_html_foot();



