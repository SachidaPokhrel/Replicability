# Methods

A complete genome and matching whole-genome Illumina data were selected for *Bacillus subtilis* BEST3145. Assembly GCA_019704475.1 is associated with BioSample SAMD00163116; paired-end Illumina MiSeq run DRR172337 is also associated with SAMD00163116. The complete chromosome sequence AP024628.1 was retrieved from NCBI Nucleotide. To make the analysis small and deterministic, the first 300,000 SRA spots from DRR172337 were extracted with SRA Toolkit `fastq-dump --split-files --skip-technical -X 300000`.

Reads were aligned to the original chromosome with BWA MEM and coordinate-sorted using SAMtools. SAMtools `flagstat` was used to record mapping statistics. Mean depth and the percentage of reference bases covered by at least one read were calculated from `samtools depth -aa`.

The original chromosome was polished with NextPolish using only the paired Illumina reads. NextPolish task `1212` was used for short-read polishing. The resulting polished FASTA was saved as `outputs/polished.fasta`.

The identical paired reads were then remapped to the polished FASTA using the same BWA/SAMtools procedure. A Meryl k-mer database (k=21) was built from the paired reads and used by Merqury to estimate QV, error rate, and k-mer completeness for both the original and polished assemblies.

Assembly size statistics were calculated from FASTA sequence lengths with AWK and combined with mapping and Merqury metrics in `outputs/summary.csv`. SHA-256 hashes were generated for `input/reference.fasta`, `input/reads_R1.fastq`, `input/reads_R2.fastq`, and every scientific file in `outputs/`. Execution logs were not included in checksum comparison because they intentionally contain machine-specific timestamps and hostnames.
