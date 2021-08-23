#!/bin/tcsh

# CSH SCRIPT TO SET UP ENVIRONMENT FOR OPERATION OF MEERPIPE_DB
# LOAD REQUIRED MODULES

module purge
module load psrhome/latest
module load psrchive/96b8d4477-python-3.6.4
module load psrdb/latest
module load pandas/0.22.0-python-3.6.4
module load matplotlib/2.2.2-python-3.6.4
module load scipy/1.3.0-python-3.6.4
module load astropy/3.1.2-python-3.6.4

# SET ENVIRONMENT VARIABLES
setenv COAST_GUARD /fred/oz002/dreardon/MeerGuard3
setenv COASTGUARD_CFG $COAST_GUARD/configurations
setenv PATH $PATH\:$COAST_GUARD\:$COAST_GUARD/coast_guard
setenv PYTHONPATH $PYTHONPATH\:$COAST_GUARD\:$COAST_GUARD/coast_guard
