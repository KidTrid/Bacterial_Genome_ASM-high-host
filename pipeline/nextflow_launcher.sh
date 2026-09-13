#!/bin/bash
#SBATCH --partition=midog
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
#SBATCH --time=48:00:00
#SBATCH --job-name=host_removal_nf

export NXF_APPTAINER_CACHEDIR=/mnt/workdir/singularity
export NXF_ENABLE_VIRTUAL_THREADS=false

META=$1
HOST_REF=$2

nextflow run main.nf \
  -profile slurm \
  -resume \
  --meta "$META" \
  --host_ref "$HOST_REF"
