nextflow.enable.dsl=2

// ---------------------
// Parameters
// ---------------------
params.meta      = "in5323_2_metadata.tsv"
params.input_dir = "/mnt/shared/myacoub/projects/in5323/fastq"
params.outdir    = "/mnt/shared/myacoub/projects/in5323/host_removed"
params.ref_dir   = "/mnt/shared/myacoub/projects/in5323/host"
params.host_ref  = "GCF_000186305.1_Python_molurus_bivittatus-5.0.2_genomic.fna.gz"

// ---------------------
// Processes
// ---------------------

process FASTP {

    tag "$internal_id"

    cpus 10
    memory '20 GB'

    container "/mnt/workdir/singularity/quay.io-biocontainers-fastp-1.0.1--heae3180_0.img"
    containerOptions "-B ${params.input_dir}:/input"

    input:
    tuple val(internal_id), val(sample_dir), val(r1), val(r2)

    output:
    tuple val(internal_id), val(sample_dir),
          path("${internal_id}_trimmed_R1.fastq.gz"),
          path("${internal_id}_trimmed_R2.fastq.gz")

    script:
    """
    fastp \
      --in1 /input/${r1} \
      --in2 /input/${r2} \
      --detect_adapter_for_pe \
      --qualified_quality_phred 20 \
      --length_required 50 \
      --thread ${task.cpus} \
      --out1 ${internal_id}_trimmed_R1.fastq.gz \
      --out2 ${internal_id}_trimmed_R2.fastq.gz \
      --html ${internal_id}_fastp.html
    """
}

process BWA_ALIGN {

    cpus 32
    memory '200 GB'

    container "/mnt/workdir/singularity/quay.io-biocontainers-bwa-0.7.17--hed695b0_7.img"
    containerOptions "-B ${params.ref_dir}:/ref"

    input:
    tuple val(internal_id), val(sample_dir), path(trimmed_r1), path(trimmed_r2)

    tag "$internal_id"

    output:
    tuple val(internal_id), val(sample_dir), path("${internal_id}.pe.sam")

    script:
    """
    bwa mem -t ${task.cpus} /ref/${params.host_ref} ${trimmed_r1} ${trimmed_r2} > ${internal_id}.pe.sam
    """
}

process SAM_TO_BAM {

    tag "$internal_id"

    cpus 16
    memory '100 GB'

    container "/mnt/workdir/singularity/us-docker.pkg.dev-cegx-releases-us-prod-samtools-0.2.3.img"

    input:
    tuple val(internal_id), val(sample_dir), path(sam)

    output:
    tuple val(internal_id), val(sample_dir), path("${internal_id}.pe.bam")

    script:
    """
    samtools view \
      -@ ${task.cpus} \
      -b \
      -h \
      -o ${internal_id}.pe.bam \
      ${sam}
    """
}

process EXTRACT_UNMAPPED {

    tag "$internal_id"

    cpus 16
    memory '100 GB'

    container "/mnt/workdir/singularity/us-docker.pkg.dev-cegx-releases-us-prod-samtools-0.2.3.img"

    input:
    tuple val(internal_id), val(sample_dir), path(bam)

    output:
    tuple val(internal_id), val(sample_dir), path("${internal_id}.sorted.bam")

    script:
    """
    samtools view -@ ${task.cpus} -h -b -f 12 -F 256 ${bam} > unmapped.bam
    samtools sort -@ ${task.cpus} -n unmapped.bam -o ${internal_id}.sorted.bam
    """
}

process BAM_TO_FASTQ {

    tag "$internal_id"

    cpus 16
    memory '50 GB'

    container "/mnt/workdir/singularity/us-docker.pkg.dev-cegx-releases-us-prod-samtools-0.2.3.img"

    input:
    tuple val(internal_id), val(sample_dir), path(sorted_bam)

    output:
    tuple val(internal_id), val(sample_dir),
          path("${internal_id}-non-host_R1.fastq"),
          path("${internal_id}-non-host_R2.fastq")

    publishDir { "${params.outdir}/${sample_dir}" }, mode: 'copy', pattern: "*-non-host_R*.fastq"

    script:
    """
    samtools fastq -@ ${task.cpus} \
      -1 ${internal_id}-non-host_R1.fastq \
      -2 ${internal_id}-non-host_R2.fastq \
      ${sorted_bam}
    """
}

process KRAKEN2_DECONTAM {

    tag "$internal_id"

    cpus 32
    memory '200 GB'

    container "/mnt/workdir/singularity/quay.io-biocontainers-kraken2-2.1.3--pl5321h077b44d_4.img"
    containerOptions "-B /mnt/shared/myacoub/Kraken2/dbs:/db"

    input:
    tuple val(internal_id), val(sample_dir), path(read1), path(read2)

    output:
tuple val(internal_id), val(sample_dir),
      path("${internal_id}.R_1.unclassified.fastq"),
      path("${internal_id}.R_2.unclassified.fastq"),
      path("${internal_id}.R_1.bacteria.fastq"),
      path("${internal_id}.R_2.bacteria.fastq"),
      path("${internal_id}.kraken"),
      path("${internal_id}.report.txt")

    publishDir { "${params.outdir}/${sample_dir}/kraken2" }, mode: 'copy'

    script:
    """
    DB=/db/k2_standard

        kraken2 \
      --db \$DB \
      --threads ${task.cpus} \
      --paired \
      --unclassified-out ${internal_id}.R#.unclassified.fastq \
      --classified-out ${internal_id}.R#.bacteria.fastq \
      --output ${internal_id}.kraken \
      --report ${internal_id}.report.txt \
      --confidence 0.1 \
      --use-names \
      $read1 $read2
    """
}

process SPADES_ASSEMBLY {

    tag "$internal_id"

    cpus 64
    memory '100 GB'
    time '12h'

    container "/mnt/workdir/singularity/quay.io-biocontainers-spades-3.15.5--h95f258a_1.img"

    input:
    tuple val(internal_id), val(sample_dir),
          path(r1),
          path(r2)

    output:
    tuple val(internal_id), val(sample_dir), path("${internal_id}_spades")

    publishDir { "${params.outdir}/${sample_dir}/spades" }, mode: 'copy'

    script:
    """
    spades.py \
     -1 ${r1} \
     -2 ${r2} \
     --careful \
     --only-assembler \
     --cov-cutoff auto \
     -k 21,33,55,77,99,127 \
     -t ${task.cpus} \
     -m 100 \
     -o ${internal_id}_spades
    """
}

// ---------------------
// Workflow
// ---------------------

workflow {

    samples = Channel
        .fromPath(params.meta)
        .splitCsv(sep: '\t', header: false)
        .map { row ->
            tuple(
                row[0],
                row[1],
                row[2],
                row[3]
            )
        }

    trimmed   = FASTP(samples)
    aligned   = BWA_ALIGN(trimmed)
    bam       = SAM_TO_BAM(aligned)
    unmapped  = EXTRACT_UNMAPPED(bam)
    fastqs    = BAM_TO_FASTQ(unmapped)
    kraken_out = KRAKEN2_DECONTAM(fastqs)

    assemblies = SPADES_ASSEMBLY(fastqs)
}
