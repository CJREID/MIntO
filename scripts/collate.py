#!/usr/bin/python

# '''
# integrates the different gene annotations from eggnog-mapper, dbcan and kofamscan

# Authors: Vithiagaran Gunalan
# '''

import pandas as pd
import numpy as np
import sys
import os
import sys

mydir = sys.argv[1]
name = sys.argv[2]

eggnog = pd.DataFrame()
dbcan  = pd.DataFrame()
kofam  = pd.DataFrame()

eggnogfile = mydir+"/"+name+"_eggNOG.tsv"
if os.path.exists(eggnogfile):
    eggnog = pd.read_csv(eggnogfile, sep="\t", index_col=False)
    eggnog.set_index("ID", inplace=True)
    df = eggnog 

dbcanfile = mydir+"/"+name+"_dbCAN.tsv"
if os.path.exists(dbcanfile):
    dbcan = pd.read_csv(dbcanfile, sep="\t", index_col=False)
    dbcan.set_index("ID", inplace=True)
    df = dbcan 

kofamfile = mydir+"/"+name+"_KEGG.tsv"
if os.path.exists(kofamfile):
    kofam = pd.read_csv(kofamfile, sep="\t", index_col=False)
    kofam.set_index("ID", inplace=True)
    df = kofam 

# eggnog and kofam
if (not eggnog.empty and not kofam.empty):
    KOdf = pd.merge(eggnog,kofam, on="ID", how="outer").fillna("-")
    kegglist = KOdf['KEGG_ko'].tolist()
    kofamlist = KOdf['kofam_KO'].tolist()
    newlist = []
    final = []
    for i in range(len(kofamlist)):
        mydict = {}
        myline = kegglist[i]+","+kofamlist[i]
        mylist = myline.split(",")
        for i in mylist:
            mydict[i] = ""
        newlist = list(mydict.keys())
        mystring = ""
        if len(newlist) > 1:
            if "-" in newlist:
                newlist.remove("-")
            mystring = ",".join(newlist)
            final.append(mystring)
        else:
            mystring = "".join(newlist)
            final.append(mystring)
    KOdf["KEGG_KO"] = final
    del KOdf['KEGG_ko']
    del KOdf['kofam_KO']
    df = KOdf   
# eggnog and dbcan, no kofam
elif (not eggnog.empty and not dbcan.empty and kofam.empty):
    del df
    eggnog["KEGG_KO"] = eggnog['KEGG_ko']
    del eggnog['KEGG_ko']
    df = pd.merge(eggnog,dbcan, on="ID", how="outer").fillna("-")
# kofam and dbcan, no eggnog
elif (not kofam.empty and not dbcan.empty and eggnog.empty):
    del df
    kofam["KEGG_KO"] = kofam['kofam_KO']
    del kofam['kofam_KO']
    df = pd.merge(dbcan,kofam, on="ID", how="outer").fillna("-")

# eggnog, kofam and dbcan
if (not eggnog.empty and not kofam.empty and not dbcan.empty):
    del df
    df = pd.merge(KOdf,dbcan, on="ID", how="outer").fillna("-")

myoutfile = mydir+"/"+name+".annotations.tsv"

df.to_csv(myoutfile, sep="\t")
