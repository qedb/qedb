FROM postgres:9.6-alpine
RUN apk update && apk add pllua &&\
 cp /usr/lib/postgresql/pllua.so /usr/local/lib/postgresql/pllua.so &&\
 cp /usr/share/postgresql/extension/pllua--1.0.sql /usr/local/share/postgresql/extension/pllua--1.0.sql &&\
 cp /usr/share/postgresql/extension/pllua.control /usr/local/share/postgresql/extension/pllua.control
COPY repositories.txt /etc/apk/repositories
RUN apk update && apk add postgresql-plperl &&\
 cp /usr/lib/postgresql/plperl.so /usr/local/lib/postgresql/plperl.so &&\
 cp /usr/share/postgresql/extension/plperl--1.0.sql /usr/local/share/postgresql/extension/plperl--1.0.sql &&\
 cp /usr/share/postgresql/extension/plperl.control /usr/local/share/postgresql/extension/plperl.control
