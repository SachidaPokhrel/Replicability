#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C LANG=C TZ=UTC

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$ROOT"
THREADS="${THREADS:-4}"
SRA_RUN="DRR172337"
SPOTS="300000"
NUCCORE_ACCESSION="AP024628.1"
ASSEMBLY_ACCESSION="GCA_019704475.1"
BIOSAMPLE="SAMD00163116"
KMER="21"

INPUT="$ROOT/input"; WORK="$ROOT/work"; OUT="$ROOT/outputs"; LOG="$ROOT/logs"; META="$ROOT/metadata"
mkdir -p "$INPUT" "$WORK" "$OUT" "$LOG" "$META"
REF="$INPUT/reference.fasta"; R1="$INPUT/reads_R1.fastq"; R2="$INPUT/reads_R2.fastq"
POLISHED="$OUT/polished.fasta"; CHECKSUMS="$ROOT/CHECKSUMS.txt"

die(){ echo "ERROR: $*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
check(){ [[ -s "$1" ]] || die "Expected non-empty file not found: $1"; }

run_step(){
  local step="$1"; shift; local log="$LOG/${step}.o"; local s
  echo "===== $step ====="; echo "Log: $log"
  { echo "Step: $step"; echo "Started: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"; echo "Host: $(hostname)"; echo "Threads: $THREADS"; } > "$log"
  set +e; "$@" 2>&1 | tee -a "$log"; s=${PIPESTATUS[0]}; set -e
  { echo "Finished: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"; echo "Exit_code: $s"; } | tee -a "$log"
  [[ "$s" -eq 0 ]] || die "$step failed; inspect $log"
}

for x in curl fastq-dump bwa samtools nextPolish meryl merqury.sh sha256sum awk sed grep sort; do need "$x"; done

{
  echo "assembly=$ASSEMBLY_ACCESSION"
  echo "nucleotide=$NUCCORE_ACCESSION"
  echo "biosample=$BIOSAMPLE"
  echo "sra_run=$SRA_RUN"
  echo "spots=$SPOTS"
  echo "kmer=$KMER"
  echo "threads=$THREADS"
  fastq-dump --version 2>&1 | head -n 2 || true
  bwa 2>&1 | grep -m1 Version || true
  samtools --version | head -n 1
  nextPolish --version 2>&1 || true
  meryl --version 2>&1 | head -n 2 || true
  merqury.sh 2>&1 | head -n 3 || true
} > "$META/software_versions.txt"

step00(){
  if [[ ! -s "$REF" ]]; then
    curl --fail --location --retry 3 --silent --show-error \
      "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=${NUCCORE_ACCESSION}&rettype=fasta&retmode=text" \
      > "$REF"
  fi
  check "$REF"; grep -q 'AP024628.1' "$REF" || die "Wrong reference accession"

  if [[ ! -s "$R1" || ! -s "$R2" ]]; then
    rm -f "$INPUT/${SRA_RUN}_1.fastq" "$INPUT/${SRA_RUN}_2.fastq" "$R1" "$R2"
    fastq-dump --split-files --skip-technical -X "$SPOTS" --outdir "$INPUT" "$SRA_RUN"
    mv "$INPUT/${SRA_RUN}_1.fastq" "$R1"
    mv "$INPUT/${SRA_RUN}_2.fastq" "$R2"
  fi
  check "$R1"; check "$R2"
  n1=$(awk 'END{print NR/4}' "$R1"); n2=$(awk 'END{print NR/4}' "$R2")
  echo "R1_records=$n1"; echo "R2_records=$n2"; [[ "$n1" == "$n2" ]] || die "Read counts differ"
  cat > "$META/data_sources.tsv" <<META
field	value
organism	Bacillus subtilis BEST3145
assembly_accession	$ASSEMBLY_ACCESSION
nucleotide_accession	$NUCCORE_ACCESSION
biosample	$BIOSAMPLE
illumina_run	$SRA_RUN
subset_rule	first $SPOTS SRA spots
META
}

map_measure(){
  local ref="$1" label="$2" idx="$WORK/index_${label}" bam="$WORK/${label}.sorted.bam"
  local fs="$OUT/${label}.flagstat.txt" mt="$OUT/${label}.mapping_metrics.tsv"
  rm -rf "$idx"; mkdir -p "$idx"; cp "$ref" "$idx/reference.fasta"
  bwa index "$idx/reference.fasta"
  bwa mem -t "$THREADS" "$idx/reference.fasta" "$R1" "$R2" | samtools sort -@ "$THREADS" -o "$bam"
  samtools index -@ "$THREADS" "$bam"
  samtools flagstat -@ "$THREADS" "$bam" > "$fs"
  total=$(grep -m1 'in total' "$fs" | awk '{print $1}')
  mapped=$(grep -m1 'primary mapped' "$fs" | sed -nE 's/.*\(([0-9.]+)%.*\).*/\1/p')
  [[ -n "$mapped" ]] || mapped=$(grep -m1 ' mapped (' "$fs" | sed -nE 's/.*\(([0-9.]+)%.*\).*/\1/p')
  proper=$(grep -m1 'properly paired' "$fs" | sed -nE 's/.*\(([0-9.]+)%.*\).*/\1/p')
  read -r depth breadth < <(samtools depth -aa "$bam" | awk '{n++; s+=$3; if($3>0)c++} END{if(n)printf "%.6f %.6f\n",s/n,100*c/n; else print "0 0"}')
  printf "metric\tvalue\n" > "$mt"
  printf "total_reads\t%s\nprimary_mapped_pct\t%s\nproperly_paired_pct\t%s\nmean_depth\t%s\nbreadth_1x_pct\t%s\n" \
    "${total:-NA}" "${mapped:-NA}" "${proper:-NA}" "${depth:-NA}" "${breadth:-NA}" >> "$mt"
}

step01(){ map_measure "$REF" original; cat "$OUT/original.mapping_metrics.tsv"; }

step02(){
  local np="$WORK/nextpolish" fofn="$WORK/sgs.fofn" cfg="$WORK/nextpolish.cfg"
  rm -rf "$np"; mkdir -p "$np"
  printf "%s\n%s\n" "$R1" "$R2" > "$fofn"
  cat > "$cfg" <<CFG
[General]
job_type = local
job_prefix = best3145
task = 1212
rewrite = yes
deltmp = yes
rerun = 3
parallel_jobs = 1
multithread_jobs = $THREADS
genome = $REF
genome_size = auto
workdir = $np
polish_options = -p {multithread_jobs}

[sgs_option]
sgs_fofn = $fofn
sgs_options = -max_depth 100 -bwa
CFG
  cat "$cfg"; nextPolish "$cfg"; check "$np/genome.nextpolish.fasta"
  cp "$np/genome.nextpolish.fasta" "$POLISHED"; check "$POLISHED"
}

step03(){ map_measure "$POLISHED" polished; cat "$OUT/polished.mapping_metrics.tsv"; }

step04(){
  local mq="$WORK/merqury" db="$WORK/merqury/reads.meryl"
  rm -rf "$mq"; mkdir -p "$mq"; cd "$mq"
  meryl k="$KMER" count output "$db" "$R1" "$R2"
  merqury.sh "$db" "$REF" original
  merqury.sh "$db" "$POLISHED" polished
  for f in original.qv original.completeness.stats polished.qv polished.completeness.stats; do check "$mq/$f"; done
  cp original.qv "$OUT/original.merqury.qv"
  cp original.completeness.stats "$OUT/original.merqury.completeness.stats"
  cp polished.qv "$OUT/polished.merqury.qv"
  cp polished.completeness.stats "$OUT/polished.merqury.completeness.stats"
  cd "$ROOT"
}

astats(){
  awk '/^>/{if(l)print l;l=0;next}{l+=length($0)}END{if(l)print l}' "$1" | sort -nr | \
  awk '{a[NR]=$1;t+=$1}END{h=t/2;r=0;n="NA";for(i=1;i<=NR;i++){r+=a[i];if(n=="NA"&&r>=h)n=a[i]}printf "%d,%d,%s,%d",NR,t,n,a[1]}'
}
mval(){ awk -F '\t' -v m="$2" '$1==m{print $2}' "$1"; }
mqval(){
  q=$(awk 'NF>=5{print $4;exit}' "$1"); e=$(awk 'NF>=5{print $5;exit}' "$1")
  c=$(awk 'NF>=5&&$2=="all"{print $5;exit}' "$2"); [[ -n "$c" ]] || c=$(awk 'NF>=5{print $5;exit}' "$2")
  printf "%s,%s,%s" "${q:-NA}" "${e:-NA}" "${c:-NA}"
}

step05(){
  local s="$OUT/summary.csv" os ps om pm
  os=$(astats "$REF"); ps=$(astats "$POLISHED")
  om=$(mqval "$OUT/original.merqury.qv" "$OUT/original.merqury.completeness.stats")
  pm=$(mqval "$OUT/polished.merqury.qv" "$OUT/polished.merqury.completeness.stats")
  echo 'assembly,contigs,total_bp,N50_bp,longest_contig_bp,primary_mapped_pct,properly_paired_pct,mean_depth,breadth_1x_pct,merqury_QV,merqury_error_rate,merqury_completeness_pct' > "$s"
  echo "original,$os,$(mval "$OUT/original.mapping_metrics.tsv" primary_mapped_pct),$(mval "$OUT/original.mapping_metrics.tsv" properly_paired_pct),$(mval "$OUT/original.mapping_metrics.tsv" mean_depth),$(mval "$OUT/original.mapping_metrics.tsv" breadth_1x_pct),$om" >> "$s"
  echo "polished,$ps,$(mval "$OUT/polished.mapping_metrics.tsv" primary_mapped_pct),$(mval "$OUT/polished.mapping_metrics.tsv" properly_paired_pct),$(mval "$OUT/polished.mapping_metrics.tsv" mean_depth),$(mval "$OUT/polished.mapping_metrics.tsv" breadth_1x_pct),$pm" >> "$s"
  cat "$s"
}

step06(){
  { sha256sum "$REF" "$R1" "$R2"; find "$OUT" -maxdepth 1 -type f ! -name '.gitkeep' -print0 | sort -z | xargs -0 sha256sum; } \
    | sed "s#${ROOT}/##g" > "$CHECKSUMS"
  cat "$CHECKSUMS"
}

run_step 00_fetch_data step00
run_step 01_map_original step01
run_step 02_nextpolish step02
run_step 03_map_polished step03
run_step 04_merqury step04
run_step 05_summary step05
run_step 06_checksums step06

echo "Done. Scientific outputs: outputs/ ; checksums: CHECKSUMS.txt"
