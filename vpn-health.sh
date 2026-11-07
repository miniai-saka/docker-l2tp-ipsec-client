#!/bin/sh
set -eu
ip -o -4 addr show dev ppp0 scope global | grep -q 'inet '
ip -4 route get 1.1.1.1 | grep -q ' dev ppp0 '
timeout 3 swanctl --list-sas --child l2tp | grep -q 'INSTALLED, TRANSPORT'
