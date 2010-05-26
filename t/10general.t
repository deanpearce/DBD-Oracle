#!perl -w

use Test::More;

use DBI;
use Oraperl;
use Config;
use DBD::Oracle qw(ORA_OCI);


unshift @INC ,'t';
require 'nchar_test_lib.pl';

$| = 1;

plan tests => 31;

diag('Test preparsing, Active, NLS_NUMERIC_CHARACTERS, err, ping and OCI version');

my $dsn = oracle_test_dsn();
my $dbuser = $ENV{ORACLE_USERID} || 'scott/tiger';
my $dbh = DBI->connect($dsn, $dbuser, '');

unless($dbh) {
    BAIL_OUT("Unable to connect to Oracle ($DBI::errstr)\nTests skipped.\n");
    exit 0;
}

my($sth, $p1, $p2, $tmp);
SKIP: {
    skip "not unix-like", 2 unless $Config{d_semctl};
    skip "solaris with OCI>9.x", 2 unless ($^O eq "solaris") and (scalar(ORA_OCI) ge 10);

    # basic check that we can fork subprocesses and wait for the status
    # after having connected to Oracle

    is system("exit 1;"), 1<<8, 'system exit 1 should return 256';
    is system("exit 0;"),    0, 'system exit 0 should return 0';
}

$sth = $dbh->prepare(q{
	/* also test preparse doesn't get confused by ? :1 */
        /* also test placeholder binding is case insensitive */
	select :a, :A from user_tables -- ? :1
});
ok($sth->{ParamValues}, 'preparse, case insensitive, placeholders in comments');
is(keys %{$sth->{ParamValues}}, 1, 'number of parameters');
is($sth->{NUM_OF_PARAMS}, 1, 'expected number of parameters');
ok($sth->bind_param(':a', 'a value'), 'bind_param for select parameter');
ok($sth->execute, 'execute for select parameter');
ok($sth->{NUM_OF_FIELDS}, 'NUM_OF_FIELDS');
eval {
  local $SIG{__WARN__} = sub { die @_ }; # since DBI 1.43
  $p1=$sth->{NUM_OFFIELDS_typo};
};
ok($@ =~ /attribute/, 'unrecognised attribute');
ok($sth->{Active}, 'statement is active');
ok($sth->finish, 'finish');
ok(!$sth->{Active}, 'statement is not active');

$sth = $dbh->prepare("select * from user_tables");
ok($sth->execute, 'execute for user_tables');
ok($sth->{Active}, 'active for user_tables');
1 while ($sth->fetch);	# fetch through to end
ok(!$sth->{Active}, 'user_tables not active after fetch');

# so following test works with other NLS settings/locations
ok($dbh->do("ALTER SESSION SET NLS_NUMERIC_CHARACTERS = '.,'"),
  'set NLS_NUMERIC_CHARACTERS');

ok($tmp = $dbh->selectall_arrayref(q{
	select 1 * power(10,-130) "smallest?",
	       9.9999999999 * power(10,125) "biggest?"
	from dual
}), 'select all for arithmetic');
my @tmp = @{$tmp->[0]};
#warn "@tmp"; $tmp[0]+=0; $tmp[1]+=0; warn "@tmp";
ok($tmp[0] <= 1.0000000000000000000000000000000001e-130, "tmp0=$tmp[0]");
ok($tmp[1] >= 9.99e+125, "tmp1=$tmp[1]");


my $warn='';
eval {
	local $SIG{__WARN__} = sub { $warn = $_[0] };
	$dbh->{RaiseError} = 1;
	$dbh->do("some invalid sql statement");
};
ok($@    =~ /DBD::Oracle::db do failed:/, "eval error: ``$@'' expected 'do failed:'");
#print "''$warn''";
ok($warn =~ /DBD::Oracle::db do failed:/, "warn error: ``$warn'' expected 'do failed:'");
ok($DBI::err, 'err defined');
ok($ora_errno, 'ora_errno defined');
is($ora_errno, $DBI::err, 'ora_errno and err equal');
$dbh->{RaiseError} = 0;

# ---

ok( $dbh->ping, 'ping - connected');

$dbh->disconnect;
$dbh->{PrintError} = 0;
ok(!$dbh->ping, 'ping disconnected');

my $ora_oci = DBD::Oracle::ORA_OCI(); # dualvar
printf "ORA_OCI = %d (%s)\n", $ora_oci, $ora_oci;
ok("$ora_oci", 'ora_oci defined');
ok($ora_oci >= 8, 'ora_oci >= 8');
diag($ora_oci);
my @ora_oci = split(/\./, $ora_oci,-1);
ok(scalar @ora_oci >= 2, 'version has 2 or more components');
ok((scalar @ora_oci == grep { DBI::looks_like_number($_) } @ora_oci),
  'version looks like numbers');
is($ora_oci[0], int($ora_oci), 'first number is int');

exit 0;
