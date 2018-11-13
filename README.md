# Pipeline for parsing biological sequences

This project is example of pipeline using:

- [TrimGalore](https://github.com/FelixKrueger/TrimGalore/tree/master/)
- [seqtk](https://github.com/lh3/seqtk)
- [FastQC](https://www.bioinformatics.babraham.ac.uk/projects/fastqc/)
- [Velvet](https://github.com/dzerbino/velvet/tree/master)
- [megan6](http://ab.inf.uni-tuebingen.de/software/megan6/)
- [Diamond](https://github.com/bbuchfink/diamond/)
- etc.?

### Example

```
./pipeline.sh --usePercentsOfFile 0.1 --propertiesFile ./properties-test-local.properties -i ./data/SRR6000947_1.fastq.gz -i ./data/SRR6000947_2.fastq.gz
```

Use ```{[<-d|--do> <trimgalor|seqtk|fastqc>] ...}``` to select just certain steps(SW) and thus avoid unnecessary processes and reuse already generated files (not using SW workspace backup).
