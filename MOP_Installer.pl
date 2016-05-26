#!/bin/perl

##########################################################
#
# NAME:  MOP_Installer
# Author: Rajesh Acharya
# Date:   Jul 17, 2006
#
# Purpose: This script is used for various install/uninstall tasks 
#          involved with upgrading the patches for a Cisco BTS 10200 
#          soft switch.
#
#####################################################################

use strict;
use Getopt::Std;
use File::Basename;

# --------------------- GLOBAL VAR DECLARATION --------------------------------
my (%CONFIG);
my (%PWDTABLE);
my ($OPERMODE);
my ($PLTFORM)="";
my ($SCRVERSION)="1.0";			# script default version
my ($LINECOUNT)=0;			# keeps track of the last line that caused an error
my ($CURRLINE)=0;			# keeps tack of current line (for caching purpose)
my ($CACHEFILE);			# keeps track of the cache file to use
my (%CLIINFOTBLE);
my ($TESTRUN)=0;

my ($optBTSflg)=0;
my (@CHANGETABLE)=();
my (@POSTACTION_TASKS)=();
my ($DEBUGMODE)=0;
my ($CONTINUETASKS)=0;
my ($OLD_NEW_FLG);
my ($CNTRLVAL);
my ($DIRPTH);
my ($MKDIRSET)=0;
my ($CMNDFLE);
my ($SECTOR);
my ($SCRNAME);
my ($THISSRVR)=`/bin/uname -n`;
chomp($THISSRVR);

my ($NODESTAT_PLTFRM);
my ($BUILD_UNINSTTBLE_ONLY)=0;
my (@datetable)=split(/\s+/, `/bin/date`);
my ($prevptch,
    $prevplatfrm,
    $prevcmnd);

# added 10/11/2006 - to disable the interrupts
my (%ORIG_SIGNALS);
$ORIG_SIGNALS{'INT'}=$SIG{'INT'};		# save interrupt signal (ie: ^C - to abort)
$ORIG_SIGNALS{'KILL'}=$SIG{'KILL'};		# save KILL signal
$ORIG_SIGNALS{'TERM'}=$SIG{'TERM'};		# save TERM signal

# ------------------------------ Check command line arg -----------------------
my (%OPTS);				# command line options
getopt('td',\%OPTS);
if (exists($OPTS{'t'}))
  {
     $TESTRUN=1;
  } # set test-run mode
if (exists($OPTS{'d'}))
  {
     $DEBUGMODE=1;
  }


# ----------------------- COMMANDS to swap server------------------------------
my (%CONTROL);
my ($TO_STATE);
my (@AGENTTYP)=("call-agent|CALL_AGT","feature-server|FEAT_SAIN",
		"feature-server|FEAT_SPTC","bdms|BDMS_AGT",
		"element-manager|EMS_AGT");
$CONTROL{'STD_ACT'}="control AGENT_TYPE id=AGENT_IDNAME; target-state=forced-standby-active;";
$CONTROL{'ACT_STD'}="control AGENT_TYPE id=AGENT_IDNAME; target-state=forced-active-standby;";
$CONTROL{'NORMAL'}="control AGENT_TYPE id=AGENT_IDNAME; target-state=normal;";


# ---------------------- START OF MAIN BLOCK -----------------------------------
# get basename of the current script running
$SCRNAME=basename($0);

# check current users privs
&Check_CurrUsrPrivs();

# read the main config file and set log file names
my ($CFGFILE)="/opt/MOP_install/runtime_cfg/MOP_config.inf";
&readconfig();
&read_PWDFILE();

$CONFIG{'PATCHORDER'} =~ s/\.gz//g;
$CONFIG{'REVERTPATCH'}=~ s/\.gz//g;
my ($INSTALL_LOG)="$CONFIG{'MOP_BASEDIR'}/$CONFIG{'LOGSDIR'}/MOP_installer_SRVRNAME_";
my ($UNINSTALL_LOG)="$CONFIG{'MOP_BASEDIR'}/$CONFIG{'LOGSDIR'}/MOP_uninstaller_SRVRNAME_";
my ($UPDATE_REVERT)="$CONFIG{'MOP_BASEDIR'}/$CONFIG{'LOGSDIR'}/MOP_OPERMODE_CLIDB_";
my ($STATECHNGLOG)="$CONFIG{'MOP_BASEDIR'}/$CONFIG{'LOGSDIR'}/OPERMODE_SRVRNAME_";
my ($flext)=join("_",$datetable[1],$datetable[2],$datetable[5]) . ".log";
my ($POSTACTFILE)="$CONFIG{'MOP_BASEDIR'}/cache/.POSTACTIONSTABLE";
$INSTALL_LOG .= $flext;
$UNINSTALL_LOG .= $flext;
$UPDATE_REVERT .= $flext;
$STATECHNGLOG .= $flext;

# print title for the script
$SCRVERSION=$CONFIG{'SCRVERSION'} if (exists($CONFIG{'SCRVERSION'}));
print "\n\n\t$SCRNAME\t\tV $CONFIG{'SCRVERSION'}\n\n" if ($SCRNAME !~ /MOP_Installer/);

# Display message for test-run
if ($TESTRUN == 1)
  {
     print "\n";
     print "     --------------------------------------------------------------------\n";
     print "     |                                                                  |\n";
     print "     |    NOTE: Running in test mode.                                   |\n";
     print "     |          Files are not actually copied to the destination, but   |\n";
     print "     |          to /dev/null.  Commands that stop and restart the       |\n";
     print "     |          platform are not actually run as shown!!                |\n";
     print "     |                                                                  |\n";
     print "     --------------------------------------------------------------------\n";
     print "\n";
  }

# check what script we are running
if ($SCRNAME =~ /^MOP_Installer/)
  {
     $OPERMODE="UPGRADE";
     $BUILD_UNINSTTBLE_ONLY=1;
  }
elsif ($SCRNAME =~ /^Uninstall_BTS_Patches/)
  {
     $CACHEFILE="$CONFIG{'MOP_BASEDIR'}/cache/$CONFIG{'REMVCACHE'}";
     $SECTOR="U";

     &read_CACHEDLINE($CACHEFILE);
     if ($CONTINUETASKS == 0)
       {
         &run_nodestat_local("Backout","STANDBY") if ($TESTRUN == 0);
       }
     $OPERMODE="BACKOUT";
  }
elsif ($SCRNAME =~ /^Install_BTS_Patches/)
  {
     $CACHEFILE="$CONFIG{'MOP_BASEDIR'}/cache/$CONFIG{'INSTCACHE'}";
     $SECTOR="I";

     &read_CACHEDLINE($CACHEFILE);
     if ($CONTINUETASKS == 0)
       {
         &run_nodestat_local("Upgrade","STANDBY") if ($TESTRUN == 0);
       }
     $OPERMODE="UPGRADE";
  }
elsif ($SCRNAME =~ /^Update_SWITCH_DB_Table/)
  {
     &run_nodestat_local("Update","ACTIVE");
     $OLD_NEW_FLG="NEW_";
     $OPERMODE="UPDATEDB";
  }
elsif ($SCRNAME =~ /^Revert_SWITCH_DB_Table/)
  {
     &run_nodestat_local("Revert","ACTIVE");
     $OLD_NEW_FLG="OLD_";
     $OPERMODE="REVERTDB";
  }
elsif ($SCRNAME =~ /^Switch_/)
  {
     if ($SCRNAME =~ /_Stdby_Active/)
       {
          &run_nodestat_local("STDBY-ACTIVE","ACTIVE");
          $CNTRLVAL="STD_ACT";
	  $TO_STATE="STANDBY";
          $OPERMODE="SW_STD_ACT";
       }
     elsif ($SCRNAME =~ /_Active_Stdby/)
       {
          &run_nodestat_local("ACTIVE-STDBY","ACTIVE");
          $CNTRLVAL="ACT_STD";
	  $TO_STATE="ACTIVE";
          $OPERMODE="SW_ACT_STD";
       }
     elsif ($SCRNAME =~ /_Normalize/)
       {
          &run_nodestat_local("NORMALIZE","ACTIVE");
          $CNTRLVAL="NORMAL";
	  $TO_STATE="NORMAL";
          $OPERMODE="SW_NORMAL";
       }
  } # script name starts with Switch

# set the install/uninstall platform
if ($CONFIG{'NODEINFO'} eq "EM")
  { $PLTFORM="STDBY_EM"; }
else
  { $PLTFORM="STDBY_CA"; }

$INSTALL_LOG=~ s/SRVRNAME/$CONFIG{'SRVRNAME'}/g;
$UNINSTALL_LOG=~ s/SRVRNAME/$CONFIG{'SRVRNAME'}/g;
$UPDATE_REVERT =~ s/OPERMODE/$OPERMODE/g;
$STATECHNGLOG =~ s/OPERMODE/$OPERMODE/g;
$STATECHNGLOG =~ s/SRVRNAME/$CONFIG{'SRVRNAME'}/g;
$CONFIG{'UNINSTALL_CFILE'}=~s/SRVRNAME/$CONFIG{'SRVRNAME'}/g;

# decision for branching
if ($OPERMODE =~ /UPGRADE/)
  {
    if (-f "/opt/MOP_install/$CONFIG{'RUNTIME_DATA'}/INSTALL.Done")
      {
	print "\nWARNING: Patches (" . $CONFIG{'PTCHSTRT'} . "-" . $CONFIG{'PTCHEND'};
	print ") have already been installed.\n";
        print "         Please <BACKOUT> if you wish to re-install the patches.\n\n";
	exit(1);
      }

    # open logging file for info
    if (! -f "$INSTALL_LOG")
      {
    	open(INSTLOG,">$INSTALL_LOG") ||
          die("\nERROR: Could not create capture log file: $INSTALL_LOG!!\n\n");
      }
    else
      {
    	open(INSTLOG,">>$INSTALL_LOG") ||
          die("\nERROR: Could not append to capture log file: $INSTALL_LOG!!\n\n");
      }
    select(INSTLOG);		$|=1;
    select(STDOUT);		$|=1;

    &upgrade_BTS_patches();
    `touch /opt/MOP_install/$CONFIG{'RUNTIME_DATA'}/INSTALL.Done` if ($BUILD_UNINSTTBLE_ONLY == 0);

     &Enable_interrupts();		# enable interrupts
  }
elsif ($OPERMODE =~ /BACKOUT/)
  {
    if (! -f "/opt/MOP_install/$CONFIG{'RUNTIME_DATA'}//INSTALL.Done")
      {
	print "\nWARNING: Patches (" . $CONFIG{'PTCHSTRT'} . "-" . $CONFIG{'PTCHEND'};
	print ") have not been installed.\n";
        print "         Patches need to have been <INSTALLED> before running backout.\n\n";
	exit(1);
      }

    # open logging file for info
    if (! -f "$INSTALL_LOG")
      {
    	open(INSTLOG,">$UNINSTALL_LOG") ||
          die("\nERROR: Could not create capture log file: $UNINSTALL_LOG!!\n\n");
      }
    else
      {
    	open(INSTLOG,">>$UNINSTALL_LOG") ||
          die("\nERROR: Could not append to capture log file: $UNINSTALL_LOG!!\n\n");
      }
    select(INSTLOG);		$|=1;
    select(STDOUT);		$|=1;

    &revert_BTS_patches();
    `\\rm /opt/MOP_install/$CONFIG{'RUNTIME_DATA'}/INSTALL.Done`;

     &Enable_interrupts();		# enable interrupts
  }
elsif (($OPERMODE =~ /SW_STD_ACT/) || ($OPERMODE =~ /SW_ACT_STD/) || ($OPERMODE =~ /SW_NORMAL/))
  {
     &Disable_interrupts();				# disable interrupts
     # open logging file for state change
     if (! -f "$UPDATE_REVERT")
       {
     	open(INSTLOG,">$STATECHNGLOG") ||
          die("\nERROR: Could not create capture log file: $STATECHNGLOG!!\n\n");
       }
     else
       {
     	open(INSTLOG,">$STATECHNGLOG") ||
          die("\nERROR: Could not append to capture log file: $STATECHNGLOG!!\n\n");
       }
     select(INSTLOG);		$|=1;
     select(STDOUT);		$|=1;

     &Print_Msg("\t----------------------------- $OPERMODE -----------------------------------\n");
     &Print_Msg("\t|                                                                        |\n");
     &Print_Msg("\t|           I will run CLI commands to make this switch $TO_STATE          |\n");
     &Print_Msg("\t|                                                                        |\n");
     &Print_Msg("\t--------------------------------------------------------------------------\n");
     &Print_Msg("\t                 START TIME: " . localtime() . "\n\n");

     &apply_StateChange();
     &Print_Msg("\n\t                 FINISH TIME: " . localtime() . "\n\n");

     &Enable_interrupts();		# enable interrupts
  }
elsif (($OPERMODE =~ /REVERTDB/) || ($OPERMODE =~ /UPDATEDB/))
  {
     if ($CONFIG{'CLIPARAMCHANGE'} eq "N")
       {
	  print "\t-------------- WARNING - ABORTING $OPERMODE OPERATION ---------------------\n";
	  print "\t|                                                                        |\n";
          print "\t|   The parameter (CLIPARAMCHANGE) in the config file is set to 'N'      |\n";
          print "\t|   This param needs to be 'Y' before continuing.  Please rerun the      |\n";
          print "\t|   /opt/MOP_INSTALL/bin/Make_SiteConfig and select 'Y' for DB update.   |\n";
	  print "\t|                                                                        |\n";
	  print "\t--------------------------------------------------------------------------\n\n";
          exit(1);
       }

     &Disable_interrupts();				# disable interrupts

     # read the attributes for change 
     &read_CLIAttrVals();

     # open logging file for info
     if (! -f "$UPDATE_REVERT")
       {
     	open(INSTLOG,">$UPDATE_REVERT") ||
          die("\nERROR: Could not create capture log file: $UPDATE_REVERT!!\n\n");
       }
     else
       {
     	open(INSTLOG,">$UPDATE_REVERT") ||
          die("\nERROR: Could not append to capture log file: $UPDATE_REVERT!!\n\n");
       }
     select(INSTLOG);		$|=1;
     select(STDOUT);		$|=1;

     # get values for changing
     &get_change_values($OLD_NEW_FLG);
     
     # check if table is populated
     if (scalar(@CHANGETABLE) == 0)
       {
	  &Print_Msg("\t-------------- WARNING - ABORTING $OPERMODE OPERATION ---------------------\n");
	  &Print_Msg("\t|                                                                        |\n");
          &Print_Msg("\t|   The parameter (CLIPARAMCHANGE) in the config file is set to 'Y',     |\n");
          &Print_Msg("\t|   but I was not able to acquire list of attributes for update/revert.  |\n");
	  &Print_Msg("\t|                                                                        |\n");
	  &Print_Msg("\t--------------------------------------------------------------------------\n\n");
          &Enable_interrupts();		# enable interrupts
          exit(1);
       }
     else
       {
	  my ($tmp)=scalar(@CHANGETABLE)-1;
	  $tmp = " " . $tmp if (length($tmp) < 10);
	  &Print_Msg("\t----------------------------- $OPERMODE -----------------------------------\n");
	  &Print_Msg("\t|                                                                        |\n");
          &Print_Msg("\t|           I will update/revert <$tmp> attributes in the DB.              |\n");
	  &Print_Msg("\t|                                                                        |\n");
	  &Print_Msg("\t--------------------------------------------------------------------------\n");
	  &Print_Msg("\t                 START TIME: " . localtime() . "\n\n");
       }

     # call function for changing
     &apply_CLIDB_change();
     &Print_Msg("\n\t                 FINISH TIME: " . localtime() . "\n\n");

     &Enable_interrupts();		# enable interrupts
  } # end case for update/revert of DB
# ------------------ END OF MAIN BLOCK -----------------------------------


# ------ SUBS START HERE -------------------------------------
# check current user's priveledges
sub Check_CurrUsrPrivs
{
    my ($usrid,$junk);
    $usrid=`/bin/id`;
    chomp($usrid);
    $usrid=~s/^\S+\(//g;	# remove unnecessary char upto first '('
    ($usrid,$junk)=split(/\)/,$usrid); # discard all after first ')'

    if ($usrid ne "root")
      {
        print "ERROR: You are not priviledged to run this script\n";
        print "       Only root user is permitted to run it\n\n";
        exit 1
      }
} # end sub


sub Disable_interrupts
{
  foreach my $int_ID (keys %ORIG_SIGNALS)
    {
	$SIG{$int_ID}='IGNORE';
    }
} # end sub


sub Enable_interrupts
{
  foreach my $int_ID (keys %ORIG_SIGNALS)
    {
	my ($value)=$ORIG_SIGNALS{$int_ID};
	if (length($value)==0)
	  { $SIG{$int_ID}=undef; }
	else
	  { $SIG{$int_ID}=$value; }
    } # end loop
} # end sub


sub readCLIINFO_TABLE
{
  if (-f "$CONFIG{'MOP_BASEDIR'}/config/$CONFIG{'CLIINFOFILE'}")
    { # if the file exists read it in
      open(CLIINFFILE,"$CONFIG{'MOP_BASEDIR'}/config/$CONFIG{'CLIINFOFILE'}");
      while (<CLIINFFILE>)
        {
          chomp;
          my ($attrib,$value)=split(/\|/);
          $CLIINFOTBLE{$attrib}=$value;
        } # end while loop
      close(CLIINFFILE);
    } # end outer if
} # end sub


sub apply_StateChange
{
    my ($commandstr);
    my ($commandstr2)="show db-size;";		# TEST case
    my ($expectprg)="/usr/local/bin/expect";
    my ($tmpexpscr)="/tmp/expCLIDB.exp";
    select(STDOUT);	$|=1;				# set autoflush for STDOUT

    foreach my $agententry (@AGENTTYP)
      {
	my ($AGENT_TYPE,$AGENT_IDNAME)=split(/\|/, $agententry);
        $commandstr=$CONTROL{$CNTRLVAL};
        $commandstr=~s/AGENT_TYPE/$AGENT_TYPE/g;
        $commandstr=~s/AGENT_IDNAME/$CONFIG{$AGENT_IDNAME}/g;
    	&Print_Msg("\nExecuting CLI command:\n\t$commandstr\n");

    	my ($expectminiscr)="set timeout -1\nspawn su - $CONFIG{'CLIUSER'}\nexpect \"CLI\"\n";
	if ($TESTRUN == 1)
    	  { $expectminiscr.="send \"$commandstr2\\r\"\n"; }
	else
    	  { $expectminiscr.="send \"$commandstr\\r\"\n"; }

    	$expectminiscr.="expect \"CLI\"\nsend \"quit\\r\"\n";
    	open(TMP,">$tmpexpscr") || die("ERROR: Could not create expect script <$tmpexpscr>!!\n\n");
    	print TMP $expectminiscr;
    	close(TMP);

    	my (@retresult)=split(/\n/, `$expectprg $tmpexpscr`);
    	`\\/bin/rm $tmpexpscr`;		# remove the temporary sxript

    	# check if command returned a successful reply
    	if (&checkCLI_retresult(@retresult) == -1)
      	  {
            &Print_Msg("\tERROR: The CLI command above did not execute successfully!!\n");
            &Print_Msg("\t       Please resolve the issue and try again.\n\n"); 
            &Enable_interrupts();		# enable interrupts
            exit 1;
      	  }
    	else
      	  {
	   &Print_Msg("\tStatus: SUCCESS\n");
      	  }

	# added - 9/21/2006 - wait time
	&Print_Msg("\nWaiting for previous command to finish ... \n\n");
	sleep 5;
      } # end loop

} # end function


sub apply_CLIDB_change
{
    my ($commandstr)="change db-size table-name=CLIDB_ATTRIBUTE_NAME; MAX-RECORD=CLIDB_ATTRIBUTE_SIZE;";
    my ($commandstr2)="show db-size table-name=CLIDB_ATTRIBUTE_NAME;";		# TEST case
    my ($expectprg)="/usr/local/bin/expect";
    my ($tmpexpscr)="/tmp/expCLIDB.exp";
    my ($cmdstrcpy);
    my ($cmdstrcpy2);
    my ($rmCLITBLE)=1;					# set to 1
    select(STDOUT);	$|=1;				# set autoflush for STDOUT

    foreach my $chngtble_entry (@CHANGETABLE)
      {
	  my ($CLIATTRNAME)=$chngtble_entry;
          my ($CLIATTRSIZE)=$CONFIG{$chngtble_entry};	# lookup value in hash
          $CLIATTRNAME=~s/$OLD_NEW_FLG//g;		# remove prefix (OLD_/NEW_)

    	  $cmdstrcpy=$commandstr;
    	  $cmdstrcpy2=$commandstr2;
    	  $cmdstrcpy=~s/CLIDB_ATTRIBUTE_NAME/$CLIATTRNAME/g;
    	  $cmdstrcpy=~s/CLIDB_ATTRIBUTE_SIZE/$CLIATTRSIZE/g;
    	  $cmdstrcpy2=~s/CLIDB_ATTRIBUTE_NAME/$CLIATTRNAME/g;
    	  &Print_Msg("\nExecuting CLI command:\n\t$cmdstrcpy\n");

    	  my ($expectminiscr)="set timeout -1\nspawn su - $CONFIG{'CLIUSER'}\nexpect \"CLI\"\n";
	  if ($TESTRUN == 0) 
    	    { $expectminiscr.="send \"$cmdstrcpy\\r\"\n"; }
	  else
    	    { $expectminiscr.="send \"$cmdstrcpy2\\r\"\n"; }

    	  $expectminiscr.="expect \"CLI\"\nsend \"quit\\r\"\n";
    	  open(TMP,">$tmpexpscr") || die("ERROR: Could not create expect script <$tmpexpscr>!!\n\n");
    	  print TMP $expectminiscr;
    	  close(TMP);

    	  my (@retresult)=split(/\n/, `$expectprg $tmpexpscr`);
    	  `\\/bin/rm $tmpexpscr`;		# remove the temporary sxript

    	  # check if command returned a successful reply
    	  if (&checkCLI_retresult(@retresult) == -1)
      	  {
              &Print_Msg("\tERROR: The CLI command above did not execute successfully!!\n");
              &Print_Msg("\t       Please resolve the issue and try again.\n\n"); 
              &Enable_interrupts();		# enable interrupts
              exit 1;
      	  }
    	  else
      	  {
	     &Print_Msg("\tStatus: SUCCESS\n");
      	  }
      } # end outer loop

    # show new changed values
    &Print_Msg("\n\n-- View modified changes --\n");
    foreach my $chngtble_entry (@CHANGETABLE)
      {
	  my ($CLIATTRNAME)=$chngtble_entry;
          $CLIATTRNAME=~s/$OLD_NEW_FLG//g;		# remove prefix (OLD_/NEW_)

    	  $cmdstrcpy=$commandstr2;
    	  $cmdstrcpy=~s/CLIDB_ATTRIBUTE_NAME/$CLIATTRNAME/g;
    	  &Print_Msg("\nExecuting CLI command:\n\t$cmdstrcpy\n");

    	  my ($expectminiscr)="set timeout -1\nspawn su - $CONFIG{'CLIUSER'}\nexpect \"CLI\"\n";
    	  $expectminiscr.="send \"$cmdstrcpy\\r\"\nexpect \"CLI\"\nsend \"quit\\r\"\n";
    	  open(TMP,">$tmpexpscr") || die("ERROR: Could not create expect script <$tmpexpscr>!!\n\n");
    	  print TMP $expectminiscr;
    	  close(TMP);

    	  my (@retresult)=split(/\n/, `$expectprg $tmpexpscr`);
    	  `\\/bin/rm $tmpexpscr`;		# remove the temporary sxript

    	  # check if command returned a successful reply
    	  if (&checkCLI_retresult(@retresult) == -1)
      	  {
              &Print_Msg("\tERROR: The CLI command above did not execute successfully!!\n");
              &Print_Msg("\t       Please resolve the issue and try again.\n\n"); 
              &Enable_interrupts();		# enable interrupts
              exit 1;
      	  }
    	  else
      	  {
	     &Print_Msg("\tStatus: SUCCESS\n");
             &Print_Msg("\t\t" . &get_changedvals(@retresult) . "\n");
      	  }
      } # end outer loop
  # The changes were made to remove current CLITABLE_INFO file
  if ($rmCLITBLE == 1)
    {
       `\\/bin/rm $CONFIG{'CLIINFOFILE'}` if (-f $CONFIG{'CLIINFOFILE'});
    } #  if flag is set

} # end sub


sub inst_uninst_prompt
{ # start sub
    my ($msg,$token)=@_;
    my (@instptches)=split(/\|/, $CONFIG{$token});
   
    if ($CONTINUETASKS == 0)
      {
        print "\n\nThe patches will be " . $msg . "ed in the order shown.\n";
        print "Ready to $msg these patches?\n";
        foreach my $ptches (@instptches)
          {
	    print "\t$ptches\n";
          }

        if ($DEBUGMODE == 0)
          {
             print "\nNOTE: Once started, the <CTRL-C> interrupt will be disabled.\n";
             print "      It will be enabled after completion of <$msg>, \n";
             print "      or on fatal error\n\n";
          }

        print "\nPress <RETURN> to start or <CTRL-C> to abort install.\n";
        my $xyz=<>;
      }
    else
      {
	print "Continuing from previous halted location.\n\n";
      }

    &Disable_interrupts() if ($DEBUGMODE == 0)		# disable interrupts
} # end sub


sub revert_BTS_patches
{ # start sub
    my ($ptchlevoccur)=0;
    my (@CLICMDS_TBLE);
    my ($optemsutils)=0;
    my ($sucommand)=0;
    my ($START_TIME)=time();

    &inst_uninst_prompt("uninstall","REVERTPATCH");
    open(CMNDFILE,"$CONFIG{'UNINSTALL_CFILE'}") ||
	die("ERROR: Could not open $CONFIG{'UNINSTALL_CFILE'} for create!!\n\n");

    &Print_Msg("Backout/Revert started at: " . localtime() . "\n");
    &Print_Msg("------------------------------------------------------------\n");

    READ_NXTUNINST: while(<CMNDFILE>)
      {
         my ($ptchrel,
	     $platform,
	     $command);
     
         chomp;
         ($ptchrel,$platform,$command)=split(/\|/);

         # check if a cache value read was greater than 0
	 if ($LINECOUNT > 0)
           {
	     if ($CURRLINE < $LINECOUNT)
	       {
	         if ($SECTOR eq "U")
	           {
	              $CURRLINE++;		# increment value
		      next READ_NXTUNINST;	# get next line
	           }
	         elsif ($SECTOR eq "P")
	           {
		      goto POSTUNINSTALL;
	           }
	       } # $CURRLINE < $LINECOUNT
	   } # $LINECOUNT > 0

	 # if the lines start with CURRSRVR, push task to the post-install table
	 if ($ptchrel =~ /^CURRSRVR/i)
	   {
	     if ($command =~ /$CONFIG{'PTCHFLTAG'}/)
	       {
		 if ($command !~ /RUNARCHIVE_/)
		   {
		     s/$CONFIG{'PTCHFLTAG'}\d+/$CONFIG{'PTCHFLTAG'}$CONFIG{'PTCHEND'}/g;
		   }
	       }
	     push(@POSTACTION_TASKS, $_);
	     &save_prevlineinf($ptchrel,$platform,$command);
	     next READ_NXTUNINST;		# read next line
	   }

	# if the line contains PatchLevel, allow for three lines to be pushed to post-install table
	if ($command =~ /PatchLevel/)
	  {
	    if ($ptchlevoccur == 0)
	      {
		 if ($command =~ /$CONFIG{'PTCHFLTAG'}/)
		   {
		     #$command=~s/$CONFIG{'PTCHFLTAG'}\d+/$CONFIG{'PTCHFLTAG'}$CONFIG{'PTCHEND'}/g;
		     next READ_NXTUNINST;
		   }
		
		 my ($newcmd)=join("|","CURRSRVR","STDBY_CA",$command);
		 push(@POSTACTION_TASKS, $newcmd);
		 my ($newcmd)=join("|","CURRSRVR","STDBY_EM",$command);
		 push(@POSTACTION_TASKS, $newcmd);
	         &save_prevlineinf($ptchrel,$platform,$command);
	         $ptchlevoccur++;
		 goto INCREMENT_CURRLN_COUNT;
	      }
	    else
	      {
		 goto INCREMENT_CURRLN_COUNT;
	      }
	  } # PatchLevel

         NODESTATCMD:if ($command =~ /^nodestat/)
           {
	      my ($scndnodestat)=0;
	      if ($platform =~ /$PLTFORM/)
	        {
		   if (($prevptch =~ /CURRSRVR/i) && ($prevcmnd =~ /^wait/))
		     {
			my ($newcmd)=join("|",$ptchrel,$platform,$command);
		        push(@POSTACTION_TASKS,$newcmd);
			$scndnodestat=1;
	             }

	           # execute the nodestat command and gather info
	           goto INCREMENT_CURRLN_COUNT if ($scndnodestat == 1);
                   &run_nodestatcmd($ptchrel,$platform,$command);
	           &save_prevlineinf($ptchrel,$platform,$command);
	        }
	      else
	        {
	          &save_prevlineinf($ptchrel,$platform,$command);
	        }
           } # nodestat command

         PLATFORMCMD:if ($command =~ /^platform/)
           {
	      if ($platform =~ /$PLTFORM/)
	        {
		  my ($newcmd);
		  my ($junk,$args,@stuff)=split(/\s+/, $command);
		  $newcmd=join("|",$ptchrel,$platform,$command);

		  push(@POSTACTION_TASKS,$newcmd) if ($args =~ /start/);
	          &run_platformcommand($ptchrel,$platform,$command) if ($args !~ /start/);
	          &save_prevlineinf($ptchrel,$platform,$command);
                  &run_nodestatcmd($ptchrel,$platform,"nodestat")
						 if ($BUILD_UNINSTTBLE_ONLY == 0);
	          goto INCREMENT_CURRLN_COUNT;
	        }
	      elsif ($platform =~ /ANY_CA_EM/)
	        {
	           my ($cmd,$args,@info)=split(/\s+/, $command);
	           if ($PLTFORM =~ /STDBY_CA/)
		     {
			$platform = "STDBY_CA";
		        my (@pltfrms)=("CALL_AGT","FEAT_SAIN","FEAT_SPTC");
		        LOOPER:foreach my $tags (@pltfrms)
		          {
		            my ($cmnd2)=$command;
			    $cmnd2 =~ s/PLATFORMID/$CONFIG{$tags}/g;
			    if (($tags =~ /CALL_AGT/) && ($CONFIG{'STOP_CALLAGT'} == 0))
		              { next LOOPER; }
			    if (($tags =~ /FEAT_SAIN/) && ($CONFIG{'STOP_FSAIN'} == 0))
		              { next LOOPER; }
			    if (($tags =~ /FEAT_SPTC/) && ($CONFIG{'STOP_FSPTC'} == 0))
		              { next LOOPER; }
		            my ($newcmd)=join("|",$ptchrel,$platform,$command);
			    
			    if ($args =~ /start/)
			      {
				 push(@POSTACTION_TASKS,$newcmd);
	                         &save_prevlineinf($ptchrel,$platform,$command);
			         next LOOPER;
			      }
	                    &run_platformcommand($ptchrel,$platform,$cmnd2);
	                    &save_prevlineinf($ptchrel,$platform,$command);
			  } # end for-each
                       &run_nodestatcmd($ptchrel,$platform,"nodestat")
						 if ($BUILD_UNINSTTBLE_ONLY == 0);
		     } # PLTFORM=STDBY_CA
		   elsif ($PLTFORM =~ /STDBY_EM/)
		     {
			$platform = "STDBY_EM";
			$command =~ s/\-i\s+PLATFORMID/all/g;
		        my ($newcmd)=join("|",$ptchrel,$platform,$command);

		        if ($args =~ /start/)
			  {
		             push(@POSTACTION_TASKS,$newcmd);
			     next READ_NXTUNINST;
			  }
	                &run_platformcommand($ptchrel,$platform,$command);
	                &save_prevlineinf($ptchrel,$platform,$command);
                        &run_nodestatcmd($ptchrel,$platform,"nodestat")
						 if ($BUILD_UNINSTTBLE_ONLY == 0);
		     }
	        } # platform is ANY_CA_EM
	      else
	        {
	          &save_prevlineinf($ptchrel,$platform,$command);
	        }
           } # platform command
         if ($command =~ /^cd/)
           {
	      if ($platform =~ /$PLTFORM/)
	        {
	          my ($cmnd,$args)=split(/\s+/, $command);
		  if ($args eq "\/opt")
	            {
		      my ($cmd);
		      $MKDIRSET=0;
		      ($cmd,$DIRPTH)=split(/\s+/,$command);
		      &run_cdcommand($ptchrel,$platform,$command);
	              &save_prevlineinf($ptchrel,$platform,$command);
	            }
	          elsif ($args =~ /OptiCall/)
	            {
		      my ($cmd);
		      $MKDIRSET=0;
		      ($cmd,$DIRPTH)=split(/\s+/,$command);
		      &run_cdcommand($ptchrel,$platform,$command);
	              &save_prevlineinf($ptchrel,$platform,$command);
		
		      if ($args =~ /\/data/)
			{
		          my ($newcmd)=join("|","CURRSRVR",$platform,$command);
			  push(@POSTACTION_TASKS,$newcmd);
		        }
	            }
	          elsif ($args =~ /ems/)
		    {
		      my ($cmd);
		      $MKDIRSET=0;
		      ($cmd,$DIRPTH)=split(/\s+/,$command);
		      &run_cdcommand($ptchrel,$platform,$command);
	              &save_prevlineinf($ptchrel,$platform,$command);
		    }
		  elsif ($args =~ /\/opt\/BTS/)
		    {
		      my ($cmd);
		      $MKDIRSET=0;
		      ($cmd,$DIRPTH)=split(/\s+/,$command);
		      &run_cdcommand($ptchrel,$platform,$command);
	              &save_prevlineinf($ptchrel,$platform,$command);
		    }
		  elsif ($args =~ /$CONFIG{'PTCHFLTAG'}\d+/)
		    {
		      $MKDIRSET=0;
		      &run_cdcommand($ptchrel,$platform,$command);
	              &save_prevlineinf($ptchrel,$platform,$command);
		    }
	          else
		    {
		      if ($args !~ /$CONFIG{'PTCHFLTAG'}\d+/)
		        {
		          $MKDIRSET=0;
		          &run_cdcommand($ptchrel,$platform,$command);
	                  &save_prevlineinf($ptchrel,$platform,$command);
		        }
		    }
	        }
	      elsif (($platform =~ /PRI_EM/) || ($platform =~ /SEC_EM/))
	        {
		  $MKDIRSET=0;
	          &run_command_2($ptchrel,$platform,$command);
	          &save_prevlineinf($ptchrel,$platform,$command);
	        }
	      else
	        {
		  my ($cmnd,$args)=split(/\s+/, $command);
		  if ($args =~ /oracle/)
		    {
			if ($platform =~ /STDBY_EM/)
			  {
		             $MKDIRSET=0;
	                     &save_prevlineinf($ptchrel,$platform,$command);
			  }
		    } # command had 'oracle' in it
		  else
		    {
		      $MKDIRSET=0;
	              &save_prevlineinf($ptchrel,$platform,$command);
		    }
	        }
           } # the CD command
         if ($command =~ /^cp/)
           {
	      if ($platform =~ /$PLTFORM/)
	        {
	          &run_cpcommand($ptchrel,$platform,$command);
	          &save_prevlineinf($ptchrel,$platform,$command);
	        } # platforms are the same
	      elsif (($platform =~ /PRI_EM/) || ($platform =~ /SEC_EM/))
	        {
	          &run_command_2($ptchrel,$platform,$command);
	          &save_prevlineinf($ptchrel,$platform,$command);
	        }
	      else
	        {
	          &save_prevlineinf($ptchrel,$platform,$command);
	        }
           } # the CP command
         if ($command =~ /^mkdir/)
	   {
	      if ($platform =~ /$PLTFORM/)
	        {
		  $MKDIRSET=1;
		  my ($cmd,$argopt)=split(/\s+/, $command);
		  $argopt = "$DIRPTH/$argopt";
		  $command= "$cmd $argopt";
		  &run_mkdircommand($ptchrel,$platform,$command);
	          &save_prevlineinf($ptchrel,$platform,$command);
	        } # platforms are the same
	      else
	        {
	          &save_prevlineinf($ptchrel,$platform,$command);
	        }
	   } # the MKDIR command
         if ($command =~ /^date/)
           {
	      if ($platform =~ /$PLTFORM/)
	        {
	          &run_datecommand($ptchrel,$platform,$command);
	          &save_prevlineinf($ptchrel,$platform,$command);
	        } # platforms are the same
	      elsif (($platform =~ /PRI_EM/) || ($platform =~ /SEC_EM/))
	        {
	          &run_command_2($ptchrel,$platform,$command);
	          &save_prevlineinf($ptchrel,$platform,$command);
	        }
	      else
	        {
	          &save_prevlineinf($ptchrel,$platform,$command);
	        }
           } # the DATE command

INCREMENT_CURRLN_COUNT:
	$CURRLINE++;			# increment line count
      } # end read-loop
    close(CMNDFILE);

    print "\nReady to run post-remove steps.  Press <RETURN> to continue.\n";
    my $xyz=<>;

POSTUNINSTALL:
    $CURRLINE=0;		$SECTOR="P";
    foreach my $postinst_entry (@POSTACTION_TASKS)
      {
	my ($ptchrel,$platform,$command)=split(/\|/, $postinst_entry);
	
	if ($LINECOUNT > 0)
	  {
	    if ($CURRLINE < $LINECOUNT)
	      {
	          &save_prevlineinf($ptchrel,$platform,$command);
                  $CURRLINE++;
	          next;
	      }
	  }

	if ($sucommand == 1)
	  {
	     if ($command =~ /^cd/)
	       {
		  my ($cmd);
	          push(@CLICMDS_TBLE, $command);
	          &save_prevlineinf($ptchrel,$platform,$command);
                  $CURRLINE++;				# increment line counter
		  next;
	       }
	     elsif (($command =~ /^mv/) || ($command =~ /^cp/))
	       {
		  if ($command =~ /\/opt\/$CONFIG{'PTCHFLTAG'}\d+/)
		    {
			my ($cmd,@args)=split(/\s+/, $command);
			for (my $idx=0; $idx < scalar(@args); $idx++)
			  {
			    next if ($args[$idx] =~ /^\-p/);
			    $args[$idx] =~ s/^\/opt/\/opt\/STAGE/g;
			  } # end for loop
		      $command=join(" ",$cmd,@args);
		    } # end outer if
		  push(@CLICMDS_TBLE,$command);
	          &save_prevlineinf($ptchrel,$platform,$command);
                  $CURRLINE++;				# increment line counter
		  next;
	       } # command is mv or cp
	     elsif ($command =~ /^\.\/update_/)
	       {
		 $sucommand=0;		# reset the flag
		 my ($cmd,$usrid,$shlprmpt);
		 ($cmd,$usrid)=split(/\s+/, $command);
		 $shlprmpt="$usrid:$THISSRVR:\.\+\\\$";
	         $command =~ s/\spatch/patch/g;

		 push(@CLICMDS_TBLE, $command);

		 &run_sucommandset($ptchrel,$platform,$shlprmpt,@CLICMDS_TBLE);
	         &save_prevlineinf($ptchrel,$platform,$command);
	         @CLICMDS_TBLE=();			# empty array before adding
                 $CURRLINE++;				# increment line counter
	       } # last command of the set
	  } # sucommand is set

        if ($command =~ /^nodestat/)
          {
	    if ($platform =~ /$PLTFORM/)
	      {
	        # execute the nodestat command and gather info
                &run_nodestatcmd($ptchrel,$platform,$command);
	        &save_prevlineinf($ptchrel,$platform,$command);
		$CURRLINE++;
	      }
	    else
	      {
	        &save_prevlineinf($ptchrel,$platform,$command);
		$CURRLINE++;
	      }
          } # the nodestat command
	elsif ($command =~ /^chown/)
	  {
	    if ($platform =~ /PLTFORM/)
	      {
		 my ($cmnd,$args,$filenm)=split(/\s+/, $command);
		 my ($dirval)=&dirname($filenm);

		 if ($dirval eq ".")
		   { $filenm = "$DIRPTH/$filenm"; }
		 
		 $command=join(" ",$cmnd, $args, $filenm);
		 &run_chowncommand($ptchrel,$platform,$command);
	         &save_prevlineinf($ptchrel,$platform,$command);
                 $CURRLINE++;				# increment line counter
	      }
	    else
	      {
	        &save_prevlineinf($ptchrel,$platform,$command);
		$CURRLINE++;
	      }
	  }
	elsif ($command =~ /^chmod/)
	  {
	    if ($platform =~ /PLTFORM/)
	      {
		 my ($cmnd,$args,$filenm)=split(/\s+/, $command);
		 my ($dirval)=&dirname($filenm);

		 if ($dirval eq ".")
		   { $filenm = "$DIRPTH/$filenm"; }
		 
		 $command=join(" ",$cmnd, $args, $filenm);
		 &run_chmodcommand($ptchrel,$platform,$command);
	         &save_prevlineinf($ptchrel,$platform,$command);
                 $CURRLINE++;				# increment line counter
	      }
	    else
	      {
	        &save_prevlineinf($ptchrel,$platform,$command);
		$CURRLINE++;
	      }
	  }
        elsif ($command =~ /^cp/)
	  {
	    if ($platform =~ /ANY_CA_EM/)
	      {
		 $platform=$PLTFORM;
	      }
	    my ($cmnd2)=&rev_cpcommand($command);
	    my ($newcmd)=join("|",$ptchrel,$platform,$cmnd2);
	    if ($platform =~ /$PLTFORM/)
	      {
	        &run_cpcommand($ptchrel,$platform,$command);
	        &save_prevlineinf($ptchrel,$platform,$command);
		$CURRLINE++;
	      }
	    elsif (($platform =~ /PRI_EM/) || ($platform =~ /SEC_EM/))
	      {
	        &run_command_2($ptchrel,$platform,$command);
	        &save_prevlineinf($ptchrel,$platform,$command);
		$CURRLINE++;
	      }
	  } # the CP command
	 elsif ($command =~ /^CLI\>/)
	   {
	      if ($platform =~ /ACTIVE_EM/)
	        {
		   if (scalar(@CLICMDS_TBLE)==0)
		     {
		       my ($newcmd)="";
		       if ($command =~ /Switch_/)
		         {
		           $newcmd=$command;
			   $newcmd=~s/^CLI\>\s+//g;
		           push(@CLICMDS_TBLE, $newcmd);
		         } # if command starts with CLI> Switch_
			   
		       $newcmd="su - $CONFIG{'CLIUSER'}";
		       push(@CLICMDS_TBLE, $newcmd);
		       $newcmd=join("|",$ptchrel,$platform,$newcmd);
		     }
		   push(@CLICMDS_TBLE, $command) if ($command !~ /Switch_/);
	           &save_prevlineinf($ptchrel,$platform,$command);
		   $CURRLINE++;
		}  
	      else
	        {
	           &save_prevlineinf($ptchrel,$platform,$command);
		   $CURRLINE++;
	        }
	   } # the CLI commands
	 elsif ($command =~ /^Perform/)
	   {
	      if ($platform =~ /ANY_CA_EM/)
		{
		   if ($prevcmnd =~ /^CLI\>/)
		     {
		       &run_performtest_cmds($ptchrel,$platform,$command,@CLICMDS_TBLE);
	               &save_prevlineinf($ptchrel,$platform,$command);
		       (@CLICMDS_TBLE)=();	# empty the array
		       $CURRLINE++;
		     }
		}
	   } # the Perform commands
         elsif ($command =~ /^platform/)
           {
	      if ($platform =~ /$PLTFORM/)
	        {
	          &run_platformcommand($ptchrel,$platform,$command);
	          &save_prevlineinf($ptchrel,$platform,$command);
		  $CURRLINE++;
	        }
           } # the platform command
        elsif ($command =~ /^cd/)
	  {
	    if ($platform =~ /$PLTFORM/)
	        {
		  my ($cmd);
		  ($cmd,$DIRPTH)=split(/\s+/,$command);
		  &run_cdcommand($ptchrel,$platform,$command);
	          &save_prevlineinf($ptchrel,$platform,$command);
		  $CURRLINE++;
	        }
	    elsif (($platform =~ /PRI_EM/) || ($platform =~ /SEC_EM/))
	        {
	          &run_command_2($ptchrel,$platform,$command);
	          &save_prevlineinf($ptchrel,$platform,$command);
		  $CURRLINE++;
	        }
	  } # the CD command
        elsif ($command =~ /$CONFIG{'DAEMONMGR_SCR'}/)
	  {
	    if ($platform =~ /$PLTFORM/)
	        {
		  &run_daemonmgr_command($ptchrel,$platform,$command);
	          &save_prevlineinf($ptchrel,$platform,$command);
		  $CURRLINE++;
	        }
	  } # the daemonmgr script
         elsif ($command =~ /^date/)
           {
	      if ($platform =~ /ANY_CA_EM/)
	        {
	          $platform=$PLTFORM;
		}

	      if ($platform =~ /$PLTFORM/)
	        {
	          &run_datecommand($ptchrel,$platform,$command);
	          &save_prevlineinf($ptchrel,$platform,$command);
		  $CURRLINE++;
	        } # platforms are the same
	      elsif (($platform =~ /PRI_EM/) || ($platform =~ /SEC_EM/))
	        {
	          &run_command_2($ptchrel,$platform,$command);
	          &save_prevlineinf($ptchrel,$platform,$command);
		  $CURRLINE++;
	        }
           } # the DATE command
         elsif ($command =~ /^wait/)
           {
	      if ($platform =~ /$PLTFORM/)
	        {
	          if (($prevplatfrm eq $platform) && ($prevcmnd !~ /wait/))
		    {
	              &run_waitcommand($ptchrel,$platform,$command);
		    }
	          &save_prevlineinf($ptchrel,$platform,$command);
		  $CURRLINE++;
	        }
           } # the WAIT command
	 elsif ($command =~ /^su/)
	  {
	    if ($platform =~ /$PLTFORM/)
	      {
		 @CLICMDS_TBLE=();
	         push(@CLICMDS_TBLE, $command);
	         &save_prevlineinf($ptchrel,$platform,$command);
		 $sucommand=1;			# set start of su command
                 $CURRLINE++;			# increment line counter
	      }
	    else
	      {
	        &save_prevlineinf($ptchrel,$platform,$command);
                $CURRLINE++;
	      }
	  } # case for su command
         elsif ($command =~ /^pkill/)
           {
	      if ($platform =~ /$PLTFORM/)
	        {
	          &run_pkillcommand($ptchrel,$platform,$command);
	          &save_prevlineinf($ptchrel,$platform,$command);
		  $CURRLINE++;
	        }
           } # the PKILL command
         elsif ($command =~ /^\\rm/)
           {
	      if ($platform =~ /$PLTFORM/)
	        {
	          # process the rm command
	          $command =~ s/\\//g;
	          my ($cmnd,$argopt)=split(/\s+/, $command);
	          $argopt = "$DIRPTH/$argopt";
	          $command=join(" ", $cmnd, $argopt);

	          &run_rmcommand($ptchrel,$platform,$command);
	          &save_prevlineinf($ptchrel,$platform,$command);
		  $CURRLINE++;
	        }
           } # the RM command
      } # end FOR-LOOP

  &Print_Msg("------------------------------------------------------------\n");
  &Print_Msg("Backout/Revert completed at: " . localtime() . "\n");
} # end sub


sub upgrade_BTS_patches
{ # start sub
    my ($ptchlevoccur)=0;
    my (@UNINSTALL_PROC);
    my (@UNINSTALL_PROC2);
    my (@CLICMDS_TBLE);
    my ($chkline);
    my ($optemsutils)=0;
    my ($sucommand)=0;
    my ($START_TIME)=time();

    &inst_uninst_prompt("install","PATCHORDER") if ($BUILD_UNINSTTBLE_ONLY == 0);

    # open commands file and execute the commands on the switch
    $CMNDFLE = $CONFIG{'CMNDSTBL_FLE'};
    open (CMNDFILE,"$CMNDFLE") || die ("ERROR: Could not open command table file!!\n");

    # check first line of the command file
    $chkline=`/bin/cat $CMNDFLE | /bin/head -1`;
    chomp($chkline);
    if ($chkline =~ /^$CONFIG{'PTCHFLTAG'}\d+\:\s+/)
      {
	my ($dirnme)=dirname($CFGFILE);
	print "\n\nERROR: The command file <$CMNDFLE> has not been pre-processed!!\n";
        print "       Please run the script: $dirnme/scripts/CommandsFilePreProc.pl, then re-run\n";
	print "       this script: $dirnme/scripts/MOP_Installer.pl\n\n";
        exit 1;
      }

    if ($BUILD_UNINSTTBLE_ONLY == 0)
      {
         &Print_Msg("Install/Upgrade started at: " . localtime() . "\n");
         &Print_Msg("------------------------------------------------------------\n");
      }
    else
      {
	print "\nBuilding the uninstall sequence table ... \n";
      }

    READ_NEXT: while (<CMNDFILE>)
      {
         my ($ptchrel,
	     $platform,
	     $command);
     
         chomp;
         ($ptchrel,$platform,$command)=split(/\|/);

	 # check if a cache value read greater than 0
         if ($LINECOUNT > 0)
	   {
	      if ($CURRLINE < $LINECOUNT)
	        {
		   if ($SECTOR eq "I")
		     {
	               $CURRLINE++;		# increment value
		       next READ_NEXT;	        # read next line from command file
		     } 
	           elsif ($SECTOR eq "P")
	             {
			goto POSTINSTALL;
	             } # sector = 'P' - post install/uninstall
		} # linecount > currline
           } # linecount > 0

	 if ($command =~ /\/opt\/$CONFIG{'PTCHFLTAG'}\d+/)
	   {
	      $command =~ s/\/opt\/$CONFIG{'PTCHFLTAG'}\d+/\/opt\/STAGE\/$ptchrel/g;
	   }
	
	# if the lines start with CURRSRVR, push task to the post-install table
	if ($ptchrel =~ /^CURRSRVR/i)
	  {
	     if ($command =~ /$CONFIG{'PTCHFLTAG'}/)
	       {
		  if ($command !~ /RUNARCHIVE_/)
		    {
	               s/$CONFIG{'PTCHFLTAG'}\d+/$CONFIG{'PTCHFLTAG'}$CONFIG{'PTCHEND'}/g;
		    }
	       }
	      push(@POSTACTION_TASKS, $_);
	      &save_prevlineinf($ptchrel,$platform,$command);
	      next READ_NEXT;
	  }
	# if the line contains PatchLevel, allow for three lines to be pushed to post-install table
	if ($command =~ /PatchLevel/)
	  {
	    if ($ptchlevoccur == 0)
	      {
		 if ($command =~ /$CONFIG{'PTCHFLTAG'}/)
		   {
		     next READ_NEXT if ($command !~ /RUNARCHIVE_/);
		   }
		
		 my ($newcmd)=join("|","CURRSRVR","STDBY_CA",$command);
		 push(@POSTACTION_TASKS, $newcmd);
		 $newcmd=join("|","CURRSRVR","STDBY_EM",$command);
		 push(@POSTACTION_TASKS, $newcmd);
                 
		 my ($cmnd2)="cp /opt/STAGE/$CONFIG{'PTCHFLTAG'}$CONFIG{'PTCHEND'}/PatchLevel /opt/ems/utils";
		 $newcmd=join("|","CURRSRVR","STDBY_CA",$cmnd2);
		 push(@POSTACTION_TASKS, $newcmd);
		 $newcmd=join("|","CURRSRVR","STDBY_EM",$cmnd2);
		 push(@POSTACTION_TASKS, $newcmd);

	         &save_prevlineinf($ptchrel,$platform,$command);
	         $ptchlevoccur++;
		 goto INCREMENT_CURRLINE_COUNT;
	      }
	    else
	      {
		 goto INCREMENT_CURRLINE_COUNT;
	      }
	  } # command PatchLevel


         NODESTATCMD:if ($command =~ /^nodestat/)
           {
	      if ($platform =~ /$PLTFORM/)
	        {
	           my ($scndnodestat)=0;
	           # execute the nodestat command and gather info
		   if (($prevptch =~ /CURRSRVR/i) && ($prevcmnd =~ /^wait/))
		     {
			my ($newcmd)=join("|",$ptchrel,$platform,$command);
		        push(@POSTACTION_TASKS,$newcmd);
			$scndnodestat=1;
	             }

		   goto INCREMENT_CURRLINE_COUNT if ($scndnodestat == 1);
                   &run_nodestatcmd($ptchrel,$platform,$command)
						 if ($BUILD_UNINSTTBLE_ONLY == 0);
	           &save_prevlineinf($ptchrel,$platform,$command);

		   # store in the uninstall table if pattern not matched
		   my ($newcmd)=join("|",$ptchrel,$platform,$command);
		   $newcmd=~s/$CONFIG{'PTCHFLTAG'}\d+/$CONFIG{'PTCHFLTAG'}$CONFIG{'PTCHEND'}/g;
		   push(@UNINSTALL_PROC,$newcmd);
	        }
	      else
	        {
	          &save_prevlineinf($ptchrel,$platform,$command);
	        }
           } # the NODESTAT command
         PLATFORMCMD:if ($command =~ /^platform/)
           {
	      if ($platform =~ /$PLTFORM/)
	        {
	          &run_platformcommand($ptchrel,$platform,$command)
						 if ($BUILD_UNINSTTBLE_ONLY == 0);
	          &save_prevlineinf($ptchrel,$platform,$command);
		  my ($newcmd)=join("|",$ptchrel,$platform,$command);
		  $newcmd=~s/$CONFIG{'PTCHFLTAG'}\d+/$CONFIG{'PTCHFLTAG'}$CONFIG{'PTCHEND'}/g;
		  push(@UNINSTALL_PROC,$newcmd);
                  &run_nodestatcmd($ptchrel,$platform,"nodestat")
						 if ($BUILD_UNINSTTBLE_ONLY == 0);
	        }
	      elsif ($platform =~ /ANY_CA_EM/)
	        {
	           my ($cmd,$args,@info)=split(/\s+/, $command);
	           if ($PLTFORM =~ /STDBY_CA/)
		     {
			$platform = "STDBY_CA";
		        my (@pltfrms)=("CALL_AGT","FEAT_SAIN","FEAT_SPTC");
		        LOOPER:foreach my $tags (@pltfrms)
		          {
		            my ($cmnd2)=$command;
			    $cmnd2 =~ s/PLATFORMID/$CONFIG{$tags}/g;
			    
			    if (($tags =~ /CALL_AGT/) && ($CONFIG{'STOP_CALLAGT'} == 0))
		              { next LOOPER; }
			    if (($tags =~ /FEAT_SAIN/) && ($CONFIG{'STOP_FSAIN'} == 0))
		              { next LOOPER; }
			    if (($tags =~ /FEAT_SPTC/) && ($CONFIG{'STOP_FSPTC'} == 0))
		              { next LOOPER; }
		            my ($newcmd)=join("|",$ptchrel,$platform,$cmnd2);
		            $newcmd=~s/$CONFIG{'PTCHFLTAG'}\d+/$CONFIG{'PTCHFLTAG'}$CONFIG{'PTCHEND'}/g;

		            if ($args =~ /start/)
			      {
		                 push(@POSTACTION_TASKS,$newcmd);
	                         &save_prevlineinf($ptchrel,$platform,$command);
				 next LOOPER;
			      }
	                    &run_platformcommand($ptchrel,$platform,$cmnd2)
						 if ($BUILD_UNINSTTBLE_ONLY == 0);
	                    &save_prevlineinf($ptchrel,$platform,$command);
		            push(@UNINSTALL_PROC,$newcmd) if ($args =~ /stop/);
			  } # end for-each
                        &run_nodestatcmd($ptchrel,$platform,"nodestat")
						 if ($BUILD_UNINSTTBLE_ONLY == 0);
		     } # PLTFORM=STDBY_CA
		   elsif ($PLTFORM =~ /STDBY_EM/)
		     {
			$platform = "STDBY_EM";
			$command =~ s/\-i\s+PLATFORMID/all/g;
		        my ($newcmd)=join("|",$ptchrel,$platform,$command);
		        $newcmd=~s/$CONFIG{'PTCHFLTAG'}\d+/$CONFIG{'PTCHFLTAG'}$CONFIG{'PTCHEND'}/g;

		        if ($args =~ /start/)
			  {
		             push(@POSTACTION_TASKS,$newcmd);
			     next READ_NEXT;
			  }
	                &run_platformcommand($ptchrel,$platform,$command)
						if ($BUILD_UNINSTTBLE_ONLY == 0);
	                &save_prevlineinf($ptchrel,$platform,$command);
		        push(@UNINSTALL_PROC,$newcmd) if ($args =~ /stop/);
                        &run_nodestatcmd($ptchrel,$platform,"nodestat")
						 if ($BUILD_UNINSTTBLE_ONLY == 0);
		     }
	        } # platform is ANY_CA_EM
	      else
	        {
	          &save_prevlineinf($ptchrel,$platform,$command);
	        }
           } # the PLATFORM command
         if ($command =~ /^cd/)
           {
	      if ($platform =~ /$PLTFORM/)
	        {
	          my ($cmnd,$args)=split(/\s+/, $command);
		  if ($args eq "\/opt")
	            {
		      my ($cmd);
		      $MKDIRSET=0;
		      $optBTSflg=0;
		      ($cmd,$DIRPTH)=split(/\s+/,$command);
		      &run_cdcommand($ptchrel,$platform,$command)
						if ($BUILD_UNINSTTBLE_ONLY == 0);
	              &save_prevlineinf($ptchrel,$platform,$command);
		      
		      my ($newcmd)=join("|",$ptchrel,$platform,$command);
		      push(@UNINSTALL_PROC2, $newcmd);
	            }
	          elsif ($args =~ /OptiCall/)
	            {
		      my ($cmd);
		      $MKDIRSET=0;
		      $optBTSflg=0;
		      ($cmd,$DIRPTH)=split(/\s+/,$command);
		      &run_cdcommand($ptchrel,$platform,$command)
						if ($BUILD_UNINSTTBLE_ONLY == 0);
	              &save_prevlineinf($ptchrel,$platform,$command);
		
		      if ($args !~ /\/data/)
		        {
		          my ($newcmd)=join("|",$ptchrel,$platform,$command);
		          push(@UNINSTALL_PROC2,$newcmd);
		        }
		      else
			{
		          my ($newcmd)=join("|","CURRSRVR",$platform,$command);
			  push(@POSTACTION_TASKS,$newcmd);
		        }
	            }
	          elsif ($args =~ /\/opt\/BTS/)
		    {
		      my ($cmd);
		      $MKDIRSET=0;
		      $optBTSflg=1;
		      
		      ($cmd,$DIRPTH)=split(/\s+/,$command);
		      &run_cdcommand($ptchrel,$platform,$command)
						if ($BUILD_UNINSTTBLE_ONLY == 0);
	              &save_prevlineinf($ptchrel,$platform,$command);
		      my ($newcmd)=join("|",$ptchrel,$platform,$command);
		      push(@UNINSTALL_PROC2,$newcmd);
		    }
	          elsif ($args =~ /ems/)
		    {
		      my ($cmd);
		      $MKDIRSET=0;
		      $optBTSflg=0;
		      ($cmd,$DIRPTH)=split(/\s+/,$command);
		      &run_cdcommand($ptchrel,$platform,$command)
						if ($BUILD_UNINSTTBLE_ONLY == 0);
	              &save_prevlineinf($ptchrel,$platform,$command);
		      my ($newcmd)=join("|",$ptchrel,$platform,$command);
		      push(@UNINSTALL_PROC2,$newcmd);
		    }
		  elsif ($args =~ /\/opt\/BTS/)
		    {
		      my ($cmd);
		      $MKDIRSET=0;
		      $optBTSflg=0;
		      ($cmd,$DIRPTH)=split(/\s+/,$command);
		      &run_cdcommand($ptchrel,$platform,$command)
						if ($BUILD_UNINSTTBLE_ONLY == 0);
	              &save_prevlineinf($ptchrel,$platform,$command);
		      my ($newcmd)=join("|",$ptchrel,$platform,$command);
		      push(@UNINSTALL_PROC2,$newcmd);
		    }
	          elsif ($args =~ /\/opt\/oracle/)
		    {
		      my ($cmd);
		      $MKDIRSET=0;
		      $optBTSflg=0;
		      ($cmd,$DIRPTH)=split(/\s+/,$command);
		      &run_cdcommand($ptchrel,$platform,$command)
						if ($BUILD_UNINSTTBLE_ONLY == 0);
	              &save_prevlineinf($ptchrel,$platform,$command);
		      my ($newcmd)=join("|",$ptchrel,$platform,$command);
		      push(@UNINSTALL_PROC2,$newcmd);
		    }
		  elsif ($args =~ /$CONFIG{'PTCHFLTAG'}\d+/)
		    {
		      $MKDIRSET=0;
		      $optBTSflg=0;
		      &run_cdcommand($ptchrel,$platform,$command)
						if ($BUILD_UNINSTTBLE_ONLY == 0);
	              &save_prevlineinf($ptchrel,$platform,$command);
		      my ($newcmd)=join("|",$ptchrel,$platform,$command);
		      push(@UNINSTALL_PROC2,$newcmd);
		    }
	          else
		    {
		      if ($args !~ /$CONFIG{'PTCHFLTAG'}\d+/)
		        {
		          $MKDIRSET=0;
		          $optBTSflg=0;
		          &run_cdcommand($ptchrel,$platform,$command)
						if ($BUILD_UNINSTTBLE_ONLY == 0);
	                  &save_prevlineinf($ptchrel,$platform,$command);
		          my ($newcmd)=join("|",$ptchrel,$platform,$command);
		          push(@UNINSTALL_PROC2,$newcmd);
		        }
		    }
	        }
	      elsif (($platform =~ /PRI_EM/) || ($platform =~ /SEC_EM/))
	        {
		  $MKDIRSET=0;
		  $optBTSflg=0;
	          &run_command_2($ptchrel,$platform,$command)
						if ($BUILD_UNINSTTBLE_ONLY == 0);
	          &save_prevlineinf($ptchrel,$platform,$command);
	        }
	      else
	        {
		  my ($cmnd,$args)=split(/\s+/, $command);
		  if ($args =~ /oracle/)
		    {
			if ($platform =~ /STDBY_EM/)
			  {
		             $MKDIRSET=0;
		             $optBTSflg=0;
	                     &save_prevlineinf($ptchrel,$platform,$command);
			  }
		    } # command had 'oracle' in it
		  else
		    {
		      $MKDIRSET=0;
		      $optBTSflg=0;
	              &save_prevlineinf($ptchrel,$platform,$command);
		    }
	        }
           } # the CD command
         if ($command =~ /^cp/)
           {
	      if ($platform =~ /$PLTFORM/)
	        {
	          if ($command =~ /\/opt\/$CONFIG{'PTCHFLTAG'}\d+/)
	            {
		      $command=&process_cpcommand($command,$DIRPTH);
		    }
	          elsif (($command =~ /$CONFIG{'CALL_AGT'}/) ||
		       ($command =~ /$CONFIG{'FEAT_SAIN'}/) ||
		        ($command =~ /$CONFIG{'FEAT_SPTC'}/))
	            {
		      $command=&process_cpcommand($command,$DIRPTH);
	            }
	          elsif ($optBTSflg == 1)
		    {
		      $command=&process_cpcommand($command,$DIRPTH);
		      $optBTSflg=0;
		    }
	          elsif ($command =~ /$CONFIG{'PTCHFLTAG'}/)
	            {
		      $command=&process_cpcommand($command,$DIRPTH);
		    }
	          else
	            {
		      if ($MKDIRSET == 1)
		        {
			  $command=&process_cpcommand($command,$DIRPTH);
			}
		      else
			{
		          $command=&process_cpcommand($command,$DIRPTH);
			}
		    }

		  # create reverse command
		  my ($cmnd2)=&rev_cpcommand($command);
		  my ($newcmd)=join("|",$ptchrel,$platform,$cmnd2);
		  if ($cmnd2 =~ /$CONFIG{'PTCHFLTAG'}/)
		    {
		       goto SKIP_1 if ($cmnd2 !~ /RUNARCHIVE_/);
		       push(@UNINSTALL_PROC2,$newcmd);
		    }

	          SKIP_1:
	          &run_cpcommand($ptchrel,$platform,$command)
						if ($BUILD_UNINSTTBLE_ONLY == 0);
	          &save_prevlineinf($ptchrel,$platform,$command);
	        } # platforms are the same
	      elsif (($platform =~ /PRI_EM/) || ($platform =~ /SEC_EM/))
	        {
	          &run_command_2($ptchrel,$platform,$command)
						if ($BUILD_UNINSTTBLE_ONLY == 0);
	          &save_prevlineinf($ptchrel,$platform,$command);
	        }
	      else
	        {
	          &save_prevlineinf($ptchrel,$platform,$command);
	        }
           } # the CP command
         if ($command =~ /^mkdir/)
	   {
	      if ($platform =~ /$PLTFORM/)
	        {
		  $MKDIRSET=1;
		  my ($cmd,$argopt)=split(/\s+/, $command);
		  $argopt = "$DIRPTH/$argopt";
		  $command= "$cmd $argopt";
		  &run_mkdircommand($ptchrel,$platform,$command)
						if ($BUILD_UNINSTTBLE_ONLY == 0);
	        } # platforms are the same
	      else
	        {
	          &save_prevlineinf($ptchrel,$platform,$command);
	        }
	   } # the MKDIR command
         if ($command =~ /^date/)
           {
	      if ($platform =~ /$PLTFORM/)
	        {
	          &run_datecommand($ptchrel,$platform,$command)
						if ($BUILD_UNINSTTBLE_ONLY == 0);
	          &save_prevlineinf($ptchrel,$platform,$command);
	        } # platforms are the same
	      elsif (($platform =~ /PRI_EM/) || ($platform =~ /SEC_EM/))
	        {
	          &run_command_2($ptchrel,$platform,$command)
						if ($BUILD_UNINSTTBLE_ONLY == 0);
	          &save_prevlineinf($ptchrel,$platform,$command);
	        }
	      else
	        {
	          &save_prevlineinf($ptchrel,$platform,$command);
	        }
           } # the DATE command
        if ($command =~ /$CONFIG{'DAEMONMGR_SCR'}/)
	  {
	    if ($platform =~ /$PLTFORM/)
	        {
		  &run_daemonmgr_command($ptchrel,$platform,$command)
							if ($BUILD_UNINSTTBLE_ONLY == 0);
		  my ($newcmd)=join("|",$ptchrel,$platform,$command);
		  push(@UNINSTALL_PROC2, $newcmd);
	          &save_prevlineinf($ptchrel,$platform,$command);
                  $CURRLINE++;				# increment line counter
	        }
	      else
	        {
	           &save_prevlineinf($ptchrel,$platform,$command);
	           $CURRLINE++;
	        }
	   }
	if ($command =~ /^chmod/)
	  {
	    if ($platform =~ /$PLTFORM/)
	      {
		 my ($cmnd,$args,$filenm)=split(/\s+/, $command);
		 my ($dirval)=&dirname($filenm);

		 if ($dirval eq ".")
		   { $filenm = "$DIRPTH/$filenm"; }
		 
		 $command=join(" ",$cmnd, $args, $filenm);
		 &run_chmodcommand($ptchrel,$platform,$command)
						if ($BUILD_UNINSTTBLE_ONLY == 0);
		 my ($newcmd)=join("|",$ptchrel,$platform,$command);
		 push(@UNINSTALL_PROC2, $newcmd);
	         &save_prevlineinf($ptchrel,$platform,$command);
                 $CURRLINE++;				# increment line counter
	      }
	    else
	      {
	        &save_prevlineinf($ptchrel,$platform,$command);
                $CURRLINE++;
	      }
	  } # chmod command
	if ($command =~ /^chown/)
	  {
	    if ($platform =~ /$PLTFORM/)
	      {
		 my ($cmnd,$args,$filenm)=split(/\s+/, $command);
		 my ($dirval)=&dirname($filenm);

		 if ($dirval eq ".")
		   { $filenm = "$DIRPTH/$filenm"; }
		 
		 $command=join(" ",$cmnd, $args, $filenm);
		 &run_chowncommand($ptchrel,$platform,$command)
						if ($BUILD_UNINSTTBLE_ONLY == 0);
		 my ($newcmd)=join("|",$ptchrel,$platform,$command);
		 push(@UNINSTALL_PROC2, $newcmd);
	         &save_prevlineinf($ptchrel,$platform,$command);
                 $CURRLINE++;				# increment line counter
	      }
	    else
	      {
	        &save_prevlineinf($ptchrel,$platform,$command);
                $CURRLINE++;
	      }
	  } # chown command
	   
         if ($command =~ /^wait/)
           {
	      if ($platform =~ /$PLTFORM/)
	        {
		  my ($newcmd)=join("|",$ptchrel,$platform,$command);
	          &run_waitcommand($ptchrel,$platform,$command)
							if ($BUILD_UNINSTTBLE_ONLY == 0);
		  push(@UNINSTALL_PROC2, $newcmd);
                  $CURRLINE++;				# increment line counter
	          &save_prevlineinf($ptchrel,$platform,$command);
	        }
	      else
	        {
	           &save_prevlineinf($ptchrel,$platform,$command);
	           $CURRLINE++;
	        }
           }
         if ($command =~ /^\\rm/)
           {
	      if ($platform =~ /$PLTFORM/)
	        {
	          # process the rm command
	          $command =~ s/\\//g;
	          my ($cmnd,$argopt)=split(/\s+/, $command);
	          $argopt = "$DIRPTH/$argopt";
	          $command=join(" ", $cmnd, $argopt);

		  my ($newcmd)=join("|","CURRSRVR",$platform,$command);
		  push(@POSTACTION_TASKS,$newcmd);
	          &save_prevlineinf($ptchrel,$platform,$command);
	        } # platforms are the same
	      else
	        {
	          &save_prevlineinf($ptchrel,$platform,$command);
	        }
           } # the RM command

INCREMENT_CURRLINE_COUNT:
        $CURRLINE++;			# increment current line counter
      } # end while loop
    close(CMNDFILE);

    # generate unstall commands set table
    my (@uninstlist)=split(/\|/, $CONFIG{'REVERTPATCH'});
    foreach my $patchrel (@uninstlist)
      {
	
	for (my $idx=0; $idx < scalar(@UNINSTALL_PROC2); $idx++)
	  {
	    if ($UNINSTALL_PROC2[$idx] =~ /^$patchrel/)
	      {
	        push(@UNINSTALL_PROC, $UNINSTALL_PROC2[$idx]);
	      } # if found add to main uninstall table
	  } # inner loop
      } # outer for-loop

    if ($BUILD_UNINSTTBLE_ONLY == 0) 
      {
         print "\nReady to run post-install steps.  Press <RETURN> to continue.\n";
         my $xyz=<>;
      }

POSTINSTALL:
    $CURRLINE=0;	$SECTOR="P";
    # step through the post install table
    foreach my $postinst_entry (@POSTACTION_TASKS)
      {
	my ($ptchrel,$platform,$command)=split(/\|/, $postinst_entry);
	
        if ($LINECOUNT > 0)
	  {
	    if ($CURRLINE < $LINECOUNT)
	      {
	         &save_prevlineinf($ptchrel,$platform,$command);
	         $CURRLINE++;
	         next;
	      }
          }

	 if ($command =~ /\/opt\/$CONFIG{'PTCHFLTAG'}\d+/)
	   {
	      $command =~ s/\/opt\/$CONFIG{'PTCHFLTAG'}\d+/\/opt\/STAGE\/$ptchrel/g;
	   }
	
	if ($sucommand == 1)
	  {
	     if ($command =~ /^cd/)
	       {
		  my ($cmd);
	          push(@CLICMDS_TBLE, $command);
	          &save_prevlineinf($ptchrel,$platform,$command);
                  $CURRLINE++;				# increment line counter
		  next;
	       }
	     elsif (($command =~ /^mv/) || ($command =~ /^cp/))
	       {
		  if ($command =~ /\/opt\/$CONFIG{'PTCHFLTAG'}\d+/)
		    {
			my ($cmd,@args)=split(/\s+/, $command);
			for (my $idx=0; $idx < scalar(@args); $idx++)
			  {
			    next if ($args[$idx] =~ /^\-p/);
			    $args[$idx] =~ s/^\/opt/\/opt\/STAGE/g;
			  } # end for loop
		      $command=join(" ",$cmd,@args);
		    } # end outer if
		  push(@CLICMDS_TBLE,$command);
	          &save_prevlineinf($ptchrel,$platform,$command);
                  $CURRLINE++;				# increment line counter
		  next;
	       } # command is mv or cp
	     elsif ($command =~ /^\.\/update_/)
	       {
		 $sucommand=0;		# reset the flag
		 my ($cmd,$usrid,$shlprmpt);
		 ($cmd,$usrid)=split(/\s+/, $command);
		 $shlprmpt="$usrid:$THISSRVR:\.\+\\\$";
	         $command =~ s/\spatch/patch/g;

		 push(@CLICMDS_TBLE, $command);

		 &run_sucommandset($ptchrel,$platform,$shlprmpt,@CLICMDS_TBLE)
						if ($BUILD_UNINSTTBLE_ONLY == 0);
	         if ($command =~ /_subscriber/)
	           {
	              foreach my $entry (@CLICMDS_TBLE)
	                {
			   my ($newcmd);
	                   $entry =~ s/patch/unpatch/g;
			   $newcmd=join("|",$ptchrel,$platform,$entry);
			   push(@UNINSTALL_PROC, $newcmd);
	                }
	           } # end case for update_subscriber
	           @CLICMDS_TBLE=();			# empty array before adding
                 $CURRLINE++;				# increment line counter
	       } # last command of the set
	  } # sucommand is set

        if ($command =~ /^nodestat/)
          {
	    if ($platform =~ /$PLTFORM/)
	      {
	        # execute the nodestat command and gather info
                &run_nodestatcmd($ptchrel,$platform,$command)
						 if ($BUILD_UNINSTTBLE_ONLY == 0);
	        &save_prevlineinf($ptchrel,$platform,$command);
		push(@UNINSTALL_PROC, $postinst_entry);
                $CURRLINE++;				# increment line counter
	      }
	    else
	      {
	        &save_prevlineinf($ptchrel,$platform,$command);
                $CURRLINE++;
	      }
          } # the nodestat command
	
	if ($command =~ /^chown/)
	  {
	    if ($platform =~ /$PLTFORM/)
	      {
		 my ($cmnd,$args,$filenm)=split(/\s+/, $command);
		 my ($dirval)=&dirname($filenm);

		 if ($dirval eq ".")
		   { $filenm = "$DIRPTH/$filenm"; }
		 
		 $command=join(" ",$cmnd, $args, $filenm);
		 &run_chowncommand($ptchrel,$platform,$command)
						if ($BUILD_UNINSTTBLE_ONLY == 0);
	         &save_prevlineinf($ptchrel,$platform,$command);

		 $postinst_entry = join("|", $ptchrel, $platform, $command);

		 push(@UNINSTALL_PROC, $postinst_entry);
                 $CURRLINE++;				# increment line counter
	      }
	    else
	      {
	        &save_prevlineinf($ptchrel,$platform,$command);
                $CURRLINE++;
	      }
	  } # chown command
	   
	if ($command =~ /^chmod/)
	  {
	    if ($platform =~ /$PLTFORM/)
	      {
		 my ($cmnd,$args,$filenm)=split(/\s+/, $command);
		 my ($dirval)=&dirname($filenm);

		 if ($dirval eq ".")
		   { $filenm = "$DIRPTH/$filenm"; }
		 
		 $command=join(" ",$cmnd, $args, $filenm);
		 &run_chmodcommand($ptchrel,$platform,$command)
						if ($BUILD_UNINSTTBLE_ONLY == 0);
	         &save_prevlineinf($ptchrel,$platform,$command);

		 $postinst_entry = join("|", $ptchrel, $platform, $command);

		 push(@UNINSTALL_PROC, $postinst_entry);
                 $CURRLINE++;				# increment line counter
	      }
	    else
	      {
	        &save_prevlineinf($ptchrel,$platform,$command);
                $CURRLINE++;
	      }
	  } # chmod command
	   
        if ($command =~ /^cp/)
	  {
	    if ($platform =~ /ANY_CA_EM/)
	      {
		 $platform=$PLTFORM;
	      }
	    my ($cmnd2)=&rev_cpcommand($command);
	    $cmnd2=&process_cpcommand($cmnd2,$DIRPTH);
	    $command=&process_cpcommand($command,$DIRPTH);

	    if ($cmnd2 =~ /\/ftp\/deposit/)
              {
	        &save_prevlineinf($ptchrel,$platform,$command);
                $CURRLINE++;				# increment line counter
                next;					# process next command
	      }
	    my ($newcmd)=join("|",$ptchrel,$platform,$cmnd2);
	    if ($platform =~ /$PLTFORM/)
	      {
	        if ($cmnd2 =~ /$CONFIG{'PTCHFLTAG'}/)
	          {
		    goto SKIP_2 if ($cmnd2 !~ /RUNARCHIVE_/);
	            push(@UNINSTALL_PROC, $newcmd);
	          }
	      SKIP_2:
	        &run_cpcommand($ptchrel,$platform,$command)
						if ($BUILD_UNINSTTBLE_ONLY == 0);
	        &save_prevlineinf($ptchrel,$platform,$command);
                $CURRLINE++;				# increment line counter
	      }
	    elsif (($platform =~ /PRI_EM/) || ($platform =~ /SEC_EM/))
	      {
	        if ($cmnd2 !~ /$CONFIG{'PTCHFLTAG'}/)
	          {
	            push(@UNINSTALL_PROC, $newcmd);
	          }
	        &run_command_2($ptchrel,$platform,$command)
						if ($BUILD_UNINSTTBLE_ONLY == 0);
	        &save_prevlineinf($ptchrel,$platform,$command);
                $CURRLINE++;				# increment line counter
	      }
	    else
	      {
	        &save_prevlineinf($ptchrel,$platform,$command);
                $CURRLINE++;
	      }
	  }
	 elsif ($command =~ /^su/)
	  {
	    if ($platform =~ /$PLTFORM/)
	      {
		 @CLICMDS_TBLE=();
	         push(@CLICMDS_TBLE, $command);
	         &save_prevlineinf($ptchrel,$platform,$command);
		 $sucommand=1;			# set start of su command
                 $CURRLINE++;			# increment line counter
	      }
	    else
	      {
	        &save_prevlineinf($ptchrel,$platform,$command);
                $CURRLINE++;
	      }
	  } # case for su command
	 elsif ($command =~ /^CLI\>/)
	   {
	      if ($platform =~ /ACTIVE_EM/)
	        {
		   if (scalar(@CLICMDS_TBLE)==0)
		     {
		       my ($newcmd)="";
		       if ($command =~ /Switch_/)
		         {
		           $newcmd=$command;
			   $newcmd=~s/^CLI\>\s+//g;
		           push(@CLICMDS_TBLE, $newcmd);
		         } # if command starts with CLI> Switch_
			   
		       $newcmd="su - $CONFIG{'CLIUSER'}";
		       push(@CLICMDS_TBLE, $newcmd);
		       $newcmd=join("|",$ptchrel,$platform,$newcmd);
		     }
		   push(@CLICMDS_TBLE, $command) if ($command !~ /Switch_/);
	           &save_prevlineinf($ptchrel,$platform,$command);
		   push(@UNINSTALL_PROC, $postinst_entry);
                   $CURRLINE++;				# increment line counter
		}  
	      else
	        {
	           &save_prevlineinf($ptchrel,$platform,$command);
	           $CURRLINE++;
	        }
	   }
	 elsif ($command =~ /^Perform/)
	   {
	      if ($platform =~ /ANY_CA_EM/)
		{
		   if ($prevcmnd =~ /^CLI\>/)
		     {
		       &run_performtest_cmds($ptchrel,$platform,$command,@CLICMDS_TBLE)
								if ($BUILD_UNINSTTBLE_ONLY == 0);
	               &save_prevlineinf($ptchrel,$platform,$command);
		       my ($newcmd)=join("|",$ptchrel,$platform,$command);
		       push(@UNINSTALL_PROC,$newcmd);
		       (@CLICMDS_TBLE)=();	# empty the array
                       $CURRLINE++;				# increment line counter
		     }
		}
	      else
	        {
	           &save_prevlineinf($ptchrel,$platform,$command);
	           $CURRLINE++;
	        }
	   }
         elsif ($command =~ /^platform/)
           {
	      if ($platform =~ /$PLTFORM/)
	        {
	          &run_platformcommand($ptchrel,$platform,$command)
							if ($BUILD_UNINSTTBLE_ONLY == 0);
	          &save_prevlineinf($ptchrel,$platform,$command);
		  my ($newcmd)=join("|",$ptchrel,$platform,$command);
		  push(@UNINSTALL_PROC,$newcmd);
                  $CURRLINE++;				# increment line counter
	        }
	      elsif ($platform =~ /ANY_CA_EM/)
	        {
	           my ($cmd,$args,@info)=split(/\s+/, $command);
	           if ($PLTFORM =~ /STDBY_CA/)
		     {
			$platform = "STDBY_CA";
		        my (@pltfrms)=("CALL_AGT","FEAT_SAIN","FEAT_SPTC");
		        LOOPER:foreach my $tags (@pltfrms)
		          {
		            my ($cmnd2)=$command;
			    $cmnd2 =~ s/PLATFORMID/$CONFIG{$tags}/g;
			    if (($tags =~ /CALL_AGT/) && ($CONFIG{'STOP_CALLAGT'} == 0))
		              { next LOOPER; }
			    if (($tags =~ /FEAT_SAIN/) && ($CONFIG{'STOP_FSAIN'} == 0))
		              { next LOOPER; }
			    if (($tags =~ /FEAT_SPTC/) && ($CONFIG{'STOP_FSPTC'} == 0))
		              { next LOOPER; }

		            my ($newcmd)=join("|",$ptchrel,$platform,$cmnd2);
		            $newcmd=~s/$CONFIG{'PTCHFLTAG'}\d+/$CONFIG{'PTCHFLTAG'}$CONFIG{'PTCHEND'}/g;

		            if ($args =~ /start/)
			      {
		                 push(@UNINSTALL_PROC,$newcmd);
	                         &save_prevlineinf($ptchrel,$platform,$command);
			      }
	                    &run_platformcommand($ptchrel,$platform,$cmnd2)
						 if ($BUILD_UNINSTTBLE_ONLY == 0);
	                    &save_prevlineinf($ptchrel,$platform,$command);
		            push(@UNINSTALL_PROC,$newcmd) if ($args =~ /stop/);
			  } # end for-each
		     } # PLTFORM=STDBY_CA
		   elsif ($PLTFORM =~ /STDBY_EM/)
		     {
			$platform = "STDBY_EM";
			$command =~ s/\-i\s+PLATFORMID/all/g;
		        my ($newcmd)=join("|",$ptchrel,$platform,$command);
		        $newcmd=~s/$CONFIG{'PTCHFLTAG'}\d+/$CONFIG{'PTCHFLTAG'}$CONFIG{'PTCHEND'}/g;

		        if ($args =~ /start/)
			  {
		             push(@UNINSTALL_PROC,$newcmd);
			  }
	                &run_platformcommand($ptchrel,$platform,$command)
						if ($BUILD_UNINSTTBLE_ONLY == 0);
	                &save_prevlineinf($ptchrel,$platform,$command);
		        push(@UNINSTALL_PROC,$newcmd) if ($args =~ /stop/);
		     }
	        } # platform is ANY_CA_EM
	      else
	        {
	           &save_prevlineinf($ptchrel,$platform,$command);
	           $CURRLINE++;
	        }
           }
        elsif ($command =~ /^cd/)
	  {
	    if ($platform =~ /$PLTFORM/)
	        {
		  my ($cmd);
		  ($cmd,$DIRPTH)=split(/\s+/,$command);
		  &run_cdcommand($ptchrel,$platform,$command)
							if ($BUILD_UNINSTTBLE_ONLY == 0);
		  push(@UNINSTALL_PROC, $postinst_entry);
	          &save_prevlineinf($ptchrel,$platform,$command);
                  $CURRLINE++;				# increment line counter
	        }
	    elsif (($platform =~ /PRI_EM/) || ($platform =~ /SEC_EM/))
	        {
		  my ($cmd);
		  ($cmd,$DIRPTH)=split(/\s+/,$command);
	          &run_command_2($ptchrel,$platform,$command)
							if ($BUILD_UNINSTTBLE_ONLY == 0);
	          &save_prevlineinf($ptchrel,$platform,$command);
		  push(@UNINSTALL_PROC, $postinst_entry);
                  $CURRLINE++;				# increment line counter
	        }
	    else
	      {
	        &save_prevlineinf($ptchrel,$platform,$command);
                $CURRLINE++;
	      }
	  }
        elsif ($command =~ /$CONFIG{'DAEMONMGR_SCR'}/)
	  {
	    if ($platform =~ /$PLTFORM/)
	        {
		  &run_daemonmgr_command($ptchrel,$platform,$command)
							if ($BUILD_UNINSTTBLE_ONLY == 0);
		  push(@UNINSTALL_PROC, $postinst_entry);
	          &save_prevlineinf($ptchrel,$platform,$command);
                  $CURRLINE++;				# increment line counter
	        }
	      else
	        {
	           &save_prevlineinf($ptchrel,$platform,$command);
	           $CURRLINE++;
	        }
	  }
         elsif ($command =~ /^date/)
           {
	      if ($platform =~ /ANY_CA_EM/)
	        {
	          $platform=$PLTFORM;
		}

	      if ($platform =~ /$PLTFORM/)
	        {
	          &run_datecommand($ptchrel,$platform,$command)
							if ($BUILD_UNINSTTBLE_ONLY == 0);
	          &save_prevlineinf($ptchrel,$platform,$command);
                  $CURRLINE++;				# increment line counter
	        } # platforms are the same
	      elsif (($platform =~ /PRI_EM/) || ($platform =~ /SEC_EM/))
	        {
	          &run_command_2($ptchrel,$platform,$command)
							if ($BUILD_UNINSTTBLE_ONLY == 0);
	          &save_prevlineinf($ptchrel,$platform,$command);
                  $CURRLINE++;				# increment line counter
	        }
	      else
	        {
	           &save_prevlineinf($ptchrel,$platform,$command);
	           $CURRLINE++;
	        }
           }
         elsif ($command =~ /^wait/)
           {
	      if ($platform =~ /$PLTFORM/)
	        {
	          #if (($prevplatfrm eq $platform) && ($prevcmnd !~ /wait/))
		  #  {
	              &run_waitcommand($ptchrel,$platform,$command)
							if ($BUILD_UNINSTTBLE_ONLY == 0);
		      push(@UNINSTALL_PROC, $postinst_entry);
		  #  }
                  $CURRLINE++;				# increment line counter
	          &save_prevlineinf($ptchrel,$platform,$command);
	        }
	      else
	        {
	           &save_prevlineinf($ptchrel,$platform,$command);
	           $CURRLINE++;
	        }
           }
         elsif ($command =~ /^pkill/)
           {
	      if ($platform =~ /$PLTFORM/)
	        {
	          &run_pkillcommand($ptchrel,$platform,$command)
							if ($BUILD_UNINSTTBLE_ONLY == 0);
	          &save_prevlineinf($ptchrel,$platform,$command);
		  push(@UNINSTALL_PROC, $postinst_entry);
                  $CURRLINE++;				# increment line counter
	        }
	      else
	        {
	           &save_prevlineinf($ptchrel,$platform,$command);
	           $CURRLINE++;
	        }
           }
         elsif (($command =~ /^\\rm/) || ($command =~ /^rm/))
           {
	      if ($platform =~ /$PLTFORM/)
	        {
	          # process the rm command
	          $command =~ s/\\//g;
	          my ($cmnd,$argopt)=split(/\s+/, $command);
	          $argopt = "$DIRPTH/$argopt";
	          $command=join(" ", $cmnd, $argopt);

	          &run_rmcommand($ptchrel,$platform,$command)
							if ($BUILD_UNINSTTBLE_ONLY == 0);
	          &save_prevlineinf($ptchrel,$platform,$command);
		  push(@UNINSTALL_PROC, $postinst_entry);
                  $CURRLINE++;				# increment line counter
	        }
	      else
	        {
	           &save_prevlineinf($ptchrel,$platform,$command);
	           $CURRLINE++;
	        }
           }
      } # end for-loop

    if ($BUILD_UNINSTTBLE_ONLY == 0)
      {
         &Print_Msg("------------------------------------------------------------\n");
         &Print_Msg("Install/Upgrade completed at: " . localtime() . "\n");
      }
    else
      {
	print "\nCompleted build of uninstall sequence table ... \n";
      }

    close(INSTLOG);
    if (! -f "$CONFIG{'UNINSTALL_CFILE'}")
      {
         print "\nCreating the uninstall commands file: $CONFIG{'UNINSTALL_CFILE'} ... \n";
         open(UNINSTCMDS_FILE,">$CONFIG{'UNINSTALL_CFILE'}") ||
		die("ERROR: Could not open $CONFIG{'UNINSTALL_CFILE'} for create!!\n\n");
	 select(UNINSTCMDS_FILE);	$|=1;
	 select(STDOUT);
         print "\nWriting to uninstall commands file ... ";
	 foreach my $uninstentry (@UNINSTALL_PROC)
	   {
	      print UNINSTCMDS_FILE "$uninstentry\n";
	   }
         print "Done\n\n";
	 close(UNINSTCMDS_FILE);

	 # remove the empty log file
	 `\\/bin/rm $INSTALL_LOG` if ($BUILD_UNINSTTBLE_ONLY == 1)
      }
} # end function


sub rev_cpcommand
{
  my ($incommand)=@_;
  my ($cmd,$opts,@args);
  my ($cmnd2);
  
  if ($incommand =~ /\-p/)
    {
       ($cmd,$opts,@args)=split(/\s+/, $incommand);
    }
  else
    {
       ($cmd,@args)=split(/\s+/, $incommand);
    }
  (@args)=reverse(@args);
  if (length($opts) != 0)
    {
	$cmnd2=join(" ",$cmd,$opts,@args);
    }
  else
    {
        $cmnd2=join(" ",$cmd,@args);
    }
  return($cmnd2);
} # end sub


sub save_prevlineinf
{
   my ($a, $b, $c)=@_;

   $prevptch=$a;
   $prevplatfrm=$b;
   $prevcmnd=$c;
} # end function


sub process_cpcommand
{
  my ($incommand,
	$dirpath)=@_;
  my ($outcommand)="";
  my ($cmnd,@args)=split(/\s+/,$incommand);

  goto CASEFOR_MDOANDSO if ($incommand =~ /\*\.mdo/);
  goto CASEFOR_MDOANDSO if ($incommand =~ /\*\.so/);
  for (my $idx=0; $idx < scalar(@args); $idx++)
     {
       if ($args[$idx] !~ /\-p/)
         {
	   if ($args[$idx] !~ /$CONFIG{'PTCHFLTAG'}/)
	     {
	       if ($args[$idx] !~ /PatchLevel/)
	         {
		    if ($args[$idx] !~ /ems\/utils/)
		      {
			if ($args[$idx] !~ /^$dirpath/)
		          {
	            	    $args[$idx]="$dirpath/$args[$idx]";
		          }
		      }
		    else
		      {
			$args[$idx].="/PatchLevel";
		      } 
	         } # does not contain 'PatchLevel'
	     } # does not contain patch tag
	 } # not -p option
     } # end loop
   goto FINAL_CPSTEPS;

CASEFOR_MDOANDSO:
  for (my $idx=0; $idx < scalar(@args); $idx++)
    {
	next if ($args[$idx] =~ /\-p/);
	$args[$idx]="$dirpath/$args[$idx]";
    }
  $MKDIRSET=0 if ($incommand =~ /\*\.so/);

FINAL_CPSTEPS:
  $outcommand=join(" ",$cmnd,@args);
  return($outcommand);
} # end sub


sub Print_Msg
{
  my ( $msg )=@_;

  print $msg;
  print INSTLOG $msg;
} # end function


sub Running_prompt
{
  my (	$pltfrm,
	$cmndline,
	$srvrnme)=@_;

  &Print_Msg("\nRunning command on $CONFIG{$srvrnme} ($pltfrm):\n\t#> $cmndline\n");
  &Print_Msg("Result:\n\t");
} # end function


sub ShowError_Msg
{
  my (  $pltfrm,
	$cmndline,
	$srvrnme,
	$errval)=@_;

  if ($errval != 0)
    {
       &Print_Msg("\tProblem running $cmndline on $CONFIG{$srvrnme} ($pltfrm)!!\n");
       &Print_Msg("\tInstall/Uninstall aborted!!\n\n");

       # create cache file on error
       write_CACHEFILE($CACHEFILE,$SECTOR . "_" . $CURRLINE);

       &Enable_interrupts();		# enable interrupts
       exit 1;
    }
  &Print_Msg("'$cmndline' successfully executed\n");
} # end function


sub Prompt_PressReturn
{
  &Print_Msg("\n\tPress <RETURN> to continue.\n");
  my $xyz=<>;
} # end function


sub run_mkdircommand
{
  my (	$ptchnum,
	$pltfrm,
	$cmndline)=@_;
  my ($cmd,@argopt)=split(/\s+/, $cmndline);
  my ($argstr);

  &Running_prompt($pltfrm,$cmndline,"SRVRNAME");
  foreach my $arg (@argopt)
    {
       $argstr.=" " . $arg;
    }

  `/bin/$cmd $argstr`;
  &ShowError_Msg($pltfrm,$cmndline,"SRVRNAME",$?);
} # end function


sub run_chowncommand
{
  my (	$ptchnum,
	$pltfrm,
	$cmndline)=@_;
  my ($cmd,@argopt)=split(/\s+/, $cmndline);
  my ($argstr);

  &Running_prompt($pltfrm,$cmndline,"SRVRNAME");
  foreach my $arg (@argopt)
    {
       $argstr.=" " . $arg;
    }

  `/bin/$cmd $argstr`;
  &ShowError_Msg($pltfrm,$cmndline,"SRVRNAME",$?);
} # end function


sub run_chmodcommand
{
  my (	$ptchnum,
	$pltfrm,
	$cmndline)=@_;
  my ($cmd,@argopt)=split(/\s+/, $cmndline);
  my ($argstr);

  &Running_prompt($pltfrm,$cmndline,"SRVRNAME");
  foreach my $arg (@argopt)
    {
       $argstr.=" " . $arg;
    }

  `/bin/$cmd $argstr`;
  &ShowError_Msg($pltfrm,$cmndline,"SRVRNAME",$?);
} # end function


sub run_sucommandset
{
  my ( $ptchnum,
	$pltfrm,
	$usrprompt,
	@CLICMDS)=@_;
  my (@cmdargs);
  my ($shellprg)="/bin/ksh";

  &Print_Msg("These set of lines will be need to be run in the shell session below ($THISSRVR).\n");
  foreach my $entry (@CLICMDS)
    {
       &Print_Msg("\t$entry\n");
    }

  &Print_Msg("\nOnce you have completed the above task, type <exit> for the oracle and the shell session to continue.\n");
  &Print_Msg("Opennig a shell session.\n");
  push (@cmdargs, $shellprg);
  system(@cmdargs);

  &Print_Msg("\nControl returned to <$SCRNAME>\n\n");
} # end sub


sub run_performtest_cmds
{
  my (	$ptchnum,
	$pltfrm,
	$cmndline,
	@CLICMDS)= @_;
  my ($currsrvr);
  my ($srvrip);
  my ($rem_srvrip);
  my ($cmd,$cmd2)=split(/\s+/, $cmndline);
  my ($scrtorun)=$CLICMDS[0];
  my ($checkscr)="$CONFIG{'MOP_BASEDIR'}/scripts/Platform_CmdDone";
  my ($checkcmd)="$checkscr $CONFIG{'RADIUSUSER'} USERPASSWD REM_SRVRIP";

  if ($PLTFORM =~ /STDBY_EM/)
    {
	if ($CONFIG{'SRVRNAME'} =~ /$CONFIG{'SECEM_NAME'}/i)
	  {
	    $currsrvr="PRIEM_NAME";
	    $srvrip="PRIEM_IP";
	    $rem_srvrip="SECCA_IP";
	  }
	elsif ($CONFIG{'SRVRNAME'} =~ /$CONFIG{'PRIEM_NAME'}/i)
	  {
	    $currsrvr="SECEM_NAME";
	    $srvrip="SECEM_IP";
	    $rem_srvrip="PRICA_IP";
	  }
    }

  $checkcmd=~s/USERPASSWD/&get_ActualUsrPw($CONFIG{'USERPASSWD'})/g;
  $checkcmd=~s/REM_SRVRIP/$CONFIG{$rem_srvrip}/g;

  &Print_Msg("NOTE: Make sure the startup of the CA has completed fully \n");
  &Print_Msg("      before proceeding with the switchover.\n\n");

  &Print_Msg("This command is to be run on ACTIVE EM-> " .
		$CONFIG{$currsrvr} . " (" . $CONFIG{$srvrip} . ")\n");
  &Print_Msg("Copy the command and paste in the ACTIVE EM's console window.\n");
  &Print_Msg("\n\t#> bin/" . $scrtorun . "\n\n");

  &Print_Msg("\t\tPress <ENTER> to continue.\n");
  my $xyz=<>; 

  &Print_Msg("Perform Test calls\n");
  &Print_Msg("\nTest Cases:\n");
  &Print_Msg("\tTest Procedure                               Expected Results\n");
  &Print_Msg("\t------------------------------------------------------------------------------------\n");
  &Print_Msg("\t1. Subscriber A calls Subscriber B          1. Call goes through and receive ring   \n");
  &Print_Msg("\t   (ON-NET -> ON-NET)\n");
  &Print_Msg("\t------------------------------------------------------------------------------------\n");
  &Print_Msg("\t2. Subscriber A calls Subscriber C          2. Call goes through and receive ring   \n");
  &Print_Msg("\t   (ON-NET -> OFF-NET)\n");
  &Print_Msg("\t------------------------------------------------------------------------------------\n");
  &Print_Msg("\t3. Subscriber C calls Subscriber A          3. Call goes through and receive ring   \n");
  &Print_Msg("\t   (OFF-NET -> ON-NET)\n");
  &Print_Msg("\t------------------------------------------------------------------------------------\n\n");

  print "\n\tPress <Enter> to continue after completing the tests.\n";
  my $xyz=<>;
  # check the second part of the cmdline
  if ($cmd2 =~ /wait/i)
    {
	$cmd2 =~ s/Wait/wait/g;
	$cmd2 =~ s/_/ /g;
        &run_waitcommand($ptchnum,"STDBY_EM",$cmd2);
    }
} # end function


sub run_pkillcommand
{
  my (	$ptchnum,
	$pltfrm,
	$cmndline)= @_;
  my ($cmd,$argopt)=split(/\s+/, $cmndline);

  &Running_prompt($pltfrm,$cmndline,"SRVRNAME");

  $argopt="-z" if ($TESTRUN == 1);

  `/bin/$cmd $argopt`; 		# test case
  &ShowError_Msg($pltfrm,$cmndline,"SRVRNAME",$?);
} # end function


sub run_waitcommand
{
  my (	$ptchnum,
	$pltfrm,
	$cmndline)= @_;

  my ($cmd,$argopt)=split(/\s+/, $cmndline);

  &Running_prompt($pltfrm,$cmndline,"SRVRNAME");

  for(my $idx=0; $idx < $argopt; $idx++)
    {
       &Print_Msg(".");
       `/bin/sleep 60`;		# sleep for 60 secs
    }

  &Print_Msg("\n\n");
} # end function


sub run_platformcommand
{
  my (	$ptchnum,
	$pltfrm,
	$cmndline)= @_;
  my ($cmd,@argopt)=split(/\s+/, $cmndline);
  my ($argstr);
  my ($action);

  &Print_Msg("\nThis command may take approx 5+ min to complete");
  &Running_prompt($pltfrm,$cmndline,"SRVRNAME");
  foreach my $opts (@argopt)
    {
	$argstr .= " ".$opts;
    }
  
  $argstr="-h" if ($TESTRUN == 1);	
  $action="start" if ($cmndline =~ /start/);
  $action="stop" if ($cmndline =~ /stop/);

  # create a mini shell script
  my ($ksh_miniscr);
  my ($ksh_scrfile)="/tmp/kshMiniScr.sh";
  my ($ksh_outfile)="/tmp/platform.out";

  $ksh_miniscr="#!/bin/ksh\n\nBINDIR=\"/bin\"\n";
  $ksh_miniscr.="\${BINDIR}/$cmd $argstr > $ksh_outfile &\n\n";
  open(MINISCR,"> $ksh_scrfile");
  print MINISCR $ksh_miniscr;
  close(MINISCR);
  `/bin/chmod 755 $ksh_scrfile`;
  `$ksh_scrfile`;
  `\\/bin/rm -rf $ksh_scrfile`;		# remove tmp script after executing
  
  my ($proccnt)=`/bin/ps -ef|/bin/grep platform|/bin/grep -v grep|/bin/wc -l|/bin/awk '{print $1}'`;
  my $strttime=time();
  chomp($proccnt);
  while($proccnt != 0)
    {
       &Print_Msg(".");
       sleep 5;
       $proccnt=`/bin/ps -ef|/bin/grep platform|/bin/grep -v grep|/bin/wc -l|/bin/awk '{print $1}'`;
       chomp($proccnt);
    }
  my $endtime=time();
  my $calctime=$endtime-$strttime;
  my $secnds="$calctime secs";

  if ($calctime > 60)
    {
	$calctime=$calctime / 60;
        my ($min,$secs)=split(/\./, $calctime);
        $secs=($secs%60) if ($secs > 60);
        $calctime="$min.$secs mins";
    }
  else
    {
	$calctime.=" secs";
	$secnds="<--";
    }

  my (@cmdresult)=split(/\n/, `/bin/cat $ksh_outfile`);
  foreach my $line (@cmdresult)
    {
	&Print_Msg("\t$line\n");
    }
  `\\/bin/rm -rf $ksh_outfile`;

  &Print_Msg("\n");
  &Print_Msg("NOTE: It actually took about " . $calctime . " (" . $secnds . 
						") to <" . $action . "> this platform.\n\n");
  &Prompt_PressReturn();
} # end function


sub run_rmcommand
{
  my (	$ptchnum,
	$pltfrm,
	$cmndline)= @_;
  my ($cmd,$argopt)=split(/\s+/, $cmndline);

  &Running_prompt($pltfrm,$cmndline,"SRVRNAME");
  $argopt="/tmp/*.log" if ($TESTRUN == 1);	

  `\\/bin/$cmd $argopt`;
  &ShowError_Msg($pltfrm,$cmndline,"SRVRNAME",$?)
			if ($TESTRUN == 0);
} # end function


sub run_datecommand
{
  my (	$ptchnum,
	$pltfrm,
	$cmndline)= @_;
  my ($mysysargs);
  my ($cmd,@argopt)=split(/\s+/, $cmndline);

  &Running_prompt($pltfrm,$cmndline,"SRVRNAME");
  foreach my $arg (@argopt)
    {
       $mysysargs.=join(" ", $arg);
    }

  $mysysargs = ">> /tmp/xyz" if ($TESTRUN == 1);
  `/bin/$cmd $mysysargs`;

  &ShowError_Msg($pltfrm,$cmndline,"SRVRNAME",$?)
				if ($TESTRUN == 0);
} # end function


sub run_daemonmgr_command
{
  my (	$ptchnum,
	$pltfrm,
	$cmndline)= @_;
  my ($cmd, @args)=split(/\s+/, $cmndline);
  my ($argopts)=join(" ",@args);

  &Running_prompt($pltfrm,$cmndline,"SRVRNAME");

  $argopts="" if ($TESTRUN == 1);
  `$cmd $argopts`;		# run the command

  &ShowError_Msg($pltfrm,$cmndline,"SRVRNAME",$?)
				if ($TESTRUN == 0);
} # end sub


sub run_cpcommand
{
  my (	$ptchnum,
	$pltfrm,
	$cmndline)= @_;
  my ($jnk,$opt,$arg1,$arg2);

  my ($cmd,@argopt)=split(/\s+/, $cmndline);
  if ($argopt[0] =~ /^\-p/)
    {
      ($jnk,$opt,$arg1,$arg2)=split(/\s+/, $cmndline);
    }
  else
    {
      ($jnk,$arg1,$arg2)=split(/\s+/, $cmndline);
    }

  &Running_prompt($pltfrm,$cmndline,"SRVRNAME");
  
  if ($TESTRUN == 1)
    {
      $arg2="/dev/null";
    }

  if ($argopt[0] =~ /^\-p/)
    { `/bin/$cmd $opt $arg1 $arg2`; }
  else
    { `/bin/$cmd $arg1 $arg2`; }

  &ShowError_Msg($pltfrm,$cmndline,"SRVRNAME",$?)
					if ($TESTRUN == 0);
} # end function


sub run_cdcommand
{
  my (	$ptchnum,
	$pltfrm,
	$cmndline	)=@_;
  my ($cmnd,$argopt)=split(/\s+/, $cmndline);

  &Running_prompt($pltfrm,$cmndline,"SRVRNAME");
  `/bin/$cmnd $argopt`;

  &ShowError_Msg($pltfrm,$cmndline,"SRVRNAME",$?);
} # end function


sub run_command_2
{
  my (	$ptchnum,
	$pltfrm,
	$cmndline	)=@_;
  my ($pltfrm_name,$pltfrm_ip);
  my ($cmnd,$argopt)=split(/\s+/, $cmndline);

  $pltfrm_name = $CONFIG{'PRIEM_NAME'} if ($pltfrm =~ /PRI_EM/);
  $pltfrm_ip = $CONFIG{'PRIEM_IP'} if ($pltfrm =~ /PRI_EM/);
  $pltfrm_name = $CONFIG{'SECEM_NAME'} if ($pltfrm =~ /SEC_EM/);
  $pltfrm_ip = $CONFIG{'SECEM_IP'} if ($pltfrm =~ /SEC_EM/);

  &Print_Msg("\nRun command on $pltfrm_name ($pltfrm_ip):\n\t#> $cmndline\n");
  &Prompt_PressReturn();
} # end function


sub run_nodestatcmd
{
  my (	$ptchnum,
	$pltfrm,
	$cmndline	)=@_;

  &Running_prompt($pltfrm,$cmndline,"SRVRNAME");
  my (@cmndresult)=split(/\n/, `/bin/$cmndline`);
  foreach my $line (@cmndresult)
    {
	&Print_Msg("\t$line\n");
    }
  &Prompt_PressReturn();
} # end function


sub run_nodestat_local
{
  my ($mode,$srvrstate)=@_;
  my ($junk);
  my ($levchk);
  my ($presplev);
  
  if ($mode =~ /Upgrade/i)
    {
      $levchk=$CONFIG{'CURRPLEV'};
    }
  else
    {
      $levchk=$CONFIG{'PTCHEND'};
    }


  print "Gathering information from the nodestat command ... ";
  `/bin/nodestat > /tmp/nodestat.info`;
  print "Done\n";

  if ($srvrstate =~ /STANDBY/i)
    {
       print "\nChecking current patch level for switch ... ";
       $presplev=`/bin/cat /tmp/nodestat.info | /bin/grep "$CONFIG{'PTCHFLTAG'}"`;
       chomp($presplev);
       ($junk,$presplev)=split(/:/, $presplev);
       ($junk,$presplev)=split(/P/, $presplev);
  
       if ($presplev ne $levchk)
         {
            print "\nERROR: BTS Switch not at the prescribed patch level to do <$mode>\n";
            print "       Prescribed patch level ($levchk) < != > Switch patch level ($presplev)\n";
            print "       -- ABORTING --\n\n";
            exit 1;
         }
       else
         {
            print "$presplev\n\n";
         }

       # added 10/11/2006 - check if the previous patch level has been installed
       if ($mode =~ /Upgrade/)
         {
           print "\nChecking version of patch to be installed ... ";
           if (($CONFIG{'PTCHSTRT'}-1) != $CONFIG{'CURRPLEV'})
             {
                print "\nERROR: BTS Switch not at the prescribed patch level to do <$mode> to P$CONFIG{'PTCHSTRT'}\n";
                print "       Switch patch level ($presplev) < != > Prescribed switch patch level (" . 
								($CONFIG{'PTCHSTRT'}-1) . ")\n";
                print "       -- ABORTING --\n\n";
                exit 1;
	     }
	   else
	     {
               print "Ok.\n\n";
	     }
         } # check that prev lev if we are in install mode
    } # end state is STANDBY

    # check switch operation state
    if ($CONFIG{'NODEINFO'} !~ /EM/i)
      {
            print "\nChecking current state of the switch for $CONFIG{'CALL_AGT'}|";
            print "$CONFIG{'FEAT_SAIN'}|$CONFIG{'FEAT_SPTC'} ... ";
            my ($caagt_state)=`/bin/cat /tmp/nodestat.info | /bin/grep "$CONFIG{'CALL_AGT'}"`; 
            my ($fsain_state)=`/bin/cat /tmp/nodestat.info | /bin/grep "$CONFIG{'FEAT_SAIN'}"`; 
            my ($fsptc_state)=`/bin/cat /tmp/nodestat.info | /bin/grep "$CONFIG{'FEAT_SPTC'}"`; 
            chomp($caagt_state); $caagt_state =~ s/\s+//g;
            chomp($fsain_state); $fsain_state =~ s/\s+//g;
            chomp($fsptc_state); $fsptc_state =~ s/\s+//g;
            ($junk,$caagt_state)=split(/:/, $caagt_state);
            ($junk,$fsain_state)=split(/:/, $fsain_state);
            ($junk,$fsptc_state)=split(/:/, $fsptc_state);
            ($caagt_state,$junk)=split(/\|/, $caagt_state);
            ($fsain_state,$junk)=split(/\|/, $fsain_state);
            ($fsptc_state,$junk)=split(/\|/, $fsptc_state);

            if ($caagt_state ne "STANDBY")
	      {
                &error_switchstate($mode,$caagt_state,"STANDBY");
	      }
            if ($fsain_state ne "STANDBY")
	      {
                &error_switchstate($mode,$fsain_state,"STANDBY");
	      }
            if ($fsptc_state ne "STANDBY")
	      {
                &error_switchstate($mode,$fsptc_state,"STANDBY");
	      }
            print "STANDBY\n\n";
         } # node info not EM
       else
         {
	    if ($srvrstate =~ /STANDBY/i)
	      {
		if (($mode =~ /update/i) || ($mode =~ /revert/i))
	          {
		     &error_switchstate($mode,"STANDBY","ACTIVE");
	          }
                print "\nChecking current state of the switch for $CONFIG{'EMS_AGT'}|";
                print "$CONFIG{'BDMS_AGT'} ... ";
                my ($emsagt_state)=`/bin/cat /tmp/nodestat.info | /bin/grep "$CONFIG{'EMS_AGT'}"`; 
                my ($bdmagt_state)=`/bin/cat /tmp/nodestat.info | /bin/grep "$CONFIG{'BDMS_AGT'}"`; 
                chomp($emsagt_state); $emsagt_state =~ s/\s+//g;
                chomp($bdmagt_state); $bdmagt_state =~ s/\s+//g;
                ($junk,$emsagt_state)=split(/:/, $emsagt_state);
                ($junk,$bdmagt_state)=split(/:/, $bdmagt_state);
                ($emsagt_state,$junk)=split(/\|/, $emsagt_state);
                ($bdmagt_state,$junk)=split(/\|/, $bdmagt_state);
                if ($emsagt_state ne "STANDBY")
	          {
                    &error_switchstate($mode,$emsagt_state,"STANDBY");
	          }
                if ($bdmagt_state ne "STANDBY")
	          {
                    &error_switchstate($mode,$bdmagt_state,"STANDBY");
	          }
                print "STANDBY\n\n";
	      }
	    else
	      {
		print "Current state for $CONFIG{'EMS_AGT'}|$CONFIG{'BDMS_AGT'} ... ";
                my ($emsagt_state)=`/bin/cat /tmp/nodestat.info | /bin/grep "$CONFIG{'EMS_AGT'}"`; 
                my ($bdmagt_state)=`/bin/cat /tmp/nodestat.info | /bin/grep "$CONFIG{'BDMS_AGT'}"`; 
                chomp($emsagt_state); $emsagt_state =~ s/\s+//g;
                chomp($bdmagt_state); $bdmagt_state =~ s/\s+//g;
                ($junk,$emsagt_state)=split(/:/, $emsagt_state);
                ($junk,$bdmagt_state)=split(/:/, $bdmagt_state);
                ($emsagt_state,$junk)=split(/\|/, $emsagt_state);
                ($bdmagt_state,$junk)=split(/\|/, $bdmagt_state);
                if ($emsagt_state ne "ACTIVE")
	          {
                    &error_switchstate($mode,$emsagt_state,"ACTIVE");
	          }
                if ($bdmagt_state ne "ACTIVE")
	          {
                    &error_switchstate($mode,$bdmagt_state,"ACTIVE");
	          }
                print "ACTIVE\n\n";
	      }
         } # node info is EM

  # remove the temporary nodestat result file
  `\/bin/rm -rf /tmp/nodestat.info`;
} # end function


sub error_switchstate
{
   my ($mode,$currstate,$prescribed)=@_;

   print "\nERROR: BTS Switch is not in the prescribed state to proceed with <$mode>\n";
   print "       Prescribed state ($prescribed) < != > Switch state ($currstate)!!\n";
   print "       -- ABORTING --\n\n";
   exit 1;
}  # end sub


sub readconfig
{
   open (CNFFILE,"$CFGFILE") || 
	die ("\nERROR: Could not open config file!!\n       Run the bin/Make_SiteConfig first\n\n");
   while(<CNFFILE>)
     {
       chomp;
       next if /^#+/;
       next if (length($_) == 0);

       # if other than comment or blank line, add to config hash
       my ($key,$value)=split(/\s+/);
       $CONFIG{$key}=$value;
     }
   close(CNFFILE);
} # end function


sub read_PWDFILE
{
   my ($PWDFILE)="$CONFIG{'MOP_BASEDIR'}/$CONFIG{'RUNTIME_DATA'}/$CONFIG{'CODEDPWD'}";

   open(PWDFILE,"$PWDFILE") || die("\nERROR: Could not open PWD file!!\n\n");
   while(<PWDFILE>)
     {
	chomp;
	my ($key,$value)=split(/\s+/, $_);
	$PWDTABLE{$key}=$value;
     }
   close(PWDFILE);
} # end function


sub get_ActualUsrPw
{
  my ($inlookup)=@_;

  return($PWDTABLE{$inlookup});
} # end function


sub read_CLIAttrVals
{
    my ($CLIDBFILE)="$CONFIG{'MOP_BASEDIR'}/$CONFIG{'CLICFGFILE'}";
    open(CNFFILE,"$CLIDBFILE") ||
	die("\nERROR: Could not open the CLI attribute table!!\n       Run the bin/Create_CLIConfig first\n\n");
   while(<CNFFILE>)
     {
       chomp;
       next if /^#+/;
       next if (length($_) == 0);

       # if other than comment or blank line, add to config hash
       my ($key,$value)=split(/\s+/);
       $CONFIG{$key}=$value;
     }
   close(CNFFILE);
} # end sub


sub read_CACHEDLINE
{
  my ($incachefile)=@_;

  if ( -f "$incachefile")
    {
       open(READCACHE,"$incachefile");
       $LINECOUNT=<READCACHE>;
       chomp($LINECOUNT);
       close(READCACHE);

       ($SECTOR,$LINECOUNT)=split(/_/, $LINECOUNT);
       # remove the cache file
       `\\/bin/rm -rf $incachefile`;

       # read in post install/uninstall table
       &read_POSTACTTABLE();

       $CONTINUETASKS=1;
    } # if file exists, read it in
} # end sub


sub read_POSTACTTABLE
{
   open(READ_POST,"$POSTACTFILE") ||
	die("ERROR: Could not read cached post install/uninstall tasks!!\n\n");
   while(<READ_POST>)
     {
	chomp;
	push(@POSTACTION_TASKS, $_);
     } # end while
   close(READ_POST);

   `\\/bin/rm -rf $POSTACTFILE`;
} # end sub


sub write_POSTACTTABLE
{
   open(WRITE_POST,">$POSTACTFILE") ||
	die("ERROR: Could not create cache file for install/uninstall tasks!!\n\n");
   foreach my $items (@POSTACTION_TASKS)
     {
	print WRITE_POST "$items\n"; 
     } # end for-loop
   close(WRITE_POST);
} # end sub


sub write_CACHEFILE
{
  my ($incachefile, $errline)=@_;

  open(WRITECACHE,">$incachefile") ||
	die("\tERROR: Could not create cache file for resume operation!!\n\n");
  print WRITECACHE "$errline\n";
  close(WRITECACHE);

  &write_POSTACTTABLE();
} # end function


sub get_change_values
{
  my ($srchitm)=@_;

  for my $key (keys %CONFIG)
    {
	if ($key =~ /^$srchitm/i)
	  {
	     push(@CHANGETABLE, $key);
	  }
    } # end loop
} # end sub


sub checkExp_retresult
{
  my ($lookfor,@retaray)=@_;

  foreach my $arayentry (@retaray)
    {
      if ($arayentry =~ /$lookfor/)
        {
	   return(0);
        }
    } # end loop
  return(-1); # if match was not found
} # end sub


sub checkCLI_retresult
{
   my (@retaray)=@_;

   foreach my $arayentry (@retaray)
     {
	if ($arayentry =~ /^Reply\s+:\s+Success:/)
          {
	     return(0);
          }
     } # end loop
   return(-1);  # if no match was found
} # end function


sub get_changedvals
{
  my (@resaray)=@_;
  my ($infostr);

  foreach my $entry (@resaray)
    {
	$entry =~ s/\cM//g;
	$infostr=$entry . "\n\t\t" if ($entry =~ /^TABLE_NAME/);
	$infostr.=$entry . "\n" if ($entry =~ /^MAX_RECORD/);
    }
  return($infostr);
} # end sub
