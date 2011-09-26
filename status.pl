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

my $r	= SPARQLReport->new( \@sources, $manifestdir );
$r->load_data();



# foreach my $spec ($r->specs) {
# 	warn "*** spec $spec\n";
# 	foreach my $man ($r->spec_manifests( $spec )) {
# 		warn "      manifest $man\n";
# 		my $m		= $self->manifest_iri( $man );
# 		my @tests	= $r->manifest_tests( $m );
# 		foreach my $test (@tests) {
# 			warn "        test $test\n";
# # 			$specs{ $spec }{ tests }{ $test->uri_value }++;
# 		}
# 	}
# }

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


# warn "Summary\n";
foreach my $s ($r->software) {
	my $software	= $s->uri_value;
# 	warn "\t$software\n";
	foreach my $spec ($r->specs) {
# 		warn "\t\t$spec results...\n";
# 		print table cell with software-spec conformance
	}
}

my $width	= 2 + scalar(@{ [ $r->software ] });

# warn "Specs\n";
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
		my $software	= $s->uri_value;
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

print "<p>Sources:</p>\n<ul>\n";
foreach my $source (@sources) {
	print "\t<li>$source</li>\n";
}
print "</ul>\n";

print qq[<p class="foot">$date</p>\n];

print_html_foot();


################################################################################

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
/* ]]> */
</style></head>
<body>
<h1>SPARQL 1.1 Test Results</h1>
<ul>
	<li>Specifications<ul>
		
END

	foreach my $spec ($r->specs) {
		my $name	= $r->spec_name( $spec );
		my $id		= $r->spec_id( $spec );
		print qq[\t\t<li><a href="#$id">$name</a></li>\n];
	}

	print "</ul></li></ul>\n";
}

sub print_html_foot {
	print <<'END';
$Id: $
</body>
</html>
END
}

__END__
