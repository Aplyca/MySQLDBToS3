FROM infrastructureascode/aws-cli

LABEL maintainer="Aplyca"

WORKDIR /usr/app

RUN apk --quiet --progress --update --no-cache add mysql-client curl

ADD ./ /usr/app/

ENTRYPOINT ["sh","/usr/app/docker-entrypoint.sh"]

CMD ["-s"]
