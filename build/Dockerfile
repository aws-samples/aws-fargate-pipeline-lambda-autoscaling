FROM amazonlinux:1

ARG AWS_REGION

COPY . /root/ECSPipeline/

RUN yum -y update
RUN yum -y install tar lzop python36 jq libcurl zip vi findutils openssh-server
RUN rm /usr/bin/python
RUN ln -s /etc/alternatives/python3 /usr/bin/python

RUN curl -O https://bootstrap.pypa.io/get-pip.py && python get-pip.py && pip install awscli 
RUN aws configure set default.region $AWS_REGION
RUN pip install requests numpy pandas Pillow

RUN mkdir -p /root/.ssh
RUN cat /root/ECSPipeline/build/ecs_key.pub >> /root/.ssh/authorized_keys
RUN chmod 600 /root/.ssh/authorized_keys
RUN cp /root/ECSPipeline/build/sshd_config /etc/ssh/sshd_config
RUN chmod 600 /etc/ssh/sshd_config

RUN chown -R root:root /root/ECSPipeline
RUN chmod +x /root/ECSPipeline/ingestion/ingestion.sh
RUN chmod +x /root/ECSPipeline/python/*.py

CMD cd /root/ECSPipeline/ && /bin/bash ./ingestion/ingestion.sh
