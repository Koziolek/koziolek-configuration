FROM ubuntu:22.04

COPY setup.sh .
RUN chmod +x setup.sh

CMD ./setup.sh
