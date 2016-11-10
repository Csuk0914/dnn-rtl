#!/bin/bash

set -e

mktempd() {
    mktemp -d 2>/dev/null || mktemp -d -t tmp
}

function usage
{
  echo "$0: [options] <test-verilog>"
  echo "    -b <backend>"
  echo "    --sim <simulator>"
  echo "    --dump <vcd file> dump vcd. Defaults to 'test.vcd'"
  exit 1
}

dump=""
monitor=""
simulator="${SIMULATOR:-vsim}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -b) backend="$2"; shift 2;;
    --sim) simulator="$2"; shift 2;;
    -p) pause="-s";;

    --backend=*) backend="${1#*=}"; shift 1;;
    --backend) echo "$1 requires an argument" >&2; exit 1;;
    --pause) pause="-s"; shift 1;;
    --dump=*) dump="-DDUMPFILE=\"${1#*=}\""; shift 1;;
    --dump) dump="-DDUMPFILE=\"test.vcd\""; shift 1;;
    --monitor) monitor="-DMONITOR"; shift 1;;

    -*) echo "unknown option: $1" >&2;  usage; exit 1;;
    *) testfile="$1"; shift 1;;
  esac
done

if [ "x$testfile" = "x" ]; then
	echo "Need input test file"
	usage
fi

if [ "$simulator" = "vsim"  ]; then

        outfile=$(mktemp --suffix ".vvp")
	case $backend in
	   normal|log) echo -n
    	     vsim -Wall "$dump" "$monitor" -s harness src/$backend/DNN.v $testfile -Iverilog/test/$backend -o "$outfile" 2>&1 ;;
           *) echo Unknown backend ;;
        esac
	vvp $pause "$outfile"
	rm "$outfile"

elif [ "$simulator" = "xsim"  ]; then
    wd=$PWD
    testfile=$(realpath $testfile)
    td=$(mktempd)

    pushd $td >/dev/null

	top="DNN"
        xvlog --nolog --relax -i $wd/src/* >/dev/null
	xelab --nolog $top -debug typical >/dev/null
    # Okay this is complicated, the first two seds will quit processing
    # when it sees $finish or ## exit, and the last will delete until it sees
    # ## run, giving us just the output from the sim.
	xsim --nolog $top -t $wd/tcl/sim.tcl | sed '/\$finish/Q' | sed '/## exit/Q' | sed '1,/^## run/d'
    popd >/dev/null

	rm -rf $td
fi
