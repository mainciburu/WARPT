# WARPT
Workflow for Association of Receptor Pairs from TREK-seq


### Set up and run Docker container
1. Clone Github repository to your local disk
2. From the top directory, build the docker image using `docker build`
3. Start the container using `docker run`


### Test run
From within the Docker container, perform test run as follows
```
warpt -b /usr/local/test/data/BCseq_sub1.fastq.gz -t /usr/local/test/data/TCRseq_sub1.fastq.gz
```