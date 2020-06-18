# Pipeline for parsing biological sequences

This project is example of pipeline using:

- [TrimGalore](https://github.com/FelixKrueger/TrimGalore/tree/master/)
- [seqtk](https://github.com/lh3/seqtk)
- [FastQC](https://www.bioinformatics.babraham.ac.uk/projects/fastqc/)
- [Velvet](https://github.com/dzerbino/velvet/tree/master)
- [megan6](http://ab.inf.uni-tuebingen.de/software/megan6/)
- [Diamond](https://github.com/bbuchfink/diamond/)
- etc.?

### Results

[Presentation](https://docs.google.com/presentation/d/1wQC_K8S8MH2UE6524UuKI-tq8SI91_7oiLgnu8QuvkE/edit)

### Example

```
./pipeline.sh -p ./properties-test-local.properties -i ./data/SRR6000947_1.fastq.gz -i ./data/SRR6000947_2.fastq.gz
```

```
./pipeline.sh -p properties-biolinux.properties -i ./../data/original/SRR6000947_1.fastq.gz -i ./../data/original/SRR6000947_2.fastq.gz &> current.log &
```


```
./pipeline.sh -p properties-biolinux.properties -i ../data/auto/trimgalore-results/SRR6000947_1_val_1.fq.gz -i ../data/auto/trimgalore-results/SRR6000947_2_val_2.fq.gz -d "seqtk" -d "velvet" -d "metaVelvet" -d "diamond" -d "megan6" &> current.log &
```




Use ```{[<-d|--do> <trimgalor|seqtk|fastqc>] ...}``` to select just certain steps(SW) and thus avoid unnecessary processes and reuse already generated files (not using SW workspace backup).
