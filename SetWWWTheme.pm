# SetWWWTheme.pm - perl source for Apache::SetWWWTheme
# 
# Copyright (C) 1999 Chad Hogan <chogan@uvphys.phys.uvic.ca>
# Copyright (C) 1999 Joint Astronomy Centre
#
# All rights reserved.
# 
# This file is part of Apache::SetWWWTheme
# 
# Apache::SetWWWTheme is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 2, or (at your option) any
# later version.
#
# Apache::SetWWWTheme is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Apache::SetWWWTheme; see the file gpl.txt.  If not, write to the Free
# Software Foundation, 675 Mass Ave, Cambridge, MA 02139, USA.

package Apache::SetWWWTheme;

use strict;
use Carp;

use vars qw($VERSION);
use Apache::Constants ':common';
use Apache::File ();
use HTML::WWWTheme;

$VERSION = '1.00';

##################################################
my $r;                                           # request object variable
my $Theme;                                       # Theme object!
my $blankgif = "";                               # the location of the blank gif.  or png.  Whatever.
my $allowbodymod;                                # 
my ($nextlink, $lastlink, $uplink, $BGCOLOR);    # vars we use to customize the page
my ($alink, $link, $text, $vlink);               # <BODY> stuff
my @infolinks;                                   # array to contain the links in the infobar
my $usenavbar;                                   # flag that tells if we use the top and bottom navbar
my $serverconfig;                                # name of the server config file
my $localconfig;                                 # name of the local config file
my $shortlocal;                                  # short name of local config file
my $allowsidebartoggle;                          # flag set by server to allow turning on/off the sidebar
my $allowBGCOLOR;                                # flag set by the server to allow the local config to 
                                                 #     change the background color.  HTML pages can *never*
                                                 #     override the background color.
my $nosidebar;                                   # flag set to turn off the sidebar.  $allownosidebar
                                                 #     must be set to use this.
my $allowbgpicture;                              # let us put in a background gif or something.  I put this in
                                                 #     so you could kill off animated bgs and other junk
my $bgpicture;                                   # used to set the bg picture for the produced page.
                                                 #
my $allowsidebarmod;                             # sidebar modification variables...
my $sidebartop;                                  #
my $sidebarmenutitle;                            #
my @sidebarmenulinks;                            #
my $sidebarsearchbox;                            #
my $sidebarcolor;                                # 
my $searchtemplate;                              # a search template
##################################################

sub handler
  {
    $r = shift;                                  # get request object
    $Theme = new HTML::WWWTheme();               # grab our theme object.

    my $content_type;
    $content_type = $r->content_type() || return DECLINED;

                                                 # we only want to deal with html files
    return DECLINED unless $content_type eq 'text/html';

    my $filename = $r->filename;                 # get the filename we're looking for
   
    unless (-e $r->finfo)                        # Apache does a stat() and puts the results in finfo,
                                                 # this is faster than testing the filename.
      {
	$r->log_error("File does not exist: $filename");
	return NOT_FOUND;
      }

    unless (-r _)                                # after finfo is used, it goes to perl's _ filehandle
      {
	$r->log_error("File permissions deny access: $filename");
	return FORBIDDEN;
      }

    $r->send_http_header;

    # reset all my vars. 
    # For now, it works, and I think we're ok for namespace issues since all vars have lexical scope.
    # This part is here to let you configure defaults if you want to unleash this module on unsuspecting
    # people that don't/won't put in a server config file or something.  I dunno.  If you can use it,
    # great.  If not, no big deal.

    undef $serverconfig; 
    undef $localconfig;
    $shortlocal =  "LookAndFeelConfig";   # a default, if nothing else is set.
    undef $nextlink;
    undef $lastlink;
    undef $uplink;
    undef $BGCOLOR;
    undef $alink;
    undef $vlink; 
    undef $link;
    undef $text;
    undef $bgpicture;
    undef @infolinks;
    undef $usenavbar;
    undef $allowsidebartoggle;
    undef $allowBGCOLOR;
    undef $allowbgpicture;
    undef $allowsidebarmod;
    undef $nosidebar;
    undef $sidebartop;
    undef $sidebarmenutitle;
    undef @sidebarmenulinks;
    undef $sidebarsearchbox;
    undef $sidebarcolor;
    undef $searchtemplate;

    # grabs the config file for the configuration.  This is all the non-user
    # stuff, and can only be changed by the web maintainers/admin people.
    
    $serverconfig = $r->dir_config->{'CONFIG_FILE'};  
    $r->log_error("Invalid server configuration file") unless ($serverconfig);
    
    # Now we'll set up our defaults from the various spots.  First we'll go
    # for the server defaults, and then we'll grab the local config if 
    # we found one.

    Get_ServerDefaults($serverconfig) if ($serverconfig);  

    # this block will go down the directory tree until it finds a Local config file.
    # if it doesn't find one before the dirs run out, it'll be undef.

    my $index = 1;
    my $path;

    my @bits = split("/", $filename);

    while ( !($localconfig) && ($index <= $#bits) )
      {
	$path = join("/", @bits[0..$#bits-$index]);
	$localconfig = "$path/$shortlocal" if (-f "$path/$shortlocal");
	$index++;
      }

    Get_LocalDefaults($localconfig)   if ($localconfig);    

    # Now the usual Apache module stuff.

    my $fh;                                       # grab a filehandle
    unless ($fh = Apache::File->new($filename))
      {
	$r->log_error("Couldn't open $filename for reading: $!");
	return SERVER_ERROR;
      }
    
    $r->register_cleanup(sub {close $fh});        # register a cleanup for the filehandle

    local $/ = undef;                             # Read in the whole schmear.

    while (<$fh>)
      {
	# this block looks through the HTML to find our comment block that contains directives
	# for controlling the "Look and Feel" of the pages. 
	
	(/\@NAVBAR\s*=\s*(\S+?);/) && ($usenavbar = $1);
	 
	# this is the part where we let the HTML override the server-set defaults
	# A few things we may or may not be able to change (like the BGCOLOR)

	( /\@NEXTLINK\s*?=\s*?(.*?);/s ) && ($nextlink  = $1);
	( /\@LASTLINK\s*?=\s*?(.*?);/s ) && ($lastlink  = $1);	
	( /\@UPLINK\s*?=\s*?(.*?);/s   ) && ($uplink    = $1);
	( /\@INFO\s*?=\s*?(.*?);/s     ) && (@infolinks = split(',',$1));

	($allowsidebartoggle) && ( /\@NOSIDEBAR\s*?=\s*?(.*?);/s) && ($nosidebar = $1);

	# these next two are relics.  They are from the days before we had an "allowbodymod" directive
	# we'll support them for a bit.  They might even be useful on their own.. we'll see.

	($allowBGCOLOR)    && ( /\@BGCOLOR\s*?=\s*?(.*?);/s  ) && ($BGCOLOR = $1);
	($allowbgpicture)  && (/\@BGPICTURE\s*?=\s*?(.*?);/s ) && ($bgpicture = $1);

	if ($allowbodymod)    # here is where we do all of our body modification if allowed
	  {
	    # first we'll look for existing <BODY> settings, then afterwards we'll check
	    # for commented directives.  Unless they're overridden, we want to preserve the
	    # look of a legacy HTML file (IE one that wasn't written with this module in mind).

	    /<BODY[^>]+?BGCOLOR=(.*?)[\s|>]/is     && ($BGCOLOR = $1)   && $BGCOLOR   =~ s/\"//g; 
	    /<BODY[^>]+?BACKGROUND=(.*?)[\s|>]/is  && ($bgpicture = $1) && $bgpicture =~ s/\"//g; 
	    /<BODY[^>]+?ALINK=(.*?)[\s|>]/is       && ($alink = $1)     && $alink     =~ s/\"//g; 
	    /<BODY[^>]+?LINK=(.*?)[\s|>]/is        && ($link = $1)      && $link      =~ s/\"//g; 
	    /<BODY[^>]+?TEXT=(.*?)[\s|>]/is        && ($text = $1)      && $text      =~ s/\"//g; 
	    /<BODY[^>]+?VLINK=(.*?)[\s|>]/is       && ($vlink = $1)     && $vlink     =~ s/\"//g; 

	    # now we're using the directives in the comment tags.

	    /\@BGCOLOR\s*=\s*(.*?);/s        && ($BGCOLOR = $1);
	    /\@BGPICTURE\s*=\s*(.*?);/s      && ($bgpicture = $1);
	    /\@ALINK\s*=\s*(.*?);/s          && ($alink = $1);
	    /\@LINK\s*=\s*(.*?);/s           && ($link = $1);
	    /\@TEXT\s*=\s*(.*?);/s           && ($text = $1);
	    /\@VLINK\s*=\s*(.*?);/s          && ($vlink = $1);
	  }
	    
	# These are all of the sidebar modifications that may be performed, if allowed.

	if ($allowsidebarmod)
	  {
	    
	    ( /\@SIDEBARTOP\s*=\s*(.*?);/s )       && ($sidebartop = $1);
	    ( /\@SIDEBARMENUTITLE\s*=\s*(.*?);/s ) && ($sidebarmenutitle = $1);
	    ( /\@SIDEBARMENULINKS\s*=\s*(.*?);/s ) && (@sidebarmenulinks = split(',',$1));
	    ( /\@SIDEBARSEARCHBOX\s*=\s*(.*?);/s ) && ($sidebarsearchbox = $1);	 
	    ( /\@SIDEBARCOLOR\s*=\s*(.*?);/s )     && ($sidebarcolor = $1);
	    ( /\@SEARCHTEMPLATE\s*=\s*(.*?);/s)    && ($searchtemplate = $1);
	  }
	
	# Now we've got all the configuration we need.  It's time to put things into action!

	# First we'll go through and fix up HTML that's missing tags and stuff.  We're already
	# satisfied that this file is text/html because we checked the content type above.

	# The order of these operations is quite important!  Don't mess it up without
	# pondering it for a minute, and understanding exactly why I've done it this way.

	$_ = "<HEAD>" . $_         unless (/<HEAD[^>]*?>/i);  # first put a <HEAD> on top
        s|<HEAD>|<HEAD></HEAD>|i   unless (/<\/HEAD>/i);      # close with </HEAD> if we need to

	s|</HEAD>|</HEAD><BODY>|i  unless (/<BODY[^>]*?/i);   # drop in a body tag if we need to

	$_ = "<HTML>" . $_         unless (/<HTML[^>]*?>/i);  # now put <HTML></HTML> around the
	$_ .= "</HTML>"            unless (/<\/HTML>/i);      # entire doc if necessary

	s|</HTML>|</BODY></HTML>|i unless (/<\/BODY>/i);      # and close the </BODY> if we need to

	# Jolly good.  We've fixed up the HTML so that we can depend on the existence
	# of <HTML>, <HEAD>, and <BODY>, and also that they're closed properly.
	# It's time to start creating the stuff we're going to insert into the HTML

	my $newbody;
	
	$newbody = MakeBody() unless ($nosidebar);            # make the replacement

	unless($newbody)                                      # This piece is used if we're not creating
	  {                                                   # a sidebar.  It just recreates a normal body
                                                              # as before, except it still uses the table.
	    $newbody  = "<BODY ";
	    ($BGCOLOR) && ($newbody .= "BGCOLOR=\"$BGCOLOR\" ");
	    ($bgpicture) && ($newbody .= "BACKGROUND=\"$bgpicture\" ");
	    ($alink) && ($newbody .= "ALINK=\"$alink\" ");
	    ($link)  && ($newbody .= "LINK=\"$link\" ");
	    ($text)  && ($newbody .= "TEXT=\"$text\" ");
	    ($vlink) && ($newbody .= "VLINK=\"$vlink\" ");
	    $newbody .= "><DIV><TABLE><TR><TD>";
	  }

	# now we'll make up a copyright notice to insert into our page.  

	my $copyrightnotice = 
	  "<!-- BEGINNING OF APACHE GENERATED HTML\n" . 
	  "***************************************\n" .
	  "This is Apache::SetWWWTheme\n" .
	  "Copyright (C) 1999 Chad Hogan <chogan\@uvphys.phys.uvic.ca>\n" .
	  "Copyright (C) 1999 Joint Astronomy Centre\n" .
	  "All Rights Reserved.\n" .
	  "Apache::SetWWWTheme is free software, licensed under the GNU General\n" .
	  "Public License as published by the Free Software Foundation.  Please\n" .
	  "see the source code for details.\n" .
          "-->\n";

	$newbody = $copyrightnotice . $newbody;

	if ($usenavbar)                                      # This puts the top/bottom nav bars into the
	  {                                                  # newly-created HTML
	    $Theme->{nextlink} = $nextlink;
	    $Theme->{lastlink} = $lastlink;
	    $Theme->{uplink}   = $uplink;
	    $newbody .= $Theme->MakeNavBar();
	  }
	
	s/<BODY[^>]*?>/$newbody/i;                # now sub in our generated HTML!
	
       	my $newendbody;                           # This will contain the end of our generated HTML
	
	                                          # if we're using top/bottom navbars, we'll tack on the
                                                  # bottom navbar piece.
	$newendbody .= $Theme->MakeNavBar() if ($usenavbar);
	
	$newendbody .= MakeEndBody();             # Them we make the closing endbody.  
	
	s/<\/BODY[^>]*?>/$newendbody/i;           # And finally, we replace the </BODY> with our new HTML
	
	$r->print($_);                            # we've made our changes, so we'll give it back to apache
	
      }
    return OK;
}

#############################################################################

# this makes the very last part of the page
# it must close off all the table stuff neatly, or else the page won't render.
sub MakeEndBody
{   
    return $Theme->MakeFooter();
}

#############################################################################

# this grabs all the server-side defaults.  This is stuff that only the 
# maintainers can set, and lives in a file that's pointed to by the 
# PerlSetVar in the httpd.conf file.  It's meant to be the controlling file.
# Get_LocalDefaults will get the local defaults that are user-definable.

sub Get_ServerDefaults
{
    my $configfile = shift;
    
    open (CONFIG, $configfile)|| ($r->log_error("Can't read $configfile"), return 0);
    
    local $/ = undef;                               # whole file
    
    while (<CONFIG>)
    {
	# this block generally says:
	# "If we find a directive, set that variable to whatever the tag equals..."

        ( /\@LOCALCONFIGFILE\s*=\s*(.*?);/s )    && ($shortlocal = $1);
	
	( /\@BLANKGIF\s*=\s*(.*?);/s )           && ($blankgif = $1);
	( /\@NAVBAR\s*=\s*(.*?);/s )             && ($usenavbar = $1);
	( /\@NEXTLINK\s*?=\s*?(.*?);/s )         && ($nextlink = $1);
	( /\@LASTLINK\s*?=\s*?(.*?);/s )         && ($lastlink = $1);
	( /\@UPLINK\s*?=\s*?(.*?);/s )           && ($uplink  = $1);
	
	( /\@ALLOWBGCOLOR\s*?=\s*?(.*?);/s )     && ($1) && ($allowBGCOLOR = $1);
	( /\@ALLOWBGPICTURE\s*?=\s*?(.*?);/s )   && ($1) && ($allowbgpicture = $1);
	( /\@ALLOWBODYMOD\s*?=\s*?(.*?);/s )     && ($1) && ($allowbodymod = $1);
	
	( /\@BGCOLOR\s*=\s*(.*?);/s )            && ($BGCOLOR = $1);	 
	( /\@BGPICTURE\s*=\s*(.*?);/s )          && ($bgpicture = $1);
	( /\@ALINK\s*=\s*(.*?);/s )              && ($alink = $1);
	( /\@LINK\s*=\s*(.*?);/s )               && ($link = $1);
	( /\@TEXT\s*=\s*(.*?);/s )               && ($text = $1);
	( /\@VLINK\s*=\s*(.*?);/s )              && ($vlink = $1);
	
	
	( /\@NEXTLINK\s*=\s*(.*?);/s )           && ($nextlink = $1);  
	( /\@ALLOWSIDEBARTOGGLE\s*=\s*(.*?);/s ) && ($allowsidebartoggle = $1);
	( /\@ALLOWNOSIDEBAR\s*=\s*(.*?);/s )     && ($allowsidebartoggle = $1);
	( /\@NOSIDEBAR\s*?=\s*?(.*?);/s)         && ($1) && ($nosidebar = $1);
	( /\@INFO\s*?=\s*?(.*?);/s )             && (@infolinks = split(',',$1));	   
	( /\@ALLOWSIDEBARMOD\s*?=\s*?(.*?);/s)   && ($1) && ($allowsidebarmod = $1);
	( /\@SIDEBARTOP\s*?=\s*?(.*?);/s )       && ($sidebartop = $1);
	( /\@SIDEBARMENUTITLE\s*?=\s*?(.*?);/s ) && ($sidebarmenutitle = $1);
	( /\@SIDEBARMENULINKS\s*?=\s*?(.*?);/s ) && (@sidebarmenulinks = split(',',$1));
	( /\@SIDEBARSEARCHBOX\s*?=\s*?(.*?);/s ) && ($1) && ($sidebarsearchbox = $1);
	( /\@SIDEBARCOLOR\s*?=\s*?(.*?);/s )     && ($sidebarcolor = $1);
	( /\@SEARCHTEMPLATE\s*?=\s*?(.*?);/s )   && ($searchtemplate = $1);

    }
    close CONFIG;
    return 1;
}

#############################################################################  

# this file will get the local defaults.  If you put it in the same directory
# as an HTML file, it will control the defaults for that HTML file.  Of course,
# directives within that HTML file override these, but if they are not present 
# in the HTML comment block before the <BODY> tag, then these defaults will
# be used.  If the local config file does not cover something, this module
# will use the defaults set in the server config.  This configuration is subject
# to the rules set by the maintainers (eg. Can users set teh BGCOLOR?)

sub Get_LocalDefaults
  {
    my $configfile = shift;
    
    open (CONFIG, $configfile)|| ($r->log_error("Can't read $configfile"), return 0);
    
    local $/ = undef;          # Read the whole file in all at once
    
    while (<CONFIG>)
      {
	
	( /\@NAVBAR\s*=\s*(.*?);/s )             && ($usenavbar = $1);
	( /\@NEXTLINK\s*?=\s*?(.*?);/s )         && ($nextlink = $1);
	( /\@LASTLINK\s*?=\s*?(.*?);/s )         && ($lastlink = $1);
	( /\@UPLINK\s*?=\s*?(.*?);/s )           && ($uplink  = $1);
	( /\@INFO\s*?=\s*?(.*?);/s )             && (@infolinks = split(',',$1));
	
	# these next two are left in so old pages won't break.  Actually, it's not
	# necessarily a bad thing to allow this like this anyhow.....  
	
	($allowBGCOLOR)       && ( /\@BGCOLOR\s*=\s*(.*?);/s )     && ($BGCOLOR = $1);
	($allowbgpicture)     && ( /\@BGPICTURE\s*=\s*(.*?);/s )   && ($bgpicture = $1);
	
        ($allowsidebartoggle) && ( /\@NOSIDEBAR\s*?=\s*?(.*?);/s ) && ($1) && ($nosidebar = $1);
	
	if ($allowbodymod)    # here is where we do all of our body modification if allowed
	  {
	    ( /\@BGCOLOR\s*=\s*(.*?);/s )   && ($BGCOLOR = $1);
	    ( /\@BGPICTURE\s*=\s*(.*?);/s ) && ($bgpicture = $1);
	    ( /\@ALINK\s*=\s*(.*?);/s )     && ($alink = $1);
	    ( /\@LINK\s*=\s*(.*?);/s )      && ($link = $1);
	    ( /\@TEXT\s*=\s*(.*?);/s )      && ($text = $1);
	    ( /\@VLINK\s*=\s*(.*?);/s )     && ($vlink = $1);
	  }
	
	if ($allowsidebarmod)
	  # if users are allowed to change the sidebar, then we'll go ahead and read in the changes
	  # that the users specify in their local configuration files.
	  {
	    ( /\@SIDEBARTOP\s*=\s*(.*?);/s )       && ($sidebartop = $1);
	    ( /\@SIDEBARMENUTITLE\s*=\s*(.*?);/s ) && ($sidebarmenutitle = $1);
	    ( /\@SIDEBARMENULINKS\s*=\s*(.*?);/s ) && (@sidebarmenulinks = split(',',$1));
	    ( /\@SIDEBARSEARCHBOX\s*=\s*(.*?);/s ) && ($sidebarsearchbox = $1);	
	    ( /\@SEARCHTEMPLATE\s*=\s*(.*?);/s )   && ($searchtemplate = $1);
	    ( /\@SIDEBARCOLOR\s*=\s*(.*?);/s )     && ($sidebarcolor = $1);
	  }
	
      }
    close CONFIG;
    return 1;
  }

#############################################################################  
# this constructs the side nav bar.  First we set the settings appropriately,
# then we grab a sidebar from it.  We use the JAC::Theme module to make a body
# given all of these settings.  We set them all manually according to the settings
# that we've collected from the server, the file, and the HTML.  

sub MakeBody
{
 
    $Theme->SetBGColor($BGCOLOR)                    if ($BGCOLOR);
    $Theme->SetBGPicture($bgpicture)                if ($bgpicture);
    $Theme->SetALink($alink)                        if ($alink);
    $Theme->SetLink($link)                          if ($link);
    $Theme->SetText($text)                          if ($text);
    $Theme->SetVLink($vlink)                        if ($vlink);

    $Theme->SetSideBarColor($sidebarcolor)          if ($sidebarcolor);
    $Theme->SetBlankGif($blankgif)                  if ($blankgif);
    $Theme->SetInfoLinks(\@infolinks)               if (@infolinks);
    $Theme->SetSideBarTop($sidebartop)              if ($sidebartop);

    $Theme->SetSideBarSearchBox($sidebarsearchbox);
    $Theme->SetSearchTemplate($searchtemplate)      if ($searchtemplate);
    
    $Theme->SetSideBarMenuLinks(\@sidebarmenulinks) if (@sidebarmenulinks);
    $Theme->SetSideBarMenuTitle($sidebarmenutitle)  if ($sidebarmenutitle);
    
    return $Theme->MakeHeader();
    
}

1;

# May a thousand locusts descend upon pod.

=head1 NAME

Apache::SetWWWTheme - Standard theme generation, including sidebars and navigation bars

=head1 SYNOPSIS

Within the httpd.conf or other apache configuration file:
    
 <Location /some/subtree>
 SetHandler perl-script
 PerlHandler Apache::SetWWWTheme
 PerlSetVar CONFIG_FILE /WWWroot/configfile
 </Location>

=head1 REQUIREMENTS

This module requires the Apache server, available from 
http://www.apache.org

This module also requires the B<module HTML::WWWTheme>, by Chad Hogan.
It is available through CPAN.

=head1 DESCRIPTION

The SetTheme module provides a server-based look-and-feel configuration for
an entire webtree. This module allows the server to introduce a common
navigation side-bar. It also provides mechanisms to control the background
color and background picture for a web page.

This is implemented in a layered fashion. The module first reads the server
directives. This sets defaults, and decides what users may have control
over. Server directives may only be set by the webmasters. Following these,
the module reads local directives. These directives are specified in a file,
and will affect all files in that same directory, as well as subdirectories
underneath it. They are set at the user-level, and so they are subject to
the constraints imposed by the server directives. Finally, the module parses
the individual HTML files. Within a file, an HTML authour may override the
settings given in the local directives. Again, these are subject to the
constraints of the server directives.

Please note that you are not required to change anything in your pages. Your
unmodified HTML will work just fine with this module. You are required to
make changes only if you wish to take advantage of the features offered.

=item Server-level configuration

At the server level, the webmaster has full access to all directives. These
tags are specified in a file that is set in the httpd.conf file. If a
webmaster would like his/her subtree to use the module, a <LOCATION> tag is
used to activate the module. A PerlSetVar is used to tell the module the
name of the configuration file. Here is an example:

 <Location />
 SetHandler perl-script
 PerlHandler Apache::SetTheme
 PerlSetVar CONFIG_FILE /WWW/ServerConfig
 </Location>

This example will use the module for the entire document tree. The
CONFIG_FILE variable is used by the module to look for the file that
controls the defaults for the entire site. Please note that CONFIG_FILE
takes the full path to the file name on the file-system -- do not list this
file relative to the document root.

The server-level configuration is primarily to set defaults. It is also to
set restrictions on the configurability of the rest of the site. The
server-level configuration decides whether or not individual authours will
be permitted to, for example, change the background colour and background
image of their web pages.

Once again, the server configuration may make use of all of the following
directives. The server then decides which of these the users may override.

Local configuration

Any authour may create a text file containing directives. The name of this file
is set by the server directive @LOCALCONFIGFILE, with a default of 
LookAndFeelConfig. This file will
affect all HTML files within that directory, as well as any subdirectories.
These directives are subject to the restrictions placed by the server-level
configuration. This file is intended to be used to set common settings for a
tree. For example, one may wish to set the background colour for an entire
tree to white. Then a @BGCOLOR=#FFFFFF; directive in the local config file.
file will set this. Directives that are explicitly set override the server
settings (if allowed). Otherwise, the server's settings persist.

Individual file configuration

This is the final level of configuration. Any authour may embed directives
within a comment tag in an HTML file, as long as this tag appears before the
<BODY> tag. Directives that are explicitly set override the local
configuration and/or server settings (if allowed). Otherwise, the local
settings and the server settings persist.

=item Module directives

Directives consist of a series of tags within a text file, or within an html
comment block before the <BODY> tag. Valid directive tags are always
terminated with a semicolon. For tags that accept lists as values, elements
are separated by commas.

=item @ALINK

HTML and local configuration subject to server configuration
This tag is used to set the HTML BODY setting "alink". This is the
active link color. It is subject to the setting of the @ALLOWBODYMOD
tag. If @ALLOWBODYMOD is set to a non-zero value, @ALINK will set this
attribute in the page. Here is an example:

 @ALINK=#FF00FF;

=item @ALLOWBODYMOD

Server configuration only
This tag is used to allow or disallow users from changing BODY
elements. These include "alink", "vlink", "link", "text", "bgcolor",
and "background" items using the directives @ALINK, @VLINK, @LINK,
@TEXT, @BGCOLOR and @BGPICTURE respectively. If it is set to a non-zero
value, the user's directives will be read and used. Otherwise, user
settings will be ignored, and only the server configuration values will
be used in creating the <BODY> tag for the page. Here is an example:

 @ALLOWBODYMOD=1;

=item @ALLOWBGCOLOR L<Deprecated>

Server configuration only
This tag is used to allow or disallow users from changing the
background colours of their pages. By default it is set to 0, meaning
that users are not allowed to change their background colours. If it is
not set to a non-zero value, only the server's @BGCOLOR directives will
be used. This directive is deprecated. Administrators should use
@ALLOWBODYMOD instead. Here is an example:

 @ALLOWBGCOLOR=0;

=item @ALLOWBGPICTURE L<Deprecated>

Server configuration only
This tag is used to allow or disallow users from changing the
background picture of their pages. By default it is set to 0, meaning
that users are not allowed to change their background colours. If it is
not set to a non-zero value, only the server's @BGPICTURE directives
will be used. This directive is deprecated. Administrators should use
@ALLOWBODYMOD instead Here is an example:

 @ALLOWBGPICTURE=0;

=item @ALLOWNOSIDEBAR L<Deprecated>

Server configuration only. I<Use @ALLOWSIDEBARTOGGLE instead>.
This tag is used to allow or disallow users from turning on/off the left
sidebar.  By default, it is set to 0, meaning that users are not allowed to
toggle the sidebar.  If is not set to a true value (1 is recommended), only the
server's @NOSIDEBAR directives will be used.  Here is an example:

 @ALLOWNOSIDEBAR=0;

=item @ALLOWSIDEBARTOGGLE

Server configuration only
This tag is used to allow or disallow users from turning on/off the left
sidebar. By default it is set to 0, meaning that users are not allowed
to toggle the sidebar. If it is not set to a true value (1 is recommended), only the
server's @NOSIDEBAR directives will be used. Here is an example:

 @ALLOWSIDEBARTOGGLE=0;

 
=item @ALLOWSIDEBARMOD

Server configuration only
This tag is set to allow users to modify the characteristics of the
sidebar. If this flag is set to anything non-zero, users may change the
title at the top of the sidebar with the @SIDEBARTOP directive, the
menu title above the menulinks with @SIDEBARMENUTITLE, the menu links
with the @SIDEBARMENULINKS. They may also then switch the sidebar
search box on or off with @SIDEBARSEARCHBOX. Here is an example:

 @ALLOWSIDEBARMOD=0;

=item @BGCOLOR

HTML and local configuration subject to server configuration
This tag may be used to set the background colour of a page (or a group
of pages, in the case of local and server configuration). @BGCOLOR is
subject to the server directive @ALLOWBGCOLOR. If @ALLOWBGCOLOR is not
set to a non-zero value by server directives, the @BGCOLOR directive
will have no effect whatsoever when used in local and HTML
configuration. @BGCOLOR will always work when used in a server
configuration. Here is an example:
     
 @BGCOLOR=#FFFFCC;

=item @BGPICTURE

HTML and local configuration subject to server configuration
This tag may be used to set the background image of a page (or a group
of pages, in the case of a local and server configuration. @BGPICTURE
is subject to the server directive @ALLOWBGPICTURE. If @ALLOWBGPICTURE
is not set to a non-zero value by server directives, the @BGPICTURE
directive will have no effect whatsoever when used in local and HTML
configuration. @BGPICTURE will always work when used in a server
configuration. Here is an example:

 @BGPICTURE=/images/paperbackground.gif;

=item @BLANKGIF

Server configuration only
This tag is used to specify the location of the blank.gif image file.
This image is a 1x1 transparent gif that is used to space the tables
properly. This should be set to the path of the image file with respect
to the server's document root. So, if the apache document root is /WWW
and the file is /WWW/images/blank.gif then the proper use of this tag
would be:

 @BLANKGIF=/images/blank.gif;

=item @INFO

Valid in HTML, local configuration, and server configuration
This tag is used to customize the "More links" section in the left
sidebar. To use this tag, supply a comma-separated list of valid HTML
links terminated with a semi-colon. The links supplied will appear in
the "More Links" section. Here is an example:

 @INFO=<A HREF="http://www.sun.com">Sun</a>,
 <A HREF="http://www.slashdot.org">Slashdot</a>;

=item @LINK

Valid in HTML, local configuration, and server configuration
This tag is used to set the HTML BODY setting "link". This is the
normal link color. It is subject to the setting of the @ALLOWBODYMOD
tag. If @ALLOWBODYMOD is set to a non-zero value, @LINK will set this
attribute in the page. Here is an example:

 @LINK=#FFFFFF;

=item @LOCALCONFIGFILE

Valid only in server configuration.  This directive tells the module what
file to look for when it looks for local configuration files.  The default is
LookAndFeelConfig.  It may be set to any valid filename.

 @LOCALCONFIGFILE=LOOKANDFEEL;

=item @NAVBAR

Valid in HTML, local configuration, and server configuration
This tag gives the switch setting for the top and bottom navigation
bars. The top and bottom navigation bars are also known as the
"previous/up/next" bars. If this is set to 0, the top and bottom bars
are not shown. If this is set to a non-zero value (1 is recommended)
then the bars will be shown. If this switch is non-zero, it is
recommended that the @NEXTLINK, @UPLINK, and @LASTLINK directives be
set. Here is an example:

 @NAVBAR=0;

=item @NEXTLINK, @LASTLINK, @UPLINK

Valid in HTML, local configuration, and server configuration
These tags control the behaviour of the top navigation bar. These tags
should be set in conjunction with the @NAVBAR directive. They should
contain valid text and linking information. Here is an example:

 @NEXTLINK=<A HREF="/pages/page3.html">Page 3</a>;
 @UPLINK=<A HREF="/pages/toc.html">Table of contents</a>;
 @LASTLINK=<A HREF="/pages/page1.html">Page 1</a>;

=item @NOSIDEBAR

HTML and local configuration subject to server configuration
This tag may be used to turn off the left sidebar by setting it to a
non-zero value. This tag is subject to the server directive
@ALLOWNOSIDEBAR. If the server configuration has not set the
@ALLOWNOSIDEBAR to a non-zero value, the @NOSIDEBAR directive will have
no effect whatsoever. Here is an example:

 @NOSIDEBAR=1;

=item @SIDEBARCOLOR

HTML and local configuration subject to server configuration
This tag is used to set the color of the sidebar. Local and HTML
configuration is subject to the server directive @ALLOWSIDEBARMOD. Here
is an example:

 @SIDEBARCOLOR=#CCCCCC;

=item @SEARCHTEMPLATE

HTML and local configuration subject to server configuration
This tag is used to set the searchbox template.  It should be a fully-contained
HTML chunk that interfaces to the apropriate cgi binary (or whatever you
want).  

 @SEARCHTEMPLATE=
 <B>Search JAC</B><BR><HR>
 <DIV align="center">
 <form method="POST" action="/cgi-bin/isearch">
 <input name="SEARCH_TYPE" type=hidden  value="ADVANCED">
 <input name="HTTP_PATH" type=hidden value="/WWW"> 
 <input name="DATABASE" type=hidden value="webindex">
 <input name="FIELD_1" type=hidden value="FULLTEXT">
 <input name="WEIGHT_1" type=hidden value= "1">
 <input name="ELEMENT_SET" type=hidden value="TITLE">
 <input name="MAXHITS" type=hidden value="50">
 <input name="ISEARCH_TERM" size="14" border="0">
 </form>
 </DIV>
 <H6><a href="http://www.yoursite.edu/search.html">More searching....</a></h6>;

Don't forget to terminate the template with a semicolon!

=item @SIDEBARMENULINKS

HTML and local configuration subject to server configuration
This tag is used to set the main menulinks. It is effective in local
and HTML configuration if and only if the server configuration has set
@ALLOWSIDEBARMOD. It takes a comma-separated list of links, terminated
by a semicolon. Here is an example:

 @SIDEBARMENULINKS=<A HREF="/WWW/stuff">Some Directory</A>,
 <A HREF="/WWW/morestuff">Another Directory</A>;

=item @SIDEBARMENUTITLE

HTML and local configuration subject to server configuration
This tag is used to set the title above the menulinks. It is effective
in local and HTML configuration if and only if the server configuration
has set @ALLOWSIDEBARMOD to a non-zero value. Here is an example of its
use:

 @SIDEBARMENUTITLE=My Divisions;

=item @SIDEBARSEARCHBOX

HTML and local configuration subject to server configuration
This tag is a switch that determines whether or not the sidebar will
contain the search box. If it is set to a non-zero value, the search
box will appear on the sidebar. It is effective in local and HTML
configuration if and only if the server configuration has set
@ALLOWSIDEBARMOD to a non-zero value. Here is an example of its use:

 @SIDEBARSEARCHBOX=0;

=item @SIDEBARTOP

HTML and local configuration subject to server configuration
This tag is used to set the title at the top of the sidebar. It is
effective in local and HTML configuration if and only if the server
configuration has set @ALLOWSIDEBARMOD to a non-zero value. Here is an
example of its use:

 @SIDEBARTOP=<A HREF="/>Joint Astronomy Centre</a>;

=item @TEXT

HTML and local configuration subject to server configuration
This tag is used to set the HTML BODY setting "text". This is the
normal text color. It is subject to the setting of the @ALLOWBODYMOD
tag. If @ALLOWBODYMOD is set to a non-zero value, @TEXT will set this
attribute in the page. Here is an example:

 @TEXT=#000000;

=item @VLINK

This tag is used to set the HTML BODY setting "vlink". This is the
visited-link color. It is subject to the setting of the @ALLOWBODYMOD
tag. If @ALLOWBODYMOD is set to a non-zero value, @VLINK will set this
attribute in the page. Here is an example:

 @VLINK=#FF00FF;

=head1 SEE ALSO

L<HTML::WWWTheme>

=head1 AUTHOR

Copyright (C) 1999 Chad Hogan (chogan@uvphys.phys.uvic.ca).  
Copyright (C) 1999 Joint Astronomy Centre

All rights reserved.  Apache::SetWWWTheme is free software;
you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 or
(at your option) any later version.

Apache::SetWWWTheme is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
details.  

You should have received a copy of the GNU General Public License along
with Apache::SetWWWTheme; see the file gpl.txt.  If not, write to the Free
Software Foundation, 675 Mass Ave, Cambridge, MA 02139, USA.

=cut
