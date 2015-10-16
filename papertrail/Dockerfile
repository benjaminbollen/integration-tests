FROM eris/base


# install remote_syslog
RUN curl -L https://github.com/papertrail/remote_syslog2/releases/download/v0.14/remote_syslog_linux_amd64.tar.gz > remote_syslog_linux_amd64.tar.gz
RUN tar xzf ./remote_syslog*.tar.gz
RUN cp ./remote_syslog/remote_syslog /usr/local/bin

ADD log_files.yml /etc/log_files.yml

CMD ["remote_syslog", "-D"]
