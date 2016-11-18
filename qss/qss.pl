#!/usr/local/bin/perl

use DBI;
use strict;
use Cwd 'abs_path';
use File::Basename;

use vars qw($db_name $db_user $db_pass $db_serverinst $db_driver);

#Define config file
my $pathname = abs_path($0);
my $scriptname = basename($0);
$pathname =~ s/\/$scriptname//;
my $config = "$pathname/qss.conf";

#Read database connection details from config
open( CONFIGFILE, "<$config" ) or die "$!";
while (<CONFIGFILE>) {
   if ( $_ =~ m/^db_name=/ ) {
      my $line = $_;
      $line =~ s/\r?\n$//;
      my @fields = split (/=/, $line);
      $main::db_name = $fields[1];
   }
   if ( $_ =~ m/^db_user=/ ) {
      my $line = $_;
      $line =~ s/\r?\n$//;
      my @fields = split (/=/, $line);
      $main::db_user = $fields[1];
   }
   if ( $_ =~ m/^db_pass=/ ) {
      my $line = $_;
      $line =~ s/\r?\n$//;
      my @fields = split (/=/, $line);
      $main::db_pass = $fields[1];
   }
   if ( $_ =~ m/^db_serverinst=/ ) {
      my $line = $_;
      $line =~ s/\r?\n$//;
      my @fields = split (/=/, $line);
      $main::db_serverinst = $fields[1];
   }
   if ( $_ =~ m/^db_driver=/ ) {
      my $line = $_;
      $line =~ s/\r?\n$//;
      my @fields = split (/=/, $line);
      $main::db_driver = $fields[1];
   }
}

# Make sure we got everything we needed from the config
if ($db_name eq ""){
   print "Error: db_name not defined in $config";
   exit 2;
}
if ($db_user eq ""){
   print "Error: db_user not defined in $config";
   exit 2;
}
if ($db_pass eq ""){
   print "Error: db_pass not defined in $config";
   exit 2;
}
if ($db_serverinst eq ""){
   print "Error: db_serverinst not defined in $config";
   exit 2;
}
if ($db_driver eq ""){
   print "Error: db_driver not defined in $config";
   exit 2;
}

# Read the command line arguments
my $sdr_in = $ARGV[0];

# Make sure an SDR number was provided
if ($sdr_in eq ""){
   exit 1;
}

my $sdr_number = $sdr_in + 0;

# Make sure the SDR number is numeric
if ($sdr_number == 0){
   print "Error: \[$sdr_in\] is not a valid SDR number.\n";
   exit 2;
}

# Create the database handle
my $dbh = DBI->connect("dbi:ODBC:DRIVER={$db_driver};SERVER=$db_serverinst;DATABASE=$db_name;UID=$db_user;PWD=$db_pass") or die("\n\nCONNECT ERROR:\n\n$DBI::errstr");
#my $dbh = DBI->connect("dbi:ODBC:DRIVER={FreeTDS};SERVER=$db_serverinst;DATABASE=$db_name;UID=$db_user;PWD=$db_pass") or die("\n\nCONNECT ERROR:\n\n$DBI::errstr");
$dbh->{LongReadLen} = 512 * 1024;

# Create the query string
my $sql = qq/SELECT CAST(summary AS TEXT) AS summary FROM call_req(nolock) WHERE ref_num='$sdr_number'
/;

# Create an array to hold our results and execute the query
my $sth = $dbh->prepare($sql);
$sth->execute();

# Read out the results one line at a time
my @row;
while (my @row = $sth->fetchrow_array) {
   print "@row\n";
}
                                                                               
$dbh->disconnect;
        
