# Week 5 Reproducibility: short-read polishing of *Bacillus subtilis* BEST3145

This repository reproduces a small downstream genome-polishing analysis using a public complete genome and public Illumina reads from the **same BioSample**.

The project is designed so that a Linux Bash user can reproduce the analysis without already having Conda installed. The `setup_and_run.sh` script checks for Conda, installs a project-local Miniforge distribution when necessary, creates the required software environment, and then runs the complete analysis.

---

## Public data

* Strain: *Bacillus subtilis* BEST3145
* Assembly: `GCA_019704475.1`
* Complete chromosome: `AP024628.1`
* BioSample: `SAMD00163116`
* Paired-end Illumina run: `DRR172337`
* BioProject: `PRJDB8028`

The genome assembly and Illumina sequencing run are both linked to BioSample `SAMD00163116`, ensuring that the assembly and short reads represent the same deposited isolate.

To keep the analysis small enough for the reproducibility exercise, the workflow uses the first **300,000 SRA spots** from `DRR172337`.

The subset is generated automatically by the workflow. No raw FASTA or FASTQ data are committed to GitHub.

---

# What the analysis does

The workflow performs the following steps:

1. Downloads chromosome `AP024628.1` into:

   ```text
   input/reference.fasta
   ```

2. Retrieves the first 300,000 paired Illumina spots from `DRR172337` and creates:

   ```text
   input/reads_R1.fastq
   input/reads_R2.fastq
   ```

3. Maps the Illumina reads to the original public genome using BWA and SAMtools.

4. Calculates mapping statistics including:

   * total reads
   * primary mapping percentage
   * properly paired percentage
   * mean sequencing depth
   * breadth of coverage at ≥1×

5. Polishes the original genome with NextPolish using only the Illumina reads:

   ```text
   task = 1212
   ```

6. Maps the exact same Illumina reads to the polished assembly.

7. Evaluates both the original and polished assemblies using Meryl and Merqury with:

   ```text
   k = 21
   ```

8. Creates a combined summary table:

   ```text
   outputs/summary.csv
   ```

9. Calculates SHA-256 checksums for:

   * all three input data files actually used in the analysis
   * every scientific output file

   and writes them to:

   ```text
   CHECKSUMS.txt
   ```

Long-read assembly, Flye, Porechop, and Medaka are intentionally excluded to keep the analysis computationally small enough for this exercise.

---

# Requirements

The automated setup currently supports:

```text
Linux x86_64
Linux aarch64
```

The system should have:

* Bash
* internet access
* either `curl` or `wget`
* `sha256sum`

Administrator or `sudo` access is **not required**.

All scientific software required by the analysis is installed through the Conda environment.

---

# Recommended setup and run

The easiest and most reproducible way to execute the project is:

```bash
bash setup_and_run.sh
```

This is the primary command for the project.

`setup_and_run.sh` performs the following automatically:

```text
Check for Conda
      ↓
If Conda exists → use it
      ↓
If Conda is absent
      ↓
Download pinned Miniforge installer
      ↓
Verify installer SHA-256
      ↓
Install Miniforge locally
      ↓
Create week5-best3145 environment
      ↓
Run run.sh inside that environment
      ↓
Download public data
      ↓
Perform analysis
      ↓
Generate outputs
      ↓
Generate CHECKSUMS.txt
```

No manual `conda activate` step is required.

---

# Local Miniforge installation

If Conda is not already installed, `setup_and_run.sh` installs Miniforge locally inside the project directory:

```text
.miniforge/
```

The installer is temporarily stored under:

```text
.bootstrap/
```

The installation does not modify the system-wide software environment and does not require root privileges.

Both directories should be excluded from GitHub:

```text
.miniforge/
.bootstrap/
```

---

# Conda environment

The required environment is defined in:

```text
environment.yml
```

The environment name is:

```text
week5-best3145
```

The environment contains the software needed for the workflow, including:

* SRA Toolkit
* BWA
* SAMtools
* NextPolish
* Meryl
* Merqury
* supporting command-line utilities

If the environment does not already exist, `setup_and_run.sh` automatically creates it with:

```bash
conda env create -f environment.yml
```

---

# Manual setup

Users who already have Conda and prefer to perform the setup manually can use:

```bash
conda env create -f environment.yml
```

Then:

```bash
conda activate week5-best3145
```

and run:

```bash
bash run.sh
```

However, the recommended reproducible method is:

```bash
bash setup_and_run.sh
```

because it also handles systems where Conda is not already installed.

---

# Recording the resolved environment

After the canonical analysis has been run successfully, the exact resolved Conda environment can also be recorded with:

```bash
conda env export --no-builds > environment.resolved.yml
```

If Miniforge was installed locally by the bootstrap script, the equivalent command is:

```bash
.miniforge/bin/conda env export \
    -n week5-best3145 \
    --no-builds \
    > environment.resolved.yml
```

The resulting:

```text
environment.resolved.yml
```

can be committed to GitHub as an additional record of the environment used for the canonical analysis.

---

# Running the analysis manually

If the Conda environment is already active:

```bash
bash run.sh
```

The workflow uses four threads by default.

To change the number of threads:

```bash
THREADS=2 bash run.sh
```

For example:

```bash
THREADS=8 bash run.sh
```

When using the automated bootstrap:

```bash
THREADS=2 bash setup_and_run.sh
```

will pass the requested thread value to the analysis.

---

# Pipeline stages

The workflow is divided into seven logged stages:

```text
00_fetch_data
      ↓
01_map_original
      ↓
02_nextpolish
      ↓
03_map_polished
      ↓
04_merqury
      ↓
05_summary
      ↓
06_checksums
```

Each stage produces its own `.o` log file.

---

# Repository structure before running

The GitHub repository should contain approximately:

```text
Week5_BIOL7800/
├── setup_and_run.sh
├── run.sh
├── environment.yml
├── verify.sh
├── prepare_box.sh
│
├── README.md
├── METHODS.md
├── DATA_SOURCES.md
├── GITHUB_REPO.txt
├── .gitignore
│
└── outputs/
    └── .gitkeep
```

Raw data are not included in the repository.

---

# Repository structure after running

After a successful run, the project will contain:

```text
Week5_BIOL7800/
│
├── input/
│   ├── reference.fasta
│   ├── reads_R1.fastq
│   └── reads_R2.fastq
│
├── work/
│   ├── BWA index files
│   ├── BAM files
│   ├── NextPolish intermediate files
│   └── Merqury intermediate files
│
├── logs/
│   ├── 00_fetch_data.o
│   ├── 01_map_original.o
│   ├── 02_nextpolish.o
│   ├── 03_map_polished.o
│   ├── 04_merqury.o
│   ├── 05_summary.o
│   └── 06_checksums.o
│
├── metadata/
│   ├── software_versions.txt
│   ├── bootstrap_environment.txt
│   └── data_sources.tsv
│
├── outputs/
│   ├── original.flagstat.txt
│   ├── original.mapping_metrics.tsv
│   ├── polished.fasta
│   ├── polished.flagstat.txt
│   ├── polished.mapping_metrics.tsv
│   ├── original.merqury.qv
│   ├── original.merqury.completeness.stats
│   ├── polished.merqury.qv
│   ├── polished.merqury.completeness.stats
│   └── summary.csv
│
├── CHECKSUMS.txt
│
├── setup_and_run.sh
├── run.sh
├── environment.yml
├── verify.sh
├── prepare_box.sh
├── README.md
├── METHODS.md
├── DATA_SOURCES.md
└── GITHUB_REPO.txt
```

---

# Input directory

All public data used by the analysis are automatically placed in:

```text
input/
```

The analysis uses exactly three input data files:

```text
input/reference.fasta
input/reads_R1.fastq
input/reads_R2.fastq
```

These files are generated automatically from public accession information.

They should **not** be committed to GitHub.

---

# Intermediate files

Temporary and intermediate files are stored under:

```text
work/
```

These include:

* BWA indexes
* sorted BAM files
* BAM indexes
* NextPolish working files
* Meryl database files
* Merqury intermediate files

These files are not required for the final submission and should normally be excluded from GitHub.

---

# Log files

Each stage generates a separate log:

```text
logs/00_fetch_data.o
logs/01_map_original.o
logs/02_nextpolish.o
logs/03_map_polished.o
logs/04_merqury.o
logs/05_summary.o
logs/06_checksums.o
```

The logs record information such as:

* computational stage
* start time
* finish time
* hostname
* number of threads
* stdout
* stderr
* exit code

These files are useful for troubleshooting and documenting execution.

Logs are intentionally excluded from `CHECKSUMS.txt` because they contain timestamps and hostnames and therefore are not expected to be byte-identical across computers.

---

# Scientific outputs

The expected scientific outputs are:

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

---

# Summary table

The main summary file is:

```text
outputs/summary.csv
```

It contains one row for:

```text
original
```

and one row for:

```text
polished
```

The table contains:

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

This allows direct comparison of the original public assembly with the NextPolish-corrected assembly.

---

# Checksums

At the end of the workflow:

```text
CHECKSUMS.txt
```

is automatically generated.

It contains SHA-256 hashes for the three input data files:

```text
input/reference.fasta
input/reads_R1.fastq
input/reads_R2.fastq
```

and every scientific output under:

```text
outputs/
```

The checksum file provides the byte-level reference for the reproducibility test.

---

# Reproducibility verification

After completing the canonical run:

```bash
bash verify.sh
```

can be used to verify the generated files.

Alternatively:

```bash
sha256sum -c CHECKSUMS.txt
```

can be run directly.

Expected output should contain lines similar to:

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

For a true independent reproducibility test, another user should:

1. Clone the GitHub repository.

2. Obtain the canonical `CHECKSUMS.txt`.

3. Run:

   ```bash
   bash setup_and_run.sh
   ```

4. Compare the regenerated files against the canonical checksums.

---

# Starting from a fresh machine

A new Linux user should be able to reproduce the project with:

```bash
git clone <PUBLIC_GITHUB_REPOSITORY_URL>

cd Week5_BIOL7800

bash setup_and_run.sh
```

No pre-existing Conda installation is required.

---

# GitHub contents

The GitHub repository should contain the reproducibility instructions and code, but not the raw public sequence data.

Recommended files to commit include:

```text
README.md
METHODS.md
DATA_SOURCES.md

setup_and_run.sh
run.sh
verify.sh
prepare_box.sh

environment.yml
environment.resolved.yml

GITHUB_REPO.txt
CHECKSUMS.txt

outputs/
```

The raw and intermediate data should remain excluded.

---

# Suggested `.gitignore`

The repository should ignore:

```text
input/
work/
logs/
metadata/

.miniforge/
.bootstrap/

box_submission/
```

The `outputs/` directory should remain available for the scientific outputs required by the assignment.

---

# Box submission

After completing the canonical analysis:

1. Push the repository to a public GitHub repository.

2. Put the public GitHub URL in:

   ```text
   GITHUB_REPO.txt
   ```

3. Run:

   ```bash
   bash prepare_box.sh
   ```

4. This creates:

   ```text
   box_submission/
   ├── GITHUB_REPO.txt
   ├── CHECKSUMS.txt
   └── outputs/
   ```

5. Upload:

   ```text
   box_submission/
   ```

   to the Week 5 Box folder.

The raw public sequence data are not included in either the GitHub repository or the Box package.

---

# Reproducibility design

This project is intended to satisfy the Week 5 reproducibility requirements by providing:

* a small computational analysis
* public input data
* an assembly and Illumina dataset derived from the same BioSample
* multiple external command-line programs
* automated software installation
* a Conda environment specification
* ordered analysis steps
* per-step logs
* scientific output files
* a README
* a Methods description
* documented data provenance
* SHA-256 hashes of the data actually used
* SHA-256 hashes of every scientific output
* no raw sequencing data committed to GitHub
* a one-command setup and execution workflow

The primary command required to reproduce the analysis is:

```bash
bash setup_and_run.sh
```
