#############################################
### WARPT pipeline
#############################################


#!/bin/bash

###################################### Help ################################################
Help()
{
   # Display Help
   echo
   echo "Workflow for Association of Receptor Pairs from TREK-seq"
   echo
   echo "Help:"
   echo "Syntax: warpt.sh [--bc --tcr --sample --rna --wd]"
   echo "options:"
   echo "   -h     Print this Help."
   echo "   -b     cell barcode and UMI fastq.gz full path and name"
   echo "   -t     tcr sequence fastq.gz full path and name"
   echo "   -d     working directory for analysis"
   echo "   -c     skip barcode correction"
   echo "   -u     skip UMI correction"
   echo "   -q     quality score threshold (default is 25)"
   echo "   -i     cluster identity threshold (default is 0.9)"
   echo "   -e     max error for consensus (default is 0.5)"
   echo "   -g     max gap for consensus (default is 0.5)"
   echo "   -o     organism (default is human)"
   echo "   -p     number of processors"

}

################################ Default variables ########################################

BCfastq="bc fastq"
TCRfastq="tcr fastq"
BaseFolder=$(pwd)
CorrectBC=true
CorrectUMI=true
MyQScore=25
MyIdentity=0.9
MyMaxError=0.5
MyMaxGap=0.5
MyOrganism="human"
MyCoreNumber=1

####################################### Options ###########################################

while getopts ":hb:t:d:c:u:q:i:e:g:p:" option; do
   case $option in
      h) # display Help
         Help
         exit;;
      b) 
         BCfastq=$OPTARG;;
      t) 
         TCRfastq=$OPTARG;;
      d) 
         BaseFolder=$OPTARG;;
      c) 
         CorrectBC=false;;
      u) 
         CorrectUMI=false;;
      q) 
         MyQScore=$OPTARG;;
      i) 
         MyIdentity=$OPTARG;;
      e) 
         MyMaxError=$OPTARG;;
      g) 
         MyMaxGap=$OPTARG;; 
      o) 
         MyOrganism=$OPTARG;; 
      p) 
         MyCoreNumber=$OPTARG;;
      :)    # If expected argument omitted:
         echo "Error: -${OPTARG} requires an argument."
         exit;;
      \?) # Invalid option
         echo "Error: Invalid option $OPTARG. Try warpt.sh -h"
         exit;;
   esac
done



# create folders
if [ ! -e ${BaseFolder}/fastq_processed/ ]; then
	mkdir ${BaseFolder}/fastq_processed/
fi

if [ ! -e ${BaseFolder}/warpt/ ]; then
	mkdir ${BaseFolder}/warpt/
	mkdir ${BaseFolder}/warpt/QC/
fi


# Log file 
touch ${BaseFolder}/warpt/warpt.log
echo "REFORMATING FASTQ FILES \n" 2>&1 | tee -a ${BaseFolder}/warpt/warpt.log

# Rearrange Fastq --------------------------------
cd ${BaseFolder}/fastq_processed/

## Get Cell barcode + UMI
zcat ${BCfastq} | awk 'NR%4==2' > "BCSeq.txt"

## Cell Barcode + UMI quality
zcat ${BCfastq} | awk 'NR%4==0' > "BCQC.txt"

## Get TCR sequence
zcat ${TCRfastq} | awk 'NR%4==2' > "TCRSeq.txt" 

## Get TCR quality 
zcat ${TCRfastq} | awk 'NR%4==0' > "TCRQC.txt"  

## Get header 
zcat ${BCfastq} | awk 'NR%4==1' | awk 'BEGIN{FS=" "};{print $1};END{}' > "seqHeaders.txt" 

## Add BC - UMI to header
paste -d ":" "seqHeaders.txt" "BCSeq.txt"  > "seqHeaders_BC.txt"

## Add qualHeader (line 3)
sed 's~@~+~' "seqHeaders.txt" > "qualHeaders.txt"

## Correct barcodes
if [ ${CorrectBC} = true ]; then
	echo "CORRECTING BARCODES \n" 2>&1 | tee -a ${BaseFolder}/warpt/warpt.log
	CorrectBC.py -b BCSeq.txt  \
					 -w /usr/local/3M-february-2018.txt.gz \
					 -d 1 \
					 -r 8 \
					 -o BCcorrected 2>&1 | tee -a ${BaseFolder}/warpt/warpt.log
	## extract UMIs and join to corrected barcodes
	cat BCSeq.txt | awk '{print substr($0,17)}' > UMI.txt
	paste -d '' BCcorrected.txt UMI.txt > BCcorrectedUMI.txt

	## Mask every UMI with no valid barcode
	cat BCcorrectedUMI.txt | sed '/NNNNNNNNNNNNNNNN/c\NNNNNNNNNNNNNNNNNNNNNNNNNNNN' > BCcorrectedUMImasked.txt 
	
	## Correct UMIs
	if [ ${CorrectUMI} = true ]; then
		echo "CORRECTING UMI \n" 2>&1 | tee -a ${BaseFolder}/warpt/warpt.log
		CorrectUMI.py -b BCcorrectedUMImasked.txt \
						  -o UMIcorrected 2>&1 | tee -a ${BaseFolder}/warpt/warpt.log
		## Join corrected BC and UMI
		paste -d '' BCcorrected.txt UMIcorrected.txt > BCSeq_final.txt

	fi

	## Or skip UMI correction
	if [ ${CorrectUMI} = false ]; then
		echo "SKIPING CORRECTING UMI \n" 2>&1 | tee -a ${BaseFolder}/warpt/warpt.log
		mv BCcorrectedUMImasked.txt BCSeq_final.txt

	fi

fi

## Skip barcode correction
if [ ${CorrectBC} = false ]; then
	echo "SKIPING CORRECTING BARCODES \n" 2>&1 | tee -a ${BaseFolder}/warpt/warpt.log
		
	## Correct UMIs
	if [ ${CorrectUMI} = true ]; then
		echo "CORRECTING UMI \n" 2>&1 | tee -a ${BaseFolder}/warpt/warpt.log
		CorrectUMI.py -b BCSeq.txt \
						  -o UMIcorrected 2>&1 | tee -a ${BaseFolder}/warpt/warpt.log
		# Extract BC
		cat BCSeq.txt | awk '{print substr($0,0,16)}' > BC.txt
		# Join BC and corrected UMI
		paste -d '' BC.txt UMIcorrected.txt > BCSeq_final.txt

	fi

	## Or skip UMI correction
	if [ ${CorrectUMI} = false ]; then
		echo "SKIPING CORRECTING UMI \n" 2>&1 | tee -a ${BaseFolder}/warpt/warpt.log
		cp BCSeq.txt BCSeq_final.txt

	fi

fi


## New fastq
paste -d '' BCSeq_final.txt TCRSeq.txt > Read1.txt
paste -d '' BCQC.txt TCRQC.txt > Read1_Q.txt
paste -d '\n' seqHeaders.txt Read1.txt qualHeaders.txt Read1_Q.txt > sample.fastq

## Remove reads with NNNN...N in BC + UMI

cat sample.fastq | paste - - - - | awk -F '\t' '{if ($2 !~/^NNNNNNNNNNNNNNNNNNNNNNNNNNNN/){ print $0}}'| tr "\t" "\n" > sample_filtered.fastq

mv sample_filtered.fastq ${BaseFolder}/warpt/

### --------------------------------------------------------------------------

cd ${BaseFolder}/warpt/

# 1) Find barcodes and convert them in tag
# MaskPrimers extract => look for the barcodes in a fixed sequence region
	# -s: input fastq
	# --start: starting position of the sequence to extract
	# --len: lenght of the sequence to extract
	# --pf: name for the resulting tag containing the barcode
	# --mode cut: remove barcode region from sequence
	# --failed: creates file containing records that failed

MaskPrimers.py extract -s sample_filtered.fastq --start 0 --len 28 --pf BARCODE --mode cut --failed --log MP.log --nproc ${MyCoreNumber} 2>&1 | tee -a ${BaseFolder}/warpt/warpt.log

# Count Ns per line
cat sample_filtered_primers-pass.fastq | awk 'NR%4==2' | grep -o -n 'N' | cut -d : -f 1 | uniq -c > QC/ns.txt

# Q average score per read
cat sample_filtered_primers-pass.fastq | perl -ne 'chomp;print;<STDIN>;<STDIN>;$_ = <STDIN>;map{ $score += ord($_)-33} 
split(""); print " " .($score/length($_))."\n";$score=0;' > QC/qscore.txt

## QC Plots: N number and Q score
QCplots_preFiltering.r $BaseFolder

# 2) Quality filter
	# -q: quality score threshold
	# -s: input fastq	
	# --failed: creates file containing records that failed

FilterSeq.py quality -q ${MyQScore} -s sample_filtered_primers-pass.fastq --failed --log FS.log --nproc ${MyCoreNumber} 2>&1 | tee -a ${BaseFolder}/warpt/warpt.log


# 3) Cluster sequences with same BC+UMI => discard products of barcode swapping
	# -s: input sequence
	# -f: annotation field used for grouping
	# -k: output field name
	# --ident: sequence identity threshold for the uclust algorithm

ClusterSets.py set -s sample_filtered_primers-pass_quality-pass.fastq -f BARCODE -k CLUSTER --log CS.log --failed --ident ${MyIdentity} --exec /usr/local/bin/usearch 2>&1 | tee -a ${BaseFolder}/warpt/warpt.log

# Join BARCODE and CLUSTER header tags
ParseHeaders.py merge -s sample_filtered_primers-pass_quality-pass_cluster-pass.fastq -f BARCODE CLUSTER -k BARCODE_CLUSTER --delim "|" "=" "_" 2>&1 | tee -a ${BaseFolder}/warpt/warpt.log

# Extract BC + UMI + cluster
cat sample_filtered_primers-pass_quality-pass_cluster-pass_reheader.fastq | awk 'NR%4==1' | awk 'BEGIN{FS="="};{print $4};END{}' > "${BaseFolder}/fastq_processed/BCSeq_final_filtered_qfiltered_cluster.txt" 

## QC plots: cluster proportion and ratio
QCplots_clustering.r $BaseFolder

# 4) Determines consensus for each BC/UMI
	# -s: input fastq	
	# --bf: tag by which to group sequences
	# -n: minimun number of sequences required to define a consensus
	# --maxerror: calculate error rate (number of missmatches) per consensus and remove groups exceding the given value
	# --maxgap: frequency of allowed gap values for each position. Positions exceeding the threshold are deleted from the consensus

BuildConsensus.py -s sample_filtered_primers-pass_quality-pass_cluster-pass_reheader.fastq  --bf BARCODE_CLUSTER -n 3 --maxerror ${MyMaxError} --maxgap ${MyMaxGap} --outname consensus --log BC.log --failed --nproc ${MyCoreNumber} 2>&1 | tee -a ${BaseFolder}/warpt/warpt.log

nreads=$(cat  BC.log | grep "SEQCOUNT" | awk -F " " '{sum+=$2};END{print sum}')   ## count number of sequences reviewed

echo "Reads used for consensus building: ${nreads} \n" 2>&1 | tee -a ${BaseFolder}/warpt/warpt.log

# convert consensus fastq into fasta
paste - - - - < consensus_consensus-pass.fastq | cut -f 1,2 | sed 's/^@/>/' | tr "\t" "\n" > sample.fa


# 5) Align consensus with igblast => assign VDJ genes
	# --loci tr: look for T cell receptor
	# --format blast: output format
	# -b: IgBLAST database directory

AssignGenes.py igblast -s sample.fa --organism ${MyOrganism} --loci tr --format blast -b /usr/igblast 2>&1 | tee -a ${BaseFolder}/warpt/warpt.log

# 6) Create database file to store alignment results
	# -i: alignment output file 
	# -s: consensus file
	# -r: directory to alginment reference sequences
	# --extended: include additional aligner specific fields in the output
	# --partial: include incomplete V(D)J alignments

MakeDb.py igblast -i sample_igblast.fmt7 -s sample.fa -r /usr/germlines/imgt/${MyOrganism}/vdj/ --log MDB.log --extended --failed --partial 2>&1 | tee -a ${BaseFolder}/warpt/warpt.log

# sum up consensus log
ParseLog.py -l BC.log -o stats.log -f BARCODE SEQCOUNT CONSCOUNT ERROR 2>&1 | tee -a ${BaseFolder}/warpt/warpt.log

