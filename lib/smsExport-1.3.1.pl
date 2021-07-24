#!/usr/bin/perl

use warnings;
use strict;

my $thisScript;
my $scriptVersion;
my $scriptStartTime;


## Version 1 should work with iOS Version 11 through 14  
## 	iOS V 11 - Confirmed
## 	iOS V 13.3.1 - Confirmed
##	iOS V 14.4.2 (_SqliteDatabaseProperties/_ClientVersion|14005)- Confirmed
##	iOS v 14.6 - Confirmed

## Version 1.1.1 Added support for Windows iTunes backups.
## Version 1.2.1 Improved user prompting for MobileSync/Backup folder.
## Version 1.2.1 Use timestamp from the Info.plist file to name output directory under UID.
## Version 1.2.1 Update mtime of files that perl copies to match the original local time.
## Version 1.2.1 Added column "idResolved" to smsWithToFrom.csv.  This will be the resolved ID, useful for filtering in spreadsheet program.
## Version 1.2.1 Added column "allHandles" to smsWithToFrom.csv.  Good for filtering group and single messages.
## Version 1.3.1 Moved some subroutines to perl module MblsyncUtils.pm

BEGIN {
$thisScript = "smsExport";
$scriptVersion = "1.3.1";
$scriptStartTime = localtime;


print "
 -----------------------------------------------------------------------------
| Running $thisScript v $scriptVersion at $scriptStartTime
|
| Will read iOS backup files, then attempt to export all messages in the SMS 
| database into one CSV file.  This could be a big file if you are popular.
| 
| Note that only message text is exported.  Pictures and other attachments
| including multimedia are NOT exported.
 -----------------------------------------------------------------------------\n\n\n";
}

###############################################################################
#### BEGIN common between mblsyncUtils

	###########################################################################
	## BEGIN Globals
	#
		
	## Database file names
	my $sms_db_FILENAME =  "3d0d7e5fb2ce288813306e4d4636395e047a3d28"; ## sms.db  sqlite DB where messages stored. Name of backup file in MobileSync/Backups
	my $AddressBook_sqlitedb_FILENAME = "31bb7ba8914766d4ba40d6dfb6113c8b614be442"; ## AddressBook.sqlitedb   sqlite DB where AddressBook.sqlitedb aka Contacts stored.  Name of backup file in MobileSync/Backups

	my $sqlite3; ## sqlite3 client binary
	my $clearCommand; ## OS specific command to clear the screen in terminal.
	my $iOSbackupRoot; ## This is where the per device iOS backups are stored. I.E. ~/mark/Library/Application Support/MobileSync/Backup
	my $outputDirectoryRoot; ## Directory where this script will write results to.
	#my $outputDirectoryRoot_user; ## USER specified (at runtime) Directory where this script will write results to.
	my @choseniOSBackup; ## Array whose elements are the properties of whatever iOS the user chose to use.
	my $MobileSyncBackup; ## The full path to the iOS backup we will copy data from.
	my $outputDirectory; ## The script specific directory we will write to. i.e. ~/Desktop/mblsync/[device UID]/smsExport
	my $Device_Name;  ## Name of iOS device, retrieved from Info.plist
	
	#
	## END Globals
	###########################################################################



	#### Load Modules 
	use File::Copy;
	use File::Basename qw(dirname);
	use Cwd  qw(abs_path);

	## Add to INC to load our module
	use lib dirname(dirname abs_path $0) . '/lib'; ##

	## Load our module 
	use MblsyncUtils::MblsyncUtils qw($macOS $MSwin $homeDirectory %configs getKeyValueFromPlist openFolder getLastModifiedFromBinaryPlist outputDirectoryRoot_user);


	#### Move some config items to variables.
	$sqlite3 =              $configs{'sqlite3'};           
	$clearCommand =         $configs{'clearCommand'};   
	$iOSbackupRoot =        $configs{'iOSbackupRoot'};  
	$outputDirectoryRoot =  $configs{'outputDirectoryRoot'};


	## Present outputDirectoryRoot to user and allow override.
	$outputDirectoryRoot = MblsyncUtils::MblsyncUtils::outputDirectoryRoot_user($outputDirectoryRoot);
	

	## Have user select the backup we will use with backupChooser
	## and add values to @choseniOSBackup.
		## @chosenIOSBackup
			## Index 0 is the folder name (UID) 
			## Index 1 is the parent folder.  
			## Index 2 is the full path to backup.
			## Index 3 is the Device Name found in Info.plist file.
			## Index 4 is the raw timestamp of the Info.plist file.
			## Index 5 is the formatted timestamp of the Info.plist file.

	@choseniOSBackup = MblsyncUtils::MblsyncUtils::backupChooser($iOSbackupRoot);
	$MobileSyncBackup = $choseniOSBackup[2];
	$Device_Name = $choseniOSBackup[3];
	

	## Create Output Directory
	$outputDirectory = MblsyncUtils::MblsyncUtils::createOutputDirectories($outputDirectoryRoot, $choseniOSBackup[0], $thisScript);

	
#### END common between MblsyncUtils
###############################################################################


#### Add directory to outputDirectory for backup set timestamp (timestamp 
#### of the Info.plist file).
$outputDirectory = $outputDirectory . "/$choseniOSBackup[5]";
unless (-e $outputDirectory ) {
	print "Making new directory [$outputDirectory]\n";
	mkdir "$outputDirectory" or die "Could not make directory [$outputDirectory]\n$!";
}


#### Create subdirectories in outputDirectory
unless (-d "$outputDirectory/copiedMblSyncBackupFiles") {
	print "Making new directory [$outputDirectory/copiedMblSyncBackupFiles]\n";
	mkdir "$outputDirectory/copiedMblSyncBackupFiles" or die "Could not create directory [$outputDirectory/copiedMblSyncBackupFiles] $!";
}

unless (-d "$outputDirectory/tableData") {
	print "Making new directory [$outputDirectory/tableData]\n";
	mkdir "$outputDirectory/tableData" or die "Could not create directory [$outputDirectory/tableData] $!";
}



#### Copy database files from MobileSync/Backup directory into outputDirectory.
## NOTE: Older iOS would keep all backup files in the root backup folder. 
## Later iOS versions (iOS 10,11,12,13,14) divided up with subdirectories 
## named with first 2 characters of the backup file.

## First create subfolder in outputDirectory for copied files from MobileSync/backup
unless (-d "$outputDirectory/copiedMblsyncBackupFiles") {
	print "Making new directory [$outputDirectory/copiedMblsyncBackupFiles]\n";
	mkdir ("$outputDirectory/copiedMblsyncBackupFiles") == 1 or die "$! \n\nERROR: Could not create [$outputDirectory/copiedMblsyncBackupFiles].\n";
}


## Build list of files we will copy.
my @msyncFilesToCopy;
push @msyncFilesToCopy,"$sms_db_FILENAME"; 
push @msyncFilesToCopy,"$AddressBook_sqlitedb_FILENAME"; 
push @msyncFilesToCopy,"Info.plist"; 
push @msyncFilesToCopy,"Manifest.plist"; 

if (-e "$choseniOSBackup[2]/Manifest.mbdb") {
	push @msyncFilesToCopy,"Manifest.mbdb"; 
}
if (-e "$choseniOSBackup[2]/Manifest.db") {
	push @msyncFilesToCopy,"Manifest.db"; 
}

## The directory copied files will be in.
my $destRoot = "$outputDirectory/copiedMblsyncBackupFiles";

foreach my $file (@msyncFilesToCopy) {

	## Prepare 'Copy From' and 'Copy To' strings.
	my $copyFrom = "$choseniOSBackup[2]/$file";
	my $copyTo = "$destRoot/$file";
	
	
	## If file stored in a 2 character prefixed parent directory then 
	## adjust copyFrom string to include this parent directory.
	my $leading2characters = substr $file,0,2;

	if (-e "$choseniOSBackup[2]/$leading2characters/$file" ) {
		$copyFrom = "$choseniOSBackup[2]/$leading2characters/$file";
	}


	## Now copy the file.
	if (-e $copyTo) {
		print "Note: File exists, will not overwrite [$copyTo]\n";
	} else {
		print "Copying files\nF:[$copyFrom]\nT:[$copyTo]\n\n";
		copy ("$copyFrom", "$copyTo") or die "ERROR: Could not copy [$copyFrom] to [$copyTo]. $!";
	}

	## Change modification timestamp of the new file to match original.
	my $fileMtime = (stat $copyFrom)[9];
	utime $fileMtime, $fileMtime, "$copyTo";

}
	


#### Change Directory to the $outputDirectory so we can use backticks and not have shell quoting issues.
chdir ($outputDirectory) or die "\nERROR: Could not chdir to [$outputDirectory]. $!" ;

## Make sure directory is writable.
unless (-d "tableData" && -w "tableData") { die "$! \n\nERROR: tableData folder does not exist or is not writeable.";}


#### Match phone number or email address to a contact name and organization,
#### building hashes for %numberName and %handleROWIDName.
### Get phone number or email address from handle.id in sms.db.  Use 
### ABPersonFullTextSearch_content table in AddressBook.sqlitedb to match 
### c16Phone with handle.id from sms.db.
my %numberName; ##%numberName{+15555555555} = "John Smith Some Organization"
my %handleROWIDName; ##%ROWIDName{1} = "John Smith Some Organization"


### Get list of phone numbers and email addresses, (unique values) to %handleid
## $handleid{rowid} = 5555555555;
## $handleid{rowid} = mike@email.com;

my $sqlCall_handleid="$sqlite3 \"copiedMblsyncBackupFiles/$sms_db_FILENAME\"  \"
select ROWID, id from handle
order by ROWID
\"
";

#print "Executing sql:\n[$sqlCall_handleid]\n\n";

my %handleid;
foreach my $handleRow (`$sqlCall_handleid`) { 
	chomp $handleRow;

	my ($ROWID, $id) = split /\|/, $handleRow,2;
	#print "$ROWID, $id \n";
	$handleid{$ROWID} = $id;
}
## Do not continue if sqlCall failed.
if ($? != 0) { die "sql failed.  \$sqlCall_handleid was [$sqlCall_handleid].\n sqlite3 error code was [$?].\nCheck to be sure this is not an encrypted backup. $!"; }



##### get phone number column
## %c16Phone{docid}
my %c16Phone;

my $sqlCall_c16Phone="$sqlite3 \"copiedMblsyncBackupFiles/$AddressBook_sqlitedb_FILENAME\"	\"
select docid, c16Phone from ABPersonFullTextSearch_content
\"
";

foreach my $ABPFTS_contentRow (`$sqlCall_c16Phone`) {
	chomp $ABPFTS_contentRow;

	my ($docid, $c16Phone) = split /\|/, $ABPFTS_contentRow,2;
	$c16Phone{$docid} = $c16Phone;

}
## Do not continue if sqlCall failed.
if ($? != 0) { die "sql failed.  \$sqlCall_c16Phone was [$sqlCall_c16Phone].\n sqlite3 error code was $?. $!"; }



##### get email address column
## %c17Email{docid}
my %c17Email;

my $sqlCall_c17Email="$sqlite3 \"copiedMblsyncBackupFiles/$AddressBook_sqlitedb_FILENAME\"	\"
select docid, c17Email from ABPersonFullTextSearch_content
\"
";

foreach my $ABPFTS_contentRow (`$sqlCall_c17Email`) {
	chomp $ABPFTS_contentRow;

	my ($docid, $c17Email) = split /\|/, $ABPFTS_contentRow,2;
	#print "$docid, $c16Phone\n";
	$c17Email{$docid} = $c17Email;
}
## Do not continue if sqlCall failed.
if ($? != 0) { die "sql failed.  \$sqlCall_c17Email was [$sqlCall_c17Email].\n sqlite3 error code was $?. $!"; }



##### get first name column
## %c0First{docid}
my %c0First;

my $sqlCall_c0First="$sqlite3 \"copiedMblsyncBackupFiles/$AddressBook_sqlitedb_FILENAME\"	\"
select docid, c0First from ABPersonFullTextSearch_content
\"
";

foreach my $ABPFTS_contentRow (`$sqlCall_c0First`) {
	chomp $ABPFTS_contentRow;

	my ($docid, $c0First) = split /\|/, $ABPFTS_contentRow,2;
	$c0First{$docid} = $c0First;
	#print "$docid, $c0First\n";
}
## Do not continue if sqlCall failed.
if ($? != 0) { die "sql failed.  \$sqlCall_c0First was [$sqlCall_c0First].\n sqlite3 error code was $?. $!"; }



##### get last name column
## %c1Last{docid}
my %c1Last;

my $sqlCall_c1Last="$sqlite3 \"copiedMblsyncBackupFiles/$AddressBook_sqlitedb_FILENAME\"	\"
select docid, c1Last from ABPersonFullTextSearch_content
\"
";

foreach my $ABPFTS_contentRow (`$sqlCall_c1Last`) {
	chomp $ABPFTS_contentRow;

	my ($docid, $c1Last) = split /\|/, $ABPFTS_contentRow,2;
	$c1Last{$docid} = $c1Last;

	#print "$docid, $c1Last\n";
}
## Do not continue if sqlCall failed.
if ($? != 0) { die "sql failed.  \$sqlCall_c1Last was [$sqlCall_c1Last].\n sqlite3 error code was $?. $!"; }



##### get organization column
## %c6Organization{docid}
my %c6Organization;

my $sqlCall_c6Organization="$sqlite3 \"copiedMblsyncBackupFiles/$AddressBook_sqlitedb_FILENAME\"	\"
select docid, c6Organization from ABPersonFullTextSearch_content

\"
";

foreach my $ABPFTS_contentRow (`$sqlCall_c6Organization`) {

	chomp $ABPFTS_contentRow;

	my ($docid, $c6Organization) = split /\|/, $ABPFTS_contentRow,2;
	$c6Organization{$docid} = $c6Organization;

}
## Do not continue if sqlCall failed.
if ($? != 0) { die "sql failed.  \$sqlCall_c6Organization was [$sqlCall_c6Organization].\n sqlite3 error code was $?. $!"; }




####  Loop through handle.ROWID (%handleid) and match handle.id to c16Phone

foreach my $handleROWID (keys %handleid) {

	my $HANDLEID = $handleid{$handleROWID};
	my $HANDLEIDquoted = quotemeta($HANDLEID);

	$numberName{$HANDLEID} = "NONAMEFOUND";
	$handleROWIDName{$handleROWID} = "NONAMEFOUND";

	foreach my $docid (keys %c16Phone){
		my $C16PHONE = $c16Phone{$docid};
		chomp $C16PHONE;
	


		if ($C16PHONE =~ / $HANDLEIDquoted /) {

			## only match handle.id that begins with a +
			next unless($HANDLEID =~ /^\+/);

			$numberName{$HANDLEID} = "$c0First{$docid} $c1Last{$docid} $c6Organization{$docid}";
			$handleROWIDName{$handleROWID} = $numberName{$HANDLEID};

		}
	}
}


####  Loop through handle.ROWID (%handleid) and match handle.id to c17Email

foreach my $handleROWID (keys %handleid) {

	my $HANDLEID = $handleid{$handleROWID};
	my $HANDLEIDquoted = quotemeta($HANDLEID);

	foreach my $docid (keys %c17Email){
		my $c17Email = $c17Email{$docid};
		chomp $c17Email;
		if ($c17Email =~ /$HANDLEIDquoted/i) {

			$numberName{$HANDLEID} = "$c0First{$docid} $c1Last{$docid} $c6Organization{$docid}";
			$handleROWIDName{$handleROWID} = $numberName{$HANDLEID};

		}
	}
}




#### Tie message_id to a chat_id so we can get list of handle_id(s) associated with a message_id
my %chat_message_join__message_id;
## $chat_message_join__message_id{34756} = 689;

my $sqlCall_chat_message_join = "$sqlite3 -header -csv \"copiedMblsyncBackupFiles/$sms_db_FILENAME\"	\"
select chat_id,message_id from chat_message_join\"
";


foreach my $chat_message_joinROW (`$sqlCall_chat_message_join`) { 
	chomp $chat_message_joinROW;
	my ($chat_id, $message_id) = split /,/,$chat_message_joinROW,2;
	$chat_message_join__message_id{$message_id} = $chat_id;
}
## Do not continue if sqlCall failed.
if ($? != 0) { die "ERROR: sql failed.  \$sqlCall_chat_message_join was [$sqlCall_chat_message_join].\n sqlite3 error code was $?. $!"; }



#### Get list of handle_id s associated with a chat_id
my %chat_handle_join__chat_id;

my $sqlCall_chat_handle_join = "$sqlite3 -header -csv \"copiedMblsyncBackupFiles/$sms_db_FILENAME\"	\"
select chat_id,handle_id from chat_handle_join\"
";


foreach my $chat_handle_joinROW (`$sqlCall_chat_handle_join`) { 
	chomp $chat_handle_joinROW;
	my ($chat_id, $handle_id) = split /,/,$chat_handle_joinROW,2;
	$chat_handle_join__chat_id{$chat_id} .= "$handle_id ";
	#print" $chat_id, $message_id\n";
}
## Do not continue if sqlCall failed.
if ($? != 0) { die "ERROR: sql failed.  \$sqlCall_chat_handle_join was [$sqlCall_chat_handle_join].\n sqlite3 error code was $?. $!"; }



#### Output message table to csv file.  This file is not currently used but could be used for debugging.

## File to write to.
my $messageCSVfile = "$outputDirectory/tableData/$Device_Name-message.csv";

## sql call
my $sqlCall_messageTable = "$sqlite3 -header -csv \"copiedMblsyncBackupFiles/$sms_db_FILENAME\"	\"
select ROWID, text, handle_id, subject, date, is_from_me from message
\" ";


## Make sure output file does not already exist.
if (-e $messageCSVfile) { 

	print "\nNOTE: Will not overwrite $messageCSVfile. $!"; 

} else {

	## Open file for writing
	print "Writing to [$messageCSVfile]\n";
	open (my $messageCSVFH,">",$messageCSVfile) or die "\nERROR: Could not open for writing: [$messageCSVfile]. $!";
	print $messageCSVFH "\x{ef}\x{bb}\x{bf}";  ## So excel will display unicode correctly.

	## Execute SQL.
	print $messageCSVFH `$sqlCall_messageTable`;

	## Do not continue if sqlCall failed.
	if ($? != 0) { die "ERROR: sql failed.  \$sqlCall_messageTable was [$sqlCall_messageTable].\n sqlite3 error code was $?. $!"; }

	close $messageCSVFH;
}



#### Output THE sms CSV file with outgoing phone number joined from handle table.

## File to write to.
my $messageWithJoinCSVfile = "$outputDirectory/tableData/$Device_Name-sms.csv";

## sql call
my $selectDate = "datetime(message.date / 1000000000 + 978307201,'unixepoch') as date"; ## Date select for iOS 14,13

if (getKeyValueFromPlist("Product Version","$outputDirectory/copiedMblsyncBackupFiles/Info.plist") =~ /^10/) {
	$selectDate = "datetime(message.date + 978307201,'unixepoch') as date"; ## Date select for iOS 10
}

my $sqlCall_messageTableWithJoin = "$sqlite3 -header -csv \"copiedMblsyncBackupFiles/$sms_db_FILENAME\"	\"

select 

message.ROWID, 
$selectDate,
message.handle_id, 
handle.id,
message.cache_roomnames,
message.is_from_me,
REPLACE(REPLACE(message.subject, x'0D','<crNEWLINE>'), x'0A', '<nlNEWLINE>') as 'subject', 
REPLACE(REPLACE(message.text, x'0D','<crNEWLINE>'), x'0A', '<nlNEWLINE>') as 'text'

from message

left join handle
on message.handle_id=handle.ROWID

order by message.ROWID

\"
";


## If file does not already exist, then output data to it.
if (-e $messageWithJoinCSVfile) { 
	print "\nNOTE: Will not overwrite $messageCSVfile. $!"; 
} else {

	## Open file for writing
	print "Writing to [$messageWithJoinCSVfile]\n";
	open (my $messageWithJoinCSVFH,">",$messageWithJoinCSVfile) or die "\nERROR: Could not open for writing: [$messageCSVfile]. $!";
	print $messageWithJoinCSVFH "\x{ef}\x{bb}\x{bf}";  ## Write BOM so excel will display unicode correctly.

	## Execute SQL, writing output to csv file.
	print $messageWithJoinCSVFH `$sqlCall_messageTableWithJoin`;
	close $messageWithJoinCSVFH or die "Could not close $messageWithJoinCSVFH. $!";

	## Do not continue if sqlCall failed.
	if ($? != 0) { die "sql failed.  \$sqlCall_messageTableWithJoin was [$sqlCall_messageTableWithJoin].\n sqlite3 error code was $?. $!"; }

}


#### Read CSV file, add contact names and output to new file.
my $messageCSVwithContacts = "$outputDirectory/tableData/$Device_Name-smsWithContacts.csv";
if (-e $messageCSVwithContacts) { 
	print "NOTE: File exists. Will not overwrite [$messageCSVwithContacts]\n" 
} else {
	die "ERROR: file exists [$messageCSVwithContacts] $!" if (-e $messageCSVwithContacts );
	print "Writing to [$messageWithJoinCSVfile]\n";
	open (my $messageWithJoinCSVFH,"<",$messageWithJoinCSVfile) or die "\nERROR: Could not open [$messageWithJoinCSVfile] for reading. $!";

	open (my $messageCSVwithContactsFH, ">",$messageCSVwithContacts) or die "\nERROR: Could not open [$messageCSVwithContacts] for writing. $!";
	print $messageCSVwithContactsFH "\x{ef}\x{bb}\x{bf}";  ## So excel will display unicode correctly.
	print $messageCSVwithContactsFH "ROWID,date,handle_id,id,contactName,is_from_me,subject,text\n";

	while (my $csvLine = <$messageWithJoinCSVFH>) {
		next if $. == 1; # Skip first line
		my ($ROWID,$date,$handle_id,$id,$cache_roomnames,$restOfline) = split /,/,$csvLine, 6;
		my $contactName="$id"; ## use $id instead of NONAMEFOUND
		if ($numberName{$id}) { $contactName = $numberName{$id} }


		## If $handle_id = 0 then this is a chat or group message.  Will need to use chat table to determine message recipient(s)
		## relevent columns are message.cache_roomnames and chat.chat_identifier
		if ($handle_id == 0) {
			$contactName = "Me to ... ";		
		}

		print $messageCSVwithContactsFH "$ROWID,$date,$handle_id,$id,$contactName,$restOfline";
	}

	close ($messageWithJoinCSVFH) or die "\nERROR: Could not close $messageWithJoinCSVFH. $!";
}


#### Read CSV file, add new columes and output new CSV file using columns:
#### ROWID,date,id,idResolved,allHandles,From,To,subject,text
####
#### Note handle_id of 0 indicates a text from me to multiple recipients.

my $messageCSVwithToFrom = "$outputDirectory/$Device_Name-smsWithToFrom.csv";
if (-e $messageCSVwithToFrom) { 
	print  "NOTE: File exists, will not overwrite [$messageCSVwithToFrom]. $!"
} else {

	open (my $messageWithJoinCSVFH,"<",$messageWithJoinCSVfile) or die "\nERROR: Could not open [$messageWithJoinCSVfile] for reading. $!";
	print "Writing to [$messageCSVwithToFrom]\n";
	open (my $messageCSVwithToFromFH, ">",$messageCSVwithToFrom) or die "\nERROR: Could not open [$messageCSVwithContacts] for writing. $!";

	## Output BOM otherwise Excel may not display UTF-8 unicode characters correctly.
	print $messageCSVwithToFromFH "\x{ef}\x{bb}\x{bf}";  ## So excel will display unicode correctly.

	## Output column names.
	print $messageCSVwithToFromFH "ROWID,date,id,idResolved,allHandles,From,To,subject,text\n"; 

	## Loop through the $outputDirectory/sms.csv file line by line, add 'from' and 'to' column data and output to the new file.
	while (my $csvLine = <$messageWithJoinCSVFH>) {
		next if $. == 1; # Skip column headers on first line.
		chomp $csvLine;
	
		my ($ROWID,$date,$handle_id,$id,$cache_roomnames,$is_from_me,$subject,$text) = split /,/,$csvLine, 8;

		unless ($id) { $id = "0";}

		print $messageCSVwithToFromFH "$ROWID,$date,$id";

		## idResolved
		my $idResolved = "";
		if ($numberName{$id}) {
			$idResolved = $numberName{$id};
		} else {
			if ($id eq "0") { 
				$idResolved = "me to ...";
			}
		}
	
		$idResolved =~ s/\"/\"\"/g; ## Escape quotes for csv compatibility.


		my $fromValue ="nonamefound"; 
		if ($handle_id == 0) {
			$fromValue = "me";
		} else {	
			if ($is_from_me == 1) { $fromValue = "me"; } 
			if ($is_from_me == 0) { $fromValue = "$numberName{$id}"; } 
		}
		$fromValue =~ s/\"/\"\"/g; ## Escape quotes for csv compatibility.

	
		my $toValue = getChatRecipientList($ROWID,$handle_id,$is_from_me,$id);
		$toValue =~ s/\"/\"\"/g; ## Escape quotes for csv compatibility.			 



		#### Output 'idResolved' column
		print $messageCSVwithToFromFH ",\"$idResolved\"";

		#### Output allHandles column All associated handles (useful for filtering by message sender or receiver to include chat messages as well as single messages.)
		print $messageCSVwithToFromFH ",\"$fromValue $toValue\"";

		#### Output 'From' column.
		print $messageCSVwithToFromFH ",\"$fromValue\"";

		#### Output 'To' column
		print $messageCSVwithToFromFH ",\"$toValue\"";




		#### Output the rest of columns (subject, text).

		## Put newlines and carriage returns back in to both subject and text columns.
		if ($subject =~ /<nlNEWLINE>/) {
			unless ($subject =~ /^"/ && $subject =~ /"$/) {	$subject = "\"$subject\"" ; }
			$subject =~ s/<nlNEWLINE>/\n/g;
		}
		if ($subject =~ /<crNEWLINE>/) {
			unless ($subject =~ /^"/ && $subject =~ /"$/) {	$subject = "\"$subject\"" ; }
			$subject =~ s/<crNEWLINE>/\n/g;
		}

		if ($text =~ /<nlNEWLINE>/) {
			unless ($text =~ /^"/ && $text =~ /"$/) {	$text = "\"$text\"" ; }
			$text =~ s/<nlNEWLINE>/\n/g;
		}
		if ($text =~ /<crNEWLINE>/) {
			unless ($text =~ /^"/ && $text =~ /"$/) {	$text = "\"$text\"" ; }
			$text =~ s/<crNEWLINE>/\n/g;
		}
	
		print $messageCSVwithToFromFH ",$subject,$text\n";

	}

	close ($messageWithJoinCSVFH) or die "\nERROR: Could not close [$messageWithJoinCSVfile] $!";
	close ($messageCSVwithToFromFH) or die "\nERROR: Could not close [$messageCSVwithContacts] $!";
}




print "\n$thisScript completed at " . localtime . "\n";
print "\nsmsExports are located at:\n\n$outputDirectory\n\n";


print "Press RETURN to open the smsExports '$choseniOSBackup[5]' folder.\n";
<STDIN>;

openFolder($outputDirectory);

exit;




##############################################################################
#### Subroutines
##############################################################################



sub getChatRecipientList {

	my $ROWID       = $_[0];
	my $handle_id   = $_[1];
	my $is_from_me  = $_[2];
	my $id          = $_[3];

	my $toValue = "ME";

	if ($handle_id == 0) {

		if ($chat_message_join__message_id{$ROWID}) {

			my $chat_id = $chat_message_join__message_id{$ROWID};
			$toValue = $chat_handle_join__chat_id{$chat_id};
			my @toValues = split /\s/,$toValue;

			if (scalar @toValues > 1) {
				$toValue = "";
				foreach my $handle_id (@toValues) { 
					if ($handleROWIDName{$handle_id}) {
						$toValue .= "[$handleROWIDName{$handle_id}]"; 
					}
				}
			}
		}
	

	} else {
		## Check to see if there are multiple handle_id(s) associated with chat_id <- message_id
		my $chat_id = $chat_message_join__message_id{$ROWID};
		if ($chat_id) {
			$toValue = $chat_handle_join__chat_id{$chat_id}; 
			my @toValues = split /\s/,$toValue;

			if (scalar @toValues > 1) {
				$toValue = "";
				foreach my $handle_id (@toValues) { 
					if ($handleROWIDName{$handle_id}) {
						$toValue .= "[$handleROWIDName{$handle_id}]"; 
					}
				}
			} else {
				if ($is_from_me == 1) { $toValue = "$numberName{$id}"; } 
				if ($is_from_me == 0) { $toValue = "me"; } 
			}
		}
	}
return $toValue;
}




