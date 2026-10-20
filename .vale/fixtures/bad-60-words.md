# Installer

The installer reads the configuration file from the current directory and then checks each entry against the schema before it starts any work on the cluster, and when an entry is missing it prints the name of the entry together with the line number so that the operator can fix the file and run the installer again without losing time.
