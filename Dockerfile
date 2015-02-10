FROM muconsulting/java7
MAINTAINER Sylvain Gibier <sylvain@munichconsulting.de>

ENV DEBIAN_FRONTEND noninteractive

RUN \
    wget -O - http://packages.elasticsearch.org/GPG-KEY-elasticsearch | apt-key add - && \
    echo 'deb http://packages.elasticsearch.org/elasticsearch/1.3/debian stable main' | tee /etc/apt/sources.list.d/elasticsearch.list && \
    echo 'deb http://packages.elasticsearch.org/logstash/1.4/debian stable main' | tee /etc/apt/sources.list.d/logstash.list && \
    apt-get -y update

RUN apt-get install -y supervisor 

# Installattion elasticseach + configuration

RUN apt-get -y install elasticsearch && \
    apt-get clean && \
    sed -i '/#cluster.name:.*/a cluster.name: logstash' /etc/elasticsearch/elasticsearch.yml && \
    sed -i '/#path.data: \/path\/to\/data/a path.data: /data' /etc/elasticsearch/elasticsearch.yml

ADD files/etc/supervisor/conf.d/elasticsearch.conf /etc/supervisor/conf.d/elasticsearch.conf

# Installation logstash
RUN apt-get -y install logstash && \
    apt-get clean

ADD files/etc/supervisor/conf.d/logstash.conf /etc/supervisor/conf.d/logstash.conf
ADD files/opt/logstash/lib/logstash/inputs/ /opt/logstash/lib/logstash/inputs/
ADD files/opt/logstash/lib/logstash/outputs/ /opt/logstash/lib/logstash/outputs/
ADD files/etc/logstash/conf.d   /etc/logstash/conf.d

RUN rm /opt/logstash/lib/logstash/outputs/elasticsearch/elasticsearch-template.json && \
    mv /opt/logstash/lib/logstash/outputs/elasticsearch/elasticsearch-template-with-ttl.json /opt/logstash/lib/logstash/outputs/elasticsearch/elasticsearch-template.json

# Installation of Nginx + Kibana
# Kibana
RUN \
    apt-get install -y nginx && \
	if ! grep "daemon off" /etc/nginx/nginx.conf; then sed -i '/worker_processes.*/a daemon off;' /etc/nginx/nginx.conf;fi && \
	mkdir -p /var/www && \
	wget -O kibana.tar.gz https://download.elasticsearch.org/kibana/kibana/kibana-3.1.2.tar.gz && \
    tar xzf kibana.tar.gz -C /opt && \
    ln -s /opt/kibana-3.1.2 /var/www/kibana


RUN sed -i 's/"http:\/\/"+window.location.hostname+":9200"/"http:\/\/"+window.location.hostname+":"+window.location.port/' /opt/kibana-3.1.2/config.js

# configure nginx
ADD files/etc/supervisor/conf.d/nginx.conf /etc/supervisor/conf.d/nginx.conf
ADD files/etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/default


# Add scripts
ADD scripts /scripts
RUN chmod +x /scripts/*.sh
RUN touch /.firstrun


VOLUME [ "/data" ]

EXPOSE 12201/tcp
EXPOSE 80

CMD ["/scripts/run.sh"]

