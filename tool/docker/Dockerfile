FROM postgres:9.6-alpine
COPY setup.sql /docker-entrypoint-initdb.d
RUN apk update && apk add pllua
RUN cp /usr/lib/postgresql/pllua.so /usr/local/lib/postgresql/pllua.so && \
    cp /usr/share/postgresql/extension/pllua--1.0.sql /usr/local/share/postgresql/extension/pllua--1.0.sql && \
    cp /usr/share/postgresql/extension/pllua.control /usr/local/share/postgresql/extension/pllua.control
# cp /usr/lib/postgresql/plperl.so /usr/local/lib/postgresql/plperl.so && \
# cp /usr/share/postgresql/extension/plperl--1.0.sql /usr/local/share/postgresql/extension/plperl--1.0.sql && \
# cp /usr/share/postgresql/extension/plperl--unpackaged--1.0.sql /usr/local/share/postgresql/extension/plperl--unpackaged--1.0.sql && \
# cp /usr/share/postgresql/extension/plperl.control /usr/local/share/postgresql/extension/plperl.control
