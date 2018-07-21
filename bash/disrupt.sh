#!/bin/bash

iptables -A INPUT -s $1 -j DROP 
iptables -A OUTPUT -d $1 -j DROP
sleep $2
iptables -D INPUT -s $1 -j DROP 
iptables -D OUTPUT -d $1 -j DROP
