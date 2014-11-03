################################################################################
#gt.pm is a perl module written by Joshua McClintock
#and is part of a larger suite called Graviton.
#Copyright (C) 2008 Gravity Edge Systems, LLP
#
#This program is free software; you can redistribute it and/or
#modify it under the terms of the GNU General Public License
#as published by the Free Software Foundation; either version 2
#of the License, or (at your option) any later version.
#
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with this program; if not, write to the Free Software
#Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
#You may contact the author Joshua McClintock <joshua at gravityedge dot com>
################################################################################

package gt;

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK $def_gt_cfg_ %avail_hosts_ %host_groups_);

require	Exporter;

use DB_File;
use File::Find;

@ISA = qw(Exporter);
@EXPORT	= qw(r_gt_cfg_ r_gt_db_ rw_gt_db_ set_util_loc_ de_ref_ write_log_ updt_pkgs_db_ find_all_hosts_ check_util_ver_ get_cur_tstamp_ inspect_hostconf_);
@EXPORT_OK = qw($def_gt_cfg_ %avail_hosts_ %host_groups_);
$VERSION = '1.31';

$def_gt_cfg_ = "/etc/graviton/gt.conf";
%avail_hosts_ = ();
%host_groups_ = ();

#Global Utilities
my(%cli_util_) = set_util_loc_();

#Global Configuration
my(%gtcfg_val_) = r_gt_cfg_();


### BEGIN SUBROUTINES ###

# Read in the gt.conf file and populate %gtcfg_val with name/value pairs 
# and return to caller
sub r_gt_cfg_
{
   my($cfg_opt) = @_;
   my($gtcfg);
   my(%gtcfg_val) = ( "packdir" => "",
                      "backupdir" => "",
		      "hostdir" => "",
		      "treedir" => "",
		      "dbdir" => "",
		      "bindir" => "", 
		      "logdir" => "",
		      "report_ignore" => "",
		      "infodir" => "",
		      "backup" => "7",
		      "email" => "",
		      "email_alwayson" => "",
		      "deb2gt_defbase" => "",
		      "rpm2gt_defbase" => "",
		      "debian_status" => "",
		      "redhat_rpmdb" => "" );

   if($cfg_opt)
      {
         $gtcfg = $cfg_opt;
      }
   else
      {
         $gtcfg = $def_gt_cfg_;
      }

    # Create gt.conf if it doesn't exist
    if(! -e $gtcfg)
       {
          create_gtcfg_($gtcfg);
       }

    open(GTCFG, $gtcfg) || die ("Can't open gt.conf --> $gtcfg (Reason: $!)\n");
    while(<GTCFG>)
       {
          chomp;
	  s/^#.*//;
	  next unless length;
	  my($name,$value) = split(/\s/, $_, 2);
	  if(exists $gtcfg_val{$name})
	     {
	        $gtcfg_val{$name} = $value;
	     }
	  else
	     {
	        die("Unrecognized config option: $name in line '$_' of $gtcfg\n");
             }
       }
    
    while(my($name,$value) = each(%gtcfg_val))
       {
          chomp($name,$value);
	  #print("$name:$value\n");
	  if($gtcfg_val{$name} eq "")
	     {
	        die("You must define: $name in $gtcfg\n");
             }
       }

    # Sanity check for backup
    if($gtcfg_val{backup} =~ /^\d+$/)
       {
       }
    else
       {
          die("\n\nError in $gtcfg --> backup is ($gtcfg_val{backup}), must be digits only.\n");
       }

   
   return(%gtcfg_val);
}

sub create_gtcfg_
{
   my($gtcfg) = @_;

   my @cfg = split(/\//, $gtcfg);

   pop(@cfg);

   my $cfg_path = join("/",@cfg);

   system("$cli_util_{'mkdir'} -p $cfg_path");

   open(GTCFG,">$gtcfg");
   print GTCFG ("# GT directory structure options
packdir /gt/shared/packages
backupdir /gt/local/backup
hostdir /gt/shared/hosts
treedir /gt/local/linktree
dbdir /gt/local/packagesdb
bindir /gt/bin
infodir /gt/local/info
logdir /var/log/gt

# Default mail address to send email reports to.
email youremail\@yourdomain.com
# If yes, you don't have to give the -m flag for email reports,
# they will just be sent to the default address.
email_alwayson yes

# If set to 'no', nothing will be ignored.  This is used to filter
# out itemized file changes in the GT report.
# For example:  If you no longer wish to see directories which are
# being updated because only their modify time has changed,
# you could put '\\.d\\.\\.t\\.\\.\\.\\.' as the value.  This is a regular
# expression, so you may add more statements by putting
# a | (or) inbetween your patterns, like pattern|pattern.
report_ignore \\.d\.\\.t\\.\\.\\.\\.

# Default package directory for deb2pkg to unpack .deb's into.
deb2gt_defbase debian-ix86-etch
# Default package directory for rpm2pkg to unpack .rpm's into.
rpm2gt_defbase redhat-ix86-rhel4as
# Should GT create the /var/lib/dpkg/status file based on the
# packages your host is subscribed to?
# The resulting file will be placed in {hostdir}/{hostname}/files/var/lib/dpkg
# The status file is used by apt to determine what packages are already
# installed and should only download new or updated packages.
debian_status yes

# Should GT create the /var/lib/rpm/Database files based on the packages your
# host is subscribed to?
# The resulting files will be placed in {hostdir}/{hostname}/files/var/lib/rpm
redhat_rpmdb yes

# Moving window of days of backups to keep
backup 3");
   close(GTCFG);
}

# Get current timestamp FORMAT: YYYYMMDDhhmm
sub get_cur_tstamp_
{
   my $cur_tstamp;
   open(CMD, "$cli_util_{'date'} +%Y%m%d%H%M%S|") || die "\n\nCannot open utility $cli_util_{'date'}. Reason: $!\n";
   while(<CMD>)
      {
         chomp $_;
         $cur_tstamp = $_;
      }
   close(CMD);

   return($cur_tstamp); 
}


# Set a hash with utility information
sub set_util_loc_
{
   my(%cli_util) = (
                    "cp" => get_util_loc_("cp"),
                    "cat" => get_util_loc_("cat"),
                    "cpio" => get_util_loc_("cpio"),
                    "id" => get_util_loc_("id"),
                    "ln" => get_util_loc_("ln"),
                    "rm" => get_util_loc_("rm"),
                    "find" => get_util_loc_("find"),
                    "mail" => get_util_loc_("mail"),
                    "mv" => get_util_loc_("mv"),
                    "mkdir" => get_util_loc_("mkdir"),
                    "date" => get_util_loc_("date"),
                    "echo" => get_util_loc_("echo"),
                    "touch" => get_util_loc_("touch"),
                    "dpkg" => get_util_loc_("dpkg"),
                    "dpkg-deb" => get_util_loc_("dpkg-deb"),
                    "rpm" => get_util_loc_("rpm"),
                    "rpm2cpio" => get_util_loc_("rpm2cpio"),
                    "rsync" => get_util_loc_("rsync"),
                    "ssh" => get_util_loc_("ssh")
                   );

}

sub check_util_ver_
{
   my($util) = @_;
   my(%cli_util) = set_util_loc_();
   
   my($ver_arg,$ver_approve,$ver_pattern,$proto_ver_approve);
   if($util eq "rsync")
      {
         $ver_arg = "--version";
	 $proto_ver_approve = "29";
	 $ver_approve = "2.6.5";
	 $ver_pattern = "^rsync  version (.*)  protocol version (.*)";

         open(UTIL, "$cli_util{$util} $ver_arg|") || die("Cannot open $cli_util{$util}. Reason: $!\n");
         while(<UTIL>)
            {
               chomp $_;
	       /($ver_pattern)/;
	       my $ver_pattern = $2;
	       my $proto_pattern = $3;
               if($proto_pattern < $proto_ver_approve && $proto_pattern =~ /\d+/)
	          {
	             die("Rsync Protocol Version: $proto_pattern is lower than the requirement: $proto_ver_approve\n");
	          }
            }
         close(UTIL);
      }
}


# Get the full path's for all GNU/Other utilities
sub get_util_loc_
{
   my($util) = @_;
   
   my $util_loc;
   open(WHICH, "which $util 2>&1 |") || die("Cannot find \"which\". Reason: $!\n");
   while(<WHICH>)
      {
         chomp $_;
         if(/^\/.*($util)$/)
            {
               $util_loc = $_;
            }
         elsif(/which: no ($util) in/)
            {
               die("\n\nRequired utility \"$util\" not found.\n\nPATH:$ENV{PATH}\n\n");
            }
         else
            {
               die("$_");
            }
      }
   close(WHICH);

   return($util_loc);
}


# Open a berkeley db and return it the %ret_db hash.
sub r_gt_db_
{
   my($gt_db) = @_;
   my(%db,%ret_db);

   tie(%db, "DB_File", $gt_db) || die("Cannot access $gt_db\n");
   %ret_db = %db;
   untie(%db);
   return %ret_db;
}

# Open a berkeley db, apply changes, and close it.
sub rw_gt_db_
{
   my($db,$type,$key,$value) = @_;
   #print("DB: $db TYPE: $type KEY: $key VALUE: $value\n");
   my(%rw_db);

   tie(%rw_db, "DB_File", $db) || die("Cannot access $db\n");
   
   $rw_db{$key} = $value;

   if($type eq "")
      {
         $type = "unknown";
      }
   
   $rw_db{dbtype} = $type;

   untie(%rw_db);
}

sub de_ref_
{
   my($ref,$type) = @_;

   #print("DEBUG: $type\n");

   my %hash;
   my @array;

   if($type eq "hash")
      {
         if(defined($ref))
	    {
	       %hash = %$ref;
	       return(%hash);
	    }
	 else
	    {
	       return(%hash);
	    }
      }
   elsif($type eq "array")
      {
         foreach my $item (@{$ref})
	    {
	       push(@array,$item);
	    }
	 return(@array);
      }
   else
      {
         die("Incorrect type defined!\n");
      }
}

sub write_log_
{
   my($log,$mesg) = @_;
   my $date = `$cli_util_{date}`;
   chomp $date;
   open(LOG, ">>$gtcfg_val_{logdir}/$log") || die("Cannot open $gtcfg_val_{logdir}/$log. Reason: $!\n");
   print LOG "$date: $mesg";
   close(LOG);
}

sub updt_pkgs_db_
{
   my($base,$section,$name,$version) = @_;
   rw_gt_db_("$gtcfg_val_{infodir}/packages.db","gtdbgen","[$base]:::$section/$name/$version",1);
}

sub find_all_hosts_
{
   find(\&process_hostdir_, $gtcfg_val_{hostdir});
}

sub process_hostdir_
{
   if(/^files$/ and $File::Find::prune = 1 and -e "$File::Find::dir/host.conf")
     {
        my(@directory) = split(/\//, $File::Find::dir);
        my $groups = inspect_hostconf_("groups",$File::Find::dir);
        my @grouplist = split(/,/, $groups);
        foreach(@grouplist)
           {
              #Since Find seems to see other directories after hitting the 
              #if(-e ...) above, we do this to prevent duplicates from showing 
              #up in $host_groups_.
              if(! $avail_hosts_{$directory[-1]})
                 {
                    $host_groups_{$_} .= "$directory[-1],";
                 }
           }
        $avail_hosts_{$directory[-1]} = $File::Find::dir;
     }
}

sub inspect_hostconf_
{
   my($type,$host) = @_;
   my($field,$value);
   open(HOSTCONF, "$host/host.conf") || die "Cannot open: $host/host.conf Reason: $!\n";
   while(<HOSTCONF>)
      {
         chomp $_;
         s/#.*//; # Get rid of comments
         next unless length;
         ($field,$value) = split(/\s/, $_, 2);
         if($field eq $type)
            {
               return $value;
            }
         else
            {
               next;
            }
      }
   close(HOSTCONF);
}

1;

__END__
