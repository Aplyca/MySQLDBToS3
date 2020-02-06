FROM infrastructureascode/aws-cli

LABEL maintainer="Aplyca"

WORKDIR /usr/app

RUN apk --quiet --progress --update --no-cache add mysql-client

ARG MYSQL_HOST
ENV MYSQL_HOST ${MYSQL_HOST} 
ENV MYSQL_PORT 3306
ARG MYSQL_USER
ENV MYSQL_USER ${MYSQL_USER}
ARG MYSQL_PASS
ENV MYSQL_PASS ${MYSQL_PASS}
ENV MYSQL_DB "--all-databases"
ENV MYSQL_DUMP_FILE "mysql-backup"

ARG S3_BUCKET
ENV S3_BUCKET ${S3_BUCKET}
ENV S3_DB_BKP_FOLDER "mysql-backup"

COPY ./backup-script.sh /usr/app/

CMD ["sh","/usr/app/backup-script.sh","-v"]
