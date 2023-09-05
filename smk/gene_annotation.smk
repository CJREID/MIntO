#!/usr/bin/env python

'''
Gene prediction and functional annotation step

Authors: Vithiagaran Gunalan, Carmen Saenz, Mani Arumugam
'''

# configuration yaml file
# import sys
import pathlib
from os import path

# Get common config variables
# These are:
#   config_path, project_id, omics, working_dir, minto_dir, script_dir, metadata
include: 'include/cmdline_validator.smk'
include: 'include/config_parser.smk'

if config['map_reference'] in ("MAG", "reference_genome"):
    map_reference=config["map_reference"]
else:
    print('ERROR in ', config_path, ': map_reference variable is not correct. "map_reference" variable should be MAG or reference_genome.')

mag_omics = 'metaG'
if map_reference == 'MAG':
    if 'MAG_omics' in config and config['MAG_omics'] != None:
        mag_omics = config['MAG_omics']
    reference_dir="{wd}/{mag_omics}/8-1-binning/mags_generation_pipeline/unique_genomes".format(wd=working_dir, mag_omics=mag_omics)
    print('NOTE: MIntO is using "' + reference_dir + '" as PATH_reference variable')
elif map_reference == 'reference_genome':
    if config['PATH_reference'] is None:
        print('ERROR in ', config_path, ': PATH_reference variable is empty. Please, complete ', config_path)
    reference_dir=config["PATH_reference"]
    print('NOTE: MIntO is using "'+ reference_dir+'" as PATH_reference variable')

if path.exists(reference_dir) is False:
    print('ERROR in ', config_path, ': reference genome path ', reference_dir, ' does not exit. Please, complete ', config_path)

if 'ANNOTATION' in config:
    if config['ANNOTATION'] is None:
        print('ERROR in ', config_path, ': ANNOTATION list is empty. "ANNOTATION" variable should be dbCAN, KEGG and/or eggNOG. Please, complete ', config_path)
    else:
        try:
            # Make list of illumina samples, if ILLUMINA in config
            annot_list = list()
            if 'ANNOTATION' in config:
                #print("Samples:")
                for annot in config["ANNOTATION"]:
                    if annot in ('dbCAN', 'KEGG', 'eggNOG'):
                        annot_list.append(annot)
                        pass
                    else:
                        raise TypeError('ANNOTATION variable is not correct. "ANNOTATION" variable should be dbCAN, KEGG and/or eggNOG. Please, complete ', config_path)
        except:
            print('ERROR in ', config_path, ': ANNOTATION variable is not correct. "ANNOTATION" variable should be dbCAN, KEGG and/or eggNOG.')
else:
    print('ERROR in ', config_path, ': ANNOTATION list is empty. "ANNOTATION" variable should be dbCAN, KEGG and/or eggNOG. Please, complete', config_path)

# Define all the outputs needed by target 'all'

if map_reference == 'MAG':
    post_analysis_dir="9-MAG-genes-post-analysis"
    post_analysis_out="MAG-genes"
elif map_reference == 'reference_genome':
    post_analysis_dir="9-refgenome-genes-post-analysis"
    post_analysis_out="refgenome-genes"
elif map_reference == 'genes_db':
    post_analysis_dir="9-db-genes-post-analysis"
    post_analysis_out="db-genes"

if map_reference == 'genes_db':
    def merge_genes_output(): # CHECK THIS PART - do not output anything when map_reference == 'genes_db'
        result = expand()
        return(result)

def predicted_genes_collate_out():
    result = expand("{wd}/DB/{post_analysis_dir}/annot/{post_analysis_out}_translated_cds_SUBSET.annotations.tsv",
                    wd = working_dir,
                    post_analysis_dir = post_analysis_dir,
                    post_analysis_out = post_analysis_out)
    return(result)

rule all:
    input:
        predicted_genes_collate_out()


###############################################################################################
# Prepare predicted genes for annotation
## Combine faa and bed files from the different genomes
###############################################################################################

# Get a sorted list of genomes

def get_genomes_from_refdir(ref_dir):
    genomes = [ pathlib.Path(f).stem for f in os.scandir(ref_dir) if f.is_file() and f.name.endswith('.fna') ]
    return(sorted(genomes))

########################
# Prokka on an fna file in reference_dir.
# To make it reproducible, we assign locus_tag based on the name of the MAG/genome.
# This makes testing and benchmarking easier.
########################

rule prokka_for_genome:
    input: lambda wildcards: "{reference_dir}/{genome}.fna".format(reference_dir=reference_dir, genome=wildcards.genome)
    output:
        fna="{wd}/DB/{post_analysis_dir}/genomes/{genome}/{genome}.fna",
        faa="{wd}/DB/{post_analysis_dir}/genomes/{genome}/{genome}.faa",
        gff="{wd}/DB/{post_analysis_dir}/genomes/{genome}/{genome}.gff",
    log:
        "{wd}/logs/DB/{post_analysis_dir}/prokka/{genome}.log"
    resources:
        mem=10
    threads: 8
    conda:
        config["minto_dir"]+"/envs/gene_annotation.yml"
    shell:
        """
        rm -rf $(dirname {output})
        locus_tag=$(echo "{wildcards.genome}" | md5sum | cut -f1 -d' ' | tr -s '0-9' 'G-P' | tr -s 'a-z' 'A-Z' | cut -c1-10)
        prokka --outdir $(dirname {output.fna}) --prefix {wildcards.genome} --locustag $locus_tag --addgenes --cdsrnaolap --cpus {threads} --centre X --compliant {input} >& {log}
        """

# Combine FAA files ####

rule make_cd_transl_faa_for_genome:
    input: rules.prokka_for_genome.output.faa
    output: "{wd}/DB/{post_analysis_dir}/CD_transl/{genome}.faa"
    log:
        "{wd}/logs/DB/{post_analysis_dir}/{genome}.reformat_faa.log"
    conda:
        config["minto_dir"]+"/envs/MIntO_base.yml" #seqtk
    shell:
        """
        time (seqtk seq -l 0 {input} | sed -e "s/^>/>{wildcards.genome}|/g" > {output}) >& {log}
        """

def get_genome_cd_transl_faa(wildcards):
    #Collect the CDS faa files for MAGs
    genomes = get_genomes_from_refdir(reference_dir)
    result = expand("{wd}/DB/{post_analysis_dir}/CD_transl/{genome}.faa",
                    wd=wildcards.wd,
                    post_analysis_dir=wildcards.post_analysis_dir,
                    genome=genomes)
    return(result)

rule make_merged_cds_faa:
    input: get_genome_cd_transl_faa
    output:
        merged_cds="{wd}/DB/{post_analysis_dir}/{post_analysis_out}_translated_cds.faa"
    wildcard_constraints:
        post_analysis_out='MAG-genes|refgenome-genes'
    shell:
        """
        cat {input} > {output}
        """

# Convert GFF file into BED file ####

rule make_bed_for_genome:
    input: rules.prokka_for_genome.output.gff
    output:
        bed=                      "{wd}/DB/{post_analysis_dir}/GFF/{genome}.bed",
        bed_hdr_mod=              "{wd}/DB/{post_analysis_dir}/GFF/{genome}.header-modif.bed",
        bed_hdr_mod_coord_correct="{wd}/DB/{post_analysis_dir}/GFF/{genome}.header-modif.coord_correct.bed"
    log:
        "{wd}/logs/DB/{post_analysis_dir}/{genome}.make_bed_from_gff.log"
    conda:
        config["minto_dir"]+"/envs/MIntO_base.yml" #gff2bed
    shell:
        """
        time (\
            gff2bed < {input} > {output.bed}
            sed -e "s/^gnl|X|/{wildcards.genome}|/g" {output.bed} > {output.bed_hdr_mod}
            awk -v FS='\\t' -v OFS='\\t' '{{$2+=1; print $0}}' {output.bed_hdr_mod} > {output.bed_hdr_mod_coord_correct} \
        ) >& {log}
        """

def get_genome_bed(wildcards):
    #Collect the BED files for MAGs
    genomes = get_genomes_from_refdir(reference_dir)
    result = expand("{wd}/DB/{post_analysis_dir}/GFF/{genome}.header-modif.coord_correct.bed",
                    wd=wildcards.wd,
                    post_analysis_dir=wildcards.post_analysis_dir,
                    genome=genomes)
    return(result)

rule make_merged_bed:
    input: get_genome_bed
    output:
        bed_file="{wd}/DB/{post_analysis_dir}/{post_analysis_out}.bed",
    log:
        "{wd}/logs/DB/{post_analysis_dir}/{post_analysis_out}.merge_bed.log"
    wildcard_constraints:
        post_analysis_out='MAG-genes|refgenome-genes'
    shell:
        """
        time (\
            cat {input} \
                    | awk -F'\\t' '{{gsub(/[;]/, "\\t", $10)}} 1' OFS='\\t' \
                    | cut -f 1-10 \
                    > {output.bed_file} \
        ) >& {log}
        """

rule gene_annot_subset:
    input:
        bed_file=       rules.make_merged_bed.output.bed_file,
        merged_cds=     rules.make_merged_cds_faa.output.merged_cds
    output:
        bed_subset="{wd}/DB/{post_analysis_dir}/{post_analysis_out}_SUBSET.bed",
        fasta_subset="{wd}/DB/{post_analysis_dir}/{post_analysis_out}_translated_cds_SUBSET.faa",
    log:
        "{wd}/logs/DB/{post_analysis_dir}/{post_analysis_out}_subset_out.log"
    resources:
        mem=5
    threads: 8
    conda:
        config["minto_dir"]+"/envs/r_pkgs.yml"
    shell:
        """
        remote_dir={wildcards.wd}/DB/{post_analysis_dir}/
        time (Rscript {script_dir}/MAGs_genes_out_subset.R {threads} {input.bed_file} {input.merged_cds} ${{remote_dir}} {post_analysis_out}) &> {log}
        """

################################################################################################
# Genes annotation using 3 different tools to retrieve functions from:
## KEGG
## eggNOG
## dbCAN
################################################################################################

rule gene_annot_kofamscan:
    input:
        fasta_subset=rules.gene_annot_subset.output.fasta_subset
    output:
        kofam_out="{wd}/DB/{post_analysis_dir}/annot/{post_analysis_out}_translated_cds_SUBSET_KEGG.tsv",
    shadow:
        "minimal"
    params:
        kofam_db=lambda wildcards: "{minto_dir}/data/kofam_db/".format(minto_dir = minto_dir) #config["KOFAM_db"]
    log:
        "{wd}/logs/DB/{post_analysis_dir}/{post_analysis_out}_kofamscan.log"
    resources:
        mem=10
    threads: 16
    conda:
        config["minto_dir"]+"/envs/gene_annotation.yml"
    shell:
        """
        remote_dir=$(dirname {output.kofam_out})
        time (exec_annotation -k {params.kofam_db}/ko_list -p {params.kofam_db}/profiles/prokaryote.hal --tmp-dir tmp --create-alignment -f mapper --cpu {threads} -o kofam_mapper.txt {input.fasta_subset}
        {script_dir}/kofam_hits.pl kofam_mapper.txt > KEGG.tsv
        sed -i 's/\\;K/\\,K/g' KEGG.tsv
        mkdir -p ${{remote_dir}}
        rsync -a KEGG.tsv {output.kofam_out}) &> {log}
        """

rule gene_annot_dbcan:
    input:
        fasta_subset=rules.gene_annot_subset.output.fasta_subset
    output:
        dbcan_out="{wd}/DB/{post_analysis_dir}/annot/{post_analysis_out}_translated_cds_SUBSET_dbCAN.tsv",
    shadow:
        "minimal"
    params:
        prefix="{post_analysis_out}_translated_cds_SUBSET",
        dbcan_db=lambda wildcards: "{minto_dir}/data/dbCAN_db/V12/".format(minto_dir = minto_dir)
    log:
        "{wd}/logs/DB/{post_analysis_dir}/{post_analysis_out}_dbcan.log"
    resources:
        mem=10
    threads: 16
    conda:
        config["minto_dir"]+"/envs/gene_annotation.yml"
    shell:
        """
        time (run_dbcan {input.fasta_subset} protein --db_dir {params.dbcan_db} --dia_cpu {threads} --out_pre {params.prefix}_ --out_dir out
        {script_dir}/process_dbcan_overview.pl out/{params.prefix}_overview.txt > out/{params.prefix}_dbCAN.tsv
        rsync out/* {wildcards.wd}/DB/{post_analysis_dir}/annot/ )&> {log}
        """

rule gene_annot_eggnog:
    input:
        fasta_subset=rules.gene_annot_subset.output.fasta_subset
    output:
        eggnog_out="{wd}/DB/{post_analysis_dir}/annot/{post_analysis_out}_translated_cds_SUBSET_eggNOG.tsv",
    shadow:
        "minimal"
    params:
        prefix="{post_analysis_out}_translated_cds_SUBSET",
        eggnog_db= lambda wildcards: "{minto_dir}/data/eggnog_data/".format(minto_dir = minto_dir) #config["EGGNOG_db"]
    log:
        "{wd}/logs/DB/{post_analysis_dir}/{post_analysis_out}_eggnog.log"
    resources:
        mem=10
    threads: 24
    conda:
        config["minto_dir"]+"/envs/gene_annotation.yml"
    shell:
        """
        time (
        [[ -d /dev/shm/eggnog_data ]] || mkdir /dev/shm/eggnog_data
        eggnogdata=(eggnog.db eggnog_proteins.dmnd eggnog.taxa.db eggnog.taxa.db.traverse.pkl)
        for e in "${{eggnogdata[@]}}"
            do [[ -f /dev/shm/eggnog_data/$e ]] || cp {params.eggnog_db}/data/$e /dev/shm/eggnog_data/
        done
        mkdir out
        emapper.py --data_dir /dev/shm/eggnog_data/ -o {params.prefix} \
                   --no_annot --no_file_comments --report_no_hits --override --output_dir out -m diamond -i {input.fasta_subset} --cpu {threads}
        emapper.py --annotate_hits_table out/{params.prefix}.emapper.seed_orthologs \
                   --data_dir /dev/shm/eggnog_data/ -m no_search --no_file_comments --override -o {params.prefix} --output_dir out --cpu {threads}
        cut -f 1,5,12,13,14,21 out/{params.prefix}.emapper.annotations > out/{params.prefix}.eggNOG
        {script_dir}/process_eggNOG_OGs.pl out/{params.prefix}.eggNOG > out/{params.prefix}_eggNOG.tsv
        rm out/{params.prefix}.eggNOG
        sed -i 's/\#query/ID/' out/{params.prefix}_eggNOG.tsv
        sed -i 's/ko\://g' out/{params.prefix}_eggNOG.tsv
        rsync out/* {wildcards.wd}/DB/{post_analysis_dir}/annot/)&> {log}
        rm -rf /dev/shm/eggnog_data
        """

################################################################################################
# Combine gene annotation results into one file
################################################################################################

rule predicted_gene_annotation_collate:
    input:
        annot_out=expand("{{wd}}/DB/{{post_analysis_dir}}/annot/{{post_analysis_out}}_translated_cds_SUBSET_{annot}.tsv", annot=annot_list)
    output:
        annot_out="{wd}/DB/{post_analysis_dir}/annot/{post_analysis_out}_translated_cds_SUBSET.annotations.tsv",
    params:
        prefix="{post_analysis_out}_translated_cds_SUBSET",
    log:
        "{wd}/logs/DB/{post_analysis_dir}/{post_analysis_out}_annot.log"
    resources:
        mem=10
    threads: 9
    conda:
        config["minto_dir"]+"/envs/mags.yml" # python with pandas
    shell:
        """
        time (python3 {script_dir}/collate.py {wildcards.wd}/DB/{post_analysis_dir}/annot/ {params.prefix})&> {log}
        """
