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
FILE=${MYSQL_DUMP_FILE}.sql

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
[ -z ${MYSQL_HOST} ] && logit ERROR "Must be defined a Mysql host"
[ -z ${MYSQL_USER} ] && logit ERROR "Must be defined a Mysql user"
[ -z ${MYSQL_PASS} ] && logit ERROR "Must be defined a Mysql password"
[ -z ${S3_BUCKET} ] && logit ERROR "Must be defined a s3 bucket"

cd /tmp
logit INFO "Executiong the mysqldump command"
mysqldump --host ${MYSQL_HOST} --port ${MYSQL_PORT} -u ${MYSQL_USER} --password="${MYSQL_PASS}" ${MYSQL_DB} > ${FILE}
if [ "${?}" -eq 0 ]; then
  logit INFO "Zipping file ${FILE}"
  gzip ${FILE}
  logit INFO "Uploading to S3"
  aws s3 cp ${FILE}.gz s3://${S3_BUCKET}/${S3_DB_BKP_FOLDER}/
  if [ "${?}" -eq 0 ]; then
  	logit INFO "Uploaded to S3 successfully"
	${SLACK} && slackNotification OK "The db dump to s3 was done successfully"
    exit 0
  else
    logit ERROR "Error copying to S3"
  fi
  rm ${FIEL}.gz
else
  logit ERROR "Error backing up mysql"
fi
exit 0
