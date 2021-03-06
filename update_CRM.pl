#!/usr/bin/perl
use warnings;
use strict;
$SIG{__WARN__} = sub { die @_ };
$| = 1; 

use Cwd 'abs_path','chdir';
use File::Basename;

BEGIN {
    my $path_prefix = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."";
    my $need= "$path_prefix/instantclient_11_2/";
    my $ld= $ENV{LD_LIBRARY_PATH};
    if(  ! $ld  ) {
        $ENV{LD_LIBRARY_PATH}= $need;
    } elsif(  $ld !~ m#(^|:)\Q$need\E(:|$)#  ) {
        $ENV{LD_LIBRARY_PATH} .= ':' . $need;
    } else {
        $need= "";
    }
    if(  $need  ) {
        exec 'env', $^X, $0, @ARGV;
    }
}

#
# hash:
#     event number 0
# 	$info->{'cust_category'}
# 	$info->{'customer'}
# 	$info->{'date'}->{'date'}
# 	$info->{'date'}->{'time'}
# 	$info->{'desc'}
# 	$info->{T,B,.N}
# 	$info->{'incharge'}->{'email'}
# 	$info->{'incharge'}->{'first_name'}
# 	$info->{'incharge'}->{'last_name'}
# 	$info->{'incharge'}->{'job'}	-- not used
# 	$info->{'last_date'}->{'date'}	-- not used
# 	$info->{'last_date'}->{'time'}	-- not used
# 	$info->{'mind_category'}
# 	$info->{'number'}
# 	$info->{'priority'}->{'color'}	-- not used
# 	$info->{'priority'}->{'desc'}	-- not used
# 	$info->{'solution'}
# 	$info->{'subject'}
# 	$info->{'type'}
#
#     event number N
# 	$info->{N}->{'customer_contact'}->{'department'}
# 	$info->{N}->{'customer_contact'}->{'email'}
# 	$info->{N}->{'customer_contact'}->{'first_name'}
# 	$info->{N}->{'customer_contact'}->{'last_name'}
# 	$info->{N}->{'customer_contact'}->{'position'}
# 	$info->{N}->{'date'}->{'date'}
# 	$info->{N}->{'date'}->{'time'}
# 	$info->{N}->{'description'}
# 	$info->{N}->{'event'}->{'code'}
# 	$info->{N}->{'event'}->{'desc'}
# 	$info->{N}->{'person'}->{'email'}
# 	$info->{N}->{'person'}->{'first_name'}
# 	$info->{N}->{'person'}->{'last_name'}
# 	$info->{N}->{'person'}->{'job'}	-- not used
# 	$info->{N}->{'reference'}
# 	$info->{N}->{'short_desc'}
# 	$info->{N}->{'show_to_customer'}
# 	$info->{N}->{'status'}->{'code'}
# 	$info->{N}->{'status'}->{'desc'}

# $path_prefix = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."";
use lib (fileparse(abs_path($0), qr/\.[^.]*/))[1]."our_perl_lib/lib";
use DBI;
use Net::FTP;
use LWP::UserAgent;
use File::Path qw(make_path remove_tree);
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use Getopt::Std; 
my $options = {};
getopts("d:n:", $options); 

my $path_prefix = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."";
use Log::Log4perl qw(:easy);
Log::Log4perl->init("$path_prefix/log4perl.config");
sub logfile {
  my @tmp1 = fileparse(abs_path($options->{'d'}), qr/\.[^.]*/);
  my $name = $tmp1[0].$tmp1[2];
  return "/var/log/mind/wiki_logs/wiki_import_$name";
} 

my @crt_timeData = localtime(time);
foreach (@crt_timeData) {$_ = "0$_" if($_<10);}
INFO "Start: ". ($crt_timeData[5]+1900) ."-".($crt_timeData[4]+1)."-$crt_timeData[3] $crt_timeData[2]:$crt_timeData[1]:$crt_timeData[0].\n";

use File::Listing qw(parse_dir);
use File::Find;
use File::Copy;
use File::Find::Rule;
use Mind_work::WikiCommons;
use XML::Simple;
use Encode;
# use utf8;
use URI::Escape;
use HTML::TreeBuilder;
use Mind_work::WikiClean;
use Mind_work::WikiWork;

our ($to_path, $domain) = ($options->{d}, $options->{n});
LOGDIE "We need the destination path and the domain: m=MIND, s=Sentori, p=PhonEX. We got :$to_path and $domain.\n" if ( ! defined $to_path || ! defined $domain || $domain !~ m/^[msp]$/i);
WikiCommons::makedir ("$to_path");
$to_path = abs_path("$to_path");

    my $dept = "";
    if ($domain =~ m/m/i) {
        $dept = '(0, 1, 2, 3)';
    } elsif ($domain =~ m/p/i) {
        $dept = '(4, 9)';
    } elsif ($domain =~ m/s/i) {
        $dept = '(13)';
    } else {
        LOGDIE "All srs unknown domain: $domain.\n";
    }
#1, 3, 4, 9, 13 0-3 mind, 4,9 phonex, 13 sentori';

my $update_all = "no";
my $ftp_addr = 'https://mindeservice.com/SupportFTP/';
my $dbh;
my $event_codes = {};
my $staff = {};
my $priorities = {};
my $problem_categories = {};
my $problem_types = {};
my $servicestatus = {};
my $customers = {};

# sub get_encoding {
#     my $txt = shift;
# #     return $txt if $txt =~ m/\s*/;
# #     $txt = 'services key';
# # write_file('./1', $txt);die;
#     use Encode::Guess;# qw/latin1 utf8  cp1251 iso-8859-1 iso-8859-2/;
# #     use Encode::Guess Encode->encodings(":all");
# # INFO Dumper(Encode->encodings(":all"));exit 1;
# #     use Encode;
#     my $enc = guess_encoding($txt, qw/utf8 iso-8859-1/);
#     return '', INFO "Can't guess encoding: $enc.\n" if (!ref($enc));
# #     INFO Dumper($enc->name);
# # write_file('./test1',$txt);
# # write_file('./test',decode('latin1',$txt));
# #     my $utf = $enc->name."\n".$enc->decode($txt);
# # INFO "$utf\n";die;
# # decode('utf8',$utf);
# #     return $enc->decode($txt);
#     return $enc->name;
# }

sub print_coco {
    my ($nr, $total) = @_;
    my @array = qw( \ | / - );
    my $padded = sprintf("%05d", $nr);
    INFO "\t\t\t\trunning $padded out of $total".$array[$nr%@array]." \r";
}

sub write_file {
    my ($path, $text) = @_;
    $text = encode_utf8( $text );
    $text =~ s/\x{c2}\x{96}/-/gsi;
    open (FILE, ">$path") or LOGDIE "can't open file $path for writing: $!\n";
    print FILE "$text";
    close (FILE);
}

sub get_servicestatus {
    my $SEL_INFO = '
select t.rscservicestatuscode, t.rscservicestatusdesc
  from tblscservicestatus t';
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	$servicestatus->{$row[0]} = $row[1];
    }
}

sub get_eventscode {
    my $SEL_INFO = '
select t.rsuppeventscode, t.rsuppeventsdesc, t.rsuppeventsdefsupstatus
  from tblsuppevents t';
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	$event_codes->{$row[0]}->{'desc'} = $row[1];
	$event_codes->{$row[0]}->{'code'} = $row[2];
    }
}

sub get_staff {
    my $SEL_INFO = '
select t.rsuppstaffenggcode,
       t.rsuppstafflastname,
       t.rsuppstafffirstname,
       t.rsuppstaffemail,
       p.rtechservjobsname
  from tblsupportstaff t, tbltechservjobs p
 where t.rsuppstaffjob = p.rtechservjobscode';
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	$staff->{$row[0]}->{'last_name'} = $row[1];
	$staff->{$row[0]}->{'first_name'} = $row[2];
	$staff->{$row[0]}->{'email'} = $row[3];
	$staff->{$row[0]}->{'job'} = $row[4];
    }
}

sub get_priorities {
    my $SEL_INFO = '
select t.rsupppriorities, t.rsuppprioritiesdesc, t.colorforlistofspr
  from tblsupppriorities t';
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	$priorities->{$row[0]}->{'desc'} = $row[1];
	$priorities->{$row[0]}->{'color'} = $row[2];
    }
}

sub get_problem_categories {
    my $SEL_INFO = 'select t.rprobcatgcode, t.rprobcatgdesc from tblproblemcategories t';
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	$problem_categories->{$row[0]} = $row[1];
    }
}

sub get_problem_types {
    my $SEL_INFO = 'select t.rsctypescode, t.rsctypesdesc from tblsctypes t';
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	$problem_types->{$row[0]} = $row[1];
    }
}

sub get_customers {
    my $SEL_INFO = "select unique a.rcustcompanycode,
       a.rcustcompanyname,
       a.rcustiddisplay
  from tblcustomers a, tblsuppdept b, tbldeptsforcustomers c
 where a.rcustcompanycode = c.rdeptcustcompanycode
   and b.rsuppdeptcode = c.rdeptcustdeptcode
   and c.rcuststatus = 'A'
   and a.rcuststatus = 'A'
   and b.rsuppdeptstatus = 'A'
   and a.rcustlastscno > 0
   and c.ractivitydate = (select max(ractivitydate)
                            from tbldeptsforcustomers
                           where rdeptcustcompanycode = a.rcustcompanycode
                             and rcuststatus = 'A')
   and c.rdeptcustdeptcode in ".$dept;

    my $sth = $dbh->prepare($SEL_INFO);
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	LOGDIE "Already have this id for cust: $row[0].\n" if exists $customers->{$row[0]};
	$customers->{$row[0]}->{'name'} = $row[1];
	$customers->{$row[0]}->{'displayname'} = $row[2];
	$customers->{$row[0]}->{'dept_code'} = $row[3];
	$customers->{$row[0]}->{'dept_name'} = $row[4];
	$customers->{$row[0]}->{'last_sc_no'} = $row[5];
# 	$customers->{$row[0]}->{'ver'} = $row[3];
    }
}

sub get_allsrs {
    my $cust = shift;
#     my $SEL_INFO = "
# select t1.rsceventsscno, count(t1.rsceventssrno)
#   from tblscevents t1, tblscmainrecord t2
#  where t1.rsceventscompanycode = :CUST_CODE
#    and t1.rsceventsscno = t2.rscmainrecscno
#    and t2.rscmainreccustcode = t1.rsceventscompanycode
#    and t2.rscmainreclasteventdate >= '20000101'
#  group by t1.rsceventsscno";

    my $SEL_INFO = "
select t1.rsceventsscno, count(t1.rsceventssrno)
  from tblscevents t1
 where t1.rsceventscompanycode = :CUST_CODE
 group by t1.rsceventsscno";

    my $sth = $dbh->prepare($SEL_INFO);
    $sth->bind_param( ":CUST_CODE", $cust );
    $sth->execute();
    my $info = {};
    while ( my @row=$sth->fetchrow_array() ) {
	$info->{$row[0]} = $row[1];
    }
    return $info;
}

sub get_sr {
    my ($cust, $sc_no) = @_;
    my $SEL_INFO = '
select t.rsceventssrno,
       t.rsceventscode,
       t.rsceventsdate,
       t.rsceventstime,
       t.rsceventscreator,
       t.rsceventsshortdesc,
       t.rsceventsservicestatus,
       t.rsceventsshowcustomer,
       t.rsceventscustcontact
  from tblscevents t
 where t.rsceventscompanycode = :CUST_CODE
   and t.rsceventsscno = :SR_NR
 order by 1';
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->bind_param( ":CUST_CODE", $cust );
    $sth->bind_param( ":SR_NR", $sc_no );
    $sth->execute();
    my $info = {};
    while ( my @row=$sth->fetchrow_array() ) {
	$info->{$row[0]}->{'event'}->{$_} = $event_codes->{$row[1]}->{$_} foreach (keys %{$event_codes->{$row[1]}});
	$info->{$row[0]}->{'date'}->{'date'} = $row[2];
	$info->{$row[0]}->{'date'}->{'time'} = $row[3];
	$info->{$row[0]}->{'person'} = {};
	$info->{$row[0]}->{'customer_contact'} = get_customer_desc($cust, $row[8]);
	$info->{$row[0]}->{'person'}->{$_} = $staff->{$row[4]}->{$_} foreach (keys %{$staff->{$row[4]}});
# INFO Dumper($info->{$row[0]}->{'person'});
	$info->{$row[0]}->{'short_desc'} = $row[5];
	my $desc = get_event_desc($sc_no, $row[0], $cust);
	$info->{$row[0]}->{'description'} = $desc;
	$desc = get_event_reference($sc_no, $row[0], $cust);
	$info->{$row[0]}->{'reference'} = $desc;
	$info->{$row[0]}->{'status'}->{'code'} = $row[6];
	$info->{$row[0]}->{'status'}->{'desc'} = $servicestatus->{$row[6]} || '';
	$info->{$row[0]}->{'show_to_customer'} = $row[7];
    }
    return $info;
}

sub get_sr_desc {
    my ($customer, $srscno) = @_;
    my $info = {};
    my $SEL_INFO = '
select t.rscmainproblemdescription,
       t.rscmainreccustomerpriority,
       t.rscmainrecenggincharge,
       t.rscmainrecopendate,
       t.rscmainrecopentime,
       t.rscmainreclasteventdate,
       t.rscmainreclasteventtime,
       t.rscmainrecprobcatg,
       t.rscmainrecsctype,
       t.rscmainrecsolution,
       t.rscmainrecsubject,
       t.rscmainrectsinternalpriority
  from tblscmainrecord t
 where t.rscmainreccustcode = :CUSTOMER
   and t.rscmainrecscno = :SRSCNO';

    my $sth = $dbh->prepare($SEL_INFO);
    $sth->bind_param( ":CUSTOMER", $customer );
    $sth->bind_param( ":SRSCNO", $srscno );
    $sth->execute();
    my $ok = 0;
    while ( my @row=$sth->fetchrow_array() ) {
	$ok++;
	$info->{'desc'} = $row[0];
	$info->{'priority'}->{$_} = $priorities->{$row[1]}->{$_} foreach (keys %{$priorities->{$row[1]}});
	$info->{'incharge'}->{$_} = $staff->{$row[2]}->{$_} foreach (keys %{$staff->{$row[2]}});
	$info->{'date'}->{'time'} = $row[4];
	$info->{'date'}->{'date'} = $row[3];
	$info->{'last_date'}->{'time'} = $row[4];
	$info->{'last_date'}->{'date'} = $row[3];
	$info->{'cust_category'} = $problem_categories->{$row[7]} || $row[7];
	$info->{'type'} = $problem_types->{$row[8]};
# 	$info->{'solution'} = get_encoding(substr $row[9], 2);
	$info->{'solution'} = substr $row[9], 2;
	$info->{'subject'} = $row[10];
	$info->{'mind_category'} = $problem_categories->{$row[11]};
    }
    $info->{'number'} = $srscno;
    $info->{'customer'} = $customers->{$customer}->{'displayname'};
    INFO "Strange things for $customer:\n".Dumper($info) if $ok != 1;
    return $info;
}

sub get_customer_desc {
    my ($cust, $code) = @_;
    my $info = {};
    return $info if $code == 0;

    my $SEL_INFO = '
select t.rcustcontlastname,
       t.rcustcontfirstname,
       t.rcustcontemail,
       t.rcustcontcustdept,
       t.rcustcontposition,
       t.rcustcontdirectphone,
       t.rcustcontmobilephno
  from tblcustomercontacts t
 where t.rcustcontcompanycode = :CUSTOMER
   and t.rcustcontactcode = :CODE';

    my $sth = $dbh->prepare($SEL_INFO);
    $sth->bind_param( ":CUSTOMER", $cust );
    $sth->bind_param( ":CODE", $code );
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	$info->{'last_name'} = $row[0];
	$info->{'first_name'} = $row[1];
	$info->{'email'} = $row[2];
	$info->{'department'} = $row[3];
	$info->{'position'} = $row[4];
	$info->{'phone'} = $row[5];
	$info->{'phone_mobile'} = $row[6];
    }
    INFO "Customer code $code does not exists anymore.\n" if ! keys %$info;
    return $info;
}

sub get_event_desc {
    my ($scno, $srno, $customer) = @_;
    my $info = {};

    my $SEL_INFO = '
select t.rsceventdoctype,
       t.rsceventdocno,
       t.rsceventdocpath
  from tblsceventdoc t
 where t.rsceventdoccompanycode = :CUSTOMER
   and t.rsceventdocscno = :SCNO
   and t.rsceventsrno = :SRNO';

    my $sth = $dbh->prepare($SEL_INFO);
    $sth->bind_param( ":CUSTOMER", $customer );
    $sth->bind_param( ":SCNO", $scno );
    $sth->bind_param( ":SRNO", $srno );
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	LOGDIE "too many rows: $scno, $srno, $customer\n" if exists $info->{$row[0]};
# 	my $data = get_encoding(substr $row[2], 2);
	my $data = substr $row[2], 2;
	$data = $ftp_addr.$data if $row[0] eq 'B';
	$info->{$row[0].$row[1]} = $data;
    }
    return $info;
}

sub get_event_reference {
    my ($scno, $srno, $customer) = @_;
    my $info = {};

    my $SEL_INFO = '
select t.rscrefnum1, t.rscrefnum2
  from tblscrefnum t
 where (trim(\' \' from NVL(t.rscrefnum1, \'\')) is not null or
       trim(\' \' from NVL(t.rscrefnum2, \'\')) is not null)
   and t.rscrefcust = :CUSTOMER
   and t.rscrefscno = :SCNO
   and t.rscrefeventsrno = :SRNO';

    my $sth = $dbh->prepare($SEL_INFO);
    $sth->bind_param( ":CUSTOMER", $customer );
    $sth->bind_param( ":SCNO", $scno );
    $sth->bind_param( ":SRNO", $srno );
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	$info->{'ref1'} = $row[0];
	$info->{'ref2'} = $row[1];
    }
    return $info;
}

sub sql_connect {
    my ($ip, $sid, $user, $pass) = @_;
    $dbh=DBI->connect("dbi:Oracle:host=$ip;sid=$sid", "$user", "$pass")|| die( $DBI::errstr . "\n" );
    $dbh->{AutoCommit}    = 0;
    $dbh->{RaiseError}    = 1;
    $dbh->{ora_check_sql} = 1;
    $dbh->{RowCacheSize}  = 0;
    $dbh->{LongReadLen} = 1024 * 1024;
    $dbh->{LongTruncOk}   = 0;
}
my $q=0;
sub parse_text {
    my ($text, $extra_info) = @_;
    return $text if $text =~ m/^\s*$/;

    my $init_text = $text;
    $text =~ s/\r?\n/\n/g;
    if (defined $extra_info) {
	my $tmp = quotemeta $extra_info->{'subject'};
	$text =~ s/Subject:[ ]+$tmp\nDate:[ ]+$extra_info->{event_date}\n+//;
	$tmp = quotemeta("*************************************************");
	my $reg_exp = "(
MIND CTI Support Center|
MindBill Support|
CMS|
Enterprise Solutions Support|
Sentori Support Center|
MIND CTI eService, USA Center|
MIND CTI eService, Israel Center)\n+[a-zA-Z0-9 ,]{0,}\n+$tmp\n+Service Call Data:\n+Number:[ ]+$extra_info->{'customer'} \/ $extra_info->{'sr_no'}\n+Received:[ ]+($extra_info->{sr_date}|$extra_info->{sr_usa_date})\n+Current Status:[ ]+[a-zA-Z0-9 ]{1,}\n+$tmp\n+PLEASE DO NOT REPLY TO THIS EMAIL - Use the CRM\n*";
	$text =~ s/$reg_exp//gs;
    }
#     my $enc = get_encoding($text);
# # INFO "$enc\n";exit 1;
#     if ($enc ne "utf8" && $enc ne ""){
#     Encode::from_to($text, "$enc", "utf8");
# use Encode;
#     $text = Encode::decode("utf8", $text);
#     utf8::upgrade($text);
# # 	$text = WikiClean::fix_wiki_chars( $text );
#     }
# INFO "$text\n";exit 1;

    $text =~ s/(\n){2,}/\n\n\n/gs;
    $text =~ s/([^\n])\n([^\n])/$1\n\n$2/gs;
    $text = WikiClean::fix_small_issues($text);
    $text =~ s/(~{3,})/<nowiki>$1<\/nowiki>/gm;
    $text =~ s/(\[\[)/<nowiki>$1<\/nowiki>/gm;
    $text = WikiClean::fix_wiki_link_to_sc( $text );
    $text =~ s/^(\*|\#|\;|\:|\=|\!|\||----|\{\|)/<nowiki>$1<\/nowiki>/gm;
    $text =~ s/(\[mailto:)/<nowiki>$1<\/nowiki>/gm;
    $text =~ s/(\[https?:)/<nowiki>$1<\/nowiki>/gm;
    $text =~ s/<!--/<nowiki><!--<\/nowiki>/gm;

    return $text;
}

sub write_intro {
    my ($hash, $date, $time) = @_;
    my $wiki =  "<center>\'\'\'$hash->{'subject'}\'\'\'</center>\n";
    $wiki .=  "<p align=\"right\">$time $date</p>\n\n";
    $wiki .=  "\'\'\'Incharge\'\'\': $hash->{'incharge'}->{'first_name'} $hash->{'incharge'}->{'last_name'} ([mailto:$hash->{'incharge'}->{'email'} $hash->{'incharge'}->{'email'}])\n" if (keys %{$hash->{'incharge'}});
    my $type = $hash->{'type'} || '';
    $wiki .="
{| class=\"wikitable\"
| \'\'\'Type\'\'\'
| \'\'\'Category\'\'\'
| \'\'\'Customer category\'\'\'
|-
| $type
| $hash->{'mind_category'}
| $hash->{'cust_category'}
|}\n\n";
    my $text = parse_text($hash->{'solution'}, undef);
    my $tmp = parse_text($hash->{'desc'}, undef);
    $wiki .=  "\'\'\'Description\'\'\': $tmp\n\n";
    $wiki .=  "\'\'\'Solution\'\'\':\n\n$text\n----\n";
    return $wiki;
}

sub get_time_date {
    my $hash = shift;
    my $time = (substr $hash->{'time'}, 0 , 2).":".(substr $hash->{'time'}, 2 , 2).":".(substr $hash->{'time'}, 4);
    my $d = substr $hash->{'date'}, 6;
    my $m = substr $hash->{'date'}, 4 , 2;
    my $y = substr $hash->{'date'}, 0 , 4;
    my $date = "$d/$m/$y";
    my $usa_date = "$m/$d/$y";
    return ($date, $usa_date, $time);
}

sub write_header {
    my ($hash, $name, $date, $time, $key) = @_;
#     $wiki .= "<font color=\"#888888\">\n";
    my $wiki .= "<div style=\"background-color:#FDE4AD;\">\n<p>";
    $wiki .= "\n----\n";
    my $tmp = $hash->{'short_desc'};
    $tmp = parse_text($tmp, undef);

    $wiki .= "\'\'\'Description\'\'\': $tmp ";
    $wiki .= "<div style=\"float: right;\">$time $date</div>\n\n";
    $wiki .= "\'\'\'From\'\'\': $name\n\n";
    $wiki .= "\'\'\'Event $key\'\'\': $hash->{event}->{desc} ($hash->{event}->{code}) \'\'\'Status\'\'\': $hash->{status}->{desc} ($hash->{status}->{code}) <div style=\"float: right;\">\'\'\'Customer visible\'\'\': $hash->{show_to_customer}</div>\n\n";
    $wiki .= "----\n";
    $wiki .= "</p>\n</div>\n\n";
    return $wiki;
}

sub get_color {
    my ($hash, $extra_info, $date, $time) = @_;
    my $event_from_mind = 0;
    my $name = "";
    my $color = "";

    $extra_info->{'event_date'} = "$date";
    if ($hash->{'show_to_customer'} ne '1') {
	### this is a mind message
	$color = "<font color=\"grey\">\n";
	if (scalar keys %{$hash->{'person'}}) {
	    $name = "$hash->{'person'}->{'first_name'} $hash->{'person'}->{'last_name'} ([mailto:$hash->{'person'}->{'email'} $hash->{'person'}->{'email'}])";
	}
	$event_from_mind = 1;
    } elsif (keys %{$hash->{'person'}}) {
	### this is a mind message
	$color = "<font >\n";
	$name = "$hash->{'person'}->{'first_name'} $hash->{'person'}->{'last_name'} ([mailto:$hash->{'person'}->{'email'} $hash->{'person'}->{'email'}])";
	$event_from_mind = 1;
    } elsif (keys %{$hash->{'customer_contact'}}) {
	### this is a customer message
	$color = "<font color=\"blue\">\n";
	my $department = "";
	my $pos = "";
	$department = "department = $hash->{customer_contact}->{department}" if $hash->{'customer_contact'}->{'department'} ne ' ';
	$pos = "position = $hash->{customer_contact}->{position}" if $hash->{'customer_contact'}->{'position'} ne ' ';
	$name = "$hash->{'customer_contact'}->{'first_name'} $hash->{'customer_contact'}->{'last_name'} ([mailto:$hash->{'customer_contact'}->{'email'} $hash->{'customer_contact'}->{'email'}]);\nPhone = $hash->{'customer_contact'}->{'phone'}; Mobile phone = $hash->{'customer_contact'}->{'phone_mobile'}\n$department; $pos";
    } else {
	$color = "<font color=\"#0000FF\">\n";
	INFO "\tNo customer and no mind engineer. Maybe a customer message.\n";
    }
    $name = parse_text($name, undef);
    $name =~ s/(<nowiki>)(\[mailto:)(<\/nowiki>)/$2/gm;  ### fix parse_text
    return ($name, $color, $event_from_mind);
}

sub write_sr {
    my $info = shift;
    my @keys = keys %$info;
    LOGDIE "pai da de ce?\n".Dumper($info) if scalar keys %{$info->{$keys[0]}} < 2 ;
    my $extra_info = {};
    my $wiki = "";
    foreach my $key (sort {$a<=>$b} keys %$info){
	my $hash = $info->{$key};
	my ($date, $usa_date, $time) = get_time_date($hash->{'date'});
	if ($key == 0){
	    $wiki = write_intro($hash, $date, $time);
	    $extra_info->{'sr_date'} = "$date";
	    $extra_info->{'sr_usa_date'} = "$usa_date";
	    $extra_info->{'customer'} = "$hash->{'customer'}";
	    $extra_info->{'sr_no'} = "$hash->{'number'}";
	    $extra_info->{'subject'} = "$hash->{'subject'}";
	} else {
	    my ($name, $color, $event_from_mind) = get_color($hash, $extra_info, $date, $time);
	    ### Header
	    if ( ! defined $hash->{'event'} ){
		INFO "No event code for event $key.\n";
		$hash->{'event'}->{'code'} = '';
		$hash->{'event'}->{'desc'} = '';
	    }
	    $wiki .= write_header($hash, $name, $date, $time, $key);
	    my $ref = $hash->{'reference'};

	    my $attachements = "";
	    my $sr_text = "";
	    foreach my $desc (sort keys %{$hash->{'description'}}){
		if ( $desc =~ m/^T[0-9]{1}$/) {
		    my $text = parse_text($hash->{'description'}->{$desc}, $event_from_mind?$extra_info:undef);
		    $sr_text .= "$text\n\n";
		} elsif ( $desc =~ m/^B[0-9]{1,2}$/) {
		    my $text = $hash->{'description'}->{$desc};
		    $text =~ s/&amp;/&/g;
		    my @arr = split '/', $text;
		    $text =~ s/ /%20/g;
		    my $see = $arr[-1];
		    $see =~ s/^[0-9]{1,}-//;
		    $attachements .= "[$text $see]\n\n";
		} elsif ( $desc =~ m/^U2$/) {
		    $attachements .= "$hash->{'description'}->{$desc}\n\n";
		} elsif ( $desc =~ m/^ [1-9]{1}$/) {
		    my $text = parse_text($hash->{'description'}->{$desc}, $event_from_mind?$extra_info:undef);
		    $sr_text .= "$text\n\n";
		} else {
		    LOGDIE "Unknown event: $desc.$info->{0}->{'number'}\n";
		}
	    }
	    my $reference =  $ref->{'ref1'};
	    if ( defined $reference && $reference !~ m/^\s*$/ ){
		my @arr_ref = split /[,\.;:_\-\s\/+&]/, $reference;
		my $replacement = "";
		foreach my $sc_ref (@arr_ref) {
		    $sc_ref =~ s/^\s*SC\s*//;
		    if ($sc_ref =~ m/^\s*$/ || $sc_ref !~ m/^\s*[a-z][0-9]{3,}\s*$/i ){
		      $replacement .= "$sc_ref ";
		    } else {
		      $replacement .= "[[SC:$sc_ref|$sc_ref]] ";
		    }
		}
		$attachements .= "\n\nSC reference: $replacement" if $replacement !~ m/^\s*$/;
	    }
	    $wiki .= "$color\n$sr_text\n$attachements\n</font>\n" if ($sr_text ne '' || $attachements ne '');
	    $wiki .= "----\n";
	}
    }
    $wiki .= "\n\n[[Category:$info->{0}->{'customer'} -- CRM]]\n\n";
    $wiki =~ s/\x{ef}\x{bf}\x{bd}/?/gsi;

    return $wiki;
}

sub get_previous {
    my $dir = shift;
    my $info = {};
    opendir(DIR, "$dir") || LOGDIE "Cannot open directory $dir: $!.\n";
    my @files = grep { (!/^\.\.?$/) && -f "$dir/$_" && "$_" ne "attributes.xml" && "$_" =~ m/\.wiki$/ && -s "$dir/$_" } readdir(DIR);
    closedir(DIR);
    foreach my $file (@files){
	my $str = $file;
	$str =~ s/\.wiki$//;
	$str =~ s/^0*//;
	my @tmp = split '_', $str;
	$info->{$tmp[0]."_".$tmp[1]} = $file;
    }
    return $info;
}

sub get_previous_customers {
    my $dir = shift;
    my $info = {};
    opendir(DIR, "$dir") || LOGDIE "Cannot open directory $dir: $!.\n";
    my @alldirs = grep { (!/^\.\.?$/) && -d "$dir/$_" } readdir(DIR);
    closedir(DIR);
    foreach my $adir (@alldirs){
	$info->{$adir} = 1;
    }
    return $info;
}

# select * from tblscmainrecord t where t.rscmainreccustcode = 309 and t.rscmainrecscno = 25;
$ENV{NLS_LANG} = 'AMERICAN_AMERICA.AL32UTF8';
# $ENV{NLS_NCHAR} = 'AMERICAN_AMERICA.UTF8';
sql_connect('10.0.10.92', 'BILL', 'service25', 'service25');
WikiCommons::reset_time();
local $| = 1;
INFO "-Get common info.\n";
get_eventscode();
get_customers();
get_staff();
get_priorities();
get_problem_categories();
get_problem_types();
get_servicestatus();
INFO "+Get common info.\n";

my $crt_cust = get_previous_customers($to_path);
my @new_cust_arr = ();

foreach my $cust (sort keys %$customers){
    INFO "\n\tStart for customer $customers->{$cust}->{'displayname'}/$customers->{$cust}->{'name'}:$cust.\n";
# next if $customers->{$cust}->{'displayname'} ne "SIW";
#     next if (! defined $customers->{$cust}->{'ver'} || $customers->{$cust}->{'ver'} lt "5.00")
# 	    && $customers->{$cust}->{'displayname'} ne "Billing";
# 	    && $customers->{$cust}->{'displayname'} !~ m/mtpcs/i;
    push @new_cust_arr, $customers->{$cust}->{'displayname'};
    my $dir = "$to_path/".$customers->{$cust}->{'displayname'};
    my $crt_srs = get_allsrs($cust);
    next if (! scalar keys %$crt_srs);
    WikiCommons::makedir ("$dir");
    my $prev_srs = get_previous("$dir");
    foreach my $key (keys %$crt_srs) {
	last if $update_all eq "yes";
	my $str = $key."_".$crt_srs->{$key};
	if (exists $prev_srs->{$str}) {
	    delete $prev_srs->{$str} ;
	    delete $crt_srs->{$key} ;
	}
    }

    INFO "\tremove ".(scalar keys %$prev_srs)." old files.\n";
    foreach my $key (keys %$prev_srs) {
	unlink("$dir/$prev_srs->{$key}") or LOGDIE "Could not delete the file $dir/$prev_srs->{$key}: ".$!."\n";
    }
    my $total = scalar keys %$crt_srs;
    INFO "\tadd $total new files.\n";
    my $nr = 0;
    foreach my $sr (sort {$a<=>$b} keys %$crt_srs) {
	my $info = {};
	$info = get_sr($cust, $sr);
	my $name = "$dir/".sprintf("%07d", $sr)."_".(scalar keys %$info);
	$info->{'0'} = get_sr_desc($cust, $sr);
	next if ! defined $info->{'0'}->{'desc'};
	my $txt = write_sr($info);
	write_file ( "$name.wiki", $txt);
	print_coco(++$nr, $total);
    }
}

### remove old dirs
my @arr2 = (keys %$crt_cust);
my ($only_in_arr1, $only_in_arr2, $intersection) = WikiCommons::array_diff( \@new_cust_arr, \@arr2 );
remove_tree("$to_path/$_") || LOGDIE "Can't remove dir $to_path/$_: $?.\n" foreach (@$only_in_arr2);

$dbh->disconnect if defined($dbh);
INFO "Done.\n";
