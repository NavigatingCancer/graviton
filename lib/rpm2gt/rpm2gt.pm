################################################################################
#rpm2gt is a perl module written by Joshua McClintock
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

package rpm2gt;

use strict;
use gt;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

require Exporter;

@ISA = qw(Exporter);
@EXPORT = qw(rpm_get_info_ rpm_extract_info_ rpm_get_deps_ rpm_get_prov_ rpm_get_scripts_ rpm_get_filelist_ rpm_updt_provides_db_ rpm_cmp_frag_ rpm_cmp_version_ rpm_order_);
$VERSION = '1.32';

#Global Configuration
my %gtcfg_val = r_gt_cfg_();

#Global Utilities
my(%cli_Util) = set_util_loc_();


### BEGIN SUBROUTINES ###

sub rpm_get_info_
{
   my($rpm_package,$tree_package,$mode,$control_ref) = @_;
   my(%control) = de_ref_($control_ref,"hash");
   if($mode eq "rpmpkg")
      {
         open(CONTROL, "$cli_Util{rpm} -qpi $rpm_package|") || die "Couldn't open package $rpm_package to get it's information. Reason: $!\n";
      }
   elsif($mode eq "rpmcontrol")
      {
         open(CONTROL, "$tree_package") || die "Couldn't open control file $tree_package to get it's information.  Reason: $!\n";
      }
   else
      {
         die("Incorrect mode ($mode) passed, must be either rpmpkg or rpmcontrol.\n");
      }

   while(<CONTROL>)
      {
         next unless length;
	 if(/(|\s)[A-Z].*:\s/)
	    {
               #Name:,Version:,Release:,Group:
	       my $line = $_;
	       chomp $line;
               # Replace any multiple spaces with 2 spaces
               $line =~ s/\s\s+/  /g;
	       $line =~ /^(Name|Version|Release|Group)\s+:\s([A-Za-z0-9\_\+\-\.\s\/]+)\s\s.*$/;
	       my($label,$value) = ($1,$2);
	       if($label eq "Name" || $label eq "Version" || $label eq "Release")
	          {
	             $control{$label} = $value;
	          }
	       #Special case for group since the value can have space in it which would mess us up
	       if($label eq "Group")
	          {
		     $value =~ s/\s/_/g;
		     $control{$label} = $value;
		  }
	       else
	          {
	             next;
	          }
            }
	 else
	    {
	       next;
	    }
      }
   close(CONTROL);

   return(%control);
}

sub rpm_get_deps_
{
   my($rpm_package,$tree_package,$mode,$control_ref) = @_;
   my(%control) = de_ref_($control_ref,"hash");
   if($mode eq "rpmpkg")
      {
         open(CONTROL, "$cli_Util{rpm} -qp -R $rpm_package|") || die "Couldn't open package $rpm_package to get it's dependencies. Reason: $!\n";
      }
   elsif($mode eq "rpmcontrol")
      {
         open(CONTROL, "$tree_package") || die "Couldn't open control file $tree_package to get it's dependencies. Reason: $!\n";
      }
   else
      {
         die("Incorrect mode ($mode) passed, must be either rpmpkg or rpmcontrol.\n");
      }

   while(<CONTROL>)
      {
         next unless length;
	 my $line = $_;
	 chomp $line;
	 ($line,undef) = split(/\s.*\s/, $line, 2);
         #print("DEBUG DEPEND: $line\n");
	 $control{Depends} .= "$line,";
      }
   #Take off the last comma
   chop($control{Depends});

   return(%control);
}

sub rpm_get_prov_
{
   my($rpm_package,$tree_package,$mode,$control_ref) = @_;
   my(%control) = de_ref_($control_ref,"hash");
   if($mode eq "rpmpkg")
      {
         open(CONTROL, "$cli_Util{rpm} -qp --provides $rpm_package|") || die "Couldn't open package $rpm_package to get it's provides. Reason: $!\n";
      }
   elsif($mode eq "rpmcontrol")
      {
         open(CONTROL, "$tree_package") || die "Couldn't open control file $tree_package to get it's provides. Reason: $!\n";
      }
   else
      {
         die("Incorrect mode ($mode) passed, must be either rpmpkg or rpmcontrol.\n");
      }

   while(<CONTROL>)
      {
         next unless length;
	 my $line = $_;
	 chomp $line;
	 $line =~ s/\s+$//;
	 ($line,undef) = split(/\s<=\s|\s>=\s|\s=\s/, $line, 2);
	 $control{Provides} .= "$line,";
      }
   #Take off the last comma
   chop($control{Provides});

   return(%control);
}

sub rpm_get_filelist_
{
   my($rpm_package,$tree_package,$mode,$control_ref) = @_;
   my(%control) = de_ref_($control_ref,"hash");
   if($mode eq "rpmpkg")
      {
         open(CONTROL, "$cli_Util{rpm} -qp --list $rpm_package|") || die "Couldn't open package $rpm_package to get it's file list. Reason: $!\n";
      }
   elsif($mode eq "rpmcontrol")
      {
         open(CONTROL, "$tree_package") || die "Couldn't open control file $tree_package to get it's file list. Reason: $!\n";
      }
   else
      {
         die("Incorrect mode ($mode) passed, must be either rpmpkg or rpmcontrol.\n");
      }

   while(<CONTROL>)
      {
         next unless length;
	 my $line = $_;
	 chomp $line;
	 $line =~ s/\s+$//;
	 $control{FileList} .= "$line,";
      }
   #Take off the last comma
   chop($control{FileList});

   return(%control);
}

sub rpm_get_scripts_
{
   my($rpm_package,$name,$finaldest) = @_;
   open(RPM, "$cli_Util{rpm} -qp --scripts $rpm_package|") || die "Couldn't open package $rpm_package to get it's scripts. Reason: $!\n";
   
   my($scr_name,%scripts);
   while(<RPM>)
      {
         next unless length;
	 my $line = $_;
	 chomp $line;
	 if($line =~ /^(\w+)\sscriptlet\s/)
	    {
	       $scr_name = $1;
	       next;
	    }
	 open(SCR, ">>$finaldest/redhat/$scr_name");
	 print SCR ("$line\n");
	 close(SCR);
	 if($scr_name ne "")
	    {
	       $scripts{$scr_name}++;
	    }
	 else
	    {
	       next;
	    }
      }
   close(RPM);

   #Put scripts in /var/lib/rpm-scripts
   if(%scripts)
      {
         system("$cli_Util{mkdir} -p $finaldest/files/var/lib/rpm-scripts");
         while(my($key,$val) = each(%scripts))
            {
               chmod(0755, "$finaldest/redhat/$key");
               system("$cli_Util{cp} -a $finaldest/redhat/$key $finaldest/files/var/lib/rpm-scripts/$name.$key");
            }
      }
}
	  
sub rpm_extract_info_
{
   my(%control) = @_;

   my($name) = $control{Name};
   my($version) = $control{Version};
   my($release) = $control{Release};
   my($group) = $control{Group};
   my(@provides) = split(/,/, $control{Provides});
   my(@depends) = split(/,/, $control{Depends});
   my(@filelist) = split(/,/, $control{FileList});

   return($name,$version,$release,$group,\@provides,\@depends,\@filelist);
}

sub rpm_updt_provides_db_
{
   my($package,$base,@provides) = @_;

   my %provides_db = r_gt_db_("$gtcfg_val{infodir}/$base" . "_provides.db");

   #Tag the DB with dbtype
   if(! $provides_db{"dbtype"})
      {
         rw_gt_db_("$gtcfg_val{infodir}/$base" . "_provides.db","provides",undef,undef);
      }
   
   foreach my $item (@provides)
      {
         $item =~ s/\s//g;
	 ($item,undef) = split(/<=|>=|=/, $item, 2);
         #print("ITEM: $item PROVIDED BY: $package\n");
         #Grab the provider packages into an array
         my @prov_ray = split(/,/, $provides_db{$item});
         #Throw values into a hash so we can test what's new (if anything)
         my %prov_hash;
         foreach(@prov_ray)
            {
               $prov_hash{$_}++;
            }
         #If provider isn't in the list for the 'item', add it to the hash   
         if(! $prov_hash{$package})
            {
              $prov_hash{$package}++;
            }
         #Throw final list back into a (fresh) array.
         @prov_ray = ();
         while(my($key,$value) = each(%prov_hash))
            {
               push(@prov_ray,$key);
            }
         # Try to make x86_64 first if it's there
         @prov_ray = sort(@prov_ray);
         @prov_ray = reverse(@prov_ray);
         #Create comma delimted list of providers
         my $prov_list = join(",", @prov_ray);

         rw_gt_db_("$gtcfg_val{infodir}/$base" . "_provides.db","provides",$item,$prov_list);
      }
}

# This sub written by Sam Vanderhyden (sam.vanderhyden@gmail.com)
sub rpm_cmp_frag_
{
   my ($frag1,$frag2) = @_;
   if(length($frag1)<=0 && length($frag2)<=0)
      {
         return 0;
      }
   if(length($frag1)<=0)
      {
         if($frag2 =~ /^~/)
	    {
	       return 1;
	    }
               return -1;
      }
   if(length($frag2)<=0)
      {
         if($frag1 =~ /^~/)
	    {
	       return -1;
	    }
	       return 1;
      }
   
   my @fragA = split(//,$frag1);
   my @fragB = split(//,$frag2);

											    
   my $a = 0;
   my $b = 0;
   while($a < length($frag1) && $b < length($frag2))
      {
         my $first_diff = 0;
	 while($a < length($frag1) && $b < length($frag2) && ($fragA[$a]!~/^\d/ || $fragB[$b]!~/^\d/))
	    {
               my $vc = rpm_order_($fragA[$a]);
               my $rc = rpm_order_($fragB[$b]);
               if($vc != $rc)
	          {
                     return $vc-$rc;
		  }
	       $a++;
	       $b++;
            }
         while(defined($fragA[$a]) && $fragA[$a] eq '0')
	    { 
               $a++;
	    }
         while(defined($fragB[$b]) && $fragB[$b] eq '0')
	    {
               $b++;
            }
         while(defined($fragA[$a]) && defined($fragB[$b]) && $fragA[$a]=~/^\d/ && $fragB[$b]=~/^\d/)
            {
               if($first_diff == 0)
	          {
                     $first_diff = $fragA[$a] - $fragB[$b];
	          }
	       $a++;
	       $b++;
            }
         if(defined($fragA[$a]) && $fragA[$a]=~/^\d/)
	    {
	       return 1;
	    }
         if(defined($fragB[$b]) && $fragB[$b]=~/^\d/)
	    {
               return -1;
            }
         if($first_diff != 0)
	    {
	       return $first_diff;
            }
     }
   if($a == length($frag1) && $b == length($frag2))
      {
         return 0;
      }
   if($a == length($frag1))
      {
         if($fragB[$b-1] eq '~')
	    {
	       return 1;
	    }
               return -1;
      }
   if($b == length($frag2))
      {
         if($fragA[$a-1] eq '~')
	    {
	       return -1;
	    }
	       return 1;
      }
   return 1;
}

# This sub written by Sam Vanderhyden (sam.vanderhyden@gmail.com)
sub rpm_cmp_version_
{
   my $ver1_str = shift;
   my $ver2_str = shift;
   #find the epoch
   my $epoch1 = "";
   my $epoch2 = "";
   if($ver1_str =~ /(.*?:)/)
      {
         $epoch1 = $1;
      }
   if($ver2_str =~ /(.*?:)/)
      {
         $epoch2 = $1;
      }
   my $res = rpm_cmp_frag_($epoch1,$epoch2);
   if($res != 0)
      {
         return $res;
      }
   my $up1 = "";
   my $up2 = "";
   my $rpm1 = "";
   my $rpm2 = "";
   if($ver1_str =~ /(.*)-(.*)/)
      {
         $up1 = $1;
         $rpm1 = $2;
      }
   else
      {
         $up1 = $ver1_str;
      }
   if($ver2_str =~ /(.*)-(.*)/)
      {
         $up2 = $1;
         $rpm2 = $2;
      }
   else
      {
         $up2 = $ver2_str;
      }
   $res = rpm_cmp_frag_($up1,$up2);
   if($res != 0)
      {
         return $res;
      }
         return rpm_cmp_frag_($rpm1,$rpm2);
}

# This sub written by Sam Vanderhyden (sam.vanderhyden@gmail.com)
sub rpm_order_
{
   my $char = shift;
   if($char =~ /^~/)
      {
         return -1;
      }
   if($char =~ /^\d/)
      {
         return 0;
      }
   if(!$char)
      {
         return 0;
      }
   if($char =~ /\w/)
      {
         return ord($char);
      }
   return ord($char) + 256;
}

1;
