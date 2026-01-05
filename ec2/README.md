# EC2 Workflow Execution - Final Solution

This document describes our production-ready EC2 workflow execution solution for the PGx analysis pipeline.

## Overview

We use **persistent EC2 spot instances** with **idempotency built throughout** the entire workflow. This approach provides:

- **Cost optimization** through spot pricing (up to 90% savings vs on-demand)
- **Reliability** through persistent spot instances that automatically restart after interruption
- **Resilience** through idempotent checkpoints that allow safe resume from any point
- **Efficiency** through pre-configured AMI with libraries and datasets pre-loaded

## Architecture

### Instance Configuration

- **Instance Type**: `x2iedn.8xlarge`
  - 32 vCPUs
  - 1,024 GiB RAM
  - 2 x 1.5 TB NVMe SSDs
  - Up to 100 Gbps network bandwidth
  - Optimized for memory-intensive workloads

- **AMI**: Pre-configured image with:
  - All required libraries and dependencies installed
  - Datasets pre-loaded on `/mnt` drive (instance storage)
  - Project code and configuration ready
  - Jupyter Lab pre-installed and configured in virtual environment (`~/jupyter-env`)
  - Runs as user `pgx3874` with config at `~/.jupyter/jupyter_lab_config.py`

### Storage Architecture

```text
┌─────────────────────────────────────────────────┐
│  EC2 Instance (x2iedn.8xlarge)                  │
├─────────────────────────────────────────────────┤
│                                                 │
│  /mnt (Instance Storage - NVMe SSD)            │
│  ────────────────────────────────               │
│  • Pre-loaded libraries                         │
│  • Pre-loaded datasets                          │
│  • Fast local access                            │
│  • Ephemeral (data persists on stop/start)      │
│                                                 │
│  /project (EBS Volume - gp3)                    │
│  ────────────────────────────────               │
│  • Idempotent checkpoints                       │
│  • Workflow state tracking                      │
│  • Intermediate results                         │
│  • Persistent across instance lifecycle         │
│                                                 │
└─────────────────────────────────────────────────┘
```

**Key Design Principles:**

- **Libraries/Datasets on `/mnt`**: Fast NVMe storage for read-heavy operations
- **Checkpoints on EBS**: Persistent storage ensures workflow can resume after interruption
- **Idempotency**: All pipeline steps check for existing outputs before processing

### Spot Instance Strategy

We use **persistent spot instances** with the following configuration:

```json
{
  "MarketType": "spot",
  "SpotOptions": {
    "SpotInstanceType": "persistent",
    "InstanceInterruptionBehavior": "stop"
  }
}
```

**Benefits:**

- **Persistent**: Automatically restarts after interruption
- **Stop behavior**: Instance state preserved, can resume from checkpoint
- **Cost savings**: Up to 90% cheaper than on-demand instances

## Subnet Selection Strategy

We select subnets based on **cheapest spot pricing** to optimize costs:

### Preferred Subnets

1. **subnet-5de81a53** (us-east-1f)
   - **Primary choice** - typically has the cheapest spot pricing
   - Use this subnet when launching new instances

2. **subnet-5bfc3416** (us-east-1a)
   - **Fallback option** - use if us-east-1f is unavailable
   - Still cost-optimized

### Spot Pricing Check

Before launching, check current spot pricing:

```bash
aws ec2 describe-spot-price-history \
  --instance-types x2iedn.8xlarge \
  --product-descriptions "Linux/UNIX" \
  --start-time $(date -u +"%Y-%m-%dT%H:%M:%SZ") \
  --region us-east-1 \
  --query 'SpotPriceHistory[*].{AZ:AvailabilityZone,Price:SpotPrice}' \
  --output table
```

### Launch Command (Preferred Subnet)

```bash
aws ec2 run-instances \
  --image-id ami-02434e92bf508ded3 \
  --instance-type x2iedn.8xlarge \
  --subnet-id subnet-5de81a53 \
  --security-group-ids sg-0eb0da772c42415dd \
  --iam-instance-profile Name=EC2_Spot \
  --instance-market-options 'MarketType=spot, SpotOptions={SpotInstanceType=persistent, InstanceInterruptionBehavior=stop}' \
  --key-name mushin_pgx
```

## Idempotency Design

### Checkpoint System

All pipeline steps implement idempotent checkpoints:

1. **Check for existing output** before processing
2. **Skip if output exists** and is valid
3. **Resume from checkpoint** if interrupted
4. **State tracking** on EBS volume for persistence

### Example Idempotent Pattern

```python
import os
from pathlib import Path

def process_step(checkpoint_path, output_path):
    """Idempotent processing step."""
    # Check if output already exists
    if os.path.exists(output_path) and os.path.getsize(output_path) > 0:
        logger.info(f"Output already exists: {output_path}, skipping...")
        return
    
    # Create checkpoint
    Path(checkpoint_path).touch()
    
    try:
        # Perform processing
        result = do_work()
        
        # Save output
        save_output(result, output_path)
        
        # Remove checkpoint on success
        os.remove(checkpoint_path)
    except Exception as e:
        logger.error(f"Processing failed: {e}")
        # Checkpoint remains, can resume later
        raise
```

### Benefits

- **Safe interruption**: Can stop/restart instance without losing progress
- **Efficient reruns**: Only processes missing steps
- **Debugging**: Can resume from specific checkpoints
- **Cost savings**: Don't waste compute on already-completed work

## Workflow Execution

### Execution Method: Jupyter Notebook Terminal Sessions

We execute workflows from **Jupyter notebook terminal sessions** to leverage automatic parallelization. This approach provides:

- **Automatic parallelization**: Multiple terminal sessions can run concurrently, utilizing all 32 vCPUs
- **Easy monitoring**: Visual progress tracking through Jupyter interface
- **Flexible execution**: Can run different pipeline steps in parallel across multiple terminals
- **Resource utilization**: Maximizes use of the high-memory instance (1TB RAM)

### Starting a Workflow

1. **Launch or start instance**:

   ```bash
   # Check for existing stopped instance
   aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' --output table
   
   # Start existing instance
   aws ec2 start-instances --instance-ids i-xxxxx
   
   # Or launch new instance in preferred subnet
   aws ec2 run-instances --subnet-id subnet-5de81a53 ...
   ```

2. **Associate Elastic IP** (recommended for persistent access):

   ```bash
   # Get your Elastic IP allocation ID (if you have one)
   # Check existing Elastic IPs
   aws ec2 describe-addresses --query 'Addresses[*].[AllocationId,PublicIp,InstanceId]' --output table
   
   # Associate Elastic IP to your instance
   aws ec2 associate-address \
     --instance-id i-xxxxx \
     --allocation-id eipalloc-xxxxx \
     --allow-reassociation
   
   # Your Elastic IP will persist even if instance stops/starts
   ```

3. **Access Jupyter Lab**:

   - Navigate to `http://<elastic-ip>:8888` (or `http://<instance-ip>:8888` if not using Elastic IP)
   - Log in with your credentials
   - Open a new terminal session from the Jupyter Lab interface

4. **Navigate to project directory**:

   ```bash
   cd ~/pgx-analysis
   # Or if using EBS mount point:
   cd /project/pgx-analysis
   ```

   **Project folder structure** (matches workflow steps):

   ```text
   pgx-analysis/
   ├── 1_apcd_input_data/          # Step 1: APCD data preprocessing (bronze → silver → gold)
   ├── 2_create_cohort/            # Step 2: Cohort creation and QA
   ├── 3_feature_importance/       # Step 3: MC-CV feature importance (aggregated importances)
   ├── 4a_model_data/              # Step 4a: Model-ready event datasets (cases + controls)
   ├── 4b_dtw_filter/              # Step 4b: DTW protocol filtering (administrative codes)
   ├── 5_pgx_analysis/            # Step 5: PGx feature engineering
   ├── 6_final_model_selection/    # Step 6: Final model selection and evaluation
   ├── 7_ffa_analysis/             # Step 7: Formal Feature Attribution (FFA) analysis
   ├── 8_shap_analysis/             # Step 8: SHAP-based post-model analysis
   ├── 9_combined_shap_ffa/         # Step 9: Combined SHAP + FFA consensus analysis
   ├── 10_risk_dashboard/           # Step 10: Risk dashboard (includes BupaR/FP-Growth/DTW visuals)
   ├── utility_scripts/             # Workflow execution scripts (run_cohort_workflow.sh)
   ├── py_helpers/                 # Shared Python utilities
   ├── r_helpers/                  # Shared R utilities
   └── docs/                       # Documentation
   ```

5. **Run initial data preparation** (if not already completed):

   These steps prepare the raw data and create cohorts. Run once before cohort workflows:

   ```bash
   # Step 1: Convert raw data to parquet format
   python 1_apcd_input_data/0_txt_to_parquet.py
   
   # Step 1b: Merge part files to bronze layer
   python 1_apcd_input_data/1b_merge_part_files_to_bronze.py
   
   # Step 2: Create cohorts (runs for all cohorts/age bands)
   python 2_create_cohort/0_create_cohort.py
   ```

6. **Run pipeline workflows** (idempotent - will skip completed steps):

   The workflow uses cohort-specific scripts that run the complete analysis pipeline. The pipeline uses **aggregated feature importances** (from Step 3) combined with **PGx features** (from Step 5c) - no feature encoding step is used. Open multiple terminal sessions in Jupyter Lab to run different cohorts/age bands in parallel:

   **Terminal 1 - Run single cohort workflow:**

   ```bash
   cd ~/pgx-analysis
   bash utility_scripts/run_cohort_workflow.sh opioid_ed 13-24
   ```

   **Terminal 2 - Run another cohort in parallel:**

   ```bash
   cd ~/pgx-analysis
   bash utility_scripts/run_cohort_workflow.sh opioid_ed 25-44
   ```

   **Terminal 3 - Run non-opioid cohort:**

   ```bash
   cd ~/pgx-analysis
   bash utility_scripts/run_cohort_workflow.sh non_opioid_ed 65-74
   ```

   **Available cohorts and age bands:**
   - `opioid_ed`: 13-24, 25-44, 45-54, 55-64
   - `non_opioid_ed`: 65-74, 75-84, 85-94

   **Workflow steps** (automatically executed by script):
   - **3**: Feature Importance (Monte Carlo CV) - Generates aggregated feature importances across models
   - **4a**: Model Data Extraction - Creates model_events.parquet with cases + controls
   - **4b**: DTW Protocol Filtering - Filters administrative/scheduling/non-medical codes
   - **5**: PGx Feature Engineering - Adds pharmacogenomics features
   - **6**: Final Model Training - Uses **aggregated feature importances + PGx features** (no encoding step)
   - **7**: FFA Analysis - Uses best XGBoost model JSON
   - **8**: SHAP Analysis - Uses best CatBoost model binary
   - **9**: Combined SHAP + FFA
   - **10**: Risk Dashboard - Includes BupaR, FP-Growth, and DTW visualizations (visuals only, not separate analysis steps)

   **Note**: BupaR analysis (5a), FP-Growth analysis (5b), and DTW analysis (5d) are no longer separate workflow steps. These are now integrated as visualizations in Step 10 (Risk Dashboard).

   The idempotent checkpoint system ensures that:
   - Multiple terminals won't conflict (each checks for existing outputs)
   - Completed steps are automatically skipped
   - Parallel execution maximizes CPU and memory utilization across cohorts

### Elastic IP Management

**Benefits of using Elastic IP:**

- **Static IP address** that persists across instance stop/start cycles
- **Easy access** to Jupyter Lab without looking up new IPs
- **Bookmark-friendly** URL that doesn't change
- **Cost**: Free when associated with a running instance

**Allocate a new Elastic IP** (if you don't have one):

```bash
# Allocate Elastic IP
aws ec2 allocate-address --domain vpc --region us-east-1

# Save the allocation ID for future use
# Output will show: AllocationId and PublicIp
```

**Associate Elastic IP to instance:**

```bash
# Associate existing Elastic IP
aws ec2 associate-address \
  --instance-id i-xxxxx \
  --allocation-id eipalloc-xxxxx \
  --allow-reassociation

# Verify association
aws ec2 describe-addresses --allocation-ids eipalloc-xxxxx
```

**Reassociate Elastic IP after restart:**

When you restart a stopped instance, it may get a new instance ID. Reassociate your Elastic IP:

```bash
# Get new instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].InstanceId' --output text)

# Reassociate Elastic IP
aws ec2 associate-address \
  --instance-id $INSTANCE_ID \
  --allocation-id eipalloc-xxxxx \
  --allow-reassociation
```

### Handling Interruptions

If the spot instance is interrupted:

1. **Instance automatically stops** (due to `InstanceInterruptionBehavior=stop`)
2. **EBS volume persists** with all checkpoints and state
3. **Restart instance**:

   ```bash
   aws ec2 start-instances --instance-ids i-xxxxx
   ```

4. **Reassociate Elastic IP** (if using one):

   ```bash
   # Get the instance ID (may be different after restart)
   aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' --output table
   
   # Reassociate Elastic IP
   aws ec2 associate-address \
     --instance-id i-xxxxx \
     --allocation-id eipalloc-xxxxx \
     --allow-reassociation
   ```

5. **Resume workflow**: Pipeline will detect existing checkpoints and skip completed steps

### Monitoring

- **Check instance status**:

  ```bash
  aws ec2 describe-instances --instance-ids i-xxxxx --query 'Reservations[*].Instances[*].[State.Name,SpotInstanceRequestId]' --output table
  ```

- **Check Elastic IP association**:

  ```bash
  # List all Elastic IPs and their associations
  aws ec2 describe-addresses --query 'Addresses[*].[AllocationId,PublicIp,InstanceId,AssociationId]' --output table
  
  # Check specific Elastic IP
  aws ec2 describe-addresses --allocation-ids eipalloc-xxxxx
  ```

- **Check if Jupyter Lab is running** (SSH into instance first):

  ```bash
  # Check if Jupyter Lab process is running
  ps aux | grep jupyter
  # Expected output shows: jupyter-lab process running from ~/jupyter-env/bin/

  # Check if Jupyter port (typically 8888) is listening
  netstat -tlnp | grep 8888
  # Or using ss command:
  ss -tlnp | grep 8888

  # Check if Jupyter is accessible via HTTP
  curl -I http://localhost:8888

  # Check Jupyter Lab config location
  ls -la ~/.jupyter/jupyter_lab_config.py
  ```

- **View spot pricing history**:

  ```bash
  aws ec2 describe-spot-price-history \
    --instance-types x2iedn.8xlarge \
    --availability-zone us-east-1f \
    --max-items 1
  ```

## Cost Optimization

### Why This Approach Saves Money

1. **Spot pricing**: Up to 90% cheaper than on-demand
2. **Persistent instances**: No need to recreate after interruption
3. **Idempotency**: Don't waste compute re-running completed steps
4. **Subnet selection**: Choose cheapest availability zone
5. **Pre-configured AMI**: Faster startup, less setup time

### Estimated Savings

- **On-demand**: ~$6.00/hour for x2iedn.8xlarge
- **Spot (us-east-1f)**: ~$0.60-1.20/hour (80-90% savings)
- **Monthly savings**: ~$3,500-4,200 for 24/7 usage

## Security

- **IAM Instance Profile**: `EC2_Spot` with appropriate permissions
- **Security Group**: `sg-0eb0da772c42415dd` configured for required access
- **SSH Key**: `mushin_pgx` for secure access
- **EBS Encryption**: Enabled with AWS KMS

## Troubleshooting

### Instance Not Starting

- Check spot capacity in the selected availability zone
- Try fallback subnet (us-east-1a)
- Check IAM permissions for EC2_Spot profile

### Workflow Not Resuming

- Verify checkpoint files exist on EBS volume
- Check file permissions on `/project` directory
- Review logs for checkpoint validation errors

### Jupyter Lab Not Running

If Jupyter Lab is not accessible:

1. **SSH into the instance** and check if Jupyter Lab process is running:

   ```bash
   ps aux | grep jupyter
   # Should show: jupyter-lab process from ~/jupyter-env/bin/
   ```

2. **Check if port 8888 is listening**:

   ```bash
   netstat -tlnp | grep 8888
   # Or:
   ss -tlnp | grep 8888
   ```

3. **Start Jupyter Lab if not running**:

   ```bash
   # Activate the virtual environment and start Jupyter Lab
   source ~/jupyter-env/bin/activate
   jupyter-lab --config=~/.jupyter/jupyter_lab_config.py
   
   # Or run in background:
   nohup ~/jupyter-env/bin/jupyter-lab --config=~/.jupyter/jupyter_lab_config.py > /tmp/jupyter.log 2>&1 &
   ```

4. **Check Jupyter Lab logs** for errors:

   ```bash
   # Check the process output/logs
   tail -f /tmp/jupyter.log
   
   # Or check Jupyter's runtime directory
   ls -la ~/.jupyter/
   cat ~/.jupyter/jupyter_lab_config.py
   ```

5. **Verify security group** allows inbound traffic on port 8888

6. **Check the Jupyter Lab config** for correct settings:

   ```bash
   cat ~/.jupyter/jupyter_lab_config.py
   # Should have ServerApp.ip = '0.0.0.0' to allow external access
   ```

### High Spot Interruption Rate

- Monitor spot pricing trends
- Consider using multiple availability zones
- Use capacity-optimized allocation strategy for fleet launches

## Git Repository Synchronization

To keep the repository synchronized between your local Windows machine and the EC2 instance:

### Windows → EC2 (Push from Windows, Pull on EC2)

**On Windows:**

```bash
# Check status and stage changes
git status
git add .

# Commit changes
git commit -m "Your commit message"

# Push to GitHub
git push origin main
# Or if using master branch:
# git push origin master
```

**On EC2:**

```bash
# SSH into EC2
ssh -i /path/to/your/key.pem pgx3874@<your-ec2-ip-or-hostname>

# Navigate to project directory
cd ~/pgx-analysis

# Pull latest changes
git pull origin main
# Or if using master branch:
# git pull origin master
```

### EC2 → Windows (Push from EC2, Pull on Windows)

**On EC2:**

```bash
cd ~/pgx-analysis

# Check status
git status

# Stage, commit, and push
git add .
git commit -m "EC2 changes: your commit message"
git push origin main
```

**On Windows:**

```bash
# Pull latest changes
git pull origin main
```

### Handling Out-of-Sync Situations

#### Scenario 1: EC2 has uncommitted local changes and you want to pull latest from remote

```bash
# Check what's changed
git status

# Option 1: Commit your changes first (recommended if changes are important)
git add .
git commit -m "EC2 local changes: describe what you did"
git pull origin main
# If there are conflicts, resolve them, then:
git add .
git commit -m "Merge remote changes"
git push origin main

# Option 2: Stash changes temporarily (if you want to discard or review later)
git stash
git pull origin main
git stash pop  # Reapply stashed changes if you want to keep them
# If stash pop causes conflicts, resolve them manually

# Option 3: Handle untracked files that conflict
# If you see "untracked working tree files would be overwritten by merge":
# Remove untracked files that conflict (they'll be recreated from remote)
git clean -fd  # Remove untracked files and directories
# OR move them to backup:
mkdir -p ~/backup_untracked
mv <conflicting_file> ~/backup_untracked/
# Then stash and pull:
git stash
git pull origin main
```

#### Scenario 2: EC2 is behind (no local changes, just needs to pull)

```bash
# Simply pull the latest
git pull origin main
```

#### Scenario 3: EC2 has committed changes that conflict with remote

```bash
# Pull will trigger a merge
git pull origin main

# If conflicts occur:
# 1. View conflicts
git status

# 2. Resolve conflicts in your editor
# 3. Stage resolved files
git add .

# 4. Complete the merge
git commit -m "Merge remote changes with EC2 local commits"

# 5. Push the merged result
git push origin main
```

#### Scenario 4: EC2 is ahead (has commits not on remote) and you want to push

```bash
# Check if you're ahead
git status
# Should show: "Your branch is ahead of 'origin/main' by X commits"

# Push your commits
git push origin main
```

### Checking Branch Status

```bash
# See current branch
git branch
# Current branch will have an asterisk (*)

# Switch branches if needed
git checkout main
# or
git checkout master
```

### Best Practices

1. **Always pull before starting work** to ensure you have the latest changes
2. **Commit frequently** with descriptive messages
3. **Push after completing logical units of work**
4. **Check `git status`** before pulling to see if you have uncommitted changes
5. **Use the same branch** on both Windows and EC2 (typically `main` or `master`)

## Related Documentation

- `ec2_start_spot.qmd` - Detailed spot instance launch procedures
- `ec2_setup_spot.qmd` - Initial EC2 setup and configuration
- `docs/CrossStep_Development/README_ec2_vs_local_dev_environment.md` - Environment comparison

## Summary

This EC2 workflow execution solution provides:

✅ **Cost-effective** spot instance usage with subnet-based pricing optimization  
✅ **Reliable** persistent instances that survive interruptions  
✅ **Resilient** idempotent checkpoints for safe resume  
✅ **Efficient** pre-configured AMI with libraries and datasets ready  
✅ **Parallelized** execution via Jupyter notebook terminal sessions for maximum resource utilization  
✅ **Production-ready** architecture for large-scale pharmacogenomics analysis  

The combination of persistent spot instances, idempotent checkpoints, and strategic subnet selection makes this our final, production-ready solution for workflow execution.
