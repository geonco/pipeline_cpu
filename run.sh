set -e

verilator -Wall -Wno-fatal --trace --public-flat-rw --cc \
    pipeline_cpu.sv imem.sv regfile.sv alu.sv dmem_unaligned.sv \
    --exe tb_pipeline_cpu.cpp

make -C obj_dir -f Vpipeline_cpu.mk Vpipeline_cpu

./obj_dir/Vpipeline_cpu
