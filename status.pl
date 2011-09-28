#!/usr/bin/perl

use strict;
use warnings;
no warnings 'uninitialized';
use lib qw(. lib);
use Data::Dumper;
use SPARQLReport;

my $url_file		= shift || 'reports.txt';
my $manifestdir		= shift || '/Users/samofool/data/prog/git/perlrdf/RDF-Query/xt/dawg11';

my $date			= scalar(gmtime) . ' GMT';

my @sources;
open( my $fh, '<:utf8', $url_file ) or die $!;
while (defined(my $u = <$fh>)) {
	chomp($u);
	next if (substr($u,0,1) eq '#');
	next if ($u !~ /\S/);
	push(@sources, $u);
}
close($fh);

unlink('sparql.sqlite');
my $r	= SPARQLReport->new( \@sources, $manifestdir );
$r->load_data();

my %software_ids;
foreach my $s ($r->software) {
	my $id	= lc($r->software_name( $s ));
	$id		=~ s/[^a-zA-Z0-9]/-/g;
	$id		=~ s/--+/-/g;
	$id		=~ s/^-+//;
	$id		=~ s/-+$//;
	$software_ids{ $s }	= "impl-$id";
}

print_html_head($r);
implementation_summary($r);
tests_table($r);
sources();
print_html_foot($date);


################################################################################

sub sources {
	print "<p>Sources:</p>\n<ul>\n";
	foreach my $source (@sources) {
		print qq[\t<li><a href="$source">$source</a></li>\n];
	}
	print "</ul>\n";
}

sub implementation_summary {
	my $r	= shift;
	
	print qq[<h3 id="summary">Implementation Summary</h3>];
	print qq[<table>\n\t<tr>\n\t\t<th>Spec</th>\n];
	foreach my $s ($r->software) {
		my $name		= $r->software_name( $s );
		print qq[\t\t<th>$name</td>\n];
	}
	print qq[\t</tr>\n];
	
	foreach my $spec ($r->specs) {
		my $specname	= $r->spec_name( $spec );
		my $specid		= $r->spec_id( $spec );
		print qq[\t<tr>\n\t\t<td><a href="#$specid">$specname</a></td>\n];

		my $total	= 0;
		my %software_totals;
		my %software_passes;
		foreach my $t ($r->spec_tests( $spec )) {
			$total++;
			next if ($r->test_is_optional( $t ));
			my $iri		= $t->uri_value;
			my $name	= strip_test($iri);
			foreach my $software ($r->software) {
				my $sid	= $software_ids{ $software };
				my $outcome	= $r->software_test_result( $software, $t );
				if ($outcome) {
					$outcome	=~ s{http://www.w3.org/ns/earl#}{};
					$software_totals{ $software }++;
					$software_passes{ $software }++ if ($outcome eq 'pass');
				}
			}
		}
		
# 		print qq[\t\t<td colspan="2">Total &mdash; %Total/%Run (Pass/Run/Total)</td>\n];
		foreach my $software ($r->software) {
			my $sid		= $software_ids{ $software };
			my $run		= $software_totals{ $software } || 0;
			my $pass	= $software_passes{ $software } || 0;
			my $num		= 100*($pass/$total);
			my $tperc	= ($run == 0) ? 'n/a' : sprintf('%.1f%%', $num);
			my $bucket	= int($num/10);
			my $grade_class	= ($run) ? "b$bucket" : '';
			print qq[\t<td class="$sid $grade_class">$tperc</td>\n];
		}
		print qq[</tr>\n];
	}
	print qq[</table>\n];	
}

sub tests_table {
	my $r	= shift;
	my $width	= 2 + scalar(@{ [ $r->software ] });
	
	# warn "Specs\n";
	print qq[<h3 id="tests">Tests</h3>];
	print qq[<table>\n];
	foreach my $spec ($r->specs) {
	# 	warn "\t$spec\n";
		my $specname	= $r->spec_name( $spec );
		my $specid		= $r->spec_id( $spec );
		print <<"END";
		<tr><th colspan="${width}"><h3 id="$specid">$specname</h3></th></tr>
		<tr>
			<th>Test</th>
			<th>Status</th>
END
		foreach my $s ($r->software) {
			my $software	= $s->as_string;
			my $name		= $r->software_name( $s );
			print "\t\t<th>$name</th>\n";
		}
		print "\t</tr>\n";
		
		my $total	= 0;
		my %software_totals;
		my %software_passes;
		foreach my $t ($r->spec_tests( $spec )) {
			$total++;
			next if ($r->test_is_optional( $t ));
			my $iri		= $t->uri_value;
			my $name	= strip_test($iri);
			my $status	= $r->test_approval_status( $t );
			$status	=~ s{http://www.w3.org/2001/sw/DataAccess/tests/test-dawg#}{};
	# 		warn "\t\t" . $t->uri_value . "\n";
			print <<"END";
		<tr>
			<td>$name</td>
			<td class="${status}">${status}</td>
END
			foreach my $software ($r->software) {
				my $sid	= $software_ids{ $software };
				my $outcome	= $r->software_test_result( $software, $t );
				if ($outcome) {
					$outcome	=~ s{http://www.w3.org/ns/earl#}{};
					$software_totals{ $software }++;
					$software_passes{ $software }++ if ($outcome eq 'pass');
					print qq[\t\t<td class="$sid ${outcome}">${outcome}</td>\n];
				} else {
					print qq[\t\t<td class="$sid notrun">not run</td>\n];
				}
			}
			print "\t</tr>\n";
		}
	
	
		print qq[<tr><td colspan="2">Total &mdash; %Total/%Run (Pass/Run/Total)</td>\n];
		foreach my $software ($r->software) {
			my $sid		= $software_ids{ $software };
			my $run		= $software_totals{ $software } || 0;
			my $pass	= $software_passes{ $software } || 0;
			my $rperc	= ($run == 0) ? 'n/a' : sprintf('%.1f%%', 100*($pass/$run));
			my $tperc	= ($total == 0) ? 'n/a' : sprintf('%.1f%%', 100*($pass/$total));
			print qq[\t<td class="$sid"><span title="($pass/$run/$total)">$tperc/$rperc</span></td>\n];
		}
		print qq[</tr>\n];
	
	# 	print totals of required software-test conformance
	# 	foreach optional test group in spec
	# 		foreach optional test
	# 			print row header cells with test name and approval status
	# 			foreach software
	# 				print table cell with software-test conformance
	# 		print totals of optional group software-test conformance
	}
	
	print qq[</table>\n];
}

sub strip_test {
	my $t	= shift;
	$t	=~ s{http://www.w3.org/2001/sw/DataAccess/tests/data-r2/}{};
	$t	=~ s{http://www.w3.org/2009/sparql/docs/tests/data-sparql11/}{};
#	$t	=~ s{file:///Users/samofool/data/prog/git/perlrdf/RDF-Query/xt/dawg11/}{};
	return $t;
}

sub print_html_head {
	my $r			= shift;
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
			
			/* red */
			.b0 { background-color:  #f00; }
			
			/* orange */
			.b1 { background-color:  #b22; }
			.b2 { background-color:  #f40; }
			.b3 { background-color:  #f80; }
			
			/* yellow */
			.b4 { background-color:  #da0; }
			.b5 { background-color:  #dd0; }
			.b6 { background-color:  #ff0; }
			
			/* green */
			.b7 { background-color:  #9c0; }
			.b8 { background-color:  #9e0; }
			.b9 { background-color:  #7e0; }
			
			/* green */
			.b10 { background-color: #0f0; }
/* ]]> */
</style></head>
<body>
<h1>SPARQL 1.1 Test Results</h1>
<ul>
	<li><a href="#summary">Implementation Summary</a></li>
	<li><a href="#tests">Tests by Specifications</a><ul>
		
END

	foreach my $spec ($r->specs) {
		my $name	= $r->spec_name( $spec );
		my $id		= $r->spec_id( $spec );
		print qq[\t\t<li><a href="#$id">$name</a></li>\n];
	}

	print "</ul></li></ul>\n";
}

sub print_html_foot {
	my $date	= shift;
	print qq[<p class="foot">$date</p>\n];
	print <<'END';
$Id: $
</body>
</html>
END
}

__END__
