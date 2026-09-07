#!/usr/bin/env sh
#(C)2019-2022 Pim Snel - https://github.com/mipmip/RUNME.sh
ALLARGS=("$@");CMDS=();DESC=();NARGS=$#;ARG1=$1;make_command(){ CMDS+=($1);DESC+=("$2");};usage(){ printf "\nUsage: %s [command]\n\nCommands:\n" $0;line="              ";for((i=0;i<=$(( ${#CMDS[*]} -1));i++));do printf "  %s %s ${DESC[$i]}\n" ${CMDS[$i]} "${line:${#CMDS[$i]}}";done;echo;};runme(){ if test $NARGS -gt 0;then eval "$ARG1"||usage;else usage;fi;}

prepare(){

 if test $NARGS -lt 2; then
   echo "Usage: ./RUNME.sh ${ARG1} [./markdown_file.md]"
   exit 1
 fi

 MARKDOWNFILE=${ALLARGS[1]}
}

aws_bin_with_1NT(){
  aws wellarchitected $SUBCMD --workload-id=$WORKLOAD_ID --lens-alias=wellarchitected --max-results=50 > $OUTFILE-0.json
  NT=`aws wellarchitected $SUBCMD --workload-id=$WORKLOAD_ID --lens-alias=wellarchitected --max-results=50 | jq ".NextToken" | tr -d '"'`
  echo $NT
  aws wellarchitected $SUBCMD --workload-id=$WORKLOAD_ID --lens-alias=wellarchitected --max-results=50 --next-token=$NT > $OUTFILE-1.json
}

##### PLACE YOUR COMMANDS BELOW #####

make_command "install_deps" "install or update exensions and other dependancies"
install_deps(){
  echo "Installing extension: TexNative"
  quarto add --no-prompt wearetechnative/texnative
  echo "Installing extension: Quarto TechNative Branding"
  quarto add --no-prompt TechNative-B-V/quarto-technative-branding
  echo "Installing extension: Quarto TechNative Presentation Template"
  quarto add --no-prompt TechNative-B-V/revealjs-technative-theme
}

make_command "render_auto" "auto render a markdown file on change"
render_auto(){
  prepare
  echo "Auto rendering. Press CTRL-C to quit."
  ls $MARKDOWNFILE | entr quarto render $MARKDOWNFILE
}

make_command "war_export_json" "export all relevant data of a workload"
war_export_json(){

  if [ -z "${WORKLOAD_ID}" ]; then
    echo "SET WORKLOAD_ID env var"
    exit 1
  fi

  aws wellarchitected get-lens-review --workload-id=$WORKLOAD_ID --lens-alias=wellarchitected > data/awstool/get-lens-review.json

  SUBCMD=list-answers
  OUTFILE=data/awstool/list-answers
  aws_bin_with_1NT

  SUBCMD=list-lens-review-improvements
  OUTFILE=data/awstool/list-lens-review-improvements
  aws_bin_with_1NT

  aws wellarchitected list-workloads > data/awstool/list-workloads.json
  aws wellarchitected get-workload --workload-id=$WORKLOAD_ID > data/awstool/get-workload.json
}

make_command "create_priorities" "create priorities for editing by consultant"
create_priorities(){
  cd waf_model/scripts
  python3 create_priority_yamls.py > ../../data/priorities/all_missing.yml

  export PILLAR=operationalExcellence
  python3 create_priority_yamls.py > ../../data/priorities/${PILLAR}.yml
  export PILLAR=security
  python3 create_priority_yamls.py > ../../data/priorities/${PILLAR}.yml
  export PILLAR=reliability
  python3 create_priority_yamls.py > ../../data/priorities/${PILLAR}.yml
  export PILLAR=performance
  python3 create_priority_yamls.py > ../../data/priorities/${PILLAR}.yml
  export PILLAR=costOptimization
  python3 create_priority_yamls.py > ../../data/priorities/${PILLAR}.yml
  export PILLAR=sustainability
  python3 create_priority_yamls.py > ../../data/priorities/${PILLAR}.yml

  cd ../..
}

##### PLACE YOUR COMMANDS ABOVE #####

runme
