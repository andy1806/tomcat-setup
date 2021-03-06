##############################################################################
# Database management script
#
# This script contains functions for database management, and will invoke the
# appropriate function based on the arguments passed to it.
##############################################################################

list_databases() {
	ssh -t $user@$ip "mysql -p -e 'show databases'"
}

list_users() {
	ssh -t $user@$ip "mysql -p -e 'select user from mysql.user'"
}

create_db() {
	db_name=$1
	[[ -z $db_name ]] && read -p 'database name: ' db_name
	db_user=$2
	[[ -z $db_user ]] && read -p 'database user: ' db_user
	read -sp 'Choose a password for this database user: ' db_pass
	echo
	read -sp 'confirm password: ' confirm_pass
	echo
	echo

	if [[ "$db_pass" != "$confirm_pass" ]]; then
		echo 'ERROR: passwords do not match!'
		exit 1
	fi

	cat <<-message
	creating database:
	    database: $db_name
	    user:     $db_user

	When prompted, enter your *database administrator* password to continue
	message

	ssh -t $user@$ip "mysql -p <<sql
	CREATE DATABASE IF NOT EXISTS $db_name;
	CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_pass';
	GRANT ALL ON ${db_name}.* TO '$db_user'@'localhost';
	FLUSH PRIVILEGES;
sql"

	[[ $? -eq 0 ]] && echo 'Database Created!'
}

backup_db() {
	database=$1
	outputfile=$2
	if [[ -z $database ]]; then
		read -p 'database name: ' database
	fi
	if [[ -z $outputfile ]]; then
		outputfile="$BASE_DIR/db-backups/$(date +%Y-%m-%d_%H:%M:%S)-${database}-backup.sql"
	fi

	read -sp 'Password: ' db_pass
	echo -e "\nbacking up...."
	ssh -t $user@$ip "mysqldump -p${db_pass} ${database} 2>/dev/null" > $outputfile
	echo
	echo "$outputfile created!"
}

run_file() {
	database=$1
	sql_file=$2
	if [[ -z $database ]]; then
		read -p 'database name: ' database
	fi
	if [[ -z $sql_file ]]; then
		read -ep 'sql file: ' sql_file
		# parse the home directory correctly
		if grep '^~' <<< "$sql_file"; then
			sql_file=$(perl -pe "s!~!$HOME!" <<< $sql_file)
		fi
	fi

	# ensure file exists and is a sql file (or at least has the extension)
	if [[ ! -f $sql_file ]]; then
		echo 'It looks like that file does not exist! Aborting...'
		echo "Could not find '$sql_file'! No migrations run."
		exit 1
	fi
	grep '\.sql$' >/dev/null <<< $sql_file
	if [[ $? -ne 0 ]]; then
		echo 'It looks like that is not a valid SQL file! Aborting...'
		echo "'$sql_file' does not have a '.sql' file extension."
		echo 'No migrations run.'
		exit 1
	fi

	echo 'When prompted, enter your *database administrator* password to continue'
	# make sure the nowdoc identifier doesnt clash with anything in the
	# migration
	ssh -t $user@$ip "mysql -p $database <<'xxxxxxxxxx_sql_migration_xxxxxxxxx'
	$(cat $sql_file)
xxxxxxxxxx_sql_migration_xxxxxxxxx"
	[[ $? -eq 0 ]] && echo 'Finished running!'
}

remove_db() {
	db_name=$1
	db_user=$2
	if [[ -z $db_name ]]; then
		read -p 'Enter the name of the database to remove: ' db_name
	fi
	if [[ -z $db_user ]]; then
		read -p 'Enter the name of the user to remove: ' db_user
	fi

	ssh -t $user@$ip "mysql -p -e 'DROP DATABASE ${db_name}'
					  mysql -p -e 'DROP USER ${db_user}@localhost'"

	[[ $? -eq 0 ]] && echo 'Database Removed!'
}

login() {
	ssh -t $user@$ip mysql -p
}

show_usage() {
	cat <<-help_message
	db -- command for interacting with databases on your server
	usage

	    ./server db <command>

	where <command> is one of the following:

	    login
	    list
	    create  [dbname [dbuser]]
	    backup  [dbname [outputfile]]
	    run     [dbname [/path/to/file.sql]]
	    remove  [dbname [dbuser]]

	help_message
}

command=$1
shift

case $command in
	create)    create_db $@;;
	backup)    backup_db $@;;
	run)       run_file  $@;;
	remove|rm) remove_db $@;;
	list|ls)   list_databases;;
	login)     login;;
	*)         show_usage;;
esac
