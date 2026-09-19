#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C
export LANG=C
export TZ=UTC

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$ROOT"

# Canonical run used 4 threads. This can be overridden, but 4 is recommended
# when reproducing the committed canonical outputs.
THREADS="${THREADS:-4}"

SRA_RUN="DRR172337"
SPOTS="300000"
NUCCORE_ACCESSION="AP024628.1"
ASSEMBLY_ACCESSION="GCA_019704475.1"
BIOSAMPLE="SAMD00163116"
KMER="21"

INPUT="$ROOT/input"
WORK="$ROOT/work"
OUT="$ROOT/outputs"
LOG="$ROOT/logs"
META="$ROOT/metadata"

mkdir -p "$INPUT" "$WORK" "$OUT" "$LOG" "$META"

REF="$INPUT/reference.fasta"
R1="$INPUT/reads_R1.fastq"
R2="$INPUT/reads_R2.fastq"
POLISHED="$OUT/polished.fasta"
GENERATED_CHECKSUMS="$ROOT/CHECKSUMS.generated.txt"
CANONICAL_CHECKSUMS="$ROOT/CHECKSUMS.txt"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

need() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
}

check() {
    local file="$1"
    [[ -s "$file" ]] || die "Expected non-empty file not found: $file"
}

run_step() {
    local step="$1"
    shift

    local log="$LOG/${step}.o"
    local status

    echo
    echo "===== $step ====="
    echo "Log: $log"

    {
        echo "======================================================================"
        echo "Step:       $step"
        echo "Started:    $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "Host:       $(hostname)"
        echo "Project:    $ROOT"
        echo "Threads:    $THREADS"
        echo "======================================================================"
        echo
    } > "$log"

    set +e
    "$@" 2>&1 | tee -a "$log"
    status=${PIPESTATUS[0]}
    set -e

    {
        echo
        echo "Finished:  $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "Exit_code: $status"
    } | tee -a "$log"

    [[ "$status" -eq 0 ]] || die "$step failed; inspect $log"
}

for cmd in curl fastq-dump bwa samtools nextPolish meryl merqury.sh sha256sum awk sed grep sort tee; do
    need "$cmd"
done

###############################################################################
# Record tool versions
###############################################################################

{
    echo "project=Bacillus subtilis BEST3145 reproducibility analysis"
    echo "assembly=$ASSEMBLY_ACCESSION"
    echo "nucleotide=$NUCCORE_ACCESSION"
    echo "biosample=$BIOSAMPLE"
    echo "sra_run=$SRA_RUN"
    echo "spots=$SPOTS"
    echo "kmer=$KMER"
    echo "threads=$THREADS"
    echo
    echo "[fastq-dump]"
    fastq-dump --version 2>&1 | head -n 2 || true
    echo
    echo "[bwa]"
    bwa 2>&1 | grep -m1 Version || true
    echo
    echo "[samtools]"
    samtools --version | head -n 1 || true
    echo
    echo "[NextPolish]"
    nextPolish --version 2>&1 || true
    echo
    echo "[meryl]"
    meryl --version 2>&1 | head -n 2 || true
    echo
    echo "[merqury]"
    merqury.sh 2>&1 | head -n 3 || true
} > "$META/software_versions.txt"

###############################################################################
# STEP 00 - Public input data
###############################################################################

step00() {
    echo "Assembly accession : $ASSEMBLY_ACCESSION"
    echo "Chromosome         : $NUCCORE_ACCESSION"
    echo "BioSample          : $BIOSAMPLE"
    echo "Illumina run       : $SRA_RUN"
    echo "SRA spots          : $SPOTS"

    if [[ ! -s "$REF" ]]; then
        echo
        echo "Downloading reference chromosome..."
        curl \
            --fail \
            --location \
            --retry 3 \
            --silent \
            --show-error \
            "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=${NUCCORE_ACCESSION}&rettype=fasta&retmode=text" \
            > "$REF"
    else
        echo "Reference already exists; reusing it."
    fi

    check "$REF"
    grep -q "$NUCCORE_ACCESSION" "$REF" || die "Reference FASTA is not $NUCCORE_ACCESSION"

    if [[ ! -s "$R1" || ! -s "$R2" ]]; then
        echo
        echo "Retrieving first $SPOTS SRA spots from $SRA_RUN..."

        rm -f \
            "$INPUT/${SRA_RUN}_1.fastq" \
            "$INPUT/${SRA_RUN}_2.fastq" \
            "$R1" \
            "$R2"

        fastq-dump \
            --split-files \
            --skip-technical \
            -X "$SPOTS" \
            --outdir "$INPUT" \
            "$SRA_RUN"

        check "$INPUT/${SRA_RUN}_1.fastq"
        check "$INPUT/${SRA_RUN}_2.fastq"

        mv "$INPUT/${SRA_RUN}_1.fastq" "$R1"
        mv "$INPUT/${SRA_RUN}_2.fastq" "$R2"
    else
        echo "FASTQ subset already exists; reusing it."
    fi

    check "$R1"
    check "$R2"

    local n1
    local n2
    n1="$(awk 'END{print NR/4}' "$R1")"
    n2="$(awk 'END{print NR/4}' "$R2")"

    echo "R1_records=$n1"
    echo "R2_records=$n2"

    [[ "$n1" == "$n2" ]] || die "R1 and R2 read counts differ"
    [[ "$n1" == "$SPOTS" ]] || die "Expected $SPOTS paired spots but found $n1"

    cat > "$META/data_sources.tsv" <<META
field	value
organism	Bacillus subtilis BEST3145
assembly_accession	$ASSEMBLY_ACCESSION
nucleotide_accession	$NUCCORE_ACCESSION
biosample	$BIOSAMPLE
illumina_run	$SRA_RUN
subset_rule	first $SPOTS SRA spots
reference_file	input/reference.fasta
read1_file	input/reads_R1.fastq
read2_file	input/reads_R2.fastq
META
}

###############################################################################
# Mapping and mapping metrics
###############################################################################

map_measure() {
    # Keep declarations and assignments separate.  With `set -u`, using label
    # while assigning it in the same `local` statement can cause an unbound
    # variable error on some Bash versions.
    local ref
    local label
    local idx
    local index_ref
    local bam
    local fs
    local mt
    local total
    local mapped
    local proper
    local depth
    local breadth

    ref="$1"
    label="$2"
    idx="$WORK/index_${label}"
    index_ref="$idx/reference.fasta"
    bam="$WORK/${label}.sorted.bam"
    fs="$OUT/${label}.flagstat.txt"
    mt="$OUT/${label}.mapping_metrics.tsv"

    check "$ref"
    check "$R1"
    check "$R2"

    echo "Reference: $ref"
    echo "Label:     $label"

    rm -rf "$idx"
    mkdir -p "$idx"
    cp "$ref" "$index_ref"

    bwa index "$index_ref"

    bwa mem \
        -t "$THREADS" \
        "$index_ref" \
        "$R1" \
        "$R2" \
    | samtools sort \
        -@ "$THREADS" \
        -o "$bam"

    check "$bam"
    samtools index -@ "$THREADS" "$bam"
    samtools flagstat -@ "$THREADS" "$bam" > "$fs"
    check "$fs"

    total="$(grep -m1 'in total' "$fs" | awk '{print $1}' || true)"

    mapped="$(
        grep -m1 'primary mapped' "$fs" \
        | sed -nE 's/.*\(([0-9.]+)%.*\).*/\1/p' \
        || true
    )"

    if [[ -z "${mapped:-}" ]]; then
        mapped="$(
            grep -m1 ' mapped (' "$fs" \
            | sed -nE 's/.*\(([0-9.]+)%.*\).*/\1/p' \
            || true
        )"
    fi

    proper="$(
        grep -m1 'properly paired' "$fs" \
        | sed -nE 's/.*\(([0-9.]+)%.*\).*/\1/p' \
        || true
    )"

    read -r depth breadth < <(
        samtools depth -aa "$bam" \
        | awk '
            {
                n++
                sum += $3
                if ($3 > 0) covered++
            }
            END {
                if (n > 0)
                    printf "%.6f %.6f\n", sum/n, 100*covered/n
                else
                    print "0 0"
            }
        '
    )

    {
        printf 'metric\tvalue\n'
        printf 'total_reads\t%s\n' "${total:-NA}"
        printf 'primary_mapped_pct\t%s\n' "${mapped:-NA}"
        printf 'properly_paired_pct\t%s\n' "${proper:-NA}"
        printf 'mean_depth\t%s\n' "${depth:-NA}"
        printf 'breadth_1x_pct\t%s\n' "${breadth:-NA}"
    } > "$mt"

    check "$mt"
    cat "$mt"
}

###############################################################################
# STEP 01 - Map to original
###############################################################################

step01() {
    map_measure "$REF" original
}

###############################################################################
# STEP 02 - NextPolish short-read polishing
###############################################################################

step02() {
    local np
    local fofn
    local cfg
    local result

    np="$WORK/nextpolish"
    fofn="$WORK/sgs.fofn"
    cfg="$WORK/nextpolish.cfg"
    result="$np/genome.nextpolish.fasta"

    rm -rf "$np"
    mkdir -p "$np"

    printf '%s\n%s\n' "$R1" "$R2" > "$fofn"

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

    echo "NextPolish configuration:"
    cat "$cfg"

    nextPolish "$cfg"
    check "$result"

    cp "$result" "$POLISHED"
    check "$POLISHED"
}

###############################################################################
# STEP 03 - Map to polished assembly
###############################################################################

step03() {
    check "$POLISHED"
    map_measure "$POLISHED" polished
}

###############################################################################
# STEP 04 - Meryl / Merqury
###############################################################################

step04() {
    local mq
    local db

    mq="$WORK/merqury"
    db="$mq/reads.meryl"

    rm -rf "$mq"
    mkdir -p "$mq"
    cd "$mq"

    meryl \
        k="$KMER" \
        count \
        output "$db" \
        "$R1" \
        "$R2"

    [[ -d "$db" ]] || die "Meryl database was not created: $db"

    merqury.sh "$db" "$REF" original
    merqury.sh "$db" "$POLISHED" polished

    for f in \
        original.qv \
        original.completeness.stats \
        polished.qv \
        polished.completeness.stats
    do
        check "$mq/$f"
    done

    cp "$mq/original.qv" "$OUT/original.merqury.qv"
    cp "$mq/original.completeness.stats" "$OUT/original.merqury.completeness.stats"
    cp "$mq/polished.qv" "$OUT/polished.merqury.qv"
    cp "$mq/polished.completeness.stats" "$OUT/polished.merqury.completeness.stats"

    cd "$ROOT"
}

###############################################################################
# Summary helpers
###############################################################################

astats() {
    local fasta="$1"

    awk '
        /^>/ {
            if (len > 0) print len
            len=0
            next
        }
        { len += length($0) }
        END { if (len > 0) print len }
    ' "$fasta" \
    | sort -nr \
    | awk '
        {
            a[NR]=$1
            total += $1
        }
        END {
            half=total/2
            running=0
            n50="NA"
            for (i=1; i<=NR; i++) {
                running += a[i]
                if (n50=="NA" && running>=half) n50=a[i]
            }
            printf "%d,%d,%s,%d", NR,total,n50,a[1]
        }
    '
}

mval() {
    local file="$1"
    local metric="$2"
    awk -F '\t' -v m="$metric" '$1==m{print $2}' "$file"
}

mqval() {
    local qv_file="$1"
    local comp_file="$2"
    local q
    local e
    local c

    q="$(awk 'NF>=5{print $4;exit}' "$qv_file")"
    e="$(awk 'NF>=5{print $5;exit}' "$qv_file")"
    c="$(awk 'NF>=5&&$2=="all"{print $5;exit}' "$comp_file")"

    if [[ -z "${c:-}" ]]; then
        c="$(awk 'NF>=5{print $5;exit}' "$comp_file")"
    fi

    printf '%s,%s,%s' "${q:-NA}" "${e:-NA}" "${c:-NA}"
}

###############################################################################
# STEP 05 - Scientific summary
###############################################################################

step05() {
    local summary
    local original_stats
    local polished_stats
    local original_mq
    local polished_mq

    summary="$OUT/summary.csv"

    original_stats="$(astats "$REF")"
    polished_stats="$(astats "$POLISHED")"

    original_mq="$(
        mqval \
            "$OUT/original.merqury.qv" \
            "$OUT/original.merqury.completeness.stats"
    )"

    polished_mq="$(
        mqval \
            "$OUT/polished.merqury.qv" \
            "$OUT/polished.merqury.completeness.stats"
    )"

    echo 'assembly,contigs,total_bp,N50_bp,longest_contig_bp,primary_mapped_pct,properly_paired_pct,mean_depth,breadth_1x_pct,merqury_QV,merqury_error_rate,merqury_completeness_pct' > "$summary"

    echo "original,$original_stats,$(mval "$OUT/original.mapping_metrics.tsv" primary_mapped_pct),$(mval "$OUT/original.mapping_metrics.tsv" properly_paired_pct),$(mval "$OUT/original.mapping_metrics.tsv" mean_depth),$(mval "$OUT/original.mapping_metrics.tsv" breadth_1x_pct),$original_mq" >> "$summary"

    echo "polished,$polished_stats,$(mval "$OUT/polished.mapping_metrics.tsv" primary_mapped_pct),$(mval "$OUT/polished.mapping_metrics.tsv" properly_paired_pct),$(mval "$OUT/polished.mapping_metrics.tsv" mean_depth),$(mval "$OUT/polished.mapping_metrics.tsv" breadth_1x_pct),$polished_mq" >> "$summary"

    check "$summary"
    cat "$summary"
}

###############################################################################
# STEP 06 - Generate checksums for THIS run
#
# IMPORTANT: Do NOT overwrite CHECKSUMS.txt.  CHECKSUMS.txt is the canonical
# reference committed to the repository.  Independent reruns must be compared
# against it, not replace it.
###############################################################################

step06() {
    {
        sha256sum "$REF" "$R1" "$R2"

        find "$OUT" \
            -maxdepth 1 \
            -type f \
            ! -name '.gitkeep' \
            -print0 \
        | sort -z \
        | xargs -0 sha256sum
    } \
    | sed "s#${ROOT}/##g" \
    > "$GENERATED_CHECKSUMS"

    check "$GENERATED_CHECKSUMS"

    echo "Generated checksums for this run:"
    cat "$GENERATED_CHECKSUMS"

    if [[ -s "$CANONICAL_CHECKSUMS" ]]; then
        echo
        echo "Canonical checksum file is present and was NOT overwritten:"
        echo "  $CANONICAL_CHECKSUMS"
    else
        echo
        echo "WARNING: Canonical CHECKSUMS.txt is absent."
        echo "For a new canonical analysis, review this run and then copy:"
        echo "  cp CHECKSUMS.generated.txt CHECKSUMS.txt"
    fi
}

###############################################################################
# Run workflow
###############################################################################

run_step 00_fetch_data step00
run_step 01_map_original step01
run_step 02_nextpolish step02
run_step 03_map_polished step03
run_step 04_merqury step04
run_step 05_summary step05
run_step 06_checksums step06

echo
echo "Analysis complete."
echo "Scientific outputs : $OUT"
echo "Run checksums      : $GENERATED_CHECKSUMS"
echo "Canonical checksums: $CANONICAL_CHECKSUMS"
echo
echo "Verify against the canonical run with:"
echo "  bash verify.sh"
