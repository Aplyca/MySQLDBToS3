#! /bin/sh

SH_SOURCE=$(basename ${0})

PID="$$"
PS4='+ ${SH_SOURCE} : ${LINENO} : '

## Example: usage 2 "Invalid input"
usage(){
	EXITCODE=${1}
	cat << USAGE >&2
This scrip is used to sync a database with information stored in a s3 bucket
Usage: ${2}
  ${SH_SOURCE} [-v]
    -v		Shows logs verbose
	-s		Send notification to slack
    -h		Shows help
USAGE
	exit "${EXITCODE}"
}

while [ $# -gt 0 ]
do
	case "${1}" in
		-v)
			VERBOSE="true"
			shift
		;;
		-s)
			SLACK=true
			shift
		;;
		-h)			
			usage 0
		;;
		*)
			usage 2 "Invalid input"
		;;
	esac
done

VERBOSE=${VERBOSE:=false}
SLACK=${SLACK:-false}
MYSQL_PORT=${MYSQL_PORT:-3306}

FILE=${MYSQL_DUMP_FILE}

deleteFile(){
        if [ -e ./${1} ]; then
                rm ${1}
        fi
        return $?
}

slackNotification(){
	TIMESTAMP=$(date +"%Y-%m-%d %T")
	COLOR=${COLOR:-"#334455"}
	MSG=${MSG:-"A sync DB was executed"}

	if [ ! -z $1 ]; then
		[ $1 = "ERROR" ] && COLOR="danger" shift
		[ $1 = "OK" ] && COLOR="good" shift
		MSG=$@
	fi

	PAYLOAD=$(cat << _EOF_ > payload.json
{
		"text": "*Sync DB from AWS Task Definition ${DESCRIPTION}*",
		"username":"aws",
		"attachments": [
	{
		"color": "${COLOR}",
		"fields": [
			{ "title": "Message", "value": "${MSG}", "short": false },
			{ "title": "Finished at", "value": "${TIMESTAMP}", "short": false}
		]
	}
	]
}
_EOF_
	)

	curl -s -o /dev/null -X POST ${SLACK_WEBHOOK} -d @./payload.json

	if [ $? -eq 0 ]
	then
		${VERBOSE} && echo ${TIMESTAMP} ${SH_SOURCE} [${PID}]: INFO "Notification sent to Slack"
	else
		deleteFile payload.json
		echo ${TIMESTAMP} ${SH_SOURCE} [${PID}]: ERROR "There was an error sending the notification to Slack"
		exit 1
	fi

	deleteFile payload.json
}

## Function to show INFO or ERROR logs
## Example: logit INFO "Test"
logit(){
	local LOG_LEVEL=${1}
	shift
	TIMESTAMP=$(date +"%Y-%m-%d %T")
	MSG=$@
	if [ ${LOG_LEVEL} = 'ERROR' ] || ${VERBOSE}
	then
		echo "${TIMESTAMP} ${SH_SOURCE} [${PID}]: ${LOG_LEVEL} ${MSG}"
		if [ ${LOG_LEVEL} = 'ERROR' ]; then
			   ${SLACK} && slackNotification ${LOG_LEVEL} $MSG
		       exit 1
	       fi
	fi
}

## Variable validations
[ -z ${MYSQL_HOST} ] && logit ERROR "Must be defined a Mysql host in variable MYSQL_HOST" 
[ -z ${MYSQL_USER} ] && logit ERROR "Must be defined a Mysql user in a variable MYSQL_USER"
[ -z ${MYSQL_PASS} ] && logit ERROR "Must be defined a Mysql password in a variable MYSQL_PASS"
[ -z ${MYSQL_DB} ] && logit ERROR "Must be defined a Mysql db in a variable MYSQL_DB"
[ -z ${S3_BUCKET} ] && logit ERROR "Must be defined a s3 bucket in a variable S3_BUCKET"
[ -z ${S3_DB_BKP_FOLDER} ] && logit ERROR "Must be defined a s3 bucket folder in a variable S3_DB_BKP_FOLDER"
[ -z ${MYSQL_DUMP_FILE} ] && logit ERROR "Must be defined the backup file in a variable MYSQL_DUMP_FILE"
${SLACK} && [ -z ${SLACK_WEBHOOK} ] && logit ERROR "Must be defined a Slack Webhook in a variable SLACK_WEBHOOK"

cd /tmp
logit INFO "Downloading the backup from S3"
aws s3 cp s3://${S3_BUCKET}/${S3_DB_BKP_FOLDER}/${FILE} .

if [ "${?}" -eq 0 ]; then
	case ${FILE} in
		*.gz)
			logit INFO "Uncompress gz file" && gunzip ${FILE} && FILE=$(echo "${FILE}" | sed "s/.gz//")			
			if [ "${?}" -ne 0 ]; then
				logit ERROR "There was an error uncompressing the file"
			fi
		;;
		*.sql) 
			logit INFO "There is a .sql file to process"
		;;
		*)
			logit ERROR "It seems the ${FILE} cannot be processed"
	esac
else
	logit ERROR "There was an error downloading the backup from S3"
fi


mysql -h ${MYSQL_HOST} -u ${MYSQL_USER} -p${MYSQL_PASS} -e 'use '"${MYSQL_DB}"

if [ $? -eq 0 ]; then
	# Delete database
	logit INFO "Dropping database: ${MYSQL_DB}"
	mysqladmin -h ${MYSQL_HOST} -u ${MYSQL_USER} -p${MYSQL_PASS} drop ${MYSQL_DB} -f || logit ERROR "There was an error droping the database ${MYSQL_DB}"

	# Create database
	logit INFO "Creating database: ${MYSQL_DB}"
	mysqladmin -h ${MYSQL_HOST} -u ${MYSQL_USER} -p${MYSQL_PASS} create ${MYSQL_DB} -f || logit ERROR "There was an error creating the database ${MYSQL_DB}"

	# Upload dump to database
	logit INFO "Importing database ${FILE} to server: ${MYSQL_HOST}"
	mysql -h ${MYSQL_HOST} -u ${MYSQL_USER} -p${MYSQL_PASS} ${MYSQL_DB} < ${FILE} || logit ERROR "There was an error loading the dump to database ${MYSQL_DB}"
else
	logit ERROR "There was an error connecting to the database ${MYSQL_HOST}"	
fi

logit INFO "The db sync process was finished successfully"

${SLACK} && slackNotification OK "The db sync process was finished successfully"

exit 0