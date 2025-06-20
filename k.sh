#!/bin/bash

proxy_on () {
	#export all_proxy=socks5://127.0.0.1:7891 no_proxy=127.0.0.1
    #export https_proxy=$all_proxy http_proxy=$all_proxy
}

# parse and expend first cmd like gn,gp,dp,dn
parsefirst() {
  arg=$1
  if [[ $arg == 'gn' ]]; then
    cmd+=('get')
    cmd+=('node')
  elif [[ $arg == 'gp' ]]; then
    cmd+=('get')
    cmd+=('pod')
  elif [[ $arg == 'dp' ]]; then
    cmd+=('describe')
    cmd+=('pod')
  elif [[ $arg == 'dn' ]]; then
    cmd+=('describe')
    cmd+=('node')
  else
    cmd+=($arg)
  fi
}

# use env avoid alias
kubectl=/usr/bin/kubectl

parseother(){
  arg=$1
  if [[ $arg == '--node='* ]] ;then
    arg=${arg:7}
    cmd+=('--field-selector=spec.nodeName='$arg)
  else
    cmd+=($arg)
  fi
}

istmp=false
if [[ x$ev == 'xtmp' ]]; then
  istmp=true
fi

islocal=false
if [[ x$ev == 'xl' ]] || [[ x$ev == 'xlocal' ]]; then
  islocal=true
fi

enfile=$HOME/.kube/env
if $islocal && readlink /proc/self/fd/2 | grep -q pts; then
  tmpidx=$(readlink /proc/self/fd/2 |awk -F '/' '{print $NF}')
  enfile=$HOME/.kube/env$tmpidx
fi

# load env
if ! $istmp; then
  if [[ x$k == 'x' ]]; then
    k=$(grep -oE 'k=(.*)' $enfile|awk -F '=' '{print $NF}')
  fi
  if [[ x$ns == 'x' ]]; then
    ns=$(grep -oE 'ns=(.*)' $enfile|awk -F '=' '{print $NF}')
  fi
fi

config=$HOME/.kube/config
# load kcfg
if [[ x$k == 'x' ]]; then
  k=l
fi
if ! yq '.contexts' $config -oj | jq '.[] | .name' -r |grep -oqE "^$k\$"; then
  echo "no such context $k"
  echo -n "should be one of: "
  yq '.contexts' $config -oj | jq '.[] | .name' -r|sed ":a;N;s/\n/, /g;ta"
  exit 1
fi
proxy_on
kcfg="--kubeconfig=$config --context $k"

if ! $istmp ; then
  # write env
  echo > $enfile
  if [ ! -z "$ns" ] && [ "$ns" != "d" ]; then
  echo ns=$ns >> $enfile
  fi
  if [[ x$k != 'x' ]]; then
  echo k=$k >> $enfile
  fi
fi

if [[ $1 == 'shownode' ]]; then
  arg=$2
  if [[ x$arg == 'x' ]]; then
    echo "need arg"
    exit 1
  fi
  # old cannot show batch job
  $kubectl $kcfg get po -A --field-selector='spec.nodeName='$arg -ojson | jq '.items[] | select(.metadata.ownerReferences[0].kind != "DaemonSet")' | jq '. | {namespace: .metadata.namespace,name: .metadata.name}'
else
  cmd=($kubectl)
  cmd+=($kcfg)
  # ns=d is delete ns env for default
  if [[ x$ns != 'x' ]] && [ "$ns" != "d" ]; then
    if [[ $ns == 's' ]]; then
      ns=kube-system
    fi
    cmd+=('-n')
    cmd+=($ns)
  fi
  for ((i=1; i<=$#; i++)); do
    if [[ $i == 1 ]]; then
      parsefirst ${!i}
      continue
    fi
    parseother ${!i}
  done
  if [[ $debug == 'true' ]]; then
    set -x
  fi
  ${cmd[@]}
fi
