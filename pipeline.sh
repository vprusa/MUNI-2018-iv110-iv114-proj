#!/bin/bash

#THIS_DIR_PATH=$(dirname `realpath "$0"`)
THIS_DIR_PATH=$(dirname `pwd`)

#abort on error
set -e

# global result array, can not use recursion for this
declare -a resultArray

function usage() {
  echo "Usage: $0 [{<-d|--do> <trimgalor|seqtk|fastqc|diamond|velvet|metavelvet|megan6> ...}] [<--properties|-p> <propertiesFile.properties>] {[<--inputFile|-i> <filepath.<fastq.gz|fq.gz|fq|fastq>>] ...} " 1>&2; exit 1;
}

function usageAlreadySet() {
  echo "$1 already set"
  usage
}


function parse_args
{
  while getopts "p:u:i:d:-:" o; do
    case "${o}" in
      p)
        propertiesFile_=${OPTARG}
        ;;
      i)
        inputFiles+=("$OPTARG")
        ;;
      d)
        doProcess+=("$OPTARG")
        ;;
      -)
        echo "Long OPTIND: ${OPTIND} OPTARG: ${OPTARG}"
        case "${OPTARG}" in
          propertiesFile)
            [ -z ${propertiesFile_+x} ] || usageAlreadySet "-p"
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

  propertiesFile=$propertiesFile_

  if [ -z ${propertiesFile+x} ] || [ -z ${inputFiles+x} ]; then
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
  echo "DRY_RUN = ${DRY_RUN}"

  echo "propertiesFile = ${propertiesFile}"
  echo "inputFiles:"
  for inputFile in "${inputFiles[@]}"
  do
    #echo "inputFile = ${inputFile}"
     echo -e "\t${inputFile}"
     readsCount=$(getReadsCount ${inputFile})
     echo -e "\treadsCount: $readsCount"
  done

  echo "doProcess:"
  for process in "${doProcess[@]}"
  do
    #echo "inputFile = ${inputFile}"
     echo -e "\t${process}"
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
  local workspacePath=$1

  if [ -d ${workspacePath} ]; then
    # TODO add flag that will remove old if exists, also use one echoDateTime across whole script run
    echo "File ${workspacePath} already exists - backing up"
    mv ${workspacePath} "${workspacePath}.bkp.${DRY_RUN}."`echoDateTime`
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
  echo "${TRIMGALORE_PATH} --paired -q ${TRIMGALORE_PARAM_Q} ${trimgaloreInputFiles} -o ${TRIMGALORE_WORKSPACE_PATH}"
  # TODO check files existence
  [ ! -z ${DRY_RUN} ] || ${TRIMGALORE_PATH} --paired -q ${TRIMGALORE_PARAM_Q} ${trimgaloreInputFiles} -o ${TRIMGALORE_WORKSPACE_PATH}
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
  echo "Processing getTrimgalorsResultsAsArray"
  echo "${inputFiles_[@]}"
  for inputFile in "${inputFiles_[@]}"
  do
    #echo "inputFile: $inputFile"
    filename=$(basename $inputFile)
    filenameExt="${filename%.*}"
    filenameNoExt="${filenameExt%.*}"
    filenameNoExt2="${filenameNoExt%.*}" # still may have some extension.????
    filenameMaybeNoExt=filenameNoExt
    filenameNoExt=filenameNoExt2
    echo "filename: ${filename} filenameNoExt: ${filenameNoExt} filenameExt: ${filenameExt}"

    #echo "filenameNoExt: ${filenameNoExt}"
    if [ -z `ls ${TRIMGALORE_WORKSPACE_PATH} | grep "trimmed" | grep ${filenameNoExt}` ] ; then
      #echo "noout"
      continue
    fi

    mayBeTrimmedFile=`ls ${TRIMGALORE_WORKSPACE_PATH}  | grep "trimmed" | grep ${filenameNoExt}`
    #echo "mayBeTrimmedFile:"
    #echo "mayBeTrimmedFile: ${mayBeTrimmedFile}"
    trimmedFilePath=${TRIMGALORE_WORKSPACE_PATH}/${mayBeTrimmedFile}
    #echo "trimmedFilePath: ${trimmedFilePath}"
    resultArray+=("${trimmedFilePath}")
  done
}

function processSeqtk(){
  local -n inputFiles_=$1
  local -n globalReadsCount_=$2

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
    expr="scale = 4; ${readsCount} * ${SEQTK_PARAM_PERCENTS}/100"
    seqCount=$(bc -l <<< $expr)

    SEQTK_OUTPUT_FILE_PATH=${SEQTK_WORKSPACE_PATH}/${filenameNoExt}-seqtk-${SEQTK_PARAM_PERCENTS}.fq

    echo "Executing seqtk for file: ${inputFile} > ${SEQTK_OUTPUT_FILE_PATH}"
    echo "${SEQTK_PATH} sample -s100 ${inputFile} ${seqCount} > ${SEQTK_OUTPUT_FILE_PATH}"
    [ ! -z ${DRY_RUN} ] || ${SEQTK_PATH} sample -s100 ${inputFile} ${seqCount} > ${SEQTK_OUTPUT_FILE_PATH}

  done
}

function processVelvet(){
  local -n inputFiles_=$1

  backupWorkspace ${VELVET_WORKSPACE_PATH}

  inputFilesString=$( IFS=$'\n'; echo "${inputFiles_[*]}" )
  # velveth_de
  #${VELVETH_PATH} ${VELVET_WORKSPACE_PATH} 31 -fastq -shortPaired ${inputFilesString}
  #${VELVETG_PATH} ${VELVET_WORKSPACE_PATH} -exp_cov auto
  echo "${VELVETH_PATH} ${VELVET_WORKSPACE_PATH} ${VELVETH_PARAMS} ${inputFilesString}"
  [ ! -z ${DRY_RUN} ] || ${VELVETH_PATH} ${VELVET_WORKSPACE_PATH} ${VELVETH_PARAMS} ${inputFilesString}
  echo "${VELVETG_PATH} ${VELVET_WORKSPACE_PATH} ${VELVETG_PARAMS}"
  [ ! -z ${DRY_RUN} ] || ${VELVETG_PATH} ${VELVET_WORKSPACE_PATH} ${VELVETG_PARAMS}
  # was -exp_cov 19 byt metavelvet needs -exp_cov auto
}

function processMetaVelvet(){
  echo "MetaVelvet"
}

function processDiamond(){
  local -n inputFiles_=$1
  echo "processDiamond"
  #PARAMTERES_EXT=.f6b${DIAMOND_PARAM_B}p${DIAMOND_PARAM_PROCESSES}

  backupWorkspace ${DIAMOND_WORKSPACE_PATH}

  for inputFile_ in "${inputFiles_[@]}"
  do
    PARAMTERES_EXT=""
    filenameWithExt=$(basename -- "$inputFile_")
    filename="${filenameWithExt%.*}"

    # convert fq to fa
    if [ ! -f "${inputFile_%.*}.fa" ] ; then
      echo "Converting ${inputFile_%.*}.fq to ${inputFile_%.*}.fa"
      [ ! -z ${DRY_RUN} ] || sed -n '1~4s/^@/>/p;2~4p' ${inputFile_%.*}.fq > ${DIAMOND_WORKSPACE_PATH}/${inputFile_%.*}.fa
      #${DIAMOND_WORKSPACE_PATH}/${inputFile_%.*}.fa
      inputFile_="${DIAMOND_WORKSPACE_PATH}/${inputFile_%.*}.fa"
      resultArray+=("${inputFile_}")
    fi
    echo "resultArray: ${resultArray[@]}"
    echo "Starting diamond blastx -d ${NR_DMND_FILE_PATH} -q ${inputFile_} -o ${DIAMOND_WORKSPACE_PATH}/matches-${filename}${PARAMTERES_EXT}.m8 -f ${DIAMOND_PARAM_F} -b${DIAMOND_PARAM_B} -p ${DIAMOND_PARAM_PROCESSES} >  ${DIAMOND_WORKSPACE_PATH}/diamond-${filename}${PARAMTERES_EXT}.log"

    [ ! -z ${DRY_RUN} ] || ${DIAMOND_PATH} blastx -d ${NR_DMND_FILE_PATH} -q ${inputFile_} -o ${DIAMOND_WORKSPACE_PATH}/matches-${filename}${PARAMTERES_EXT}.m8 -f ${DIAMOND_PARAM_F} -b${DIAMOND_PARAM_B} -p ${DIAMOND_PARAM_PROCESSES} > ${DIAMOND_WORKSPACE_PATH}/diamond-${filename}${PARAMTERES_EXT}.log
  done
}

function processMegan6(){
  echo "Megan6"
}

containsElement () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

# this is the main method that runs everything
run()
{
  parse_args "$@"
  loadWorkspace
  echoParameters
  if [[ -z ${doProcess} ]] ; then
    doProcess=("trimgalore" "seqtk" "velvet" "metaVelvet" "diamond" "megan6")
  fi
  echo "new doProcess: ${doProcess[@]}"

  if containsElement "trimgalore" "${doProcess[@]}"; then
    # TODO better way how to say that there is just one readCount?
    globalReadsCount=$(getReadsCount ${inputFiles[0]})
    # TODO fix
    processTrimGalore inputFiles

    # get reuslt files to push them into pipeline - TODO test
  fi
  getTrimgalorsResultsAsArray inputFiles

  if containsElement "fastqc" "${doProcess[@]}" ; then
    # TODO FASTQC
    #processFastQC
    echo "Not processing FastQC"
  fi



  #copy the array in another one
  trimmedInputFiles=("${resultArray[@]}")
  if containsElement "seqtk" "${doProcess[@]}"; then
    processSeqtk trimmedInputFiles globalReadsCount
  fi

  if containsElement "velvet" "${doProcess[@]}"; then
    processVelvet inputFiles
  fi

  # pairs
  if containsElement "metaVelvet" "${doProcess[@]}"; then
    processMetaVelvet inputFiles
  fi

  if containsElement "diamond" "${doProcess[@]}"; then
    processDiamond inputFiles
    # update input files to use .fa?
    #inputFiles = ("${resultArray[@]}")
  fi

  if containsElement "megan6" "${doProcess[@]}"; then
    processMegan6 inputFiles
  fi

  # TODO ? process evaluated files with fastqc?
  #processSeqtk inputFilesWithBetterQualityArray globalReadsCount
}

# lets run it with program arguments
run "$@";
