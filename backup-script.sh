#! /bin/sh

SH_SOURCE=$(basename ${0})

PID="$$"
PS4='+ ${SH_SOURCE} : ${LINENO} : '

## Example: usage 2 "Invalid input"
usage(){
	EXITCODE=${1}
	cat << USAGE >&2
This scrip is used to create a dump of mysql database and send the backup to bucket s3
Usage: ${2}
  ${SH_SOURCE} [-v]
    -v		Shows logs verbose
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
		-h)			
			usage 0
		;;
		*)
			usage 2 "Invalid input"
		;;
	esac
done

VERBOSE=${VERBOSE:=false}
TIMESTAMP=$(date +"%Y-%m-%d %T")
FILE=${MYSQL_DUMP_FILE}-$(date +%Y-%m-%h).sql

## Function to show INFO or ERROR logs
## Example: logit INFO "Test"
logit(){
	local LOG_LEVEL=${1}
	shift
	MSG=$@
	if [ ${LOG_LEVEL} = 'ERROR' ] || ${VERBOSE}
	then
		echo "${TIMESTAMP} ${SH_SOURCE} [${PID}]: ${LOG_LEVEL} ${MSG}"
		if [ ${LOG_LEVEL} = 'ERROR' ]; then
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
logit INFO "mysqldump --host ${MYSQL_HOST} --port ${MYSQL_PORT} -u ${MYSQL_USER} --password="${MYSQL_PASS}" ${MYSQL_DB} > ${FILE}"
if [ "${?}" -eq 0 ]; then
  logit INFO "gzip ${FILE}"
  logit INFO "aws s3 cp ${FILE}.gz s3://${S3_BUCKET}/${S3_DB_BKP_FOLDER}/"
  if [ "${?}" -eq 0 ]; then
  	logit INFO "Uploaded to S3 successfully"
    exit 0
  else
    logit ERROR "Error copying to S3"
  fi
  rm ${FIEL}.gz
else
  logit ERROR "Error backing up mysql"
fi
exit 0