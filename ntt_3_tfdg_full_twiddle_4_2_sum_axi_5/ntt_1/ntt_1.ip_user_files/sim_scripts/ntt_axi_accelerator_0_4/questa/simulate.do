onbreak {quit -f}
onerror {quit -f}

vsim -t 1ps -lib xil_defaultlib ntt_axi_accelerator_0_opt

do {wave.do}

view wave
view structure
view signals

do {ntt_axi_accelerator_0.udo}

run -all

quit -force
