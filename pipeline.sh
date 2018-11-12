#!/bin/sh

THIS_DIR_PATH=$(dirname `realpath "$0"`)

#abort on error
set -e

function usage() {
  echo "Usage: $0 [[--usePercentsOfFile|-u] (0,100>]] [[--properties|-p] <propertiesFile.properties>] {[[--inputFile|-i] <filepath.[fastq.gz|fq.gz|fq|fastq]>] ...} " 1>&2; exit 1;
}

function usageAlreadySet() {
  echo "$1 already set"
  usage
}


function parse_args
{

  while getopts "p:u:i:-:" o; do
    case "${o}" in
      u)
        [ -z ${usePercentsOfFile_} ] || usageAlreadySet "usePercentsOfFile"
        usePercentsOfFile=${OPTARG}
        [ $(echo "${usePercentsOfFile_}<=100" | bc -l) -eq 1 ] && [ $(echo "$u>0" | bc -l) -eq 1 ] || usage
        ;;
      p)
        properties=${OPTARG}
        ;;
      i)
        inputFiles+=("$OPTARG")
        ;;
      -)
        echo "Long OPTIND: ${OPTIND} OPTARG: ${OPTARG}"
        case "${OPTARG}" in
          usePercentsOfFile)
            [ -z ${usePercentsOfFile_} ] || usageAlreadySet "usePercentsOfFile"
            #usePercentsOfFile=${OPTARG}
            usePercentsOfFile_="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
            echo "usePercentsOfFile: ${usePercentsOfFile_}"
            [ $(echo "${usePercentsOfFile_}<=100" | bc -l) -eq 1 ] && [ $(echo "${usePercentsOfFile_}>0" | bc -l) -eq 1 ] || usage
            ;;
          propertiesFile)
            [ -z $propertiesFile_ ] || usageAlreadySet "usePercentsOfFile"
            propertiesFile_="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
            ;;
          inputFile)
            inputFile_="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
            inputFiles+=("$inputFile_")
            ;;
          *)
            if [ "$OPTERR" = 1 ] && [ "${optspec:0:1}" != ":" ]; then
              echo "Unknown option --${OPTARG}" >&2
            fi
            ;;
        esac;;
      *)
        usage
        ;;
    esac
  done
  shift $((OPTIND-1));

  usePercentsOfFile=$usePercentsOfFile_
  propertiesFile=$propertiesFile_

  if [ -z "${usePercentsOfFile}" ] || [ -z "${propertiesFile}" ] || [ -z "${inputFiles}" ]; then
    if [ -z "${usePercentsOfFile}" ] ; then
      echo "Missing usePercentsOfFile parameter";
    fi
    if [ -z "${propertiesFile}" ] ; then
      echo "Missing propertiesFile parameter";
    fi
    if [ -z "${inputFiles}" ] ; then
      echo "Missing inputFiles parameter";
    fi
    usage
  fi

}

# reads cached value by its name \$2 from file \$1 stored in cache dir in workspace
function getCachedValue(){
  cacheFileName=$1
  propertyKey=$2
  cachedFilePath=${CACHE_DIR_PATH}/${cacheFileName}.cached.properties
  if [ ! -f "$cachedFilePath" ]; then
    return
  fi
  propValue=`cat $cachedFilePath | grep "$propertyKey" `
  echo "${propValue/${propertyKey}=/}"
}

# reads cached value by its name \$2 from file \$1 stored in cache dir in workspace
function setCachedValue(){
  cacheFileName=$1
  propertyKey=$2
  propertyValue=$3
  cachedFilePath=${CACHE_DIR_PATH}/${cacheFileName}.cached.properties
  if [ ! -f "$cachedFilePath" ]; then
    touch $cachedFilePath
  fi
  echo "${propertyKey}=${propertyValue}" >>  ${cachedFilePath}
}

# https://www.biostars.org/p/9610/
# take \$1 as filePath
function getReadsCount(){
  echo "Filepath $1"
  filepath=$1
  filename=$(basename $filepath)

  cachedKey="READS_COUNT"
  cachedValue=`getCachedValue $filename "$cachedKey"`

  if [ ! -z $cachedValue ]; then
    echo "$cachedValue"
    return
  fi
  exit
  ext=${filename##*\.}
  case "$ext" in
    fastq.gz|fq.gz)
      #echo "$filename : "
      # for 4GB compressed file it took few minutes -> caching
      zcat $filepath | echo $((`wc -l`/4))
      ;;
    *)
      # do nothing
      #echo " $filename : "
      ;;
  esac
  setCachedValue ${filename} ${cachedKey} ${cachedValue}
}

# prints parameters and atirbutes at start of script executions
function echoParameters(){
  echo "WORKSPACE_PATH = ${WORKSPACE_PATH}"

  echo "usePercentsOfFile = ${usePercentsOfFile}"
  echo "propertiesFile = ${propertiesFile}"
  for inputFile in "${inputFiles[@]}"
  do
     echo "inputFile = ${inputFile}"
     readsCount=$(getReadsCount ${inputFile})
     echo -e "\treadsCount: $readsCount"
  done
}

# as name says this method loads workspace
# loads:
# properties from properties file
# prepare directory structure - for workspace and cache
function loadWorkspace(){
  source $propertiesFile
  echo "WORKSPACE_PATH: $WORKSPACE_PATH"
  if [ ! -d "$WORKSPACE_PATH" ]; then
    mkdir -p $WORKSPACE_PATH
  fi
  echo "CACHE_DIR_PATH: $CACHE_DIR_PATH"
  CACHE_DIR_PATH="${WORKSPACE_PATH}/cache"
  if [ ! -d "$CACHE_DIR_PATH" ]; then
    mkdir $CACHE_DIR_PATH
  fi
}


# this function handles tirmgalore input and output
function processTrimGalore(){
  # TODO move parameters to properties file
  # ./trim_galore --paired ../data/SRR6000947_1.fastq.gz ../data/SRR6000947_2.fastq.gz
  trimgalorInputFiles=""
  for inputFile in "${inputFiles[@]}"
  do
    trimgalorInputFiles="${trimgalorInputFiles} ${inputFile}"
  done

  TRIMGALOR_WORKSPACE_PATH="${WORKSPACE_PATH}/trimgalore-results"
  if [ ! -d ${TRIMGALOR_WORKSPACE_PATH} ] ; then
    mkdir -p ${TRIMGALOR_WORKSPACE_PATH}
  fi
  ${TRIMGALORE_PATH} --paired -q 25 ${trimgalorInputFiles} -o ${TRIMGALOR_WORKSPACE_PATH}
}

function processFastQC(){
  fastqcInputFiles=""
  for inputFile in "${inputFiles[@]}"
  do
    fastqcInputFiles="${fastqcInputFiles} ${inputFile}"
  done

  FASTQC_WORKSPACE_PATH="${WORKSPACE_PATH}/trimgalore-results"
  if [ ! -d ${FASTQC_WORKSPACE_PATH} ] ; then
    mkdir -p ${FASTQC_WORKSPACE_PATH}
  fi

  # TODO magic if missing value then pass it as function parameter

}


function processSeqtk(){
  # get input as arrays
  inputFiles_=("$@")
  SEQTK_WORKSPACE_PATH="${WORKSPACE_PATH}/seqtk-results"
  if [ ! -d ${SEQTK_WORKSPACE_PATH} ] ; then
    mkdir -p ${SEQTK_WORKSPACE_PATH}
  fi

  for inputFile_ in "${inputFiles_[@]}"
  do
    filename=$(basename -- "$inputFile_")
    extension="${filename##*.}"
    filenameNoExt="${filename%.*}"
    readsCount=$(getReadsCount ${inputFile_})
    seqCount=$(( ${readsCount}*${usePercentsOfFile} ))

    SEQTK_OUTPUT_FILE_PATH=${SEQTK_WORKSPACE_PATH}/${filenameNoExt}-seqtk-${usePercentsOfFile}.fq
    if [ -f ${SEQTK_OUTPUT_FILE_PATH} ]; then
      # TODO add flag that will remove old if exists
      #rm -rf ${SEQTK_OUTPUT_FILE_PATH}
      echo "File ${SEQTK_OUTPUT_FILE_PATH} already exists skipping"
    else
      ${SEQTK_PATH} sample -s100 ${inputFile} ${seqCount} > ${SEQTK_OUTPUT_FILE_PATH}
    fi
    #seqtkInputFiles="${seqtkInputFiles} ${inputFile}"

    #${SEQTK_PATH} sample -s100 SRR6000947_2.fastq.gz 2341316 > SRR6000947_2.fastq-seqtk-0.05.fq
  done


  #${SEQTK_PATH} sample -s100 SRR6000947_1.fastq.gz 2341316 > SRR6000947_1.fastq-seqtk-0.05.fq

  #${SEQTK_PATH} sample -s100 SRR6000947_2.fastq.gz 2341316 > SRR6000947_2.fastq-seqtk-0.05.fq


  #those files with better quality
  # SRR6000947_1_val_1.fq.gz
  # SRR6000947_2_val_2.fq.gz

  #${SEQTK_PATH} sample -s100 SRR6000947_1_val_1.fq.gz 2341316 > SRR6000947_1_eval_1-seqtk-0.05.fq

  #${SEQTK_PATH} sample -s100 SRR6000947_2_val_2.fq.gz 2341316 > SRR6000947_2_eval_2-seqtk-0.05.fq

}


function run()
{
  parse_args "$@"
  loadWorkspace
  echoParameters

  processTrimGalore
  # TODO FASTQC
  # processFastQC
  processSeqtk

}

run "$@";
