connect -url tcp:127.0.0.1:3121
source F:/experiment/NTT/1/sum/ntt_3_tfdg_full_twiddle_4_2_sum_axi_3/ntt_1/vitis_3/design_1_wrapper_hw_platform_0/ps7_init.tcl
targets -set -nocase -filter {name =~"APU*" && jtag_cable_name =~ "Digilent JTAG-HS1 210512180081"} -index 0
rst -system
after 3000
targets -set -filter {jtag_cable_name =~ "Digilent JTAG-HS1 210512180081" && level==0} -index 1
fpga -file F:/experiment/NTT/1/sum/ntt_3_tfdg_full_twiddle_4_2_sum_axi_3/ntt_1/vitis_3/design_1_wrapper_hw_platform_0/design_1_wrapper.bit
targets -set -nocase -filter {name =~"APU*" && jtag_cable_name =~ "Digilent JTAG-HS1 210512180081"} -index 0
loadhw -hw F:/experiment/NTT/1/sum/ntt_3_tfdg_full_twiddle_4_2_sum_axi_3/ntt_1/vitis_3/design_1_wrapper_hw_platform_0/system.hdf -mem-ranges [list {0x40000000 0xbfffffff}]
configparams force-mem-access 1
targets -set -nocase -filter {name =~"APU*" && jtag_cable_name =~ "Digilent JTAG-HS1 210512180081"} -index 0
ps7_init
ps7_post_config
targets -set -nocase -filter {name =~ "ARM*#0" && jtag_cable_name =~ "Digilent JTAG-HS1 210512180081"} -index 0
dow F:/experiment/NTT/1/sum/ntt_3_tfdg_full_twiddle_4_2_sum_axi_3/ntt_1/vitis_3/ntt/Debug/ntt.elf
configparams force-mem-access 0
targets -set -nocase -filter {name =~ "ARM*#0" && jtag_cable_name =~ "Digilent JTAG-HS1 210512180081"} -index 0
con
