FROM tez-0.5.0
MAINTAINER Prasanth Jayachandran

USER root

# configure postgres as hive metastore backend
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update
RUN apt-get -yq install postgresql-9.3 libpostgresql-jdbc-java

# create metastore db, hive user and assign privileges
USER postgres
RUN /etc/init.d/postgresql start &&\
    psql --command "CREATE DATABASE metastore;" &&\
    psql --command "CREATE USER hive WITH PASSWORD 'hive';" && \
    psql --command "ALTER USER hive WITH SUPERUSER;" && \
    psql --command "GRANT ALL PRIVILEGES ON DATABASE metastore TO hive;"

# revert back to default user
USER root

# dev tools to build hive trunk
RUN apt-get install -y git 

# install maven
RUN curl -s http://mirror.olnevhost.net/pub/apache/maven/binaries/apache-maven-3.2.1-bin.tar.gz | tar -xz -C /usr/local/
RUN cd /usr/local && ln -s apache-maven-3.2.1 maven

# clone and compile hive
RUN cd /usr/local && git clone https://github.com/apache/hive.git
RUN cd /usr/local/hive && /usr/local/maven/bin/mvn clean install -DskipTests -Phadoop-2,dist
RUN mkdir /usr/local/hive-dist
RUN cd /usr/local/hive && tar -xf packaging/target/apache-hive-0.15.0-SNAPSHOT-bin.tar.gz -C /usr/local/hive-dist

# set hive environment
ENV HIVE_HOME /usr/local/hive-dist/apache-hive-0.15.0-SNAPSHOT-bin
ENV HIVE_CONF $HIVE_HOME/conf
ENV PATH $HIVE_HOME/bin:$PATH

# add postgresql jdbc jar to classpath
RUN ln -s /usr/share/java/postgresql-jdbc4.jar $HIVE_HOME/lib/postgresql-jdbc4.jar

# to avoid psql asking password, set PGPASSWORD
ENV PGPASSWORD hive

# initialize hive metastore db
RUN /etc/init.d/postgresql start &&\
	psql -h localhost -U hive -d metastore -f $HIVE_HOME/scripts/metastore/upgrade/postgres/hive-schema-0.15.0.postgres.sql
RUN /etc/init.d/postgresql start &&\
	psql -h localhost -U hive -d metastore -f $HIVE_HOME/scripts/metastore/upgrade/postgres/hive-txn-schema-0.13.0.postgres.sql

# copy hive configs and log4j properties. By default hive client logs goes to /tmp/logs/hive.log
ADD hive-site.xml $HIVE_CONF/hive-site.xml
ADD hive-log4j.properties $HIVE_CONF/hive-log4j.properties

# set permissions for hive bootstrap file
ADD hive-bootstrap.sh /etc/hive-bootstrap.sh
RUN chown root:root /etc/hive-bootstrap.sh
RUN chmod 700 /etc/hive-bootstrap.sh

ENV BOOTSTRAP /etc/hive-bootstrap.sh

# run hive bootstrap script
CMD ["/etc/hive-bootstrap.sh", "-d"]
