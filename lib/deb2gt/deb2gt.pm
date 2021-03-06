################################################################################
#deb2gt.pm is a perl module written by Joshua McClintock
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

package deb2gt;

use strict;
use gt;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

require	Exporter;

@ISA = qw(Exporter);
@EXPORT = qw(deb_cmp_frag_ deb_cmp_version_ deb_order_ deb_get_arch_dir_ deb_get_packinfo_ deb_extract_info_ deb_updt_provides_db_);
$VERSION = '1.11';

#Global Configuration
my %gtcfg_val = r_gt_cfg_();

#Global Utilities
my(%cli_Util) = set_util_loc_();

### BEGIN SUBROUTINES ###

sub deb_get_arch_dir_
{
   my $dir = "/var/cache/apt/archives";
   return($dir);
}

# This sub written by Sam Vanderhyden (sam.vanderhyden@gmail.com)
sub deb_cmp_frag_
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
               my $vc = deb_order_($fragA[$a]);
               my $rc = deb_order_($fragB[$b]);
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
sub deb_cmp_version_
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
   my $res = deb_cmp_frag_($epoch1,$epoch2);
   if($res != 0)
      {
         return $res;
      }
   my $up1 = "";
   my $up2 = "";
   my $deb1 = "";
   my $deb2 = "";
   if($ver1_str =~ /(.*)-(.*)/)
      {
         $up1 = $1;
         $deb1 = $2;
      }
   else
      {
         $up1 = $ver1_str;
      }
   if($ver2_str =~ /(.*)-(.*)/)
      {
         $up2 = $1;
         $deb2 = $2;
      }
   else
      {
         $up2 = $ver2_str;
      }
   $res = deb_cmp_frag_($up1,$up2);
   if($res != 0)
      {
         return $res;
      }
         return deb_cmp_frag_($deb1,$deb2);
}

# This sub written by Sam Vanderhyden (sam.vanderhyden@gmail.com)
sub deb_order_
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

sub deb_get_packinfo_
{
   my(%control);
   my $deb_arch_dir = deb_get_arch_dir_();
   my($deb_package,$tree_package,$mode) = @_;
   if($mode eq "debpkg")
      {
         open(CONTROL, "$cli_Util{dpkg} -I $deb_arch_dir/$deb_package|") || die "Couldn't $cli_Util{dpkg}. Reason: $!\n";
      }
   elsif($mode eq "debcontrol")
      {
         open(CONTROL, "$tree_package") || die "Couldn't open control file $tree_package to get it's information.  Reason: $!\n";
      }
   else
      {
         die("Incorrect mode ($mode) passed, must be either debpkg or debcontrol.\n");
      }

   while(<CONTROL>)
      {
         next unless length;
	 if(/(|\s)[A-Z].*:\s/)
	    {
               #Version:,Package:,Section:,Depends:,Pre-Depends:,Provides:,Replaces:,Conflicts:
	       my $line = $_;
	       chomp $line;
	       $line =~ s/^\s//;
	       my($label,$value) = split(/:\s/, $line, 2);
	       if($label eq "Version" || $label eq "Package" || $label eq "Section" || $label eq "Depends" || $label eq "Pre-Depends" || $label eq "Provides" || $label eq "Replaces" || $label eq "Conflicts")
	          {
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

sub deb_extract_info_
{
   my(%control) = @_;

   my($version) = $control{"Version"};
   my($package) = $control{"Package"};
   my($section) = $control{"Section"};
   my(@predepends) = split(/,/, $control{"Pre-Depends"});
   my(@depends) = split(/,/, $control{"Depends"});
   push(@depends,@predepends);
   my(@provides) = split(/,/, $control{"Provides"});

   return($version,$package,$section,@depends);
}

sub deb_updt_provides_db_
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
         $item =~ s/\s//;
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
	 #Create comma delimted list of providers
	 my $prov_list = join(",", @prov_ray);
         rw_gt_db_("$gtcfg_val{infodir}/$base" . "_provides.db","provides",$item,$prov_list);
      }
}

         

1;

__END__
