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

# this function handles tirmgalore input and output
function processTrimGalore(){
  # TODO move parameters to properties file
  trim_galore --paired -q 25 --three_prime_clip_R1 15 --three_prime_clip_R2 15 *.clock_UMI.R1.fq.gz *.clock_UMI.R2.fq.gz
  trim_galore --paired -q 25 --three_prime_clip_R1 15 --three_prime_clip_R2 15 *.clock_UMI.R1.fq.gz *.clock_UMI.R2.fq.gz
}

# https://www.biostars.org/p/9610/
# take \$1 as filePath
function getFileCount(){
  echo "Filepath $1"
  filename=$(basename $1)
  ext=${filename##*\.}
  case "$ext" in
    fastqgz) echo "$filename : "
      ;;
    fqgz) echo "$filename : "
      ;;
    *) echo " $filename : "
      ;;
  esac
}

function run()
{
  parse_args "$@"

  echo "usePercentsOfFile = ${usePercentsOfFile}"
  echo "propertiesFile = ${propertiesFile}"
  for inputFile in "${inputFiles[@]}"
  do
     echo "inputFile = ${inputFile}"
  done

}

run "$@";
