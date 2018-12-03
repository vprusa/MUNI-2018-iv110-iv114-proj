#!/bin/sh

THIS_DIR_PATH=$(dirname `realpath "$0"`)

#abort on error
set -e

# global result array, can not use recursion for this
declare -a resultArray

function usage() {
  echo "Usage: $0 [{<-d|--do> <trimgalor|seqtk|fastqc> ...}] [<-u|--usePercentsOfFile> (0,100>]] [<--properties|-p> <propertiesFile.properties>] {[<--inputFile|-i> <filepath.<fastq.gz|fq.gz|fq|fastq>>] ...} " 1>&2; exit 1;
}

function usageAlreadySet() {
  echo "$1 already set"
  usage
}


function parse_args
{

  while getopts "p:u:i:d:-:" o; do
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
      d)
        doProcess+=("$OPTARG")
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
          do)
            doProcess_="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
            doProcess+=("$doProcess_")
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
  TRIMGALORE_WORKSPACE_PATH="${WORKSPACE_PATH}/trimgalore-results"
  SEQTK_WORKSPACE_PATH="${WORKSPACE_PATH}/seqtk-results"
  FASTQC_WORKSPACE_PATH="${WORKSPACE_PATH}/fastqc-results"
  DIAMOND_WORKSPACE_PATH="${WORKSPACE_PATH}/diamond-results"
  VELVET_WORKSPACE_PATH="${WORKSPACE_PATH}/velvet-results"
  METAVELVET_WORKSPACE_PATH="${WORKSPACE_PATH}/metavelvet-results"
  MEGAN6_WORKSPACE_PATH="${WORKSPACE_PATH}/megan6-results"

  echo "CACHE_DIR_PATH: $CACHE_DIR_PATH"
  CACHE_DIR_PATH="${WORKSPACE_PATH}/cache"
  if [ ! -d "$CACHE_DIR_PATH" ]; then
    mkdir $CACHE_DIR_PATH
  fi
}

function echoDateTime(){
  echo `date +%Y-%m-%d_%H-%M-%S`
}

function backupWorkspace(){
  local -n workspacePath=$1

  if [ -d ${workspacePath} ]; then
    # TODO add flag that will remove old if exists, also use one echoDateTime across whole script run
    echo "File ${workspacePath} already exists - backing up"
    mv ${workspacePath} "${workspacePath}.bkp."`echoDateTime`
    mkdir -p ${workspacePath}
  else
    mkdir -p ${workspacePath}
  fi

}

# this function handles tirmgalore input and output
function processTrimGalore(){
  # TODO move parameters to function arguments and/or properties file
  # ./trim_galore --paired ../data/SRR6000947_1.fastq.gz ../data/SRR6000947_2.fastq.gz
  local -n inputFiles_=$1

  trimgaloreInputFiles=""
  for inputFile in "${inputFiles_[@]}"
  do
    trimgaloreInputFiles="${trimgaloreInputFiles} ${inputFile}"
  done

  backupWorkspace ${TRIMGALORE_WORKSPACE_PATH}

  # TODO check files existence
  ${TRIMGALORE_PATH} --paired -q ${TRIMGALORE_PARAM_Q} ${trimgaloreInputFiles} -o ${TRIMGALORE_WORKSPACE_PATH}
}

function processFastQC(){
  fastqcInputFiles=""
  for inputFile in "${inputFiles[@]}"
  do
    fastqcInputFiles="${fastqcInputFiles} ${inputFile}"
  done

  if [ ! -d ${FASTQC_WORKSPACE_PATH} ] ; then
    mkdir -p ${FASTQC_WORKSPACE_PATH}
  fi

  # TODO magic if missing value then pass it as function parameter
}

function getTrimgalorsResultsAsArray(){
  local -n inputFiles_=$1

  for inputFile in "${inputFiles_[@]}"
  do
    filename=$(basename $inputFile)
    filenameNoExt="${filename%.*}"
    filenameNoExt="${filenameNoExt%.*}"
    mayBeTrimmedFile=`ls ${TRIMGALORE_WORKSPACE_PATH} | grep ${filenameNoExt} | grep "trimmed"`
    trimmedFilePath=${TRIMGALORE_WORKSPACE_PATH}/${mayBeTrimmedFile}
    echo "trimmedFilePath: ${trimmedFilePath}"
    resultArray+=("${trimmedFilePath}")
  done
}

function processSeqtk(){
  local -n inputFiles_=$1
  local -n globalReadsCount_=$2
  local -n usePercentsOfFile_=$3


  backupWorkspace ${SEQTK_WORKSPACE_PATH}

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

    echo "Executing seqtk for file: ${inputFile} > ${SEQTK_OUTPUT_FILE_PATH}"
    ${SEQTK_PATH} sample -s100 ${inputFile} ${seqCount} > ${SEQTK_OUTPUT_FILE_PATH}

  done
}

function processVelvet(){
  local -n inputFiles_=$1

  backupWorkspace ${VELVET_WORKSPACE_PATH}

  inputFilesString=$( IFS=$'\n'; echo "${inputFiles_[*]}" )
  # velveth_de
  #${VELVETH_PATH} ${VELVET_WORKSPACE_PATH} 31 -fastq -shortPaired ${inputFilesString}
  #${VELVETG_PATH} ${VELVET_WORKSPACE_PATH} -exp_cov auto
  ${VELVETH_PATH} ${VELVET_WORKSPACE_PATH} ${VELVETH_PARAMS} ${inputFilesString}
  ${VELVETG_PATH} ${VELVET_WORKSPACE_PATH} ${VELVETG_PARAMS}
  # was -exp_cov 19 byt metavelvet needs -exp_cov auto
}

function processMetaVelvet(){

}


function processDiamond(){
  local -n inputFiles_=$1
  #PARAMTERES_EXT=.f6b${DIAMOND_PARAM_B}p${DIAMOND_PARAM_PROCESSES}

  backupWorkspace ${DIAMOND_WORKSPACE_PATH}

  for inputFile_ in "${inputFiles_[@]}"
  do
    PARAMTERES_EXT=""
    FILE_NAME=$(basename -- "$fullfile")
    filename="${FILE_NAME%.*}"
    #FILE_NAME=SRR6000947_2_eval_2-seqtk-0.05.fa
    ${DIAMOND_PATH} blastx -d ${NR_DMND_FILE_PATH} -q ${inputFile_} -o matches-${filename}${PARAMTERES_EXT}.m8 -f ${DIAMOND_PARAM_F} -b${DIAMOND_PARAM_B} -p ${DIAMOND_PARAM_PROCESSES} > ${DIAMOND_WORKSPACE}diamond-${FILE_NAME}${PARAMTERES_EXT}.log
  done
}

function processMegan6(){

}

# this is the main method that runs everything
function run()
{
  parse_args "$@"
  loadWorkspace
  echoParameters

  if [[ -z $doProcess || -n "${doProcess['trimgalore']}" ]] ; then
    # TODO better way how to say that there is just one readCount?
    globalReadsCount=$(getReadsCount ${inputFiles[0]})

    # TODO fix
    processTrimGalore inputFiles
  fi

  if [[ -z $doProcess || -n "${doProcess['fastqc']}" ]] ; then
    # TODO FASTQC
    #processFastQC
  fi

  # get reuslt files to push them into pipeline - TODO test
  getTrimgalorsResultsAsArray inputFiles

  #copy the array in another one
  trimmedInputFiles=("${resultArray[@]}")
  if [[ -z $doProcess || -n "${doProcess['seqtk']}" ]] ; then
    processSeqtk trimmedInputFiles globalReadsCount usePercentsOfFile
  fi

  if [[ -z $doProcess || -n "${doProcess['velvet']}" ]] ; then
    processVelvet inputFiles
  fi

  # pairs
  if [[ -z $doProcess || -n "${doProcess['metaVelvet']}" ]] ; then
    processMetaVelvet
  fi

  if [[ -z $doProcess || -n "${doProcess['diamond']}" ]] ; then
    processDiamond
  fi

  if [[ -z $doProcess || -n "${doProcess['megan6']}" ]] ; then
    processMegan6
  fi

  # TODO ? process evaluated files with fastqc?
  #processSeqtk inputFilesWithBetterQualityArray globalReadsCount usePercentsOfFile
}

# lets run it with program arguments
run "$@";
