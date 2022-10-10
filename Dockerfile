# postgresql image 
FROM postgres:lastest

# set the working directory
WORKDIR /usr/src/app
COPY transfer.sql /usr/src/app/transfer.sql
EXPOSE 5432
