#!/bin/tcsh

# Andrew Cameron, 25/08/2021 (andrewcameron@swin.edu.au)
# CSH SCRIPT TO SET UP ENVIRONMENT FOR OPERATION OF MEERPIPE_DB - PYTHON3
# SHOULD PROVIDE IDENTICAL INSTRUCTIONS TO ENV_SETUP.SH

if ( "${SYS_ARCH}" == "milan" ) then
    # Using new Ngarrgu Tindebeek (NT) cluster
    module use /apps/users/pulsar/milan/gcc-11.3.0/modulefiles
endif
if ( ${SYS_ARCH} == "skylake" ) then
    # Using original ozstar cluster
    module use /apps/users/pulsar/skylake/modulefiles
endif
module purge

# LOAD REQUIRED MODULES
module load psrhome/latest
if ( "${SYS_ARCH}" == "milan" ) then
    # Using new Ngarrgu Tindebeek (NT) cluster
    module load psrdb/d41d4b3
    module load pandas/1.4.2-scipy-bundle-2022.05
    module load matplotlib/3.5.2
endif
if ( ${SYS_ARCH} == "skylake" ) then
    # Using original ozstar cluster
    module load psrchive/96b8d4477-python-3.6.4
    module load psrdb/latest
    module load pandas/0.22.0-python-3.6.4
    module load matplotlib/2.2.2-python-3.6.4
    module load scipy/1.3.0-python-3.6.4
    module load astropy/3.1.2-python-3.6.4
endif

# SET ENVIRONMENT VARIABLES
setenv COAST_GUARD /fred/oz005/software/MeerGuard
setenv COASTGUARD_CFG $COAST_GUARD/configurations
setenv PATH $PATH\:$COAST_GUARD\:$COAST_GUARD/coast_guard
setenv PYTHONPATH $PYTHONPATH\:$COAST_GUARD\:$COAST_GUARD/coast_guard
