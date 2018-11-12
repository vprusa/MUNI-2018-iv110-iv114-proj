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
        [ -z ${usePercentsOfFile_+x} ] || usageAlreadySet "usePercentsOfFile"
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
            [ -z ${usePercentsOfFile_+x} ] || usageAlreadySet "usePercentsOfFile"
            #usePercentsOfFile=${OPTARG}
            usePercentsOfFile_="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
            echo "usePercentsOfFile: ${usePercentsOfFile_}"
            [ $(echo "${usePercentsOfFile_}<=100" | bc -l) -eq 1 ] && [ $(echo "${usePercentsOfFile_}>0" | bc -l) -eq 1 ] || usage
            ;;
          propertiesFile)
            [ -z ${propertiesFile_+x} ] || usageAlreadySet "usePercentsOfFile"
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

  if [ -z ${usePercentsOfFile+x} ] || [ -z ${propertiesFile+x} ] || [ -z ${inputFiles+x} ]; then
    if [ -z ${usePercentsOfFile+x} ] ; then
      echo "Missing usePercentsOfFile parameter";
    fi
    if [ -z ${propertiesFile+x} ] ; then
      echo "Missing propertiesFile parameter";
    fi
    if [ -z ${inputFiles+x} ] ; then
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
  filepath=$1
  filename=$(basename $filepath)

  cachedKey="READS_COUNT"
  cachedValue=`getCachedValue $filename "$cachedKey"`

  if [ ! -z $cachedValue ]; then
    echo "$cachedValue"
    return
  fi
  # TODO remove return
  return
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
  echo "inputFiles:"
  for inputFile in "${inputFiles[@]}"
  do
    #echo "inputFile = ${inputFile}"
     echo -e "\t${inputFile}"
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
  # TODO move parameters to function arguments and/or properties file
  # ./trim_galore --paired ../data/SRR6000947_1.fastq.gz ../data/SRR6000947_2.fastq.gz
  local -n inputFiles_=$1

  trimgalorInputFiles=""
  for inputFile in "${inputFiles_[@]}"
  do
    trimgalorInputFiles="${trimgalorInputFiles} ${inputFile}"
  done

  TRIMGALOR_WORKSPACE_PATH="${WORKSPACE_PATH}/trimgalore-results"
  if [ ! -d ${TRIMGALOR_WORKSPACE_PATH} ] ; then
    mkdir -p ${TRIMGALOR_WORKSPACE_PATH}
  else
    # move
    rm -rf "${TRIMGALOR_WORKSPACE_PATH}.old"
    mv "${TRIMGALOR_WORKSPACE_PATH}" "${TRIMGALOR_WORKSPACE_PATH}.old"
    mkdir -p ${TRIMGALOR_WORKSPACE_PATH}
  fi

  # TODO check files existence
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
  local -n inputFiles_=$1
  local -n globalReadsCount_=$2
  local -n usePercentsOfFile_=$3

  SEQTK_WORKSPACE_PATH="${WORKSPACE_PATH}/seqtk-results"
  if [ ! -d ${SEQTK_WORKSPACE_PATH} ] ; then
    mkdir -p ${SEQTK_WORKSPACE_PATH}
  fi

  for inputFile_ in "${inputFiles_[@]}"
  do
    filename=$(basename -- "$inputFile_")
    extension="${filename##*.}"
    filenameNoExt="${filename%.*}"
    if [ ! -z ${globalReadsCount_+x} ] ; then
      readsCount=$globalReadsCount_
    else
      readsCount=$(getReadsCount ${inputFile_})
    fi
    expr="scale = 4; ${readsCount} * ${usePercentsOfFile_}/100"
    seqCount=$(bc -l <<< $expr)

    SEQTK_OUTPUT_FILE_PATH=${SEQTK_WORKSPACE_PATH}/${filenameNoExt}-seqtk-${usePercentsOfFile_}.fq
    if [ -f ${SEQTK_OUTPUT_FILE_PATH} ]; then
      # TODO add flag that will remove old if exists
      echo "File ${SEQTK_OUTPUT_FILE_PATH} already exists - removing"
      rm -rf ${SEQTK_OUTPUT_FILE_PATH}
    fi
    echo "Executing seqtk for file: ${inputFile} > ${SEQTK_OUTPUT_FILE_PATH}"
    ${SEQTK_PATH} sample -s100 ${inputFile} ${seqCount} > ${SEQTK_OUTPUT_FILE_PATH}


  done
}


function run()
{
  parse_args "$@"
  loadWorkspace
  echoParameters

  # TODO better way how to say that there is just one readCount?
  globalReadsCount=$(getReadsCount ${inputFiles[0]})

  # TODO fix
  processTrimGalore inputFiles
  # TODO FASTQC
  #processFastQC

  processSeqtk inputFiles globalReadsCount usePercentsOfFile

  # TODO ? process evaluated files with fastqc?
  #processSeqtk inputFilesWithBetterQualityArray globalReadsCount usePercentsOfFile
}

run "$@";
