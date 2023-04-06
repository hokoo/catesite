ARG PHP_TAG

FROM wodby/wordpress-php:$PHP_TAG

LABEL maintaner="Igor Tron <public@itron.pro>"

WORKDIR /var/www/html

USER root

RUN echo 'alias ll="ls -l --color"' >>  /etc/bash.bashrc
RUN echo 'alias ll="ls -l --color"' >>  /home/wodby/.bashrc

USER wodby