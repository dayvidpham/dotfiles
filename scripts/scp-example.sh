#!/usr/bin/env sh

# remote to local
scp -P <port_number> minttea@<remote_ip>:/home/minttea/where/its/needed/something.txt /home/minttea/somewhere/something.txt

# local to remote
scp -P <port_number> /home/minttea/somewhere/something.txt minttea@<remote_ip>:/home/minttea/where/its/needed/something.txt

