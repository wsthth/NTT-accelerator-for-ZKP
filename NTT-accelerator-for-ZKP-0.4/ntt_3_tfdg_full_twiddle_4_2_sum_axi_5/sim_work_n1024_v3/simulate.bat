@echo off
REM Run N=1024 simulation
xsim sim_snapshot -tcl run.tcl -log xsim.log
echo Simulation done.
