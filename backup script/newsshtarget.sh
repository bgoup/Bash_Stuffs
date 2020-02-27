#!/bin/bash

read -re -p 'Enter a hostname to connect to: ' TARGET_HOSTNAME
ssh-copy-id -i /root/.ssh/id_rsa.pub root@$TARGET_HOSTNAME
