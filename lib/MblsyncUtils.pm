package MblsyncUtils::MblsyncUtils;

use strict;
use warnings;
use File::Find;

use Exporter qw(import);


#### Set flags for OS version, win or mac.
our $macOS;
our $MSwin;
my @osList;

{
	if ($^O =~ /darwin/i) {
		$macOS = 1;
		push @osList, "darwin";
	}

	if ($^O =~ /MSWin32/i) {
		$MSwin=1;
		push @osList, "MSWin32";
	}

	## Make sure we don't have more than one OS defined
	if (scalar @osList > 1) {
		die "ERROR: Cannot define more than one OS. $!";
	}
}




## $homeDirectory is the per user home.
our $homeDirectory = "/usr/home/rando";

if ($macOS) {
	$homeDirectory = "$ENV{'HOME'}";
}

if ($MSwin) {
	$homeDirectory = "$ENV{SYSTEMDRIVE}$ENV{HOMEPATH}";
}

## Make sure homeDirectory is defined and is a directory that is readable.
unless ($homeDirectory && -d $homeDirectory && -r $homeDirectory) {
	die "ERROR: homeDirectory is either not defined, not a directory or not readable.\n\$homeDirectory: [$homeDirectory] $!";
}

## Load config file (~/.mblsyncUtils/mblsyncUtils.conf)
our %configs;
loadConfig();

## Make sure sqlite3 is executable.
unless (-x $configs{'sqlite3'}) { die "ERROR: sqlite3 is not executable. Tried [$configs{'sqlite3'}] $!"; }

## Export some things.
our @EXPORT_OK = qw($macOS $MSwin $clearCommand $sqlite3 $homeDirectory $outputDirectory $loadConfig %configs getKeyValueFromPlist getLastModifiedFromBinaryPlist openFolder outputDirectoryRoot_user);



sub backupChooser {
	my @chosenBackup; ## This will ultimately be the iOS Backup we will use. 
	## Index 0 is the folder name (UID) 
	## Index 1 is the parent folder.  
	## Index 2 is the full path to backup.
	## Index 3 is the Device Name found in Info.plist file.
	## Index 4 is the raw mtime of the Info.plist file.
	## Index 5 is the formatted timestamp Info.plist mtime.
	
	our $iOSbackupRoot = $_[0]; ## If iOSbackupRoot is specified in config file then use that.
	our $iOSbackupRootDEFAULT = $iOSbackupRoot;
	
	#### Get list of iOS backup folders into iosBackups array.
	my @iosBackups; ## List of potential iOS Backup directories in iOSbackupRoot.

	{ ## Begin loop until a directory with at least one iOS backup is specified.
	
		## Allow user to override default and specify the iOS Backup root.
		print "\niOS Backup directory is:\n[$iOSbackupRoot]\n";
		print "Press enter to continue, CTL C to quit or specify path to iOS Backup folder:\n";
	
		my $iOSbackupRoot_userInput = <STDIN>;
		chomp $iOSbackupRoot_userInput;
		
		if ($iOSbackupRoot_userInput ne "") {
			$iOSbackupRoot = $iOSbackupRoot_userInput;

			if ($macOS) {
			
				print "\$iOSbackupRoot [$iOSbackupRoot]\n";
				## On macOS specific shell escaping issues:
				$iOSbackupRoot = macOSRemoveShellEscapes($iOSbackupRoot);
				
				## On macOS if dragging and dropping from finder to terminal, an extra space is added at end. Remove it.
				$iOSbackupRoot =~ s/ $//;
				print "\$iOSbackupRoot [$iOSbackupRoot]\n";
				#die;
	
				print "Looking for iOS backups in:\n[$iOSbackupRoot]\n\n";

			}
			
			
			unless (-d $iOSbackupRoot && -r $iOSbackupRoot) {
				print "That is not a readable directory!\n";
				sleep 2;
				$iOSbackupRoot = $iOSbackupRootDEFAULT;
				redo;
			}
			
			 
		}
		
		
		#### Check to see if user specified an individual backup.
	
		## Match 40 character unique id anywhere in string.
		if ($iOSbackupRoot =~ m/[0-9a-f]{40}/) { 
	
			## Look for Info.plist in subfolder	
			if (-e "$iOSbackupRoot/Info.plist")	{
			
				## Look for a key name Unique Identifier with a value that matches [0-9a-f]{40}
				my $uid = getKeyValueFromPlist("Unique Identifier", "$iOSbackupRoot/Info.plist" );
				my $device_name = getKeyValueFromPlist("Device Name", "$iOSbackupRoot/Info.plist" );
				my @stat = stat ("$iOSbackupRoot/Info.plist");
 				unless ($stat[9]) { warn "WARNING: Could not get mtime for $iOSbackupRoot/Info.plist"; }
				my $infoplistMtime = $stat[9];
#				print "uid [$uid] $device_name\n";die;

				if ($uid && $uid =~ m/^[0-9a-f]{40}$/ && $device_name) {
					$chosenBackup[0] = "$uid";  ## Just the uid
					$chosenBackup[1] = ""; ## Parent directory. (don't bother with this here)
					$chosenBackup[2] = "$iOSbackupRoot"; ## Full path to backup root
					$chosenBackup[3] = "$device_name"; ## Device name from info.plist
					$chosenBackup[4] = "$infoplistMtime"; ## raw Last mod time of Info.plist file
					$chosenBackup[5] = returnTimestamp($infoplistMtime); ## formatted Last mod time of Info.plist file
					return @chosenBackup;
	
				}
			}	
		}
		
		
		
		
		
		## Check to see if there is at least one iOS backup in $iOSbackupRoot.  Look for Info.plist in a UID directory.
		find (\&wanted, $iOSbackupRoot);

		#our $iOSbackupFound;
		our $seemsLikeValid_iosBackupsRoot = 0;

		sub wanted {
			if ($seemsLikeValid_iosBackupsRoot) {	
				$File::Find::prune = 1;
				return;
			}


			## If the file we are at is a directory and name looks like an iOS
			## backup UID directory name, then look for an Info.plist within  
			## the directory.  If Info.plist found then assume this directory  
			## is a valid ios Backup directory.
			if (-d $_ && $_ =~ /^[0-9a-f]{40}/i) {

				opendir (my $uidDirFH, $File::Find::name);
				while (my $fileInUIDdir = readdir $uidDirFH) {
					if ($fileInUIDdir eq "Info.plist") {
						$seemsLikeValid_iosBackupsRoot = $File::Find::dir;
						$iOSbackupRoot = $File::Find::dir;
						print "\$seemsLikeValid_iosBackupsRoot $seemsLikeValid_iosBackupsRoot\n";
					}
				}
			}	
		}

		
		print "Looking for iOS backups in:\n$iOSbackupRoot\n\n";
		

	
		opendir(iOSbackupRootFH, $iOSbackupRoot) or die "\n\nERROR: Can't open [$iOSbackupRoot]. $!";
	
		while (readdir iOSbackupRootFH ) {

			next if /^\./; ## Ignore files that begin with a '.'
			next unless (-d "$iOSbackupRoot/$_"); ## Ignore files that are not a directory.
			next unless (-r "$iOSbackupRoot/$_\/Info.plist");  ## Ignore directories that do not contain a readable Info.plist file.
			next unless (-s "$iOSbackupRoot/$_\/Info.plist");  ## Skip directories that have a zero size Info.plist
			next unless (-r "$iOSbackupRoot/$_\/Manifest.db"); ## Ignore directories that do not contain a readable Manifest.db file.
			push @iosBackups, $_;	
		}
		close iOSbackupRootFH;
	
		unless (scalar @iosBackups > 0) {
			print "NO BACKUPS FOUND in:[$iOSbackupRoot]\n";
			print "Reverting to default.\n\n";
			$iOSbackupRoot = $iOSbackupRootDEFAULT;
			print "redoing\n";
			redo;
		}
	} ## End loop until a directory with at least one iOS backup is found.

	

	#### Get a hash of backup directory names. Key is directory name, value is mtime.
	#### i.e $iosBackups{3da7aakbakjhetc} = 167193723;
	my %iosBackups;
	foreach my $dirName (@iosBackups) {
		my $UIDInfoPlist = "$iOSbackupRoot/$dirName/Info.plist";
		my @stat = stat ($UIDInfoPlist);
 			unless ($stat[9]) { 
			warn "WARNING: Could not get mtime for $UIDInfoPlist"; 
			$iosBackups{$dirName} = 1; 
			next;
		}
		$iosBackups{$dirName} = $stat[9];
	}


	#### Get a sorted by date of Info.plist list of iOS Backups. 
	my @keys_iosBackups = sort { $iosBackups{$a} <=> $iosBackups{$b} } keys(%iosBackups);
	my @vals_iosBackups = @iosBackups{@keys_iosBackups};


	#### Get Device Name and formatted Last Modified timestamp for each backup so as to be able to present to user.
	my %uid_DeviceName;
	my %uid_LastModified;
	foreach  my $UID (keys %iosBackups ) {
		#my $UID = $keys_iosBackups[$i];
		my $UIDInfoPlist = "$iOSbackupRoot/$UID/Info.plist";
		$uid_DeviceName{$UID} = getKeyValueFromPlist("Device Name", $UIDInfoPlist);
		$uid_LastModified{$UID} = returnTimestamp($iosBackups{$UID});
	}


	#### Present sorted list to user for backup directory selection (backupSelector).
	my $chosenBackupSelection;
	my $chosenBackupUID;

	## Begin Backup Selector loop
	{
		$chosenBackupSelection = 0;
		foreach  my $i (0 .. $#keys_iosBackups ) {
			my $UID = $keys_iosBackups[$i];
			print $i + 1 . ") [$uid_DeviceName{$UID}]";
			if ($i == $#keys_iosBackups) { print " (MOST RECENT)"; }
			print "\n\tUID: $UID\n\tLast Modified: $uid_LastModified{$UID}\n";

		}
		
		print "Press return to use the most recent backup " . scalar @keys_iosBackups . ") [" . $uid_DeviceName{$keys_iosBackups[scalar @keys_iosBackups-1]} . "] OR choose from the above list.\nEnter (1 to " . scalar @keys_iosBackups . ") or q to quit: " ;
		$chosenBackupSelection = <STDIN>;
		chomp $chosenBackupSelection;

		## If user entered q or quit then quit.
		$chosenBackupSelection = lc $chosenBackupSelection;
		if ($chosenBackupSelection eq "q" || $chosenBackupSelection eq "quit") {
			print "Exiting.\n";
			exit;
		}
		
		
		## If user pressed return without typing anything else, then assume wants mostRecentBackupUID
		if ($chosenBackupSelection eq "") {
			$chosenBackupSelection = scalar@vals_iosBackups;
			$chosenBackupUID = $keys_iosBackups[$#vals_iosBackups];
			#last backupSelector;
		}

		## If user entered invalid selection (out of range number) then redo, otherwise set $chosenBackupUID;
		if ($chosenBackupSelection =~ m/\D/ || $chosenBackupSelection < 1 || $chosenBackupSelection > $#keys_iosBackups+1 ) {
			print "Invalid selection ($chosenBackupSelection)\n";
			sleep 2; 
			redo;
		} else {
			$chosenBackupUID = $keys_iosBackups[$chosenBackupSelection-1];
		}
	}	
	## End Backup Selector loop


	$chosenBackup[0] = "$chosenBackupUID";  ## Just the uid
	$chosenBackup[1] = "$iOSbackupRoot"; ## Parent directory.
	$chosenBackup[2] = "$iOSbackupRoot/$chosenBackupUID"; ## Full path to backup root
	$chosenBackup[3] = "$uid_DeviceName{$chosenBackupUID}"; ## Device name from info.plist
	$chosenBackup[4] = "$iosBackups{$chosenBackupUID}"; ## raw Last mod time of Info.plist file
	$chosenBackup[5] = "$uid_LastModified{$chosenBackupUID}"; ## formatted Last mod time of Info.plist file
	return @chosenBackup;
}





sub returnTimestamp {
	## return a time value in the form yyyymmdd-hhmmss.txt

	my $timeValue = $_[0];
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime ($timeValue);
	
	$year += 1900;
	my $month = $mon+1;
	$month = sprintf("%02d",$month);
	my $day = sprintf("%02d",$mday);
	$hour = sprintf("%02d",$hour);
	$min = sprintf("%02d",$min);
	$sec = sprintf("%02d",$sec);
	return "$year$month$day-$hour$min$sec";

}



sub getKeyValueFromPlist {
	#### Retrieve the value of a key from Info.plist.  First try PlistBuddy.
	####  If PlistBuddy fails attempt to parse the file manually.

	my $keyName = $_[0];
	my $plistFile = $_[1];
	
	unless ($plistFile) { die "ERROR: No plistFile specified to getKeyValueFromPlist. $!"; }
	unless ($keyName)   { die "ERROR: No keyName specified to getKeyValueFromPlist. $!"; }
	unless (-r $plistFile) { warn "Could not read $plistFile $!"; }
	my $keyValue = "NOT FOUND";
	
	## Use PlistBuddy
	my $PlistBuddy = "/usr/libexec/PlistBuddy";
	if (-x $PlistBuddy) {
		my @PlistBuddyArgs;
		push @PlistBuddyArgs, "-c";
		#push @PlistBuddyArgs, "Print \\\$objects:1:LastModified";
		push @PlistBuddyArgs, "Print '$keyName'";
		push @PlistBuddyArgs, "$plistFile";
		open (my $plistBuddyFH, '-|', $PlistBuddy, @PlistBuddyArgs) or die "ERROR: Could not open the command $PlistBuddy $!";
		while (<$plistBuddyFH>){
			$keyValue = $_;
		}
		close ($plistBuddyFH) or die "ERROR: PlistBuddy failed with error [$?]\n plist file was [$plistFile] PlistBuddyArgs was [@PlistBuddyArgs] $!";
		chomp $keyValue;


		
		## If PlistBuddy executed without error then use then return the Device Name value.
		if ($? == 0) {
			return $keyValue;
		} 
	}
	

	
	
	## Attempt to parse the Info.plist file.
	my $loopFlag = 0;
	my $plistLine;
	
	unless (-r "$plistFile") {
		return "No Plist found or could not read [$plistFile]";
	}

	open (plistFH, "<", $plistFile);
	while (my $plistLine = <plistFH>) {
		chomp $plistLine;

		if ($loopFlag == 1) {
			$keyValue = $plistLine;
			last;
		}
		
		#print "PLISTLINE $plistLine\n";
		if ($plistLine =~ m/<key>$keyName<\/key>/i) { 
			$loopFlag = 1; 
		}
	}
	close plistFH;

	$keyValue =~ s/.*<string>//s;
	$keyValue =~ s/<\/string>.*//s;
#	$keyValue =~ s/.*<.+>//s;
#	$keyValue =~ s/<\/.+>.*//s;
	#$keyValue = "WHAT";
	return $keyValue;

}

sub getLastModifiedFromBinaryPlist {

	my $plistFile = $_[0];
	
	my $keyValue = "no date";
	#my $LastModified = `/usr/libexec/PlistBuddy -c "Print \\\$objects:1:LastModified" $plistFile`;


	## Use PlistBuddy
	my $PlistBuddy = "/usr/libexec/PlistBuddy";
	if (-x $PlistBuddy) {
		my @PlistBuddyArgs;
		push @PlistBuddyArgs, "-c";
		push @PlistBuddyArgs, "Print \\\$objects:1:LastModified";
		#push @PlistBuddyArgs, "Print '$keyName'";
		push @PlistBuddyArgs, "$plistFile";
		open (my $plistBuddyFH, '-|', $PlistBuddy, @PlistBuddyArgs) or die "ERROR: Could not open the command $PlistBuddy $!";
		while (<$plistBuddyFH>){
			$keyValue = $_;
		}
		close ($plistBuddyFH) or die "ERROR: PlistBuddy failed with error [$?]\n plist file was [$plistFile] PlistBuddyArgs was [@PlistBuddyArgs] $!";
		chomp $keyValue;


		
		## If PlistBuddy executed without error then use then return the Device Name value.
		if ($? == 0) {
			return $keyValue;
		} 
	}
	return $keyValue;	
}




sub loadConfig {
	
	#my $configDir = $_[0]; ## /config
	
	my $configDir = "$homeDirectory/.mblsyncUtils";
	my $userConfigFileName = "mblsyncUtils.conf";
	my $userConfigFile = "$configDir/$userConfigFileName";

	#my $fileToLoad = $defaultConfigFile;  ## Set this to default initially.  If we find a userConfigFile then use that.

	## Check to see if default config file exists, if not create it using defaults defined in writeDefaultConfig subroutine.
# 	unless (-e $defaultConfigFile) {
# 		writeDefaultConfig ($defaultConfigFile);
# 	}
	
	## Check to see if USER config file exists, if not create it using defaults defined in writeDefaultConfig subroutine.
	unless (-e $userConfigFile) {
		writeDefaultConfig ($configDir, $userConfigFileName, $userConfigFile);
	}
	


	## Now read in the config file, parse and load the variables.
	print "Loading config file [$userConfigFile]\n";
	open (my $configFH, "<", $userConfigFile) or die "ERROR: Could not open file for reading [$userConfigFile] $!";
		
		while  (my $configLine = <$configFH>) {
		chomp $configLine;
		next if ($configLine =~ /^#/); ## skip comment lines
		## $configLine =~ s/#.+//; ## ignore after comment NO LONGER USING as # may be contained in values.

#		next if ($configLine eq "\n"); ## ignore blank lines
		next if ($configLine !~ /\=/); ## ignore lines that do not contain =

#		print "[$configLine]\n";

		## Error out of no space after = sign in config file.
		unless ($configLine =~ /= /) { die "ERROR: Config file is bad.  Need space after equals sign. Please edit [$userConfigFile]. $!" };
		
		my ($var, $val) = split /= /,$configLine, 2;
		$var =~ s/\s//g;
		#print "var [$var], val [$val]\n";
		$configs{$var}=$val;
		
	}
	
	close $configFH or die "ERROR: Could not close [$userConfigFile] $!";
	
	## Add the config file location to the configs hash.
	$configs{'userConfigFile'} = $userConfigFile;


}

sub writeDefaultConfig {
	my $configDir = $_[0];
	my $userConfigFileName = $_[1];
	my $userConfigFile = $_[2];
	
	## Make sure config directory exitsts.
	unless (-d $configDir) {
		print "Will create $configDir.\n";
		mkdir "$configDir" or die "ERROR: Could not create directory [$configDir] $!";
	}
	
	if (-e $userConfigFile) { die "ERROR.  Will not overwrite [$userConfigFile] $!"; }
  	
	## Put the contents of the default config file into an array. 
	my @defaultConfigFileContents; ## Will write the contents of this array to a file on disk.
	
	push @defaultConfigFileContents, "## Lines beginning with a # are ignored.\n\n";

	## Mac version of config file.
	if ($macOS) {
		push @defaultConfigFileContents, "## sqlite3 client location";
		push @defaultConfigFileContents, "sqlite3         = /usr/bin/sqlite3";
		push @defaultConfigFileContents, "";
		push @defaultConfigFileContents, "## Clear Command. Used by the shell to clear the screen.";
		push @defaultConfigFileContents, "clearCommand	= clear";
		push @defaultConfigFileContents, "";
		push @defaultConfigFileContents, "## iOS Backups Root";
		push @defaultConfigFileContents, "iOSbackupRoot = $ENV{'HOME'}/Library/Application Support/MobileSync/Backup";
		push @defaultConfigFileContents, "";
		push @defaultConfigFileContents, "## Directory will write or copy files to.";
		push @defaultConfigFileContents, "outputDirectoryRoot = $homeDirectory/Desktop";

	}
		
	if ($MSwin) {
		push @defaultConfigFileContents, "## sqlite3 client location";
		push @defaultConfigFileContents, "sqlite3         = c:\\sqlite3\\sqlite3.exe";
		push @defaultConfigFileContents, "";
		push @defaultConfigFileContents, "## Clear Command. Used by the shell to clear the screen.";
		push @defaultConfigFileContents, "clearCommand	= cls";
		push @defaultConfigFileContents, "";
		push @defaultConfigFileContents, "## Output Location";
		push @defaultConfigFileContents, "outputDirectoryRoot = on win different directory";
		push @defaultConfigFileContents, "";
		push @defaultConfigFileContents, "## iOS Backups Root";
		push @defaultConfigFileContents, "iOSbackupRoot = $ENV{'APPDATA'}\\Apple Computer\\MobileSync\\Backup";	
		push @defaultConfigFileContents, "";
		push @defaultConfigFileContents, "## Directory will write or copy files to.";
		push @defaultConfigFileContents, "outputDirectoryRoot = $homeDirectory\\Desktop";

	}
	
	print "Writing [$userConfigFile]\n";
	open (my $dfltFH, ">>", $userConfigFile) or die "ERROR: Could not open filehandle [$userConfigFile] $!";	;
	
	foreach (@defaultConfigFileContents) {
		print $dfltFH $_ . "\n";
	}

	close ($dfltFH) or die "ERROR: Could not close filehandle [$userConfigFile] $!";	
	
	

}



sub openFolder {
	my $folderToOpen = $_[0];
	
	
	if ($macOS) {
		#system("open $folderToOpen");
		my $openCommand="/usr/bin/open";
		my $openArgs = $folderToOpen;
		open (my $openFH, "-|", $openCommand, $openArgs);
		close $openFH or warn "Could not close \$openCommand.  Error was [$?] $!";
	}

	if ($MSwin) {
		#system("start $folderToOpen");
		my $openCommand="start $folderToOpen";
		open (my $openFH, "-|", $openCommand) or warn "Could not open pipe to [$openCommand] $!";
		close $openFH or warn "Could not close \$openCommand. Unable to open [$folderToOpen] Error was [$?] $!";


	}

}



sub createOutputDirectories {
my $outputDirRoot;	      ## Desktop
my $outputDir;             ## Desktop/mblsync
my $outputDirUID;          ## Desktop/mblsync/5dg8angfakjh
my $outputDirUIDscript;    ## Desktop/mblsync/5dg8angfakjh/smsExport
#my outputDirUIDscriptBUP; ## Desktop/mblsync/5dg8angfakjh/smsExport/20210101-0101/ ## smsExport specific


	$outputDirRoot = $_[0];
	my $UID = $_[1];
	my $scriptName = $_[2];
	
	#die "[$outputDirRoot] $!";
	$outputDir =          "$outputDirRoot/mblsyc";
	$outputDirUID =       "$outputDirRoot/mblsyc/$UID";
	$outputDirUIDscript = "$outputDirRoot/mblsyc/$UID/$scriptName";
	
	## Create the main outputDirectoryRoot. (mblsync)
	unless (-d $outputDir) {
		print "Making new directory [$outputDir]\n";
		mkdir $outputDir or die "Could not create directory [$outputDir] $!";
	}
	
	
	## Create the per device output directory.
	unless (-d $outputDirUID) {
		print "Making new directory [$outputDirUID]\n";
		mkdir "$outputDirUID" or die "Could not create directory [$outputDirUID] $!";
	}


	## Create the per script outputDirectory we will use
	unless (-d $outputDirUIDscript) {
		print "Making new directory [$outputDirUIDscript]\n";
		mkdir $outputDirUIDscript or die "Could not create directory [$outputDirUIDscript] $!";
	}

return $outputDirUIDscript;


}


sub outputDirectoryRoot_user {
	## Allow user to specify outputDirectoryRoot.
	
	my $outputDirectoryRoot = $_[0];

	print "\nOutput directory is:\n[$outputDirectoryRoot]\n";
	print "Press enter to contine, CTL C to quit or specify a different directory:\n";	

	my $outputDirectoryRoot_user = <STDIN>;
	chomp $outputDirectoryRoot_user;
	## If user pressed enter and nothing else then use the original outputDirectoryRoot.
	
	if ($outputDirectoryRoot_user eq "") { return $outputDirectoryRoot; }
	
	if ($macOS) {
		$outputDirectoryRoot_user = macOSRemoveShellEscapes($outputDirectoryRoot_user);
	}
	
	
	
	{  ## Begin loop until user enters a pre existing and writable directory.

		unless (-d $outputDirectoryRoot_user && -w $outputDirectoryRoot_user) {
			print "Invalid folder!\n";
			sleep 2;

			print "\nOutput directory is:\n[$outputDirectoryRoot]\n";
			print "Press enter to contine, CTL C to quit or specify a different directory:\n";	
			
			
			$outputDirectoryRoot_user = <STDIN>;
			chomp $outputDirectoryRoot_user;
	
			## If user pressed enter and nothing else then use the original outputDirectoryRoot.
			if ($outputDirectoryRoot_user eq "") { return $outputDirectoryRoot_user; }

			if ($macOS) {
				$outputDirectoryRoot_user = macOSRemoveShellEscapes($outputDirectoryRoot_user);
			}
			
		
		} else {
			print "\nOutput directory changed to:\n[$outputDirectoryRoot_user]\n";
			return $outputDirectoryRoot_user; 
		}
	

		redo;
	} ## End loop until user enters a pre existing and writable directory.
}





sub macOSRemoveShellEscapes {
	my $string = $_[0];

		## Remove single back slashes, but replace double back slashes with a single backslash.
		$string =~ s/\\\\/\r/g; ## Replace double backslash with return character.
		$string =~ s/\\//g; ## Remove all remaining backslashes.
		$string =~ s/\r/\\/g; ## Replace return characters with single backslash.
	
		#If you drag and drop a folder to the terminal window there will be an extra space.  Remove that space.
		$string =~ s/ $//;
		
		## Change ~/ to $ENV{'HOME'}/
		$string =~ s/^~\//$ENV{'HOME'}\//;
		
		return $string;
}





1;