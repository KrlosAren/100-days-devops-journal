#!/bin/bash

echo "Backup script"

zip -r /backup/xfusioncorp_blog.zip /var/www/html/blog

echo "finish zip created"

echo "copy file into server"

scp /backup/xfusioncorp_blog.zip clint@stbkp01.stratos.xfusioncorp.com:/backup/

echo "finished backup"
