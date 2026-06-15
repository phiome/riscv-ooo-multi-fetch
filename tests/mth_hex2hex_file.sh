#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: ./mth_hex2hex_file.sh <source.hex>"
    exit 1
fi

SOURCE=$1
BASE=$(basename "$SOURCE" .hex)

verilator --binary scrambler.sv  --top scrambler
./obj_dir/Vscrambler > _imem.hex
head -n -3 _imem.hex > imem.mem
rm _imem.hex