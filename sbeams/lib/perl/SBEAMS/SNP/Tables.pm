package SBEAMS::SNP::Tables;

###############################################################################
# Program     : SBEAMS::SNP::Tables
# Author      : Eric Deutsch <edeutsch@systemsbiology.org>
# $Id$
#
# Description : This is part of the SBEAMS::SNP module which provides
#               a level of abstraction to the database tables.
#
###############################################################################


use strict;
use vars qw(@ISA @EXPORT 
    $TB_ORGANISM

    $TBSN_BIOSEQUENCE_SET
    $TBSN_BIOSEQUENCE

    $TBSN_SNP
    $TBSN_SNP_SOURCE
    $TBSN_SOURCE_VERSION
    $TBSN_SNP_INSTANCE
    $TBSN_ALLELE
    $TBSN_ALLELE_FREQUENCY
    $TBSN_ALLELE_BLAST_STATS

    $TBSN_QUERY_OPTION

);

require Exporter;
@ISA = qw (Exporter);

@EXPORT = qw (
    $TB_ORGANISM

    $TBSN_BIOSEQUENCE_SET
    $TBSN_BIOSEQUENCE

    $TBSN_SNP
    $TBSN_SNP_SOURCE
    $TBSN_SOURCE_VERSION
    $TBSN_SNP_INSTANCE
    $TBSN_ALLELE
    $TBSN_ALLELE_FREQUENCY
    $TBSN_ALLELE_BLAST_STATS


    $TBSN_QUERY_OPTION

);


$TB_ORGANISM                = 'sbeams.dbo.organism';

$TBSN_BIOSEQUENCE_SET       = 'SNP.dbo.biosequence_set';
$TBSN_BIOSEQUENCE           = 'SNP.dbo.biosequence';

$TBSN_SNP                   = 'SNP.dbo.snp';
$TBSN_SNP_SOURCE            = 'SNP.dbo.snp_source';
$TBSN_SOURCE_VERSION        = 'SNP.dbo.source_version';
$TBSN_SNP_INSTANCE          = 'SNP.dbo.snp_instance';
$TBSN_ALLELE                = 'SNP.dbo.allele';
$TBSN_ALLELE_FREQUENCY      = 'SNP.dbo.allele_frequency';
$TBSN_ALLELE_BLAST_STATS    = 'SNP.dbo.allele_blast_stats';

$TBSN_QUERY_OPTION          = 'SNP.dbo.query_option';


