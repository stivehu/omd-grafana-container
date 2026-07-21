#!/bin/bash
service apache2 restart
omd start
omd status
tail -f /dev/null
