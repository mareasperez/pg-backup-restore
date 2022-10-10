# postgresql image 
FROM postgres

# set the working directory
WORKDIR /usr/src/app
COPY transfer.sql /usr/src/app/
EXPOSE 5432
