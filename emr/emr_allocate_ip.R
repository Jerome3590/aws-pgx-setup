library(jsonlite)
library(here)

# Setup local environment
setup_environment <- function() {
  cwd <- here::here()
  Sys.setenv("CWD" = cwd)
  return(cwd)
}

# Execute shell command and return output
execute_shell_command <- function(command) {
  output <- system(command, intern = TRUE)
  return(output)
}

# Get EMR Cluster Info
get_emr_cluster_info <- function(cwd) {
  command <- paste("aws emr list-clusters --active --profile pgx | tee", 
                   file.path(cwd, "cluster-config/cluster_info.json"))
  execute_shell_command(command)
}

# Parse EMR Cluster ID
parse_emr_cluster_id <- function() {
  cluster_json <- read_json(here("cluster-config", "cluster_info.json"))
  cluster_id <- as.data.frame(cluster_json[["Clusters"]][[1]][["Id"]])
  names(cluster_id) <- "cluster_id"
  write.table(cluster_id, here("cluster-config", "cluster_id.csv"), sep = ";", 
              col.names = FALSE, row.names = FALSE)
  Sys.setenv("CLUSTER_ID" = cluster_id)
  return(cluster_id)
}

# Get EMR Cluster Configuration
get_emr_cluster_config <- function(cluster_id) {
  command <- paste("aws emr describe-cluster --cluster-id", cluster_id, 
                   "--profile pgx | tee", file.path(Sys.getenv("CWD"), "cluster-config/cluster_description.json"))
  execute_shell_command(command)
}

# Parse EMR Head Node Info
parse_emr_head_node_info <- function() {
  emr_json <- read_json(here("cluster-config", "emr_node.json"))
  emr_dns <- emr_json[["Instances"]][[1]][["PublicDnsName"]]
  emr_instance_id <- emr_json[["Instances"]][[1]][["Ec2InstanceId"]]
  emr_instance_id <- as.data.frame(emr_instance_id)
  write.table(emr_instance_id, here("cluster-config", "emr_instance_id.csv"), 
              sep = ";", col.names = FALSE, row.names = FALSE)
  Sys.setenv("EMR_NODE_ID" = emr_instance_id)
  return(list(emr_dns, emr_instance_id))
}

# Allocate Elastic IP to AWS EMR Head Node
allocate_elastic_ip <- function(emr_instance_id) {
  command <- paste("aws ec2 associate-address --instance-id", emr_instance_id, 
                   "--allocation-id eipalloc-0d2b32dc1f19a9a4a --profile pgx")
  execute_shell_command(command)
}

# Main function
main <- function() {
  cwd <- setup_environment()
  get_emr_cluster_info(cwd)
  cluster_id <- parse_emr_cluster_id()
  get_emr_cluster_config(cluster_id)
  node_info <- parse_emr_head_node_info()
  allocate_elastic_ip(node_info[[2]])
}

# Execute the main function
main()
