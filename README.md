# Week 5 Reproducibility: Short-read polishing of *Bacillus subtilis* BEST3145

## Introduction

Reproducibility is a central requirement of computational biology because an analysis should be repeatable by another researcher using the same input data, software environment, and commands. In practice, this requires more than providing a list of commands. A reproducible workflow should document the origin of the data, the software versions and dependencies, the exact sequence of analytical steps, the expected outputs, and a method for verifying that independently generated results are identical.

This project demonstrates a small, fully scripted genome-polishing workflow using publicly available bacterial genome data. The analysis uses a complete genome assembly and paired-end Illumina sequencing reads from the same deposited *Bacillus subtilis* BEST3145 BioSample. The short reads are mapped to the original genome, used to polish the assembly with NextPolish, and then mapped again to the polished genome. Assembly quality before and after polishing is evaluated using read-mapping statistics and k-mer-based metrics from Meryl and Merqury.

Long-read assembly, Porechop, Flye, and Medaka are intentionally excluded so that the workflow remains computationally small enough for the Week 5 reproducibility exercise.

---

## Objective

The objective of this project is to create a computational genome-polishing analysis that can be reproduced from start to finish by another Linux Bash user using only the files provided in the GitHub repository and publicly available sequence data.

Specifically, the workflow is designed to:

* retrieve public genome and sequencing data automatically;
* ensure that the reference assembly and Illumina reads originate from the same deposited isolate;
* map paired-end Illumina reads to the original assembly;
* polish the assembly using NextPolish;
* remap the same reads to the polished assembly;
* compare the original and polished assemblies using mapping and k-mer-based quality metrics;
* record all computational steps in individual log files;
* create SHA-256 checksums for the input data and scientific outputs; and
* allow an independent user to verify whether the analysis reproduces the same files byte for byte.

---

## Research Question

**Does short-read polishing with NextPolish change measurable genome-quality metrics of the public *Bacillus subtilis* BEST3145 assembly when evaluated using the same paired-end Illumina reads before and after polishing?**

The analysis compares the original and polished assemblies using:

* primary read-mapping percentage;
* properly paired percentage;
* mean sequencing depth;
* breadth of reference coverage;
* assembly size and contiguity statistics;
* Merqury QV;
* estimated Merqury error rate; and
* Merqury k-mer completeness.

The purpose of the project is not only to compare these metrics, but also to determine whether the complete computational workflow can be independently reproduced.

---

## Public Data

The analysis uses publicly available data for *Bacillus subtilis* BEST3145:

| Resource                | Accession                    |
| ----------------------- | ---------------------------- |
| Strain                  | *Bacillus subtilis* BEST3145 |
| Assembly                | `GCA_019704475.1`            |
| Complete chromosome     | `AP024628.1`                 |
| BioSample               | `SAMD00163116`               |
| Paired-end Illumina run | `DRR172337`                  |
| BioProject              | `PRJDB8028`                  |

The genome assembly and Illumina sequencing run are both associated with BioSample `SAMD00163116`, allowing the reference and short-read data to be treated as originating from the same deposited isolate.

To keep the analysis small enough for the assignment, the workflow uses the first **300,000 SRA spots** from `DRR172337` rather than the complete sequencing run.

The raw data are generated automatically and are not committed to GitHub.

---

# Methods

## 1. Software Environment

The workflow is designed for Linux systems using Bash.

The primary command for reproducing the project is:

```bash
bash setup_and_run.sh
```

The setup script first checks whether Conda is available. If Conda is not installed, it downloads a pinned Miniforge installer, verifies the installer checksum, and installs Miniforge locally within the project directory without requiring administrator privileges. It then creates the `week5-best3145` Conda environment from `environment.yml` and executes the analysis script.

The Conda environment includes the main external programs used in the analysis:

* SRA Toolkit
* BWA
* SAMtools
* NextPolish
* Meryl
* Merqury

The environment specification is stored in:

```text
environment.yml
```

Users who already have Conda installed may create the environment manually:

```bash
conda env create -f environment.yml
conda activate week5-best3145
bash run.sh
```

However, `setup_and_run.sh` is the recommended entry point because it also supports users who do not already have Conda installed.

---

## 2. Public Data Retrieval

The complete chromosome sequence `AP024628.1` is downloaded automatically and saved as:

```text
input/reference.fasta
```

The first 300,000 spots from Illumina run `DRR172337` are retrieved using SRA Toolkit and split into paired FASTQ files:

```text
input/reads_R1.fastq
input/reads_R2.fastq
```

The workflow verifies that the two FASTQ files contain the same number of read records before continuing.

The three files used as the input to the analysis are therefore:

```text
input/reference.fasta
input/reads_R1.fastq
input/reads_R2.fastq
```

The input files are generated during the analysis and should not be committed to GitHub.

---

## 3. Mapping Illumina Reads to the Original Assembly

The original genome assembly is indexed using BWA.

The paired-end Illumina reads are aligned to the original genome using:

```text
bwa mem
```

The resulting alignments are sorted and indexed using SAMtools.

SAMtools is then used to calculate:

* total number of reads;
* primary mapped reads;
* percentage of properly paired reads;
* mean sequencing depth; and
* percentage of reference positions covered by at least one read.

The primary mapping results are written to:

```text
outputs/original.flagstat.txt
outputs/original.mapping_metrics.tsv
```

---

## 4. Short-read Genome Polishing

The original genome is polished using NextPolish with only the paired-end Illumina reads.

The workflow uses:

```text
task = 1212
```

which performs short-read polishing.

The resulting polished genome is copied to:

```text
outputs/polished.fasta
```

The workflow intentionally does not perform long-read assembly or Medaka polishing.

---

## 5. Mapping Illumina Reads to the Polished Assembly

The exact same Illumina reads used for the original assembly are mapped to the polished assembly using the same BWA and SAMtools procedure.

This produces:

```text
outputs/polished.flagstat.txt
outputs/polished.mapping_metrics.tsv
```

Using the same read set before and after polishing provides a direct comparison between the original and polished assemblies.

---

## 6. K-mer-based Assembly Evaluation

Meryl is used to construct a k-mer database from the paired-end Illumina reads using:

```text
k = 21
```

The same Meryl database is then used by Merqury to evaluate both assemblies independently.

For each assembly, Merqury reports:

* quality value (QV);
* estimated consensus error rate; and
* k-mer completeness.

The retained Merqury outputs are:

```text
outputs/original.merqury.qv
outputs/original.merqury.completeness.stats

outputs/polished.merqury.qv
outputs/polished.merqury.completeness.stats
```

---

## 7. Assembly Statistics and Final Summary

Basic assembly statistics are calculated directly from the FASTA files, including:

* number of contigs;
* total assembly size;
* N50;
* longest contig.

These statistics are combined with the mapping and Merqury metrics into:

```text
outputs/summary.csv
```

The table contains one row for the original assembly and one row for the polished assembly.

The columns are:

```text
assembly
contigs
total_bp
N50_bp
longest_contig_bp
primary_mapped_pct
properly_paired_pct
mean_depth
breadth_1x_pct
merqury_QV
merqury_error_rate
merqury_completeness_pct
```

---

## 8. Logging

Each major computational stage generates its own log file:

```text
logs/00_fetch_data.o
logs/01_map_original.o
logs/02_nextpolish.o
logs/03_map_polished.o
logs/04_merqury.o
logs/05_summary.o
logs/06_checksums.o
```

The logs record information including:

* computational stage;
* start time;
* finish time;
* hostname;
* number of threads;
* standard output;
* error output; and
* exit status.

Logs are useful for troubleshooting but are not included in the byte-for-byte reproducibility comparison because timestamps and hostnames differ across machines.

---

## 9. SHA-256 Verification

At the end of the analysis, SHA-256 hashes are generated for the three input data files:

```text
input/reference.fasta
input/reads_R1.fastq
input/reads_R2.fastq
```

and for every scientific output file under:

```text
outputs/
```

The hashes are written to:

```text
CHECKSUMS.txt
```

This checksum file serves as the reference for testing whether an independently reproduced analysis generates byte-identical files.

---

# Running the Analysis

## Recommended method

From the repository directory:

```bash
bash setup_and_run.sh
```

This single command:

1. checks for Conda;
2. installs Miniforge locally if Conda is absent;
3. verifies the Miniforge installer;
4. creates the Conda environment;
5. downloads the public data;
6. performs the analysis;
7. creates the scientific outputs;
8. generates the logs; and
9. generates `CHECKSUMS.txt`.

No manual Conda activation is required.

---

## Thread control

The workflow uses four threads by default.

To use another number:

```bash
THREADS=2 bash setup_and_run.sh
```

or:

```bash
THREADS=8 bash setup_and_run.sh
```

---

# Expected Workflow

```text
Public genome + public Illumina reads
                │
                ▼
         00_fetch_data
                │
                ▼
       01_map_original
                │
                ▼
         02_nextpolish
                │
                ▼
       03_map_polished
                │
                ▼
          04_merqury
                │
                ▼
          05_summary
                │
                ▼
         06_checksums
```

---

# Expected Outputs

The main scientific outputs are:

```text
outputs/original.flagstat.txt
outputs/original.mapping_metrics.tsv

outputs/polished.fasta

outputs/polished.flagstat.txt
outputs/polished.mapping_metrics.tsv

outputs/original.merqury.qv
outputs/original.merqury.completeness.stats

outputs/polished.merqury.qv
outputs/polished.merqury.completeness.stats

outputs/summary.csv
```

The main comparison table is:

```text
outputs/summary.csv
```

---

# Repository Structure

Before running the analysis:

```text
Week5_BIOL7800/
├── setup_and_run.sh
├── run.sh
├── environment.yml
├── verify.sh
├── README.md
├── METHODS.md
├── DATA_SOURCES.md
└── outputs/
    └── .gitkeep
```

After running:

```text
Week5_BIOL7800/
├── input/
├── work/
├── logs/
├── metadata/
├── outputs/
├── CHECKSUMS.txt
├── setup_and_run.sh
├── run.sh
├── environment.yml
├── verify.sh
├── README.md
├── METHODS.md
└── DATA_SOURCES.md
```

---

# Reproducibility Verification

After completing the analysis, verify the files using:

```bash
bash verify.sh
```

or:

```bash
sha256sum -c CHECKSUMS.txt
```

A successful verification should report:

```text
input/reference.fasta: OK
input/reads_R1.fastq: OK
input/reads_R2.fastq: OK
outputs/original.flagstat.txt: OK
outputs/original.mapping_metrics.tsv: OK
outputs/polished.fasta: OK
outputs/polished.flagstat.txt: OK
outputs/polished.mapping_metrics.tsv: OK
outputs/summary.csv: OK
```

For an independent reproducibility test, another user should clone the repository, obtain the canonical `CHECKSUMS.txt`, and run:

```bash
bash setup_and_run.sh
```

The files generated on that machine can then be compared against the canonical SHA-256 hashes.

---

# Starting From a Fresh Linux Machine

A user with no existing Conda installation should be able to reproduce the project using:

```bash
git clone https://github.com/SachidaPokhrel/Replicability

cd Replicability

bash setup_and_run.sh
```

No administrator privileges or pre-existing Conda installation are required.

---

# Reproducibility Statement

This project is designed so that the complete analysis can be reconstructed from publicly available data and version-controlled code without distributing the raw sequence files themselves.

Reproducibility is supported through:

* publicly available input data;
* explicit accession numbers;
* matching assembly and short-read BioSample identity;
* automated data retrieval;
* automated software installation;
* a Conda environment specification;
* a single executable analysis script;
* separate logs for every computational stage;
* documented software and data provenance;
* clearly defined scientific outputs; and
* SHA-256 verification of both inputs and outputs.

The primary command required to reproduce the project is:

```bash
bash setup_and_run.sh
```
