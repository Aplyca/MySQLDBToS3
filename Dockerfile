FROM infrastructureascode/aws-cli

LABEL maintainer="Aplyca"

WORKDIR /usr/app

RUN apk --quiet --progress --update --no-cache add mysql-client

ENV MYSQL_PORT 3306

COPY ./backup-script.sh /usr/app/

CMD ["sh","/usr/app/backup-script.sh","-v"]
