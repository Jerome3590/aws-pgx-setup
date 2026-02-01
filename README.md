# AWS Services Used in PGx Analysis Project

### AWS S3
**Primary data storage and data lake**
- Bucket: `pgxdatalake`
- Stores all pipeline outputs: bronze/silver/gold data layers
- Hosts dashboard static files and model artifacts
- Used extensively throughout the project for data persistence

### AWS Lambda
**Serverless API for risk dashboard**
- Container-based deployment (ECR) supporting up to 10GB images
- Provides REST API endpoints:
  - `/metadata` - Returns valid codes for cohorts/age_bands
  - `/risk` - Calculates risk scores using ensemble models
  - `/risk/comparison` - Compares risk scores for scenarios
  - `/pgx/card` - Generates PGx patient cards
- Models bundled in container for fast inference

### AWS ECR (Elastic Container Registry)
**Container image storage for Lambda**
- Stores Lambda container images with bundled models
- Supports up to 10GB container images
- Enables fast model loading without S3 latency

### AWS SES (Simple Email Service)
**Pipeline status notifications**
- Sends email notifications for pipeline completion/errors
- Used by `py_helpers/aws_utils.py` for status updates

### AWS EC2
**Development and compute environment**
- Used for running analysis pipelines
- Instance metadata service used for environment detection
- Spot instances for cost-effective compute

### AWS IAM (Identity and Access Management)
**Access control and permissions management**
- Lambda execution roles for API functions
- EC2 instance roles for S3 access and Elastic IP management
- EMR service roles for cluster operations
- User management and access key creation (`iam/create_iam_user.py`)
- Cross-account access policies for S3 buckets
- Policy simulation and permission testing

### AWS QuickSight
**Business intelligence dashboards and data visualization**
- Interactive dashboards for data analysis and reporting
- Data formatting utilities in `py_helpers/visualization_utils.py` for QuickSight compatibility
- Dashboard creation and management (`quicksight/quicksight_ops.qmd`)
- Analysis and visualization of pipeline outputs and results
- S3 data source integration for real-time dashboards

### AWS CloudFront (Optional)
**CDN for dashboard hosting**
- Optional deployment for dashboard static website
- Provides HTTPS, custom domain, and caching

### AWS Route 53
**DNS management and domain hosting**
- Custom domain DNS management and hosted zones
- Alias records for S3 website endpoints and CloudFront distributions
- SSL certificate validation via DNS records (for ACM)
- Domain routing and hosting configuration (`route53/route53.qmd`)
- Integration with CloudFront for custom domain HTTPS access

### AWS CloudTrail
**API activity logging and audit trail**
- Query API events as backup to application logging
- Lookup events by event source (e.g., KMS usage analysis)
- Analyze service usage patterns and access patterns
- Logs stored in S3 for long-term retention
- Used for security auditing and compliance

### AWS CloudWatch Logs
**Application logging and monitoring**
- Application log collection and retention
- Log group management and retention policies
- Used alongside CloudTrail for comprehensive logging coverage
- KMS usage analysis and service activity tracking

### AWS Glue/AWS Athena (Limited)
**Data catalog and querying**
- Limited use - DuckDB is primary query engine
- May be used for data cataloging in S3

### AWS Lake Formation
**Data lake permissions (effectively “turned off” for this project)**
- We use IAM-only access to the Glue Data Catalog; Lake Formation fine-grained permissions are not used.
- See **`lake_formation/README.md`** for lessons learned, best practices, and how we set IAM-only defaults and grant the Glue crawler role on existing databases (e.g. `pgxdatalake`).

## Local Services

### DuckDB
**Primary analytical database**
- Used extensively for data processing and analysis
- S3 integration for direct data access
- Replaces need for traditional data warehouse

### Apache Spark (via EMR Studio)
**Distributed processing** (if using EMR)
- Available through EMR Studio for large-scale processing
- Not primary compute engine in this project

