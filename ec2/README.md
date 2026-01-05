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
  - Jupyter Notebook pre-installed and configured

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

2. **Access Jupyter Notebook**:

   - Navigate to `http://<instance-ip>:8888` (or configured port)
   - Log in with your credentials
   - Open a new terminal session from the Jupyter interface

3. **Navigate to project directory**:

   ```bash
   cd /project/pgx-analysis
   ```

4. **Run pipeline steps in parallel** (idempotent - will skip completed steps):

   Open multiple terminal sessions in Jupyter and run different pipeline steps concurrently:

   **Terminal 1:**

   ```bash
   python 1_apcd_input_data/0_txt_to_parquet.py
   ```

   **Terminal 2:**

   ```bash
   python 1_apcd_input_data/1b_merge_part_files_to_bronze.py
   ```

   **Terminal 3:**

   ```bash
   python 2_create_cohort/0_create_cohort.py
   ```

   The idempotent checkpoint system ensures that:
   - Multiple terminals won't conflict (each checks for existing outputs)
   - Completed steps are automatically skipped
   - Parallel execution maximizes CPU and memory utilization

### Handling Interruptions

If the spot instance is interrupted:

1. **Instance automatically stops** (due to `InstanceInterruptionBehavior=stop`)
2. **EBS volume persists** with all checkpoints and state
3. **Restart instance**:

   ```bash
   aws ec2 start-instances --instance-ids i-xxxxx
   ```

4. **Resume workflow**: Pipeline will detect existing checkpoints and skip completed steps

### Monitoring

- **Check instance status**:

  ```bash
  aws ec2 describe-instances --instance-ids i-xxxxx --query 'Reservations[*].Instances[*].[State.Name,SpotInstanceRequestId]' --output table
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

### High Spot Interruption Rate

- Monitor spot pricing trends
- Consider using multiple availability zones
- Use capacity-optimized allocation strategy for fleet launches

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
